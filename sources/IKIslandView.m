#import "IKCoverLayout.h"
#import "IKIslandView.h"

#pragma mark - 封面

@interface IKCoverView ()
@property (nonatomic, strong) UIImageView *disc;
@property (nonatomic, strong) UIView *hole;
@property (nonatomic) BOOL spinning;
@property (nonatomic) double period;
@property (nonatomic) CGFloat restAngle;   // 停转时停在的角度，再转时从这里接着转
@end

@implementation IKCoverView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _period = 8;
        self.clipsToBounds = YES;
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
    self.layer.cornerRadius = s / 2;
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
    if (periodChanged) [self freeze]; // 换了转速：从当前角度重新起转
    [self applySpin];
}

// 停转：把当前转到的角度写进图层，再拿掉旋转动画。
// 不能用 layer.speed = 0 来暂停：图层被暂停后，UIKit 动画块里给它加的布局动画永远走不完，
// 那个动画块的完成回调也就永远不会来（之前“暂停后收起的胶囊一直留在屏幕上”就是这个原因）
- (void)freeze {
    CALayer *layer = self.disc.layer;
    if (![layer animationForKey:@"ik.spin"]) return;
    CALayer *shown = layer.presentationLayer ?: layer;
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
    a.duration = self.period;
    a.repeatCount = HUGE_VALF;
    a.removedOnCompletion = NO;
    [layer addAnimation:a forKey:@"ik.spin"];
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
// 居中和自定义时文字中心想放的位置（本行坐标），由岛按胶囊中线换算；NAN 表示按本行自己的宽度居中
@property (nonatomic) CGFloat anchor;
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
@property (nonatomic) NSInteger alignment;
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
        _anchor = NAN;
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

- (void)setAlignment:(NSInteger)alignment {
    if (_alignment == alignment) return;
    _alignment = alignment;
    [self setNeedsLayout];
}

- (void)setAnchor:(CGFloat)anchor {
    if ((isnan(anchor) && isnan(_anchor)) || fabs(anchor - _anchor) < 0.25) return;
    _anchor = anchor;
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
    }
    self.text = t;
    self.baseLabel.text = t;
    self.topLabel.text = t;
    [self measure];
}

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
    // Use center and bounds because the track may have an independent scrolling transform.
    void (^place)(void) = ^{
        self.track.bounds = CGRectMake(0, 0, lw, H);
        self.track.center = CGPointMake(IKTextOrigin(W, lw, self.alignment, self.anchor) + lw / 2, H / 2);
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

@end

#pragma mark - 进度环的遮罩

// 以中心为顶点的扇形，从 12 点方向顺时针张开。尺寸固定得很大（远大于胶囊），
// 所以胶囊变形时它只需要把中心对准环的中心：中心跟着同一个弹簧动画平移，扇形本身不用变
@interface IKWedgeView : UIView
@end

@implementation IKWedgeView
+ (Class)layerClass { return [CAShapeLayer class]; }
@end

static const CGFloat IKWedgeSide = 2400;
static const NSInteger IKWedgeSteps = 48;

// 圆角矩形（宽 w、高 h、圆角 r）的边上，从顶部中点顺时针走过全长 p 倍的那个点，
// 相对矩形中心的角度（弧度，12 点方向为 -π/2，顺时针增大，取值 [-π/2, 3π/2]）
CGFloat IKRingAngle(CGFloat w, CGFloat h, CGFloat r, CGFloat p) {
    w = MAX(w, 1); h = MAX(h, 1);
    r = MAX(0, MIN(r, MIN(w, h) / 2));
    p = MAX(0, MIN(1, p));
    CGFloat a = w / 2 - r, b = h - 2 * r, c = w - 2 * r, q = M_PI_2 * r;
    CGFloat lengths[9] = { a, q, b, q, c, q, b, q, a };
    CGFloat total = 0;
    for (int i = 0; i < 9; i++) total += lengths[i];
    CGFloat s = p * total, x = w / 2, y = 0;
    for (int i = 0; i < 9; i++) {
        CGFloat len = lengths[i];
        CGFloat t = (i == 8 || s <= len) ? (len > 0 ? MIN(1, s / len) : 1) : -1;
        if (t < 0) { s -= len; continue; }
        CGFloat ang;
        switch (i) {
            case 0: x = w / 2 + a * t; y = 0; break;
            case 1: ang = -M_PI_2 + M_PI_2 * t; x = w - r + r * cos(ang); y = r + r * sin(ang); break;
            case 2: x = w; y = r + b * t; break;
            case 3: ang = M_PI_2 * t; x = w - r + r * cos(ang); y = h - r + r * sin(ang); break;
            case 4: x = w - r - c * t; y = h; break;
            case 5: ang = M_PI_2 + M_PI_2 * t; x = r + r * cos(ang); y = h - r + r * sin(ang); break;
            case 6: x = 0; y = h - r - b * t; break;
            case 7: ang = M_PI + M_PI_2 * t; x = r + r * cos(ang); y = r + r * sin(ang); break;
            default: x = r + a * t; y = 0; break;
        }
        break;
    }
    if (p >= 1) return M_PI * 1.5;
    CGFloat angle = atan2(y - h / 2, x - w / 2);
    if (angle < -M_PI_2 - 1e-6) angle += 2 * M_PI;
    // 走到最后一小段（回到 12 点左侧）时 atan2 会接近 -π/2，按整圈处理
    if (p > 0.5 && angle < 0 && x <= w / 2) angle += 2 * M_PI;
    return MAX(-M_PI_2, MIN(M_PI * 1.5, angle));
}

#pragma mark - 岛

typedef NS_ENUM(NSInteger, IKTextKind) {
    IKTextKindPlain = 0,   // 歌名 + 歌手
    IKTextKindLyric,       // 歌词（双行时上面是歌名）
    IKTextKindNotif,       // 通知标题 + 正文
};

@interface IKIslandView ()
@property (nonatomic, strong) UIView *content;       // 除黑色底以外的所有内容，可以单独淡出
@property (nonatomic, strong) IKCoverView *cover;
@property (nonatomic, strong) IKBarsView *barsView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *appLabel;
@property (nonatomic, strong) IKLineView *row1;
@property (nonatomic, strong) IKLineView *row2;
@property (nonatomic) BOOL iconRound;
@property (nonatomic) IKTextKind textKind;
@property (nonatomic, strong) CADisplayLink *sizeLink;
@property (nonatomic) BOOL resizingShell;
@property (nonatomic) CGSize drawnSize;
@property (nonatomic) CGSize drawnFit;                 // 形变期间按它判断内容放不放得下（变小时比 drawnSize 小）
// 进度环。不放在 content 里：content 在形变时逐帧排版，会比胶囊慢一帧；
// 环用视图的描边画，尺寸和圆角在同一个动画块里设置，跟胶囊用同一条弹簧曲线，形变时不用藏起来。
//   ringHolder 透明度跟随 contentAlpha（收进开孔时一起淡出），ringBox 透明度表示开没开进度环
@property (nonatomic, strong) UIView *ringHolder;
@property (nonatomic, strong) UIView *ringBox;
@property (nonatomic, strong) UIView *ringTrack;
@property (nonatomic, strong) UIView *ring;
@property (nonatomic, strong) IKWedgeView *ringWedge;
@property (nonatomic) CGSize wedgeSize;                 // 遮罩扇形是按多大的胶囊算的
@property (nonatomic, weak) UIView *fadingSnapshot;
@end

@implementation IKIslandView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        _lyricLines = 2;
        _cutoutWidth = 126;
        _cutoutBand = 37;
        _lyricEffect = 1;
        _lyricFontSize = 16;
        _contentAlpha = 1;

        _ringHolder = [[UIView alloc] initWithFrame:self.bounds];
        _ringHolder.userInteractionEnabled = NO;
        _ringBox = [[UIView alloc] initWithFrame:self.bounds];
        _ringBox.alpha = 0;
        [_ringHolder addSubview:_ringBox];
        _ringTrack = [UIView new];
        _ring = [UIView new];
        for (UIView *v in @[_ringTrack, _ring]) {
            v.layer.borderWidth = 2;
            v.layer.cornerCurve = kCACornerCurveContinuous;
            [_ringBox addSubview:v];
        }
        _ringTrack.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        _ringWedge = [[IKWedgeView alloc] initWithFrame:CGRectMake(0, 0, IKWedgeSide, IKWedgeSide)];
        _ringWedge.userInteractionEnabled = NO;
        ((CAShapeLayer *)_ringWedge.layer).fillColor = [UIColor blackColor].CGColor;
        _ring.maskView = _ringWedge;
        [self addSubview:_ringHolder];

        _content = [[UIView alloc] initWithFrame:self.bounds];
        _content.userInteractionEnabled = NO;
        [self addSubview:_content];

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

        _row1 = [IKLineView new];
        _row2 = [IKLineView new];
        for (UIView *v in @[_cover, _barsView, _iconView, _appLabel, _row1, _row2]) [_content addSubview:v];
        [self applyFonts];
        self.accent = [UIColor whiteColor];
        [self applyWedgeAnimated:NO];
    }
    return self;
}

