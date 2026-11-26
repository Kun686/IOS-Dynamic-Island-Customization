#import "IKController.h"
#import "IKIslandView.h"
#import "IKPrefs.h"
#import "IKMusicCenter.h"
#import "IKNotificationSource.h"

#pragma mark - 系统岛的实际位置

// SpringBoardServices 里的私有类：把系统岛各部分此刻的位置推给观察者。
// 系统自己的辅助功能界面（AccessibilityUIService 的 AXUIDisplayManager）就是这样跟踪系统岛的。
// 连接需要权限 com.apple.springboard.system-component-layout-monitoring，没有的话 SpringBoard 会直接断开。
// iOS 16.6 和 18.7 的 SpringBoardServices 里都有下面这几个方法。
// （声明直接写在这里：Xcode 工程按文件引用找头文件，放进 headers/ 的新文件它找不到）
@protocol SBSSystemApertureLayoutMonitoring <NSObject>
// frames 里是 NSValue 包着的 CGRect，屏幕坐标（竖屏）。系统岛待机时只有一项，就是开孔那块
- (void)systemApertureLayoutDidChange:(NSArray *)frames;
@end

@interface SBSSystemApertureLayoutMonitor : NSObject
- (void)addObserver:(id<SBSSystemApertureLayoutMonitoring>)observer;
- (void)removeObserver:(id<SBSSystemApertureLayoutMonitoring>)observer;
- (void)invalidate;
@end

NSString *const IKSystemIslandDidChangeNotification = @"IKSystemIslandDidChangeNotification";

@interface IKSystemIslandMonitor () <SBSSystemApertureLayoutMonitoring>
@property (nonatomic, copy) NSArray<NSValue *> *frames;
@property (nonatomic, strong) SBSSystemApertureLayoutMonitor *monitor;
@end

@implementation IKSystemIslandMonitor

+ (instancetype)shared {
    static IKSystemIslandMonitor *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IKSystemIslandMonitor new]; });
    return s;
}

- (void)start {
    if (self.monitor) return;
    // 用类名取，不直接引用符号：系统里没有这个类时只是拿到 nil
    Class cls = NSClassFromString(@"SBSSystemApertureLayoutMonitor");
    if (!cls || ![cls instancesRespondToSelector:@selector(addObserver:)]) {
        [IKPrefs log:@"system island monitor: class unavailable, using worst-case widths"];
        return;
    }
    @try {
        self.monitor = [[cls alloc] init];
        [self.monitor addObserver:self];
        [IKPrefs log:@"system island monitor: started"];
    } @catch (NSException *e) {
        self.monitor = nil;
        [IKPrefs log:[NSString stringWithFormat:@"system island monitor: failed to start (%@)", e.name]];
    }
}

- (void)systemApertureLayoutDidChange:(NSArray *)frames {
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    if ([frames isKindOfClass:[NSArray class]]) {
        for (id v in frames) {
            if (![v isKindOfClass:[NSValue class]]) continue;
            const char *type = [(NSValue *)v objCType];
            if (type && strcmp(type, @encode(CGRect)) == 0) [rects addObject:v];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.frames && [self.frames isEqualToArray:rects]) return;
        self.frames = rects;
        NSMutableString *line = [NSMutableString stringWithString:@"system island frames:"];
        for (NSValue *v in rects) [line appendFormat:@" %@", NSStringFromCGRect(v.CGRectValue)];
        [IKPrefs log:line];
        [[NSNotificationCenter defaultCenter] postNotificationName:IKSystemIslandDidChangeNotification object:self];
    });
}

@end

#pragma mark - 控制器

@interface IKController ()
@property (nonatomic, weak) UIView *container;
@property (nonatomic, strong) IKIslandView *island;
@property (nonatomic, strong) IKCoverView *miniCover;   // 听歌时来通知：封面缩成旁边的小圆
@property (nonatomic, strong) UIView *miniHolder;

@property (nonatomic) BOOL notifActive;
@property (nonatomic) NSUInteger notifToken;
@property (nonatomic, copy) NSString *notifBundle;
@property (nonatomic, copy) NSString *notifAppName;
@property (nonatomic, copy) NSString *notifTitle;
@property (nonatomic, copy) NSString *notifMessage;

