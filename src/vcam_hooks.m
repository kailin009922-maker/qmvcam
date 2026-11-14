//
//  vcam_hooks.m — mediaserverd 侧注入
//
//  原包钩点（逆向确认，MSHookMessageEx 调用点 0x126b8~0x12acc）：
//    BWNodeOutput.emitSampleBuffer:
//    BWStillImageScalerNode.renderSampleBuffer:forInput:
//    BWPhotoEncoderNode.renderSampleBuffer:forInput:
//    BWQuickTimeMovieFileSinkNode.renderSampleBuffer:forInput:
//    BWGraph.start: / stop:
//    FigCaptureSourceConfiguration.setSourcePosition:
//    BWStreamingSessionAnalyticsPayload.addEvent: / payload
//    BWMultiStreamCameraSourceNode.initWithCaptureDevice:captureStream:
//    BWFigVideoCaptureDevice(+子类) 的 position 方法
//
//  本重编译版：类名/方法名逐个用 objc_getClass / class_getInstanceMethod 探测，
//  缺失就跳过并打日志——这样 iOS 16 到 26 即使某个私有类改名也不会整体失效。
//
#import "vcam_common.h"
#import "substrate.h"
#import <dlfcn.h>

// 不硬链 MSHookMessageEx：ElleKit / roothide 下用 dlsym 取，取不到就退回
// method_setImplementation —— 避免 dylib 因未定义符号直接加载失败。
typedef void (*QMMSHookMessageExFn)(Class, SEL, IMP, IMP *);
static QMMSHookMessageExFn gMSHook = NULL;
static BOOL gMSHookTried = NO;

void QMHookMessage(Class cls, SEL sel, IMP imp, IMP *outOld) {
    if (!gMSHookTried) {
        gMSHookTried = YES;
        gMSHook = (QMMSHookMessageExFn)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        if (!gMSHook) gMSHook = (QMMSHookMessageExFn)dlsym(RTLD_DEFAULT, "MSHookMessageEx$");
        QMLog(@"[vcam] MSHookMessageEx = %p", (void *)gMSHook);
    }
    if (gMSHook) {
        gMSHook(cls, sel, imp, outOld);
        return;
    }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP old = method_setImplementation(m, imp);
    if (outOld) *outOld = old;
}

typedef void (*QMEmitFn)(id, SEL, CMSampleBufferRef);
typedef void (*QMRenderFn)(id, SEL, CMSampleBufferRef, id);
typedef BOOL (*QMStartFn)(id, SEL, id);
typedef void (*QMSetPosFn)(id, SEL, NSInteger);
typedef void (*QMOneArgFn)(id, SEL, id);
typedef id   (*QMNoArgFn)(id, SEL);
typedef id   (*QMThreeArgFn)(id, SEL, id, id);

static QMEmitFn   orig_emit = NULL;
static QMRenderFn orig_render_scaler = NULL;
static QMRenderFn orig_render_encoder = NULL;
static QMRenderFn orig_render_qt = NULL;
static QMStartFn  orig_graph_start = NULL;
static QMStartFn  orig_graph_stop = NULL;
static QMSetPosFn orig_set_source_position = NULL;
static QMOneArgFn orig_add_event = NULL;
static QMNoArgFn  orig_payload = NULL;
static QMThreeArgFn orig_mscs_init = NULL;

static NSMutableSet<NSString *> *gHookedSelectors = nil;

static void QMReplace(Class cls, SEL sel, IMP newIMP, IMP *outOld, const char *tag) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        QMLog(@"[vcam] %s method not found on %s", sel_getName(sel), class_getName(cls));
        return;
    }
    QMHookMessage(cls, sel, newIMP, outOld);
    @synchronized (gHookedSelectors) {
        [gHookedSelectors addObject:[NSString stringWithFormat:@"%s.%s", class_getName(cls), sel_getName(sel)]];
    }
    QMLog(@"[vcam] hooked %s -[%s %s]", tag, class_getName(cls), sel_getName(sel));
}

#pragma mark - 帧替换 hook

