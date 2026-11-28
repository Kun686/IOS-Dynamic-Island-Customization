// 悬浮窗接入联网时间轴：用真的 IKMusicCenter.m，只替换平台回调、容器定位、日志和网络层（按 URL 取夹具）。
//   用法：test-net-lyrics-center <夹具目录> <输出目录>
#import "IKPrefs.h"
#import "MediaRemote.h"
#import "IKMusicCenter.h"
#import "IKNetLyrics.h"
#include <sys/stat.h>

static NSString *store, *bundle, *prefsFile, *fixtures;
static NSDictionary *metadata;
static BOOL playing = YES, netEnabled = YES, holdReplies;
static NSMutableArray<NSString *> *messages;
static NSMutableArray<NSURLRequest *> *requests;
static NSMutableArray *held;

@implementation UIImage
+ (instancetype)imageWithData:(NSData *)data { return data.length ? [self new] : nil; }
@end
@implementation IKPrefs
+ (instancetype)shared { static IKPrefs *prefs; if (!prefs) prefs = [IKPrefs new]; return prefs; }
- (BOOL)netLyrics { return netEnabled; }
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

#define NSClassFromString(name) FixtureApp.class
#undef IKDataDir
#define IKDataDir store
#undef IKPrefsPath
#define IKPrefsPath prefsFile
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
void MRMediaRemoteGetNowPlayingApplicationDisplayID(dispatch_queue_t q, void (^reply)(NSString *)) { reply(bundle); }

static int count;
static void check(BOOL ok, const char *message) {
    if (!ok) {
        fprintf(stderr, "FAIL %s\n", message);
        for (NSString *m in messages) fprintf(stderr, "  log: %s\n", m.UTF8String);
        exit(1);
    }
    count++;
}

static void pump(double seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static NSData *fixture(NSString *name) {
    return [NSData dataWithContentsOfFile:[fixtures stringByAppendingPathComponent:name]];
}
static NSData *json(NSDictionary *object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }
static NSString *param(NSURL *url, NSString *name) {
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)
        if ([item.name isEqual:name]) return item.value;
    return nil;
}

static NSData *route(NSURL *url) {
    if ([url.path hasSuffix:@"client_search_cp"]) {
        if ([param(url, @"w") hasPrefix:@"晴天"]) return fixture(@"qq-search-qingtian.json");
        return json(@{@"code":@0, @"data":@{@"song":@{@"list":@[]}}});
    }
    if ([url.path hasSuffix:@"fcg_query_lyric_new.fcg"]) return fixture(@"qq-lyric-qingtian.json");
    if ([url.path isEqual:@"/api/search/get/web"]) {
        if ([param(url, @"s") hasPrefix:@"晴天"]) return fixture(@"netease-search-qingtian.json");
        if ([param(url, @"s") hasPrefix:@"十年"]) return fixture(@"netease-search-shinian.json");
        return json(@{@"result":@{@"songCount":@0}, @"code":@200});
    }
    if ([url.path isEqual:@"/api/song/lyric"]) {
        return [param(url, @"id") isEqual:@"66842"] ? fixture(@"netease-lyric-shinian.json") : json(@{@"nolyric":@YES, @"code":@200});
    }
    return nil;
}

// 依次把挂起的回包送回去（每送一个可能又发出下一个请求）
static void flush(void) {
    while (held.count) {
        NSArray *next = held.firstObject;
        [held removeObjectAtIndex:0];
        IKNetReply reply = next[1];
        NSData *data = route([next[0] URL]);
        reply(data, data ? 200 : 0, nil);
    }
}

static NSDictionary *settingsTarget(void) {
    __block NSDictionary *result;
    [IKMusicCenter requestImportTarget:^(NSDictionary *target) { result = target; }];
    return result;
}

static NSUInteger netFiles(void) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtPath:IKNetDirectory() error:nil].count;
}

static NSString *netFile(NSString *bid, NSString *title, NSString *artist, double duration) {
    return [IKNetDirectory() stringByAppendingPathComponent:IKRecordingFile(bid, IKTrackIdentity(nil, nil, title, artist, duration))];
}

static BOOL logged(NSString *line) { return [messages containsObject:line]; }

