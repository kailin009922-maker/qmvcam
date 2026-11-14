//
//  vcam_license.m — 授权（对齐 98d 线：66 字节载荷 + DER 签名 + 卖家自有公钥）
//
//  格式（与 千面_发卡器.exe / CLI 完全一致，已用真码回验通过）：
//      code   = base64( payload(65B) | sigLen(1B) | sig(DER) )
//      payload= [0]=0x01 | [1:17) 设备指纹16B | [17:21) 到期u32LE(0=永久)
//               | [21:25) 功能位u32LE | [25:65) 40B 随机/运行密钥
//      签名覆盖 payload 的 65 字节（不含 sigLen）
//
//  设备指纹 = SHA256( IOPlatformUUID | Serial | ChipID )[0:16]，小写 hex
//  （与 25r20 门禁同一算法，发卡器给出的码可直接用）
//
#import "vcam_common.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <IOKit/IOKitLib.h>
#include <sys/stat.h>
#include <unistd.h>

// 卖家公钥（65 字节未压缩点；SHA256 前 8 字节 = 556D71361578ED37）
static const uint8_t kQMPublicKey[65] = {
    0x04, 0x38, 0xe2, 0x8d, 0xba, 0xd2, 0x67, 0x3e, 0xef, 0xf2, 0x55, 0xca, 0xf9, 0x9f, 0xbc, 0x7d,
    0xe4, 0x20, 0x99, 0x1f, 0xa2, 0x56, 0x49, 0xec, 0xeb, 0xcb, 0x2d, 0xdc, 0x24, 0x8d, 0x5b, 0x36,
    0x5a, 0x83, 0x99, 0x19, 0xae, 0x65, 0xe5, 0x40, 0x4b, 0xda, 0x17, 0x63, 0xf6, 0xce, 0xbe, 0x40,
    0x70, 0xc3, 0x43, 0xf3, 0x20, 0xdd, 0xdc, 0x9f, 0x09, 0xac, 0x40, 0xca, 0x6d, 0x0d, 0x13, 0x18,
    0x46
};

static NSString *QMHexLower(NSData *d) {
    const uint8_t *p = d.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 2];
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}

static NSString *QMReadIOProperty(NSString *key) {
    io_service_t svc = IOServiceGetMatchingService(MACH_PORT_NULL,
                                                   IOServiceMatching("IOPlatformExpertDevice"));
    if (!svc) return nil;
    CFTypeRef v = IORegistryEntryCreateCFProperty(svc, (__bridge CFStringRef)key,
                                                  kCFAllocatorDefault, 0);
    IOObjectRelease(svc);
    if (!v) return nil;
    NSString *out = nil;
    if (CFGetTypeID(v) == CFDataGetTypeID()) {
        out = QMHexLower((__bridge NSData *)v);
    } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
        out = [(__bridge NSString *)v copy];
    } else if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        long long n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberLongLongType, &n);
        out = [NSString stringWithFormat:@"0x%llx", n];
    }
    CFRelease(v);
    return out ?: @"(unavailable)";
}

@implementation QMLicense {
    NSString *_fp3;
    QMLicenseStatus _status;
    NSDate *_expiry;
    BOOL _permanent;
    uint32_t _featureMask;
    NSString *_lastMessage;
}

+ (instancetype)shared {
    static QMLicense *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [QMLicense new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self _computeFingerprint];
        [self reload];
    }
    return self;
}

#pragma mark - 指纹

- (void)_computeFingerprint {
    NSString *uuid   = QMReadIOProperty(@"IOPlatformUUID");
    NSString *serial = QMReadIOProperty(@"IOPlatformSerialNumber");
    NSString *chip   = QMReadIOProperty(@"UniqueChipID");

    // 与 25r20 门禁一致：三项用 '|' 连接后 SHA256，取前 16 字节
    NSString *joined = [NSString stringWithFormat:@"%@|%@|%@",
                        uuid ?: @"-", serial ?: @"-", chip ?: @"-"];
    uint8_t d[CC_SHA256_DIGEST_LENGTH];
    NSData *blob = [joined dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(blob.bytes, (CC_LONG)blob.length, d);
    _fp3 = [QMHexLower([NSData dataWithBytes:d length:16]) copy];
    QMLog(@"[vcam] device fingerprint %@", _fp3);
}

- (NSString *)deviceFingerprint { return _fp3; }
- (NSString *)deviceFingerprintExt { return _fp3; }
- (QMLicenseStatus)status { return _status; }
- (NSDate *)expiry { return _expiry; }
- (BOOL)permanent { return _permanent; }
- (uint32_t)featureMask { return _featureMask; }

- (BOOL)authorized {
    // 调试开关：存在 /DCIM/.qm_dev 时直接放行（量产前删除该文件即恢复校验）
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Media/DCIM/.qm_dev"]) return YES;
    if (_status != QMLicenseStatusOK) return NO;
    if (_permanent) return YES;
    return _expiry && [_expiry timeIntervalSinceNow] > 0;
}

- (NSString *)statusText {
    if (self.authorized) {
        return _permanent ? @"已授权 · 永久"
                          : [NSString stringWithFormat:@"已授权 · 至 %@",
                             [[self _fmt] stringFromDate:_expiry]];
    }
    return _lastMessage ?: @"未授权";
}

- (NSDateFormatter *)_fmt {
    static NSDateFormatter *f; static dispatch_once_t o;
    dispatch_once(&o, ^{ f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd"; });
    return f;
}

#pragma mark - 存储

- (NSString *)storePath { return @"/var/mobile/Media/DCIM/vc_license.txt"; }   // 98d 同款

- (void)reload {
    NSString *code = nil;
    NSString *p = [self storePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
        code = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
        code = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if (!code.length) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:QMV_FILE_STATE];
        code = d[@"activationCode"];
    }
    if (!code.length) {
        _status = QMLicenseStatusNone;
        _lastMessage = @"未授权";
        return;
    }
    NSString *msg = nil;
    _status = [self _verifyCode:code message:&msg];
    _lastMessage = [msg copy];
    QMLog(@"[vcam] license: %@ (%@)", [self statusText], msg ?: @"-");
}

#pragma mark - 校验

static NSData *QMBase64Decode(NSString *s) {
    if (!s.length) return nil;
    NSMutableString *t = [s mutableCopy];
    [t replaceOccurrencesOfString:@"\n" withString:@"" options:0 range:NSMakeRange(0, t.length)];
    [t replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0, t.length)];
    [t replaceOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, t.length)];
    [t replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, t.length)];
    [t replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, t.length)];
    while (t.length % 4) [t appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:t options:0];
}