- (void)setAccent:(UIColor *)accent {
    _accent = accent;
    self.cover.accent = accent;
    [self.barsView setColor:accent];
    [self applyTextStyles];
}

// 每一行用什么颜色、要不要高亮层，取决于现在显示的是哪一类文字
- (void)applyTextStyles {
    UIColor *dim = [UIColor colorWithWhite:1 alpha:0.5];
    UIColor *title = self.titleColor ?: [UIColor whiteColor];
    UIColor *lyric = self.lyricColor ?: self.accent;
    UIColor *c1 = title, *c2 = dim, *h1 = nil, *h2 = nil;
    BOOL truncates = NO;
    switch (self.textKind) {
        case IKTextKindNotif:
            c1 = self.notifTitleColor ?: [UIColor whiteColor];
            c2 = self.notifMessageColor ?: [UIColor colorWithWhite:1 alpha:0.66];
            truncates = YES;
            break;
        case IKTextKindLyric:
            // 双行：第一行歌名（自己的颜色，不带高亮），第二行歌词。单行：只有歌词
            if (self.lyricLines >= 2) { h2 = lyric; }
            else { c1 = dim; h1 = lyric; }
            break;
        case IKTextKindPlain:
            break;
    }
    self.row1.textColor = c1;
    self.row1.alignment = self.textKind == IKTextKindNotif ? 0 : self.lyricAlignment;
    self.row2.alignment = self.row1.alignment;
    self.row1.highlightColor = h1;
    self.row1.truncates = truncates;
    self.row2.textColor = c2;
    self.row2.highlightColor = h2;
    self.row2.truncates = truncates;
    self.appLabel.textColor = self.notifTitleColor ?: [UIColor colorWithWhite:1 alpha:0.66];
    self.ring.layer.borderColor = (self.ringColor ?: self.accent).CGColor;
}

