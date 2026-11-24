#import "IKIslandView.h"

#pragma mark - 封面

@interface IKCoverView ()
@property (nonatomic, strong) UIImageView *disc;
@property (nonatomic, strong) UIView *hole;
@property (nonatomic) BOOL spinning;
@property (nonatomic) double period;
@end

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
    BOOL periodChanged = fabs(seconds - self.period) > 0.01;
    self.spinning = spinning;
    self.period = seconds;
    if (periodChanged) [self.disc.layer removeAnimationForKey:@"ik.spin"];
    [self applySpin];
}

- (void)applySpin {
    CALayer *layer = self.disc.layer;
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

#pragma mark - 岛

@interface IKIslandView ()
@property (nonatomic, strong) IKCoverView *cover;
@property (nonatomic, strong) IKBarsView *barsView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *appLabel;
@property (nonatomic, strong) UILabel *label1;
@property (nonatomic, strong) UILabel *label2;
@property (nonatomic) BOOL iconRound;
@property (nonatomic, strong) UILabel *label1H;      // 当前行的高亮层，叠在 label1 上
@property (nonatomic, strong) UILabel *label2H;      // 双行模式下当前歌词的高亮层
@property (nonatomic, strong) CALayer *sweepMask;
@property (nonatomic) double sweepStart;             // 这一行开始的时刻（CACurrentMediaTime 基准）
@property (nonatomic) double sweepDuration;
@property (nonatomic) double sweepPausedFraction;
@property (nonatomic) BOOL sweepPlaying;
@property (nonatomic, strong) CAShapeLayer *ringTrack;
@property (nonatomic, strong) CAShapeLayer *ring;
@end

@implementation IKIslandView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        _lyricLines = 2;
        _cutoutWidth = 126;

        _cover = [IKCoverView new];
        _barsView = [IKBarsView new];
        _iconView = [UIImageView new];
        _iconView.clipsToBounds = YES;
        _iconView.layer.cornerRadius = 11;
        _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        _iconView.backgroundColor = [UIColor colorWithWhite:0.17 alpha:1];

        _appLabel = [UILabel new];
        _appLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _appLabel.textColor = [UIColor colorWithWhite:0.66 alpha:1];
        _appLabel.textAlignment = NSTextAlignmentRight;

        _label1 = [UILabel new];
        _label1.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        _label1.lineBreakMode = NSLineBreakByTruncatingTail;

        _label2 = [UILabel new];
        _label2.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        _label2.textColor = [UIColor colorWithWhite:0.66 alpha:1];
        _label2.lineBreakMode = NSLineBreakByTruncatingTail;

        for (UIView *v in @[_cover, _barsView, _iconView, _appLabel, _label1, _label2]) [self addSubview:v];

        _label1H = [UILabel new];
        _label1H.font = _label1.font;
        _label1H.lineBreakMode = NSLineBreakByTruncatingTail;
        _label1H.hidden = YES;
        [self addSubview:_label1H];
        _label2H = [UILabel new];
        _label2H.font = _label2.font;
        _label2H.lineBreakMode = NSLineBreakByTruncatingTail;
        _label2H.hidden = YES;
        [self addSubview:_label2H];
        _lyricEffect = 1;
        _lyricFontSize = 16;

        _ringTrack = [CAShapeLayer layer];
        _ringTrack.fillColor = [UIColor clearColor].CGColor;
        _ringTrack.strokeColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        _ringTrack.lineWidth = 2;
        _ring = [CAShapeLayer layer];
        _ring.fillColor = [UIColor clearColor].CGColor;
        _ring.lineWidth = 2;
        _ring.lineCap = kCALineCapRound;
        _ring.strokeEnd = 0;
        _ringTrack.hidden = YES;
        _ring.hidden = YES;
        [self.layer addSublayer:_ringTrack];
        [self.layer addSublayer:_ring];
        self.accent = [UIColor whiteColor];
    }
    return self;
}

- (void)setAccent:(UIColor *)accent {
    _accent = accent;
    self.cover.accent = accent;
    [self.barsView setColor:accent];
    [self applyColors];
}

