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
    BOOL changed = self.spinning != spinning || fabs(seconds - self.period) > 0.01;
    self.spinning = spinning;
    self.period = MAX(0.1, seconds);
    if (changed) [self applySpin];
}

- (CGFloat)currentRotation {
    CALayer *layer = self.disc.layer;
    CALayer *presentation = layer.presentationLayer;
    CATransform3D transform = presentation ? presentation.transform : layer.transform;
    return atan2(transform.m12, transform.m11);
}

- (void)applySpin {
    CALayer *layer = self.disc.layer;
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
@property (nonatomic, strong) UIView *label1Viewport;
@property (nonatomic, strong) UIView *label2Viewport;
@property (nonatomic) BOOL iconRound;
@property (nonatomic, strong) UILabel *label1H;      // 当前行的高亮层，叠在 label1 上
@property (nonatomic, strong) UILabel *label2H;      // 双行模式下当前歌词的高亮层
@property (nonatomic, strong) CALayer *sweepMask;
@property (nonatomic) double sweepStart;             // 这一行开始的时刻（CACurrentMediaTime 基准）
@property (nonatomic) double sweepDuration;
@property (nonatomic) double sweepPausedFraction;
@property (nonatomic) BOOL sweepPlaying;
@property (nonatomic) CGFloat label1Offset;
@property (nonatomic) CGFloat label2Offset;
@property (nonatomic) CGFloat label1TextWidth;
@property (nonatomic) CGFloat label2TextWidth;
@property (nonatomic) BOOL sweepConfigured;
@property (nonatomic) double configuredSweepStart;
@property (nonatomic) BOOL configuredSweepPlaying;
@property (nonatomic, strong) CAShapeLayer *ringTrack;
@property (nonatomic, strong) CAShapeLayer *ring;
- (void)removeLyricScrollAnimationsForViews:(NSArray<UIView *> *)views;
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
        _label1.lineBreakMode = NSLineBreakByClipping;

        _label2 = [UILabel new];
        _label2.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        _label2.textColor = [UIColor colorWithWhite:0.66 alpha:1];
        _label2.lineBreakMode = NSLineBreakByClipping;

        _label1Viewport = [UIView new];
        _label1Viewport.clipsToBounds = YES;
        _label2Viewport = [UIView new];
        _label2Viewport.clipsToBounds = YES;
        for (UIView *v in @[_cover, _barsView, _iconView, _appLabel, _label1Viewport, _label2Viewport]) [self addSubview:v];

        _label1H = [UILabel new];
        _label1H.font = _label1.font;
        _label1H.lineBreakMode = NSLineBreakByClipping;
        _label1H.hidden = YES;
        [_label1Viewport addSubview:_label1];
        [_label1Viewport addSubview:_label1H];
        _label2H = [UILabel new];
        _label2H.font = _label2.font;
        _label2H.lineBreakMode = NSLineBreakByClipping;
        _label2H.hidden = YES;
        [_label2Viewport addSubview:_label2];
        [_label2Viewport addSubview:_label2H];
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
    UIColor *songTitle = self.songTitleColor ?: [UIColor colorWithWhite:1 alpha:0.66];
    UIColor *notifTitle = self.notifTitleColor ?: [UIColor whiteColor];
    UIColor *notifMessage = self.notifMessageColor ?: [UIColor colorWithWhite:1 alpha:0.66];
    // 双行时第一行是歌名，第二行是当前歌词。高亮层只覆盖当前歌词。
    self.label1.textColor = notif ? notifTitle
                                  : (self.lyricLines >= 2 ? songTitle
                                                          : [UIColor colorWithWhite:1 alpha:0.5]);
    self.label2.textColor = notif ? notifMessage
                                  : [UIColor colorWithWhite:1 alpha:0.5];
    self.appLabel.textColor = notif ? notifTitle : [UIColor colorWithWhite:0.66 alpha:1];
    self.label1H.textColor = lyric;
    self.label2H.textColor = lyric;
    self.ring.strokeColor = (self.ringColor ?: self.accent).CGColor;
}