- (void)applyFonts {
    CGFloat size = self.lyricFontSize;
    self.row1.font = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    self.row2.font = [UIFont systemFontOfSize:MAX(11, size - 3) weight:UIFontWeightRegular];
}

- (void)setLyricColor:(UIColor *)lyricColor { _lyricColor = lyricColor; [self applyTextStyles]; }
- (void)setTitleColor:(UIColor *)titleColor { _titleColor = titleColor; [self applyTextStyles]; }
- (void)setRingColor:(UIColor *)ringColor { _ringColor = ringColor; [self applyTextStyles]; }
- (void)setNotifTitleColor:(UIColor *)color { _notifTitleColor = color; [self applyTextStyles]; }
- (void)setNotifMessageColor:(UIColor *)color { _notifMessageColor = color; [self applyTextStyles]; }

- (void)setLyricFontSize:(CGFloat)size {
    if (fabs(_lyricFontSize - size) < 0.1) return;
    _lyricFontSize = size;
    [self applyFonts];
}

- (void)setState:(IKState)state {
    _state = state;
    [self setNeedsLayout];
}

- (void)setCoversCutout:(BOOL)coversCutout {
    if (_coversCutout != coversCutout) self.wedgeSize = CGSizeZero; // 圆角变了，扇形要重算
    _coversCutout = coversCutout;
    [self setNeedsLayout];
}