- (void)applyColors {
    BOOL notif = (self.state == IKStateNotif);
    UIColor *lyric = self.lyricColor ?: self.accent;
    // 双行时第一行是歌名，第二行是当前歌词。高亮层只覆盖当前歌词。
    self.label1.textColor = notif ? [UIColor whiteColor]
                                  : (self.lyricLines >= 2 ? [UIColor colorWithWhite:1 alpha:0.66]
                                                          : [UIColor colorWithWhite:1 alpha:0.5]);
    self.label2.textColor = notif ? [UIColor colorWithWhite:1 alpha:0.66]
                                  : [UIColor colorWithWhite:1 alpha:0.5];
    self.label1H.textColor = lyric;
    self.label2H.textColor = lyric;
    self.ring.strokeColor = (self.ringColor ?: self.accent).CGColor;
}

- (void)setLyricColor:(UIColor *)lyricColor { _lyricColor = lyricColor; [self applyColors]; }
- (void)setRingColor:(UIColor *)ringColor { _ringColor = ringColor; [self applyColors]; }

- (void)setLyricEffect:(NSInteger)lyricEffect {
    if (_lyricEffect == lyricEffect) return;
    _lyricEffect = lyricEffect;
    [self applySweep];
}

- (void)setLyricFontSize:(CGFloat)size {
    if (fabs(_lyricFontSize - size) < 0.1) return;
    _lyricFontSize = size;
    self.label1.font = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    self.label1H.font = self.label1.font;
    self.label2.font = [UIFont systemFontOfSize:MAX(11, size - 3) weight:UIFontWeightRegular];
    self.label2H.font = self.label2.font;
    [self applySweep];
}

- (void)setState:(IKState)state {
    _state = state;
    [self applyColors];
    [self setNeedsLayout];
}

- (void)setCoversCutout:(BOOL)coversCutout {
    _coversCutout = coversCutout;
    [self setNeedsLayout];
}

- (void)setLyricLines:(NSInteger)lyricLines {
    _lyricLines = lyricLines;
    [self applyColors];
    [self setNeedsLayout];
}

- (void)setLine1:(NSString *)l1 line2:(NSString *)l2 {
    if (![(l1 ?: @"") isEqualToString:self.label1.text ?: @""]) {
        CATransition *t = [CATransition animation];
        t.type = kCATransitionFade;
        t.duration = 0.2;
        [self.label1.layer addAnimation:t forKey:@"ik.fade"];
        [self.label2.layer addAnimation:t forKey:@"ik.fade"];
    }
    self.label1.text = l1;
    self.label1H.text = l1;
    self.label2.text = l2;
    self.label2H.text = l2;
    self.sweepDuration = 0; // 没有时间信息：整行高亮
    [self applySweep];
}

- (void)setLyricCurrent:(NSString *)current next:(NSString *)next
           lineDuration:(double)lineDuration elapsed:(double)elapsed playing:(BOOL)playing {
    BOOL two = self.lyricLines >= 2;
    BOOL changed = ![(current ?: @"") isEqualToString:(two ? self.label2.text : self.label1.text) ?: @""];
    if (changed) {
        // 换行：旧的一行向上滑出，新的一行从下面滑入（“淡入”效果时改为淡入）
        CATransition *t = [CATransition animation];
        if (self.lyricEffect == 2) {
            t.type = kCATransitionFade;
        } else {
            t.type = kCATransitionPush;
            t.subtype = kCATransitionFromTop;
        }
        t.duration = 0.32;
        t.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        for (UIView *v in @[self.label1, self.label1H, self.label2, self.label2H]) {
            v.clipsToBounds = YES;
            [v.layer addAnimation:t forKey:@"ik.line"];
        }
    }
    if (two) {
        self.label1.text = next;
        self.label1H.text = next;
        self.label2.text = current;
        self.label2H.text = current;
    } else {
        self.label1.text = current;
        self.label1H.text = current;
        self.label2.text = @"";
        self.label2H.text = @"";
    }

    self.sweepDuration = lineDuration;
    self.sweepPlaying = playing;
    self.sweepPausedFraction = lineDuration > 0 ? MAX(0, MIN(1, elapsed / lineDuration)) : 1;
    self.sweepStart = CACurrentMediaTime() - elapsed;
    [self applySweep];
}

