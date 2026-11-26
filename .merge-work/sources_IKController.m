#import "IKController.h"
#import "IKIslandView.h"
#import "IKPrefs.h"
#import "IKMusicCenter.h"
#import "IKNotificationSource.h"
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKController.m

#pragma mark - 系统岛的实际位置

// SpringBoardServices 里的私有类：把系统岛各部分此刻的位置推给观察者。
// 系统自己的辅助功能界面（AccessibilityUIService 的 AXUIDisplayManager）就是这样跟踪系统岛的。
// 连接需要权限 com.apple.springboard.system-component-layout-monitoring，没有的话 SpringBoard 会直接断开。
// iOS 16.6 和 18.7 的 SpringBoardServices 里都有下面这几个方法。
// （声明直接写在这里：Xcode 工程按文件引用找头文件，放进 headers/ 的新文件它找不到）
@protocol SBSSystemApertureLayoutMonitoring <NSObject>
// frames 里是 NSValue 包着的 CGRect，屏幕坐标（竖屏）。系统岛待机时只有一项，就是开孔那块
- (void)systemApertureLayoutDidChange:(NSArray *)frames;
@end

@interface SBSSystemApertureLayoutMonitor : NSObject
- (void)addObserver:(id<SBSSystemApertureLayoutMonitoring>)observer;
- (void)removeObserver:(id<SBSSystemApertureLayoutMonitoring>)observer;
- (void)invalidate;
@end

NSString *const IKSystemIslandDidChangeNotification = @"IKSystemIslandDidChangeNotification";

@interface IKSystemIslandMonitor () <SBSSystemApertureLayoutMonitoring>
@property (nonatomic, copy) NSArray<NSValue *> *frames;
@property (nonatomic, strong) SBSSystemApertureLayoutMonitor *monitor;
@end

@implementation IKSystemIslandMonitor

+ (instancetype)shared {
    static IKSystemIslandMonitor *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IKSystemIslandMonitor new]; });
    return s;
}

- (void)start {
    if (self.monitor) return;
    // 用类名取，不直接引用符号：系统里没有这个类时只是拿到 nil
    Class cls = NSClassFromString(@"SBSSystemApertureLayoutMonitor");
    if (!cls || ![cls instancesRespondToSelector:@selector(addObserver:)]) {
        [IKPrefs log:@"system island monitor: class unavailable, using worst-case widths"];
        return;
    }
    @try {
        self.monitor = [[cls alloc] init];
        [self.monitor addObserver:self];
        [IKPrefs log:@"system island monitor: started"];
    } @catch (NSException *e) {
        self.monitor = nil;
        [IKPrefs log:[NSString stringWithFormat:@"system island monitor: failed to start (%@)", e.name]];
    }
}

- (void)systemApertureLayoutDidChange:(NSArray *)frames {
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    if ([frames isKindOfClass:[NSArray class]]) {
        for (id v in frames) {
            if (![v isKindOfClass:[NSValue class]]) continue;
            const char *type = [(NSValue *)v objCType];
            if (type && strcmp(type, @encode(CGRect)) == 0) [rects addObject:v];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.frames && [self.frames isEqualToArray:rects]) return;
        self.frames = rects;
        NSMutableString *line = [NSMutableString stringWithString:@"system island frames:"];
        for (NSValue *v in rects) [line appendFormat:@" %@", NSStringFromCGRect(v.CGRectValue)];
        [IKPrefs log:line];
        [[NSNotificationCenter defaultCenter] postNotificationName:IKSystemIslandDidChangeNotification object:self];
    });
}
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKController.m
    longPress.allowableMovement = 18;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKController.m
@end

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKController.m