- (void)setCutoutBand:(CGFloat)cutoutBand {
    if (fabs(_cutoutBand - cutoutBand) < 0.01) return;
    _cutoutBand = cutoutBand;
    [self setNeedsLayout];
}

- (void)setLyricLines:(NSInteger)lyricLines {
    if (_lyricLines == lyricLines) return;
    _lyricLines = lyricLines;
    [self applyTextStyles];
    [self setNeedsLayout];
}

- (void)setLyricAlignment:(NSInteger)lyricAlignment {
    if (_lyricAlignment == lyricAlignment) return;
    _lyricAlignment = lyricAlignment;
    [self applyTextStyles];
    [self setNeedsLayout];
}

- (void)setLyricOffsetX:(CGFloat)lyricOffsetX {
    if (fabs(_lyricOffsetX - lyricOffsetX) < 0.01) return;
    _lyricOffsetX = lyricOffsetX;
    [self setNeedsLayout];
}

- (void)setLyricOffsetY:(CGFloat)lyricOffsetY {
    if (fabs(_lyricOffsetY - lyricOffsetY) < 0.01) return;
    _lyricOffsetY = lyricOffsetY;
    [self setNeedsLayout];
}

- (void)setContentAlpha:(CGFloat)contentAlpha {
    _contentAlpha = contentAlpha;
    self.content.alpha = contentAlpha;
    self.ringHolder.alpha = contentAlpha;
}

- (void)setOutlineOnly:(BOOL)outlineOnly {
    _outlineOnly = outlineOnly;
    self.backgroundColor = outlineOnly ? [UIColor clearColor] : [UIColor blackColor];
    // 红色在白底和黑色的系统岛上都看得清
    self.layer.borderColor = [UIColor colorWithRed:1.0 green:0.18 blue:0.33 alpha:1].CGColor;
    self.layer.borderWidth = outlineOnly ? 1.5 : 0;
}

- (void)stopAnimations {
    [self endFollowingShell];
    [self.layer removeAllAnimations];
    [self.content.layer removeAllAnimations];
    [self.fadingSnapshot removeFromSuperview];
    [self removeRingAnimationsKeepingFades:NO];
}

- (void)stopShellAnimations {
    [self.layer removeAllAnimations];
    [self removeRingAnimationsKeepingFades:YES];
}

// 环的几个视图和胶囊一起做形变动画。胶囊的动画被拿掉时它们的也要一起拿掉，否则会和胶囊错开
- (void)removeRingAnimationsKeepingFades:(BOOL)keepFades {
    for (UIView *v in @[self.ringHolder, self.ringBox, self.ringTrack, self.ring, self.ringWedge]) {
        for (NSString *key in [v.layer.animationKeys copy]) {
            if (keepFades && [key isEqualToString:@"opacity"]) continue;
            if ([key isEqualToString:@"ik.progress"]) continue;
            [v.layer removeAnimationForKey:key];
        }
    }
}

- (void)hideContentImmediately {
    [self.content.layer removeAllAnimations];
    [self.ringHolder.layer removeAnimationForKey:@"opacity"];
    [UIView performWithoutAnimation:^{ self.contentAlpha = 0; }];
}

// 换一类内容（音乐 ↔ 通知）时：旧内容留一张快照淡出，真正的内容先隐去，再由过渡把新内容淡入。
// 进度环不在 content 里，不受影响，由 showsProgress 自己淡入淡出
- (void)crossfadeContent {
    [self.fadingSnapshot removeFromSuperview];
    UIView *snap = nil;
    if (self.window && !self.hidden && self.alpha > 0.01 && self.content.alpha > 0.01)
        snap = [self.content snapshotViewAfterScreenUpdates:NO];
    [self.content.layer removeAllAnimations];
    [UIView performWithoutAnimation:^{ self.content.alpha = 0; }];
    _contentAlpha = 0;
    if (!snap) return;
    snap.frame = self.content.frame;
    snap.userInteractionEnabled = NO;
    // 胶囊左右对称地变宽变窄：快照跟着中线走，不贴着左边
    snap.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleBottomMargin;
    [self insertSubview:snap aboveSubview:self.content];
    self.fadingSnapshot = snap;
    [UIView animateWithDuration:0.18 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ snap.alpha = 0; }
                     completion:^(BOOL finished) { [snap removeFromSuperview]; }];
}

