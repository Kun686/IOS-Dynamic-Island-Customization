#import "IKMusicCenter.h"
#import "MediaRemote.h"
#import "IKPlaybackDiagnostic.h"
#import "IKPrefs.h"
#import "IKNetLyrics.h"
#import <objc/message.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *const IKMusicDidChangeNotification = @"IKMusicDidChangeNotification";

static double IKNumber(id value) {
    if (![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class]) return 0;
    double n = [value doubleValue];
    return isfinite(n) ? n : 0;
}

static NSDictionary *IKSystemTrack(NSDictionary *d) {
    return IKReportedTrack(d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoExternalContentIdentifier],
        d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoUniqueIdentifier],
        d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle], d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist],
        d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDuration],NO);
}

static BOOL IKSupportedPlayer(NSString *bid) {
    return [@[@"com.tencent.qqmusic", @"com.netease.cloudmusic"] containsObject:bid.lowercaseString ?: @""];
}

static NSString *IKPlayerLyricsPath(NSString *bundleID) {
    if (!IKSupportedPlayer(bundleID)) return nil;
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL makeProxy = NSSelectorFromString(@"applicationProxyForIdentifier:");
    SEL containerSelector = NSSelectorFromString(@"dataContainerURL");
    if (!proxyClass || ![proxyClass respondsToSelector:makeProxy]) return nil;

    id proxy = nil;
    @try {
        proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, makeProxy, bundleID);
        NSURL *container = proxy && [proxy respondsToSelector:containerSelector]
            ? ((id (*)(id, SEL))objc_msgSend)(proxy, containerSelector) : nil;
        if (![container isKindOfClass:[NSURL class]] || !container.isFileURL) return nil;
        return [[container.path stringByAppendingPathComponent:@"Library/IslandKit"]
                stringByAppendingPathComponent:@"lyrics.plist"];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSArray<NSURL *> *IKImportURLs(NSString *bid, NSDictionary *track) {
    NSURL *directory = [NSURL fileURLWithPath:[IKDataDir stringByAppendingPathComponent:@"Timelines"] isDirectory:YES];
    NSMutableArray *urls = [NSMutableArray array];
    for (NSString *name in IKRecordingFilenames(bid, track)) [urls addObject:[directory URLByAppendingPathComponent:name]];
    return urls;
}

static NSString *IKAdjacentFile(NSString *playerPath, NSString *name) {
    return [playerPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];
}

// ---- 联网时间轴 ----
static NSString *const IKNetTimelineMode = @"联网时间轴（QQ 音乐/网易云）";
// 换歌后等这么久再查：IKRecordingTracker 在换歌后 5 秒内可能纠正继承来的旧歌名
static double IKNetSettleSeconds = 6;
// 缓存目录里最多留这么多首，超出时删最旧的
static NSUInteger IKNetCacheLimit = 400;

static NSString *IKNetDirectory(void) {
    return [IKDataDir stringByAppendingPathComponent:@"NetTimelines"];
}

static NSArray<NSURL *> *IKNetURLs(NSString *bid, NSDictionary *track) {
    NSURL *directory = [NSURL fileURLWithPath:IKNetDirectory() isDirectory:YES];
    NSMutableArray *urls = [NSMutableArray array];
    for (NSString *name in IKRecordingFilenames(bid, track)) [urls addObject:[directory URLByAppendingPathComponent:name]];
    return urls;
}

// 悬浮进程按 IKPrefs 判断。单测宿主的 IKPrefs 只桩了 +log:，没有 +shared 时按关闭处理，也就不会联网
static BOOL IKNetLyricsEnabled(void) {
    return [IKPrefs respondsToSelector:@selector(shared)] && [IKPrefs shared].netLyrics;
}

// 设置 App 里的 IKPrefs 不跟着开关刷新，直接读配置文件；没写过这个键就是默认的打开
static BOOL IKNetLyricsEnabledOnDisk(void) {
    id value = [NSDictionary dictionaryWithContentsOfFile:IKPrefsPath][@"netLyrics"];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

static BOOL IKNetProviderName(id value) {
    return [value isEqual:IKNetProviderQQ] || [value isEqual:IKNetProviderNetease];
}

// 日志只记播放器、提供方、结果、句数和时长差，不记歌名、歌手和歌词
static NSString *IKNetLogLine(NSString *bid, NSString *provider, NSString *result, NSUInteger lines, id delta) {
    BOOL known = [delta isKindOfClass:NSNumber.class] && [delta doubleValue] >= 0 && [delta doubleValue] < 1000;
    return [NSString stringWithFormat:@"net lyrics app=%@ provider=%@ result=%@ lines=%lu dt=%@", bid, provider, result,
            (unsigned long)MIN(lines, (NSUInteger)9999), known ? [NSString stringWithFormat:@"%.1f", [delta doubleValue]] : @"-"];
}

// 悬浮进程是 root。照 IKRepairDataDirectory()：不碰符号链接和普通文件，只动目录本身，
// 属主交给 mobile、权限至少 0755，设置 App 才读得到；root 写出的 0644 文件 mobile 可读
static BOOL IKPrepareNetDirectory(NSString *dir) {
    const char *path = dir.fileSystemRepresentation;
    struct stat st;
    if (lstat(path, &st) != 0) {
        if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES
                                                      attributes:@{NSFilePosixPermissions:@0755} error:nil] ||
            lstat(path, &st) != 0) return NO;
    }
    if (!S_ISDIR(st.st_mode)) return NO;
    if (getuid() == 0) (void)lchown(path, 501, 501);
    if ((st.st_mode & 0755) != 0755) (void)fchmodat(AT_FDCWD, path, (st.st_mode & 07777) | 0755, AT_SYMLINK_NOFOLLOW);
    return YES;
}

// 只留最近的 IKNetCacheLimit 首
static void IKPruneNetDirectory(NSString *dir) {
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLContentModificationDateKey];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:dir isDirectory:YES]
        includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSURL *url in files) {
        NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
        if ([values[NSURLIsRegularFileKey] boolValue] && [url.pathExtension isEqual:@"plist"])
            [entries addObject:@[values[NSURLContentModificationDateKey] ?: NSDate.distantPast, url]];
    }
    if (entries.count <= IKNetCacheLimit) return;
    [entries sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    for (NSUInteger i = 0; i + IKNetCacheLimit < entries.count; i++)
        [NSFileManager.defaultManager removeItemAtURL:entries[i][1] error:nil];
}

