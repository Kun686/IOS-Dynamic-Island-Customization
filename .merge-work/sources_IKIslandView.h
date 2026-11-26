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

<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.h
// 黑色胶囊。覆盖模式下盖在开孔上，内容只放在开孔两侧和下方
=======
// 盖在硬件开孔上的黑色胶囊。内容只放在开孔两侧和下方
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.h
@interface IKIslandView : UIView
@property (nonatomic) IKState state;
@property (nonatomic) NSInteger lyricLines;
@property (nonatomic) CGFloat cutoutWidth;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.h
// 覆盖模式下，开孔下沿在本视图坐标里的位置；文字要放到它下面
@property (nonatomic) CGFloat cutoutBand;
=======
@property (nonatomic) CGFloat cutoutHeight;
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.h
@property (nonatomic, strong) UIColor *accent;
@property (nonatomic, readonly) IKCoverView *cover;

- (void)setLine1:(NSString *)l1 line2:(NSString *)l2;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.h
// 文字外观。歌名和歌词各用各的颜色
=======
- (void)setLine1:(NSString *)l1 line2:(NSString *)l2;

// 歌词外观
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.h
// 歌词外观
@property (nonatomic, strong) UIColor *lyricColor;
<<<<<<< sources/IKIslandView.h
@property (nonatomic, strong) UIColor *songTitleColor;
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.h
@property (nonatomic, strong) UIColor *ringColor;
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.h
@property (nonatomic, strong) UIColor *ringColor;
@property (nonatomic, strong) UIColor *notifTitleColor;
@property (nonatomic, strong) UIColor *notifMessageColor;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.h
// 通知：第一行标题，第二行正文。过长时截断
- (void)setNotifTitle:(NSString *)title message:(NSString *)message;
// 播放器没有上报歌词时：第一行歌名，第二行歌手。不填色，过长时来回滚动
- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle playing:(BOOL)playing;
// 一句带时间的歌词：换句时只有歌词这一行上滑切换，并在 lineDuration 内从左到右填色，
// 过长的歌词跟着填色进度向左滚动。title 是歌名，只在双行时显示在歌词上方，不参与歌词的动画。
=======
// 显示一行带时间的歌词：换行时上滑切换，当前行在 lineDuration 内从左到右填色。
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.h
           lineDuration:(double)lineDuration elapsed:(double)elapsed playing:(BOOL)playing;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.h
- (void)setLyric:(NSString *)lyric title:(NSString *)title
    lineDuration:(double)lineDuration elapsed:(double)elapsed playing:(BOOL)playing;

=======
- (void)setLyricCurrent:(NSString *)current next:(NSString *)next
           lineDuration:(double)lineDuration elapsed:(double)elapsed playing:(BOOL)playing;
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.h

// 播放进度环：沿胶囊边缘从顶部中点顺时针走，走满一圈表示这首歌播完
@property (nonatomic) BOOL showsProgress;
@property (nonatomic) CGFloat progress; // 0...1

// 通知出现时的过渡：图标弹入，文字依次上滑淡入
- (void)playNotifEntrance;
<<<<<<< sources/IKIslandView.h
- (void)playInteractionPulse;
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.h

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.h
@end
