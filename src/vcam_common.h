//
//  vcam_common.h  —  千面 VCam 重编译版（iOS 16 – 26）
//  逆向自 com.taokk3.qianmian 1.0.0-98d
//  共享约定：路径 / 通知 / plist 键 / 日志
//
#ifndef VCAM_COMMON_H
#define VCAM_COMMON_H

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define QMV_NAME        "qmvcam"
#define QMV_VERSION     "3.0.2"
#define QMV_BUILD_TAG   "ios16-26"

// ---------- 设备信标（写到 Media，PC 可直接 AFC 取回） ----------
void QMBeacon(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
/// 同一进程 120 秒内第 N 次启动就返回 N（用于崩溃熔断）
int  QMBootGuard(NSString *proc);

// ---------- hook 适配（ElleKit / CydiaSubstrate 通吃） ----------
void QMHookMessage(Class cls, SEL sel, IMP imp, IMP *outOld);

// ---------- 日志 ----------
#define QMLog(fmt, ...) NSLog(@"[vcam] " fmt, ##__VA_ARGS__)

// ---------- 根路径（rootless 兼容） ----------
// 越狱环境：roothide 的 / 就是 jbroot；rootless（Dopamine/palera1n）真实前缀是 /var/jb
// QMRoot() 在首次调用时探测一次，之后缓存。
NSString *QMRoot(void);
NSString *QMPath(NSString *absolute);   // 给绝对路径加前缀（已存在的绝对路径优先）

// ---------- 固定路径（与原包一致） ----------
#define QMV_MEDIA_DIR       @"/var/mobile/Media/DCIM"
#define QMV_DIR_VCAM        @"/var/mobile/Media/DCIM/vcam"
#define QMV_FILE_STATE      @"/var/mobile/Media/DCIM/vc.plist"
#define QMV_FILE_LIGHT      @"/var/mobile/Media/DCIM/vc.lighting.plist"
#define QMV_SLOT_IMAGE_DIR  @"/var/mobile/Media/DCIM/2"
#define QMV_SLOT_VIDEO_DIR  @"/var/mobile/Media/DCIM/4"
#define QMV_SHM_JOYSTICK    @"/var/mobile/Media/DCIM/.qm_joystick_shm_v1"
#define QMV_DEFAULT_VIDEO   @"/var/mobile/Media/DCIM/vcam.mp4"

// ---------- Darwin 通知（跨进程，与原包同名） ----------
#define QMV_NOTIFY_RELOAD       "com.vcam.ios.media.reload"
#define QMV_NOTIFY_RESTART      "com.vcam.ios.media.restart"
#define QMV_NOTIFY_CLEAR        "com.vcam.ios.media.clear"
#define QMV_NOTIFY_PAUSE        "com.vcam.ios.pause.toggle"
#define QMV_NOTIFY_LIVE         "com.vcam.ios.live.changed"
#define QMV_NOTIFY_LICENSE      "com.vcam.ios.license.updated"
#define QMV_NOTIFY_POST         "com.vcam.notify"

// ---------- vc.plist 键 ----------
#define QMK_LIVE            @"isLive"
#define QMK_BALL            @"floatingBallEnabled"
#define QMK_MIRROR          @"editHorizontalMirror"
#define QMK_EDGE            @"edgeClampEnabled"
#define QMK_PAN_X           @"editPanX"
#define QMK_PAN_Y           @"editPanY"
#define QMK_ZOOM            @"editZoom"
#define QMK_BRIGHT          @"editBrightness"
#define QMK_CONTRAST        @"editContrast"
#define QMK_SATURATION      @"editSaturation"
#define QMK_GAMMA           @"editGamma"
#define QMK_MEDIA_KIND      @"activeMediaKind"       // @"image" / @"video"
#define QMK_SLOT_INDEX      @"activeSlotIndex"
#define QMK_ACTIVE_PATH     @"activePlaybackPath"
#define QMK_PAUSED          @"paused"
#define QMK_POSITION        @"fakePosition"          // 0 未指定 / 1 后置 / 2 前置
#define QMK_ROTATION        @"rotationDegrees"       // 0/90/180/270

// ---------- vc.lighting.plist 键 ----------
#define QMK_LIGHT_ON        @"lightingEnabled"
#define QMK_LIGHT_PICKER    @"screenPickerEnabled"
#define QMK_LIGHT_INTENSITY @"lightIntensity"
#define QMK_LIGHT_WSCALE    @"lightingWidthScale"
#define QMK_LIGHT_HSCALE    @"lightingHeightScale"
#define QMK_LIGHT_SCENE     @"sceneAdaptiveEnabled"
#define QMK_LIGHT_FEATHER   @"featherRadius"
#define QMK_LIGHT_DIR       @"lightingDirection"
#define QMK_LIGHT_BLEND     @"blendMode"
#define QMK_LIGHT_SRC       @"colorSource"
#define QMK_LIGHT_R         @"colorR"
#define QMK_LIGHT_G         @"colorG"
#define QMK_LIGHT_B         @"colorB"

// ---------- 授权状态 ----------
typedef NS_ENUM(NSInteger, QMLicenseStatus) {
    QMLicenseStatusNone = 0,
    QMLicenseStatusOK,
    QMLicenseStatusExpired,
    QMLicenseStatusWrongDevice,
    QMLicenseStatusBadFormat,
    QMLicenseStatusBadSig,
    QMLicenseStatusNoKey,
};

@interface QMLicense : NSObject
@property (nonatomic, copy, readonly) NSString *deviceFingerprint;      // 3 项 SHA256[0:16]
@property (nonatomic, copy, readonly) NSString *deviceFingerprintExt;   // 5 项 SHA256[0:16]
@property (nonatomic, assign, readonly) QMLicenseStatus status;
@property (nonatomic, assign, readonly) BOOL authorized;
@property (nonatomic, assign, readonly) BOOL permanent;
@property (nonatomic, strong, readonly) NSDate *expiry;
@property (nonatomic, copy, readonly) NSString *statusText;             // “已授权 · 永久” 等
+ (instancetype)shared;
- (void)reload;
- (QMLicenseStatus)activateWithCode:(NSString *)code message:(NSString **)message;
- (void)clearLicense;
- (uint32_t)featureMask;
- (NSString *)activationInfoText;
@end

// ---------- 状态 ----------
@interface QMState : NSObject
@property (nonatomic, assign) BOOL live;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL mirror;
@property (nonatomic, assign) BOOL edgeClamp;
@property (nonatomic, assign) BOOL ballEnabled;
@property (nonatomic, assign) double panX, panY, zoom;
@property (nonatomic, assign) double brightness, contrast, saturation, gamma;
@property (nonatomic, assign) NSInteger fakePosition;   // 0 = 不改
@property (nonatomic, assign) NSInteger rotation;       // 0/90/180/270
@property (nonatomic, copy)   NSString *mediaKind;      // image / video
@property (nonatomic, assign) NSInteger slotIndex;
@property (nonatomic, copy)   NSString *activePath;
+ (instancetype)shared;
- (void)load;
- (void)save;
- (void)saveSoon;
- (NSDictionary *)dictionary;
@end

// ---------- 光源参数 ----------
@interface QMLightState : NSObject
@property (nonatomic, assign) BOOL enabled, screenPicker, sceneAdaptive;
@property (nonatomic, assign) double intensity, widthScale, heightScale, feather;
@property (nonatomic, assign) NSInteger direction, blendMode;   // 0..7 / 0..5
@property (nonatomic, assign) double colorR, colorG, colorB;
+ (instancetype)shared;
- (void)load; - (void)save;
- (void)reloadFromDisk;
@end

// ---------- 核心 ----------
@interface QMCore : NSObject
+ (instancetype)shared;
@property (nonatomic, assign) BOOL pipelineActive;
@property (nonatomic, assign) unsigned long long generation;
- (void)setActive:(BOOL)active reason:(NSString *)reason;   // 开/关替换
- (BOOL)isActive;
- (void)invalidate;
- (void)reloadMedia;         // 重新解析 activePath
- (void)restartPlayback;
- (void)togglePause;
/// 原地改写真实相机 CVPixelBuffer 的像素（不新建 sample buffer）
- (BOOL)processSampleBuffer:(CMSampleBufferRef)sb;
@end

// ---------- 打光 ----------
@interface QMLighting : NSObject
+ (instancetype)shared;
- (BOOL)applyToPixelBuffer:(CVPixelBufferRef)pb;
- (void)pickScreenColor;
@property (nonatomic, strong, readonly) UIColor *pickedColor;
@end

#endif /* VCAM_COMMON_H */