// 写成与手动导入同结构的时间轴文件，另带 source=net、provider、fetchedAt
static BOOL IKWriteNetTimeline(NSString *bid, NSDictionary *track, IKNetLyricsResult *result) {
    NSString *name = IKRecordingFilenames(bid, track).firstObject;
    NSString *dir = IKNetDirectory();
    if (!name || !result.lines.count || !IKPrepareNetDirectory(dir)) return NO;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"externalID", @"persistentID", @"title", @"artist", @"duration", @"unstablePersistentID"]) {
        if (track[k]) d[k] = track[k];
    }
    d[@"bundleID"] = bid;
    d[@"lines"] = result.lines;
    d[@"source"] = @"net";
    d[@"provider"] = result.provider;
    d[@"providerSongID"] = result.songID ?: @"";
    d[@"durationDelta"] = @(result.durationDelta);
    d[@"fetchedAt"] = @(NSDate.date.timeIntervalSince1970);
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!plist || plist.length > IKMaxLyricBytes ||
        ![plist writeToFile:[dir stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:nil]) return NO;
    IKPruneNetDirectory(dir);
    return YES;
}

@interface IKMusicCenter ()
@property(nonatomic, copy) NSString *title, *artist, *album, *mediaApplicationID, *playerPath;
@property(nonatomic, copy) NSDictionary *recording, *nativeClock;
- (void)loadPlayerClock;
- (void)syncRecording:(BOOL)force;
- (void)logPlayerDiagnostic;
@property(nonatomic, strong) IKRecordingTracker *tracker;
@property(nonatomic, copy) NSDictionary *rawTrack, *pairedBase;
@property(nonatomic, strong) NSNumber *queueIndex;
@property(nonatomic, copy) NSString *playerLine, *loggedSession, *lastDiagnostic;
@property(nonatomic) double playerLineExpiry;
@property(nonatomic) NSInteger loggedField;
@property(nonatomic, strong) UIImage *artwork;
@property(nonatomic, strong) NSData *artworkData;
@property(nonatomic) BOOL isPlaying, lyricsBridgeActive, singleCue;
@property(nonatomic) double systemDiscontinuity;
@property(nonatomic) double duration, bridgeLyricElapsed, bridgeLyricDuration;
@property(nonatomic, copy) NSString *bridgeLyric, *bridgeNextLyric, *bridgeTitle;
@property(nonatomic, strong) IKPlaybackClock *clock;
@property(nonatomic, copy) NSArray *bridgeLines, *loadedKey;
@property(nonatomic, copy) NSDictionary *loadedTrack;
@property(nonatomic, strong) NSTimer *boundary;
@property(nonatomic) NSUInteger generation;
// 当前时间轴来自哪一类文件：import / player / net / legacy；net 时 bridgePacket 是那份缓存
@property(nonatomic, copy) NSString *bridgeSource;
@property(nonatomic, copy) NSDictionary *bridgePacket;
// 联网查询的状态。netToken 在换歌、换播放器、关开关时递增，用来丢弃过期回调
@property(nonatomic, copy) NSString *netSession;
@property(nonatomic, copy) NSArray *netQueryKey;
@property(nonatomic) double netSessionSeen;
@property(nonatomic) NSUInteger netToken;
@property(nonatomic) BOOL netInFlight, netLoggedCache;
@property(nonatomic, strong) NSTimer *netTimer;
// 这首歌已经上报过的车载歌词，只在本地用来校验联网结果，不外发
@property(nonatomic, strong) NSMutableOrderedSet<NSString *> *netEvidence;
- (void)considerNetLyrics;
@end

static void IKLyricsBridgeChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                  const void *object, CFDictionaryRef info) {
    BOOL clockOnly = CFEqual(name,CFSTR(IKClockChangedDarwin));
    BOOL recording = CFEqual(name,CFSTR(IKRecordingChangedDarwin));
    BOOL request = CFEqual(name,CFSTR(IKRequestRecordingDarwin));
    BOOL diagnostic = CFEqual(name,CFSTR(IKPlaybackDiagnosticsNotification));
    dispatch_async(dispatch_get_main_queue(), ^{
        IKMusicCenter *m = [IKMusicCenter shared];
        if (diagnostic) { [m logPlayerDiagnostic]; return; }
        if (request) { [m syncRecording:YES]; return; }
        if (recording) [m syncRecording:NO];
        else if (clockOnly) [m loadPlayerClock];
        else m.loadedKey = nil;
        [m refreshLyricsBridge];
        [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:m];
    });
}

// 设置里开关“联网匹配逐句歌词”。IKController 收到同一个通知后在主队列上 reload IKPrefs，
// 这里在主队列上再排一轮，保证读到的是新值
static void IKNetPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                              const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            IKMusicCenter *m = [IKMusicCenter shared];
            if ([m refreshLyricsBridge])
                [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:m];
        });
    });
}

@implementation IKMusicCenter

+ (instancetype)shared {
    static IKMusicCenter *music;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ music = [IKMusicCenter new]; music.clock = [IKPlaybackClock new]; music.tracker = [IKRecordingTracker new]; });
    return music;
}

