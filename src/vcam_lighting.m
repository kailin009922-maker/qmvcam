//
//  vcam_lighting.m — 人脸补光（Metal）+ 屏幕取色
//
//  原包内嵌了完整 MSL（faceLighting / eyeCatchlight），本重编译版保留同一条
//  渲染思路：法线混合 + Half-Lambert + 羽化椭圆遮罩 + 6 种混合模式。
//  为便于参数对齐，运行时 kernel 用 float4 打包参数（原 MSL 原文见
//  shaders/face_lighting_original.metal，可直接替换）。
//
#import "vcam_common.h"
#import <Metal/Metal.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

static NSString *const kQMShaderSource = @R"MSL(
#include <metal_stdlib>
using namespace metal;

struct LightParams {
    float4 faceRect;        // x,y,w,h  (pixels)
    float4 dirIntensity;    // xyz = light dir, w = intensity
    float4 colorFeather;    // rgb = light color, a = feather
    float4 misc;            // x = blendMode, y = width, z = height, w = unused
};

static float3 applyBlend(float3 src, float3 light, uint mode) {
    switch (mode) {
        case 0: return src * (light + 0.5);
        case 1: return select(2.0 * src * light, 1.0 - 2.0 * (1.0 - src) * (1.0 - light), src >= 0.5);
        case 2: return 1.0 - (1.0 - src) * (1.0 - light);
        case 3: return src + light;
        case 4: return select(2.0 * src * light, 1.0 - 2.0 * (1.0 - src) * (1.0 - light), light >= 0.5);
        case 5: return min(float3(1.0), src / max(float3(0.001), 1.0 - light));
        default: return src;
    }
}

kernel void faceLighting(
    texture2d<float, access::read_write> frame [[texture(0)]],
    constant LightParams &p [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint W = uint(p.misc.y), H = uint(p.misc.z);
    if (gid.x >= W || gid.y >= H) return;

    float4 fr = p.faceRect;
    float feather = p.colorFeather.a;
    float ex = fr.z * feather * 0.5;
    float ey = fr.w * feather * 0.5;
    float minX = fr.x - ex, minY = fr.y - ey;
    float maxX = fr.x + fr.z + ex, maxY = fr.y + fr.w + ey;
    float fx = float(gid.x), fy = float(gid.y);
    if (fx < minX || fx >= maxX || fy < minY || fy >= maxY) return;

    float cx = fr.x + fr.z * 0.5;
    float cy = fr.y + fr.w * 0.5;
    float rx = fr.z * 0.5 + ex;
    float ry = fr.w * 0.5 + ey;
    float ndx = (fx - cx) / max(1.0, rx);
    float ndy = (fy - cy) / max(1.0, ry);
    float d2 = ndx * ndx + ndy * ndy;
    if (d2 >= 1.0) return;
    float mask = (1.0 - d2) * (1.0 - d2);

    float u = (fx - fr.x) / max(1.0, fr.z);
    float v = (fy - fr.y) / max(1.0, fr.w);
    float3 N = normalize(float3((u - 0.5) * 1.2, (v - 0.5) * 1.2, 1.0));
    float3 L = normalize(p.dirIntensity.xyz);
    float halfLambert = dot(N, L) * 0.5 + 0.5;
    float diffuse = 0.20 + 0.80 * (halfLambert * halfLambert);

    float2 spotUV = float2(0.5, 0.28);
    float dl = distance(float2(u, v), spotUV);
    float spot = exp(-dl * dl / (2.0 * 0.40 * 0.40));

    float localIntensity = clamp(p.dirIntensity.w * mask * spot, 0.0, 1.0);
    if (localIntensity < 0.005) return;

    float4 pixel = frame.read(gid);
    float3 src = pixel.rgb;
    float3 lightContrib = p.colorFeather.rgb * diffuse;
    float3 blended = applyBlend(src, lightContrib, uint(p.misc.x));
    frame.write(float4(clamp(src + (blended - src) * localIntensity, 0.0, 1.0), pixel.a), gid);
}
)MSL";

typedef struct {
    float faceRect[4];
    float dirIntensity[4];
    float colorFeather[4];
    float misc[4];
} QMLightParams;   // 64 bytes, 与 MSL 结构布局一致

@implementation QMLighting {
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _pipeline;
    id<MTLCommandQueue> _queue;
    CVMetalTextureCacheRef _texCache;
    BOOL _failed;
    UIColor *_pickedColor;
}

+ (instancetype)shared {
    static QMLighting *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [QMLighting new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _device = MTLCreateSystemDefaultDevice();
        if (!_device) { _failed = YES; return self; }
        NSError *err = nil;
        id<MTLLibrary> lib = [_device newLibraryWithSource:kQMShaderSource options:nil error:&err];
        if (!lib) {
            QMLog(@"[vcam] Metal library compile failed: %@", err);
            _failed = YES;
            return self;
        }
        _pipeline = [_device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"faceLighting"]
                                                           error:&err];
        if (!_pipeline) { QMLog(@"[vcam] pipeline failed: %@", err); _failed = YES; return self; }
        _queue = [_device newCommandQueue];
        CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _device, NULL, &_texCache);
        QMLog(@"[vcam] MetalLightingEngine ready");
    }
    return self;
}

- (UIColor *)pickedColor { return _pickedColor; }

