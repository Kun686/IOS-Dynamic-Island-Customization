// Drive the production activation and sampling code in a Mac Catalyst command-line process.
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>

static id published;
static BOOL raiseOnRead, readOnMain;
static NSUInteger reads, checks;

@interface FixtureNowPlaying : NSObject
+ (instancetype)defaultCenter;
@property(nonatomic, readonly) NSDictionary *nowPlayingInfo;
@end
@implementation FixtureNowPlaying
+ (instancetype)defaultCenter { return [self new]; }
- (NSDictionary *)nowPlayingInfo {
    reads++;
    readOnMain = NSThread.isMainThread;
    if (raiseOnRead) [NSException raise:NSInvalidArgumentException format:@"fixture read failed"];
    return published;
}
@end

// Substitute only the host playback dictionary. UIKit activation and dispatch queues are real.
#define MPNowPlayingInfoCenter FixtureNowPlaying
#import "../players/IKPlaybackDiagnostics.m"
#undef MPNowPlayingInfoCenter

static void check(BOOL ok, const char *label) {
    if (!ok) { fprintf(stderr, "FAIL %s\n", label); exit(1); }
    checks++;
}

static void sample(dispatch_queue_t queue, NSDictionary *expected, NSString *expectedIssue) {
    __block BOOL done = NO;
    NSUInteger before = reads;
    IKReadPlaybackInfo(queue, ^(NSDictionary *info, NSString *issue) {
        BOOL onReceiver = dispatch_get_specific(&checks) == &checks;
        dispatch_async(dispatch_get_main_queue(), ^{
            check(onReceiver && readOnMain && reads == before + 1, "one main-thread read per callback on the receiver");
            check(info == expected || [info isEqual:expected], "snapshot contents");
            check(issue == expectedIssue || [issue isEqual:expectedIssue], "read outcome");
            done = YES;
        });
    });
    double deadline = NSProcessInfo.processInfo.systemUptime + 2;
    while (!done && NSProcessInfo.processInfo.systemUptime < deadline) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    }
    check(done, "bounded delivery");
}

int main(void) { @autoreleasepool {
    UIApplication *application = UIApplication.sharedApplication;
    check(!application || application.applicationState != UIApplicationStateActive, "fixture starts before foreground");
    __block NSUInteger starts = 0;
    IKWhenPlayerIsActive(^{ starts++; });
    check(starts == 0 && !reads, "defer startup before first activation");
    for (int i = 0; i < 2; i++) {
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        check(starts == 1, "only one start across activations");
    }
    dispatch_queue_t queue = dispatch_queue_create("islandkit.fixture.playback", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(queue, &checks, &checks, NULL);
    sample(queue, nil, nil);
    published = @"malformed";
    sample(queue, nil, @"invalid-metadata");
    raiseOnRead = YES;
    sample(queue, nil, @"read-error");
    raiseOnRead = NO;
    published = @{MPMediaItemPropertyTitle:@"fixture"};
    sample(queue, published, nil);
    printf("Player activation and sampling: %lu checks passed\n", (unsigned long)checks);
    return 0;
} }