- (void)start {
    MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
    for (NSString *name in @[kMRMediaRemoteNowPlayingInfoDidChangeNotification,
                             kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:name object:nil];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationChanged)
                                               name:kMRMediaRemoteNowPlayingApplicationDidChangeNotification object:nil];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKLyricsBridgeChanged,
                                    CFSTR(IKLyricsChangedDarwin), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKLyricsBridgeChanged,
                                    CFSTR(IKClockChangedDarwin), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    for (NSString *name in @[@IKRecordingChangedDarwin, @IKRequestRecordingDarwin, @IKPlaybackDiagnosticsNotification])
        CFNotificationCenterAddObserver(center, NULL, IKLyricsBridgeChanged, (__bridge CFStringRef)name, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    // 用自己做 observer，和 IKController 对同一通知的登记区分开
    CFNotificationCenterAddObserver(center, (__bridge const void *)self, IKNetPrefsChanged, CFSTR(IKPrefsChangedDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    [self refresh];
}

- (BOOL)hasTrack { return self.title.length > 0; }
- (BOOL)nativePosition:(double *)position rate:(double *)rate {
    double now = NSProcessInfo.processInfo.systemUptime;
    double samplePosition, sampleRate;
    if (!IKPlayerPosition(self.nativeClock,self.mediaApplicationID,self.recording,self.isPlaying,
                          now,NSDate.date.timeIntervalSince1970,&samplePosition,&sampleRate)) return NO;
    if ([self.nativeClock[@"uptime"] doubleValue] < self.systemDiscontinuity &&
        ((sampleRate == 0 && self.clock.speed > 0) || fabs(samplePosition-[self.clock positionAt:now]) > 0.35)) return NO;
    if (position) *position = samplePosition;
    if (rate) *rate = sampleRate;
    return YES;
}
- (double)playbackSpeed {
    double rate;
    return [self nativePosition:NULL rate:&rate] ? rate : self.clock.speed;
}
- (double)currentElapsed {
    double p;
    if (![self nativePosition:&p rate:NULL]) p = [self.clock positionAt:NSProcessInfo.processInfo.systemUptime];
    return self.duration > 0 ? MIN(self.duration, p) : p;
}

static id IKFileStamp(NSString *path) {
    NSDictionary *attrs = path ? [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] : nil;
    if (![attrs[NSFileType] isEqual:NSFileTypeRegular] || [attrs fileSize] > IKMaxLyricBytes) return NSNull.null;
    return @[path, attrs[NSFileSystemFileNumber], attrs[NSFileModificationDate], attrs[NSFileSize]];
}

static NSDictionary *IKSnapshot(NSString *path) {
    NSData *d = path ? IKReadLyricFile([NSURL fileURLWithPath:path]) : nil;
    id value = d ? [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:nil error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

- (void)logPlayerDiagnostic {
    if (!IKSupportedPlayer(self.mediaApplicationID)) return;
    NSDictionary *packet = IKSnapshot(IKAdjacentFile(self.playerPath,IKPlaybackDiagnosticsName));
    NSString *summary = IKDiagnosticSummary(packet,self.mediaApplicationID,NSProcessInfo.processInfo.systemUptime,
                                            NSDate.date.timeIntervalSince1970);
    if (summary && ![self.lastDiagnostic isEqual:summary]) {
        self.lastDiagnostic = summary;
        [IKPrefs log:summary];
    }
}

- (void)syncRecording:(BOOL)force {
    double now = NSProcessInfo.processInfo.systemUptime;
    NSString *bid = self.mediaApplicationID;
    NSDictionary *s = IKSupportedPlayer(bid) ? IKSnapshot(IKAdjacentFile(self.playerPath,@"recording.plist")) : nil;
    NSDictionary *paired = IKLiveRecording(s,bid,self.rawTrack,self.queueIndex,self.pairedBase[@"playSession"],now,NSDate.date.timeIntervalSince1970);
    if (paired) self.pairedBase = paired;
    else if (IKConflictingRecordingIDs(self.pairedBase,self.rawTrack)) self.pairedBase = nil;
    NSDictionary *base = self.pairedBase;
    if (base) {
        // Either observer may learn the stable ID after the first lyric.
        NSMutableDictionary *enriched = nil;
        for (NSString *key in @[@"externalID",@"persistentID"]) {
            if (![base[key] length] && [self.tracker.recording[key] length]) {
                if (!enriched) enriched = [base mutableCopy];
                enriched[key] = self.tracker.recording[key];
            }
        }
        if ([self.tracker.recording[@"unstablePersistentID"] isEqual:@YES] && ![base[@"unstablePersistentID"] isEqual:@YES]) {
            if (!enriched) enriched = [base mutableCopy];
            enriched[@"unstablePersistentID"] = @YES;
        }
        if ([self.tracker.recording[@"correctedTitle"] isEqual:@YES] && ![base[@"correctedTitle"] isEqual:@YES]) {
            if (!enriched) enriched = [base mutableCopy];
            enriched[@"title"] = self.tracker.recording[@"title"];
            enriched[@"correctedTitle"] = @YES;
        }
        if ([base[@"duration"] doubleValue] <= 0 && [self.tracker.recording[@"duration"] doubleValue] > 0) {
            if (!enriched) enriched = [base mutableCopy];
            enriched[@"duration"] = self.tracker.recording[@"duration"];
            if (![self.tracker.recording[@"live"] isEqual:@YES]) [enriched removeObjectForKey:@"live"];
        }
        if (enriched) self.pairedBase = enriched;
    }
    self.recording = self.pairedBase ?: self.tracker.recording;
    self.playerLine = paired ? IKFreshPlayerLyric(s,self.tracker,self.rawTrack) : nil;
    self.playerLineExpiry = paired ? [s[@"uptime"] doubleValue]+10 : 0;
    if (IKSupportedPlayer(bid)) {
        NSURL *file = [NSURL fileURLWithPath:[IKDataDir stringByAppendingPathComponent:@"active-recording.plist"]];
        [self.tracker writeSnapshotTo:file canonical:self.recording force:force];
    }
    NSString *session = self.tracker.recording[@"playSession"];
    if (bid.length && session && ![session isEqual:self.loggedSession]) {
        self.loggedSession = session;
        self.loggedField = 0;
        [IKPrefs log:[NSString stringWithFormat:@"recording app=%@ externalID=%d persistentID=%d queueIndex=%d",
                      bid, [self.rawTrack[@"externalID"] length]>0, [self.rawTrack[@"persistentID"] length]>0, self.queueIndex!=nil]];
        [self logPlayerDiagnostic];
    }
    NSInteger field = self.playerLine && [s[@"lyricField"] isKindOfClass:NSNumber.class] ? [s[@"lyricField"] integerValue] : self.tracker.lyricField;
    if (field >= 0 && field <= 3 && field != self.loggedField) {
        [IKPrefs log:[NSString stringWithFormat:@"lyric field=%ld",(long)field]];
        self.loggedField = field;
    }
}

- (NSString *)reportedLyric {
    return self.playerLine.length && NSProcessInfo.processInfo.systemUptime <= self.playerLineExpiry
        ? self.playerLine : self.tracker.carLyric;
}

- (void)loadPlayerClock {
    NSString *path = [self.playerPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"clock.plist"];
    self.nativeClock = IKSnapshot(path);
}

- (BOOL)refreshLyricsBridge {
    NSString *bid = self.mediaApplicationID;
    NSDictionary *track = self.recording;
    NSArray<NSURL *> *imports = IKImportURLs(bid,track);
    // 优先级：手动导入 > 播放器时间轴 > 联网缓存 > 旧路径。开关关掉时不读联网缓存
    NSArray<NSURL *> *nets = IKSupportedPlayer(bid) && IKNetLyricsEnabled() ? IKNetURLs(bid,track) : @[];
    NSString *legacy = [IKDataDir stringByAppendingPathComponent:@"lyrics.plist"];
    NSMutableArray *files = [NSMutableArray array];
    for (NSURL *url in imports) [files addObject:url.path];
    [files addObject:self.playerPath ?: @""];
    for (NSURL *url in nets) [files addObject:url.path];
    [files addObject:legacy];
    NSUInteger playerIndex = imports.count, netEnd = playerIndex + 1 + nets.count;
    NSMutableArray *key = [NSMutableArray arrayWithObject:bid ?: @""];
    for (NSString *p in files) [key addObject:IKFileStamp(p)];
    BOOL changed = ![key isEqual:self.loadedKey] || (self.loadedTrack != track && ![self.loadedTrack isEqual:track]);
    if (changed) {
        [self loadPlayerClock];
        self.loadedKey = key;
        self.loadedTrack = track;
        self.bridgeLines = nil;
        self.bridgeTitle = nil;
        self.bridgeSource = nil;
        self.bridgePacket = nil;
        self.singleCue = NO;
        // 播放器只给了当前一句（没有整首时间轴）时先记下，联网缓存有整首就用联网的
        NSDictionary *cue = nil, *chosen = nil;
        for (NSUInteger i=0; bid.length && track && ![track[@"live"] isEqual:@YES] && i<files.count; i++) {
            if (cue && i >= netEnd) break;
            if (key[i+1] == NSNull.null) continue;
            NSDictionary *d = IKSnapshot(files[i]);
            if (!d || [d[@"active"] isEqual:@NO]) continue;
            BOOL fromNet = i > playerIndex && i < netEnd;
            if (fromNet && ![d[@"source"] isEqual:@"net"]) continue;
            NSString *declared = IKLyricString(d[@"bundleID"], 256);
            if (declared && ![bid.lowercaseString isEqual:declared.lowercaseString]) continue;
            BOOL ms = [@[@"ms", @"millisecond", @"milliseconds", @YES] containsObject:d[@"timeUnit"] ?: @""];
            double dur = IKNumber(d[@"durationMs"]) / 1000;
            if (dur <= 0) dur = IKNumber(d[@"duration"]) / (ms ? 1000 : 1);
            id persistent = [d[@"unstablePersistentID"] isEqual:@YES] ? nil : d[@"persistentID"];
            NSDictionary *identity = IKTrackIdentity(d[@"externalID"], persistent, d[@"title"] ?: d[@"trackTitle"], d[@"artist"], dur);
            if (!IKSameRecording(track, identity)) continue;
            NSArray *rows = IKNormalizeLyricLines(d[@"lines"] ?: d[@"timeline"] ?: d[@"lyricsLines"], ms, self.duration);
            if (!rows.count) rows = IKParseTimedLyrics(d[@"lrc"] ?: d[@"lyrics"], self.duration);
            BOOL single = NO;
            if (!rows.count && !fromNet && [d[@"current"] ?: d[@"lyric"] isKindOfClass:NSString.class]) {
                id start = d[@"currentStartMs"] ?: d[@"currentStart"] ?: d[@"positionMs"] ?: d[@"position"];
                BOOL startMS = d[@"currentStartMs"] || (!d[@"currentStart"] && d[@"positionMs"]) || ms;
                if (start && [start respondsToSelector:@selector(doubleValue)]) {
                    double begin = [start doubleValue] / (startMS ? 1000 : 1);
                    double end = d[@"currentEndMs"] ? IKNumber(d[@"currentEndMs"])/1000 : IKNumber(d[@"currentEnd"])/(ms?1000:1);
                    double length = d[@"lineDurationMs"] ? IKNumber(d[@"lineDurationMs"])/1000 : IKNumber(d[@"lineDuration"])/(ms?1000:1);
                    if (end <= begin) end = begin + (length > 0 ? length : 4);
                    single = YES;
                    rows = IKNormalizeLyricLines(@[@{@"start":@(begin), @"end":@(end), @"text":d[@"current"] ?: d[@"lyric"]}], NO, self.duration);
                }
            }
            if (!rows.count) continue;
            NSString *kind = i < playerIndex ? @"import" : i == playerIndex ? @"player" : fromNet ? @"net" : @"legacy";
            NSString *source = kind, *field = @"";
            if (i == playerIndex) {
                source = IKMetadataSymbol(d[@"source"]) ? d[@"source"] : @"player";
                if (IKMetadataSymbol(d[@"sourceKey"])) field = [@" key=" stringByAppendingString:d[@"sourceKey"]];
            }
            NSString *title = [track[@"correctedTitle"] isEqual:@YES] ? track[@"title"] : IKLyricString(identity[@"title"],512);
            NSDictionary *pick = @{@"rows":rows, @"single":@(single), @"kind":kind, @"source":source, @"field":field,
                                   @"title":title ?: NSNull.null, @"packet":d};
            if (single && i == playerIndex && nets.count) { cue = pick; continue; }
            chosen = pick;
            break;
        }
        if (!chosen) chosen = cue;
        if (chosen) {
            NSArray *rows = chosen[@"rows"];
            self.bridgeLines = rows;
            self.bridgeTitle = chosen[@"title"] == NSNull.null ? nil : chosen[@"title"];
            self.singleCue = [chosen[@"single"] boolValue];
            self.bridgeSource = chosen[@"kind"];
            if ([chosen[@"kind"] isEqual:@"net"]) self.bridgePacket = chosen[@"packet"];
            [IKPrefs log:[NSString stringWithFormat:@"lyrics timeline app=%@ source=%@%@ lines=%lu",
                          bid, chosen[@"source"], chosen[@"field"], (unsigned long)rows.count]];
        }
    }
    self.lyricsBridgeActive = self.bridgeLines.count > 0;
    [self advanceLyricsBridge];
    [self scheduleBoundary];
    [self considerNetLyrics];
    return changed;
}

#pragma mark 联网时间轴

// 曲目确定、基线歌名稳定、开关打开、本地没有手动导入或播放器时间轴时，后台查一次
- (void)considerNetLyrics {
    NSString *session = self.tracker.recording[@"playSession"];
    double now = NSProcessInfo.processInfo.systemUptime;
    if (!(session ? [session isEqual:self.netSession] : !self.netSession)) {
        // 换歌：作废上一首的计时和还没回来的查询
        self.netToken++;
        [self.netTimer invalidate];
        self.netTimer = nil;
        self.netSession = session;
        self.netSessionSeen = now;
        self.netQueryKey = nil;
        self.netInFlight = NO;
        self.netLoggedCache = NO;
        self.netEvidence = [NSMutableOrderedSet orderedSet];
    }
    NSString *line = session ? self.reportedLyric : nil;
    if (line.length && line.length <= 512 && self.netEvidence.count < 16) [self.netEvidence addObject:line];
    NSString *bid = self.mediaApplicationID;
    NSDictionary *track = self.recording;
    if (!session || !IKSupportedPlayer(bid) || !track || [track[@"live"] isEqual:@YES] || !IKNetLyricsEnabled()) return;
    NSString *title = IKLyricString(track[@"title"],512);
    double duration = [track[@"duration"] doubleValue];
    if (!title || !(duration > 0) || !IKRecordingFilenames(bid,track).count) return;
    if ([self.bridgeSource isEqual:@"import"] || ([self.bridgeSource isEqual:@"player"] && !self.singleCue)) return;
    if ([self.bridgeSource isEqual:@"net"]) {
        // 缓存命中：不再联网
        if (!self.netLoggedCache) {
            self.netLoggedCache = YES;
            NSString *provider = self.bridgePacket[@"provider"];
            if (IKNetProviderName(provider))
                [IKPrefs log:IKNetLogLine(bid, provider, @"cached", self.bridgeLines.count, self.bridgePacket[@"durationDelta"])];
        }
        return;
    }
    double wait = self.netSessionSeen + IKNetSettleSeconds - now;
    if (wait > 0) {
        if (!self.netTimer) {
            __weak IKMusicCenter *weakSelf = self;
            self.netTimer = [NSTimer timerWithTimeInterval:wait repeats:NO block:^(NSTimer *timer) {
                weakSelf.netTimer = nil;
                [weakSelf considerNetLyrics];
            }];
            [NSRunLoop.mainRunLoop addTimer:self.netTimer forMode:NSRunLoopCommonModes];
        }
        return;
    }
    if (self.netInFlight) return;
    NSString *artist = IKLyricString(track[@"artist"],512);
    // 歌手字段被车载歌词占用时，基线里的“歌手”可能是一句歌词：只按歌名搜，靠歌名和时长匹配
    BOOL reliable = artist && self.tracker.lyricField != 2;
    NSArray *identity = @[bid.lowercaseString, title, artist ?: @"", @(llround(duration))];
    NSArray *queryKey = [identity arrayByAddingObject:@(reliable)];
    if ([queryKey isEqual:self.netQueryKey]) return;
    self.netQueryKey = queryKey;
    NSUInteger token = self.netToken;
    __weak IKMusicCenter *weakSelf = self;
    // 歌手不可靠时只能按歌名和时长匹配，再用已上报的车载歌词在本地核对，排除同名同长的翻唱
    NSArray *evidence = reliable ? nil : self.netEvidence.array;
    self.netInFlight = [[IKNetLyricsClient shared] lookupBundle:bid title:title artist:artist artistReliable:reliable
        duration:duration evidence:evidence completion:^(IKNetLyricsResult *result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishNetLookup:result token:token identity:identity];
            });
        }];
}

- (void)finishNetLookup:(IKNetLyricsResult *)result token:(NSUInteger)token identity:(NSArray *)identity {
    // 换歌、换播放器后回来的结果直接丢掉
    if (token != self.netToken) return;
    self.netInFlight = NO;
    NSString *bid = self.mediaApplicationID;
    NSDictionary *track = self.recording;
    NSArray *current = @[bid.lowercaseString ?: @"", IKLyricString(track[@"title"],512) ?: @"",
                         IKLyricString(track[@"artist"],512) ?: @"", @(llround([track[@"duration"] doubleValue]))];
    // 查询期间歌名被纠正或开关被关掉：丢弃，按当前状态重新判断
    if (![current isEqual:identity] || !IKNetLyricsEnabled() || !IKSupportedPlayer(bid)) {
        [self considerNetLyrics];
        return;
    }
    for (NSDictionary *a in result.attempts) {
        if (IKNetProviderName(a[@"provider"]))
            [IKPrefs log:IKNetLogLine(bid, a[@"provider"], a[@"status"], [a[@"lines"] unsignedIntegerValue], a[@"dt"])];
    }
    if (![result.status isEqual:@"hit"]) return;   // 继续显示车载单句
    if (!IKWriteNetTimeline(bid, track, result)) return;
    self.netLoggedCache = YES;
    if ([self refreshLyricsBridge])
        [NSNotificationCenter.defaultCenter postNotificationName:IKMusicDidChangeNotification object:self];
}

- (void)advanceLyricsBridge {
    double pos = [self currentElapsed];
    NSUInteger index = IKCurrentLyricIndex(self.bridgeLines, pos);
    NSDictionary *line = index == NSNotFound ? nil : self.bridgeLines[index];
    if (self.singleCue) self.lyricsBridgeActive = line != nil;
    self.bridgeLyric = line[@"text"];
    double start = [line[@"start"] doubleValue];
    self.bridgeLyricDuration = line ? [line[@"end"] doubleValue]-start : 0;
    self.bridgeLyricElapsed = MIN(self.bridgeLyricDuration, MAX(0,pos-start));
    NSUInteger next = IKNextLyricIndex(self.bridgeLines, pos);
    self.bridgeNextLyric = next < self.bridgeLines.count ? self.bridgeLines[next][@"text"] : nil;
}

- (void)scheduleBoundary {
    [self.boundary invalidate];
    self.boundary = nil;
    if (!self.bridgeLines.count || self.playbackSpeed <= 0) return;
    double pos = [self currentElapsed];
    NSUInteger i = IKCurrentLyricIndex(self.bridgeLines, pos), next = IKNextLyricIndex(self.bridgeLines, pos);
    double boundary;
    if (i != NSNotFound) boundary = [self.bridgeLines[i][@"displayEnd"] doubleValue];
    else if (next < self.bridgeLines.count) boundary = [self.bridgeLines[next][@"start"] doubleValue];
    else return;
    NSTimeInterval delay = MAX(0.001, (boundary-pos)/self.playbackSpeed);
    self.boundary = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        [self advanceLyricsBridge];
        [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:self];
        [self scheduleBoundary];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.boundary forMode:NSRunLoopCommonModes];
}