@property (nonatomic) BOOL userCollapsed;               // 用户点了一下，把歌词态收成紧凑态
@property (nonatomic) CFAbsoluteTime pauseGraceUntil;   // 暂停后再显示几秒
@property (nonatomic) CFAbsoluteTime pausedAt;          // 暂停的时刻，没在暂停时为 0。暂停期间歌词的进度不往前走
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

// 过渡动画演示：出现 → 停留 → 收起，之后回到正常状态
@property (nonatomic) BOOL demoActive;
@property (nonatomic) BOOL demoRetracting;
@property (nonatomic) NSUInteger demoToken;
@property (nonatomic) CFAbsoluteTime demoStartedAt;
@property (nonatomic) BOOL outlineShown;                 // 正在显示校准描边
@property (nonatomic) NSUInteger transitionToken;        // 每开始一次过渡加一，用来作废上一次过渡的收尾
@property (nonatomic) BOOL hideInFlight;                 // 正在收起，还没隐藏
- (void)musicChanged;
- (void)update;
- (void)playTransitionDemo;
@end

static void IKPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef i) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[IKPrefs shared] reload];
        IKController *ctl = [IKController shared];
        [ctl musicChanged];
    });
}

static void IKDemoRequested(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef i) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[IKController shared] playTransitionDemo];
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
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.45;
    longPress.allowableMovement = 18;
    [tap requireGestureRecognizerToFail:longPress];
    [self.island addGestureRecognizer:tap];
    [self.island addGestureRecognizer:longPress];

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
    [nc addObserver:self selector:@selector(update) name:IKSystemIslandDidChangeNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKPrefsChanged,
                                    CFSTR(IKPrefsChangedDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKDemoRequested,
                                    CFSTR(IKDemoTransitionDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    [[IKMusicCenter shared] start];
    [[IKNotificationSource shared] start];
    [[IKSystemIslandMonitor shared] start];
    [self update];
}

#pragma mark 音乐

- (void)musicChanged {
    IKMusicCenter *m = [IKMusicCenter shared];

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (self.wasPlaying && !m.isPlaying) {
        self.pausedAt = now;
        self.pauseGraceUntil = now + 8;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self update];
        });
    } else if (m.isPlaying && self.pausedAt > 0) {
        // 继续播放：把当前这句歌词的起点顺延暂停的时长，填色和滚动从停下的地方接着走
        self.lyricChangedAt += now - self.pausedAt;
        self.pausedAt = 0;
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
    if (m.lyricsBridgeActive) {
        // 注入插件已经提供了带时间轴的歌词，不能再从歌名、歌手和专辑的变化猜测顺序。
        self.lyricField = 0;
        return;
    }
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
        if (self.pausedAt > 0) self.pausedAt = self.lyricChangedAt;
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
    IKMusicCenter *m = [IKMusicCenter shared];
    if (m.lyricsBridgeActive) {
        [self.island setLyric:m.bridgeLyric
                         title:(m.bridgeTitle ?: m.title)
                  lineDuration:m.bridgeLyricDuration
                       elapsed:m.bridgeLyricElapsed
                       playing:m.isPlaying];
        return;
    }
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
        [self.island setTitle:m.title subtitle:(m.artist ?: @"") playing:m.isPlaying];
        return;
    }
    // 系统只给“当前这一句”，没有下一句，也没有每句的时长，所以填色时长按最近几句的间隔估计
    double dur = self.lyricInterval > 0 ? MAX(1.5, MIN(self.lyricInterval, 8)) : 4;
    CFAbsoluteTime ref = (!m.isPlaying && self.pausedAt > 0) ? self.pausedAt : CFAbsoluteTimeGetCurrent();
    double elapsed = MAX(0, ref - self.lyricChangedAt);
    [self.island setLyric:lyric title:(song ?: @"") lineDuration:dur elapsed:elapsed playing:m.isPlaying];
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
    if (mode == 3) return [UIColor whiteColor];
    return p.accent;
}