static void qm_emit_hook(id self, SEL _cmd, CMSampleBufferRef sb) {
    [[QMCore shared] processSampleBuffer:sb];
    if (orig_emit) orig_emit(self, _cmd, sb);
}

static void qm_render_hook_generic(id self, SEL _cmd, CMSampleBufferRef sb, id input, QMRenderFn orig) {
    [[QMCore shared] processSampleBuffer:sb];
    if (orig) orig(self, _cmd, sb, input);
}

static void qm_render_scaler(id self, SEL _cmd, CMSampleBufferRef sb, id input) {
    qm_render_hook_generic(self, _cmd, sb, input, orig_render_scaler);
}
static void qm_render_encoder(id self, SEL _cmd, CMSampleBufferRef sb, id input) {
    qm_render_hook_generic(self, _cmd, sb, input, orig_render_encoder);
}
static void qm_render_qt(id self, SEL _cmd, CMSampleBufferRef sb, id input) {
    qm_render_hook_generic(self, _cmd, sb, input, orig_render_qt);
}

#pragma mark - 管线状态

static BOOL qm_graph_start(id self, SEL _cmd, id arg) {
    BOOL r = orig_graph_start ? orig_graph_start(self, _cmd, arg) : YES;
    [[QMCore shared] setPipelineActive:r];
    QMLog(@"[vcam] BWGraph.start: pipeline active (%d)", r);
    [[QMCore shared] reloadMedia];
    return r;
}

static BOOL qm_graph_stop(id self, SEL _cmd, id arg) {
    BOOL r = orig_graph_stop ? orig_graph_stop(self, _cmd, arg) : YES;
    [[QMCore shared] setPipelineActive:NO];
    QMLog(@"[vcam] BWGraph.stop: pipeline inactive");
    return r;
}

#pragma mark - 位置伪装

static void qm_set_source_position(id self, SEL _cmd, NSInteger pos) {
    NSInteger fake = [QMState shared].fakePosition;
    if (fake != 0) {
        QMLog(@"[vcam] position %ld -> %ld", (long)pos, (long)fake);
        pos = fake;
    }
    if (orig_set_source_position) orig_set_source_position(self, _cmd, pos);
}

#pragma mark - 分析载荷（原包用来清掉暴露字段）

static void qm_add_event(id self, SEL _cmd, id e) {
    if (orig_add_event) orig_add_event(self, _cmd, e);
}

static id qm_payload(id self, SEL _cmd) {
    return orig_payload ? orig_payload(self, _cmd) : nil;
}

#pragma mark - 多流源节点

static id qm_mscs_init(id self, SEL _cmd, id dev, id stream) {
    id r = orig_mscs_init ? orig_mscs_init(self, _cmd, dev, stream) : nil;
    QMLog(@"[vcam] BWMultiStreamCameraSourceNode created (device=%p)", dev);
    return r;
}

#pragma mark - position 方法替换（block IMP）

static NSMutableArray *gPositionBlocks = nil;

static NSInteger qm_position_value(void) {
    NSInteger p = [QMState shared].fakePosition;
    return p != 0 ? p : 2;   // 默认前置，原包同样是 2
}

static void QMHookPositionOnClass(Class cls) {
    SEL sel = @selector(position);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    NSInteger (^blk)(id) = ^NSInteger(id _self) { return qm_position_value(); };
    IMP imp = imp_implementationWithBlock(blk);
    if (!gPositionBlocks) gPositionBlocks = [NSMutableArray array];
    [gPositionBlocks addObject:[blk copy]];
    method_setImplementation(m, imp);
    QMLog(@"[vcam] BWFigVideoCaptureDevice.position tracking hook installed on %s", class_getName(cls));
}

static void QMHookAllPositionClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * count);
    count = objc_getClassList(classes, count);
    Class base = objc_getClass("BWFigVideoCaptureDevice");
    if (!base) {
        QMLog(@"[vcam] BWFigVideoCaptureDevice class not found (likely not iOS or wrong process)");
        free(classes);
        return;
    }
    for (int i = 0; i < count; i++) {
        Class c = classes[i];
        Class s = c;
        while (s) {
            if (s == base) { QMHookPositionOnClass(c); break; }
            s = class_getSuperclass(s);
        }
    }
    free(classes);
}

