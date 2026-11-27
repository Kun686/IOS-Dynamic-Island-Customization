#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import "IKLyricsTimeline.h"
#import "IKCoverLayout.h"
#import "IKAvatarProxy.h"
#import "IKPlaybackDiagnostic.h"
#import "IKPlaybackDiagnostics.h"
#import <math.h>

@interface IKPlayerLyrics : NSObject
@property(nonatomic, strong) NSURL *file;
@property(nonatomic, strong) AVPlayerItemMetadataOutput *output;
@property(nonatomic, copy) NSDictionary *observedTrack;
@property(nonatomic, strong) NSMutableDictionary *streamCues;
- (void)metadataOutput:(AVPlayerItemMetadataOutput *)output didOutputTimedMetadataGroups:(NSArray *)groups fromPlayerItemTrack:(AVPlayerItemTrack *)track;
- (void)publish;
- (BOOL)writeInfo:(NSDictionary *)info bundle:(NSString *)bundle;
@end

@interface StreamProbe : IKPlayerLyrics
@property(nonatomic) int events;
@end
@implementation StreamProbe
- (void)publish { self.events++; }
@end

@interface TestProxy : NSObject
@end
@implementation TestProxy
- (id)read:(NSError **)error { return @"decoded"; }
- (id)fail:(NSError **)error { *error = [NSError errorWithDomain:@"fixture" code:7 userInfo:nil]; return nil; }
- (id)wrong:(NSInteger)value { abort(); }
@end

static int checks;
static void check(BOOL ok, const char *name) {
    if (!ok) { fprintf(stderr, "FAIL %s\n", name); exit(1); }
    checks++;
}

static NSString *lineAt(NSArray<NSDictionary *> *rows, double pos) {
    NSUInteger i = IKCurrentLyricIndex(rows, pos);
    return i == NSNotFound ? nil : rows[i][@"text"];
}

