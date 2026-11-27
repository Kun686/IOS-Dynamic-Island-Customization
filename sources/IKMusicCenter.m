#import "IKMusicCenter.h"
#import "MediaRemote.h"
#import "IKPrefs.h"
#import <objc/message.h>

NSString *const IKMusicDidChangeNotification = @"IKMusicDidChangeNotification";

static double IKNumber(id value) {
    if (![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class]) return 0;
    double n = [value doubleValue];
    return isfinite(n) ? n : 0;
}

static NSDictionary *IKSystemTrack(NSDictionary *d) {
    return IKTrackIdentity(d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoExternalContentIdentifier],
        d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoUniqueIdentifier],
        d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle], d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist],
        [d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDuration] doubleValue]);
}

static BOOL IKSupportedPlayer(NSString *bid) {
    return [@[@"com.tencent.qqmusic", @"com.netease.cloudmusic"] containsObject:bid.lowercaseString ?: @""];
}

static NSString *IKPlayerLyricsPath(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
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

static NSURL *IKImportURL(NSString *bid, NSDictionary *track) {
    NSString *name = IKRecordingFile(bid, track);
    return name ? [[NSURL fileURLWithPath:[IKDataDir stringByAppendingPathComponent:@"Timelines"] isDirectory:YES]
                   URLByAppendingPathComponent:name] : nil;
}

@interface IKMusicCenter ()
@property(nonatomic, copy) NSString *title, *artist, *album, *mediaApplicationID, *playerPath;
@property(nonatomic, copy) NSDictionary *recording, *nativeClock;
- (void)loadPlayerClock;
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
@end

static void IKLyricsBridgeChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                  const void *object, CFDictionaryRef info) {
    BOOL clockOnly = CFEqual(name,CFSTR(IKClockChangedDarwin));
    dispatch_async(dispatch_get_main_queue(), ^{
        IKMusicCenter *m = [IKMusicCenter shared];
        if (clockOnly) [m loadPlayerClock];
        else m.loadedKey = nil;
        [m refreshLyricsBridge];
        [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:m];
    });
}

@implementation IKMusicCenter

+ (instancetype)shared {
    static IKMusicCenter *music;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ music = [IKMusicCenter new]; music.clock = [IKPlaybackClock new]; });
    return music;
}

