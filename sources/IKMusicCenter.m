#import "IKMusicCenter.h"
#import "MediaRemote.h"
#import "IKPlaybackDiagnostic.h"
#import "IKLyricEvidence.h"
#import "IKContainerScan.h"
#import "IKPrefs.h"
#import <objc/message.h>

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

static NSURL *IKPlayerContainer(NSString *bundleID) {
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
        return [container isKindOfClass:[NSURL class]] && container.isFileURL ? container : nil;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *IKPlayerLyricsPath(NSString *bundleID) {
    NSURL *container = IKPlayerContainer(bundleID);
    return container ? [[container.path stringByAppendingPathComponent:@"Library/IslandKit"]
                        stringByAppendingPathComponent:@"lyrics.plist"] : nil;
}

static NSURL *IKHUDEventsURL(NSString *bundleID) {
    NSString *name = [NSString stringWithFormat:@"%@%@.plist", IKHUDEventsPrefix, bundleID.lowercaseString];
    return [NSURL fileURLWithPath:[IKDataDir stringByAppendingPathComponent:name]];
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
@property(nonatomic, strong) NSMutableDictionary<NSString *, IKLyricEventLog *> *eventLogs;
// Dictionaries the HUD applied, in the order applied, each waiting for the app ID of its own refresh round.
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *pendingRounds;
@property(nonatomic) BOOL roundFlushScheduled;
@end

// How long an applied dictionary waits for its own round's app ID before it is dropped instead of guessed.
static double IKRoundWait = 3;

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
    NSString *legacy = [IKDataDir stringByAppendingPathComponent:@"lyrics.plist"];
    NSMutableArray *files = [NSMutableArray array];
    for (NSURL *url in imports) [files addObject:url.path];
    [files addObjectsFromArray:@[self.playerPath ?: @"", legacy]];
    NSMutableArray *key = [NSMutableArray arrayWithObject:bid ?: @""];
    for (NSString *p in files) [key addObject:IKFileStamp(p)];
    BOOL changed = ![key isEqual:self.loadedKey] || (self.loadedTrack != track && ![self.loadedTrack isEqual:track]);
    if (changed) {
        [self loadPlayerClock];
        self.loadedKey = key;
        self.loadedTrack = track;
        self.bridgeLines = nil;
        self.bridgeTitle = nil;
        self.singleCue = NO;
        for (NSUInteger i=0; bid.length && track && ![track[@"live"] isEqual:@YES] && i<files.count; i++) {
            if (key[i+1] == NSNull.null) continue;
            NSDictionary *d = IKSnapshot(files[i]);
            if (!d || [d[@"active"] isEqual:@NO]) continue;
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
                self.bridgeTitle = [track[@"correctedTitle"] isEqual:@YES] ? track[@"title"] : IKLyricString(identity[@"title"],512);
                NSString *source = i < imports.count ? @"import" : @"legacy";
                NSString *field = @"";
                if (i == imports.count) {
                    source = IKMetadataSymbol(d[@"source"]) ? d[@"source"] : @"player";
                    if (IKMetadataSymbol(d[@"sourceKey"])) field = [@" key=" stringByAppendingString:d[@"sourceKey"]];
                }
                [IKPrefs log:[NSString stringWithFormat:@"lyrics timeline app=%@ source=%@%@ lines=%lu",
                              bid, source, field, (unsigned long)rows.count]];
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

// When the system delivered a changed title, artist or album from a supported player. The probe inside the player
// records when the player set it. Only times, positions and text lengths are kept.
// `bid` is the app the same refresh round reported, `seen` the uptime at which that round's dictionary arrived.
- (void)noteDisplayFields:(NSDictionary *)info app:(NSString *)bid seenAt:(double)seen {
    if (!IKSupportedPlayer(bid)) return;
    if (!self.eventLogs) self.eventLogs = [NSMutableDictionary dictionary];
    IKLyricEventLog *log = self.eventLogs[bid.lowercaseString];
    if (!log) log = self.eventLogs[bid.lowercaseString] = [[IKLyricEventLog alloc] initWithBundle:bid side:@"hud"];
    NSNumber *(^number)(CFStringRef) = ^NSNumber *(CFStringRef key) {
        id value = info[(__bridge NSString *)key];
        return [value isKindOfClass:NSNumber.class] ? value : nil;
    };
    if ([log observeTitle:info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle]
                   artist:info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist]
                    album:info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum]
                 duration:number(kMRMediaRemoteNowPlayingInfoDuration) elapsed:number(kMRMediaRemoteNowPlayingInfoElapsedTime)
                     rate:number(kMRMediaRemoteNowPlayingInfoPlaybackRate) uptime:seen])
        [log writeTo:IKHUDEventsURL(bid)];
}

// Field-change evidence is recorded in the order the HUD applied the dictionaries, each credited to the app ID of
// its own round. A round whose app ID has not arrived holds back the later ones, so a late reply neither loses
// its event nor lands after a newer one.
- (void)queueRound:(NSUInteger)gen info:(NSDictionary *)info seenAt:(double)seen app:(NSString *)bid known:(BOOL)known {
    if (!self.pendingRounds) self.pendingRounds = [NSMutableArray array];
    NSMutableDictionary *round = [@{@"gen": @(gen), @"info": info, @"seen": @(seen), @"queued": @(NSProcessInfo.processInfo.systemUptime)} mutableCopy];
    if (known) round[@"app"] = bid ?: NSNull.null;
    [self.pendingRounds addObject:round];
    while (self.pendingRounds.count > 32) [self.pendingRounds removeObjectAtIndex:0];
    [self flushRounds];
}

- (void)round:(NSUInteger)gen app:(NSString *)bid {
    for (NSMutableDictionary *round in self.pendingRounds) {
        if ([round[@"gen"] unsignedIntegerValue] != gen) continue;
        round[@"app"] = bid ?: NSNull.null;
        break;
    }
    [self flushRounds];
}

- (void)flushRounds {
    double now = NSProcessInfo.processInfo.systemUptime;
    while (self.pendingRounds.count) {
        NSMutableDictionary *round = self.pendingRounds.firstObject;
        if (!round[@"app"]) {
            double waited = now - [round[@"queued"] doubleValue];
            if (waited < IKRoundWait) {
                if (!self.roundFlushScheduled) {
                    self.roundFlushScheduled = YES;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((IKRoundWait - waited + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        self.roundFlushScheduled = NO;
                        [self flushRounds];
                    });
                }
                return;
            }
        } else if (round[@"app"] != NSNull.null) {
            [self noteDisplayFields:round[@"info"] app:round[@"app"] seenAt:[round[@"seen"] doubleValue]];
        }
        [self.pendingRounds removeObjectAtIndex:0];
    }
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
    // Timing evidence for the probe report: what the island was given and when. Only a dictionary this HUD applied
    // counts, at the moment it arrived; one that arrives after a newer refresh started is dropped by the HUD and not
    // recorded either. It is credited to this round's app ID, which may arrive later, also after newer rounds.
    __block NSString *roundApp;
    __block BOOL appKnown = NO;
    MRMediaRemoteGetNowPlayingApplicationDisplayID(main, ^(NSString *bid) {
        roundApp = [bid isKindOfClass:NSString.class] ? bid : nil;
        appKnown = YES;
        [self round:gen app:roundApp];
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
        double arrived = NSProcessInfo.processInfo.systemUptime;
        if (gen != self.generation) return;
        NSDictionary *copy = [(__bridge NSDictionary *)result copy] ?: @{};
        [self queueRound:gen info:copy seenAt:arrived app:roundApp known:appKnown];
        info = copy;
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

// Probe output from inside the player, the HUD's view of the same field changes, and the container's file shapes.
static NSString *IKLyricEvidenceReport(NSString *bid) {
    NSURL *container = IKPlayerContainer(bid);
    if (![container checkResourceIsReachableAndReturnError:nil]) return nil;
    NSURL *directory = [container URLByAppendingPathComponent:@"Library/IslandKit" isDirectory:YES];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *classes = IKClassInventoryReport(IKReadEvidence([directory URLByAppendingPathComponent:IKProbeClassesName]), bid);
    [parts addObject:classes ?: [NSString stringWithFormat:@"lyric probe app=%@ classes=absent", bid]];
    NSString *unfinished = IKProbeGuardReport(IKReadEvidence([directory URLByAppendingPathComponent:IKProbeGuardName]), bid);
    if (unfinished) [parts addObject:unfinished];
    [parts addObject:IKLyricEventsReport(IKReadEvidence([directory URLByAppendingPathComponent:IKProbeEventsName]),
                                         IKReadEvidence(IKHUDEventsURL(bid)), bid)];
    NSDictionary *namesFile = IKReadEvidence([directory URLByAppendingPathComponent:IKProbeNamesName]);
    [parts addObject:IKProbeNamesReport(namesFile, bid)];
    NSSet *fixed = IKProbeConfirmedNames(namesFile, bid);
    NSString *scan = IKContainerScanReportKeeping(container, bid, IKDefaultScanLimits(), fixed);
    [parts addObject:scan ?: [NSString stringWithFormat:@"container scan app=%@ unreadable", bid]];
    return [parts componentsJoinedByString:@"\n"];
}

// Reads files and walks both player containers. Call it off the main thread.
+ (NSString *)playbackDiagnosticReport {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *bid in @[@"com.tencent.QQMusic",@"com.netease.cloudmusic"]) {
        NSString *path = IKPlayerLyricsPath(bid);
        NSString *history = path ? IKDiagnosticHistory([NSURL fileURLWithPath:path.stringByDeletingLastPathComponent],bid) : nil;
        if (!history) history = IKDiagnosticSummary(IKSnapshot(IKAdjacentFile(path,IKPlaybackDiagnosticsName)),bid,
                                                   NSProcessInfo.processInfo.systemUptime,NSDate.date.timeIntervalSince1970);
        if (history) [parts addObject:history];
        NSString *file = IKFileShapeSummary(IKSnapshot(IKSelectedShapePath(bid)));
        if (file) [parts addObject:[NSString stringWithFormat:@"%@ selected/%@",bid,file]];
        NSString *evidence = IKLyricEvidenceReport(bid);
        if (evidence) [parts addObject:evidence];
    }
    return parts.count ? [parts componentsJoinedByString:@"\n"] : nil;
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
