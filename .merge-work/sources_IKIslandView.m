#import "IKIslandView.h"

#pragma mark - 封面

@interface IKCoverView ()
@property (nonatomic, strong) UIImageView *disc;
@property (nonatomic, strong) UIView *hole;
@property (nonatomic) BOOL spinning;
@property (nonatomic) double period;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
@property (nonatomic) CGFloat restAngle;   // 停转时停在的角度，再转时从这里接着转
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m

@implementation IKCoverView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _period = 8;
        _disc = [UIImageView new];
        _disc.contentMode = UIViewContentModeScaleAspectFill;
        _disc.clipsToBounds = YES;
        _disc.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        [self addSubview:_disc];
        _hole = [UIView new];
        _hole.backgroundColor = [UIColor blackColor];
        [self addSubview:_hole];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat s = MIN(self.bounds.size.width, self.bounds.size.height);
    self.disc.bounds = CGRectMake(0, 0, s, s);
    self.disc.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    self.disc.layer.cornerRadius = s / 2;
    CGFloat h = MAX(4, s * 0.16);
    self.hole.bounds = CGRectMake(0, 0, h, h);
    self.hole.center = self.disc.center;
    self.hole.layer.cornerRadius = h / 2;
    self.hole.layer.borderWidth = 1;
    self.hole.layer.borderColor = (self.accent ?: [UIColor whiteColor]).CGColor;
}

- (void)setImage:(UIImage *)image {
    _image = image;
    self.disc.image = image;
}

- (void)setAccent:(UIColor *)accent {
    _accent = accent;
    [self setNeedsLayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self applySpin];
}

- (void)setSpinning:(BOOL)spinning period:(double)seconds {
    BOOL changed = self.spinning != spinning || fabs(seconds - self.period) > 0.01;
    self.spinning = spinning;
<<<<<<< sources/IKIslandView.m
    self.period = MAX(0.1, seconds);
    if (changed) [self applySpin];
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
    self.spinning = spinning;
    self.period = seconds;
=======
    self.period = seconds;
    if (periodChanged) [self.disc.layer removeAnimationForKey:@"ik.spin"];
    [self applySpin];
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m
}

<<<<<<< sources/IKIslandView.m
- (CGFloat)currentRotation {
    CALayer *layer = self.disc.layer;
    CALayer *presentation = layer.presentationLayer;
    CATransform3D transform = presentation ? presentation.transform : layer.transform;
    return atan2(transform.m12, transform.m11);
}

||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
}

// 停转：把当前转到的角度写进图层，再拿掉旋转动画。
// 不能用 layer.speed = 0 来暂停：图层被暂停后，UIKit 动画块里给它加的布局动画永远走不完，
// 那个动画块的完成回调也就永远不会来（之前“暂停后收起的胶囊一直留在屏幕上”就是这个原因）
- (void)freeze {
    CALayer *layer = self.disc.layer;
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m
- (void)applySpin {
    CALayer *layer = self.disc.layer;
<<<<<<< sources/IKIslandView.m
    CGFloat rotation = [self currentRotation];
    [layer removeAnimationForKey:@"ik.spin"];
    layer.speed = 1;
    layer.timeOffset = 0;
    layer.beginTime = 0;
    layer.transform = CATransform3DMakeRotation(rotation, 0, 0, 1);

    if (self.spinning && self.window) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        animation.fromValue = @(rotation);
        animation.toValue = @(rotation + M_PI * 2);
        animation.duration = self.period;
        animation.repeatCount = HUGE_VALF;
        animation.removedOnCompletion = NO;
        [layer addAnimation:animation forKey:@"ik.spin"];
    }
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
    CGFloat angle = [[shown valueForKeyPath:@"transform.rotation.z"] doubleValue];
    [layer removeAnimationForKey:@"ik.spin"];
    self.restAngle = angle;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer setValue:@(angle) forKeyPath:@"transform.rotation.z"];
    [CATransaction commit];
}

