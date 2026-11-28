//
//  MainApplicationDelegate.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import "MainApplicationDelegate.h"
#import "MainApplication.h"
#import "RootViewController.h"

#import "HUDHelper.h"
#import "TrollSpeed-Swift.h"

@implementation MainApplicationDelegate {
    RootViewController *_rootViewController;
}

- (instancetype)init {
    if (self = [super init]) {
        log_debug(OS_LOG_DEFAULT, "- [MainApplicationDelegate init]");
    }
    return self;
}

- (BOOL)application:(UIApplication *)application openURL:(nonnull NSURL *)url options:(nonnull NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    if ([url.scheme isEqualToString:@"trollspeed"]) {
        if ([url.host isEqualToString:@"toggle"]) {
            [self setupAndNotifyToggleHUDAfterLaunchWithAction:nil];
            return YES;
        } else if ([url.host isEqualToString:@"on"]) {
            [self setupAndNotifyToggleHUDAfterLaunchWithAction:kToggleHUDAfterLaunchNotificationActionToggleOn];
            return YES;
        } else if ([url.host isEqualToString:@"off"]) {
            [self setupAndNotifyToggleHUDAfterLaunchWithAction:kToggleHUDAfterLaunchNotificationActionToggleOff];
            return YES;
        }
    }
    return NO;
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler
{
    if ([shortcutItem.type isEqualToString:@"com.YiChen.LDDMH.shortcut.toggle-hud"])
    {
        [self setupAndNotifyToggleHUDAfterLaunchWithAction:nil];
    }
}

- (void)setupAndNotifyToggleHUDAfterLaunchWithAction:(NSString *)action
{
    if (!_rootViewController) {
        // IslandKit 界面下没有原来的主界面，快捷方式和 URL 直接开关悬浮进程
        if ([action isEqualToString:kToggleHUDAfterLaunchNotificationActionToggleOn]) SetHUDEnabled(YES);
        else if ([action isEqualToString:kToggleHUDAfterLaunchNotificationActionToggleOff]) SetHUDEnabled(NO);
        else SetHUDEnabled(!IsHUDEnabled());
        return;
    }
    [RootViewController setShouldToggleHUDAfterLaunch:YES];
    if (action) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kToggleHUDAfterLaunchNotificationName object:nil userInfo:@{
            kToggleHUDAfterLaunchNotificationActionKey: action,
        }];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:kToggleHUDAfterLaunchNotificationName object:nil];
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary <UIApplicationLaunchOptionsKey, id> *)launchOptions {
    log_debug(OS_LOG_DEFAULT, "- [MainApplicationDelegate application:%{public}@ didFinishLaunchingWithOptions:%{public}@]", application, launchOptions);

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    if (@available(iOS 16.0, *)) {
        // IslandKit：直接进入自己的界面，不再经过 TrollSpeed 原来的主界面
        [self.window setRootViewController:[IKSettingsFactory makeSettingsViewController]];
    } else {
        _rootViewController = [[RootViewController alloc] init];
        [self.window setRootViewController:_rootViewController];
    }
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    log_debug(OS_LOG_DEFAULT, "- [MainApplicationDelegate applicationDidBecomeActive:%{public}@]", application);

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf->_rootViewController reloadMainButtonState];
    });
}

@end