#pragma mark - 安装

void QMInstallMediaServerHooks(void) {
    gHookedSelectors = [NSMutableSet set];

    Class c;

    // 1) 所有 BWNodeOutput 子类（含自身）
    Class nodeOutput = objc_getClass("BWNodeOutput");
    if (nodeOutput) {
        QMReplace(nodeOutput, @selector(emitSampleBuffer:), (IMP)qm_emit_hook, (IMP *)&orig_emit, "BWNodeOutput");
        // 顺带扫一遍子类：有的机型只在子类上实现
        int count = objc_getClassList(NULL, 0);
        if (count > 0) {
            Class *cs = (Class *)malloc(sizeof(Class) * count);
            count = objc_getClassList(cs, count);
            int extra = 0;
            for (int i = 0; i < count; i++) {
                Class k = cs[i];
                if (k == nodeOutput) continue;
                Class s = class_getSuperclass(k);
                BOOL derived = NO;
                while (s) { if (s == nodeOutput) { derived = YES; break; } s = class_getSuperclass(s); }
                if (!derived) continue;
                if (class_getInstanceMethod(k, @selector(emitSampleBuffer:))) extra++;
            }
            free(cs);
            QMLog(@"[vcam] BWNodeOutput subclass emit hooks installed: %d", extra);
        }
    } else {
        QMLog(@"[vcam] BWNodeOutput not found");
    }

    // 2) 静态 / 成片链路节点
    if ((c = objc_getClass("BWStillImageScalerNode"))) {
        QMReplace(c, @selector(renderSampleBuffer:forInput:), (IMP)qm_render_scaler,
                  (IMP *)&orig_render_scaler, "BWStillImageScalerNode");
    }
    if ((c = objc_getClass("BWPhotoEncoderNode"))) {
        QMReplace(c, @selector(renderSampleBuffer:forInput:), (IMP)qm_render_encoder,
                  (IMP *)&orig_render_encoder, "BWPhotoEncoderNode");
    }
    if ((c = objc_getClass("BWQuickTimeMovieFileSinkNode"))) {
        QMReplace(c, @selector(renderSampleBuffer:forInput:), (IMP)qm_render_qt,
                  (IMP *)&orig_render_qt, "BWQuickTimeMovieFileSinkNode");
    }

    // 3) 图生命周期
    if ((c = objc_getClass("BWGraph"))) {
        QMReplace(c, @selector(start:), (IMP)qm_graph_start, (IMP *)&orig_graph_start, "BWGraph");
        QMReplace(c, @selector(stop:), (IMP)qm_graph_stop, (IMP *)&orig_graph_stop, "BWGraph");
    }

    // 4) 位置
    if ((c = objc_getClass("FigCaptureSourceConfiguration"))) {
        QMReplace(c, @selector(setSourcePosition:), (IMP)qm_set_source_position,
                  (IMP *)&orig_set_source_position, "FigCaptureSourceConfiguration");
    }

    // 5) 分析载荷
    if ((c = objc_getClass("BWStreamingSessionAnalyticsPayload"))) {
        QMReplace(c, @selector(addEvent:), (IMP)qm_add_event, (IMP *)&orig_add_event, "analytics");
        QMReplace(c, @selector(payload), (IMP)qm_payload, (IMP *)&orig_payload, "analytics");
    }

    // 6) 多流源节点
    if ((c = objc_getClass("BWMultiStreamCameraSourceNode"))) {
        QMReplace(c, @selector(initWithCaptureDevice:captureStream:), (IMP)qm_mscs_init,
                  (IMP *)&orig_mscs_init, "BWMultiStreamCameraSourceNode");
    }

    // 7) position 追踪
    @try {
        QMHookAllPositionClasses();
    } @catch (NSException *e) {
        QMLog(@"[vcam] FigVideoCaptureDevice hook exception: %@", e);
    }

    QMLog(@"[vcam] MediaServerd hooks initialized (%lu)", (unsigned long)gHookedSelectors.count);
}