- (void)applySpin {
    CALayer *layer = self.disc.layer;
    if (!self.spinning) { [self freeze]; return; }
    if ([layer animationForKey:@"ik.spin"] || !self.window) return;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    a.fromValue = @(self.restAngle);
    a.toValue = @(self.restAngle + M_PI * 2);
=======
    if (![layer animationForKey:@"ik.spin"]) {
        // 先恢复时间线再加动画，否则暂停状态下新动画不会走
        layer.speed = 1; layer.timeOffset = 0; layer.beginTime = 0;
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        a.fromValue = @0;
        a.toValue = @(M_PI * 2);
        a.duration = self.period;
        a.repeatCount = HUGE_VALF;
        a.removedOnCompletion = NO;
        [layer addAnimation:a forKey:@"ik.spin"];
    }
    BOOL paused = (layer.speed == 0);
    if (self.spinning && paused) {
        CFTimeInterval pausedAt = layer.timeOffset;
        layer.speed = 1; layer.timeOffset = 0; layer.beginTime = 0;
        layer.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedAt;
    } else if (!self.spinning && !paused) {
        CFTimeInterval t = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
        layer.speed = 0;
        layer.timeOffset = t;
    }
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m
}

@end

#pragma mark - 跳动的音柱

@interface IKBarsView : UIView
@property (nonatomic, strong) NSArray<CALayer *> *bars;
@property (nonatomic) BOOL animating;
@end

@implementation IKBarsView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        NSMutableArray *a = [NSMutableArray array];
        for (int i = 0; i < 4; i++) {
            CALayer *l = [CALayer layer];
            l.cornerRadius = 1.5;
            [self.layer addSublayer:l];
            [a addObject:l];
        }
        _bars = a;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    for (NSUInteger i = 0; i < self.bars.count; i++) {
        CALayer *l = self.bars[i];
        l.bounds = CGRectMake(0, 0, 3, h);
        l.position = CGPointMake(1.5 + i * 5, h / 2);
    }
}

- (void)setColor:(UIColor *)c {
    for (CALayer *l in self.bars) l.backgroundColor = c.CGColor;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self setAnimating:self.animating];
}

- (void)setAnimating:(BOOL)animating {
    _animating = animating;
    NSArray *delays = @[@0.0, @0.3, @0.6, @0.15];
    for (NSUInteger i = 0; i < self.bars.count; i++) {
        CALayer *l = self.bars[i];
        [l removeAnimationForKey:@"ik.bar"];
        if (!animating) {
            l.transform = CATransform3DMakeScale(1, 0.35, 1);
            continue;
        }
        l.transform = CATransform3DIdentity;
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale.y"];
        a.fromValue = @0.35;
        a.toValue = @1.0;
        a.duration = 0.45;
        a.autoreverses = YES;
        a.repeatCount = HUGE_VALF;
        a.timeOffset = [delays[i] doubleValue];
        a.removedOnCompletion = NO;
        [l addAnimation:a forKey:@"ik.bar"];
    }
}

@end
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
    }
}

@end

#pragma mark - 一行文字

typedef NS_ENUM(NSInteger, IKLineChange) {
    IKLineChangeNone = 0,
    IKLineChangeFade,
    IKLineChangePush,   // 旧的一行向上滑出，新的一行从下面滑入
};

// 一行文字。可以带一层从左到右铺开的高亮；文字比视图宽时不截断，而是跟着进度向左滚动
@interface IKLineView : UIView
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, strong) UIColor *highlightColor;   // nil：这一行没有高亮层
@property (nonatomic) BOOL truncates;                    // YES：过长时截断并加省略号，不滚动
@property (nonatomic, copy, readonly) NSString *text;
- (void)setText:(NSString *)text change:(IKLineChange)change;
// duration > 0：这一行在 duration 秒内唱完。fill 为 YES 时高亮从左到右铺开，过长的文字跟着进度向左滚动。
// duration <= 0：没有时间信息，整行直接高亮；过长时来回缓慢滚动。
// playing 为 NO 时停在当前位置
- (void)setDuration:(double)duration elapsed:(double)elapsed playing:(BOOL)playing fill:(BOOL)fill;
@end

