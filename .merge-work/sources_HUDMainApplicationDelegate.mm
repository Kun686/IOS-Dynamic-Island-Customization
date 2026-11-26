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

<<<<<<< sources/HUDMainApplicationDelegate.mm
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

||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/HUDMainApplicationDelegate.mm
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

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/HUDMainApplicationDelegate.mm
@implementation HUDMainApplicationDelegate {
    HUDRootViewController *_rootViewController;
    SBSAccessibilityWindowHostingController *_windowHostingController;
<<<<<<< sources/HUDMainApplicationDelegate.mm
    unsigned int _registeredContextID;
    double _registeredWindowLevel;
    BOOL _hasRegisteredWindow;
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/HUDMainApplicationDelegate.mm
    double _appliedWindowLevel;
}

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/HUDMainApplicationDelegate.mm
}

- (instancetype)init
{
    if (self = [super init])
    {
        log_debug(OS_LOG_DEFAULT, "- [HUDMainApplicationDelegate init]");
    }
    return self;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/HUDMainApplicationDelegate.mm
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

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/HUDMainApplicationDelegate.mm