- (void)playInteractionPulse {
    CAKeyframeAnimation *pulse = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    pulse.values = @[@1, @0.975, @1];
    pulse.duration = 0.28;
    [self.content.layer addAnimation:pulse forKey:@"interactionPulse"];
}

#pragma mark 文字

- (void)setNotifTitle:(NSString *)title message:(NSString *)message {
    self.textKind = IKTextKindNotif;
    [self applyTextStyles];
    [self.row1 setText:title change:IKLineChangeFade];
    [self.row2 setText:message change:IKLineChangeFade];
    [self.row1 setDuration:0 elapsed:0 playing:NO fill:NO];
    [self.row2 setDuration:0 elapsed:0 playing:NO fill:NO];
}

- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle playing:(BOOL)playing {
    self.textKind = IKTextKindPlain;
    [self applyTextStyles];
    [self.row1 setText:title change:IKLineChangeFade];
    [self.row2 setText:subtitle change:IKLineChangeFade];
    [self.row1 setDuration:0 elapsed:0 playing:playing fill:NO];
    [self.row2 setDuration:0 elapsed:0 playing:playing fill:NO];
}

- (void)setLyric:(NSString *)lyric title:(NSString *)title
    lineDuration:(double)lineDuration elapsed:(double)elapsed playing:(BOOL)playing {
    self.textKind = IKTextKindLyric;
    [self applyTextStyles];
    BOOL two = self.lyricLines >= 2;
    IKLineView *lyricRow = two ? self.row2 : self.row1;
    // 换句的动画只作用在歌词这一行；歌名只有自己的文字变了才淡入一次
    IKLineChange change = self.lyricEffect == 0 ? IKLineChangeNone : (self.lyricEffect == 2 ? IKLineChangeFade : IKLineChangePush);
    if (two) {
        [self.row1 setText:title change:IKLineChangeFade];
        [self.row1 setDuration:0 elapsed:0 playing:playing fill:NO];
    } else {
        [self.row2 setText:@"" change:IKLineChangeNone];
        [self.row2 setDuration:0 elapsed:0 playing:NO fill:NO];
    }
    [lyricRow setText:lyric change:change];
    [lyricRow setDuration:lineDuration elapsed:elapsed playing:playing fill:(self.lyricEffect == 1)];
}

#pragma mark 通知、音柱、进度环

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

// 开关进度环时淡入淡出，不再一下子出现或消失（形变期间也照常显示，见 ringHolder 的说明）
- (void)setShowsProgress:(BOOL)showsProgress {
    if (_showsProgress == showsProgress) return;
    _showsProgress = showsProgress;
    CGFloat alpha = showsProgress ? 1 : 0;
    if (!self.window) {
        [self.ringBox.layer removeAnimationForKey:@"opacity"];
        self.ringBox.alpha = alpha;
        return;
    }
    [UIView animateWithDuration:0.22 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.ringBox.alpha = alpha; } completion:nil];
}

- (void)setProgress:(CGFloat)progress {
    CGFloat p = MAX(0, MIN(1, progress));
    BOOL small = fabs(p - _progress) < 0.05;
    _progress = p;
    [self applyWedgeAnimated:(small && !self.resizingShell && self.window != nil)];
}

static CGFloat IKShellRadius(CGSize size, BOOL coversCutout) {
    return MAX(0, MIN(size.height / 2, coversCutout ? 36 : 29));
}

