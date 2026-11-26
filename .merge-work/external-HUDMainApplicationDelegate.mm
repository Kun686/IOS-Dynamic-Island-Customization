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
- (void)applyWindowLevelIfChanged;
@end

static void IKWindowLevelPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                      const void *object, CFDictionaryRef userInfo)
{
    HUDMainApplicationDelegate *delegate = (__bridge HUDMainApplicationDelegate *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate applyWindowLevelIfChanged];
    });
}

@implementation HUDMainApplicationDelegate {
    HUDRootViewController *_rootViewController;
    SBSAccessibilityWindowHostingController *_windowHostingController;
    double _appliedWindowLevel;
}

- (instancetype)init
{
    if (self = [super init])
    {
        log_debug(OS_LOG_DEFAULT, "- [HUDMainApplicationDelegate init]");
    }
    return self;
}

// SpringBoard 为每个登记的窗口单独建一个场景，场景的层级就是这里传的 level
- (void)registerWindowAtLevel:(double)windowLevel
{
    unsigned int _contextId = [self.window _contextId];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    // [_windowHostingController registerWindowWithContextID:_contextId atLevel:windowLevel];
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_windowHostingController];
    [invocation setSelector:NSSelectorFromString(@"registerWindowWithContextID:atLevel:")];
    [invocation setArgument:&_contextId atIndex:2];
    [invocation setArgument:&windowLevel atIndex:3];
    [invocation invoke];
#pragma clang diagnostic pop

    _appliedWindowLevel = windowLevel;
    [IKPrefs log:[NSString stringWithFormat:@"windowLevel applied=%.0f context=%u", windowLevel, _contextId]];
}

// IslandKit：设置里改了层级就立即生效，不用重启悬浮进程。
// SpringBoard 对已经登记过的窗口不会更新层级（重复登记会被忽略），所以先注销，再按新层级登记
- (void)applyWindowLevelIfChanged
{
    if (!self.window || !_windowHostingController) return;
    double level = [IKPrefs windowLevelFromFile];
    if (fabs(level - _appliedWindowLevel) < 0.5) return;
    if (![_windowHostingController respondsToSelector:@selector(unregisterWindowWithContextID:)]) {
        [IKPrefs log:@"windowLevel change needs a restart: unregisterWindowWithContextID: is missing"];
        return;
    }
    [_windowHostingController unregisterWindowWithContextID:[self.window _contextId]];
    [self.window setWindowLevel:level];
    [self registerWindowAtLevel:level];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary <UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    log_debug(OS_LOG_DEFAULT, "- [HUDMainApplicationDelegate application:%{public}@ didFinishLaunchingWithOptions:%{public}@]", application, launchOptions);

    _rootViewController = [[HUDRootViewController alloc] init];

    self.window = [[HUDMainWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self.window setRootViewController:_rootViewController];
    
    // IslandKit：层级可在设置里调
    [self.window setWindowLevel:[IKPrefs windowLevelFromFile]];
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    _windowHostingController = [[objc_getClass("SBSAccessibilityWindowHostingController") alloc] init];
    [self registerWindowAtLevel:[self.window windowLevel]];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                    IKWindowLevelPrefsChanged, CFSTR(IKPrefsChangedDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    return YES;
}

@end
