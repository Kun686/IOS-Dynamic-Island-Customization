//
//  HUDMainWindow.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import "HUDMainWindow.h"
#import "IKController.h"

@implementation HUDMainWindow

+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest {
    // 不能按启动时的透明度决定是否透传。窗口创建时胶囊尚未出现，
    // 否则后续显示时仍会被旧的全局透传挡住手势。
    return NO;
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