// 当前行从左到右填色：用一个宽度随时间增长的遮罩盖在高亮层上
- (void)applySweep {
    UILabel *highlight = self.lyricLines >= 2 ? self.label2H : self.label1H;
    CALayer *host = highlight.layer;
    if (self.lyricEffect != 1 || self.sweepDuration <= 0 || highlight.hidden) {
        self.label1H.layer.mask = nil;
        self.label2H.layer.mask = nil;
        return;
    }
    CGFloat h = highlight.bounds.size.height;
    CGFloat textW = [highlight.text ?: @"" sizeWithAttributes:@{NSFontAttributeName: highlight.font}].width + 2;
    CGFloat full = MIN(highlight.bounds.size.width, textW);
    if (full <= 0 || h <= 0) { host.mask = nil; return; }

    double frac = self.sweepPlaying
        ? MAX(0, MIN(1, (CACurrentMediaTime() - self.sweepStart) / self.sweepDuration))
        : self.sweepPausedFraction;

    if (!self.sweepMask) {
        self.sweepMask = [CALayer layer];
        self.sweepMask.backgroundColor = [UIColor blackColor].CGColor;
        self.sweepMask.anchorPoint = CGPointZero;
    }
    CALayer *m = self.sweepMask;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [m removeAllAnimations];
    m.position = CGPointZero;
    m.bounds = CGRectMake(0, 0, full, h);
    m.transform = CATransform3DMakeScale(frac, 1, 1);
    host.mask = m;
    [CATransaction commit];

    if (self.sweepPlaying && frac < 1) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale.x"];
        a.fromValue = @(frac);
        a.toValue = @1.0;
        a.duration = self.sweepDuration * (1 - frac);
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.fillMode = kCAFillModeForwards;
        a.removedOnCompletion = NO;
        [m addAnimation:a forKey:@"ik.sweep"];
    }
}

- (void)setNotifIcon:(UIImage *)icon appName:(NSString *)app round:(BOOL)round {
    self.iconView.image = icon;
    self.iconView.contentMode = UIViewContentModeScaleAspectFill;
    self.iconRound = round;
    self.appLabel.text = app;
    [self setNeedsLayout];
}

- (void)setBarsAnimating:(BOOL)on {
    [self.barsView setAnimating:on];
}

- (void)setShowsProgress:(BOOL)showsProgress {
    _showsProgress = showsProgress;
    self.ring.hidden = !showsProgress;
    self.ringTrack.hidden = !showsProgress;
}

- (void)setProgress:(CGFloat)progress {
    _progress = MAX(0, MIN(1, progress));
    self.ring.strokeEnd = _progress; // 独立图层自带隐式动画，变化是平滑的
}

// 从顶部中点出发、顺时针绕胶囊一圈的路径
- (void)layoutRingWithCornerRadius:(CGFloat)cr {
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height, i = 1.5;
    CGFloat x0 = i, y0 = i, x1 = W - i, y1 = H - i;
    CGFloat r = MAX(0, MIN(cr - i, MIN((y1 - y0) / 2, (x1 - x0) / 2)));
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(W / 2, y0)];
    [p addLineToPoint:CGPointMake(x1 - r, y0)];
    [p addArcWithCenter:CGPointMake(x1 - r, y0 + r) radius:r startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(x1, y1 - r)];
    [p addArcWithCenter:CGPointMake(x1 - r, y1 - r) radius:r startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(x0 + r, y1)];
    [p addArcWithCenter:CGPointMake(x0 + r, y1 - r) radius:r startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(x0, y0 + r)];
    [p addArcWithCenter:CGPointMake(x0 + r, y0 + r) radius:r startAngle:M_PI endAngle:M_PI * 1.5 clockwise:YES];
    [p addLineToPoint:CGPointMake(W / 2, y0)];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.ring.frame = self.bounds;
    self.ringTrack.frame = self.bounds;
    self.ring.path = p.CGPath;
    self.ringTrack.path = p.CGPath;
    [CATransaction commit];
}