- (void)setLyricColor:(UIColor *)lyricColor { _lyricColor = lyricColor; [self applyColors]; }
- (void)setSongTitleColor:(UIColor *)songTitleColor { _songTitleColor = songTitleColor; [self applyColors]; }
- (void)setRingColor:(UIColor *)ringColor { _ringColor = ringColor; [self applyColors]; }
- (void)setNotifTitleColor:(UIColor *)color { _notifTitleColor = color; [self applyColors]; }
- (void)setNotifMessageColor:(UIColor *)color { _notifMessageColor = color; [self applyColors]; }

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
    self.label1Offset = 0;
    self.label2Offset = 0;
    self.sweepConfigured = NO;
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
        NSArray<UIView *> *changingViews = two
            ? @[self.label2, self.label2H]
            : @[self.label1, self.label1H];
        [self removeLyricScrollAnimationsForViews:changingViews];
        UILabel *changingLabel = two ? self.label2 : self.label1;
        UILabel *changingHighlight = two ? self.label2H : self.label1H;
        [UIView performWithoutAnimation:^{
            [self setTrackOffset:0 label:changingLabel highlight:changingHighlight];
        }];
        for (UIView *v in changingViews) {
            v.clipsToBounds = YES;
            [v.layer addAnimation:t forKey:@"ik.line"];
        }
        if (two) self.label2Offset = 0;
        else self.label1Offset = 0;
        self.sweepConfigured = NO;
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

// 当前行从左到右填色，同时让过长歌词沿填色进度平滑左移。
- (CGFloat)textWidthForLabel:(UILabel *)label {
    if (label.text.length == 0 || label.font == nil) return 0;
    CGRect bounds = [label.text boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, label.font.lineHeight)
                                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                          attributes:@{NSFontAttributeName: label.font}
                                             context:nil];
    return ceil(CGRectGetWidth(bounds)) + 2;
}

- (CGFloat)presentationOffsetForLabel:(UILabel *)label fallback:(CGFloat)fallback {
    CALayer *presentation = label.layer.presentationLayer;
    return presentation ? presentation.frame.origin.x : fallback;
}

- (void)setTrackOffset:(CGFloat)offset label:(UILabel *)label highlight:(UILabel *)highlight {
    CGRect frame = label.frame;
    frame.origin.x = offset;
    label.frame = frame;
    frame = highlight.frame;
    frame.origin.x = offset;
    highlight.frame = frame;
}

- (void)removeLyricScrollAnimations {
    [self removeLyricScrollAnimationsForViews:@[self.label1, self.label1H, self.label2, self.label2H]];
}

- (void)removeLyricScrollAnimationsForViews:(NSArray<UIView *> *)views {
    // UIView 的 frame 动画使用 position/bounds 图层键，不会使用自定义名称。
    // 保留 ik.line 和 ik.fade，避免清掉换句过渡。
    for (UIView *view in views) {
        [view.layer removeAnimationForKey:@"position"];
        [view.layer removeAnimationForKey:@"bounds"];
        [view.layer removeAnimationForKey:@"bounds.size"];
        [view.layer removeAnimationForKey:@"frame"];
    }
}

