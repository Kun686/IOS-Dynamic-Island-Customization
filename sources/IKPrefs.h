#import <UIKit/UIKit.h>

#define IKPrefsPath @"/var/mobile/Library/Preferences/com.islandkit.prefs.plist"
#define IKPrefsChangedDarwin "com.islandkit.prefs/changed"
#define IKDataDir @"/var/mobile/Library/IslandKit"

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

// 岛的几何参数，不同机型可在 plist 里微调
@property (nonatomic) CGFloat islandTop;         // 默认 11
@property (nonatomic) CGFloat cutoutWidth;       // 默认按机型自动识别
@property (nonatomic) CGFloat cutoutHeight;

// 过渡动画。0 回弹下落；1 柔和滑入；2 淡入；3 缩放弹出；4 果冻
@property (nonatomic) NSInteger transitionStyle;
// 悬浮窗层级。0 默认；1 更高；2 最高（改后需重启悬浮进程）
@property (nonatomic) NSInteger windowLevelBoost;
+ (double)windowLevelFromFile;

// 往 /var/mobile/Library/IslandKit/island.log 追加一行诊断信息
+ (void)log:(NSString *)message;

// 显示位置。0：挂在系统岛下方（默认，不遮挡系统岛和状态栏时间）；1：盖在系统岛上
@property (nonatomic) NSInteger placement;
@property (nonatomic) BOOL progressRing;         // 播放进度沿胶囊边缘走一圈

// 颜色模式。0：用强调色；1：跟随专辑封面；2：自定义
@property (nonatomic) NSInteger lyricColorMode;
@property (nonatomic) NSInteger ringColorMode;
@property (nonatomic, strong) UIColor *lyricColor;   // 自定义歌词颜色
@property (nonatomic, strong) UIColor *ringColor;    // 自定义进度环颜色
@property (nonatomic) NSInteger lyricEffect;         // 0 无；1 逐行填色（卡拉OK式）；2 淡入
@property (nonatomic) CGFloat lyricFontSize;         // 默认 16
@property (nonatomic) CGFloat belowTop;          // 下挂模式的顶部位置，默认 54
@end
