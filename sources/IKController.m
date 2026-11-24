#import "IKController.h"
#import "IKIslandView.h"
#import "IKPrefs.h"
#import "IKMusicCenter.h"
#import "IKNotificationSource.h"

#pragma mark - 控制器

@interface IKController ()
@property (nonatomic, weak) UIView *container;
@property (nonatomic, strong) IKIslandView *island;
@property (nonatomic, strong) IKCoverView *miniCover;   // 听歌时来通知：封面缩成旁边的小圆
@property (nonatomic, strong) UIView *miniHolder;

@property (nonatomic) BOOL notifActive;
@property (nonatomic) NSUInteger notifToken;
@property (nonatomic, copy) NSString *notifBundle;
@property (nonatomic, copy) NSString *notifTitle;
@property (nonatomic, copy) NSString *notifMessage;

@property (nonatomic) BOOL userCollapsed;               // 用户点了一下，把歌词态收成紧凑态
@property (nonatomic) CFAbsoluteTime pauseGraceUntil;   // 暂停后再显示几秒
@property (nonatomic) BOOL wasPlaying;

// 歌词直接来自系统“正在播放”信息：有的播放器会把当前这句歌词写进标题、歌手或专辑字段。
// 同一首歌（时长不变）期间哪个字段在变，哪个就是歌词
@property (nonatomic) double trackDuration;
@property (nonatomic, copy) NSString *lastTitle;
@property (nonatomic, copy) NSString *lastArtist;
@property (nonatomic, copy) NSString *lastAlbum;
@property (nonatomic, copy) NSString *trackTitleBaseline;
@property (nonatomic, copy) NSString *trackArtistBaseline;
@property (nonatomic, copy) NSString *trackAlbumBaseline;
@property (nonatomic) NSInteger titleChanges;
@property (nonatomic) NSInteger artistChanges;
@property (nonatomic) NSInteger albumChanges;
@property (nonatomic) NSInteger lyricField;             // 0 未发现；1 标题；2 歌手；3 专辑
@property (nonatomic) CFAbsoluteTime lyricChangedAt;
@property (nonatomic) double lyricInterval;             // 最近几句的平均间隔，用来估计填色时长
@property (nonatomic, strong) NSTimer *lyricTimer;
@property (nonatomic, strong) UIImage *colorSourceImage; // 已经取过主色的封面
@property (nonatomic, strong) UIColor *artworkColor;
@property (nonatomic) IKState shownState;
- (void)musicChanged;
- (void)update;
@end

static void IKPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef i) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[IKPrefs shared] reload];
        IKController *ctl = [IKController shared];
        [ctl musicChanged];
    });
}

@implementation IKController

+ (instancetype)shared {
    static IKController *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IKController new]; });
    return s;
}

- (void)attachToContainerView:(UIView *)container {
    if (self.island) return;
    self.container = container;

    self.island = [IKIslandView new];
    self.island.alpha = 0;
    [container addSubview:self.island];
    [self.island addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];

    self.miniHolder = [UIView new];
    self.miniHolder.backgroundColor = [UIColor blackColor];
    self.miniHolder.alpha = 0;
    self.miniHolder.userInteractionEnabled = NO;
    self.miniCover = [IKCoverView new];
    [self.miniHolder addSubview:self.miniCover];
    [container addSubview:self.miniHolder];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(musicChanged) name:IKMusicDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(update) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKPrefsChanged,
                                    CFSTR(IKPrefsChangedDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    [[IKMusicCenter shared] start];
    [[IKNotificationSource shared] start];
    [self update];
}

#pragma mark 音乐

- (void)musicChanged {
    IKMusicCenter *m = [IKMusicCenter shared];

    if (self.wasPlaying && !m.isPlaying) {
        self.pauseGraceUntil = CFAbsoluteTimeGetCurrent() + 8;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self update];
        });
    }
    self.wasPlaying = m.isPlaying;

    [self trackLyricFields];
    [self update];
}

static BOOL IKSame(NSString *a, NSString *b) {
    return [(a ?: @"") isEqualToString:(b ?: @"")];
}