- (void)start {
    MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
    for (NSString *name in @[kMRMediaRemoteNowPlayingInfoDidChangeNotification,
                             kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:name object:nil];
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKLyricsBridgeChanged,
                                    CFSTR(IKLyricsChangedDarwin), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKLyricsBridgeChanged,
                                    CFSTR(IKClockChangedDarwin), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
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

- (void)loadPlayerClock {
    NSString *path = [self.playerPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"clock.plist"];
    self.nativeClock = IKSnapshot(path);
}

- (BOOL)refreshLyricsBridge {
    NSString *bid = self.mediaApplicationID;
    NSDictionary *track = self.recording;
    NSString *import = IKImportURL(bid, track).path;
    NSString *legacy = [IKDataDir stringByAppendingPathComponent:@"lyrics.plist"];
    NSArray *files = @[import ?: @"", self.playerPath ?: @"", legacy];
    NSMutableArray *key = [NSMutableArray arrayWithObject:bid ?: @""];
    for (NSString *p in files) [key addObject:IKFileStamp(p)];
    BOOL changed = ![key isEqual:self.loadedKey] || (self.loadedTrack != track && !IKSameRecording(self.loadedTrack, track));
    if (changed) {
        [self loadPlayerClock];
        self.loadedKey = key;
        self.loadedTrack = track;
        self.bridgeLines = nil;
        self.bridgeTitle = nil;
        self.singleCue = NO;
        for (NSUInteger i=0; bid.length && track && i<files.count; i++) {
            if (key[i+1] == NSNull.null) continue;
            NSDictionary *d = IKSnapshot(files[i]);
            if (!d || [d[@"active"] isEqual:@NO]) continue;
            NSString *declared = IKLyricString(d[@"bundleID"], 256);
            if (declared && ![bid.lowercaseString isEqual:declared.lowercaseString]) continue;
            BOOL ms = [@[@"ms", @"millisecond", @"milliseconds", @YES] containsObject:d[@"timeUnit"] ?: @""];
            double dur = IKNumber(d[@"durationMs"]) / 1000;
            if (dur <= 0) dur = IKNumber(d[@"duration"]) / (ms ? 1000 : 1);
            NSDictionary *identity = IKTrackIdentity(d[@"externalID"], d[@"persistentID"], d[@"title"] ?: d[@"trackTitle"], d[@"artist"], dur);
            if (!IKSameRecording(track, identity)) continue;
            NSArray *rows = IKNormalizeLyricLines(d[@"lines"] ?: d[@"timeline"] ?: d[@"lyricsLines"], ms, self.duration);
            if (!rows.count) rows = IKParseTimedLyrics(d[@"lrc"] ?: d[@"lyrics"], self.duration);
            if (!rows.count && [d[@"current"] ?: d[@"lyric"] isKindOfClass:NSString.class]) {
                id start = d[@"currentStartMs"] ?: d[@"currentStart"] ?: d[@"positionMs"] ?: d[@"position"];
                BOOL startMS = d[@"currentStartMs"] || (!d[@"currentStart"] && d[@"positionMs"]) || ms;
                if (start && [start respondsToSelector:@selector(doubleValue)]) {
                    double begin = [start doubleValue] / (startMS ? 1000 : 1);
                    double end = d[@"currentEndMs"] ? IKNumber(d[@"currentEndMs"])/1000 : IKNumber(d[@"currentEnd"])/(ms?1000:1);
                    double length = d[@"lineDurationMs"] ? IKNumber(d[@"lineDurationMs"])/1000 : IKNumber(d[@"lineDuration"])/(ms?1000:1);
                    if (end <= begin) end = begin + (length > 0 ? length : 4);
                    self.singleCue = YES;
                    rows = IKNormalizeLyricLines(@[@{@"start":@(begin), @"end":@(end), @"text":d[@"current"] ?: d[@"lyric"]}], NO, self.duration);
                }
            }
            if (rows.count) {
                self.bridgeLines = rows;
                self.bridgeTitle = identity[@"title"];
                [IKPrefs log:[NSString stringWithFormat:@"lyrics timeline app=%@ source=%@ lines=%lu",
                              bid, i == 0 ? @"import" : (i == 1 ? (IKLyricString(d[@"source"],24) ?: @"player") : @"legacy"), (unsigned long)rows.count]];
                break;
            }
        }
    }
    self.lyricsBridgeActive = self.bridgeLines.count > 0;
    [self advanceLyricsBridge];
    [self scheduleBoundary];
    return changed;
}

- (void)advanceLyricsBridge {
    double pos = [self currentElapsed];
    NSUInteger index = IKCurrentLyricIndex(self.bridgeLines, pos);
    NSDictionary *line = index == NSNotFound ? nil : self.bridgeLines[index];
    if (self.singleCue) self.lyricsBridgeActive = line != nil;
    self.bridgeLyric = line[@"text"];
    double start = [line[@"start"] doubleValue];
    self.bridgeLyricElapsed = line ? MAX(0,pos-start) : 0;
    self.bridgeLyricDuration = line ? [line[@"end"] doubleValue]-start : 0;
    NSUInteger next = IKNextLyricIndex(self.bridgeLines, pos);
    self.bridgeNextLyric = next < self.bridgeLines.count ? self.bridgeLines[next][@"text"] : nil;
}

- (void)scheduleBoundary {
    [self.boundary invalidate];
    self.boundary = nil;
    if (!self.lyricsBridgeActive || self.playbackSpeed <= 0) return;
    double pos = [self currentElapsed];
    NSUInteger i = IKCurrentLyricIndex(self.bridgeLines, pos), next = IKNextLyricIndex(self.bridgeLines, pos);
    double boundary;
    if (i != NSNotFound) boundary = [self.bridgeLines[i][@"end"] doubleValue];
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
    NSDictionary *track = IKSystemTrack(info);
    BOOL same = IKSameRecording(track, self.recording);
    // Players with no comparable metadata can still use the ordinary progress display.
    if (!same && track && !IKSameRecording(track, track)) same = [track isEqual:self.recording];
    id rate = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoPlaybackRate];
    id stamp = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTimestamp];
    double now = NSProcessInfo.processInfo.systemUptime;
    double previous = [self.clock positionAt:now];
    [self.clock updatePosition:info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime]
                         stamp:[stamp isKindOfClass:NSDate.class] ? stamp : nil playing:playing
                          rate:rate ? [rate doubleValue] : 1 sameTrack:same wall:NSDate.date uptime:now];
    if (self.isPlaying != playing || (same && fabs([self.clock positionAt:now]-previous) > 0.35)) self.systemDiscontinuity = now;
    self.recording = track;
    self.isPlaying = playing;
    self.title = track[@"title"];
    self.artist = track[@"artist"];
    self.duration = [track[@"duration"] doubleValue];
    self.album = IKLyricString(info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum], 512);
    NSData *art = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtworkData];
    if ([art isKindOfClass:NSData.class] && art.length) {
        if (![art isEqual:self.artworkData]) { self.artworkData = art; self.artwork = [UIImage imageWithData:art]; }
    } else if (!same) { self.artworkData = nil; self.artwork = nil; }
    [self refreshLyricsBridge];
    [NSNotificationCenter.defaultCenter postNotificationName:IKMusicDidChangeNotification object:self];
}

