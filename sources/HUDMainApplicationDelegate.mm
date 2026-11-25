//
//  HUDMainApplicationDelegate.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <objc/runtime.h>

#import "HUDMainApplicationDelegate.h"
#import "HUDMainWindow.h"
#import "HUDRootViewController.h"
#import "IKPrefs.h"

#import "SBSAccessibilityWindowHostingController.h"
#import "UIWindow+Private.h"

@interface HUDMainApplicationDelegate ()
- (void)applyWindowLevel;
- (void)scheduleWindowLevelRegistrationRetries;
@end

static void IKWindowPrefsChanged(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    HUDMainApplicationDelegate *delegate = (__bridge HUDMainApplicationDelegate *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate applyWindowLevel];
    });
}

@implementation HUDMainApplicationDelegate {
    HUDRootViewController *_rootViewController;
    SBSAccessibilityWindowHostingController *_windowHostingController;
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

    _rootViewController = [[HUDRootViewController alloc] init];

    self.window = [[HUDMainWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self.window setRootViewController:_rootViewController];
    
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    _windowHostingController = [[objc_getClass("SBSAccessibilityWindowHostingController") alloc] init];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self,
                                    IKWindowPrefsChanged, CFSTR(IKPrefsChangedDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    [self applyWindowLevel];
    [self scheduleWindowLevelRegistrationRetries];

    return YES;
}

- (void)applyWindowLevel {
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

    // 同一窗口上下文在部分系统版本上不会因重复 register 自动更新层级。
    // 有注销接口时先注销再注册，没有接口时直接调用兼容的 register 方法。
    SEL unregisterSelector = NSSelectorFromString(@"unregisterWindowWithContextID:");
    if ([_windowHostingController respondsToSelector:unregisterSelector]) {
        NSMethodSignature *unregisterSignature = [NSMethodSignature signatureWithObjCTypes:"v@:I"];
        NSInvocation *unregisterInvocation = [NSInvocation invocationWithMethodSignature:unregisterSignature];
        [unregisterInvocation setTarget:_windowHostingController];
        [unregisterInvocation setSelector:unregisterSelector];
        [unregisterInvocation setArgument:&contextId atIndex:2];
        [unregisterInvocation invoke];
    }

    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_windowHostingController];
    [invocation setSelector:selector];
    [invocation setArgument:&contextId atIndex:2];
    [invocation setArgument:&windowLevel atIndex:3];
    [invocation invoke];
#pragma clang diagnostic pop
    [IKPrefs log:[NSString stringWithFormat:@"windowLevel applied=%.0f context=%u", windowLevel, contextId]];
}

- (void)scheduleWindowLevelRegistrationRetries {
    // 启动早期窗口可能已有 context ID，但 SpringBoard 尚未完成登记。
    // 这些是有限重试，避免常驻定时器和重复注册。
    NSArray<NSNumber *> *delays = @[@0.15, @0.45, @1.0, @2.0, @4.0];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self applyWindowLevel]; });
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [self applyWindowLevel];
    [self scheduleWindowLevelRegistrationRetries];
}

@end
