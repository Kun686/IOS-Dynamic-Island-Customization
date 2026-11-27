// Exercise the real HUD and settings entry points against fixture media events and local directories.
#import "IKPrefs.h"
#import "MediaRemote.h"
#import "IKMusicCenter.h"

static NSString *store, *bundle;
static NSDictionary *metadata;
static BOOL playing, delayBundle;
static void (^bundleReply)(NSString *);
static NSMutableArray<NSString *> *messages;

@implementation UIImage
+ (instancetype)imageWithData:(NSData *)data { return data.length ? [self new] : nil; }
@end
@implementation IKPrefs
+ (void)log:(NSString *)message { [messages addObject:message]; }
@end

@interface FixtureApp : NSObject
@property(nonatomic, strong) NSURL *dataContainerURL;
@end
@implementation FixtureApp
+ (instancetype)applicationProxyForIdentifier:(NSString *)bid {
    FixtureApp *app = [self new];
    app.dataContainerURL = [NSURL fileURLWithPath:[store stringByAppendingPathComponent:bid] isDirectory:YES];
    return app;
}
@end

// Only the platform callbacks, container locator, image decode and log sink are replaced.
#define NSClassFromString(name) FixtureApp.class
#undef IKDataDir
#define IKDataDir store
#import "../sources/IKMusicCenter.m"
#undef NSClassFromString
#define MRKEY(name) CFStringRef kMRMediaRemoteNowPlayingInfo##name = CFSTR(#name)
MRKEY(Title); MRKEY(Artist); MRKEY(Album); MRKEY(Duration); MRKEY(ElapsedTime); MRKEY(ArtworkData);
MRKEY(Timestamp); MRKEY(PlaybackRate); MRKEY(ExternalContentIdentifier); MRKEY(UniqueIdentifier); MRKEY(QueueIndex);
NSString *kMRMediaRemoteNowPlayingInfoDidChangeNotification = @"info";
NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification = @"playing";
NSString *kMRMediaRemoteNowPlayingApplicationDidChangeNotification = @"application";
void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t q) {}
void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t q, void (^reply)(CFDictionaryRef)) { reply((__bridge CFDictionaryRef)metadata); }
void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t q, void (^reply)(Boolean)) { reply(playing); }
void MRMediaRemoteGetNowPlayingApplicationDisplayID(dispatch_queue_t q, void (^reply)(NSString *)) {
    if (delayBundle) bundleReply = reply;
    else reply(bundle);
}

static int count;
static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr,"FAIL %s\n",message); exit(1); }
    count++;
}