// 每 0.25 秒：推进歌词，更新进度环
- (void)tick {
    IKMusicCenter *m = [IKMusicCenter shared];
    [m advanceLyricsBridge];
    [self trackLyricFields];
    if (self.island.state == IKStateLyric && !self.demoActive) [self refreshLyricText];
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

- (NSUInteger)showNotificationWithBundle:(NSString *)bundleID appName:(NSString *)appName
                             title:(NSString *)title message:(NSString *)message avatar:(UIImage *)avatar {
    return [self showNotificationWithBundle:bundleID appName:appName title:title message:message
                                     avatar:avatar avatarIsSender:(avatar != nil)];
}

- (NSUInteger)showNotificationWithBundle:(NSString *)bundleID appName:(NSString *)appName
                             title:(NSString *)title message:(NSString *)message avatar:(UIImage *)avatar
                     avatarIsSender:(BOOL)avatarIsSender {
    self.notifBundle = bundleID;
    self.notifAppName = appName;
    self.notifTitle = title.length ? title : appName;
    self.notifMessage = message;
    UIImage *icon = avatar;
    if (!icon && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:[UIScreen mainScreen].scale];
    }
    [self.island setNotifIcon:icon appName:appName round:avatarIsSender];

    self.notifActive = YES;
    NSUInteger token = ++self.notifToken;
    [self update];
    [self.island playNotifEntrance];
    double stay = [IKPrefs shared].notifDuration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token == self.notifToken) [self dismissNotification];
    });
    return token;
}

- (void)updateNotificationAvatar:(UIImage *)avatar
                        forBundle:(NSString *)bundleID
                            title:(NSString *)title
                          message:(NSString *)message
                            token:(NSUInteger)token {
    if (token != 0 && token != self.notifToken) return;
    if (!avatar || !self.notifActive || ![self.notifBundle isEqualToString:bundleID]
        || ![self.notifTitle isEqualToString:(title.length ? title : self.notifAppName)]
        || ![self.notifMessage isEqualToString:message]) return;
    [self.island setNotifIcon:avatar appName:self.notifAppName round:YES];
}

- (void)updateNotificationAvatar:(UIImage *)avatar
                        forBundle:(NSString *)bundleID
                            title:(NSString *)title
                          message:(NSString *)message {
    [self updateNotificationAvatar:avatar forBundle:bundleID title:title message:message token:0];
}

- (void)dismissNotification {
    self.notifActive = NO;
    self.notifToken++;
    [self update];
}