- (void)applyInfo:(NSDictionary *)info playing:(BOOL)playing {
    NSDictionary *raw = IKSystemTrack(info);
    if (!raw && info.count && self.tracker.recording) raw = @{};
    self.rawTrack = raw;
    NSNumber *index = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoQueueIndex];
    NSString *album = IKLyricString(info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum],512);
    BOOL boundary = [self.tracker observe:raw album:album queueIndex:index
                                 position:info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime]
                                   bundle:self.mediaApplicationID];
    if ([self.tracker.recording[@"unstablePersistentID"] isEqual:@YES] && raw) {
        NSMutableDictionary *adjusted = [raw mutableCopy];
        adjusted[@"unstablePersistentID"] = @YES;
        self.rawTrack = adjusted;
    }
    if (boundary || index || !raw) self.queueIndex = index;
    NSDictionary *previousBase = self.pairedBase;
    if (boundary) self.pairedBase = nil;
    [self syncRecording:NO];
    BOOL hostSwitched = previousBase && self.pairedBase &&
        ![previousBase[@"playSession"] isEqual:self.pairedBase[@"playSession"]] && !IKSameRecording(previousBase,self.pairedBase);
    BOOL same = !boundary && !hostSwitched;
    id rate = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoPlaybackRate];
    id stamp = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTimestamp];
    double now = NSProcessInfo.processInfo.systemUptime;
    double previous = [self.clock positionAt:now];
    [self.clock updatePosition:info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime]
                         stamp:[stamp isKindOfClass:NSDate.class] ? stamp : nil playing:playing
                          rate:rate ? [rate doubleValue] : 1 sameTrack:same wall:NSDate.date uptime:now];
    if (self.isPlaying != playing || (same && fabs([self.clock positionAt:now]-previous) > 0.35)) self.systemDiscontinuity = now;
    self.isPlaying = playing;
    self.title = IKLyricString(raw[@"title"],512) ?: self.recording[@"title"];
    self.artist = IKLyricString(raw[@"artist"],512) ?: self.recording[@"artist"];
    self.duration = [self.recording[@"duration"] doubleValue];
    self.album = album ?: (same ? self.album : nil);
    NSData *art = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtworkData];
    if ([art isKindOfClass:NSData.class] && art.length) {
        if (![art isEqual:self.artworkData]) { self.artworkData = art; self.artwork = [UIImage imageWithData:art]; }
    } else if (!same) { self.artworkData = nil; self.artwork = nil; }
    [self refreshLyricsBridge];
    [NSNotificationCenter.defaultCenter postNotificationName:IKMusicDidChangeNotification object:self];
}