@interface IKLineView ()
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIView *track;        // 承载两层文字，滚动时整体平移
@property (nonatomic, strong) UILabel *baseLabel;
@property (nonatomic, strong) UILabel *topLabel;    // 高亮层，叠在 baseLabel 上
@property (nonatomic, strong) CALayer *fillMask;
@property (nonatomic) CGFloat textWidth;
@property (nonatomic) double duration;
@property (nonatomic) double startTime;             // 这一行开始的时刻（CACurrentMediaTime 基准）
@property (nonatomic) double pausedFraction;
@property (nonatomic) BOOL playing;
@property (nonatomic) BOOL fill;
@property (nonatomic) BOOL applied;                 // 当前参数已经变成动画了
@property (nonatomic) CGFloat appliedWidth;
@property (nonatomic) BOOL marqueeRunning;          // 正在跑“没有时间信息”的来回滚动
@property (nonatomic) CGFloat restOffset;           // 来回滚动被打断时已经滚过去的量，之后从这里接着滚
@end

@implementation IKLineView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        _text = @"";
        _font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        _textColor = [UIColor whiteColor];
        _track = [UIView new];
        _baseLabel = [UILabel new];
        _topLabel = [UILabel new];
        for (UILabel *l in @[_baseLabel, _topLabel]) {
            l.font = _font;
            l.lineBreakMode = NSLineBreakByClipping;
            [_track addSubview:l];
        }
        _baseLabel.textColor = _textColor;
        _topLabel.hidden = YES;
        [self addSubview:_track];
    }
    return self;
}

- (void)setFont:(UIFont *)font {
    if ([_font isEqual:font]) return;
    _font = font;
    self.baseLabel.font = font;
    self.topLabel.font = font;
    [self measure];
}

- (void)setTextColor:(UIColor *)textColor {
    _textColor = textColor;
    self.baseLabel.textColor = textColor;
}

- (void)setHighlightColor:(UIColor *)highlightColor {
    BOOL had = (_highlightColor != nil);
    _highlightColor = highlightColor;
    self.topLabel.textColor = highlightColor;
    if (had != (highlightColor != nil)) [self invalidate];
}

- (void)setTruncates:(BOOL)truncates {
    if (_truncates == truncates) return;
    _truncates = truncates;
    NSLineBreakMode mode = truncates ? NSLineBreakByTruncatingTail : NSLineBreakByClipping;
    self.baseLabel.lineBreakMode = mode;
    self.topLabel.lineBreakMode = mode;
    [self invalidate];
}

- (void)invalidate {
    self.applied = NO;
    [self setNeedsLayout];
}

- (void)measure {
    self.textWidth = self.text.length
        ? ceil([self.text sizeWithAttributes:@{NSFontAttributeName: self.font}].width) + 1 : 0;
    // 文字或字体变了：之前滚到哪里已经没有意义，从头开始
    [self.track.layer removeAnimationForKey:@"ik.scroll"];
    self.marqueeRunning = NO;
    self.restOffset = 0;
    [self invalidate];
}

