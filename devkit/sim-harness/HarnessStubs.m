#import "IKCoverLayout.h"
#import "HarnessStubs.h"
#import "IKController.h"
#import "IKPrefs.h"
#import "IKNotificationSource.h"
#import "IKIslandView.h"
#import <objc/runtime.h>

NSString *const IKMusicDidChangeNotification = @"IKMusicDidChangeNotification";

@interface IKMusicCenter ()
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic) BOOL isPlaying;
@property (nonatomic) double duration;
@property (nonatomic) double startedAt;
@property (nonatomic, strong) IKRecordingTracker *tracker;
@end

@implementation IKMusicCenter
+ (instancetype)shared { static IKMusicCenter *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [IKMusicCenter new]; }); return s; }
- (void)start {}
- (void)refresh {}
- (BOOL)refreshLyricsBridge { return NO; }
- (void)advanceLyricsBridge {}
+ (NSString *)playbackDiagnosticReport { return nil; }
+ (NSString *)sampleReportAtURL:(NSURL *)folder { return nil; }
+ (void)requestImportTarget:(void (^)(NSDictionary *))completion { completion(nil); }
+ (NSString *)importLyricsAtURL:(NSURL *)url target:(NSDictionary *)target { return @"测试桩没有播放器"; }
+ (NSString *)removeImport:(NSDictionary *)target { return @"测试桩没有播放器"; }
- (NSDictionary *)recording { return self.tracker.recording; }
- (NSString *)reportedLyric { return self.tracker.carLyric; }
- (BOOL)hasTrack { return self.title.length > 0; }
- (double)currentElapsed { return self.isPlaying ? CFAbsoluteTimeGetCurrent() - self.startedAt + 60 : 60; }
- (void)h_setTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album duration:(double)duration playing:(BOOL)playing {
    if (self.startedAt == 0) self.startedAt = CFAbsoluteTimeGetCurrent();
    if (!self.tracker) self.tracker = [IKRecordingTracker new];
    [self.tracker observe:IKTrackIdentity(nil,nil,title,artist,duration) album:album queueIndex:nil
                 position:@([self currentElapsed]) bundle:@"harness"];
    self.title = title; self.artist = artist; self.album = album; self.duration = duration; self.isPlaying = playing;
    [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:self];
}
- (void)h_setArtworkColor:(UIColor *)color {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60)];
    self.artwork = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill]; UIRectFill(CGRectMake(0, 0, 60, 60));
        [[UIColor whiteColor] setFill]; UIRectFill(CGRectMake(0, 26, 60, 8));
    }];
}
@end

@implementation IKNotificationSource
+ (instancetype)shared { static IKNotificationSource *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [IKNotificationSource new]; }); return s; }
- (void)start {}
@end

BOOL IsHUDEnabled(void) { return YES; }
void SetHUDEnabled(BOOL isEnabled) {}

static NSDictionary *gOverrides;
static UIView *gSystemLayer;   // 放模拟系统岛的那一层，在岛的容器下面
static IMP gOrigReload;
static void HarnessReload(IKPrefs *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigReload)(self, _cmd);
    [gOverrides enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) { [self setValue:v forKey:k]; }];
}

@implementation HarnessHUD

+ (void)installInWindow:(UIWindow *)window overrides:(NSDictionary *)prefs systemCompact:(BOOL)compact {
    gOverrides = prefs;
    Method m = class_getInstanceMethod([IKPrefs class], @selector(reload));
    gOrigReload = method_setImplementation(m, (IMP)HarnessReload);
    [[IKPrefs shared] reload];
    IKPrefs *p = [IKPrefs shared];

    UIView *root = window.rootViewController.view;
    root.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1];
    CGFloat sw = root.bounds.size.width;
    gSystemLayer = [[UIView alloc] initWithFrame:root.bounds];
    [root addSubview:gSystemLayer];
    // 模拟的系统岛（灰色，这样黑色的胶囊盖在上面或缩在里面都看得出来）。
    // compact：系统岛紧凑态（两侧各一个 62.33 宽的小视图），只画出来，不通知监视器
    CGFloat w = compact ? 250.67 : p.cutoutWidth;
    [self drawSystemFrames:@[[NSValue valueWithCGRect:CGRectMake((sw - w) / 2, p.islandTop, w, p.cutoutHeight)]]];
    UIView *container = [[UIView alloc] initWithFrame:root.bounds];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:container];
    [[IKController shared] attachToContainerView:container];
}

+ (NSString *)describeRows {
    IKIslandView *v = [[IKController shared] valueForKey:@"island"];
    NSMutableString *out = [NSMutableString string];
    for (NSString *key in @[@"row1", @"row2"]) {
        UIView *row = [v valueForKey:key];
        if (![row respondsToSelector:NSSelectorFromString(@"track")]) continue;
        UIView *track = [row valueForKey:@"track"];
        CALayer *shown = track.layer.presentationLayer ?: track.layer;
        CGRect f = shown.frame; // 在这一行自己的坐标系里
        CALayer *mask = [row valueForKey:@"fillMask"];
        CALayer *shownMask = mask.presentationLayer ?: mask;
        BOOL masked = mask != nil && [[row valueForKey:@"topLabel"] layer].mask == mask;
        NSString *fill = masked ? [NSString stringWithFormat:@"%.2f", [[shownMask valueForKeyPath:@"transform.scale.x"] doubleValue]] : @"-";
        [out appendFormat:@"%@[w=%.1f text=%.1f track=%.1f..%.1f fill=%@%@] ", key, row.bounds.size.width,
         [[row valueForKey:@"textWidth"] doubleValue], CGRectGetMinX(f), CGRectGetMaxX(f), fill, row.hidden ? @" hidden" : @""];
    }
    return out;
}

