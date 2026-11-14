//
//  vcam_source.m — 媒体源：图片 / 视频 → 连续 BGRA 帧
//
//  设计：
//   · 解码在独立串行队列里跑，消费者（相机回调）只做“取最新帧 + 拷贝”，不阻塞管线
//   · 视频用 AVAssetReader 逐帧读 BGRA，读完自动回到开头（循环）
//   · 图片只解一次，之后一直复用
//   · paused 时不再推进帧（保留当前帧）
//
#import "vcam_common.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import "vcam_source.h"

@implementation QMFrameSource {
    NSString *_path;
    NSString *_kind;
    BOOL _isVideo;
    CGSize _size;

    dispatch_queue_t _q;
    dispatch_semaphore_t _tick;

    CVPixelBufferRef _latest;      // 受 _lock 保护
    NSLock *_lock;
    BOOL _running;
    BOOL _finished;

    // video
    AVAsset *_asset;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_output;
    CMTime _duration;
    double _fps;
    NSUInteger _frameIndex;

    CVPixelBufferPoolRef _pool;
    CGImageRef _image;
}

- (instancetype)initWithPath:(NSString *)path kind:(NSString *)kind {
    if ((self = [super init])) {
        _path = [path copy];
        _kind = [kind copy] ?: @"video";
        _isVideo = ![_kind isEqualToString:@"image"];
        _lock = [NSLock new];
        _q = dispatch_queue_create("com.vcam.decode", DISPATCH_QUEUE_SERIAL);
        _tick = dispatch_semaphore_create(0);
        _fps = 30.0;
        _size = CGSizeMake(1080, 1920);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (CGSize)size { return _size; }
- (BOOL)isVideo { return _isVideo; }
- (NSString *)path { return _path; }

- (void)start {
    if (_running) return;
    _running = YES;
    if (_isVideo) {
        __weak typeof(self) w = self;
        dispatch_async(_q, ^{ [w _videoLoop]; });
    } else {
        // 图片解码也放到串行队列，避免在相机回调线程里做 JPEG/HEIC 解码
        __weak typeof(self) w = self;
        dispatch_async(_q, ^{ [w _loadImage]; });
    }
}

- (void)stop {
    _running = NO;
    dispatch_semaphore_signal(_tick);
    @synchronized (self) {
        if (_latest) { CVPixelBufferRelease(_latest); _latest = NULL; }
    }
}

- (void)setPaused:(BOOL)paused {
    _paused = paused;
    if (!paused) dispatch_semaphore_signal(_tick);
}

- (CVPixelBufferRef)copyLatestFrame {
    CVPixelBufferRef out = NULL;
    [_lock lock];
    if (_latest) { out = CVPixelBufferRetain(_latest); }
    [_lock unlock];
    return out;
}

- (void)_store:(CVPixelBufferRef)pb {
    [_lock lock];
    if (_latest) CVPixelBufferRelease(_latest);
    _latest = pb ? CVPixelBufferRetain(pb) : NULL;
    [_lock unlock];
    // 通知消费者有新帧（相机回调按自己的节奏取，无需等待）
    dispatch_semaphore_signal(_tick);
}

// ---------------------------------------------------------------- image
- (void)_loadImage {
    NSURL *url = [NSURL fileURLWithPath:_path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) { QMLog(@"Image file not found %@", _path); return; }
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!img) { QMLog(@"Failed to decode image %@", _path); return; }
    _image = img;
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    _size = CGSizeMake(w, h);

    CVPixelBufferRef pb = NULL;
    NSDictionary *attrs = @{ (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
                             (id)kCVPixelBufferMetalCompatibilityKey : @YES };
    CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                        (__bridge CFDictionaryRef)attrs, &pb);
    if (!pb) { QMLog(@"[vcam] CVPixelBufferCreate failed: image"); return; }
    CVPixelBufferLockBaseAddress(pb, 0);
    void *base = CVPixelBufferGetBaseAddress(pb);
    size_t bpr = CVPixelBufferGetBytesPerRow(pb);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(base, w, h, 8, bpr, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb, 0);
    [self _store:pb];
    CVPixelBufferRelease(pb);
    QMLog(@"[vcam] Image loaded successfully %@ (%zux%zu)", _path.lastPathComponent, w, h);
}

// ---------------------------------------------------------------- video
- (BOOL)_openReader {
    NSURL *url = [NSURL fileURLWithPath:_path];
    _asset = [AVAsset assetWithURL:url];
    if (!_asset) return NO;
    AVAssetTrack *track = [[_asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) { QMLog(@"No video track found %@", _path); return NO; }
    _duration = _asset.duration;
    float nominal = track.nominalFrameRate;
    if (nominal > 1.0f) _fps = MIN(MAX(nominal, 15.0f), 60.0f);
    CGSize natural = track.naturalSize;
    if (natural.width > 0 && natural.height > 0) _size = natural;

    NSError *err = nil;
    _reader = [AVAssetReader assetReaderWithAsset:_asset error:&err];
    if (!_reader) { QMLog(@"[vcam] Failed to setup reader: %@", err); return NO; }
    NSDictionary *opts = @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
        (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    _output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:opts];
    _output.alwaysCopiesSampleData = NO;
    if (![_reader canAddOutput:_output]) return NO;
    [_reader addOutput:_output];
    if (![_reader startReading]) { QMLog(@"[vcam] reader startReading failed"); return NO; }
    _frameIndex = 0;
    QMLog(@"[vcam] LocalVideoPlayer: %@ (%0.fx%0.f @ %.1ffps)", _path.lastPathComponent,
          _size.width, _size.height, _fps);
    return YES;
}

- (void)_videoLoop {
    if (![self _openReader]) { _finished = YES; return; }
    while (_running) {
        if (_paused) {
            dispatch_semaphore_wait(_tick, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)));
            continue;
        }
        CMSampleBufferRef sb = [_output copyNextSampleBuffer];
        if (!sb) {
            // 读完 → 回到开头
            [_reader cancelReading];
            _reader = nil; _output = nil;
            if (!_running) break;
            if (![self _openReader]) break;
            continue;
        }
        CVImageBufferRef pb = CMSampleBufferGetImageBuffer(sb);
        if (pb) {
            // 保持尺寸信息（有些视频 track.naturalSize 带 transform，这里用真实像素尺寸）
            size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
            if (w && h) _size = CGSizeMake(w, h);
            [self _store:(CVPixelBufferRef)pb];
        }
        CFRelease(sb);
        // 让出节奏，避免一次性把整个视频读进内存
        dispatch_semaphore_wait(_tick, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 / MAX(_fps, 15.0) * NSEC_PER_SEC)));
    }
    if (_reader) { [_reader cancelReading]; _reader = nil; _output = nil; }
    _finished = YES;
}

@end