- (void)clearPlayerScope {
    [self.tracker observe:nil album:nil queueIndex:nil position:nil bundle:nil];
    self.mediaApplicationID = nil;
    self.playerPath = nil;
    self.pairedBase = nil;
    self.playerLine = nil;
    self.rawTrack = nil;
    self.recording = nil;
    self.nativeClock = nil;
    self.queueIndex = nil;
    self.loadedKey = nil;
    self.clock = [IKPlaybackClock new];
    self.artwork = nil;
    self.artworkData = nil;
    self.album = nil;
    self.lastDiagnostic = nil;
    // 换播放器：丢弃还没回来的联网查询
    self.netToken++;
    [self.netTimer invalidate];
    self.netTimer = nil;
    self.netSession = nil;
    self.netQueryKey = nil;
    self.netInFlight = NO;
    self.bridgeSource = nil;
    self.bridgePacket = nil;
}

- (void)applicationChanged {
    [self clearPlayerScope];
    [self refresh];
}

- (void)refresh {
    NSUInteger gen = ++self.generation;
    dispatch_queue_t main = dispatch_get_main_queue();
    __block NSDictionary *info;
    __block NSNumber *playing;
    MRMediaRemoteGetNowPlayingApplicationDisplayID(main, ^(NSString *bid) {
        if (gen != self.generation) return;
        BOOL switched = self.mediaApplicationID && ![self.mediaApplicationID isEqual:bid];
        if (switched) [self clearPlayerScope];
        BOOL newScope = switched || ![(self.mediaApplicationID ?: @"") isEqual:(bid ?: @"")];
        self.mediaApplicationID = [bid isKindOfClass:NSString.class] ? bid : nil;
        if (newScope || !self.playerPath) self.playerPath = IKPlayerLyricsPath(self.mediaApplicationID);
        if (info && newScope) [self applyInfo:info playing:playing ? playing.boolValue : self.isPlaying];
    });
    MRMediaRemoteGetNowPlayingApplicationIsPlaying(main, ^(Boolean value) {
        if (gen != self.generation) return;
        playing = @(value);
        if (info) [self applyInfo:info playing:value];
    });
    MRMediaRemoteGetNowPlayingInfo(main, ^(CFDictionaryRef result) {
        if (gen != self.generation) return;
        info = [(__bridge NSDictionary *)result copy] ?: @{};
        id rate = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoPlaybackRate];
        [self applyInfo:info playing:playing ? playing.boolValue : (rate ? [rate doubleValue]>0 : self.isPlaying)];
    });
}