- (void)tapped {
    [IKPrefs log:[NSString stringWithFormat:@"interaction tap state=%ld notif=%d",
                  (long)self.shownState, self.notifActive]];
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

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    if (self.notifActive) {
        [self dismissNotification];
        [IKPrefs log:@"interaction longPress dismissNotification"];
    } else if (self.shownState == IKStateLyric || self.shownState == IKStateMusicCompact) {
        self.userCollapsed = !self.userCollapsed;
        [self update];
        [self.island playInteractionPulse];
        [IKPrefs log:[NSString stringWithFormat:@"interaction longPress state=%@",
                      self.userCollapsed ? @"compact" : @"lyric"]];
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback prepare];
        [feedback impactOccurred];
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

- (BOOL)shouldHandleTouchAtPoint:(CGPoint)point {
    if (!self.island || self.island.hidden || self.island.alpha < 0.01 || !self.container) return NO;
    UIWindow *window = self.container.window;
    if (!window) return NO;
    CGPoint localPoint = [self.container convertPoint:point fromView:window];
    CGRect islandFrame = [self.island convertRect:self.island.bounds toView:self.container];
    return CGRectContainsPoint(CGRectInset(islandFrame, -8, -8), localPoint);
}

- (CGFloat)screenWidth {
    CGSize ss = self.container ? self.container.bounds.size : [UIScreen mainScreen].bounds.size;
    return MIN(ss.width, ss.height);
}

// 开孔（系统岛待机时的黑色胶囊）在容器里的位置。
// “上下位置”是覆盖模式的校准项（设置里只在覆盖模式下出现），下挂模式不受它影响
- (CGRect)cutoutRect {
    IKPrefs *p = [IKPrefs shared];
    CGFloat top = p.islandTop + (p.placement != 0 ? p.coverOffsetY : 0);
    return CGRectMake(([self screenWidth] - p.cutoutWidth) / 2, top, p.cutoutWidth, p.cutoutHeight);
}

// 覆盖模式下胶囊在开孔处的范围：比开孔稍大一圈，多出多少可以在设置里调
- (CGRect)coverBaseRect {
    IKPrefs *p = [IKPrefs shared];
    CGRect c = [self cutoutRect];
    CGFloat w = MAX(40, c.size.width + p.coverExtraWidth), h = MAX(20, c.size.height + p.coverExtraHeight);
    return CGRectMake(CGRectGetMidX(c) - w / 2, CGRectGetMidY(c) - h / 2, w, h);
}

// 收起后的位置：整个缩进开孔里面，四周各留 3pt。
// 这块地方要么是屏幕上的物理开孔，要么被系统画的黑色遮罩盖着，所以收起后的胶囊不会露出来
- (CGRect)tuckedRect {
    return CGRectInset([self cutoutRect], 3, 3);
}

// 系统岛此刻的样子。known 为 NO 表示读不到（没有监视接口，或者还没收到过）
typedef struct {
    BOOL known;
    BOOL expanded;      // 比紧凑态高：长按展开、来电、面容解锁动画等
    CGFloat halfWidth;  // 从屏幕中线到系统岛最远一端的距离（系统岛分成两块时把两块都算上）
} IKSystemIslandState;

- (IKSystemIslandState)systemIslandState {
    IKSystemIslandState state = { NO, NO, 0 };
    NSArray<NSValue *> *frames = [IKSystemIslandMonitor shared].frames;
    if (![frames isKindOfClass:[NSArray class]] || frames.count == 0) return state;
    CGFloat sw = [self screenWidth];
    CGRect cutout = [self cutoutRect];
    for (NSValue *v in frames) {
        CGRect f = v.CGRectValue;
        if (CGRectIsEmpty(f) || CGRectGetMinY(f) > 120) continue;
        if (f.size.height > cutout.size.height + 14) state.expanded = YES;
        state.halfWidth = MAX(state.halfWidth, MAX(sw / 2 - CGRectGetMinX(f), CGRectGetMaxX(f) - sw / 2));
    }
    state.known = state.halfWidth > 0;
    return state;
}

// 覆盖模式下，要把系统岛的紧凑显示完全盖住，高 height 的胶囊至少得多宽。
// 读得到系统岛的位置就按实际大小算；读不到就按最宽的情况算：
// 系统岛紧凑态的上限是 屏宽 − 73.33（SBUISystemApertureLayoutMetrics 的 maximumCompactSize）
- (CGFloat)coverWidthNeededForHeight:(CGFloat)height {
    IKPrefs *p = [IKPrefs shared];
    CGFloat sw = [self screenWidth];
    IKSystemIslandState sys = [self systemIslandState];
    CGFloat w = sys.known ? 2 * sys.halfWidth : sw - 73.33;
    // 胶囊的圆角比系统岛的大时（歌词、通知态的圆角是 36，系统岛是高度的一半 18.33），
    // 只比系统岛宽一点点是不够的：系统岛圆头的“肩膀”会从胶囊的圆角外面露出来。
    // 这里算出还要再宽多少，才能让系统岛的圆头整个落在胶囊的圆角以内
    CGFloat R = MIN(height / 2, 36), r = p.cutoutHeight / 2, y0 = MAX(0, p.coverExtraHeight / 2);
    CGFloat shoulder = 0;
    if (R > r + y0) {
        CGFloat dy = R - r - y0;
        shoulder = 2 * ((R - r) - sqrt(MAX(0, (R - r) * (R - r) - dy * dy)));
    }
    return MIN(sw - 12, w + shoulder + MAX(0, p.coverExtraWidth));
}

- (CGRect)frameForState:(IKState)state musicOn:(BOOL)musicOn {
    IKPrefs *p = [IKPrefs shared];
    CGFloat sw = [self screenWidth];
    if (state == IKStateHidden) return [self tuckedRect];
    CGFloat wide = MIN(sw - 40, 360);

    if (p.placement == 0) {
        // 下挂模式：系统岛照常显示，胶囊挂在它下面，不挡状态栏
        CGFloat w = wide, h = 58;
        if (state == IKStateMusicCompact) { w = 84; h = 34; }
        else if (state == IKStateLyric)   { h = (p.lyricLines >= 2) ? 58 : 46; }
        return CGRectMake((sw - w) / 2, p.belowTop, w, h);
    }

    // 覆盖模式：盖在开孔上。每个状态先按自己的排版定宽度，再保证不小于 coverWidthNeededForHeight:，
    // 所以系统岛的紧凑显示不管多宽都露不出来；系统岛展开时在 update 里让开，不在这里处理
    CGRect base = [self coverBaseRect];
    CGFloat w = base.size.width, h = base.size.height;
    switch (state) {
        case IKStateMusicCompact: w = base.size.width + 2 * p.coverCompactSide; break;
        case IKStateLyric:        w = wide; h += (p.lyricLines >= 2) ? 55 : 39; break;
        // 听歌时来通知：窄一些，右边放得下小封面时再把小封面显示出来
        case IKStateNotif:        w = musicOn ? MIN(wide, 300) : wide; h += 55; break;
        default: break;
    }
    w = MIN(sw - 12, MAX(w, [self coverWidthNeededForHeight:h]));
    return CGRectMake((sw - w) / 2, base.origin.y, w, h);
}

#pragma mark 过渡动画

static const UIViewAnimationOptions IKAnimOptions =
    UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;

// 不带动画地把岛摆到某个状态。先停掉还在跑的动画，否则它们的增量会叠在新位置上
- (void)snapIsland:(void (^)(IKIslandView *island))changes {
    self.transitionToken++;
    self.hideInFlight = NO;
    [self.island stopAnimations];
    [UIView performWithoutAnimation:^{
        self.island.transform = CGAffineTransformIdentity;
        changes(self.island);
        [self.island layoutIfNeeded];
    }];
}

- (void)snapHidden {
    CGRect tucked = [self tuckedRect];
    [self snapIsland:^(IKIslandView *island) {
        island.outlineOnly = NO;
        island.frame = tucked;
        island.alpha = 0;
        island.contentAlpha = 0;
    }];
    self.outlineShown = NO;
    self.miniHolder.alpha = 0;
}

// 出现：按用户选的风格。settle 里是 miniHolder 等跟着一起变的东西
- (void)appearToState:(IKState)target frame:(CGRect)frame alongside:(void (^)(void))settle {
    self.transitionToken++;
    NSInteger style = [IKPrefs shared].transitionStyle;
    CGRect tucked = [self tuckedRect];
    IKIslandView *island = self.island;

    if (style == 2 || style == 3) {
        // 淡入、缩放弹出：原地出现
        [self snapIsland:^(IKIslandView *v) {
            v.state = target;
            v.frame = frame;
            v.alpha = 0;
            v.contentAlpha = 1;
        }];
        if (style == 2) {
            [UIView animateWithDuration:0.3 delay:0 options:IKAnimOptions animations:^{
                island.alpha = 1;
                settle();
            } completion:nil];
        } else {
            island.transform = CGAffineTransformMakeScale(0.6, 0.6);
            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.58 initialSpringVelocity:0.8
                                options:IKAnimOptions animations:^{
                island.transform = CGAffineTransformIdentity;
                island.alpha = 1;
                settle();
            } completion:nil];
        }
        return;
    }

    // 回弹下落、柔和滑入、果冻：从开孔里面长出来，内容稍后淡入
    [self snapIsland:^(IKIslandView *v) {
        v.state = target;
        v.frame = tucked;
        v.alpha = 1;
        v.contentAlpha = 0;
    }];
    NSTimeInterval duration = 0.62;
    CGFloat damping = 0.62, velocity = 0.9;
    if (style == 1) { duration = 0.42; damping = 1.0; velocity = 0; }
    if (style == 4) { duration = 0.85; damping = 0.4; velocity = 1.2; }
    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:damping initialSpringVelocity:velocity
                        options:IKAnimOptions animations:^{
        island.frame = frame;
        [island layoutIfNeeded];
        settle();
    } completion:nil];
    [UIView animateWithDuration:0.22 delay:0.06 options:IKAnimOptions animations:^{
        island.contentAlpha = 1;
    } completion:nil];
}

