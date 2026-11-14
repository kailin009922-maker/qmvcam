//
//  vcam_core.m — 帧替换核心
//
//  关键点（与原包一致）：不新建 CMSampleBuffer，而是把解码出来的画面
//  “原地”写进真实相机输出的 CVPixelBuffer。时间戳 / 元数据 / 序列号全部是
//  真机真实数据，所以下游看不出来源被替换。
//
#import "vcam_common.h"
#import "vcam_source.h"
#import <CoreImage/CoreImage.h>
#import <VideoToolbox/VideoToolbox.h>
#import <ImageIO/ImageIO.h>
#include <sys/stat.h>
#include <math.h>

/// 视频/图片类型判定：kind == "image" 才算图片
BOOL kindIsVideo(NSString *kind);

static const char *kMediaExts[] = { "mp4", "m4v", "mov", "MP4", "MOV", NULL };
static const char *kImageExts[] = { "jpg", "jpeg", "png", "heic", "heif", "JPG", "PNG", NULL };

static BOOL QMExtMatch(NSString *path, const char **exts) {
    NSString *e = path.pathExtension.lowercaseString;
    for (int i = 0; exts[i]; i++) {
        if ([e isEqualToString:[NSString stringWithUTF8String:exts[i]].lowercaseString]) return YES;
    }
    return NO;
}

NSArray<NSString *> *QMListMedia(NSString *dir, BOOL video) {
    NSMutableArray *out = [NSMutableArray array];
    NSError *err = nil;
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:&err];
    for (NSString *name in items) {
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [dir stringByAppendingPathComponent:name];
        if (QMExtMatch(full, video ? kMediaExts : kImageExts)) [out addObject:full];
    }
    [out sortUsingSelector:@selector(compare:)];
    return out;
}

@implementation QMCore {
    QMFrameSource *_src;
    CIContext *_ci;
    NSLock *_lock;
    CVPixelBufferPoolRef _pool;
    size_t _pw, _ph;
    OSType _pfmt;
    BOOL _active;
    unsigned long long _gen;
    BOOL _loggedFormat;
    dispatch_source_t _watch;
    CVPixelBufferRef _prepared;      // 预渲染帧（相机尺寸/格式），每帧复用
    size_t _prepW, _prepH;
    OSType _prepFmt;
    CVPixelBufferRef _lastFrame;     // 最近一帧源图，饥饿时继续用它
    NSUInteger _lastEditHash;
    double _watchMtime;
    unsigned long long _watchSize;
}

+ (instancetype)shared {
    static QMCore *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [QMCore new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lock = [NSLock new];
        NSDictionary *opts = @{ kCIContextUseSoftwareRenderer : @NO,
                                kCIContextWorkingColorSpace : (id)[NSNull null] };
        _ci = [CIContext contextWithOptions:opts];
        if (!_ci) _ci = [CIContext context];
    }
    return self;
}

- (BOOL)isActive { @synchronized (self) { return _active; } }
- (unsigned long long)generation { @synchronized (self) { return _gen; } }

- (void)setActive:(BOOL)active reason:(NSString *)reason {
    BOOL changed = NO;
    @synchronized (self) {
        if (_active != active) { _active = active; _gen++; changed = YES; }
    }
    if (changed) {
        QMLog(@"[vcam] %@ (gen=%llu) — %@", active ? @"Replacement frames activated"
                                                   : @"Replacement frame cleared, real camera restored",
              _gen, reason ?: @"");
        if (active) [self reloadMedia];
    }
}

- (void)invalidate {
    @synchronized (self) { _gen++; }
    [_src stop];
    _src = nil;
}

- (NSString *)_pickDefaultPathForKind:(NSString *)kind {
    NSArray *list = QMListMedia(kindIsVideo(kind) ? QMPath(QMV_SLOT_VIDEO_DIR) : QMPath(QMV_SLOT_IMAGE_DIR),
                                kindIsVideo(kind));
    if (list.count) return list.firstObject;
    // 兼容原包默认位置
    if (kindIsVideo(kind)) {
        NSString *p = QMPath(QMV_DEFAULT_VIDEO);
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
        NSArray *all = QMListMedia(QMPath(QMV_DIR_VCAM), YES);
        if (all.count) return all.firstObject;
    } else {
        NSArray *all = QMListMedia(QMPath(QMV_DIR_VCAM), NO);
        if (all.count) return all.firstObject;
    }
    return nil;
}