static NSDictionary *IKImportTarget(NSString *bid, NSDictionary *info) {
    NSDictionary *raw = IKSystemTrack(info);
    NSString *playerPath = IKPlayerLyricsPath(bid);
    NSArray *paths = @[[IKDataDir stringByAppendingPathComponent:@"active-recording.plist"], IKAdjacentFile(playerPath,@"recording.plist") ?: @""];
    NSDictionary *base = nil;
    for (NSString *p in paths) {
        base = IKLiveRecording(IKSnapshot(p),bid,raw,info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoQueueIndex],
                               nil,NSProcessInfo.processInfo.systemUptime,NSDate.date.timeIntervalSince1970);
        if (base) break;
    }
    if (!base && ([raw[@"externalID"] length] || [raw[@"persistentID"] length])) base = raw;
    NSMutableDictionary *target = [base mutableCopy];
    if ([target[@"live"] isEqual:@YES]) {
        target[@"bundleID"] = bid;
        target[@"mode"] = @"电台 / 直播节目";
        return target;
    }
    if (!IKRecordingFile(bid,target)) return nil;
    target[@"bundleID"] = bid;
    NSDictionary *packet = IKSnapshot(playerPath);
    BOOL paired = [packet[@"bundleID"] isEqual:bid] && IKSameRecording(packet,target);
    BOOL hasLines = paired && [packet[@"lines"] isKindOfClass:NSArray.class] && [packet[@"lines"] count];
    NSDictionary *live = IKSnapshot(IKAdjacentFile(playerPath,@"recording.plist"));
    BOOL sameLive = IKLiveRecording(live,bid,raw,info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoQueueIndex],
                                    nil,NSProcessInfo.processInfo.systemUptime,NSDate.date.timeIntervalSince1970) != nil;
    if (hasLines) target[@"mode"] = @"播放器时间轴";
    else if (sameLive && IKLyricString(live[@"carLyric"],512)) target[@"mode"] = @"播放器单句（无时间标签）";
    else target[@"mode"] = sameLive ? @"播放器已连接，当前曲目未提供时间轴" : @"系统播放信息";
    // 与悬浮窗同样的优先级：播放器时间轴 > 联网缓存；手动导入在下面覆盖
    if (!hasLines && IKNetLyricsEnabledOnDisk()) {
        for (NSURL *url in IKNetURLs(bid,target)) {
            NSDictionary *net = IKSnapshot(url.path);
            if ([net[@"source"] isEqual:@"net"] && [net[@"lines"] isKindOfClass:NSArray.class] && [net[@"lines"] count] &&
                IKSameRecording(target,net)) { target[@"mode"] = IKNetTimelineMode; break; }
        }
    }
    for (NSURL *url in IKImportURLs(bid,target)) {
        if (IKSameRecording(target,IKSnapshot(url.path))) { target[@"mode"] = @"已绑定本地时间轴"; break; }
    }
    return target;
}