// 消失：淡入和缩放风格原地消失；其余先隐去内容，再整个缩回开孔里面。
// 收尾（done）按时间触发，不挂在动画的完成回调上：动画块里只要有一个图层的动画走不完，
// 完成回调就不会来，胶囊会停在收起的位置却一直不隐藏
- (void)vanishWithDuration:(NSTimeInterval)duration completion:(void (^)(void))done {
    NSInteger style = [IKPrefs shared].transitionStyle;
    CGRect tucked = [self tuckedRect];
    IKIslandView *island = self.island;
    NSUInteger token = ++self.transitionToken;

    if (style == 2 || style == 3) {
        [UIView animateWithDuration:duration delay:0 options:IKAnimOptions | UIViewAnimationOptionCurveEaseIn animations:^{
            island.alpha = 0;
            if (style == 3) island.transform = CGAffineTransformMakeScale(0.7, 0.7);
            self.miniHolder.alpha = 0;
        } completion:nil];
    } else {
        [UIView animateWithDuration:duration * 0.45 delay:0 options:IKAnimOptions animations:^{
            island.contentAlpha = 0;
        } completion:nil];
        [UIView animateWithDuration:duration delay:0 options:IKAnimOptions | UIViewAnimationOptionCurveEaseIn animations:^{
            island.frame = tucked;
            [island layoutIfNeeded];
            self.miniHolder.alpha = 0;
        } completion:nil];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + 0.02) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self.transitionToken) return; // 期间已经开始了别的过渡
        island.transform = CGAffineTransformIdentity;
        if (done) done();
    });
}