// 按此刻看得见的胶囊尺寸，把遮罩扇形张到 progress 对应的角度。
// 形变期间每一帧都按看得见的尺寸重算一次：扇形只决定进度走到哪里，晚一帧看不出来
- (void)applyWedgeAnimated:(BOOL)animated {
    CGSize size = (self.resizingShell && self.sizeLink) ? self.drawnSize : self.bounds.size;
    self.wedgeSize = size;
    CGFloat w = MAX(1, size.width - 1), h = MAX(1, size.height - 1);
    CGFloat r = MAX(0, IKShellRadius(size, self.coversCutout) - 0.5);
    // 描边宽 2，按描边中线算角度
    CGFloat end = IKRingAngle(w - 2, h - 2, MAX(0, r - 1), self.progress);
    CGFloat c = IKWedgeSide / 2, R = IKWedgeSide / 2;
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, c, c);
    for (NSInteger i = 0; i <= IKWedgeSteps; i++) {
        CGFloat a = -M_PI_2 + (end + M_PI_2) * i / IKWedgeSteps;
        CGPathAddLineToPoint(path, NULL, c + R * cos(a), c + R * sin(a));
    }
    CGPathCloseSubpath(path);
    CAShapeLayer *shape = (CAShapeLayer *)self.ringWedge.layer;
    if (animated && shape.path) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"path"];
        CAShapeLayer *shown = (CAShapeLayer *)shape.presentationLayer;
        a.fromValue = (__bridge id)((shown && shown.path) ? shown.path : shape.path);
        a.toValue = (__bridge id)path;
        a.duration = 0.25;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [shape addAnimation:a forKey:@"ik.progress"];
    } else {
        [shape removeAnimationForKey:@"ik.progress"];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    shape.path = path;
    [CATransaction commit];
    CGPathRelease(path);
}

// 环和胶囊外形：在 layoutSubviews 里、不包 performWithoutAnimation 地设置，
// 胶囊在动画块里改尺寸时，它们就和胶囊用同一个弹簧，一帧不差
- (void)layoutShell {
    CGSize size = self.bounds.size;
    CGFloat radius = IKShellRadius(size, self.coversCutout);
    self.layer.cornerRadius = radius;
    CGRect bounds = (CGRect){CGPointZero, size};
    self.ringHolder.frame = bounds;
    self.ringBox.frame = bounds;
    CGRect ringRect = CGRectInset(bounds, 0.5, 0.5);
    for (UIView *v in @[self.ringTrack, self.ring]) {
        v.frame = ringRect;
        v.layer.cornerRadius = MAX(0, radius - 0.5);
    }
    self.ringWedge.center = CGPointMake(ringRect.size.width / 2, ringRect.size.height / 2);
}

- (void)playNotifEntrance {
    // Presentation-only animation keeps the layout frames valid if a notification interrupts a resize.
    CABasicAnimation *pop = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pop.fromValue = @0.78;
    pop.toValue = @1;
    pop.duration = 0.22;
    [self.iconView.layer addAnimation:pop forKey:@"notificationEntrance"];
    for (UIView *row in @[self.row1, self.row2, self.appLabel]) {
        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        slide.fromValue = @5;
        slide.toValue = @0;
        slide.duration = 0.2;
        [row.layer addAnimation:slide forKey:@"notificationEntrance"];
    }
}

#pragma mark 布局

- (void)beginFollowingShell {
    if (self.resizingShell) return;
    self.resizingShell = YES;
    self.drawnSize = (self.layer.presentationLayer ?: self.layer).bounds.size;
    self.drawnFit = self.drawnSize;
    self.sizeLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(followShell:)];
    [self.sizeLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self setNeedsLayout];
}

- (void)endFollowingShell {
    self.resizingShell = NO;
    [self.sizeLink invalidate];
    self.sizeLink = nil;
    [UIView performWithoutAnimation:^{ [self layoutContentForSize:self.bounds.size]; }];
    [self refreshWedgeIfSizeChanged];
    [self setNeedsLayout];
}