+ (NSString *)describeGeometry {
    UIScreen *screen = [UIScreen mainScreen];
    CGRect raw = CGRectNull;
    @try {
        if ([screen respondsToSelector:NSSelectorFromString(@"_exclusionArea")]) {
            id area = [screen valueForKey:@"_exclusionArea"];
            if (area && [area respondsToSelector:NSSelectorFromString(@"rect")]) {
                id value = [area valueForKey:@"rect"];
                if ([value isKindOfClass:[NSValue class]]) raw = [value CGRectValue];
            }
        }
    } @catch (__unused NSException *e) {}
    IKPrefs *p = [IKPrefs shared];
    return [NSString stringWithFormat:@"screen=%.0fx%.0f _exclusionArea=%@ used=(top %.2f, %.2f x %.2f)",
            screen.bounds.size.width, screen.bounds.size.height, CGRectIsNull(raw) ? @"none" : NSStringFromCGRect(raw),
            p.islandTop, p.cutoutWidth, p.cutoutHeight];
}

+ (void)drawSystemFrames:(NSArray<NSValue *> *)frames {
    for (UIView *v in gSystemLayer.subviews.copy) [v removeFromSuperview];
    IKPrefs *p = [IKPrefs shared];
    for (NSValue *value in frames) {
        CGRect f = value.CGRectValue;
        UIView *sys = [[UIView alloc] initWithFrame:f];
        sys.backgroundColor = [UIColor colorWithWhite:0.42 alpha:1];
        sys.layer.cornerRadius = MIN(f.size.height / 2, 36);
        [gSystemLayer addSubview:sys];
        if (f.size.width > p.cutoutWidth + 40) {
            // 两头各放一个带颜色的小块，露出来一眼就能看到
            UIView *art = [[UIView alloc] initWithFrame:CGRectMake(10, 7, 23, 23)];
            art.backgroundColor = [UIColor systemBlueColor]; art.layer.cornerRadius = 5;
            UIView *wave = [[UIView alloc] initWithFrame:CGRectMake(f.size.width - 34, 9, 22, 19)];
            wave.backgroundColor = [UIColor systemOrangeColor];
            [sys addSubview:art]; [sys addSubview:wave];
        }
    }
}

+ (void)setSystemFrames:(NSArray<NSValue *> *)frames {
    [self drawSystemFrames:frames];
    [[IKSystemIslandMonitor shared] systemApertureLayoutDidChange:frames];
}

+ (void)setPauseGrace:(double)seconds {
    [[IKController shared] setValue:@(CFAbsoluteTimeGetCurrent() + seconds) forKey:@"pauseGraceUntil"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((seconds + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[IKController shared] refresh];
    });
}

+ (BOOL)expandedContentFitsPresentation {
    IKIslandView *v = [[IKController shared] valueForKey:@"island"];
    if (!v.coversCutout || (v.state != IKStateLyric && v.state != IKStateNotif)) return YES;
    UIView *content = [v valueForKey:@"content"];
    CALayer *shell = v.layer.presentationLayer ?: v.layer;
    CALayer *shown = content.layer.presentationLayer ?: content.layer;
    UIView *row = [v valueForKey:@"row1"];
    if (row.hidden || content.hidden || shell.opacity * shown.opacity < 0.05) return YES;
    return IKCoverRows(shell.bounds.size, v.cutoutBand, v.state == IKStateNotif ? 70 : 76,
                       v.state == IKStateNotif || v.lyricLines >= 2).fits;
}

+ (BOOL)expandedRowsVisible {
    IKIslandView *v = [[IKController shared] valueForKey:@"island"];
    UIView *row = [v valueForKey:@"row1"], *content = [v valueForKey:@"content"];
    return !row.hidden && !content.hidden && (content.layer.presentationLayer ?: content.layer).opacity > 0.5;
}

+ (NSString *)describeIsland {
    IKIslandView *v = [[IKController shared] valueForKey:@"island"];
    CALayer *pl = v.layer.presentationLayer ?: v.layer;
    double ca = [v respondsToSelector:NSSelectorFromString(@"contentAlpha")] ? [[v valueForKey:@"contentAlpha"] doubleValue] : -1;
    return [NSString stringWithFormat:@"state=%ld shown=%@ frame=%@ pres=%@ alpha=%.2f contentAlpha=%.2f",
            (long)v.state, [[IKController shared] valueForKey:@"shownState"], NSStringFromCGRect(v.frame),
            NSStringFromCGRect(pl.frame), v.alpha, ca];
}
@end