static void play(NSDictionary *info) { metadata = info; [IKMusicCenter.shared refresh]; }

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 3) return 2;
    fixtures = @(argv[1]);
    store = [@(argv[2]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    prefsFile = [store stringByAppendingPathComponent:@"prefs.plist"];
    messages = [NSMutableArray array];
    requests = [NSMutableArray array];
    held = [NSMutableArray array];
    IKNetSettleSeconds = 0.3;
    IKNetLyricsClient.shared.transport = ^(NSURLRequest *request, IKNetReply reply) {
        [requests addObject:request];
        if (holdReplies) { [held addObject:@[request, [reply copy]]]; return; }
        NSData *data = route(request.URL);
        reply(data, data ? 200 : 0, nil);
    };
    IKMusicCenter *m = IKMusicCenter.shared;
    bundle = @"com.tencent.QQMusic";

    // 1. 稳定后查询，命中后按位置换句，缓存写成与手动导入同结构的文件
    play(@{@"Title":@"晴天", @"Artist":@"周杰伦", @"Duration":@269.4, @"ElapsedTime":@30, @"QueueIndex":@1});
    check(!requests.count && !m.lyricsBridgeActive, "no request until the baseline title has settled");
    pump(0.2);
    check(!requests.count, "still waiting inside the settle window");
    pump(0.5);
    check(requests.count == 2 && [param(requests[0].URL, @"w") isEqual:@"晴天 周杰伦"], "QQ app queries QQ with title and artist");
    check(m.lyricsBridgeActive && [m.bridgeLyric isEqual:@"故事的小黄花"] && [m.bridgeNextLyric isEqual:@"从出生那年就飘着"] &&
          [m.bridgeTitle isEqual:@"晴天"], "timeline line follows the playback position");
    check(logged(@"net lyrics app=com.tencent.QQMusic provider=qq result=hit lines=24 dt=0.4"), "hit log without title or lyrics");
    NSString *file = netFile(bundle, @"晴天", @"周杰伦", 269.4);
    NSDictionary *cached = [NSDictionary dictionaryWithContentsOfFile:file];
    check([cached[@"source"] isEqual:@"net"] && [cached[@"provider"] isEqual:@"qq"] && [cached[@"fetchedAt"] doubleValue] > 1e9 &&
          [cached[@"lines"] count] == 24 && [cached[@"bundleID"] isEqual:bundle] && [cached[@"title"] isEqual:@"晴天"] &&
          IKSameRecording(m.recording, cached) && [cached[@"providerSongID"] isEqual:@"0039MnYb0qxYhV"], "cache file shape");
    struct stat st;
    check(stat(IKNetDirectory().fileSystemRepresentation, &st) == 0 && (st.st_mode & 0777) == 0755, "NetTimelines directory is 0755");
    check([settingsTarget()[@"mode"] isEqual:@"联网时间轴（QQ 音乐/网易云）"], "settings shows the net timeline mode");

    // 2. 车载歌词变化不再联网；同一首再放一遍直接用缓存
    play(@{@"Title":@"晴天", @"Artist":@"从出生那年就飘着", @"Duration":@269.4, @"ElapsedTime":@33, @"QueueIndex":@1});
    pump(0.5);
    check(requests.count == 2 && m.lyricsBridgeActive && [m.bridgeLyric isEqual:@"从出生那年就飘着"], "car lyric updates do not re-query");
    NSString *session = m.recording[@"playSession"];
    play(@{@"Title":@"晴天", @"Artist":@"周杰伦", @"Duration":@269.4, @"ElapsedTime":@0.5, @"QueueIndex":@2});
    check(![session isEqual:m.recording[@"playSession"]] && m.lyricsBridgeActive, "replay uses the cache immediately");
    pump(0.5);
    check(requests.count == 2 && logged(@"net lyrics app=com.tencent.QQMusic provider=qq result=cached lines=24 dt=0.4"), "cache hit, no network");

    // 3. 匹配不到：保持车载单句
    play(@{@"Title":@"查无此歌", @"Artist":@"某人", @"Duration":@200, @"ElapsedTime":@1, @"QueueIndex":@3});
    pump(0.6);
    check(logged(@"net lyrics app=com.tencent.QQMusic provider=qq result=miss lines=0 dt=-") &&
          logged(@"net lyrics app=com.tencent.QQMusic provider=netease result=miss lines=0 dt=-"), "miss logged for both providers");
    play(@{@"Title":@"查无此歌", @"Artist":@"第一句", @"Duration":@200, @"ElapsedTime":@3, @"QueueIndex":@3});
    pump(0.3);
    check(!m.lyricsBridgeActive && [m.reportedLyric isEqual:@"第一句"], "car single line keeps showing after a miss");
    NSUInteger before = requests.count;
    play(@{@"Title":@"查无此歌", @"Artist":@"第二句", @"Duration":@200, @"ElapsedTime":@5, @"QueueIndex":@3});
    pump(0.3);
    check(requests.count == before, "no repeated query for the same song and query");

    // 4. 换歌时丢弃过期回调
    holdReplies = YES;
    NSUInteger files = netFiles();
    play(@{@"Title":@"十年", @"Artist":@"陈奕迅", @"Duration":@205.4, @"ElapsedTime":@10, @"QueueIndex":@6});
    pump(0.5);
    check(held.count == 1, "lookup for the first song is in flight");
    play(@{@"Title":@"另一首歌", @"Artist":@"别人", @"Duration":@190, @"ElapsedTime":@0, @"QueueIndex":@7});
    flush();
    pump(0.5);
    flush();
    pump(0.2);
    check(netFiles() == files && ![NSFileManager.defaultManager fileExistsAtPath:netFile(bundle, @"十年", @"陈奕迅", 205.4)] &&
          !m.lyricsBridgeActive && !logged(@"net lyrics app=com.tencent.QQMusic provider=netease result=hit lines=14 dt=0.0"),
          "a late result for the previous song is discarded");

    // 5. 换播放器时丢弃过期回调；网易云先查网易云
    play(@{@"Title":@"十年", @"Artist":@"陈奕迅", @"Duration":@205.4, @"ElapsedTime":@16, @"QueueIndex":@8});
    pump(0.5);
    check(held.count == 1, "QQ-scope lookup in flight");
    bundle = @"com.netease.cloudmusic";
    [m applicationChanged];
    flush();   // 旧播放器那次查询的剩余请求在这里跑完
    NSUInteger mark = requests.count;
    pump(0.5);
    check(![NSFileManager.defaultManager fileExistsAtPath:netFile(@"com.tencent.QQMusic", @"十年", @"陈奕迅", 205.4)],
          "result from the previous player is discarded");
    check(requests.count == mark + 1 && [requests[mark].URL.host isEqual:@"music.163.com"], "NetEase scope asks NetEase first");
    flush();
    pump(0.3);
    check(m.lyricsBridgeActive && [m.bridgeLyric isEqual:@"如果那两个字没有颤抖"] &&
          [NSFileManager.defaultManager fileExistsAtPath:netFile(bundle, @"十年", @"陈奕迅", 205.4)] &&
          logged(@"net lyrics app=com.netease.cloudmusic provider=netease result=hit lines=14 dt=0.0"), "NetEase hit after the switch");
    holdReplies = NO;

    // 6. 歌名纠正：查询中途歌名变了，旧结果作废、按新歌名再查
    holdReplies = YES;
    play(@{@"Title":@"十年", @"Artist":@"歌手乙", @"Duration":@300, @"ElapsedTime":@0, @"QueueIndex":@9});
    pump(0.5);
    check(held.count == 1 && [param([held[0][0] URL], @"s") isEqual:@"十年 歌手乙"], "lookup started with the inherited title");
    play(@{@"Title":@"新歌名", @"Artist":@"歌手乙", @"Duration":@300, @"ElapsedTime":@1, @"QueueIndex":@9});
    check([m.recording[@"title"] isEqual:@"新歌名"] && [m.recording[@"correctedTitle"] isEqual:@YES], "tracker corrected the title");
    mark = requests.count;
    flush();
    pump(0.3);
    BOOL requeried = NO;
    for (NSUInteger i = mark; i < requests.count; i++) requeried |= [param(requests[i].URL, @"s") isEqual:@"新歌名 歌手乙"];
    check(requeried && ![NSFileManager.defaultManager fileExistsAtPath:netFile(bundle, @"十年", @"歌手乙", 300)],
          "stale title is dropped and the corrected title is queried");
    flush();
    holdReplies = NO;

    // 7. 开关关掉：不联网，也不用已缓存的联网时间轴
    play(@{@"Title":@"十年", @"Artist":@"陈奕迅", @"Duration":@205.4, @"ElapsedTime":@16, @"QueueIndex":@10});
    check(m.lyricsBridgeActive, "cached NetEase timeline is used");
    netEnabled = NO;
    check([m refreshLyricsBridge] && !m.lyricsBridgeActive, "turning the switch off drops the net timeline");
    check([settingsTarget()[@"mode"] isEqual:@"联网时间轴（QQ 音乐/网易云）"], "settings mode while the file still says on");
    [@{@"netLyrics":@NO} writeToFile:prefsFile atomically:YES];
    NSDictionary *target = settingsTarget();
    check(target && ![target[@"mode"] isEqual:@"联网时间轴（QQ 音乐/网易云）"], "settings mode follows the switch on disk");
    [NSFileManager.defaultManager removeItemAtPath:prefsFile error:nil];
    mark = requests.count;
    play(@{@"Title":@"关着开关的歌", @"Artist":@"歌手", @"Duration":@180, @"ElapsedTime":@0, @"QueueIndex":@11});
    pump(0.6);
    check(requests.count == mark, "no network while the switch is off");
    netEnabled = YES;
    play(@{@"Title":@"十年", @"Artist":@"陈奕迅", @"Duration":@205.4, @"ElapsedTime":@16, @"QueueIndex":@12});
    check(m.lyricsBridgeActive && [m.bridgeSource isEqual:@"net"], "switch back on restores the cache");

    // 8. 手动导入优先于联网缓存
    NSURL *lrc = [NSURL fileURLWithPath:[store stringByAppendingPathComponent:@"pick.lrc"]];
    [@"[00:00]导入首句\n[00:15]导入当前\n[00:40]导入下句" writeToURL:lrc atomically:YES encoding:NSUTF8StringEncoding error:nil];
    check(![IKMusicCenter importLyricsAtURL:lrc target:settingsTarget()], "manual import");
    [m refresh];
    check([m.bridgeLyric isEqual:@"导入当前"] && [m.bridgeSource isEqual:@"import"] &&
          [settingsTarget()[@"mode"] isEqual:@"已绑定本地时间轴"], "import beats the net cache");
    check(![IKMusicCenter removeImport:settingsTarget()], "remove import");
    [m refresh];
    check([m.bridgeSource isEqual:@"net"] && [m.bridgeLyric isEqual:@"如果那两个字没有颤抖"], "net cache returns after removing the import");

    // 9. 电台、零时长：不联网
    mark = requests.count;
    play(@{@"Title":@"电台节目", @"Artist":@"电台", @"Duration":@0, @"QueueIndex":@13});
    pump(0.6);
    check(requests.count == mark, "live programs are never queried");

    // 10. 导出诊断只带白名单里的联网记录
    NSString *log = @"11-28 20:00:00 net lyrics app=com.tencent.QQMusic provider=qq result=hit lines=24 dt=0.4\n"
                    @"11-28 20:00:01 net lyrics app=com.netease.cloudmusic provider=netease result=cached lines=14 dt=-\n"
                    @"11-28 20:00:02 net lyrics app=com.tencent.QQMusic provider=qq result=hit lines=24 dt=0.4 title=晴天\n"
                    @"11-28 20:00:03 net lyrics app=com.tencent.QQMusic provider=kugou result=hit lines=1 dt=0.0\n";
    [log writeToFile:[store stringByAppendingPathComponent:@"island.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *report = [IKMusicCenter playbackDiagnosticReport];
    check([report containsString:@"20:00:00 net lyrics app=com.tencent.QQMusic provider=qq result=hit lines=24 dt=0.4"] &&
          [report containsString:@"result=cached lines=14 dt=-"] && ![report containsString:@"晴天"] && ![report containsString:@"kugou"],
          "diagnostic export keeps only the fixed net lyrics format");
    NSUInteger netLines = 0;
    for (NSString *line in messages) {
        if (![line hasPrefix:@"net lyrics"]) continue;
        netLines++;
        check(![line containsString:@"晴天"] && ![line containsString:@"周杰伦"] && ![line containsString:@"十年"] &&
              ![line containsString:@"故事"] && ![line containsString:@"新歌名"], "HUD log never records titles, artists or lyrics");
    }
    check(netLines >= 6, "net lyrics events were logged");
    [NSFileManager.defaultManager removeItemAtPath:store error:nil];
    printf("HUD net timeline: %d checks passed\n", count);
    return 0;
} }