+ (void)requestImportTarget:(void (^)(NSDictionary *))completion {
    dispatch_queue_t main = dispatch_get_main_queue();
    __block BOOL finished = NO;
    void (^finish)(NSDictionary *) = ^(NSDictionary *target) {
        if (!finished) { finished = YES; completion(target); }
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),main,^{ finish(nil); });
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR(IKRequestRecordingDarwin),NULL,NULL,true);
    MRMediaRemoteGetNowPlayingApplicationDisplayID(main, ^(NSString *bid) {
        if (finished || !IKSupportedPlayer(bid)) { finish(nil); return; }
        void (^readTarget)(BOOL) = ^(BOOL last) {
            if (finished) return;
            MRMediaRemoteGetNowPlayingInfo(main, ^(CFDictionaryRef result) {
                if (finished) return;
                NSDictionary *target = IKImportTarget(bid,(__bridge NSDictionary *)result);
                if (!target && !last) return;
                MRMediaRemoteGetNowPlayingApplicationDisplayID(main, ^(NSString *current) {
                    finish([bid isEqual:current] ? target : nil);
                });
            });
        };
        readTarget(NO);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),main,^{ readTarget(YES); });
    });
}

static NSString *IKSelectedShapePath(NSString *bundle) {
    if (!IKSupportedPlayer(bundle)) return nil;
    NSString *name = [NSString stringWithFormat:@"selected-lyric-%@.plist",bundle.lowercaseString];
    return [IKDataDir stringByAppendingPathComponent:name];
}

+ (NSString *)playbackDiagnosticReport {
    NSString *release = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"?";
    NSMutableArray *parts = [NSMutableArray arrayWithObject:[@"IslandKit 播放诊断 " stringByAppendingString:release]];
    for (NSString *bid in @[@"com.tencent.QQMusic",@"com.netease.cloudmusic"]) {
        NSString *path = IKPlayerLyricsPath(bid);
        NSDictionary *launch = IKSnapshot(IKAdjacentFile(path,IKPlaybackLaunchName));
        NSDictionary *phases = @{@"loaded":@"已加载，等待播放器前台及首次采样", @"idle":@"采样成功，暂未播放",
            @"sampling":@"收到播放信息", @"read-error":@"读取播放信息异常", @"sample-error":@"处理播放样本异常",
            @"invalid-metadata":@"播放器返回了不支持的元数据类型"};
        NSString *phase = [launch[@"bundleID"] isEqual:bid] && [launch[@"phase"] isKindOfClass:NSString.class] ? phases[launch[@"phase"]] : nil;
        NSString *when = @"";
        double stamp = [launch[@"wall"] isKindOfClass:NSNumber.class] ? [launch[@"wall"] doubleValue] : 0;
        if (phase && isfinite(stamp) && stamp > 0 && stamp < 1e11) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:stamp];
            when = [@" " stringByAppendingString:[[NSISO8601DateFormatter new] stringFromDate:date]];
        }
        NSString *version = phase ? [@" 播放器版本=" stringByAppendingString:IKPlayerVersion(launch[@"version"])] : @"";
        [parts addObject:[NSString stringWithFormat:@"%@ 适配器最后记录=%@%@%@",
            bid, phase ?: (path ? @"未读到启动记录" : @"播放器容器不可用"), when, version]];
        NSString *history = path ? IKDiagnosticHistory([NSURL fileURLWithPath:path.stringByDeletingLastPathComponent],bid) : nil;
        if (!history) history = IKDiagnosticSummary(IKSnapshot(IKAdjacentFile(path,IKPlaybackDiagnosticsName)),bid,
                                                   NSProcessInfo.processInfo.systemUptime,NSDate.date.timeIntervalSince1970);
        [parts addObject:history ?: @"未读到可用的播放器采样。"];
        NSString *file = IKFileShapeSummary(IKSnapshot(IKSelectedShapePath(bid)));
        if (file) [parts addObject:[NSString stringWithFormat:@"%@ selected/%@",bid,file]];
    }
    // Older HUDs already recorded these events. Export only known fields, never free-form log lines.
    NSURL *url = [NSURL fileURLWithPath:[IKDataDir stringByAppendingPathComponent:@"island.log"]];
    NSString *log = [[NSString alloc] initWithData:IKReadLyricFile(url) ?: [NSData data] encoding:NSUTF8StringEncoding];
    NSString *pattern = @"(?m)^\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} (?:recording app=(?:com\\.tencent\\.QQMusic|com\\.netease\\.cloudmusic) externalID=[01] persistentID=[01] queueIndex=[01]|lyric field=[0-3]|interaction tap state=[0-5] notif=[01]|interaction longPress state=(?:compact|lyric|hang)|net lyrics app=(?i:com\\.tencent\\.qqmusic|com\\.netease\\.cloudmusic) provider=(?:qq|netease) result=(?:hit|miss|error|cached) lines=\\d{1,4} dt=(?:-|\\d{1,3}\\.\\d))$";
    NSRegularExpression *events = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray *matches = log ? [events matchesInString:log options:0 range:NSMakeRange(0,log.length)] : nil;
    [parts addObject:matches.count ? @"悬浮窗最近的播放与切换记录" : @"悬浮窗尚无可导出的播放或切换记录。"];
    for (NSUInteger i = matches.count > 24 ? matches.count - 24 : 0; i < matches.count; i++) {
        [parts addObject:[log substringWithRange:[matches[i] range]]];
    }
    return [parts componentsJoinedByString:@"\n"];
}

