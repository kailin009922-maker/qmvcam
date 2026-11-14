//
//  main.m — 入口（v3.0.3：崩溃熔断 + 全 try/catch）
//
//  安全策略：
//   · 同一进程 120s 内启动 ≥4 次 = 判定崩溃循环 → 只写信标，不装钩子、不建窗口
//   · 所有安装步骤包在 @try 里，异常只记录不上抛
//   · 非相机进程、非 SpringBoard 一律 no-op
//
#import "vcam_common.h"
#include <string.h>
#include <dlfcn.h>
// ---- 诊断：尝试 dlopen 98d 原 dylib，把 dyld 的真实错误写盘 ----
static void QMTryLoad98(NSString *proc) {
    NSString *p = @"/Library/MobileSubstrate/DynamicLibraries/vcameracrack98.dylib";
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Media/DCIM/.qm_load98"]) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:p]) return;
    NSString *logPath = @"/var/mobile/Media/DCIM/.qm_dl.txt";
    void *h = dlopen(p.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    const char *err = h ? "OK" : dlerror();
    NSString *line = [NSString stringWithFormat:@"[%@] dlopen(%@) => %s\n",
                      proc, p.lastPathComponent, err ? err : "unknown"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:logPath
                                                contents:[line dataUsingEncoding:NSUTF8StringEncoding]
                                              attributes:nil];
    } else {
        @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
        @catch (NSException *e) { }
    }
    QMLog(@"[vcam] dl98 %@ => %@", proc, h ? @"OK" : [NSString stringWithUTF8String:err ?: "?"]);
    QMBeacon(@"dlopen98 => %@", h ? @"OK" : [NSString stringWithUTF8String:err ?: "?"]);
}


// 强引用 substrate 符号：让链接器写入 LC_LOAD_DYLIB @rpath/CydiaSubstrate.framework/CydiaSubstrate
extern void MSHookMessageEx(Class, SEL, IMP, IMP *);
__attribute__((used)) static void *QMV_SUBSTRATE_STUB = (void *)&MSHookMessageEx;

extern void QMInstallMediaServerHooks(void);
extern void QMInstallSpringBoardHooks(void);
extern void QMRegisterNotifications(void);
extern void QMStartStatePolling(void);

static NSString *QMProcessName(void) {
    return [[NSProcessInfo processInfo] processName];
}

static BOOL QMHasClass(const char *name) {
    return objc_getClass(name) != NULL;
}

__attribute__((constructor)) static void QMInit(void) {
    @autoreleasepool {
        @try {
            NSString *proc = QMProcessName();
            QMLog(@"[vcam] Loading in process: %@ (v%s, %@)", proc, QMV_VERSION, @QMV_BUILD_TAG);
            QMBeacon(@"LOAD v%s", QMV_VERSION);

            QMTryLoad98(proc);   // ALWAYS: 只 dlopen 98d 并记录 dyld 结果
            int boots = QMBootGuard(proc);
            QMBeacon(@"boot #%d (120s window)", boots);
            if (boots >= 4) {
                QMLog(@"[vcam] SAFE MODE: crash loop detected (%d boots/120s), skipping all hooks", boots);
                QMBeacon(@"SAFE MODE: skip hooks");
                return;
            }

#if QMV_PROBE_ONLY
            QMBeacon(@"PROBE ONLY build: no hooks, no UI");
#else
            QMRegisterNotifications();
#endif

            BOOL hasNodeOutput = QMHasClass("BWNodeOutput");
            BOOL hasGraph      = QMHasClass("BWGraph");
            BOOL hasFigConfig  = QMHasClass("FigCaptureSourceConfiguration");
            BOOL hasFigDevice  = QMHasClass("BWFigVideoCaptureDevice");
            BOOL hasMSCSN      = QMHasClass("BWMultiStreamCameraSourceNode");
            BOOL cameraHost    = hasNodeOutput || hasGraph || hasFigConfig || hasMSCSN;

            QMBeacon(@"CLASSES nodeOutput=%d graph=%d figConfig=%d figDevice=%d mscsn=%d",
                     hasNodeOutput, hasGraph, hasFigConfig, hasFigDevice, hasMSCSN);

#if !QMV_PROBE_ONLY
            if (cameraHost) {
                @try {
                    QMStartStatePolling();
                    QMInstallMediaServerHooks();
                    QMBeacon(@"CAMERA HOOKS DONE");
                    if ([QMState shared].live) {
                        [[QMCore shared] setActive:YES reason:@"launch"];
                    }
                } @catch (NSException *e) {
                    QMLog(@"[vcam] camera hooks exception: %@", e);
                    QMBeacon(@"CAMERA HOOKS EXCEPTION: %@", e.reason);
                }
            }

            if ([proc isEqualToString:@"SpringBoard"]) {
                QMBeacon(@"SPRINGBOARD branch");
                @try {
                    QMInstallSpringBoardHooks();
                    QMStartStatePolling();
                } @catch (NSException *e) {
                    QMLog(@"[vcam] SpringBoard hooks exception: %@", e);
                    QMBeacon(@"SPRINGBOARD EXCEPTION: %@", e.reason);
                }
            }

            if (!cameraHost && ![proc isEqualToString:@"SpringBoard"]) {
                QMBeacon(@"passive process, no-op");
            }
#endif
            QMLog(@"[vcam] ready in %@", proc);
        } @catch (NSException *e) {
            QMLog(@"[vcam] init exception: %@", e);
            QMBeacon(@"INIT EXCEPTION: %@", e.reason);
        }
    }
}