- (void)reloadMedia {
    QMState *st = [QMState shared];
    [st load];
    NSString *kind = st.mediaKind;
    if (!kind) kind = @"video";
    NSString *path = st.activePath;
    NSFileManager *fm = [NSFileManager defaultManager];

    // activePath 可能是 rootless 之外的老路径，做一次前缀归一
    if (path && ![fm fileExistsAtPath:path]) {
        NSString *alt = QMPath(path);
        if ([fm fileExistsAtPath:alt]) path = alt;
    }
    if (!path || ![fm fileExistsAtPath:path]) {
        path = [self _pickDefaultPathForKind:kind];
        if (path) { st.activePath = path; }
    }
    if (!path) {
        QMLog(@"[vcam] No media file found; real camera kept");
        return;
    }
    // 同路径同 kind 且已在播放 → 不动
    if (_src && [_src.path isEqualToString:path]) {
        _src.paused = st.paused;
        return;
    }
    [_src stop];
    QMLog(@"[vcam] Loading %@: %@", kind, path);
    _src = [[QMFrameSource alloc] initWithPath:path kind:kind];
    _src.paused = st.paused;
    [_src start];
    [self startWatchingPath:path];
    QMLog(@"[vcam] Source ready %@ (%.0fx%.0f)", path.lastPathComponent, _src.size.width, _src.size.height);
}

- (void)restartPlayback {
    [_src stop];
    _src = nil;
    [self reloadMedia];
}

- (void)togglePause {
    QMState *st = [QMState shared];
    st.paused = !st.paused;
    _src.paused = st.paused;
    QMLog(@"[vcam][btn] paused -> %d", st.paused);
}

#pragma mark - 文件监听（98d 同款：inode/mtime/size 变化即重载）

- (void)startWatchingPath:(NSString *)path {
    if (_watch) { dispatch_source_cancel(_watch); _watch = nil; }
    if (!path.length) return;
    _watchMtime = 0; _watchSize = 0;
    NSString *watched = [path copy];
    __weak typeof(self) weakSelf = self;
    _watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                    dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(_watch,
                              dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              (uint64_t)(1.0 * NSEC_PER_SEC), (uint64_t)(0.2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(_watch, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        struct stat st;
        if (stat(watched.fileSystemRepresentation, &st) != 0) {
            QMLog(@"[vcam] Active source missing, clearing: %@", watched);
            dispatch_source_cancel(self->_watch);
            self->_watch = nil;
            [self invalidate];
            return;
        }
        double mt = (double)st.st_mtimespec.tv_sec + (double)st.st_mtimespec.tv_nsec / 1e9;
        unsigned long long sz = (unsigned long long)st.st_size;
        if (self->_watchMtime != 0 && (mt != self->_watchMtime || sz != self->_watchSize)) {
            QMLog(@"[vcam] Media changed: %@, reloading...", watched.lastPathComponent);
            [self reloadMedia];
        }
        self->_watchMtime = mt;
        self->_watchSize = sz;
    });
    dispatch_resume(_watch);
    QMLog(@"[vcam] Started watching file: %@", path.lastPathComponent);
}

#pragma mark - pooled destination buffer

- (CVPixelBufferRef)_destBufferForWidth:(size_t)w height:(size_t)h format:(OSType)fmt {
    if (_pool && (_pw != w || _ph != h || _pfmt != fmt)) {
        CVPixelBufferPoolRelease(_pool); _pool = NULL;
    }
    if (!_pool) {
        NSDictionary *attrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey : @(fmt),
            (id)kCVPixelBufferWidthKey : @(w),
            (id)kCVPixelBufferHeightKey : @(h),
            (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
            (id)kCVPixelBufferMetalCompatibilityKey : @YES,
        };
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attrs, &_pool);
        _pw = w; _ph = h; _pfmt = fmt;
        QMLog(@"[vcam] Created dest pool %zux%zu fmt=%08x", w, h, fmt);
    }
    CVPixelBufferRef pb = NULL;
    if (!_pool || CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &pb) != kCVReturnSuccess) {
        return NULL;
    }
    return pb;
}

#pragma mark - render