- (void)setText:(NSString *)text change:(IKLineChange)change {
    NSString *t = text ?: @"";
    if ([t isEqualToString:self.text]) return;
    if (change != IKLineChangeNone && self.window && !self.hidden) {
        CATransition *tr = [CATransition animation];
        if (change == IKLineChangePush) {
            tr.type = kCATransitionPush;
            tr.subtype = kCATransitionFromTop;
            tr.duration = 0.32;
        } else {
            tr.type = kCATransitionFade;
            tr.duration = 0.2;
        }
        tr.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.layer addAnimation:tr forKey:@"ik.line"];
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m
- (void)setLyricColor:(UIColor *)lyricColor { _lyricColor = lyricColor; [self applyColors]; }
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
    self.text = t;
    self.baseLabel.text = t;
    self.topLabel.text = t;
    [self measure];
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m

- (void)setLyricEffect:(NSInteger)lyricEffect {
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
- (void)setDuration:(double)duration elapsed:(double)elapsed playing:(BOOL)playing fill:(BOOL)fill {
    elapsed = MAX(0, elapsed);
    double start = CACurrentMediaTime() - elapsed;
    double frac = duration > 0 ? MIN(1, elapsed / duration) : 1;
    if (self.applied && fabs(duration - self.duration) < 0.01 && playing == self.playing && fill == self.fill) {
        // 控制器每 0.25 秒会重新送一次参数，没有实质变化就不要打断正在跑的动画
        if (duration <= 0) return;
        if (playing ? fabs(start - self.startTime) < 0.3 : fabs(frac - self.pausedFraction) < 0.02) return;
    }
    self.duration = duration;
    self.startTime = start;
    self.pausedFraction = frac;
    self.playing = playing;
    self.fill = fill;
    [self applyProgress];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self invalidate];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    CGFloat lw = self.truncates ? W : self.textWidth;
    // track 左对齐在本行的 x = 0：宽 lw、中心在 lw / 2，等价于 frame = (0, 0, lw, H)，
    // 所以平移 0 时看到的是文字开头，平移 -(lw - W) 时文字末尾正好贴着本行右边。
    // 不直接设 frame，是因为 track 上带着滚动用的平移变换
    void (^place)(void) = ^{
        self.track.bounds = CGRectMake(0, 0, lw, H);
        self.track.center = CGPointMake(lw / 2, H / 2);
        self.baseLabel.frame = self.track.bounds;
        self.topLabel.frame = self.track.bounds;
    };
    // 截断的行宽度跟着胶囊走，可以随胶囊的形变一起动画；
    // 不截断的行宽度只取决于文字，换句时直接到位，不要被外层的弹簧动画带着伸缩
    if (self.truncates) place();
    else [UIView performWithoutAnimation:place];
    if (!self.applied || fabs(self.appliedWidth - W) > 0.5) [self applyProgress];
}

// 按当前的进度参数摆好高亮遮罩和滚动位置；正在播放时再加上走到这一行结束的动画
- (void)applyProgress {
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    CALayer *trackLayer = self.track.layer;
    if (self.marqueeRunning) {
        // 来回滚动要被打断了（暂停、宽度变化）：记下此刻滚到的位置
        CALayer *shown = trackLayer.presentationLayer;
        if (shown) self.restOffset = -[[shown valueForKeyPath:@"transform.translation.x"] doubleValue];
        self.marqueeRunning = NO;
    }
    [trackLayer removeAnimationForKey:@"ik.scroll"];
    [self.fillMask removeAnimationForKey:@"ik.fill"];

    BOOL highlight = (self.highlightColor != nil);
    self.topLabel.hidden = !highlight;
    if (W <= 0 || H <= 0) { self.applied = NO; return; }
    self.applied = YES;
    self.appliedWidth = W;

    CGFloat tw = self.textWidth;
    CGFloat overflow = self.truncates ? 0 : MAX(0, tw - W);
    BOOL scrolls = overflow > 0.5;
    BOOL timed = self.duration > 0;
    BOOL filling = highlight && self.fill && timed && tw > 0;
    double frac = 1;
    if (timed) {
        frac = self.playing ? (CACurrentMediaTime() - self.startTime) / self.duration : self.pausedFraction;
        frac = MAX(0, MIN(1, frac));
    }

    // 滚动量是进度的分段线性函数。填色时让填色的前沿停在可见宽度的 55% 处，
    // 所以开头和结尾不动、中间跟着填色走；不填色时用中间 70% 的时间匀速滚完
    double f1 = filling ? (W * 0.55) / tw : 0.15;
    double f2 = filling ? (W * 0.55 + overflow) / tw : 0.85;
    CGFloat (^offsetAt)(double) = ^CGFloat(double f) {
        if (!scrolls || f2 <= f1) return 0;
        return overflow * MAX(0, MIN(1, (f - f1) / (f2 - f1)));
    };

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (filling) {
        if (!self.fillMask) {
            self.fillMask = [CALayer layer];
            self.fillMask.backgroundColor = [UIColor blackColor].CGColor;
            self.fillMask.anchorPoint = CGPointZero;
        }
        CALayer *m = self.fillMask;
        m.position = CGPointZero;
        m.bounds = CGRectMake(0, 0, tw, H);
        m.transform = CATransform3DMakeScale(MAX(frac, 0.0001), 1, 1);
        self.topLabel.layer.mask = m;
    } else {
        self.topLabel.layer.mask = nil;
    }
    // 没有时间信息的一行停在上次滚到的位置（暂停时不跳回开头）
    CGFloat rest = (!timed && scrolls) ? MAX(0, MIN(self.restOffset, overflow)) : 0;
    if (timed || !scrolls) self.restOffset = 0;
    trackLayer.transform = CATransform3DMakeTranslation(timed ? -offsetAt(frac) : -rest, 0, 0);
    [CATransaction commit];

    if (!self.playing) return;

    if (!timed) {
        if (!scrolls) return;
        // 没有时间信息（歌名等）：停一下，匀速滚到头，停一下，再滚回来。
        // 之前滚到一半被打断的话，用 timeOffset 把动画的起点挪到那个位置，接着往前滚
        double hold = 1.6, travel = MAX(1.5, overflow / 28.0), total = hold * 2 + travel;
        CAKeyframeAnimation *s = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        s.values = @[@0, @0, @(-overflow), @(-overflow)];
        s.keyTimes = @[@0, @(hold / total), @((hold + travel) / total), @1];
        s.duration = total;
        if (rest > 0.5) s.timeOffset = hold + travel * (rest / overflow);
        s.autoreverses = YES;
        s.repeatCount = HUGE_VALF;
        s.removedOnCompletion = NO;
        [trackLayer addAnimation:s forKey:@"ik.scroll"];
        self.marqueeRunning = YES;
        return;
    }

    if (frac >= 1) return;
    double remaining = self.duration * (1 - frac);
    if (filling) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale.x"];
        a.fromValue = @(MAX(frac, 0.0001));
        a.toValue = @1.0;
        a.duration = remaining;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.fillMode = kCAFillModeForwards;
        a.removedOnCompletion = NO;
        [self.fillMask addAnimation:a forKey:@"ik.fill"];
    }
    if (scrolls) {
        NSMutableArray<NSNumber *> *values = [NSMutableArray array], *times = [NSMutableArray array];
        double last = -1;
        for (NSNumber *n in @[@(frac), @(f1), @(f2), @1.0]) {
            double f = n.doubleValue;
            if (f < frac || f > 1 || f - last < 1e-6) continue;
            last = f;
            [values addObject:@(-offsetAt(f))];
            [times addObject:@((f - frac) / (1 - frac))];
        }
        if (values.count < 2) return;
        CAKeyframeAnimation *s = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        s.values = values;
        s.keyTimes = times;
        s.duration = remaining;
        s.calculationMode = kCAAnimationLinear;
        s.fillMode = kCAFillModeForwards;
        s.removedOnCompletion = NO;
        [trackLayer addAnimation:s forKey:@"ik.scroll"];
    }
}

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m
        [self removeLyricScrollAnimations];
        if (!canScroll) {
            self.label1Offset = 0;
            self.label2Offset = 0;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
typedef NS_ENUM(NSInteger, IKTextKind) {
    IKTextKindPlain = 0,   // 歌名 + 歌手
    IKTextKindLyric,       // 歌词（双行时上面是歌名）
    IKTextKindNotif,       // 通知标题 + 正文
};

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m

<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKIslandView.m
@property (nonatomic, strong) UIView *content;       // 除黑色底以外的所有内容，可以单独淡出
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKIslandView.m
