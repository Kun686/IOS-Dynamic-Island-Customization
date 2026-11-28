// Exercise the real HUD and settings entry points against fixture media events and local directories.
#import "IKPrefs.h"
#import "MediaRemote.h"
#import "IKMusicCenter.h"
#import "IKLocalAvatar.h"
#import <ImageIO/ImageIO.h>
#include <sys/stat.h>

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

static void testPublishedHandoff(IKMusicCenter *center, NSString *fixtures, NSString *player, NSString *directory) {
    [center clearPlayerScope];
    bundle = player;
    playing = NO;
    NSString *path = IKPlayerLyricsPath(bundle);
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *source = [[fixtures stringByAppendingPathComponent:directory] stringByAppendingPathComponent:@"custom-output.plist"];
    check([[NSData dataWithContentsOfFile:source] writeToFile:path atomically:YES], "deliver unmodified producer snapshot");
    NSMutableDictionary *event = [@{@"ExternalContentIdentifier":@"fixture", @"Title":@"测试录音", @"Artist":@"测试歌手",
                                    @"Duration":@98, @"QueueIndex":@1, @"ElapsedTime":@2.499} mutableCopy];
    metadata = event;
    [center refresh];
    check([center.bridgeLyric isEqual:@"甲"] && [settingsTarget()[@"mode"] isEqual:@"播放器时间轴"], "actual adapter snapshot at 2.499 seconds");
    event[@"ElapsedTime"] = @2.5;
    [center refresh];
    check([center.bridgeLyric isEqual:@"乙"] && center.bridgeLyricElapsed == 0, "HUD switches at 2.500 seconds");
    check([messages containsObject:[NSString stringWithFormat:@"lyrics timeline app=%@ source=publishedField key=player.syncedLyrics lines=2",bundle]],
          "HUD records the actual field from the adapter");

    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithContentsOfFile:source];
    event[@"ExternalContentIdentifier"] = snapshot[@"externalID"] = @"second-fixture";
    event[@"QueueIndex"] = @2;
    event[@"ElapsedTime"] = @1;
    [snapshot writeToFile:path atomically:YES];
    [center refresh];
    event[@"Title"] = @"迟到的歌名";
    event[@"Artist"] = @"第一句";
    [center refresh];
    check([center.bridgeTitle isEqual:@"迟到的歌名"] && [center.bridgeLyric isEqual:@"甲"],
          "late corrected title also replaces the cached timeline title");

    [snapshot removeObjectForKey:@"externalID"];
    snapshot[@"unstablePersistentID"] = @YES;
    snapshot[@"persistentID"] = @"77";
    [snapshot writeToFile:path atomically:YES];
    metadata = @{@"UniqueIdentifier":@77, @"Title":@"别的录音", @"Artist":@"别的歌手", @"Duration":@102, @"QueueIndex":@3};
    [center refresh];
    check(!center.lyricsBridgeActive, "a stale timeline cannot match a different recording by a quarantined ID");
}

