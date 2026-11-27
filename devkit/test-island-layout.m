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

int main(void) { @autoreleasepool {
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
    UIView *track = [row1 valueForKey:@"track"];
    CALayer *ring = [v valueForKey:@"ring"], *outline = [v valueForKey:@"ringTrack"];
    check([[row1 valueForKey:@"text"] isEqual:@"当前句"] && row2.hidden, "one lyric row");
    check(v.cover.bounds.size.width == 38, "single row cover");
    for (NSInteger choice = 0; choice <= 2; choice++) {
        v.lyricAlignment = choice;
        [row1 layoutIfNeeded];
        CGFloat free = row1.bounds.size.width-track.bounds.size.width;
        check(fabs(track.frame.origin.x-choice*free/2)<0.01, "base and fill track aligned within the row");
    }
    NSString *longLine = [@"长歌词" stringByPaddingToLength:90 withString:@"长歌词" startingAtIndex:0];
    for (NSInteger choice = 0; choice <= 2; choice++) {
        v.lyricAlignment = choice;
        [v setLyric:longLine title:@"歌名" lineDuration:8 elapsed:0 playing:NO];
        [v layoutIfNeeded];
        check(track.bounds.size.width > row1.bounds.size.width && fabs(track.frame.origin.x)<0.01,
              "overflowing lyrics start at the first character for every alignment");
        [v setLyric:longLine title:@"歌名" lineDuration:8 elapsed:8 playing:NO];
        check(fabs(CGRectGetMaxX(track.frame) - row1.bounds.size.width)<0.01, "last character visible at line end");
    }
    v.lyricLines = 2;
    v.frame = CGRectMake(0,0,381,94);
    [v setLyric:@"当前句" title:@"歌名" lineDuration:8 elapsed:4 playing:NO];
    [v layoutIfNeeded];
    check(!row2.hidden && [[row1 valueForKey:@"text"] isEqual:@"歌名"] && [[row2 valueForKey:@"text"] isEqual:@"当前句"], "title above lyric");
    check(v.cover.bounds.size.width == 54 && CGRectGetMinX(row2.frame)>CGRectGetMaxX(v.cover.frame), "two row cover clears lyrics");
    [v beginFollowingShell];
    v.showsProgress = NO;
    v.showsProgress = YES;
    [v beginFollowingShell];
    check(ring.hidden && outline.hidden, "retarget and refresh keep both strokes hidden");
    for (int i = 0; i <= 60; i++) {
        CGFloat f = i/60.;
        CGSize shell = CGSizeMake(119+262*f,31+63*f);
        [v layoutContentForSize:shell];
        check(ring.hidden && outline.hidden, "both progress strokes hidden on every intermediate frame");
        check(v.cover.hidden || CGRectGetMaxX(v.cover.frame)<=(shell.width-v.cutoutWidth)/2-6, "cover clears cutout");
        check(row2.hidden || CGRectGetMaxY(row2.frame)+5<=shell.height, "show only complete rows");
    }
    [v layoutContentForSize:CGSizeMake(198,51)];
    check(v.cover.hidden && row1.hidden && row2.hidden && ring.hidden, "reported screenshot size");
    [v endFollowingShell];
    NSArray *layers = ring.superlayer.sublayers;
    check(!ring.hidden && !outline.hidden && [layers indexOfObject:ring]<[layers indexOfObject:v.cover.layer],
          "restore the ring behind cover after settling");
    v.state = IKStateMusicCompact;
    [v layoutIfNeeded];
    check(row1.hidden && row2.hidden && !v.cover.hidden, "compact only displays music decorations");
    v.state = IKStateNotif;
    [v setNotifTitle:@"发送者" message:@"正文"];
    [v layoutIfNeeded];
    check([[row1 valueForKey:@"alignment"] integerValue]==0 && [[row2 valueForKey:@"alignment"] integerValue]==0,
          "notification text keeps its own alignment");
    NSLog(@"UIKit layout: %lu checks passed", (unsigned long)checks);
    return 0;
} }