// The settings file picker supplies the root. Only shapes leave this method.
+ (NSString *)sampleReportAtURL:(NSURL *)folder {
    NSNumber *isDirectory = nil, *symlink = nil;
    if (!folder.isFileURL || ![folder getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil] || !isDirectory.boolValue ||
        ![folder getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:nil] || symlink.boolValue) return nil;
    NSArray *keys = @[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey, NSURLIsRegularFileKey];
    __block NSUInteger unreadable = 0;
    NSDirectoryEnumerator<NSURL *> *walk = [NSFileManager.defaultManager enumeratorAtURL:folder includingPropertiesForKeys:keys
        options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
        errorHandler:^BOOL(NSURL *url, NSError *error) { unreadable++; return YES; }];
    if (!walk) return nil;
    NSUInteger checked = 0;
    BOOL limited = NO;
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (NSURL *url in walk) {
        if (checked == 256 || rows.count == 32) { limited = YES; break; }
        checked++;
        NSDictionary *attrs = [url resourceValuesForKeys:keys error:nil];
        if (!attrs) { unreadable++; continue; }
        if ([attrs[NSURLIsSymbolicLinkKey] boolValue]) continue;
        if ([attrs[NSURLIsDirectoryKey] boolValue]) {
            if (walk.level >= 3) { [walk skipDescendants]; limited = YES; }
            continue;
        }
        if (![attrs[NSURLIsRegularFileKey] boolValue]) continue;
        NSMutableArray *path = [NSMutableArray arrayWithObject:@"<sample>"];
        BOOL matches = IKLyricSymbol(folder.lastPathComponent) || IKLyricSymbol(url.lastPathComponent);
        NSArray *components = url.pathComponents;
        for (NSUInteger i = components.count - walk.level; i+1 < components.count; i++) {
            BOOL lyric = IKLyricSymbol(components[i]);
            matches |= lyric;
            [path addObject:lyric ? @"<lyric-dir>" : @"<dir>"];
        }
        if (!matches) continue;
        NSString *shape = IKFileShapeSummary(IKLyricFileShape(url));
        if (!shape) { unreadable++; continue; }
        [path addObject:shape];
        [rows addObject:[path componentsJoinedByString:@"/"]];
    }
    [rows sortUsingSelector:@selector(compare:)];
    NSString *summary = [NSString stringWithFormat:@"sample folder checked=%lu matched=%lu unreadable=%lu limited=%d",
                         (unsigned long)checked,(unsigned long)rows.count,(unsigned long)unreadable,limited];
    [rows insertObject:summary atIndex:0];
    return [rows componentsJoinedByString:@"\n"];
}

+ (NSString *)importLyricsAtURL:(NSURL *)url target:(NSDictionary *)target {
    NSArray<NSURL *> *candidates = IKImportURLs(target[@"bundleID"],target);
    NSURL *dest = candidates.firstObject;
    // Keep a no-external-ID binding discoverable on replay if the player later generates a different ID.
    if (![target[@"externalID"] length] && candidates.count > 1 && ![target[@"unstablePersistentID"] isEqual:@YES]) {
        NSURL *metadataURL = candidates.lastObject;
        NSDictionary *old = IKSnapshot(metadataURL.path);
        if (!IKSnapshot(dest.path) && (!old || IKSameRecording(target,old))) dest = metadataURL;
    }
    if (!dest || !IKSupportedPlayer(target[@"bundleID"])) return @"未识别当前歌曲";
    NSDictionary *shape = IKLyricFileShape(url);
    if (shape && [NSFileManager.defaultManager createDirectoryAtPath:IKDataDir withIntermediateDirectories:YES attributes:nil error:nil])
        [shape writeToFile:IKSelectedShapePath(target[@"bundleID"]) atomically:YES];
    NSData *bytes = IKReadLyricFile(url);
    if (!bytes) return @"文件读不到或超过 512 KB";
    NSString *text = IKDecodeLyricText(bytes);
    if (!text) return @"无法读取歌词编码，请选择 UTF-8、UTF-16 或 GBK 系列的文本文件";
    NSArray *lines = IKParseTimedLyrics(text, [target[@"duration"] doubleValue]);
    if (!lines.count) return @"文件里没有可用的时间标签，请选明文 LRC、QRC 或 YRC";
    NSMutableDictionary *d = [target mutableCopy];
    [d removeObjectForKey:@"mode"];
    d[@"lines"] = lines;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!plist || plist.length > IKMaxLyricBytes ||
        ![NSFileManager.defaultManager createDirectoryAtURL:dest.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil] ||
        ![plist writeToURL:dest options:NSDataWritingAtomic error:nil]) return @"歌词未能保存";
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKLyricsChangedDarwin), NULL, NULL, true);
    return nil;
}
+ (NSString *)removeImport:(NSDictionary *)target {
    NSArray *urls = IKImportURLs(target[@"bundleID"],target);
    if (!urls.count || !IKSupportedPlayer(target[@"bundleID"])) return @"未识别当前歌曲";
    for (NSURL *url in urls) {
        if (!IKSameRecording(target,IKSnapshot(url.path))) continue;
        NSError *error = nil;
        if (![NSFileManager.defaultManager removeItemAtURL:url error:&error] && error.code != NSFileNoSuchFileError)
            return @"歌词未能移除";
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKLyricsChangedDarwin), NULL, NULL, true);
    return nil;
}
@end