// 找出哪个字段在承载歌词
- (void)trackLyricFields {
    IKMusicCenter *m = [IKMusicCenter shared];
    BOOL sameTrack = m.duration > 0 && self.trackDuration > 0 && fabs(m.duration - self.trackDuration) < 1.5;
    if (!sameTrack) {
        // 换歌了：重新观察
        self.trackDuration = m.duration;
        self.trackTitleBaseline = m.title;
        self.trackArtistBaseline = m.artist;
        self.trackAlbumBaseline = m.album;
        self.titleChanges = self.artistChanges = self.albumChanges = 0;
        self.lyricField = 0;
        self.lyricInterval = 0;
        self.lyricChangedAt = CFAbsoluteTimeGetCurrent();
        [IKPrefs log:[NSString stringWithFormat:@"track duration=%.0f title.len=%lu artist.len=%lu album.len=%lu",
                      m.duration, (unsigned long)m.title.length, (unsigned long)m.artist.length, (unsigned long)m.album.length]];
    } else {
        BOOL t = !IKSame(m.title, self.lastTitle), a = !IKSame(m.artist, self.lastArtist), al = !IKSame(m.album, self.lastAlbum);
        if (t) self.titleChanges++;
        if (a) self.artistChanges++;
        if (al) self.albumChanges++;

        // 只选择已经偏离本首歌初始元数据、并且变化次数最多的字段。
        // 这样标题、歌手或专辑中的系统歌词一出现就能切换，不再等待第二次变化。
        NSInteger field = self.lyricField;
        NSInteger bestChanges = 0;
        if (!IKSame(m.title, self.trackTitleBaseline) && self.titleChanges > bestChanges) {
            field = 1; bestChanges = self.titleChanges;
        }
        if (!IKSame(m.artist, self.trackArtistBaseline) && self.artistChanges > bestChanges) {
            field = 2; bestChanges = self.artistChanges;
        }
        if (!IKSame(m.album, self.trackAlbumBaseline) && self.albumChanges > bestChanges) {
            field = 3; bestChanges = self.albumChanges;
        }
        if (field != self.lyricField) {
            self.lyricField = field;
            [IKPrefs log:[NSString stringWithFormat:@"lyric field=%ld (1 title, 2 artist, 3 album)", (long)field]];
        }

        BOOL lyricChanged = (field == 1 && t) || (field == 2 && a) || (field == 3 && al);
        if (lyricChanged) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            double gap = now - self.lyricChangedAt;
            if (gap > 0.5 && gap < 15) self.lyricInterval = self.lyricInterval > 0 ? self.lyricInterval * 0.6 + gap * 0.4 : gap;
            self.lyricChangedAt = now;
        }
    }
    self.lastTitle = m.title;
    self.lastArtist = m.artist;
    self.lastAlbum = m.album;
}

- (void)refreshLyricText {
    [self refreshLyricForce:YES];
}

- (void)refreshLyricForce:(BOOL)force {
    IKMusicCenter *m = [IKMusicCenter shared];
    NSString *lyric = nil, *song = nil;
    NSString *baseline = nil;
    switch (self.lyricField) {
        case 1: lyric = m.title;  song = m.artist; baseline = self.trackTitleBaseline; break;
        case 2: lyric = m.artist; song = m.title;  baseline = self.trackArtistBaseline; break;
        case 3: lyric = m.album;  song = m.artist.length ? [NSString stringWithFormat:@"%@ - %@", m.title ?: @"", m.artist] : m.title; baseline = self.trackAlbumBaseline; break;
        default: break;
    }
    if (lyric.length == 0 || IKSame(lyric, baseline)) {
        // 播放器没有上报歌词（或者间奏）：第一行歌名，第二行歌手
        [self.island setLine1:m.title line2:(m.artist ?: @"")];
        return;
    }
    // 第一行是当前这句歌词，带填色；第二行是歌名。
    // 系统只给“当前这一句”，没有下一句，也没有每句的时长，所以填色时长按最近几句的间隔估计
    double dur = self.lyricInterval > 0 ? MAX(1.5, MIN(self.lyricInterval, 8)) : 4;
    double elapsed = MAX(0, CFAbsoluteTimeGetCurrent() - self.lyricChangedAt);
    [self.island setLyricCurrent:lyric next:(song ?: @"") lineDuration:dur elapsed:elapsed playing:m.isPlaying];
}