static void testSampleFolder(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[store stringByAppendingPathComponent:@"chosen-samples"] isDirectory:YES];
    NSURL *sub = [root URLByAppendingPathComponent:@"person-Lyric" isDirectory:YES];
    [fm createDirectoryAtURL:sub withIntermediateDirectories:YES attributes:nil error:nil];
    [@"[00:01]私有句" writeToURL:[root URLByAppendingPathComponent:@"artist.lrc"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSData *binary = [NSData dataWithBytes:"\0\1\2" length:3];
    [binary writeToURL:[sub URLByAppendingPathComponent:@"12345.dat"] atomically:YES];
    [binary writeToURL:[root URLByAppendingPathComponent:@"unrelated.dat"] atomically:YES];
    [fm createSymbolicLinkAtURL:[root URLByAppendingPathComponent:@"linked.lrc"] withDestinationURL:[sub URLByAppendingPathComponent:@"12345.dat"] error:nil];
    NSString *report = [IKMusicCenter sampleReportAtURL:root];
    check([report containsString:@"matched=2"] && [report containsString:@"<sample>/*.lrc bytes="] &&
          [report containsString:@"<sample>/<lyric-dir>/*.dat bytes=3 header=binary"], "report relevant shapes in a selected export folder");
    check(![report containsString:root.path] && ![report containsString:@"12345"] && ![report containsString:@"person"] &&
          ![report containsString:@"artist"] && ![report containsString:@"私有句"], "folder report redacts song names, directory names and content");
    for (int i=0; i<35; i++)
        [binary writeToURL:[root URLByAppendingPathComponent:[NSString stringWithFormat:@"sample-%d.yrc",i]] atomically:YES];
    report = [IKMusicCenter sampleReportAtURL:root];
    check([report containsString:@"matched=32"] && [report containsString:@"limited=1"], "limit reports from large folders");
    check(![IKMusicCenter sampleReportAtURL:[root URLByAppendingPathComponent:@"missing"]], "missing folder is distinct from no matches");
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
    NSString *emptyExport = [IKMusicCenter playbackDiagnosticReport];
    check([emptyExport containsString:@"未读到启动记录"] && [emptyExport containsString:@"悬浮窗尚无可导出"],
          "empty first launch can export the absence of each source");
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
    metadata = @{@"Title":@"播放标题",@"Artist":@"演唱者",@"Duration":@100,@"QueueIndex":@8,
                 @"UniqueIdentifier":@400,@"ElapsedTime":@18,@"ArtworkData":[@"cover" dataUsingEncoding:NSUTF8StringEncoding]};
    [m refresh];
    session = m.recording[@"playSession"]; cover = m.artwork;
    metadata = @{@"Title":@"车载标题",@"Artist":@"第一句",@"Duration":@100,@"QueueIndex":@8,
                 @"UniqueIdentifier":@401,@"ElapsedTime":@21};
    [m refresh];
    check([m.recording[@"playSession"] isEqual:session] && m.artwork == cover && [m.reportedLyric isEqual:@"第一句"],
          "changing persistent ID during continuous car playback preserves track, cover and lyric");
    check([m.recording[@"unstablePersistentID"] isEqual:@YES] && ![IKMusicCenter importLyricsAtURL:file target:settingsTarget()],
          "bind the canonical recording after its ID becomes unstable");
    metadata = @{@"Title":@"播放标题",@"Artist":@"第二句",@"Duration":@100,@"QueueIndex":@8,@"UniqueIdentifier":@402};
    [m refresh];
    check([session isEqual:m.recording[@"playSession"]] && [settingsTarget()[@"mode"] isEqual:@"已绑定本地时间轴"] && m.currentElapsed>=21,
          "sparse next lyric keeps binding and clock despite another new ID");
    check([messages containsObject:@"lyric field=2"], "log selected numeric car field");
    metadata = @{@"Title":@"播放标题",@"Artist":@"演唱者乙",@"Duration":@121,@"QueueIndex":@9,@"ElapsedTime":@0};
    [m refresh]; session = m.recording[@"playSession"];
    metadata = @{@"Title":@"新歌名",@"Artist":@"新歌第一句",@"Duration":@121,@"QueueIndex":@9,@"ElapsedTime":@2};
    [m refresh];
    check([m.recording[@"title"] isEqual:@"新歌名"] && [m.reportedLyric isEqual:@"新歌第一句"] &&
          [session isEqual:m.recording[@"playSession"]], "correct inherited stale title, select artist on simultaneous first update");
    metadata = @{@"Title":@"电台节目一",@"Artist":@"电台",@"Duration":@0,@"QueueIndex":@12}; [m refresh];
    metadata = @{@"Title":@"电台节目二",@"Artist":@"电台",@"Duration":@0,@"QueueIndex":@12}; [m refresh];
    check([m.recording[@"title"] isEqual:@"电台节目二"] && !m.reportedLyric, "zero-duration program changes display as titles");
    metadata = @{@"Title":@"播报一",@"Artist":@"电台",@"UniqueIdentifier":@912,@"QueueIndex":@13}; [m refresh];
    metadata = @{@"Title":@"播报二",@"Artist":@"电台",@"UniqueIdentifier":@912,@"QueueIndex":@13}; [m refresh];
    check([m.recording[@"title"] isEqual:@"播报二"] && [settingsTarget()[@"mode"] isEqual:@"电台 / 直播节目"],
          "missing duration and a reused station ID cannot bind a program to an old timeline");
    metadata = @{@"Title":@"播报二",@"Artist":@"电台",@"Duration":@130,@"UniqueIdentifier":@912,@"QueueIndex":@13}; [m refresh];
    check(![m.recording[@"live"] boolValue] && m.duration == 130, "a delayed positive duration restores timed playback");
    metadata = @{@"Title":@"播放标题",@"Artist":@"演唱者",@"Duration":@100,@"QueueIndex":@14,@"UniqueIdentifier":@800,@"ElapsedTime":@10};
    [m refresh];
    metadata = @{@"Title":@"播放标题",@"Artist":@"重播第一句",@"Duration":@100,@"QueueIndex":@14,@"UniqueIdentifier":@801,@"ElapsedTime":@11};
    [m refresh];
    check(m.lyricsBridgeActive && [settingsTarget()[@"mode"] isEqual:@"已绑定本地时间轴"], "replay with different unstable ID finds metadata binding");
    NSString *diagnosticDir = IKPlayerLyricsPath(bundle).stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:diagnosticDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *launchFile = [diagnosticDir stringByAppendingPathComponent:IKPlaybackLaunchName];
    [@{@"bundleID":bundle, @"phase":@"loaded", @"version":@"15.2.3", @"wall":@1000} writeToFile:launchFile atomically:YES];
    NSString *launchOnly = [IKMusicCenter playbackDiagnosticReport];
    check([launchOnly containsString:@"等待播放器前台"] && [launchOnly containsString:@"播放器版本=15.2.3"] &&
          [launchOnly containsString:@"未读到可用的播放器采样"], "early exit report identifies version before first sample");
    NSDictionary *diagnostic = @{@"bundleID":bundle,@"schema":@1,@"fields":@{@"title":@"text"},@"customFields":@{@"vendorLyrics":@"text"},
        @"unknown":@1,@"jumpEvents":@1,@"accessEvents":@2,@"asset":@"remote",@"wall":@1000,@"uptime":@10,
        @"result":@{@"source":@"publishedField",@"key":@"vendorLyrics",@"lines":@3}};
    IKRememberDiagnostic([NSURL fileURLWithPath:diagnosticDir],diagnostic);
    [m clearPlayerScope];
    NSString *logPath = [store stringByAppendingPathComponent:@"island.log"];
    NSString *log = @"11-27 21:22:36 recording app=com.tencent.QQMusic externalID=0 persistentID=0 queueIndex=0\n11-27 21:22:44 lyric field=2\n11-27 21:24:37 interaction longPress state=compact\n11-27 21:24:38 lyric field=1 private-text\nprivate-text";
    [log writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *report = [IKMusicCenter playbackDiagnosticReport];
    check([report containsString:@"queueIndex=0"] && [report containsString:@"lyric field=2"] &&
          [report containsString:@"longPress state=compact"] && ![report containsString:@"private-text"], "export recovers only whitelisted historical HUD events");
    check([report containsString:@"1970-"] && [report containsString:@"vendorLyrics/text"] &&
          [report containsString:@"timeline=publishedField key=vendorLyrics lines=3"], "settings exports old host evidence with no active player");
    check([report containsString:@"selected/*.lrc bytes="] && ![report containsString:@"fixture.lrc"] && ![report containsString:@"当前"],
          "settings exports selected file shape without real file name or lyrics");
    metadata = @{}; [m refresh];
    check(!m.hasTrack && !m.reportedLyric && !m.recording, "empty playback clears song");
    testPublishedHandoff(m,@(argv[1]),@"com.tencent.QQMusic",@"qq");
    testPublishedHandoff(m,@(argv[1]),@"com.netease.cloudmusic",@"netease");
    testSampleFolder();
    IKLocalAvatar *avatars = [[IKLocalAvatar alloc] initWithDirectory:[NSURL fileURLWithPath:[store stringByAppendingPathComponent:@"avatars"]]];
    NSURL *picture = [NSURL fileURLWithPath:@"Resources/icon.png"];
    check(![avatars setImage:picture forTitle:@" 测试会话 "], "save chosen image under normalized notification title");
    NSURL *saved = [avatars imageForTitle:@"测试会话"];
    check(saved && ![saved.path containsString:@"测试会话"] && ![avatars imageForTitle:@"另一个会话"], "title digest isolates two conversations");
    CGImageSourceRef icon = CGImageSourceCreateWithURL((__bridge CFURLRef)saved,NULL);
    NSDictionary *dimensions = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(icon,0,NULL));
    CFRelease(icon);
    check([dimensions[(__bridge id)kCGImagePropertyPixelWidth] intValue] == 160, "stored picture is a downsampled thumbnail");
    check([avatars setImage:file forTitle:@"测试会话"] && [avatars imageForTitle:@"测试会话"], "invalid replacement preserves selected photo");
    check([avatars setImage:picture forTitle:@"微信"] != nil, "generic hidden notification title cannot receive a shared photo");
    check(![avatars setImage:nil forTitle:@"测试会话"] && ![avatars imageForTitle:@"测试会话"], "removing binding restores automatic fallback");
    NSData *pictureData = [NSData dataWithContentsOfURL:picture];
    check(pictureData && ![avatars setImageData:pictureData forTitle:@"相册会话"] && [avatars imageForTitle:@"相册会话"],
          "photo library data is stored as a bound avatar");
    check([avatars setImageData:[@"not an image" dataUsingEncoding:NSUTF8StringEncoding] forTitle:@"相册会话"] != nil &&
          [avatars imageForTitle:@"相册会话"], "undecodable photo data keeps the previous avatar");
    check([avatars setImageData:[NSData data] forTitle:@"相册会话"] != nil, "empty photo data is rejected");
    NSString *lockedRoot = [store stringByAppendingPathComponent:@"locked"];
    [NSFileManager.defaultManager createDirectoryAtPath:lockedRoot withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(lockedRoot.fileSystemRepresentation, 0555);
    IKLocalAvatar *locked = [[IKLocalAvatar alloc] initWithDirectory:[NSURL fileURLWithPath:[lockedRoot stringByAppendingPathComponent:@"WeChatAvatars"]]];
    NSString *lockedMessage = [locked setImageData:pictureData forTitle:@"相册会话"];
    check([lockedMessage containsString:@"无法创建目录"] && [lockedMessage containsString:@"WeChatAvatars"],
          "an unwritable data directory names the failing step and path");
    chmod(lockedRoot.fileSystemRepresentation, 0755);
    if (![NSFileManager.defaultManager removeItemAtPath:store error:nil]) return 2;
    printf("HUD and settings: %d checks passed\n",count);
    return 0;
} }
