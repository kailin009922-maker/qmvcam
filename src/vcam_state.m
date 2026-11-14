//
//  vcam_state.m — 根路径探测 + plist 状态（跨进程共享）
//
#import "vcam_common.h"
#include <sys/stat.h>
#include <unistd.h>

static NSString *gRoot = nil;
static NSLock *gRootLock = nil;

NSString *QMRoot(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gRootLock = [NSLock new];
        // rootless：/var/jb 存在且 /var/jb/usr/lib 存在
        struct stat st;
        if (stat("/var/jb/usr/lib", &st) == 0 && S_ISDIR(st.st_mode)) {
            gRoot = @"/var/jb";
        } else {
            gRoot = @"";
        }
    });
    return gRoot;
}

NSString *QMPath(NSString *absolute) {
    if (absolute.length == 0) return absolute;
    if (![absolute hasPrefix:@"/"]) return absolute;
    // /var/mobile 是用户数据区，不属于 jbroot，绝不能加前缀
    if ([absolute hasPrefix:@"/var/mobile"]) return absolute;
    if (QMRoot().length == 0) return absolute;
    if ([absolute hasPrefix:QMRoot()]) return absolute;
    return [QMRoot() stringByAppendingString:absolute];
}

// =====================================================================
#pragma mark - 设备信标

// 每个被注入的进程都往 /var/mobile/Media/DCIM/.qm_beacon.txt 追加一行，
// PC 端用 AFC 直接取，不需要 SSH。
void QMBeacon(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ [%@:%d] %@\n",
                      [NSDate date], [[NSProcessInfo processInfo] processName],
                      getpid(), msg];
    NSString *path = @"/var/mobile/Media/DCIM/.qm_beacon.txt";
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:[line dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
        chmod(path.fileSystemRepresentation, 0666);
        return;
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) return;
    @try {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (NSException *e) { }
}

int QMBootGuard(NSString *proc) {
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Media/DCIM/.qm_boot_%@", proc];
    double now = [[NSDate date] timeIntervalSince1970];
    double last = 0; int count = 0;
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (s.length) {
        NSArray *p = [s componentsSeparatedByString:@" "];
        if (p.count == 2) { count = [p[0] intValue]; last = [p[1] doubleValue]; }
    }
    if (now - last > 120.0) count = 0;
    count += 1;
    [[NSString stringWithFormat:@"%d %.0f", count, now] writeToFile:path atomically:YES
                                                          encoding:NSUTF8StringEncoding error:nil];
    return count;
}

// =====================================================================
#pragma mark - QMState

@implementation QMState {
    NSMutableDictionary *_dict;
    dispatch_queue_t _q;
    BOOL _savePending;
}

+ (instancetype)shared {
    static QMState *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [QMState new]; [s performSelector:@selector(_setup)]; });
    return s;
}

- (void)_setup {
    _dict = [NSMutableDictionary dictionary];
    _q = dispatch_queue_create("com.vcam.state", DISPATCH_QUEUE_SERIAL);
    [self load];
    // 默认值
    if (!_dict[QMK_ZOOM])       _dict[QMK_ZOOM] = @1.0;
    if (!_dict[QMK_EDGE])       _dict[QMK_EDGE] = @1;   // 默认裁剪填充，避免画面缩在框里
    if (!_dict[QMK_BRIGHT])     _dict[QMK_BRIGHT] = @0.0;
    if (!_dict[QMK_CONTRAST])   _dict[QMK_CONTRAST] = @1.0;
    if (!_dict[QMK_SATURATION]) _dict[QMK_SATURATION] = @1.0;
    if (!_dict[QMK_GAMMA])      _dict[QMK_GAMMA] = @1.0;
    if (!_dict[QMK_MEDIA_KIND]) _dict[QMK_MEDIA_KIND] = @"video";
    if (!_dict[QMK_POSITION])   _dict[QMK_POSITION] = @0;
}

- (NSString *)statePath {
    NSString *p = QMPath(QMV_FILE_STATE);
    return p;
}

- (void)load {
    NSString *p = QMPath(QMV_FILE_STATE);
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
    if (!d) { // 兼容旧路径
        d = [NSDictionary dictionaryWithContentsOfFile:QMV_FILE_STATE];
    }
    if (d) {
        @synchronized (self) { [_dict addEntriesFromDictionary:d]; }
    }
}

- (void)save {
    NSDictionary *snapshot = [_dict copy];
    NSString *p = QMPath(QMV_FILE_STATE);
    NSString *dir = [p stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    // 原子写：先写 .tmp 再改名（与原包行为一致）
    NSString *tmp = [p stringByAppendingString:@".tmp"];
    if ([snapshot writeToFile:tmp atomically:YES]) {
        [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
        if (rename([tmp fileSystemRepresentation], [p fileSystemRepresentation]) != 0) {
            [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:p error:nil];
        }
        chmod([p fileSystemRepresentation], 0644);
    } else {
        QMLog(@"[vcam] Failed to save state: %@", p);
    }
}

- (void)saveSoon {
    @synchronized (self) {
        if (_savePending) return;
        _savePending = YES;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), _q, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        @synchronized (self) { self->_savePending = NO; }
        [self save];
    });
}