// 从封面里取一个醒目的主色，用于歌词和进度环
- (UIColor *)dominantColorOfImage:(UIImage *)image {
    if (!image.CGImage) return nil;
    const int N = 24;
    uint8_t px[N * N * 4];
    memset(px, 0, sizeof(px));
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, N, N, 8, N * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextDrawImage(ctx, CGRectMake(0, 0, N, N), image.CGImage);
    CGContextRelease(ctx);

    // 按色相分 12 档，按“鲜艳程度 × 亮度”加权，取分数最高的一档
    double score[12] = {0}, sr[12] = {0}, sg[12] = {0}, sb[12] = {0};
    for (int i = 0; i < N * N; i++) {
        CGFloat r = px[i * 4] / 255.0, g = px[i * 4 + 1] / 255.0, b = px[i * 4 + 2] / 255.0;
        CGFloat hue, sat, bri, al;
        if (![[UIColor colorWithRed:r green:g blue:b alpha:1] getHue:&hue saturation:&sat brightness:&bri alpha:&al]) continue;
        if (bri < 0.2 || sat < 0.25) continue;
        int bin = MIN(11, (int)(hue * 12));
        double w = sat * bri;
        score[bin] += w; sr[bin] += r * w; sg[bin] += g * w; sb[bin] += b * w;
    }
    int best = -1;
    for (int i = 0; i < 12; i++) if (score[i] > 0 && (best < 0 || score[i] > score[best])) best = i;
    if (best < 0) return [UIColor whiteColor]; // 黑白封面
    UIColor *avg = [UIColor colorWithRed:sr[best] / score[best] green:sg[best] / score[best] blue:sb[best] / score[best] alpha:1];
    // 黑底上要看得清：亮度和饱和度设下限
    CGFloat hue, sat, bri, al;
    [avg getHue:&hue saturation:&sat brightness:&bri alpha:&al];
    return [UIColor colorWithHue:hue saturation:MIN(1, MAX(sat, 0.45)) brightness:MAX(bri, 0.9) alpha:1];
}

- (UIColor *)colorForMode:(NSInteger)mode custom:(UIColor *)custom {
    IKPrefs *p = [IKPrefs shared];
    if (mode == 1) return self.artworkColor ?: p.accent;
    if (mode == 2) return custom ?: p.accent;
    return p.accent;
}

// 每 0.25 秒：推进歌词，更新进度环
- (void)tick {
    IKMusicCenter *m = [IKMusicCenter shared];
    [self trackLyricFields];
    if (self.island.state == IKStateLyric) [self refreshLyricForce:NO];
    if (m.duration > 0) self.island.progress = [m currentElapsed] / m.duration;
}

- (void)setLyricTimerRunning:(BOOL)run {
    if (run && !self.lyricTimer) {
        self.lyricTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self
                                                         selector:@selector(tick) userInfo:nil repeats:YES];
    } else if (!run && self.lyricTimer) {
        [self.lyricTimer invalidate];
        self.lyricTimer = nil;
    }
}

#pragma mark 通知

- (BOOL)shouldTakeBundle:(NSString *)bundleID {
    IKPrefs *p = [IKPrefs shared];
    return self.island && p.enabled && p.notifEnabled && bundleID.length && [p.notifApps containsObject:bundleID]
        && !self.suspended && [self isPortrait];
}

- (void)showNotificationWithBundle:(NSString *)bundleID appName:(NSString *)appName
                             title:(NSString *)title message:(NSString *)message avatar:(UIImage *)avatar {
    self.notifBundle = bundleID;
    self.notifTitle = title.length ? title : appName;
    self.notifMessage = message;
    UIImage *icon = avatar;
    if (!icon && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:[UIScreen mainScreen].scale];
    }
    [self.island setNotifIcon:icon appName:appName round:(avatar != nil)];

    self.notifActive = YES;
    NSUInteger token = ++self.notifToken;
    [self update];
    [self.island playNotifEntrance];
    double stay = [IKPrefs shared].notifDuration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token == self.notifToken) [self dismissNotification];
    });
}

- (void)dismissNotification {
    self.notifActive = NO;
    self.notifToken++;
    [self update];
}

- (void)tapped {
    if (self.notifActive) {
        NSString *bid = self.notifBundle;
        [self dismissNotification];
        // 独立进程里没有 SpringBoard 的启动方法，改用 LSApplicationWorkspace 打开应用
        Class cls = NSClassFromString(@"LSApplicationWorkspace");
        SEL ws = NSSelectorFromString(@"defaultWorkspace");
        SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (bid && [cls respondsToSelector:ws]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id workspace = [cls performSelector:ws];
            if ([workspace respondsToSelector:open]) [workspace performSelector:open withObject:bid];
#pragma clang diagnostic pop
        }
    } else {
        self.userCollapsed = !self.userCollapsed;
        [self update];
    }
}

#pragma mark 布局与状态

- (void)refresh {
    [self update];
}

- (BOOL)isPortrait {
    // 宿主会让容器跟随屏幕方向，用容器的宽高判断即可
    CGSize size = self.container ? self.container.bounds.size : [UIScreen mainScreen].bounds.size;
    return size.width <= size.height;
}

