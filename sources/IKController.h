#import <UIKit/UIKit.h>

extern NSString *const IKSystemIslandDidChangeNotification;

// 系统岛此刻的实际位置，来自 SpringBoard 的 SBSSystemApertureLayoutMonitor。
// 覆盖模式用它决定胶囊至少要多宽；系统岛展开（长按、来电等）时胶囊让开。
// 系统里没有这个类，或者连接被拒绝时，frames 一直是 nil，控制器改按最宽的情况留宽度
@interface IKSystemIslandMonitor : NSObject
+ (instancetype)shared;
- (void)start;
@property (nonatomic, copy, readonly) NSArray<NSValue *> *frames;
// SpringBoard 的回调入口（在它自己的队列上）；模拟器里的验证 App 也用它来模拟系统岛的变化
- (void)systemApertureLayoutDidChange:(NSArray *)frames;
@end

// 状态机：决定岛现在显示什么。优先级：通知 > 音乐 > 隐藏
@interface IKController : NSObject
+ (instancetype)shared;
// 宿主（悬浮 HUD 进程的根视图）准备好后调用一次。container 应铺满屏幕、背景透明
- (void)attachToContainerView:(UIView *)container;

// 宿主在横屏等不适合显示时置为 YES，岛会收起；设置后需调用 refresh
@property (nonatomic) BOOL suspended;
- (void)refresh;

// 只有自定义胶囊范围内的触摸交给悬浮进程，其余区域继续走系统事件路径。
- (BOOL)shouldHandleTouchAtPoint:(CGPoint)point;

// 该应用的通知是否由岛接管
- (BOOL)shouldTakeBundle:(NSString *)bundleID;
// avatar：发送者头像，没有就传 nil，会改用应用图标
- (NSUInteger)showNotificationWithBundle:(NSString *)bundleID
                           appName:(NSString *)appName
                             title:(NSString *)title
                           message:(NSString *)message
                            avatar:(UIImage *)avatar;
- (NSUInteger)showNotificationWithBundle:(NSString *)bundleID
                           appName:(NSString *)appName
                             title:(NSString *)title
                           message:(NSString *)message
                            avatar:(UIImage *)avatar
                    avatarIsSender:(BOOL)avatarIsSender;
- (BOOL)updateNotificationAvatar:(UIImage *)avatar
                        forBundle:(NSString *)bundleID
                            title:(NSString *)title
                          message:(NSString *)message
                            token:(NSUInteger)token;
- (void)updateNotificationAvatar:(UIImage *)avatar
                        forBundle:(NSString *)bundleID
                            title:(NSString *)title
                          message:(NSString *)message;
@end
