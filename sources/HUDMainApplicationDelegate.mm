//
//  HUDMainApplicationDelegate.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <objc/runtime.h>

#import "HUDMainApplicationDelegate.h"
#import "HUDHelper.h"
#import "HUDMainWindow.h"
#import "HUDRootViewController.h"
#import "IKPrefs.h"

#import "SBSAccessibilityWindowHostingController.h"
#import "UIWindow+Private.h"

@interface HUDMainApplicationDelegate ()
- (void)applyWindowLevel:(BOOL)force;
- (void)scheduleWindowLevelRegistrationRetries;
@end

static void IKWindowPrefsChanged(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    HUDMainApplicationDelegate *delegate = (__bridge HUDMainApplicationDelegate *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate applyWindowLevel:NO];
    });
}

@implementation HUDMainApplicationDelegate {
    HUDRootViewController *_rootViewController;
    SBSAccessibilityWindowHostingController *_windowHostingController;
    unsigned int _registeredContextID;
    double _registeredWindowLevel;
    BOOL _hasRegisteredWindow;
}

- (instancetype)init
{
    if (self = [super init])
    {
        log_debug(OS_LOG_DEFAULT, "- [HUDMainApplicationDelegate init]");
    }
    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary <UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    log_debug(OS_LOG_DEFAULT, "- [HUDMainApplicationDelegate application:%{public}@ didFinishLaunchingWithOptions:%{public}@]", application, launchOptions);

    // 悬浮进程是 root，之前建的数据目录归 root，设置 App 写不进去。启动时改回 mobile，
    // 这样设置 App 保存备用头像、歌词时间轴和诊断报告时不必再提权
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        BOOL repaired = IKRepairDataDirectory();
        [IKPrefs log:[NSString stringWithFormat:@"dataDirectory repaired=%d uid=%d", repaired, getuid()]];
    });

    _rootViewController = [[HUDRootViewController alloc] init];

    self.window = [[HUDMainWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self.window setRootViewController:_rootViewController];
    // 先设置 UIKit 层级，再让窗口可见，避免启动瞬间被系统灵动岛压在下面。
    [self.window setWindowLevel:[IKPrefs windowLevelFromFile]];
    _windowHostingController = [[objc_getClass("SBSAccessibilityWindowHostingController") alloc] init];
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self,
                                    IKWindowPrefsChanged, CFSTR(IKPrefsChangedDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    [IKPrefs log:[NSString stringWithFormat:@"touchPassthrough configured=%d",
                  [HUDRootViewController passthroughMode]]];
    [self applyWindowLevel:NO];
    [self scheduleWindowLevelRegistrationRetries];

    return YES;
}

- (void)applyWindowLevel:(BOOL)force {
    if (!self.window) return;
    double windowLevel = [IKPrefs windowLevelFromFile];
    [self.window setWindowLevel:windowLevel];

    SEL selector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    if (!_windowHostingController || ![_windowHostingController respondsToSelector:selector]) {
        [IKPrefs log:@"windowLevel registration unavailable"];
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    unsigned int contextId = [self.window _contextId];
    if (contextId == 0) {
        [IKPrefs log:@"windowLevel context unavailable"];
        return;
    }

    // 设置页会在滑块拖动时连续发通知。相同上下文和层级已经登记成功时跳过，
    // 只有真正改变层级或窗口上下文时才重新登记。
    SEL unregisterSelector = NSSelectorFromString(@"unregisterWindowWithContextID:");
    if (!force && _hasRegisteredWindow && _registeredContextID == contextId
        && fabs(_registeredWindowLevel - windowLevel) < 0.5) {
        return;
    }
    if (_hasRegisteredWindow && [_windowHostingController respondsToSelector:unregisterSelector]) {
        NSMethodSignature *unregisterSignature = [NSMethodSignature signatureWithObjCTypes:"v@:I"];
        NSInvocation *unregisterInvocation = [NSInvocation invocationWithMethodSignature:unregisterSignature];
        [unregisterInvocation setTarget:_windowHostingController];
        [unregisterInvocation setSelector:unregisterSelector];
        [unregisterInvocation setArgument:&_registeredContextID atIndex:2];
        [unregisterInvocation invoke];
    }

    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_windowHostingController];
    [invocation setSelector:selector];
    [invocation setArgument:&contextId atIndex:2];
    [invocation setArgument:&windowLevel atIndex:3];
    [invocation invoke];
    _registeredContextID = contextId;
    _registeredWindowLevel = windowLevel;
    _hasRegisteredWindow = YES;
#pragma clang diagnostic pop
    [IKPrefs log:[NSString stringWithFormat:@"windowLevel applied=%.0f context=%u", windowLevel, contextId]];
}

- (void)scheduleWindowLevelRegistrationRetries {
    // 启动早期窗口可能已有 context ID，但 SpringBoard 尚未完成登记。
    // 这些是有限的强制重试，避免首次登记被系统启动时序吞掉。
    NSArray<NSNumber *> *delays = @[@0.15, @0.45, @1.0, @2.0, @4.0];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self applyWindowLevel:YES]; });
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [self applyWindowLevel:NO];
    [self scheduleWindowLevelRegistrationRetries];
}

@end
