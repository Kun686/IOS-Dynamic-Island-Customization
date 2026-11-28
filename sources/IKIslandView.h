#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, IKState) {
    IKStateHidden = 0,
    IKStateMusicCompact,
    IKStateLyric,
    IKStateNotif,
};

// 圆角矩形（宽 w、高 h、圆角 r）的边上，从顶部中点顺时针走过全长 p 倍的那个点相对中心的角度，
// 12 点方向为 -π/2，顺时针增大，取值 [-π/2, 3π/2]。进度环的遮罩按它张开
FOUNDATION_EXTERN CGFloat IKRingAngle(CGFloat w, CGFloat h, CGFloat r, CGFloat p);

// 圆形封面，可匀速旋转、暂停和继续
@interface IKCoverView : UIView
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIColor *accent;
- (void)setSpinning:(BOOL)spinning period:(double)seconds;
@end

// 黑色胶囊。覆盖模式下盖在开孔上，内容只放在开孔两侧和下方
@interface IKIslandView : UIView
@property (nonatomic) IKState state;
@property (nonatomic) NSInteger lyricLines;
@property (nonatomic) NSInteger lyricAlignment;   // 0 左、1 中（按整个胶囊的中线）、2 右、3 自定义
@property (nonatomic) CGFloat lyricOffsetX;       // 自定义：文字中心相对胶囊中线的偏移，正数向右
@property (nonatomic) CGFloat lyricOffsetY;       // 自定义：上下偏移，正数向下
@property (nonatomic) CGFloat cutoutWidth;
// 覆盖模式下，开孔下沿在本视图坐标里的位置；文字要放到它下面
@property (nonatomic) CGFloat cutoutBand;
@property (nonatomic) BOOL coversCutout;   // YES：盖在开孔上，内容要避让；NO：独立胶囊，自由布局
@property (nonatomic, strong) UIColor *accent;
@property (nonatomic, readonly) IKCoverView *cover;

// 文字外观。歌名和歌词各用各的颜色
@property (nonatomic, strong) UIColor *lyricColor;
@property (nonatomic, strong) UIColor *titleColor;
@property (nonatomic, strong) UIColor *ringColor;
@property (nonatomic, strong) UIColor *notifTitleColor;
@property (nonatomic, strong) UIColor *notifMessageColor;
@property (nonatomic) NSInteger lyricEffect;   // 0 无；1 逐行填色；2 淡入
@property (nonatomic) CGFloat lyricFontSize;

// 通知：第一行标题，第二行正文。过长时截断
- (void)setNotifTitle:(NSString *)title message:(NSString *)message;
// 播放器没有上报歌词时：第一行歌名，第二行歌手。不填色，过长时来回滚动
- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle playing:(BOOL)playing;
// 一句带时间的歌词：换句时只有歌词这一行上滑切换，并在 lineDuration 内从左到右填色，
// 过长的歌词跟着填色进度向左滚动。title 是歌名，只在双行时显示在歌词上方，不参与歌词的动画。
// lineDuration <= 0 表示没有时间信息（整行直接高亮）
- (void)setLyric:(NSString *)lyric title:(NSString *)title
    lineDuration:(double)lineDuration elapsed:(double)elapsed playing:(BOOL)playing;

// round：YES 时按头像显示成圆形，NO 时按应用图标显示成圆角方形
- (void)setNotifIcon:(UIImage *)icon appName:(NSString *)app round:(BOOL)round;
- (void)setBarsAnimating:(BOOL)on;

// 播放进度环：沿胶囊边缘从顶部中点顺时针走，走满一圈表示这首歌播完。
// 胶囊形变时环跟着胶囊一起变（同一个动画），开关时淡入淡出
@property (nonatomic) BOOL showsProgress;
@property (nonatomic) CGFloat progress; // 0...1

// 通知出现时的过渡：图标弹入，文字依次上滑淡入
- (void)playNotifEntrance;

// 封面、文字、音柱和进度环的透明度，不影响黑色胶囊本身。收进开孔之前先把内容隐去
@property (nonatomic) CGFloat contentAlpha;
// 校准用：只画描边，不填充，方便和真正的系统岛对齐
@property (nonatomic) BOOL outlineOnly;
// 停掉胶囊和内容层上还在跑的形变、透明度动画（不影响歌词填色和封面旋转）
- (void)stopAnimations;
// 只停胶囊外形（和跟着它的进度环）的形变动画，透明度渐变照常走完
- (void)stopShellAnimations;
- (void)beginFollowingShell;
- (void)endFollowingShell;
- (void)hideContentImmediately;
// 换一类内容（音乐 ↔ 通知）前调用：旧内容留一张快照淡出，真正的内容先隐去，等过渡把新内容淡入
- (void)crossfadeContent;
// 点击或长按后给一个轻微回弹，确认交互已经被悬浮进程收到。
- (void)playInteractionPulse;
@end