- (BOOL)_renderFrame:(CVPixelBufferRef)src into:(CVPixelBufferRef)dst {
    QMState *st = [QMState shared];
    size_t dw = CVPixelBufferGetWidth(dst), dh = CVPixelBufferGetHeight(dst);
    size_t sw = CVPixelBufferGetWidth(src), sh = CVPixelBufferGetHeight(src);
    if (!sw || !sh) return NO;

    CIImage *img = [CIImage imageWithCVPixelBuffer:src
                                          options:@{ kCIImageColorSpace : (id)[NSNull null] }];
    if (!img) return NO;

    // 1) 旋转
    NSInteger rot = st.rotation % 360;
    if (rot < 0) rot += 360;
    if (rot == 90) {
        img = [img imageByApplyingOrientation:kCGImagePropertyOrientationRight];
    } else if (rot == 180) {
        img = [img imageByApplyingOrientation:kCGImagePropertyOrientationDown];
    } else if (rot == 270) {
        img = [img imageByApplyingOrientation:kCGImagePropertyOrientationLeft];
    }
    CGRect ext = img.extent;
    img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(-ext.origin.x, -ext.origin.y)];
    CGFloat iw = ext.size.width, ih = ext.size.height;

    // 2) 填充方式：edgeClamp = 裁剪填充（aspect fill），否则留边（aspect fit）
    double zoom = MAX(0.2, MIN(st.zoom, 6.0));
    CGFloat sxFill = dw / iw, syFill = dh / ih;
    CGFloat scale = st.edgeClamp ? MAX(sxFill, syFill) : MIN(sxFill, syFill);
    scale *= zoom;

    CGFloat finalW = iw * scale, finalH = ih * scale;
    CGFloat dx = (dw - finalW) * 0.5 + st.panX * dw * 0.5;
    CGFloat dy = (dh - finalH) * 0.5 + st.panY * dh * 0.5;

    CGAffineTransform place = CGAffineTransformMakeScale(st.mirror ? -scale : scale, scale);
    if (st.mirror) {
        place = CGAffineTransformConcat(place, CGAffineTransformMakeTranslation(-iw, 0));
    }
    place = CGAffineTransformConcat(place, CGAffineTransformMakeTranslation(dx, dy));
    img = [img imageByApplyingTransform:place];

    // 3) 颜色调整
    if (st.brightness != 0.0 || st.contrast != 1.0 || st.saturation != 1.0) {
        CIFilter *f = [CIFilter filterWithName:@"CIColorControls"];
        [f setValue:img forKey:kCIInputImageKey];
        [f setValue:@(st.brightness) forKey:@"inputBrightness"];
        [f setValue:@(st.contrast) forKey:@"inputContrast"];
        [f setValue:@(st.saturation) forKey:@"inputSaturation"];
        img = f.outputImage ?: img;
    }
    if (st.gamma != 1.0) {
        CIFilter *f = [CIFilter filterWithName:@"CIGammaAdjust"];
        [f setValue:img forKey:kCIInputImageKey];
        [f setValue:@(1.0 / MAX(0.05, st.gamma)) forKey:@"inputPower"];
        img = f.outputImage ?: img;
    }

    // 4) 渲染到目标 buffer（尺寸/格式天然匹配相机）
    CGRect outRect = CGRectMake(0, 0, dw, dh);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    [_ci render:img toCVPixelBuffer:dst bounds:outRect colorSpace:cs];
    CGColorSpaceRelease(cs);
    return YES;
}