static NSDictionary *settingsTarget(void) {
    __block NSDictionary *result;
    [IKMusicCenter requestImportTarget:^(NSDictionary *target) { result = target; }];
    return result;
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    store = [@(argv[1]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    bundle = @"com.tencent.QQMusic";
    messages = [NSMutableArray array];
    playing = YES;
    metadata = @{@"Title":@"歌曲", @"Artist":@"歌手", @"Duration":@180, @"ElapsedTime":@42,
                 @"QueueIndex":@1, @"ArtworkData":[@"cover" dataUsingEncoding:NSUTF8StringEncoding]};
    IKMusicCenter *m = IKMusicCenter.shared;
    [m refresh];
    UIImage *cover = m.artwork;
    NSString *session = m.recording[@"playSession"];
    check(m.hasTrack && m.isPlaying && cover && session, "initial song and cover");
    metadata = @{@"Title":@"甲", @"Artist":@"歌手", @"Duration":@180};
    [m refresh];
    metadata = @{@"Title":@"乙", @"Artist":@"歌手", @"Duration":@180};
    [m refresh];
    metadata = @{@"Title":@"乙", @"Artist":@"丙", @"Duration":@180};
    [m refresh];
    check([m.reportedLyric isEqual:@"丙"] && [m.recording[@"title"] isEqual:@"歌曲"], "alternate car fields use latest line and stable title");
    check([session isEqual:m.recording[@"playSession"]] && m.currentElapsed >= 42 && m.artwork == cover, "line-only packets retain session, position and cover");
    NSDictionary *target = settingsTarget();
    check([target[@"title"] isEqual:@"歌曲"] && [target[@"artist"] isEqual:@"歌手"], "settings opened mid-song sees same canonical target");
    NSURL *file = [NSURL fileURLWithPath:[store stringByAppendingPathComponent:@"fixture.lrc"]];
    NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    check([@"[00:00]首句\n[00:40]当前\n[01:00]下句" writeToURL:file atomically:YES encoding:gb error:nil], "write GBK fixture");
    check(![IKMusicCenter importLyricsAtURL:file target:target], "normal settings import");
    [m refresh];
    check(m.lyricsBridgeActive && [m.bridgeLyric isEqual:@"当前"] && [m.bridgeTitle isEqual:@"歌曲"], "matching imported line at real clock");
    metadata = @{@"Title":@"丁", @"Artist":@"丙", @"UniqueIdentifier":@75, @"Duration":@180};
    [m refresh];
    check([m.bridgeLyric isEqual:@"当前"] && m.artwork == cover && m.currentElapsed >= 42, "late stable ID preserves old import and artwork");
    check([settingsTarget()[@"mode"] isEqual:@"已绑定本地时间轴"], "settings can find original metadata filename after ID arrives");
    playing = NO; [m refresh];
    double parked = m.currentElapsed;
    check(m.playbackSpeed == 0 && parked >= 42, "missing position on pause stays at playhead");
    playing = YES; [m refresh];
    check(fabs(m.currentElapsed-parked)<0.5 && m.playbackSpeed > 0, "resume has no jump");
    check(![IKMusicCenter removeImport:settingsTarget()], "remove through actual settings entry");
    [m refresh];
    check(!m.lyricsBridgeActive && [m.reportedLyric isEqual:@"丁"], "remove old filename returns to current car line");
    metadata = @{@"Title":@"同长歌曲", @"Artist":@"歌手", @"Duration":@180, @"QueueIndex":@2};
    [m refresh];
    check(![session isEqual:m.recording[@"playSession"]] && !m.artwork && m.currentElapsed < 1, "real track switch clears artwork and resets a missing position");
    check([[messages filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@",@"recording app="]] count] == 2,
          "identity availability logged once per track");
    bundle = @"com.netease.cloudmusic";
    metadata = @{@"Title":@"网易曲目",@"Artist":@"歌手",@"Duration":@180,@"ElapsedTime":@28};
    delayBundle = YES;
    [m applicationChanged];
    check([m.title isEqual:@"网易曲目"] && m.currentElapsed >= 28 && !m.lyricsBridgeActive && !m.mediaApplicationID,
          "now-playing display does not depend on app-ID callback");
    delayBundle = NO; bundleReply(bundle);
    check([settingsTarget()[@"bundleID"] isEqual:bundle] && !m.artwork, "late app-ID scopes handoff to new player");
    IKRecordingTracker *producer = [IKRecordingTracker new];
    [producer observe:IKTrackIdentity(nil,nil,@"原曲",@"原唱",212) album:nil queueIndex:@3 position:@0 bundle:bundle];
    NSDictionary *raw = IKTrackIdentity(nil,nil,@"原曲",@"播放器当前句",212);
    [producer observe:raw album:nil queueIndex:@3 position:@63 bundle:bundle];
    NSURL *recordingFile = [NSURL fileURLWithPath:IKAdjacentFile(IKPlayerLyricsPath(bundle),@"recording.plist")];
    check([producer writeSnapshotTo:recordingFile canonical:nil force:YES], "host publishes no-ID handoff in its container");
    metadata = @{@"Title":@"原曲",@"Artist":@"播放器当前句",@"Duration":@212,@"QueueIndex":@3,@"ElapsedTime":@63};
    [m refresh];
    check([m.reportedLyric isEqual:@"播放器当前句"] && [m.recording[@"artist"] isEqual:@"原唱"], "HUD joins host mid-verse");
    check([settingsTarget()[@"mode"] isEqual:@"播放器单句（无时间标签）"], "settings distinguishes host single cue from a timeline");
    metadata = @{@"Title":@"原曲",@"Artist":@"系统新句",@"Duration":@212,@"UniqueIdentifier":@98};
    [m refresh];
    check([m.reportedLyric isEqual:@"系统新句"] && [m.recording[@"persistentID"] isEqual:@"98"], "HUD keeps newer line and fills late ID with a paired host");
    check([settingsTarget()[@"artist"] isEqual:@"原唱"], "settings still has canonical artist on staggered callbacks");
    // When the host restarts, its new session ID alone does not imply a different song.
    IKRecordingTracker *restarted = [IKRecordingTracker new];
    [restarted observe:IKTrackIdentity(nil,@98,@"原曲",@"原唱",212) album:nil queueIndex:@3 position:@63 bundle:bundle];
    [restarted writeSnapshotTo:recordingFile canonical:nil force:YES];
    [m refresh];
    check(m.currentElapsed >= 63, "reopening adapter during same recording preserves playhead");
    metadata = @{}; [m refresh];
    check(!m.hasTrack && !m.reportedLyric && !m.recording, "empty playback clears song");
    if (![NSFileManager.defaultManager removeItemAtPath:store error:nil]) return 2;
    printf("HUD and settings: %d checks passed\n",count);
    return 0;
} }