- (NSDictionary *)dictionary { @synchronized (self) { return [_dict copy]; } }

#define QM_ACC(T, name, key, defv) \
- (T)name { @synchronized (self) { id v = _dict[key]; return v ? (T)[v doubleValue] : (T)(defv); } } \
- (void)set##name:(T)v { @synchronized (self) { _dict[key] = @(v); } [self saveSoon]; }

- (BOOL)live { @synchronized (self) { return [_dict[QMK_LIVE] boolValue]; } }
- (void)setLive:(BOOL)v {
    @synchronized (self) { _dict[QMK_LIVE] = @(v); }
    [self saveSoon];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(QMV_NOTIFY_LIVE), NULL, NULL, true);
}
- (BOOL)paused { @synchronized (self) { return [_dict[QMK_PAUSED] boolValue]; } }
- (void)setPaused:(BOOL)v { @synchronized (self) { _dict[QMK_PAUSED] = @(v); } [self saveSoon]; }
- (BOOL)mirror { @synchronized (self) { return [_dict[QMK_MIRROR] boolValue]; } }
- (void)setMirror:(BOOL)v { @synchronized (self) { _dict[QMK_MIRROR] = @(v); } [self saveSoon]; }
- (BOOL)edgeClamp { @synchronized (self) { return [_dict[QMK_EDGE] boolValue]; } }
- (void)setEdgeClamp:(BOOL)v { @synchronized (self) { _dict[QMK_EDGE] = @(v); } [self saveSoon]; }
- (BOOL)ballEnabled {
    @synchronized (self) { id v = _dict[QMK_BALL]; return v ? [v boolValue] : YES; }
}
- (void)setBallEnabled:(BOOL)v { @synchronized (self) { _dict[QMK_BALL] = @(v); } [self saveSoon]; }

- (double)panX { @synchronized (self) { return [_dict[QMK_PAN_X] doubleValue]; } }
- (void)setPanX:(double)v { @synchronized (self) { _dict[QMK_PAN_X] = @(v); } [self saveSoon]; }
- (double)panY { @synchronized (self) { return [_dict[QMK_PAN_Y] doubleValue]; } }
- (void)setPanY:(double)v { @synchronized (self) { _dict[QMK_PAN_Y] = @(v); } [self saveSoon]; }
- (double)zoom { @synchronized (self) { id v = _dict[QMK_ZOOM]; return v ? [v doubleValue] : 1.0; } }
- (void)setZoom:(double)v { @synchronized (self) { _dict[QMK_ZOOM] = @(v); } [self saveSoon]; }

- (double)brightness { @synchronized (self) { return [_dict[QMK_BRIGHT] doubleValue]; } }
- (void)setBrightness:(double)v { @synchronized (self) { _dict[QMK_BRIGHT] = @(v); } [self saveSoon]; }
- (double)contrast { @synchronized (self) { id x = _dict[QMK_CONTRAST]; return x ? [x doubleValue] : 1.0; } }
- (void)setContrast:(double)v { @synchronized (self) { _dict[QMK_CONTRAST] = @(v); } [self saveSoon]; }
- (double)saturation { @synchronized (self) { id x = _dict[QMK_SATURATION]; return x ? [x doubleValue] : 1.0; } }
- (void)setSaturation:(double)v { @synchronized (self) { _dict[QMK_SATURATION] = @(v); } [self saveSoon]; }
- (double)gamma { @synchronized (self) { id x = _dict[QMK_GAMMA]; return x ? [x doubleValue] : 1.0; } }
- (void)setGamma:(double)v { @synchronized (self) { _dict[QMK_GAMMA] = @(v); } [self saveSoon]; }

- (NSInteger)fakePosition { @synchronized (self) { return [_dict[QMK_POSITION] integerValue]; } }
- (void)setFakePosition:(NSInteger)v { @synchronized (self) { _dict[QMK_POSITION] = @(v); } [self saveSoon]; }
- (NSInteger)rotation { @synchronized (self) { return [_dict[QMK_ROTATION] integerValue]; } }
- (void)setRotation:(NSInteger)v { @synchronized (self) { _dict[QMK_ROTATION] = @(v); } [self saveSoon]; }

