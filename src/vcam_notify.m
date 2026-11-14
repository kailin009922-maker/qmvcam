//
//  vcam_notify.m — 跨进程通知 + 状态轮询
//
#import "vcam_common.h"

extern void QMShowPanel(void);

static void QMNotifyCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                             const void *object, CFDictionaryRef userInfo) {
    NSString *n = (__bridge NSString *)name;
    QMLog(@"[vcam] notification: %@", n);

    if ([n isEqualToString:@(QMV_NOTIFY_RELOAD)]) {
        [[QMCore shared] reloadMedia];
    } else if ([n isEqualToString:@(QMV_NOTIFY_RESTART)]) {
        [[QMCore shared] restartPlayback];
    } else if ([n isEqualToString:@(QMV_NOTIFY_CLEAR)]) {
        QMState *st = [QMState shared];
        st.activePath = nil;
        st.live = NO;
        [[QMCore shared] invalidate];
        [[QMCore shared] setActive:NO reason:@"media cleared"];
    } else if ([n isEqualToString:@(QMV_NOTIFY_PAUSE)]) {
        [[QMCore shared] togglePause];
    } else if ([n isEqualToString:@(QMV_NOTIFY_LIVE)]) {
        QMState *st = [QMState shared];
        [st load];
        [[QMCore shared] setActive:st.live reason:@"live notification"];
    } else if ([n isEqualToString:@(QMV_NOTIFY_LICENSE)]) {
        [[QMLicense shared] reload];
    }
}

void QMRegisterNotifications(void) {
    CFNotificationCenterRef c = CFNotificationCenterGetDarwinNotifyCenter();
    NSArray *names = @[ @(QMV_NOTIFY_RELOAD), @(QMV_NOTIFY_RESTART), @(QMV_NOTIFY_CLEAR),
                        @(QMV_NOTIFY_PAUSE), @(QMV_NOTIFY_LIVE), @(QMV_NOTIFY_LICENSE) ];
    static char kObserverToken;   // 稳定指针，绝不能用临时 NSString 的桥接指针
    for (NSString *n in names) {
        CFNotificationCenterAddObserver(c, &kObserverToken, QMNotifyCallback,
                                        (__bridge CFStringRef)n, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        QMLog(@"[vcam] Registered for notification: %@", n);
    }
}

// mediaserverd 里没有 UI，靠轻量轮询把 plist 改动同步进来
static dispatch_source_t gPollTimer;

void QMStartStatePolling(void) {
    if (gPollTimer) return;
    gPollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(gPollTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                              (uint64_t)(1.2 * NSEC_PER_SEC), (uint64_t)(0.2 * NSEC_PER_SEC));
    __block BOOL lastLive = NO;
    __block NSString *lastPath = nil;
    dispatch_source_set_event_handler(gPollTimer, ^{
        QMState *st = [QMState shared];
        [st load];
        BOOL live = st.live;
        NSString *path = st.activePath;
        if (live != lastLive) {
            lastLive = live;
            QMLog(@"[vcam] Live state changed to: %@", live ? @"YES" : @"NO");
            [[QMCore shared] setActive:live reason:@"polling"];
        }
        if (path && ![path isEqualToString:lastPath ?: @""]) {
            lastPath = path;
            [[QMCore shared] reloadMedia];
        }
    });
    dispatch_resume(gPollTimer);
    QMLog(@"[vcam] State polling timer started");
}