- (CGRect)frameForState:(IKState)state musicOn:(BOOL)musicOn {
    IKPrefs *p = [IKPrefs shared];
    CGSize ss = self.container ? self.container.bounds.size : [UIScreen mainScreen].bounds.size;
    CGFloat sw = MIN(ss.width, ss.height);

    if (p.placement == 0) {
        // 下挂模式：系统岛照常显示，胶囊挂在它下面，不挡状态栏
        CGFloat wide = MIN(sw - 40, 360);
        CGFloat w = p.cutoutWidth, h = 20, y = p.belowTop;
        switch (state) {
            case IKStateMusicCompact: w = 84; h = 34; break;
            case IKStateLyric:        w = wide; h = (p.lyricLines >= 2) ? 58 : 46; break;
            case IKStateNotif:        w = wide; h = 58; break;
            default:                  y = p.islandTop + p.cutoutHeight / 2 - 2; break; // 收起时缩回系统岛背后
        }
        return CGRectMake((sw - w) / 2, y, w, h);
    }

    // 覆盖模式：盖在开孔上
    CGFloat wide = MIN(sw - 50, 340);
    // 比开孔四周各大 1pt，避免露出系统岛的边
    CGFloat ch = p.cutoutHeight + 2, top = p.islandTop - 1;
    CGFloat w = p.cutoutWidth + 2, h = ch;
    switch (state) {
        case IKStateMusicCompact: w = p.cutoutWidth + 120; break;
        case IKStateLyric:        w = wide; h = ch + ((p.lyricLines >= 2) ? 55 : 39); break;
        case IKStateNotif:        w = musicOn ? MIN(wide, 300) : wide; h = ch + 55; break;
        default: break;
    }
    return CGRectMake((sw - w) / 2, top, w, h);
}