- (QMLicenseStatus)_verifyCode:(NSString *)code message:(NSString **)msg {
    NSData *raw = QMBase64Decode(code);
    if (!raw || raw.length <= 129) {   // 与 app 内置判定一致：≤129 直接判非法
        if (msg) *msg = @"未授权 / 激活码格式非法";
        return QMLicenseStatusBadFormat;
    }
    const uint8_t *p = raw.bytes;
    if (p[0] != 0x01) {
        if (msg) *msg = [NSString stringWithFormat:@"未授权 / 激活码版本不支持 (v%u)", p[0]];
        return QMLicenseStatusBadFormat;
    }
    uint8_t siglen = p[65];
    if (raw.length != 66 + (NSUInteger)siglen) {
        if (msg) *msg = @"未授权 / 激活码长度异常";
        return QMLicenseStatusBadFormat;
    }

    NSData *payload = [raw subdataWithRange:NSMakeRange(0, 65)];
    NSData *sig = [raw subdataWithRange:NSMakeRange(66, siglen)];

    // 1) 验签（ECDSA P-256 / SHA-256，DER）
    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType : (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass : (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits : @256,
    };
    SecKeyRef pub = SecKeyCreateWithData((__bridge CFDataRef)[NSData dataWithBytes:kQMPublicKey
                                                                           length:sizeof(kQMPublicKey)],
                                         (__bridge CFDictionaryRef)attrs, NULL);
    if (!pub) {
        if (msg) *msg = @"未授权 / 公钥异常";
        return QMLicenseStatusNoKey;
    }
    BOOL ok = SecKeyVerifySignature(pub,
                                    kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                    (__bridge CFDataRef)payload, (__bridge CFDataRef)sig, NULL);
    CFRelease(pub);
    if (!ok) {
        if (msg) *msg = @"未授权 / 签名非法";
        return QMLicenseStatusBadSig;
    }

    // 2) 设备指纹（前 16 字节）
    NSData *fpData = [raw subdataWithRange:NSMakeRange(1, 16)];
    NSString *fp = QMHexLower(fpData);
    if (![fp isEqualToString:_fp3]) {
        if (msg) *msg = @"未授权 / 激活码不属于本机";
        return QMLicenseStatusWrongDevice;
    }

    // 3) 有效期（u32 LE，0 = 永久）
    uint32_t exp = 0;
    memcpy(&exp, p + 17, 4);
    uint32_t mask = 0;
    memcpy(&mask, p + 21, 4);
    _featureMask = mask;

    if (exp == 0) {
        _permanent = YES;
        _expiry = nil;
    } else {
        _permanent = NO;
        _expiry = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)exp];
        if ([_expiry timeIntervalSinceNow] <= 0) {
            if (msg) *msg = @"未授权 / 激活码已过期";
            return QMLicenseStatusExpired;
        }
    }
    if (msg) *msg = @"验证通过";
    return QMLicenseStatusOK;
}

- (QMLicenseStatus)activateWithCode:(NSString *)code message:(NSString **)message {
    code = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (code.length < 20 || code.length > 4096) {
        if (message) *message = @"输入为空或长度异常";
        return QMLicenseStatusBadFormat;
    }
    NSString *msg = nil;
    QMLicenseStatus st = [self _verifyCode:code message:&msg];
    if (message) *message = msg;
    if (st != QMLicenseStatusOK) return st;

    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Media/DCIM"
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *p = [self storePath];
    if (![code writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        if (message) *message = @"保存失败";
        return QMLicenseStatusBadFormat;
    }
    chmod([p fileSystemRepresentation], 0644);
    _status = st;
    _lastMessage = [msg copy];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR(QMV_NOTIFY_LICENSE), NULL, NULL, true);
    QMLog(@"[vcam] 激活成功 (%lu 字节)", (unsigned long)code.length);
    return st;
}

- (void)clearLicense {
    [[NSFileManager defaultManager] removeItemAtPath:[self storePath] error:nil];
    _status = QMLicenseStatusNone;
    _lastMessage = @"未授权";
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR(QMV_NOTIFY_LICENSE), NULL, NULL, true);
    QMLog(@"[vcam] 清除激活信息");
}

- (NSString *)activationInfoText {
    return [NSString stringWithFormat:@"%@\n\n设备指纹（发给客服）\n%@",
            [self statusText], _fp3 ?: @"-"];
}

@end