// 设置界面点了某个过渡动画：用示例内容（没有在放歌时）把出现和收起各演示一遍
- (void)playTransitionDemo {
    if (!self.island) return;
    [[IKPrefs shared] reload];
    IKPrefs *p = [IKPrefs shared];
    if (!p.enabled || self.suspended || ![self isPortrait] || self.notifActive) return;

    NSUInteger token = ++self.demoToken;
    // 先瞬间收起，保证“出现”能从头播一遍
    [self snapHidden];
    self.shownState = IKStateHidden;
    self.demoRetracting = NO;
    self.demoActive = YES;
    self.demoStartedAt = CFAbsoluteTimeGetCurrent();
    [self update];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self.demoToken) return;
        self.demoActive = NO;
        self.demoRetracting = YES;
        [self update];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (token != self.demoToken) return;
            self.demoRetracting = NO;
            [self update];
        });
    });
}

#pragma mark 状态

- (void)update {
    if (!self.island) return;
    IKPrefs *p = [IKPrefs shared];
    IKMusicCenter *m = [IKMusicCenter shared];

    // 系统岛展开时（长按、来电等）让开：那时用户要看、要点的是系统岛
    BOOL usable = p.enabled && !self.suspended && [self isPortrait] && ![self systemIslandState].expanded;
    BOOL musicOn = usable && (p.lyricEnabled || p.spinEnabled) && m.hasTrack
        && (m.isPlaying || CFAbsoluteTimeGetCurrent() < self.pauseGraceUntil);
    BOOL demo = usable && self.demoActive && !self.notifActive;

    IKState target = IKStateHidden;
    if (usable && self.notifActive) target = IKStateNotif;
    else if (demo) target = IKStateLyric;
    else if (self.demoRetracting) target = IKStateHidden;
    else if (musicOn) target = (p.lyricEnabled && !self.userCollapsed) ? IKStateLyric : IKStateMusicCompact;

    // 内容
    CGRect frame = [self frameForState:target musicOn:musicOn];
    self.island.accent = p.accent;
    self.island.lyricLines = p.lyricLines;
    self.island.cutoutWidth = p.cutoutWidth;
    self.island.cutoutBand = CGRectGetMaxY([self cutoutRect]) - CGRectGetMinY([self coverBaseRect]);
    self.island.coversCutout = (p.placement != 0);
    self.island.cover.image = m.artwork;
    self.miniCover.image = m.artwork;
    self.miniCover.accent = p.accent;

    if (m.artwork != self.colorSourceImage) {
        self.colorSourceImage = m.artwork;
        self.artworkColor = [self dominantColorOfImage:m.artwork];
    }
    self.island.lyricColor = [self colorForMode:p.lyricColorMode custom:p.lyricColor];
    self.island.titleColor = [self colorForMode:p.titleColorMode custom:p.titleColor];
    self.island.ringColor = [self colorForMode:p.ringColorMode custom:p.ringColor];
    self.island.notifTitleColor = p.notifTitleColor;
    self.island.notifMessageColor = p.notifMessageColor;
    self.island.lyricEffect = p.lyricEffect;
    self.island.lyricFontSize = p.lyricFontSize;

    BOOL playing = m.isPlaying || (demo && !musicOn);
    BOOL spin = p.spinEnabled && (playing || !p.pauseStopsSpin);
    [self.island.cover setSpinning:spin period:p.spinSeconds];
    [self.miniCover setSpinning:spin period:p.spinSeconds];
    [self.island setBarsAnimating:playing];

    if (target == IKStateNotif) {
        [self.island setNotifTitle:self.notifTitle message:self.notifMessage];
    } else if (demo && !musicOn) {
        // 没有在放歌：用一句示例歌词，顺便能看到歌名和歌词各自的颜色、填色和滚动
        [self.island setLyric:@"这是一句用来演示过渡动画和逐行填色效果的示例歌词"
                        title:@"歌名 - 歌手"
                 lineDuration:1.8
                      elapsed:MAX(0, CFAbsoluteTimeGetCurrent() - self.demoStartedAt - 0.3)
                      playing:YES];
    } else if (target == IKStateLyric) {
        [self refreshLyricText];
    }
    BOOL musicShown = (target == IKStateLyric || target == IKStateMusicCompact) && !(demo && !musicOn);
    self.island.showsProgress = p.progressRing && musicShown && m.duration > 0;
    if (musicShown && m.duration > 0) self.island.progress = [m currentElapsed] / m.duration;
    [self setLyricTimerRunning:(musicShown && m.isPlaying)];

    // 下挂模式里系统岛自己还在显示音乐，不需要旁边的小封面。
    // 覆盖模式下，胶囊为了盖住系统岛被加宽到右边放不下小封面时也不显示
    CGRect cutout = [self cutoutRect];
    CGRect mini = CGRectMake(CGRectGetMaxX(frame) + 6, cutout.origin.y, cutout.size.height, cutout.size.height);
    BOOL showMini = (target == IKStateNotif) && musicOn && (p.placement != 0)
        && CGRectGetMaxX(mini) <= [self screenWidth] - 4;
    self.miniHolder.layer.cornerRadius = cutout.size.height / 2;
    self.miniCover.frame = CGRectInset(CGRectMake(0, 0, cutout.size.height, cutout.size.height), 5, 5);
    if (self.miniHolder.alpha == 0) self.miniHolder.frame = mini;
    void (^settleMini)(void) = ^{
        self.miniHolder.frame = mini;
        self.miniHolder.alpha = showMini ? 1 : 0;
    };

    IKState previous = self.shownState;
    self.shownState = target;

    if (target == IKStateHidden) {
        // 校准：在开孔位置画出覆盖范围的描边，方便在设置里对着真正的系统岛调大小
        double remaining = p.calibrateUntil - [NSDate date].timeIntervalSince1970;
        if (usable && p.placement != 0 && remaining > 0) {
            CGRect base = [self coverBaseRect];
            [self snapIsland:^(IKIslandView *island) {
                island.outlineOnly = YES;
                island.frame = base;
                island.alpha = 1;
                island.contentAlpha = 0;
            }];
            self.outlineShown = YES;
            self.miniHolder.alpha = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MIN(remaining, 600) + 0.1) * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self update]; });
            return;
        }
        if (self.outlineShown || (previous == IKStateHidden && self.island.alpha == 0)) {
            [self snapHidden];
            return;
        }
        if (self.hideInFlight) return; // 已经在收起了，等它收完
        self.hideInFlight = YES;
        [self vanishWithDuration:0.32 completion:^{
            if (self.shownState == IKStateHidden) [self snapHidden];
        }];
        return;
    }

    if (self.outlineShown) [self snapHidden];
    BOOL wasNotif = (previous == IKStateNotif), isNotif = (target == IKStateNotif);
    BOOL fromHidden = (previous == IKStateHidden || self.island.alpha == 0);

    if (fromHidden) {
        [self appearToState:target frame:frame alongside:settleMini];
    } else if (wasNotif != isNotif) {
        // 音乐和通知互相切换：先收起，再以新内容出现
        [self vanishWithDuration:0.2 completion:^{
            if (self.shownState != target) return; // 期间状态又变了，交给后一次 update
            [self appearToState:target frame:frame alongside:settleMini];
            if (isNotif) [self.island playNotifEntrance];
        }];
    } else {
        // 同类状态之间的大小变化
        self.transitionToken++;
        self.island.state = target;
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4
                            options:IKAnimOptions animations:^{
            self.island.frame = frame;
            self.island.alpha = 1;
            self.island.contentAlpha = 1;
            [self.island layoutIfNeeded];
            settleMini();
        } completion:nil];
    }
}

@end
