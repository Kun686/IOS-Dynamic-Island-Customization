#import <UIKit/UIKit.h>

// 状态机：决定岛现在显示什么。优先级：通知 > 音乐 > 隐藏
@interface IKController : NSObject
+ (instancetype)shared;
// 宿主（悬浮 HUD 进程的根视图）准备好后调用一次。container 应铺满屏幕、背景透明
- (void)attachToContainerView:(UIView *)container;

// 宿主在横屏等不适合显示时置为 YES，岛会收起；设置后需调用 refresh
@property (nonatomic) BOOL suspended;
- (void)refresh;

// 覆盖模式下，只有自定义胶囊可见时才接管对应触摸点。
// 其他开孔区域交还给系统灵动岛处理。
- (BOOL)shouldHandleTouchAtPoint:(CGPoint)point;

// 该应用的通知是否由岛接管
- (BOOL)shouldTakeBundle:(NSString *)bundleID;
// avatar：发送者头像，没有就传 nil，会改用应用图标
- (void)showNotificationWithBundle:(NSString *)bundleID
                           appName:(NSString *)appName
                             title:(NSString *)title
                           message:(NSString *)message
                            avatar:(UIImage *)avatar;
@end
