// Exercise the shipping UIKit view, including its sublayers, without a player or window server.
#import "IKIslandView.h"

@interface IKIslandView (LayoutFixture)
- (void)layoutContentForSize:(CGSize)size;
@end

static NSUInteger checks;
static void check(BOOL ok, const char *name) {
    if (!ok) { fprintf(stderr, "FAIL %s\n", name); exit(1); }
    checks++;
}
static BOOL near(CGFloat a, CGFloat b, CGFloat tol) { return fabs(a - b) <= tol; }

// 文字（track）中心在岛坐标里的横坐标
static CGFloat textCenter(UIView *row, UIView *track) {
    return CGRectGetMinX(row.frame) + CGRectGetMidX(track.frame);
}

static BOOL hasAnimation(CALayer *layer, NSString *prefix) {
    for (NSString *key in layer.animationKeys) if ([key hasPrefix:prefix]) return YES;
    return NO;
}

static CAAnimation *animationWithPrefix(CALayer *layer, NSString *prefix) {
    for (NSString *key in layer.animationKeys) if ([key hasPrefix:prefix]) return [layer animationForKey:key];
    return nil;
}

int main(void) { @autoreleasepool {
    // ---- 进度环遮罩的角度 ----
    check(near(IKRingAngle(100,100,0,0), -M_PI_2, 1e-6), "ring starts at twelve o'clock");
    check(near(IKRingAngle(100,100,0,0.25), 0, 1e-6), "quarter of a square is three o'clock");
    check(near(IKRingAngle(100,100,0,0.5), M_PI_2, 1e-6), "half is six o'clock");
    check(near(IKRingAngle(100,100,0,0.75), M_PI, 1e-6), "three quarters is nine o'clock");
    check(near(IKRingAngle(100,100,0,0.999), 1.5*M_PI, 0.02) && near(IKRingAngle(100,100,0,1), 1.5*M_PI, 1e-6), "full ring");
    CGFloat last = -10;
    BOOL monotonic = YES;
    for (int i = 0; i <= 200; i++) {
        CGFloat a = IKRingAngle(378, 92, 35, i / 200.0);
        if (a < last - 1e-6) monotonic = NO;
        last = a;
    }
    check(monotonic, "ring angle grows clockwise along a capsule");

    // ---- 单行歌词、覆盖模式 ----
    IKIslandView *v = [[IKIslandView alloc] initWithFrame:CGRectMake(0,0,381,78)];
    v.coversCutout = YES;
    v.cutoutBand = 38;
    v.cutoutWidth = 125;
    v.lyricLines = 1;
    v.state = IKStateLyric;
    v.showsProgress = YES;
    v.progress = 0.7;
    [v setLyric:@"当前句" title:@"歌名" lineDuration:8 elapsed:4 playing:NO];
    [v layoutIfNeeded];
    UIView *row1 = [v valueForKey:@"row1"], *row2 = [v valueForKey:@"row2"];
    UIView *track = [row1 valueForKey:@"track"], *track2 = [row2 valueForKey:@"track"];
    UIView *ring = [v valueForKey:@"ring"], *outline = [v valueForKey:@"ringTrack"];
    UIView *ringBox = [v valueForKey:@"ringBox"], *ringHolder = [v valueForKey:@"ringHolder"];
    UIView *content = [v valueForKey:@"content"], *wedge = [v valueForKey:@"ringWedge"];
    check([[row1 valueForKey:@"text"] isEqual:@"当前句"] && row2.hidden, "one lyric row");
    check(v.cover.bounds.size.width == 38, "single row cover");

    CGFloat W = v.bounds.size.width;
    v.lyricAlignment = 0;
    [v layoutIfNeeded];
    check(near(track.frame.origin.x, 0, 0.01), "left alignment starts at the row");
    v.lyricAlignment = 2;
    [v layoutIfNeeded];
    check(near(CGRectGetMaxX(track.frame), row1.bounds.size.width, 0.01), "right alignment ends at the row");
    v.lyricAlignment = 1;
    [v layoutIfNeeded];
    check(near(textCenter(row1, track), W / 2, 0.5), "center alignment uses the shell midline, not the text area");
    check(CGRectGetMinX(row1.frame) > 40 && !near(CGRectGetMidX(row1.frame), W / 2, 5),
          "fixture: the text area itself is off-center because of the cover");

    // 自定义：左右偏移、到边停住、上下偏移不进开孔那条
    v.lyricAlignment = 3;
    v.lyricOffsetX = 40;
    [v layoutIfNeeded];
    check(near(textCenter(row1, track), W / 2 + 40, 0.5), "custom offset moves the text center");
    v.lyricOffsetX = -200;
    [v layoutIfNeeded];
    check(near(track.frame.origin.x, 0, 0.01), "custom offset stops beside the cover");
    v.lyricOffsetX = 300;
    [v layoutIfNeeded];
    check(near(CGRectGetMaxX(track.frame), row1.bounds.size.width, 0.01), "custom offset stops at the right edge");
    v.lyricOffsetX = 0;
    CGFloat baseY = CGRectGetMinY(row1.frame);
    v.lyricOffsetY = 4;
    [v layoutIfNeeded];
    check(near(CGRectGetMinY(row1.frame), baseY + 4, 0.01), "custom offset moves the text down");
    v.lyricOffsetY = 12;
    [v layoutIfNeeded];
    check(CGRectGetMaxY(row1.frame) <= v.bounds.size.height - 3 + 0.01, "text never leaves the shell bottom");
    v.lyricOffsetY = -12;
    [v layoutIfNeeded];
    check(CGRectGetMinY(row1.frame) >= 38 + 1 - 0.01, "text never moves into the cutout band");
    v.lyricOffsetY = 0;
    v.lyricAlignment = 2;
    v.lyricOffsetX = 80;
    [v layoutIfNeeded];
    check(near(CGRectGetMaxX(track.frame), row1.bounds.size.width, 0.01), "offsets only apply to the custom position");
    v.lyricOffsetX = 0;

    NSString *longLine = [@"长歌词" stringByPaddingToLength:90 withString:@"长歌词" startingAtIndex:0];
    for (NSInteger choice = 0; choice <= 3; choice++) {
        v.lyricAlignment = choice;
        [v setLyric:longLine title:@"歌名" lineDuration:8 elapsed:0 playing:NO];
        [v layoutIfNeeded];
        check(track.bounds.size.width > row1.bounds.size.width && fabs(track.frame.origin.x)<0.01,
              "overflowing lyrics start at the first character for every alignment");
        [v setLyric:longLine title:@"歌名" lineDuration:8 elapsed:8 playing:NO];
        check(fabs(CGRectGetMaxX(track.frame) - row1.bounds.size.width)<0.01, "last character visible at line end");
    }

    // ---- 进度环：用视图描边画，几何跟着胶囊 ----
    CGRect expectRing = CGRectInset(v.bounds, 0.5, 0.5);
    check(CGRectEqualToRect(ring.frame, expectRing) && CGRectEqualToRect(outline.frame, expectRing),
          "ring hugs the shell edge");
    check(near(ring.layer.cornerRadius, v.layer.cornerRadius - 0.5, 0.01) && near(v.layer.cornerRadius, 36, 0.01),
          "ring corner follows the shell corner");
    check(ringBox.alpha == 1 && ringHolder.alpha == 1 && ring.maskView == wedge && ((CAShapeLayer *)wedge.layer).path,
          "progress ring visible and masked");
    check(near(wedge.center.x, expectRing.size.width / 2, 0.01) && near(wedge.center.y, expectRing.size.height / 2, 0.01),
          "wedge mask centered on the ring");
    NSArray *subs = v.subviews;
    check([subs indexOfObject:ringHolder] < [subs indexOfObject:content], "ring stays behind the cover and text");

    // ---- 双行 ----
    v.lyricAlignment = 1;
    v.lyricLines = 2;
    v.frame = CGRectMake(0,0,381,94);
    [v setLyric:@"当前句" title:@"歌名" lineDuration:8 elapsed:4 playing:NO];
    [v layoutIfNeeded];
    check(!row2.hidden && [[row1 valueForKey:@"text"] isEqual:@"歌名"] && [[row2 valueForKey:@"text"] isEqual:@"当前句"], "title above lyric");
    check(v.cover.bounds.size.width == 54 && CGRectGetMinX(row2.frame)>CGRectGetMaxX(v.cover.frame), "two row cover clears lyrics");
    check(near(textCenter(row1, track), W / 2, 0.5) && near(textCenter(row2, track2), W / 2, 0.5),
          "both rows center on the shell midline");

    // ---- 形变：环在同一个动画块里跟着胶囊，内容逐帧排版 ----
    [v beginFollowingShell];
    v.showsProgress = NO;
    v.showsProgress = YES;
    check(ringBox.alpha == 1 && !ringBox.hidden && !ring.hidden, "ring stays visible while the shell resizes");
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4 options:0 animations:^{
        v.frame = CGRectMake(60, 0, 260, 40);
        [v layoutIfNeeded];
    } completion:nil];
    check(hasAnimation(v.layer, @"bounds") && hasAnimation(v.layer, @"cornerRadius"), "fixture: shell animates in the block");
    check(hasAnimation(ring.layer, @"bounds") && hasAnimation(outline.layer, @"bounds") &&
          hasAnimation(ring.layer, @"cornerRadius") && hasAnimation(wedge.layer, @"position"),
          "ring geometry animates in the same block as the shell");
    CAAnimation *shellAnim = animationWithPrefix(v.layer, @"bounds"), *ringAnim = animationWithPrefix(ring.layer, @"bounds");
    check(shellAnim && ringAnim && [shellAnim class] == [ringAnim class] && near(shellAnim.duration, ringAnim.duration, 1e-6) &&
          near(shellAnim.beginTime, ringAnim.beginTime, 1e-3),
          "ring uses the same spring timing as the shell");
    if ([shellAnim isKindOfClass:[CASpringAnimation class]]) {
        CASpringAnimation *a = (CASpringAnimation *)shellAnim, *b = (CASpringAnimation *)ringAnim;
        check(a.stiffness == b.stiffness && a.damping == b.damping && a.mass == b.mass, "identical spring parameters");
    }
    check(CGRectEqualToRect(ring.frame, CGRectMake(0.5, 0.5, 259, 39)) && near(v.layer.cornerRadius, 20, 0.01),
          "ring and corner target the new shell");
    for (int i = 0; i <= 60; i++) {
        CGFloat f = i/60.;
        CGSize shell = CGSizeMake(119+262*f,31+63*f);
        [v layoutContentForSize:shell];
        check(CGRectEqualToRect(ring.frame, CGRectMake(0.5, 0.5, 259, 39)), "per-frame content layout leaves the ring to the animation");
        check(v.cover.hidden || CGRectGetMaxX(v.cover.frame)<=(shell.width-v.cutoutWidth)/2-6, "cover clears cutout");
        check(row2.hidden || CGRectGetMaxY(row2.frame)+5<=shell.height, "show only complete rows");
    }
    [v layoutContentForSize:CGSizeMake(198,51)];
    check(v.cover.hidden && row1.hidden && row2.hidden, "reported screenshot size");
    [v stopShellAnimations];
    check(!hasAnimation(v.layer, @"bounds") && !hasAnimation(ring.layer, @"bounds") && !hasAnimation(wedge.layer, @"position"),
          "stopping the shell also stops the ring");
    [v endFollowingShell];
    v.frame = CGRectMake(0, 0, 381, 94);
    [v layoutIfNeeded];
    check(!ring.hidden && ringBox.alpha == 1 && CGRectEqualToRect(ring.frame, CGRectInset(v.bounds, 0.5, 0.5)),
          "ring back on the settled shell");

    // ---- 进度环开关、内容淡出 ----
    v.showsProgress = NO;
    check(ringBox.alpha == 0, "progress off hides the ring");
    v.showsProgress = YES;
    v.contentAlpha = 0;
    check(ringHolder.alpha == 0 && content.alpha == 0, "ring fades with the content");
    v.contentAlpha = 1;
    [v crossfadeContent];
    check(content.alpha == 0 && v.contentAlpha == 0 && ringHolder.alpha == 1,
          "crossfade hides the old content but keeps the ring for its own fade");
    v.contentAlpha = 1;

    v.state = IKStateMusicCompact;
    [v layoutIfNeeded];
    check(row1.hidden && row2.hidden && !v.cover.hidden, "compact only displays music decorations");
    v.state = IKStateNotif;
    v.lyricAlignment = 3;
    v.lyricOffsetX = 60;
    [v setNotifTitle:@"发送者" message:@"正文"];
    [v layoutIfNeeded];
    check([[row1 valueForKey:@"alignment"] integerValue]==0 && [[row2 valueForKey:@"alignment"] integerValue]==0 &&
          near(track.frame.origin.x, 0, 0.01),
          "notification text keeps its own alignment");

    // ---- 悬挂歌词（覆盖模式）：方形封面、右边音柱、开孔下沿一行居中小字 ----
    v.lyricAlignment = 0;
    v.lyricOffsetX = 0;
    v.lyricLines = 1;
    v.frame = CGRectMake(0, 0, 262, 56.67);
    v.state = IKStateLyricHang;
    [v setLyric:@"Where am I without you" title:@"歌名" lineDuration:8 elapsed:2 playing:NO];
    [v layoutIfNeeded];
    UIView *bars = [v valueForKey:@"barsView"];
    check(!v.cover.hidden && !bars.hidden && !row1.hidden && row2.hidden, "hang shows cover, bars and one row");
    check(v.cover.squared && near(v.cover.layer.cornerRadius, round(27 * 0.22), 0.01) && v.cover.bounds.size.width == 27,
          "hang uses a rounded-square artwork");
    check(near(CGRectGetMidY(v.cover.frame), v.bounds.size.height / 2, 0.01) &&
          near(CGRectGetMidY(bars.frame), v.bounds.size.height / 2, 0.01), "artwork and bars centered vertically");
    check(near(CGRectGetMinY(row1.frame), 38 - 1, 0.01) && CGRectGetMaxY(row1.frame) <= v.bounds.size.height - 2,
          "hang lyric sits on the cutout's lower edge");
    check(CGRectGetMinX(row1.frame) >= CGRectGetMaxX(v.cover.frame) && CGRectGetMaxX(row1.frame) <= CGRectGetMinX(bars.frame),
          "hang lyric stays between artwork and bars");
    check([[row1 valueForKey:@"alignment"] integerValue] == 1 && near(textCenter(row1, track), v.bounds.size.width / 2, 0.5),
          "hang lyric centers on the shell midline even with left alignment chosen");
    check(((UILabel *)[row1 valueForKey:@"baseLabel"]).font.pointSize < 14, "hang lyric uses a small font");
    v.lyricAlignment = 3;
    v.lyricOffsetX = 10;
    [v layoutIfNeeded];
    check(near(textCenter(row1, track), v.bounds.size.width / 2 + 10, 0.5), "hang honors the custom offset");
    v.lyricOffsetX = 120;
    [v layoutIfNeeded];
    check(near(CGRectGetMaxX(track.frame), row1.bounds.size.width, 0.01), "hang offset stops before the bars");
    v.lyricAlignment = 0;
    v.lyricOffsetX = 0;
    [v layoutContentForSize:CGSizeMake(200, 45)];
    check(row1.hidden, "hang text hidden while the shell is too short");
    [v layoutIfNeeded];
    v.state = IKStateMusicCompact;
    v.frame = CGRectMake(0, 0, 260, 39.67);
    [v layoutIfNeeded];
    check(!v.cover.squared && near(v.cover.layer.cornerRadius, 13.5, 0.01), "compact goes back to the round disc");

    // ---- 录屏 ----
    UIView *dot = [v valueForKey:@"recordDot"];
    UILabel *recLabel = [v valueForKey:@"recordLabel"];
    check(dot.hidden && recLabel.hidden, "no record marks while not recording");
    v.recording = YES;
    [v layoutIfNeeded];
    check(!dot.hidden && recLabel.hidden && CGRectGetMaxX(dot.frame) <= CGRectGetMinX(bars.frame) &&
          near(CGRectGetMidY(dot.frame), CGRectGetMidY(bars.frame), 0.01), "recording dot beside the bars while music plays");
    v.state = IKStateRecord;
    v.recordElapsed = 83.4;
    [v layoutIfNeeded];
    check(!dot.hidden && !recLabel.hidden && v.cover.hidden && bars.hidden && row1.hidden, "record state shows dot and timer only");
    check([recLabel.text isEqualToString:@"01:23"], "record timer text");
    check(CGRectGetMaxX(dot.frame) <= (v.bounds.size.width - v.cutoutWidth) / 2 &&
          CGRectGetMinX(recLabel.frame) >= (v.bounds.size.width + v.cutoutWidth) / 2, "record marks stay outside the cutout");
    v.recordElapsed = 3725;
    check([recLabel.text isEqualToString:@"1:02:05"], "record timer over an hour");
    v.recording = NO;
    v.state = IKStateMusicCompact;
    [v layoutIfNeeded];
    check(dot.hidden, "dot gone after recording stops");
    NSLog(@"UIKit layout: %lu checks passed", (unsigned long)checks);
    return 0;
} }