- (NSString *)mediaKind { @synchronized (self) { return _dict[QMK_MEDIA_KIND] ?: @"video"; } }
- (void)setMediaKind:(NSString *)v { @synchronized (self) { _dict[QMK_MEDIA_KIND] = [v copy] ?: @"video"; } [self saveSoon]; }
- (NSInteger)slotIndex { @synchronized (self) { return [_dict[QMK_SLOT_INDEX] integerValue]; } }
- (void)setSlotIndex:(NSInteger)v { @synchronized (self) { _dict[QMK_SLOT_INDEX] = @(v); } [self saveSoon]; }
- (NSString *)activePath { @synchronized (self) { return _dict[QMK_ACTIVE_PATH]; } }
- (void)setActivePath:(NSString *)v { @synchronized (self) { if (v) _dict[QMK_ACTIVE_PATH] = [v copy]; else [_dict removeObjectForKey:QMK_ACTIVE_PATH]; } [self saveSoon]; }

@end

// =====================================================================
#pragma mark - QMLightState

@implementation QMLightState {
    NSMutableDictionary *_d;
}

+ (instancetype)shared {
    static QMLightState *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [QMLightState new]; [s load]; });
    return s;
}

- (void)load {
    _d = [NSMutableDictionary dictionary];
    NSDictionary *x = [NSDictionary dictionaryWithContentsOfFile:QMPath(QMV_FILE_LIGHT)];
    if (!x) x = [NSDictionary dictionaryWithContentsOfFile:QMV_FILE_LIGHT];
    if (x) [_d addEntriesFromDictionary:x];
    if (!_d[QMK_LIGHT_INTENSITY]) _d[QMK_LIGHT_INTENSITY] = @0.55;
    if (!_d[QMK_LIGHT_WSCALE])    _d[QMK_LIGHT_WSCALE] = @1.0;
    if (!_d[QMK_LIGHT_HSCALE])    _d[QMK_LIGHT_HSCALE] = @1.0;
    if (!_d[QMK_LIGHT_FEATHER])   _d[QMK_LIGHT_FEATHER] = @0.35;
    if (!_d[QMK_LIGHT_R])         _d[QMK_LIGHT_R] = @1.0;
    if (!_d[QMK_LIGHT_G])         _d[QMK_LIGHT_G] = @1.0;
    if (!_d[QMK_LIGHT_B])         _d[QMK_LIGHT_B] = @1.0;
}

- (void)reloadFromDisk { [self load]; }

- (void)save {
    NSString *p = QMPath(QMV_FILE_LIGHT);
    NSString *tmp = [p stringByAppendingString:@".tmp"];
    if ([_d writeToFile:tmp atomically:YES]) {
        [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
        rename([tmp fileSystemRepresentation], [p fileSystemRepresentation]);
        chmod([p fileSystemRepresentation], 0644);
    }
}

- (BOOL)enabled { return [_d[QMK_LIGHT_ON] boolValue]; }
- (void)setEnabled:(BOOL)v { _d[QMK_LIGHT_ON] = @(v); [self save]; }
- (BOOL)screenPicker { return [_d[QMK_LIGHT_PICKER] boolValue]; }
- (void)setScreenPicker:(BOOL)v { _d[QMK_LIGHT_PICKER] = @(v); [self save]; }
- (BOOL)sceneAdaptive { return [_d[QMK_LIGHT_SCENE] boolValue]; }
- (void)setSceneAdaptive:(BOOL)v { _d[QMK_LIGHT_SCENE] = @(v); [self save]; }
- (double)intensity { return [_d[QMK_LIGHT_INTENSITY] doubleValue]; }
- (void)setIntensity:(double)v { _d[QMK_LIGHT_INTENSITY] = @(v); [self save]; }
- (double)widthScale { return [_d[QMK_LIGHT_WSCALE] doubleValue]; }
- (void)setWidthScale:(double)v { _d[QMK_LIGHT_WSCALE] = @(v); [self save]; }
- (double)heightScale { return [_d[QMK_LIGHT_HSCALE] doubleValue]; }
- (void)setHeightScale:(double)v { _d[QMK_LIGHT_HSCALE] = @(v); [self save]; }
- (double)feather { return [_d[QMK_LIGHT_FEATHER] doubleValue]; }
- (void)setFeather:(double)v { _d[QMK_LIGHT_FEATHER] = @(v); [self save]; }
- (NSInteger)direction { return [_d[QMK_LIGHT_DIR] integerValue]; }
- (void)setDirection:(NSInteger)v { _d[QMK_LIGHT_DIR] = @(v); [self save]; }
- (NSInteger)blendMode { return [_d[QMK_LIGHT_BLEND] integerValue]; }
- (void)setBlendMode:(NSInteger)v { _d[QMK_LIGHT_BLEND] = @(v); [self save]; }
- (double)colorR { return [_d[QMK_LIGHT_R] doubleValue]; }
- (void)setColorR:(double)v { _d[QMK_LIGHT_R] = @(v); [self save]; }
- (double)colorG { return [_d[QMK_LIGHT_G] doubleValue]; }
- (void)setColorG:(double)v { _d[QMK_LIGHT_G] = @(v); [self save]; }
- (double)colorB { return [_d[QMK_LIGHT_B] doubleValue]; }
- (void)setColorB:(double)v { _d[QMK_LIGHT_B] = @(v); [self save]; }

@end