- (void)applySweep {
    UILabel *highlight = self.lyricLines >= 2 ? self.label2H : self.label1H;
    UILabel *track = self.lyricLines >= 2 ? self.label2 : self.label1;
    UIView *viewport = self.lyricLines >= 2 ? self.label2Viewport : self.label1Viewport;
    CALayer *host = highlight.layer;
    BOOL hasTiming = self.sweepDuration > 0 && viewport.bounds.size.width > 0;
    BOOL canFill = self.lyricEffect == 1 && hasTiming && !highlight.hidden;
    BOOL canScroll = hasTiming && !track.hidden;
    CGFloat h = highlight.bounds.size.height;
    CGFloat textW = [self textWidthForLabel:track];
    CGFloat full = MAX(0, textW);
    CGFloat overflow = MAX(0, textW - viewport.bounds.size.width);

    if (!canFill) {
        self.label1H.layer.mask = nil;
        self.label2H.layer.mask = nil;
    } else {
        CALayer *otherHost = host == self.label1H.layer ? self.label2H.layer : self.label1H.layer;
        otherHost.mask = nil;
    }
    if (!canScroll || full <= 0 || h <= 0) {
        [self removeLyricScrollAnimations];
        if (!canScroll) {
            self.label1Offset = 0;
            self.label2Offset = 0;
            [self setTrackOffset:0 label:self.label1 highlight:self.label1H];
            [self setTrackOffset:0 label:self.label2 highlight:self.label2H];
        }
        self.sweepConfigured = NO;
        return;
    }

    double frac = self.sweepPlaying
        ? MAX(0, MIN(1, (CACurrentMediaTime() - self.sweepStart) / self.sweepDuration))
        : self.sweepPausedFraction;
    // 播放时文字从左端滚到右端，暂停时停在当前填色比例对应的位置。
    CGFloat targetOffset = self.sweepPlaying ? -overflow : -overflow * frac;
    BOOL sameSweep = self.sweepConfigured
        && self.configuredSweepPlaying == self.sweepPlaying
        && fabs(self.configuredSweepStart - self.sweepStart) < 0.05
        && ((!canFill && host.mask == nil) || (canFill && host.mask != nil));

    if (!self.sweepMask) {
        self.sweepMask = [CALayer layer];
        self.sweepMask.backgroundColor = [UIColor blackColor].CGColor;
        self.sweepMask.anchorPoint = CGPointZero;
    }
    CALayer *mask = self.sweepMask;
    if (!sameSweep) {
        CGFloat currentOffset = [self presentationOffsetForLabel:track
                                                             fallback:(self.lyricLines >= 2 ? self.label2Offset : self.label1Offset)];
        // 先读取 presentation layer，再移除 UIView 动画，否则暂停或改色时
        // 会丢失当前滚动位置，文字瞬间跳到旧的模型值。
        [self removeLyricScrollAnimations];
        [self setTrackOffset:currentOffset label:track highlight:highlight];
        if (canFill) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [mask removeAllAnimations];
            mask.position = CGPointZero;
            mask.bounds = CGRectMake(0, 0, full, h);
            mask.transform = CATransform3DMakeScale(frac, 1, 1);
            host.mask = mask;
            [CATransaction commit];
        }

        if (self.sweepPlaying && frac < 1) {
            if (canFill) {
                CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"transform.scale.x"];
                fill.fromValue = @(frac);
                fill.toValue = @1.0;
                fill.duration = self.sweepDuration * (1 - frac);
                fill.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
                fill.fillMode = kCAFillModeForwards;
                fill.removedOnCompletion = NO;
                [mask addAnimation:fill forKey:@"ik.sweep"];
            }

            CGFloat *storedOffset = self.lyricLines >= 2 ? &_label2Offset : &_label1Offset;
            *storedOffset = targetOffset;
            NSTimeInterval remaining = MAX(0.05, self.sweepDuration * (1 - frac));
            [UIView animateWithDuration:remaining delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                [self setTrackOffset:targetOffset label:track highlight:highlight];
            } completion:nil];
        } else {
            if (self.lyricLines >= 2) self.label2Offset = targetOffset;
            else self.label1Offset = targetOffset;
            [self setTrackOffset:targetOffset label:track highlight:highlight];
        }
        self.configuredSweepStart = self.sweepStart;
        self.configuredSweepPlaying = self.sweepPlaying;
        self.sweepConfigured = YES;
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

- (void)playInteractionPulse {
    [self.layer removeAnimationForKey:@"ik.interactionPulse"];
    CASpringAnimation *pulse = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    pulse.fromValue = @1.0;
    pulse.toValue = @1.035;
    pulse.initialVelocity = 0.4;
    pulse.damping = 12;
    pulse.stiffness = 180;
    pulse.mass = 1;
    pulse.duration = 0.42;
    pulse.autoreverses = YES;
    pulse.removedOnCompletion = YES;
    [self.layer addAnimation:pulse forKey:@"ik.interactionPulse"];
}

