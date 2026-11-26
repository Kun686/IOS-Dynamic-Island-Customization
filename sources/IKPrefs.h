#import <UIKit/UIKit.h>

#define IKPrefsPath @"/var/mobile/Library/Preferences/com.islandkit.prefs.plist"
#define IKPrefsChangedDarwin "com.islandkit.prefs/changed"
// 设置界面点了某个过渡动画：悬浮进程用当前配置把“出现 → 停留 → 收起”演示一遍
#define IKDemoTransitionDarwin "com.islandkit.demo/transition"
#define IKDataDir @"/var/mobile/Library/IslandKit"

// 系统各层在 SpringBoard 里的场景层级（iOS 16.6 的 SpringBoard.framework 里读到的常量）：
//   系统岛的内容（专辑图、波形等）    10000002
//   开孔处的黑色遮罩和隐私指示灯      11000002
// 悬浮窗用 10000010 就已经在系统岛内容之上、遮罩之下。
#define IKWindowLevelStandard   10000010.0
#define IKWindowLevelHigher    100000000.0
#define IKWindowLevelHighest  2147483000.0

@interface IKPrefs : NSObject
+ (instancetype)shared;
- (void)reload;

@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL notifEnabled;
@property (nonatomic) BOOL lyricEnabled;
@property (nonatomic) BOOL spinEnabled;
@property (nonatomic) BOOL pauseStopsSpin;
@property (nonatomic) NSInteger lyricLines;      // 1 或 2
@property (nonatomic) double spinSeconds;        // 转一圈用时
@property (nonatomic) double notifDuration;      // 通知停留秒数
@property (nonatomic, copy) NSSet<NSString *> *notifApps;
@property (nonatomic, strong) UIColor *accent;
@property (nonatomic, strong) UIColor *notifTitleColor;
@property (nonatomic, strong) UIColor *notifMessageColor;

// 开孔（系统岛待机时的黑色胶囊）在竖屏坐标里的位置和大小。默认按机型识别，可在设置里微调
@property (nonatomic) CGFloat islandTop;
@property (nonatomic) CGFloat cutoutWidth;
@property (nonatomic) CGFloat cutoutHeight;

// 覆盖模式下，胶囊比开孔多出来的量：宽、高各自的总和（两侧平分），以及整体上下偏移
@property (nonatomic) CGFloat coverExtraWidth;   // 默认 3
@property (nonatomic) CGFloat coverExtraHeight;  // 默认 3
@property (nonatomic) CGFloat coverOffsetY;      // 默认 0。只在覆盖模式下起作用
// 覆盖模式的紧凑态按自己的排版在开孔两侧各伸出多少，默认 66（只能在 plist 里改）。
// 实际宽度还会被加宽到盖住系统岛，见 IKController 的 coverWidthNeededForHeight:
@property (nonatomic) CGFloat coverCompactSide;
// 校准：在这个时刻（Unix 时间）之前，悬浮进程在开孔位置画出覆盖范围的描边
@property (nonatomic) double calibrateUntil;

// 过渡动画。0 回弹下落；1 柔和滑入；2 淡入；3 缩放弹出；4 果冻
@property (nonatomic) NSInteger transitionStyle;
// 悬浮窗层级。0 自动（覆盖模式用最高、下挂模式用标准）；1 更高；2 最高。
// 改动后悬浮进程会立即按新层级重新挂载窗口
@property (nonatomic) NSInteger windowLevelBoost;
+ (double)windowLevelFromFile;

// 往 /var/mobile/Library/IslandKit/island.log 追加一行诊断信息
+ (void)log:(NSString *)message;

// 显示位置。0：挂在系统岛下方（默认，不遮挡系统岛和状态栏时间）；1：盖在系统岛上
@property (nonatomic) NSInteger placement;
@property (nonatomic) BOOL progressRing;         // 播放进度沿胶囊边缘走一圈

// 颜色模式。0：用强调色；1：跟随专辑封面；2：自定义；3：默认白色（只用于歌名）
@property (nonatomic) NSInteger lyricColorMode;
@property (nonatomic) NSInteger titleColorMode;
@property (nonatomic) NSInteger ringColorMode;
@property (nonatomic, strong) UIColor *lyricColor;   // 自定义歌词颜色
@property (nonatomic, strong) UIColor *titleColor;   // 自定义歌名颜色
@property (nonatomic, strong) UIColor *ringColor;    // 自定义进度环颜色
@property (nonatomic) NSInteger lyricEffect;         // 0 无；1 逐行填色（卡拉OK式）；2 淡入
@property (nonatomic) CGFloat lyricFontSize;         // 默认 16
@property (nonatomic) CGFloat belowTop;          // 下挂模式的顶部位置，默认 54
@end