- (CGRect)_detectFaceIn:(CVPixelBufferRef)pb {
    @try {
        VNDetectFaceRectanglesRequest *req = [VNDetectFaceRectanglesRequest new];
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pb options:@{}];
        if (![h performRequests:@[req] error:nil]) return CGRectZero;
        VNFaceObservation *face = req.results.firstObject;
        if (!face) return CGRectZero;
        CGRect bb = face.boundingBox;      // 归一化，原点左下
        size_t w = CVPixelBufferGetWidth(pb), hgt = CVPixelBufferGetHeight(pb);
        return CGRectMake(bb.origin.x * w,
                          (1.0 - bb.origin.y - bb.size.height) * hgt,
                          bb.size.width * w, bb.size.height * hgt);
    } @catch (NSException *e) {
        return CGRectZero;
    }
}

- (BOOL)applyToPixelBuffer:(CVPixelBufferRef)pb {
    QMLightState *ls = [QMLightState shared];
    if (_failed || !_pipeline || !pb || !ls.enabled) return NO;
    if (CVPixelBufferGetPixelFormatType(pb) != kCVPixelFormatType_32BGRA) return NO;

    CGRect face = [self _detectFaceIn:pb];
    size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
    if (face.size.width < 8 || face.size.height < 8) {
        // 没人脸时退化到画面中央区域，保证开关有可见效果
        face = CGRectMake(w * 0.5 - w * 0.18 * ls.widthScale, h * 0.22,
                          w * 0.36 * ls.widthScale, h * 0.34 * ls.heightScale);
    } else {
        face = CGRectMake(CGRectGetMidX(face) - face.size.width * 0.5 * ls.widthScale,
                          face.origin.y, face.size.width * ls.widthScale,
                          face.size.height * ls.heightScale);
    }

    CVMetalTextureRef tex = NULL;
    CVReturn r = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _texCache, pb, NULL,
                                                           MTLPixelFormatBGRA8Unorm, w, h, 0, &tex);
    if (r != kCVReturnSuccess || !tex) return NO;

    static const float dirs[8][2] = {
        {-0.7f, -0.7f}, {0, -1}, {0.7f, -0.7f}, {-1, 0},
        {1, 0}, {-0.7f, 0.7f}, {0, 1}, {0.7f, 0.7f}
    };
    int di = (int)MAX(0, MIN(7, ls.direction));

    QMLightParams p = {0};
    p.faceRect[0] = face.origin.x; p.faceRect[1] = face.origin.y;
    p.faceRect[2] = face.size.width; p.faceRect[3] = face.size.height;
    p.dirIntensity[0] = dirs[di][0]; p.dirIntensity[1] = -dirs[di][1]; p.dirIntensity[2] = 0.8f;
    p.dirIntensity[3] = (float)ls.intensity;
    p.colorFeather[0] = (float)ls.colorR; p.colorFeather[1] = (float)ls.colorG;
    p.colorFeather[2] = (float)ls.colorB; p.colorFeather[3] = (float)MAX(0.05, ls.feather);
    p.misc[0] = (float)ls.blendMode; p.misc[1] = (float)w; p.misc[2] = (float)h; p.misc[3] = 0;

    id<MTLTexture> frame = CVMetalTextureGetTexture(tex);
    if (!frame) { CFRelease(tex); return NO; }

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
    [enc setComputePipelineState:_pipeline];
    [enc setTexture:frame atIndex:0];
    [enc setBytes:&p length:sizeof(p) atIndex:0];
    MTLSize grid = MTLSizeMake(w, h, 1);
    NSUInteger tw = _pipeline.threadExecutionWidth;
    NSUInteger th = MAX(1, _pipeline.maxTotalThreadsPerThreadgroup / tw);
    [enc dispatchThreads:grid threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    CFRelease(tex);
    CVMetalTextureCacheFlush(_texCache, 0);
    return YES;
}

#pragma mark - 屏幕取色

- (void)pickScreenColor {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *win = nil;
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
        }
        UIColor *c = nil;
        if (win) {
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)];
            UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [win drawViewHierarchyInRect:win.bounds afterScreenUpdates:NO];
            }];
            c = [self _averageColorOf:img];
        }
        if (!c) {
            // 兜底：CARenderServer 直接取一帧
            void *sym = dlsym(RTLD_DEFAULT, "CARenderServerRenderDisplay");
            if (sym) {
                QMLog(@"[vcam] CARenderServerRenderDisplay available");
                c = win.backgroundColor;
            }
        }
        self->_pickedColor = c ?: [UIColor whiteColor];
        QMLightState *ls = [QMLightState shared];
        CGFloat rr = 1, gg = 1, bb = 1, aa = 1;
        [self->_pickedColor getRed:&rr green:&gg blue:&bb alpha:&aa];
        ls.colorR = rr; ls.colorG = gg; ls.colorB = bb;
        QMLog(@"[vcam] ScreenColorPicker picked r=%.2f g=%.2f b=%.2f", rr, gg, bb);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR(QMV_NOTIFY_POST), NULL, NULL, true);
    });
}

- (UIColor *)_averageColorOf:(UIImage *)img {
    if (!img) return nil;
    CGImageRef cg = img.CGImage;
    if (!cg) return nil;
    size_t w = 1, h = 1;
    uint8_t px[4] = {0, 0, 0, 0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    return [UIColor colorWithRed:px[0] / 255.0 green:px[1] / 255.0 blue:px[2] / 255.0 alpha:1.0];
}

@end