- (void)playNotifEntrance {
    self.iconView.transform = CGAffineTransformMakeScale(0.3, 0.3);
    self.iconView.alpha = 0;
    [UIView animateWithDuration:0.5 delay:0.08 usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.iconView.transform = CGAffineTransformIdentity;
        self.iconView.alpha = 1;
    } completion:nil];

    NSArray<UIView *> *texts = @[self.label1, self.label2, self.appLabel];
    for (NSUInteger idx = 0; idx < texts.count; idx++) {
        UIView *v = texts[idx];
        v.transform = CGAffineTransformMakeTranslation(0, 10);
        v.alpha = 0;
        [UIView animateWithDuration:0.35 delay:0.14 + 0.06 * idx options:UIViewAnimationOptionCurveEaseOut animations:^{
            v.transform = CGAffineTransformIdentity;
            v.alpha = 1;
        } completion:nil];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    self.layer.cornerRadius = MIN(H / 2, 36);

    BOOL compact = (self.state == IKStateMusicCompact);
    BOOL lyric   = (self.state == IKStateLyric);
    BOOL notif   = (self.state == IKStateNotif);
    BOOL two     = notif || (lyric && self.lyricLines >= 2);

    self.cover.hidden    = !(compact || lyric);
    self.barsView.hidden = !(compact || lyric);
    self.iconView.hidden = !notif;
    self.appLabel.hidden = !notif;
    self.label1.hidden   = !(lyric || notif);
    self.label2.hidden   = !two;

    [self layoutRingWithCornerRadius:(self.coversCutout ? MIN(H / 2, 36) : MIN(H / 2, 29))];

    if (!self.coversCutout) {
        // 独立胶囊：左边封面或图标，中间文字，右边音柱
        self.layer.cornerRadius = MIN(H / 2, 29);
        if (compact) {
            self.cover.frame = CGRectMake(4, (H - 26) / 2, 26, 26);
            self.barsView.frame = CGRectMake(W - 12 - 18, (H - 16) / 2, 18, 16);
        } else if (lyric) {
            CGFloat c = H - 12;
            self.cover.frame = CGRectMake(6, 6, c, c);
            self.barsView.frame = CGRectMake(W - 16 - 18, (H - 16) / 2, 18, 16);
            CGFloat x = 6 + c + 10, w = W - x - 16 - 18 - 10;
            if (two) {
                self.label1.frame = CGRectMake(x, H / 2 - 21, w, 22);
                self.label2.frame = CGRectMake(x, H / 2 + 2, w, 18);
            } else {
                self.label1.frame = CGRectMake(x, (H - 22) / 2, w, 22);
            }
        } else if (notif) {
            self.iconView.frame = CGRectMake(8, (H - 42) / 2, 42, 42);
            CGFloat x = 60, w = W - x - 18;
            self.appLabel.frame = CGRectMake(W - 18 - 96, H / 2 - 19, 96, 16);
            self.label1.frame = CGRectMake(x, H / 2 - 21, w - 102, 22);
            self.label2.frame = CGRectMake(x, H / 2 + 2, w, 18);
        }
        self.label1H.frame = self.label1.frame;
        self.label1H.hidden = self.label1.hidden || notif;
        self.label2H.frame = self.label2.frame;
        self.label2H.hidden = self.label2.hidden || notif;
        self.iconView.layer.cornerRadius = self.iconRound ? self.iconView.bounds.size.width / 2 : 11;
        [self applySweep];
        return;
    }

    // 开孔占据顶部 37pt 高、居中 cutoutWidth 宽的区域，文字一律放到它下面
    CGFloat band = self.cutoutHeight > 0 ? self.cutoutHeight : 37;
    if (compact) {
        self.cover.frame = CGRectMake(5, (H - 27) / 2, 27, 27);
        self.barsView.frame = CGRectMake(W - 14 - 18, (H - 16) / 2, 18, 16);
    } else if (lyric) {
        self.cover.frame = CGRectMake(12, (H - 52) / 2, 52, 52);
        self.barsView.frame = CGRectMake(W - 20 - 18, (band - 16) / 2, 18, 16);
        self.label1.frame = CGRectMake(76, band + 6, W - 76 - 18, 22);
        self.label2.frame = CGRectMake(76, band + 28, W - 76 - 18, 18);
    } else if (notif) {
        self.iconView.frame = CGRectMake(14, (H - 44) / 2, 44, 44);
        CGFloat ax = W / 2 + self.cutoutWidth / 2 + 6;
        self.appLabel.frame = CGRectMake(ax, (band - 16) / 2, MAX(0, W - ax - 16), 16);
        self.label1.frame = CGRectMake(70, band + 6, W - 70 - 18, 22);
        self.label2.frame = CGRectMake(70, band + 28, W - 70 - 18, 18);
    }
    self.label1H.frame = self.label1.frame;
    self.label1H.hidden = self.label1.hidden || notif;
    self.label2H.frame = self.label2.frame;
    self.label2H.hidden = self.label2.hidden || notif;
    self.iconView.layer.cornerRadius = self.iconRound ? self.iconView.bounds.size.width / 2 : 11;
    [self applySweep];
}

@end