// 逐 plane 拷贝（BGRA 与 420f/420v 都覆盖）
static BOOL QMCopyPixelBuffer(CVPixelBufferRef from, CVPixelBufferRef to) {
    if (!from || !to) return NO;
    size_t fw = CVPixelBufferGetWidth(from), fh = CVPixelBufferGetHeight(from);
    size_t tw = CVPixelBufferGetWidth(to), th = CVPixelBufferGetHeight(to);
    if (fw != tw || fh != th) return NO;
    if (CVPixelBufferGetPixelFormatType(from) != CVPixelBufferGetPixelFormatType(to)) return NO;

    CVPixelBufferLockBaseAddress(from, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(to, 0);
    BOOL ok = YES;
    size_t planes = CVPixelBufferIsPlanar(from) ? CVPixelBufferGetPlaneCount(from) : 1;
    for (size_t p = 0; p < planes; p++) {
        void *sb = CVPixelBufferIsPlanar(from) ? CVPixelBufferGetBaseAddressOfPlane(from, p)
                                               : CVPixelBufferGetBaseAddress(from);
        void *db = CVPixelBufferIsPlanar(to) ? CVPixelBufferGetBaseAddressOfPlane(to, p)
                                             : CVPixelBufferGetBaseAddress(to);
        size_t srow = CVPixelBufferIsPlanar(from) ? CVPixelBufferGetBytesPerRowOfPlane(from, p)
                                                  : CVPixelBufferGetBytesPerRow(from);
        size_t drow = CVPixelBufferIsPlanar(to) ? CVPixelBufferGetBytesPerRowOfPlane(to, p)
                                                : CVPixelBufferGetBytesPerRow(to);
        size_t ph = CVPixelBufferIsPlanar(from) ? CVPixelBufferGetHeightOfPlane(from, p)
                                                : CVPixelBufferGetHeight(from);
        size_t n = MIN(srow, drow);
        for (size_t y = 0; y < ph; y++) {
            memcpy((uint8_t *)db + y * drow, (uint8_t *)sb + y * srow, n);
        }
    }
    CVPixelBufferUnlockBaseAddress(to, 0);
    CVPixelBufferUnlockBaseAddress(from, kCVPixelBufferLock_ReadOnly);
    return ok;
}

#pragma mark - hook entry

- (BOOL)processSampleBuffer:(CMSampleBufferRef)sb {
    if (!sb) return NO;
    if (![self isActive]) return NO;
    QMState *st = [QMState shared];
    if (!st.live) return NO;
    if (!_src) {
        // 不要在相机线程里开 AVAsset（会卡管线）：异步加载，本帧放行真画面
        static BOOL sLoading = NO;
        if (!sLoading) {
            sLoading = YES;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                [self reloadMedia];
                sLoading = NO;
            });
        }
        return NO;
    }

    CVPixelBufferRef cam = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sb);
    if (!cam) return NO;
    size_t w = CVPixelBufferGetWidth(cam), h = CVPixelBufferGetHeight(cam);
    OSType fmt = CVPixelBufferGetPixelFormatType(cam);
    if (!w || !h) return NO;

    if (!_loggedFormat) {
        QMLog(@"[vcam] camera buffer %zux%zu fmt=%c%c%c%c", w, h,
              (char)((fmt >> 24) & 0xff), (char)((fmt >> 16) & 0xff),
              (char)((fmt >> 8) & 0xff), (char)(fmt & 0xff));
        _loggedFormat = YES;
    }

    CVPixelBufferRef frame = [_src copyLatestFrame];
    if (frame) {
        if (_lastFrame) CVPixelBufferRelease(_lastFrame);
        _lastFrame = frame;              // 持有：下一帧没有新图时继续用它
    }
    if (!_lastFrame) return NO;          // 仅最前面几帧会放行真画面

    NSUInteger eh = [self editHash];
    BOOL needRender = (!_prepared) || (_prepW != w) || (_prepH != h) || (_prepFmt != fmt) ||
                      (eh != _lastEditHash) || (frame != NULL);
    if (needRender) {
        if (_prepared && (_prepW != w || _prepH != h || _prepFmt != fmt)) {
            CVPixelBufferRelease(_prepared); _prepared = NULL;
        }
        if (!_prepared) {
            _prepared = [self _destBufferForWidth:w height:h format:fmt];
            _prepW = w; _prepH = h; _prepFmt = fmt;
        }
        if (_prepared) {
            @try {
                [self _renderFrame:_lastFrame into:_prepared];
                if ([QMLightState shared].enabled && fmt == kCVPixelFormatType_32BGRA) {
                    [[QMLighting shared] applyToPixelBuffer:_prepared];
                }
            } @catch (NSException *e) {
                QMLog(@"[vcam] render exception: %@", e);
            }
        }
        _lastEditHash = eh;
    }
    if (!_prepared) return NO;
    return QMCopyPixelBuffer(_prepared, cam);   // 每帧都写：绝不回退真实画面
}

- (NSUInteger)editHash {
    QMState *st = [QMState shared];
    NSUInteger h = 17;
    h = h*31 + (NSUInteger)llround(st.zoom * 1000);
    h = h*31 + (NSUInteger)llround((st.panX + 2.0) * 1000);
    h = h*31 + (NSUInteger)llround((st.panY + 2.0) * 1000);
    h = h*31 + (st.mirror ? 1 : 0);
    h = h*31 + (NSUInteger)llround((st.brightness + 1.0) * 100);
    h = h*31 + (NSUInteger)llround(st.contrast * 100);
    h = h*31 + (NSUInteger)llround(st.saturation * 100);
    h = h*31 + (NSUInteger)llround(st.gamma * 100);
    h = h*31 + (NSUInteger)(((st.rotation % 360) + 360) % 360);
    return h;
}

#pragma mark
@end

BOOL kindIsVideo(NSString *kind) { return ![kind isEqualToString:@"image"]; }