- (void)layoutTextViewport:(UIView *)viewport label:(UILabel *)label highlight:(UILabel *)highlight
                     frame:(CGRect)frame hidden:(BOOL)hidden notification:(BOOL)notification offset:(CGFloat)offset {
    viewport.frame = frame;
    viewport.hidden = hidden;
    label.numberOfLines = 1;
    highlight.numberOfLines = 1;
    BOOL isCurrentLyric = !notification && self.state == IKStateLyric && self.sweepDuration > 0
        && ((self.lyricLines < 2 && viewport == self.label1Viewport)
            || (self.lyricLines >= 2 && viewport == self.label2Viewport));
    label.lineBreakMode = isCurrentLyric ? NSLineBreakByClipping : NSLineBreakByTruncatingTail;
    highlight.lineBreakMode = NSLineBreakByClipping;

    CGFloat textWidth = [self textWidthForLabel:label];
    CGFloat trackWidth = isCurrentLyric ? MAX(frame.size.width, textWidth) : MAX(0, frame.size.width);
    CGRect trackFrame = CGRectMake(offset, 0, trackWidth, frame.size.height);
    label.frame = trackFrame;
    highlight.frame = trackFrame;
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
    self.label1H.hidden  = self.label1.hidden || notif || self.sweepDuration <= 0
        || (lyric && self.lyricLines >= 2);
    self.label2H.hidden  = self.label2.hidden || notif || self.sweepDuration <= 0
        || !(lyric && self.lyricLines >= 2);

    [self layoutRingWithCornerRadius:(self.coversCutout ? MIN(H / 2, 36) : MIN(H / 2, 29))];

    if (!self.coversCutout) {
        // 独立胶囊：左边封面或图标，中间文字，右边音柱
        self.layer.cornerRadius = MIN(H / 2, 29);
        if (compact) {
            self.cover.frame = CGRectMake(4, (H - 26) / 2, 26, 26);
            self.barsView.frame = CGRectMake(W - 12 - 18, (H - 16) / 2, 18, 16);
            [self layoutTextViewport:self.label1Viewport label:self.label1 highlight:self.label1H
                               frame:CGRectZero hidden:YES notification:NO offset:0];
            [self layoutTextViewport:self.label2Viewport label:self.label2 highlight:self.label2H
                               frame:CGRectZero hidden:YES notification:NO offset:0];
        } else if (lyric) {
            CGFloat c = H - 12;
            self.cover.frame = CGRectMake(6, 6, c, c);
            self.barsView.frame = CGRectMake(W - 16 - 18, (H - 16) / 2, 18, 16);
            CGFloat x = 6 + c + 10, w = W - x - 16 - 18 - 10;
            [self layoutTextViewport:self.label1Viewport label:self.label1 highlight:self.label1H
                               frame:(two ? CGRectMake(x, H / 2 - 21, w, 22) : CGRectMake(x, (H - 22) / 2, w, 22))
                              hidden:NO notification:NO offset:self.label1Offset];
            [self layoutTextViewport:self.label2Viewport label:self.label2 highlight:self.label2H
                               frame:(two ? CGRectMake(x, H / 2 + 2, w, 18) : CGRectZero)
                              hidden:!two notification:NO offset:self.label2Offset];
        } else if (notif) {
            self.iconView.frame = CGRectMake(8, (H - 42) / 2, 42, 42);
            CGFloat x = 60, w = W - x - 18;
            self.appLabel.frame = CGRectMake(W - 18 - 96, H / 2 - 19, 96, 16);
            [self layoutTextViewport:self.label1Viewport label:self.label1 highlight:self.label1H
                               frame:CGRectMake(x, H / 2 - 21, MAX(0, w - 102), 22)
                              hidden:NO notification:YES offset:0];
            [self layoutTextViewport:self.label2Viewport label:self.label2 highlight:self.label2H
                               frame:CGRectMake(x, H / 2 + 2, MAX(0, w), 18)
                              hidden:NO notification:YES offset:0];
        } else {
            [self layoutTextViewport:self.label1Viewport label:self.label1 highlight:self.label1H
                               frame:CGRectZero hidden:YES notification:NO offset:0];
            [self layoutTextViewport:self.label2Viewport label:self.label2 highlight:self.label2H
                               frame:CGRectZero hidden:YES notification:NO offset:0];
        }
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
        CGFloat textWidth = MAX(0, W - 76 - 18);
        [self layoutTextViewport:self.label1Viewport label:self.label1 highlight:self.label1H
                           frame:(self.lyricLines >= 2 ? CGRectMake(76, band + 6, textWidth, 22) : CGRectMake(76, band + 17, textWidth, 22))
                          hidden:NO notification:NO offset:self.label1Offset];
        [self layoutTextViewport:self.label2Viewport label:self.label2 highlight:self.label2H
                           frame:(self.lyricLines >= 2 ? CGRectMake(76, band + 28, textWidth, 18) : CGRectZero)
                          hidden:self.lyricLines < 2 notification:NO offset:self.label2Offset];
    } else if (notif) {
        self.iconView.frame = CGRectMake(14, (H - 44) / 2, 44, 44);
        CGFloat ax = W / 2 + self.cutoutWidth / 2 + 6;
        self.appLabel.frame = CGRectMake(ax, (band - 16) / 2, MAX(0, W - ax - 16), 16);
        CGFloat textWidth = MAX(0, W - 70 - 18);
        [self layoutTextViewport:self.label1Viewport label:self.label1 highlight:self.label1H
                           frame:CGRectMake(70, band + 6, textWidth, 22)
                          hidden:NO notification:YES offset:0];
        [self layoutTextViewport:self.label2Viewport label:self.label2 highlight:self.label2H
                           frame:CGRectMake(70, band + 28, textWidth, 18)
                          hidden:NO notification:YES offset:0];
    } else {
        [self layoutTextViewport:self.label1Viewport label:self.label1 highlight:self.label1H
                           frame:CGRectZero hidden:YES notification:NO offset:0];
        [self layoutTextViewport:self.label2Viewport label:self.label2 highlight:self.label2H
                           frame:CGRectZero hidden:YES notification:NO offset:0];
    }
    self.iconView.layer.cornerRadius = self.iconRound ? self.iconView.bounds.size.width / 2 : 11;
    [self applySweep];
}

@end
