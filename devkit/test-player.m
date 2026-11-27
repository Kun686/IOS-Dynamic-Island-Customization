#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import "IKLyricsTimeline.h"
#import "IKCoverLayout.h"
#import "IKAvatarProxy.h"
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
    printf("%s: %d checks passed\n", [bid UTF8String], checks);
    return 0;
} }
