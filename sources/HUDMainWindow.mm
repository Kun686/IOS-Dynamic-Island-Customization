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
- (BOOL)_ignoresHitTest { return [HUDRootViewController passthroughMode]; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    IKPrefs *prefs = [IKPrefs shared];
    if (prefs.enabled && prefs.placement != 0) {
        CGRect cutout = CGRectMake((self.bounds.size.width - prefs.cutoutWidth) / 2.0,
                                   prefs.islandTop,
                                   prefs.cutoutWidth,
                                   prefs.cutoutHeight);
        // 自定义胶囊覆盖开孔时优先接收自己的长按。胶囊隐藏或只覆盖开孔
        // 的区域仍交还给 SpringBoard，避免遮断系统灵动岛的交互。
        if (CGRectContainsPoint(CGRectInset(cutout, -6, -4), point)
            && ![[IKController shared] shouldHandleTouchAtPoint:point]) return nil;
    }
    return [super hitTest:point withEvent:event];
}

@end
