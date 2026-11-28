#import <UIKit/UIKit.h>
#import "IKMusicCenter.h"

// 测试桩：可以随意改写的“正在播放”信息
@interface IKMusicCenter (Harness)
- (void)h_setTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album
          duration:(double)duration playing:(BOOL)playing;
- (void)h_setArtworkColor:(UIColor *)color;
@end

@interface HarnessHUD : NSObject
// 在 window 里搭一个和悬浮进程一样的环境：模拟的系统岛 + 岛的容器
+ (void)installInWindow:(UIWindow *)window overrides:(NSDictionary *)prefs systemCompact:(BOOL)compact;
+ (void)setPauseGrace:(double)seconds;
// 模拟系统岛变成这几块（屏幕坐标）：重画灰色的模拟系统岛，并像 SpringBoard 那样通知 IKSystemIslandMonitor
+ (void)setSystemFrames:(NSArray<NSValue *> *)frames;
+ (NSString *)describeIsland;
+ (BOOL)expandedContentFitsPresentation;
+ (BOOL)expandedRowsVisible;
// 两行文字各自的宽度、文字宽度、承载文字的 track 此刻（按正在显示的状态）在行内的左右边缘、填色比例
+ (NSString *)describeRows;
// 屏幕尺寸、系统私有接口给的开孔矩形、IKPrefs 最终采用的开孔
+ (NSString *)describeGeometry;
// 按此刻正在显示的状态检查：胶囊有没有把 sys（屏幕坐标）整个盖住；进度环是不是和胶囊同尺寸、同圆角。
// 没问题返回 nil，否则返回描述。胶囊几乎透明时不检查覆盖
+ (nullable NSString *)coverageProblemForSystemRect:(CGRect)sys;
+ (nullable NSString *)ringProblem;
// 进度环此刻实际的不透明度（ringHolder × ringBox）
+ (double)ringOpacity;
// 第一行文字中心相对胶囊中线的偏移（屏幕坐标），用来看“居中”和“自定义”
+ (double)firstRowCenterOffset;
@end