static void testRecordingUpdates(IKPlayerLyrics *player, NSURL *folder, NSString *bid) {
    NSMutableDictionary *info = [@{MPMediaItemPropertyTitle:@"歌一", MPMediaItemPropertyArtist:@"歌手",
        MPMediaItemPropertyPlaybackDuration:@180, MPNowPlayingInfoPropertyElapsedPlaybackTime:@30,
        MPNowPlayingInfoPropertyPlaybackQueueIndex:@4} mutableCopy];
    NSURL *rec = [player.file.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"recording.plist"];
    check([player writeInfo:info bundle:bid], "stream without asset URL starts");
    NSDictionary *base = [NSDictionary dictionaryWithContentsOfURL:rec];
    NSString *name = IKRecordingFile(bid,base);
    check(name.length > 0 && ![base[@"externalID"] length] && ![base[@"persistentID"] length], "metadata binding has no IDs");
    info[MPMediaItemPropertyTitle] = @"第一句";
    [player writeInfo:info bundle:bid];
    info[MPMediaItemPropertyTitle] = @"第二句";
    [player writeInfo:info bundle:bid];
    info[MPMediaItemPropertyArtist] = @"第三句";
    [info removeObjectForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [player writeInfo:info bundle:bid];
    NSDictionary *live = [NSDictionary dictionaryWithContentsOfURL:rec];
    check([live[@"carLyric"] isEqual:@"第三句"] && [live[@"playSession"] isEqual:base[@"playSession"]], "latest artist wins after two title changes");
    check([name isEqual:IKRecordingFile(bid,live)], "line changes preserve file name");
    NSDictionary *raw = IKTrackIdentity(nil,nil,@"第二句",@"第三句",180);
    IKRecordingTracker *hud = [IKRecordingTracker new];
    [hud observe:raw album:nil queueIndex:@4 position:@36 bundle:bid];
    double now = NSProcessInfo.processInfo.systemUptime, wall = NSDate.date.timeIntervalSince1970;
    NSDictionary *paired = IKLiveRecording(live,bid,raw,@4,nil,now,wall);
    check([paired[@"title"] isEqual:@"歌一"], "observer starts mid-line and adopts original title");
    check([IKFreshPlayerLyric(live,hud,raw) isEqual:@"第三句"], "host single cue works without AssetURL or timeline");
    check(!IKLiveRecording(live,bid,raw,@5,nil,now,wall), "different queue slot rejected");
    check(!IKLiveRecording(live,@"other",raw,@4,nil,now,wall), "other player's handoff rejected");
    check(!IKLiveRecording(live,bid,raw,@4,nil,now+11,wall+11), "abandoned handoff expires");
    check(!IKLiveRecording(live,bid,raw,@4,nil,now,wall+30), "wall / uptime disagreement rejected");
    NSDictionary *nextRaw = IKTrackIdentity(nil,nil,@"第二句",@"第四句",180);
    check(!IKLiveRecording(live,bid,nextRaw,@4,nil,now,wall), "unpaired mismatching display fields rejected");
    [hud observe:nextRaw album:nil queueIndex:nil position:nil bundle:bid];
    check(!IKFreshPlayerLyric(live,hud,nextRaw), "old host heartbeat cannot rewind a newer system line");
    check(IKLiveRecording(live,bid,nextRaw,nil,paired[@"playSession"],now,wall) != nil, "paired observers tolerate staggered callbacks");
    info[MPMediaItemPropertyPersistentID] = @123;
    [player writeInfo:info bundle:bid];
    NSDictionary *enriched = [NSDictionary dictionaryWithContentsOfURL:rec];
    check([IKRecordingFilenames(bid,enriched) containsObject:name] && IKSameRecording(enriched,base), "late ID can still open previous binding");
    [player writeInfo:@{MPNowPlayingInfoPropertyElapsedPlaybackTime:@49} bundle:bid];
    live = [NSDictionary dictionaryWithContentsOfURL:rec];
    check([live[@"carLyric"] isEqual:@"第三句"] && [live[@"queueIndex"] isEqual:@4], "sparse playback sample preserves line and queue");
    info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = @5;
    [info removeObjectForKey:MPMediaItemPropertyPersistentID];
    info[MPMediaItemPropertyTitle] = @"歌二"; info[MPMediaItemPropertyArtist] = @"歌手";
    [player writeInfo:info bundle:bid];
    live = [NSDictionary dictionaryWithContentsOfURL:rec];
    check(![live[@"playSession"] isEqual:base[@"playSession"]] && ![name isEqual:IKRecordingFile(bid,live)], "equal duration next queue item drops old binding");
    hud = [IKRecordingTracker new];
    [hud observe:IKTrackIdentity(nil,nil,@"甲",@"同一歌手",180) album:nil queueIndex:nil position:@18 bundle:bid];
    check(![hud observe:hud.recording album:nil queueIndex:nil position:@1 bundle:bid], "seek alone preserves session");
    [hud observe:hud.recording album:nil queueIndex:nil position:@51 bundle:bid];
    check([hud observe:IKTrackIdentity(nil,nil,@"乙",@"同一歌手",180) album:nil queueIndex:nil position:@0 bundle:bid], "different song at playback restart without IDs or queue");
    check([hud observe:hud.recording album:nil queueIndex:nil position:@1 bundle:@"other"], "changing players starts a new session");
}

static void testPublishedTimeline(IKPlayerLyrics *player, NSString *bundle, NSURL *folder) {
    NSMutableDictionary *info = [@{MPMediaItemPropertyTitle:@"测试录音", MPMediaItemPropertyArtist:@"测试歌手",
        MPMediaItemPropertyPlaybackDuration:@98, MPNowPlayingInfoPropertyExternalContentIdentifier:@"fixture",
        @"player.syncedLyrics":@{@"timeUnit":@"ms", @"lines":@[
            @{@"start":@500, @"text":@"甲"}, @{@"start":@2500, @"text":@"乙"}]}} mutableCopy];
    check([player writeInfo:info bundle:bundle], "write custom published field");
    NSDictionary *packet = [NSDictionary dictionaryWithContentsOfURL:player.file];
    check([lineAt(packet[@"lines"],2.5) isEqual:@"乙"], "public custom field selects second cue without AssetURL");
    check([packet[@"source"] isEqual:@"publishedField"] && [packet[@"sourceKey"] isEqual:@"player.syncedLyrics"], "record actual published source");
    NSURL *handoff = [folder URLByAppendingPathComponent:@"custom-output.plist"];
    check([[NSData dataWithContentsOfURL:player.file] writeToURL:handoff atomically:YES], "save exact producer bytes for the HUD test");
    [info removeObjectForKey:@"player.syncedLyrics"];
    info[@"player.lrc"] = @"[00:01]新甲\n[00:03]新乙";
    check([player writeInfo:info bundle:bundle], "custom field changes mid-recording");
    check([lineAt([NSDictionary dictionaryWithContentsOfURL:player.file][@"lines"],3) isEqual:@"新乙"], "replace custom timeline from LRC");
    info[@"player.lrc"] = @"无时间单句";
    check([player writeInfo:info bundle:bundle] && ![[NSDictionary dictionaryWithContentsOfURL:player.file][@"lines"] count],
          "untimed custom value clears expired timeline");
    [info removeObjectForKey:@"player.lrc"];
    NSMutableDictionary *cue = [@{@"startMs":@1000,@"text":@"初次"} mutableCopy];
    info[@"vendor"] = @{@"timedLyrics":@[cue]};
    check([player writeInfo:info bundle:bundle], "nested published timing data becomes available");
    packet = [NSDictionary dictionaryWithContentsOfURL:player.file];
    check([packet[@"sourceKey"] isEqual:@"vendor.timedLyrics"] && [lineAt(packet[@"lines"],1) isEqual:@"初次"],
          "nested public field path and cue agree");
    cue[@"text"] = @"改正";
    check([player writeInfo:info bundle:bundle] &&
          [lineAt([NSDictionary dictionaryWithContentsOfURL:player.file][@"lines"],1) isEqual:@"改正"], "mutable nested cue invalidates snapshot");
    [info removeObjectForKey:@"vendor"];
    info[@"lyricEnvelope"] = @{@"timeUnit":@"ms", @"syncedLyrics":@[@{@"start":@2500,@"text":@"套层原文"}]};
    [player writeInfo:info bundle:bundle];
    packet = [NSDictionary dictionaryWithContentsOfURL:player.file];
    check([packet[@"sourceKey"] isEqual:@"lyricEnvelope.syncedLyrics"] && !lineAt(packet[@"lines"],2.499) &&
          [lineAt(packet[@"lines"],2.5) isEqual:@"套层原文"], "nested lyric-named container passes its time unit to published rows");
    [info removeObjectForKey:@"lyricEnvelope"];
    info[@"originalLyrics"] = @"[ {\"startMs\":1200,\"text\":\"原文\"} ]";
    info[@"aTranslatedLyrics"] = @"[00:01.2]翻译";
    check([player writeInfo:info bundle:bundle], "published JSON alternative");
    packet = [NSDictionary dictionaryWithContentsOfURL:player.file];
    check([lineAt(packet[@"lines"],1.2) isEqual:@"原文"] && [packet[@"sourceKey"] isEqual:@"originalLyrics"],
          "prefer original JSON over translated text");
    [info removeObjectForKey:@"aTranslatedLyrics"];
    [info removeObjectForKey:@"originalLyrics"];
    info[@"vendor.qrc"] = [@"[1200,500]字(1200,500)" dataUsingEncoding:NSUTF8StringEncoding];
    check([player writeInfo:info bundle:bundle] &&
          [lineAt([NSDictionary dictionaryWithContentsOfURL:player.file][@"lines"],1.2) isEqual:@"字"], "published timed bytes");
    info[@"vendor.qrc"] = [NSData data];
    info[@"comment"] = @"[00:01]unrelated field";
    [player writeInfo:info bundle:bundle];
    check(![[NSDictionary dictionaryWithContentsOfURL:player.file][@"lines"] count], "ignore unrelated timestamp-looking metadata");

}

static void testSignals(NSURL *parent, NSURL *asset, NSString *bid) {
    NSURL *directory = [parent URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSDictionary *info = @{MPMediaItemPropertyTitle:@"sensitive-song",MPMediaItemPropertyPersistentID:@98765432,
                           MPNowPlayingInfoPropertyAssetURL:asset,@"sensitive key/user@example":@"sensitive-value", @"VendorLRC":@[]};
    NSDictionary *data = IKPlaybackSignals(info,14,2);
    NSDictionary *fields = data[@"fields"];
    check([fields[@"title"] isEqual:@"text"] && [fields[@"persistentID"] isEqual:@"number"], "public key shapes");
    check([data[@"unknown"] isEqual:@2] && [data[@"asset"] isEqual:@"file"] && [data[@IK_PLAYER_FORMAT] boolValue], "only neighboring file extensions and unknown count");
    IKWritePlaybackSignals(directory,bid,info,14,2,nil);
    NSDictionary *packet = [NSDictionary dictionaryWithContentsOfURL:[directory URLByAppendingPathComponent:IKPlaybackDiagnosticsName]];
    NSString *dump = [packet description];
    check(packet && ![dump containsString:@"sensitive"] && ![dump containsString:@"98765432"] && ![dump containsString:asset.path], "diagnostic file excludes content, IDs and paths");
    double now = NSProcessInfo.processInfo.systemUptime, wall = NSDate.date.timeIntervalSince1970;
    NSString *summary = IKDiagnosticSummary(packet,bid,now,wall);
    check([summary containsString:@"avAccess=14 avJump=2"] && [summary containsString:@"title/text"], "consumer prints actual observed counters");
    check(!IKDiagnosticSummary(packet,bid,now+91,wall+91) && !IKDiagnosticSummary(packet,@"wrong",now,wall), "old and foreign diagnostics rejected");
    NSDictionary *nestedSignals = IKPlaybackSignals(@{@"vendor":@{@"timedLyrics":@[],@"contact":@"sensitive"}},0,0);
    NSDictionary *children = nestedSignals[@"nestedFields"];
    check([children[@"vendor.timedLyrics"] isEqual:@"array"] && children.count==1, "nested lyric fields expose only names and types");
    NSDictionary *objectSignals = IKPlaybackSignals(@{@"vendor":@{@"timedLyrics":@[[TestProxy new]]},@"unrelated":[TestProxy new]},0,0);
    NSMutableDictionary *objectPacket = [packet mutableCopy];
    [objectPacket addEntriesFromDictionary:objectSignals];
    check([IKDiagnosticSummary(objectPacket,bid,now,wall) containsString:@"objects=[vendor.timedLyrics[]/TestProxy]"],
          "report the type actually published as a lyric row and exclude unrelated objects");
    check([summary containsString:@"VendorLRC/array"] && [summary containsString:@"omitted=1"] &&
          [summary containsString:@"<media>/*."] && [summary containsString:@"header=timed-text"], "diagnostic locates custom key and identifies adjacent text shape");
    NSMutableDictionary *many = [NSMutableDictionary dictionary];
    for (int i=0;i<65;i++) many[[NSString stringWithFormat:@"Field%d",i]] = @1;
    many[@"zKaraokeLyrics"] = @"sensitive";
    NSDictionary *extras = IKPlaybackSignals(many,0,0)[@"customFields"];
    check(extras.count==40 && [extras[@"zKaraokeLyrics"] isEqual:@"text"], "lyric-like keys survive report limit");
    NSMutableDictionary *archived = [packet mutableCopy];
    archived[@"wall"] = @1000;
    archived[@"uptime"] = @50;
    IKRememberDiagnostic(directory,archived);
    archived[@"accessEvents"] = @50;
    IKRememberDiagnostic(directory,archived);
    NSString *history = IKDiagnosticHistory(directory,bid);
    check([history containsString:@"avAccess=50"] && ![history containsString:@"sensitive"] && ![history containsString:asset.path],
          "durable report survives expiry and strips actual content");
    check([history componentsSeparatedByString:@"VendorLRC/array"].count==2, "deduplicate equivalent key shapes across heartbeats");
    check(!IKDiagnosticHistory(directory,@"other"), "do not export another player's packet");
    NSURL *binary = [directory URLByAppendingPathComponent:@"private-person.qrc"];
    const uint8_t bytes[] = {0,1,2,3,4,5};
    [[NSData dataWithBytes:bytes length:sizeof(bytes)] writeToURL:binary atomically:YES];
    NSString *fileSummary = IKFileShapeSummary(IKLyricFileShape(binary));
    check([fileSummary isEqual:@"*.qrc bytes=6 header=binary"], "binary header described without filenames or bytes");
    [[NSData data] writeToURL:binary atomically:YES];
    check([IKLyricFileShape(binary)[@"header"] isEqual:@"empty"], "explicit empty file shape");
    NSDictionary *remote = IKPlaybackSignals(@{MPNowPlayingInfoPropertyAssetURL:[NSURL URLWithString:@"https://example.invalid/private"]},0,0);
    check([remote[@"asset"] isEqual:@"remote"] && !remote[@"qrc"] && ![[remote description] containsString:@"private"], "remote URL shape only");
    check([IKPlaybackSignals(@{},0,0)[@"asset"] isEqual:@"absent"], "missing asset seen explicitly");
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 2) return 2;
    NSArray *lrc = IKParseTimedLyrics(@"[offset:+200]\n[00:01.20][00:05.200]原词\n[00:01.20]译词\n[00:03.20]\n[00:10.20]结尾", 15);
    check(lrc.count == 3, "deduplicate translation without discarding repeat");
    check(!lineAt(lrc, 0.999), "intro");
    check([lineAt(lrc, 1.0) isEqual:@"原词"], "offset and first line");
    check(!lineAt(lrc, 3.00), "empty LRC cue clears previous line");
    check([lineAt(lrc, 5.0) isEqual:@"原词"], "multi-tag repeat");
    check(!lineAt(lrc, 15), "end exclusive");

    NSArray<NSDictionary *> *overlap = IKNormalizeLyricLines(@[@{@"text":@"乙",@"startMs":@3500,@"durationMs":@1200},
                                               @{@"text":@"甲",@"start":@1,@"end":@6}], NO, 10);
    check([lineAt(overlap,3.499) isEqual:@"甲"], "before next cue");
    check([lineAt(overlap,3.5) isEqual:@"乙"], "overlap at exact boundary");
    check([overlap.firstObject[@"end"] doubleValue] == 3.5, "fill finishes at next start");
    check(!lineAt(overlap,4.71), "instrumental gap");
    check([lineAt(overlap,1) isEqual:@"甲"], "backward seek");
    check(!IKParseTimedLyrics(@"一行没有时间标签的歌词", 180).count, "untimed lyrics");
    check(!IKNormalizeLyricLines(@[@{@"text":@"错",@"start":@"nan"}], NO, 15).count, "invalid time");
    NSArray *xml = IKParseTimedLyrics(@"<QrcInfos><Lyric_1 LyricContent=\"[100,300]你(100,100)好(200,200)&#10;[400,600]世(400,300)界(700,300)\"/></QrcInfos>", 15);
    check([lineAt(xml,0.4) isEqual:@"世界"], "XML QRC");
    check(!lineAt(xml,0.05), "QRC intro");

    NSDictionary *a = IKTrackIdentity(@"first",nil,@"歌一",@"歌手",183);
    NSDictionary *b = IKTrackIdentity(@"second",nil,@"歌一",@"歌手",183);
    check(!IKSameRecording(a,b), "equal metadata different recording IDs");
    check(IKSameRecording(a,IKTrackIdentity(@"first",nil,@"蓝牙歌词",@"歌手",183)), "stable ID with dynamic title");
    check(![IKRecordingFile(@"A",a) isEqual:IKRecordingFile(@"B",a)], "player-scoped imports");
    check(!IKSameRecording(IKTrackIdentity(nil,nil,@"另一首",@"歌手",183),a), "same duration different song");
    check(IKRecordingFile(@"A",IKTrackIdentity(nil,nil,@"缺少信息",nil,0)) == nil, "ambiguous import rejected");

    NSMutableDictionary *native = [a mutableCopy];
    [native addEntriesFromDictionary:@{@"bundleID":@"player",@"position":@3,@"rate":@2,@"uptime":@10,@"wall":@100}];
    double exact = 0;
    check(IKPlayerPosition(native,@"player",a,YES,10.5,100.5,&exact,NULL) && exact == 4, "native playhead and rate");
    check(!IKPlayerPosition(native,@"player",a,NO,10.5,100.5,NULL,NULL), "system pause rejects moving anchor");
    check(!IKPlayerPosition(native,@"player",a,YES,19,109,NULL,NULL), "abandoned anchor expires");
    check(!IKPlayerPosition(native,@"player",a,YES,10.5,190,NULL,NULL), "old boot rejected");
    check(!IKPlayerPosition(native,@"player",b,YES,10.5,100.5,NULL,NULL), "clock from another track rejected");
    native[@"playSession"] = @"old";
    NSMutableDictionary *repeated = [a mutableCopy]; repeated[@"playSession"] = @"new";
    check(!IKPlayerPosition(native,@"player",repeated,YES,10.5,100.5,NULL,NULL), "same song repeated rejects previous session clock");
    native[@"rate"] = @0;
    check(IKPlayerPosition(native,@"player",a,YES,12,102,&exact,NULL) && exact==3, "buffering host freezes playhead");
    IKPlaybackClock *clock = [IKPlaybackClock new];
    NSDate *start = [NSDate dateWithTimeIntervalSince1970:100];
    [clock updatePosition:@4 stamp:start playing:YES rate:1 sameTrack:NO wall:start uptime:10];
    check([clock positionAt:12] == 6, "playing clock");
    NSDate *pause = [start dateByAddingTimeInterval:2];
    [clock updatePosition:@4 stamp:pause playing:NO rate:0 sameTrack:YES wall:pause uptime:12];
    check([clock positionAt:22] == 6, "repeated position on pause");
    NSDate *resume = [start dateByAddingTimeInterval:12];
    [clock updatePosition:@4 stamp:resume playing:YES rate:2 sameTrack:YES wall:resume uptime:22];
    check([clock positionAt:24] == 10, "resume and double speed");
    [clock updatePosition:@1 stamp:resume playing:YES rate:1 sameTrack:YES wall:resume uptime:24];
    check([clock positionAt:24] == 1, "seek");
    [clock updatePosition:@0 stamp:resume playing:YES rate:1 sameTrack:NO wall:resume uptime:25];
    check([clock positionAt:25] == 0, "new recording clock reset");

    NSString *bid = @IK_PLAYER_BUNDLE;
    NSURL *folder = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
    IKPlayerLyrics *player = [IKPlayerLyrics new];
    player.file = [folder URLByAppendingPathComponent:@"Library/IslandKit/lyrics.plist"];
    NSURL *audio = [folder URLByAppendingPathComponent:@"song.m4a"];
    NSString *text = [@IK_PLAYER_FORMAT isEqual:@"qrc"] ? @"[1000,3500]上(1000,1000)句(2000,2500)\n[3000,2000]下(3000,1200)句(4200,800)"
        : @"[1000,3500](1000,1000,0)上(2000,2500,0)句\n[3000,2000](3000,1200,0)下(4200,800,0)句";
    NSURL *sidecar = [[audio URLByDeletingPathExtension] URLByAppendingPathExtension:@IK_PLAYER_FORMAT];
    check([text writeToURL:sidecar atomically:YES encoding:NSUTF8StringEncoding error:nil], "write test fixture");
    NSMutableDictionary *info = [@{MPNowPlayingInfoPropertyExternalContentIdentifier:@"first", MPMediaItemPropertyTitle:@"歌一",
                                   MPMediaItemPropertyArtist:@"歌手", MPMediaItemPropertyPlaybackDuration:@183,
                                   MPNowPlayingInfoPropertyAssetURL:audio} mutableCopy];
    check([player writeInfo:info bundle:bid], "producer publishes local asset sidecar");
    NSDictionary *packet = [NSDictionary dictionaryWithContentsOfURL:player.file];
    check([packet[@"source"] isEqual:@"sidecar"] && [packet[@"bundleID"] isEqual:bid], "producer origin and player");
    check(IKSameRecording(packet,a), "consumer accepts matching producer");
    NSArray *decoded = IKNormalizeLyricLines(packet[@"lines"], NO, 183);
    check([lineAt(decoded,2.999) isEqual:@"上句"] && [lineAt(decoded,3.00) isEqual:@"下句"], "producer -> file -> consumer at overlap");
    check(![player writeInfo:info bundle:bid], "no duplicate write");
    [info removeObjectForKey:MPNowPlayingInfoPropertyAssetURL];
    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = @"second";
    check([player writeInfo:info bundle:bid], "new same-duration track");
    packet = [NSDictionary dictionaryWithContentsOfURL:player.file];
    check([packet[@"source"] isEqual:@"clock"] && [packet[@"lines"] count]==0 && !IKSameRecording(packet,a), "no stale timeline");
    info[MPMediaItemPropertyLyrics] = @"[00:03.5]发布的歌词";
    check([player writeInfo:info bundle:bid], "metadata becomes available mid-track");
    packet = [NSDictionary dictionaryWithContentsOfURL:player.file];
    check([lineAt(packet[@"lines"],3.5) isEqual:@"发布的歌词"], "direct metadata");
    check([player writeInfo:@{} bundle:bid] && [[[NSDictionary dictionaryWithContentsOfURL:player.file] objectForKey:@"active"] isEqual:@NO], "player cleared");
    NSURL *large = [folder URLByAppendingPathComponent:@"oversize.lrc"];
    [[NSMutableData dataWithLength:IKMaxLyricBytes+1] writeToURL:large atomically:YES];
    check(!IKReadLyricFile(large), "size bound");

    testPublishedTimeline(player,bid,folder);
    testRecordingUpdates(player,folder,bid);
    testSignals(folder,audio,bid);
    NSString *legacy = @"[00:01]歌词";
    NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    for (NSNumber *n in @[@(gb),@(NSUTF8StringEncoding),@(NSUnicodeStringEncoding),@(NSUTF16BigEndianStringEncoding),@(NSUTF16LittleEndianStringEncoding)]) {
        check([IKDecodeLyricText([legacy dataUsingEncoding:n.unsignedIntegerValue]) isEqual:legacy], "decode legacy lyrics without losing Chinese");
    }
    NSArray<NSDictionary *> *breaths = IKParseTimedLyrics(@"[1000,1000]甲\n[3000,1000]乙\n[6200,500]丙",10);
    check([lineAt(breaths,2.95) isEqual:@"甲"] && [breaths[0][@"end"] doubleValue]==2, "hold completed fill through a short breath");
    check([lineAt(breaths,3) isEqual:@"乙"] && !lineAt(breaths,4.01) && !lineAt(breaths,7), "long gap and tail clear");
    NSArray *clear = IKParseTimedLyrics(@"[00:01]甲\n[00:02]\n[00:02.5]乙",10);
    check(!lineAt(IKNormalizeLyricLines(clear,NO,10),2.3), "explicit short blank survives disk normalization");

    StreamProbe *probe = [StreamProbe new];
    probe.output = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:@[AVMetadataIdentifierID3MetadataSynchronizedLyric]];
    probe.streamCues = [NSMutableDictionary dictionary];
    probe.observedTrack = a;
    AVMutableMetadataItem *tag = [AVMutableMetadataItem metadataItem];
    tag.identifier = AVMetadataIdentifierID3MetadataSynchronizedLyric;
    tag.value = @"媒体时间戳";
    AVTimedMetadataGroup *group = [[AVTimedMetadataGroup alloc] initWithItems:@[tag]
        timeRange:CMTimeRangeMake(CMTimeMake(3500,1000),CMTimeMake(1200,1000))];
    [probe metadataOutput:nil didOutputTimedMetadataGroups:@[group] fromPlayerItemTrack:nil];
    check(!probe.events, "drop metadata from replaced output");
    [probe metadataOutput:probe.output didOutputTimedMetadataGroups:@[group] fromPlayerItemTrack:nil];
    NSArray *live = IKNormalizeLyricLines(probe.streamCues.allValues, NO, 183);
    check(!lineAt(live, 3.499) && [lineAt(live,3.5) isEqual:@"媒体时间戳"], "timed audio metadata uses presentation timestamp");
    check(!lineAt(live,4.71), "timed audio metadata duration");
    [probe metadataOutput:probe.output didOutputTimedMetadataGroups:@[group] fromPlayerItemTrack:nil];
    check(probe.events == 1, "duplicate timed audio group");
    IKCoverTextLayout small = IKCoverRows(CGSizeMake(198,55), 38, 76, YES);
    check(!small.fits, "screenshot 198x55 shell hides expanded content");
    check(IKCoverRows(CGSizeMake(358,94),38,76,YES).fits, "expanded music fits both rows");
    check(IKCoverRows(CGSizeMake(300,94),38,70,YES).fits, "notification fits both rows");
    check(IKCoverRows(CGSizeMake(358,78),38,76,NO).fits, "one-line lyric fits");
    TestProxy *proxy = [TestProxy new];
    NSError *error = nil;
    check([IKReadProxyImage(proxy,@selector(read:),&error) isEqual:@"decoded"], "resolved concrete image");
    check(!IKReadProxyImage(proxy,@selector(fail:),&error) && error.code==7, "resolver error distinct from timeout");
    check(!IKReadProxyImage(proxy,@selector(wrong:),&error), "reject incompatible resolver ABI");
    NSMutableDictionary *pending = [NSMutableDictionary dictionary];
    __block int applied = 0;
    check(IKAwaitAvatar(pending,@"first",^{ applied = 1; }) == IKAvatarStart, "one proxy starts");
    check(IKAwaitAvatar(pending,@"first",^{ applied = 2; }) == IKAvatarJoined && pending.count == 1, "one sender and URL share one worker");
    void (^reply)(void) = pending[@"first"]; reply();
    check(applied == 2, "coalesced proxy delivers to latest notification");
    check(IKAwaitAvatar(pending,@"second",^{}) == IKAvatarStart && IKAwaitAvatar(pending,@"third",^{}) == IKAvatarBusy, "two stalled calls bound all work");
    [pending removeObjectForKey:@"first"];
    check(IKAwaitAvatar(pending,@"third",^{}) == IKAvatarStart, "worker completion recovers capacity");
    printf("%s: %d checks passed\n", [bid UTF8String], checks);
    return 0;
} }