- (void)update {
    if (!self.island) return;
    IKPrefs *p = [IKPrefs shared];
    IKMusicCenter *m = [IKMusicCenter shared];

    BOOL usable = p.enabled && !self.suspended && [self isPortrait];
    BOOL musicOn = usable && (p.lyricEnabled || p.spinEnabled) && m.hasTrack
        && (m.isPlaying || CFAbsoluteTimeGetCurrent() < self.pauseGraceUntil);

    IKState target = IKStateHidden;
    if (usable && self.notifActive) target = IKStateNotif;
    else if (musicOn) target = (p.lyricEnabled && !self.userCollapsed) ? IKStateLyric : IKStateMusicCompact;

    // 内容
    self.island.accent = p.accent;
    self.island.lyricLines = p.lyricLines;
    self.island.cutoutWidth = p.cutoutWidth;
    self.island.cutoutHeight = p.cutoutHeight;
    self.island.coversCutout = (p.placement != 0);
    self.island.cover.image = m.artwork;
    self.miniCover.image = m.artwork;
    self.miniCover.accent = p.accent;

    if (m.artwork != self.colorSourceImage) {
        self.colorSourceImage = m.artwork;
        self.artworkColor = [self dominantColorOfImage:m.artwork];
    }
    self.island.lyricColor = [self colorForMode:p.lyricColorMode custom:p.lyricColor];
    self.island.ringColor = [self colorForMode:p.ringColorMode custom:p.ringColor];
    self.island.lyricEffect = p.lyricEffect;
    self.island.lyricFontSize = p.lyricFontSize;

    BOOL spin = p.spinEnabled && (m.isPlaying || !p.pauseStopsSpin);
    [self.island.cover setSpinning:spin period:p.spinSeconds];
    [self.miniCover setSpinning:spin period:p.spinSeconds];
    [self.island setBarsAnimating:m.isPlaying];

    if (target == IKStateNotif) {
        [self.island setLine1:self.notifTitle line2:self.notifMessage];
    } else if (target == IKStateLyric) {
        [self refreshLyricText];
    }
    BOOL musicShown = (target == IKStateLyric || target == IKStateMusicCompact);
    self.island.showsProgress = p.progressRing && musicShown && m.duration > 0;
    if (musicShown && m.duration > 0) self.island.progress = [m currentElapsed] / m.duration;
    [self setLyricTimerRunning:(musicShown && m.isPlaying)];

    // 形变动画
    CGRect frame = [self frameForState:target musicOn:musicOn];
    // 下挂模式里系统岛自己还在显示音乐，不需要旁边的小封面
    BOOL showMini = (target == IKStateNotif) && musicOn && (p.placement != 0);
    CGRect mini = CGRectMake(CGRectGetMaxX(frame) + 6, p.islandTop, p.cutoutHeight, p.cutoutHeight);
    self.miniHolder.layer.cornerRadius = 18.5;
    self.miniCover.frame = CGRectMake(5, 5, 27, 27);
    if (self.miniHolder.alpha == 0) self.miniHolder.frame = mini;

    CGRect tucked = [self frameForState:IKStateHidden musicOn:NO]; // 缩在系统岛背后的位置
    if (p.placement != 0) tucked.origin.y = p.islandTop - 1;
    IKState previous = self.shownState;
    self.shownState = target;

    void (^settle)(void) = ^{
        self.island.frame = frame;
        self.island.alpha = (target == IKStateHidden) ? 0 : 1;
        [self.island layoutIfNeeded];
        self.miniHolder.frame = mini;
        self.miniHolder.alpha = showMini ? 1 : 0;
    };
    UIViewAnimationOptions opts = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;

    BOOL wasNotif = (previous == IKStateNotif), isNotif = (target == IKStateNotif);
    BOOL fromHidden = (previous == IKStateHidden || self.island.alpha == 0);
    NSInteger style = p.transitionStyle;

    // 出现：按用户选的风格
    void (^appear)(void) = ^{
        self.island.state = target;
        self.island.transform = CGAffineTransformIdentity;
        switch (style) {
            case 1: { // 柔和滑入：从岛背后滑下来，不回弹
                self.island.frame = tucked; self.island.alpha = 1; [self.island layoutIfNeeded];
                [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0
                                    options:opts animations:settle completion:nil];
                break;
            }
            case 2: { // 淡入：原地出现
                self.island.frame = frame; self.island.alpha = 0; [self.island layoutIfNeeded];
                [UIView animateWithDuration:0.3 delay:0 options:opts animations:settle completion:nil];
                break;
            }
            case 3: { // 缩放弹出：原地由小变大
                self.island.frame = frame; self.island.alpha = 0; [self.island layoutIfNeeded];
                self.island.transform = CGAffineTransformMakeScale(0.6, 0.6);
                [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.58 initialSpringVelocity:0.8
                                    options:opts animations:^{
                    self.island.transform = CGAffineTransformIdentity;
                    self.island.alpha = 1;
                    self.miniHolder.frame = mini;
                    self.miniHolder.alpha = showMini ? 1 : 0;
                } completion:nil];
                break;
            }
            case 4: { // 果冻：下落后明显晃几下
                self.island.frame = tucked; self.island.alpha = 1; [self.island layoutIfNeeded];
                [UIView animateWithDuration:0.85 delay:0 usingSpringWithDamping:0.4 initialSpringVelocity:1.2
                                    options:opts animations:settle completion:nil];
                break;
            }
            default: { // 回弹下落
                self.island.frame = tucked; self.island.alpha = 1; [self.island layoutIfNeeded];
                [UIView animateWithDuration:0.62 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.9
                                    options:opts animations:settle completion:nil];
                break;
            }
        }
    };
    // 消失：淡入和缩放风格原地消失，其余缩回岛里
    void (^vanish)(NSTimeInterval, void (^)(void)) = ^(NSTimeInterval duration, void (^done)(void)) {
        [UIView animateWithDuration:duration delay:0 options:opts | UIViewAnimationOptionCurveEaseIn animations:^{
            if (style == 2) {
                self.island.alpha = 0;
            } else if (style == 3) {
                self.island.alpha = 0;
                self.island.transform = CGAffineTransformMakeScale(0.7, 0.7);
            } else {
                self.island.frame = tucked;
                [self.island layoutIfNeeded];
            }
            self.miniHolder.alpha = 0;
        } completion:^(BOOL finished) {
            self.island.transform = CGAffineTransformIdentity;
            if (done) done();
        }];
    };

    if (target == IKStateHidden) {
        vanish(0.3, ^{
            if (self.shownState == IKStateHidden) self.island.alpha = 0;
        });
    } else if (fromHidden) {
        appear();
    } else if (wasNotif != isNotif) {
        // 音乐和通知互相切换：先收起，再以新内容出现
        vanish(0.2, ^{
            if (self.shownState != target) return; // 期间状态又变了，交给后一次 update
            appear();
            if (isNotif) [self.island playNotifEntrance];
        });
    } else {
        // 同类状态之间的大小变化
        self.island.state = target;
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4
                            options:opts animations:settle completion:nil];
    }
}

@end
