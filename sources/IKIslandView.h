#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, IKState) {
    IKStateHidden = 0,
    IKStateMusicCompact,
    IKStateLyric,
    IKStateNotif,
};

// 圆形封面，可匀速旋转、暂停和继续
@interface IKCoverView : UIView
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIColor *accent;
- (void)setSpinning:(BOOL)spinning period:(double)seconds;
@end

// 盖在硬件开孔上的黑色胶囊。内容只放在开孔两侧和下方
@interface IKIslandView : UIView
@property (nonatomic) IKState state;
@property (nonatomic) NSInteger lyricLines;
@property (nonatomic) CGFloat cutoutWidth;
@property (nonatomic) CGFloat cutoutHeight;
@property (nonatomic) BOOL coversCutout;   // YES：盖在开孔上，内容要避让；NO：独立胶囊，自由布局
@property (nonatomic, strong) UIColor *accent;
@property (nonatomic, readonly) IKCoverView *cover;

- (void)setLine1:(NSString *)l1 line2:(NSString *)l2;

// 歌词外观
@property (nonatomic, strong) UIColor *lyricColor;
@property (nonatomic, strong) UIColor *ringColor;
@property (nonatomic) NSInteger lyricEffect;   // 0 无；1 逐行填色；2 淡入
@property (nonatomic) CGFloat lyricFontSize;

// 显示一行带时间的歌词：换行时上滑切换，当前行在 lineDuration 内从左到右填色。
// lineDuration <= 0 表示没有时间信息（整行直接高亮）
- (void)setLyricCurrent:(NSString *)current next:(NSString *)next
           lineDuration:(double)lineDuration elapsed:(double)elapsed playing:(BOOL)playing;
// round：YES 时按头像显示成圆形，NO 时按应用图标显示成圆角方形
- (void)setNotifIcon:(UIImage *)icon appName:(NSString *)app round:(BOOL)round;
- (void)setBarsAnimating:(BOOL)on;

// 播放进度环：沿胶囊边缘从顶部中点顺时针走，走满一圈表示这首歌播完
@property (nonatomic) BOOL showsProgress;
@property (nonatomic) CGFloat progress; // 0...1

// 通知出现时的过渡：图标弹入，文字依次上滑淡入
- (void)playNotifEntrance;
@end