- (void)followShell:(CADisplayLink *)link {
    CALayer *visible = self.layer.presentationLayer;
    if (!visible || CGSizeEqualToSize(visible.bounds.size,self.drawnSize)) return;
    CGSize now = visible.bounds.size, before = self.drawnSize;
    self.drawnSize = now;
    // 这里排好的内容要到下一帧才显示，那时胶囊又变了一点。变小的方向往前多看两帧判断放不放得下
    // （收起用的是先慢后快的曲线，只看一帧不够），免得最后一行文字被胶囊底边切掉；
    // 变大的方向仍按此刻的尺寸，宁可晚一帧出现
    CGSize fit = CGSizeMake(MIN(now.width, now.width + 2 * (now.width - before.width)),
                            MIN(now.height, now.height + 2 * (now.height - before.height)));
    self.drawnFit = fit;
    [UIView performWithoutAnimation:^{ [self layoutContentForSize:now fitSize:fit]; }];
    [self refreshWedgeIfSizeChanged];
}

- (void)refreshWedgeIfSizeChanged {
    CGSize size = (self.resizingShell && self.sizeLink) ? self.drawnSize : self.bounds.size;
    if (CGSizeEqualToSize(size, self.wedgeSize)) return;
    self.wedgeSize = size;
    [self applyWedgeAnimated:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 外形和环跟着当前的动画走；内容按此刻看得见的尺寸排，不做动画
    [self layoutShell];
    CGSize size = self.resizingShell ? (self.sizeLink ? self.drawnSize : CGSizeZero) : self.bounds.size;
    // 形变期间的其他布局（属性变化触发的）沿用逐帧算出的“放不放得下”，不要把刚藏起来的内容又放出来
    CGSize fit = (self.resizingShell && self.sizeLink) ? self.drawnFit : size;
    [UIView performWithoutAnimation:^{ [self layoutContentForSize:size fitSize:fit]; }];
    [self refreshWedgeIfSizeChanged];
}

- (void)layoutContentForSize:(CGSize)size {
    [self layoutContentForSize:size fitSize:size];
}

// size 决定各元素摆在哪里；fit 决定放不放得下（形变时可能比 size 小一点，见 followShell:）
- (void)layoutContentForSize:(CGSize)size fitSize:(CGSize)fit {
    CGFloat W = size.width, H = size.height;
    self.content.frame = (CGRect){CGPointZero,size};

    BOOL compact = (self.state == IKStateMusicCompact);
    BOOL lyric   = (self.state == IKStateLyric);
    BOOL notif   = (self.state == IKStateNotif);
    BOOL two     = notif || (lyric && self.lyricLines >= 2);

    CGFloat bandHeight = self.cutoutBand > 0 ? self.cutoutBand : 37;
    CGRect disc = IKCoverDisc(size, self.cutoutWidth, bandHeight);
    IKCoverTextLayout rows = IKCoverRows(size, bandHeight, notif ? 70 : CGRectGetMaxX(disc) + 12, two);
    CGRect fitDisc = IKCoverDisc(fit, self.cutoutWidth, bandHeight);
    IKCoverTextLayout fitRows = IKCoverRows(fit, bandHeight, notif ? 70 : CGRectGetMaxX(fitDisc) + 12, two);
    CGFloat side = MAX(0,(W-self.cutoutWidth)/2);
    BOOL decorFits = !self.coversCutout || MAX(0, (fit.width - self.cutoutWidth) / 2) >= 32;
    BOOL textFits = self.coversCutout ? fitRows.fits
        : (fit.width >= (notif ? 200 : 104) && fit.height >= (two ? 42 : 24));
    self.cover.hidden    = !(compact || lyric) || !decorFits || (self.coversCutout && lyric && fitDisc.size.width < 22);
    self.barsView.hidden = !(compact || lyric) || !decorFits;
    self.iconView.hidden = !notif || !decorFits;
    self.appLabel.hidden = !notif || !decorFits;
    self.row1.hidden     = !(lyric || notif) || !textFits;
    self.row2.hidden     = !two || !textFits;

    if (!self.coversCutout) {
        // 独立胶囊：左边封面或图标，中间文字，右边音柱
        if (compact) {
            self.cover.frame = CGRectMake(4, (H - 26) / 2, 26, 26);
            self.barsView.frame = CGRectMake(W - 12 - 18, (H - 16) / 2, 18, 16);
        } else if (lyric) {
            CGFloat c = MAX(0,H - 12);
            self.cover.frame = CGRectMake(6, 6, c, c);
            self.barsView.frame = CGRectMake(W - 16 - 18, (H - 16) / 2, 18, 16);
            CGFloat x = 6 + c + 10, w = MAX(0,W - x - 16 - 18 - 10);
            if (two) {
                self.row1.frame = CGRectMake(x, H / 2 - 21, w, 22);
                self.row2.frame = CGRectMake(x, H / 2 + 2, w, 18);
            } else {
                self.row1.frame = CGRectMake(x, (H - 22) / 2, w, 22);
            }
        } else if (notif) {
            self.iconView.frame = CGRectMake(8, (H - 42) / 2, 42, 42);
            CGFloat x = 60, w = W - x - 18;
            self.appLabel.frame = CGRectMake(W - 18 - 96, H / 2 - 19, 96, 16);
            self.row1.frame = CGRectMake(x, H / 2 - 21, MAX(0,w - 102), 22);
            self.row2.frame = CGRectMake(x, H / 2 + 2, w, 18);
        }
    } else {
        // 开孔占据顶部 band 高、居中 cutoutWidth 宽的区域，文字一律放到它下面
        CGFloat band = self.cutoutBand > 0 ? self.cutoutBand : 37;
        if (compact) {
            self.cover.frame = CGRectMake(5, (H - 27) / 2, 27, 27);
            self.barsView.frame = CGRectMake(W - 14 - 18, (H - 16) / 2, 18, 16);
        } else if (lyric) {
            self.cover.frame = disc;
            self.barsView.frame = CGRectMake(W - 20 - 18, (band - 16) / 2, 18, 16);
            self.row1.frame = rows.first;
            self.row2.frame = rows.second;
        } else if (notif) {
            CGFloat iconSize = MAX(0,MIN(44,MIN(H-6,side-14)));
            self.iconView.frame = CGRectMake(14, (H-iconSize)/2, iconSize, iconSize);
            CGFloat ax = W / 2 + self.cutoutWidth / 2 + 6;
            self.appLabel.frame = CGRectMake(ax, (band - 16) / 2, MAX(0, W - ax - 16), 16);
            self.row1.frame = rows.first;
            self.row2.frame = rows.second;
        }
    }
    [self placeTextForSize:size lyric:lyric two:two band:bandHeight];
    self.iconView.layer.cornerRadius = self.iconRound ? self.iconView.bounds.size.width / 2 : 11;
    [self.content layoutIfNeeded];
}

// 歌词态的文字位置。居中和自定义都以整个胶囊的中线（= 屏幕中线）为基准，
// 而不是封面右边剩下那块文字区域的中间；自定义再加上左右、上下偏移。
// 文字只在自己那一行里移动，所以不会压到封面、音柱或胶囊边缘，到边就停住
- (void)placeTextForSize:(CGSize)size lyric:(BOOL)lyric two:(BOOL)two band:(CGFloat)band {
    if (!lyric) {
        self.row1.anchor = NAN;
        self.row2.anchor = NAN;
        return;
    }
    BOOL custom = (self.lyricAlignment == 3);
    if (custom && fabs(self.lyricOffsetY) > 0.01) {
        CGRect used = two ? CGRectUnion(self.row1.frame, self.row2.frame) : self.row1.frame;
        // 覆盖模式下不能往上移进开孔那一条
        CGFloat top = self.coversCutout ? band + 1 : 3, bottom = size.height - 3;
        CGFloat dy = MIN(bottom - CGRectGetMaxY(used), self.lyricOffsetY);
        dy = MAX(top - CGRectGetMinY(used), dy);
        self.row1.frame = CGRectOffset(self.row1.frame, 0, dy);
        if (two) self.row2.frame = CGRectOffset(self.row2.frame, 0, dy);
    }
    CGFloat mid = size.width / 2 + (custom ? self.lyricOffsetX : 0);
    self.row1.anchor = mid - CGRectGetMinX(self.row1.frame);
    self.row2.anchor = mid - CGRectGetMinX(self.row2.frame);
}

@end