- (void)refresh {
    NSUInteger gen = ++self.generation;
    dispatch_queue_t main = dispatch_get_main_queue();
    __block NSDictionary *info;
    __block NSNumber *playing;
    __block BOOL receivedID = NO;
    MRMediaRemoteGetNowPlayingApplicationDisplayID(main, ^(NSString *bid) {
        if (gen != self.generation) return;
        receivedID = YES;
        if (![self.mediaApplicationID isEqual:bid] || !self.playerPath) {
            self.mediaApplicationID = [bid isKindOfClass:NSString.class] ? bid : nil;
            self.playerPath = IKPlayerLyricsPath(self.mediaApplicationID);
        }
        if (info && [self refreshLyricsBridge])
            [NSNotificationCenter.defaultCenter postNotificationName:IKMusicDidChangeNotification object:self];
    });
    MRMediaRemoteGetNowPlayingApplicationIsPlaying(main, ^(Boolean value) {
        if (gen != self.generation) return;
        playing = @(value);
        if (info) [self applyInfo:info playing:value];
    });
    MRMediaRemoteGetNowPlayingInfo(main, ^(CFDictionaryRef result) {
        if (gen != self.generation) return;
        info = [(__bridge NSDictionary *)result copy] ?: @{};
        if (!receivedID && !IKSameRecording(IKSystemTrack(info), self.recording)) {
            self.mediaApplicationID = nil;
            self.playerPath = nil;
        }
        id rate = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoPlaybackRate];
        [self applyInfo:info playing:playing ? playing.boolValue : (rate ? [rate doubleValue]>0 : self.isPlaying)];
    });
}

+ (void)requestImportTarget:(void (^)(NSDictionary *))completion {
    dispatch_queue_t main = dispatch_get_main_queue();
    __block BOOL finished = NO;
    void (^finish)(NSDictionary *) = ^(NSDictionary *target) {
        if (!finished) { finished = YES; completion(target); }
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), main, ^{ finish(nil); });
    MRMediaRemoteGetNowPlayingApplicationDisplayID(main, ^(NSString *bid) {
        if (finished || !IKSupportedPlayer(bid)) { finish(nil); return; }
        MRMediaRemoteGetNowPlayingInfo(main, ^(CFDictionaryRef result) {
            NSMutableDictionary *target = [IKSystemTrack((__bridge NSDictionary *)result) mutableCopy];
            target[@"bundleID"] = bid;
            if (!IKRecordingFile(bid,target)) { finish(nil); return; }
            NSDictionary *snapshot = IKSnapshot(IKPlayerLyricsPath(bid));
            BOOL paired = [snapshot[@"bundleID"] isEqual:bid] && IKSameRecording(snapshot, target);
            if ([NSFileManager.defaultManager fileExistsAtPath:IKImportURL(bid,target).path]) target[@"mode"] = @"已绑定本地时间轴";
            else if (paired && [snapshot[@"lines"] count]) target[@"mode"] = @"播放器时间轴";
            else target[@"mode"] = paired ? @"播放器已连接，当前曲目未提供时间轴" : @"系统播放信息";
            MRMediaRemoteGetNowPlayingApplicationDisplayID(main, ^(NSString *current) {
                finish([bid isEqual:current] ? target : nil);
            });
        });
    });
}

+ (NSString *)importLyricsAtURL:(NSURL *)url target:(NSDictionary *)target {
    NSURL *dest = IKImportURL(target[@"bundleID"], target);
    if (!dest || !IKSupportedPlayer(target[@"bundleID"])) return @"未识别当前歌曲";
    NSData *bytes = IKReadLyricFile(url);
    if (!bytes) return @"文件读不到或超过 512 KB";
    NSString *text = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:bytes encoding:NSUnicodeStringEncoding];
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
    NSURL *url = IKImportURL(target[@"bundleID"], target);
    if (!url || !IKSupportedPlayer(target[@"bundleID"])) return @"未识别当前歌曲";
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtURL:url error:&error] && error.code != NSFileNoSuchFileError)
        return @"歌词未能移除";
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKLyricsChangedDarwin), NULL, NULL, true);
    return nil;
}
@end
