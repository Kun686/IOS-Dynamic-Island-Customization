//
//  HUDMainWindow.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import "HUDMainWindow.h"
#import "HUDRootViewController.h"
#import "IKController.h"
#import "IKPrefs.h"

@implementation HUDMainWindow

+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest {
    // 全局透传会让自定义胶囊连 UIGestureRecognizer 都收不到。
    // 只有胶囊本身暂时关闭透传，其他位置仍在 hitTest 中返回 nil。
    return [HUDRootViewController passthroughMode] && ![[IKController shared] hasInteractiveIsland];
}
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    IKController *controller = [IKController shared];
    // 窗口铺满屏幕，但只有可见的自定义胶囊可以成为触摸目标。
    // 其他位置返回 nil，保持系统灵动岛和屏幕其他区域的事件路径。
    if (![controller shouldHandleTouchAtPoint:point]) return nil;
    return [super hitTest:point withEvent:event];
}

@end
