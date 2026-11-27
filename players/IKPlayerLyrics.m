#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "IKLyricsTimeline.h"
#import "IKPlaybackDiagnostics.h"
#import "IKPlaybackDiagnostic.h"

// Runs inside the player. Read its own published playback metadata and local asset only.
static NSArray *IKAssetLyrics(NSURL *url, double duration) {
    if (!url.isFileURL) return nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    for (AVMetadataItem *item in asset.metadata) {
        if ([item.identifier isEqual:AVMetadataIdentifieriTunesMetadataLyrics] ||
            [item.identifier isEqual:AVMetadataIdentifierID3MetadataUnsynchronizedLyric] ||
            [item.identifier isEqual:AVMetadataIdentifierID3MetadataSynchronizedLyric]) {
            NSString *value = IKLyricString(item.stringValue, IKMaxLyricBytes);
            NSArray *lines = IKParseTimedLyrics(value, duration);
            if (lines.count) return lines;
        }
    }
    return nil;
}

// Copy only the published timing fields. A mutable host dictionary must not change the previous cache key.
static id IKCuePayload(id value, BOOL *ms, NSUInteger depth, id previous) {
    if ([value isKindOfClass:NSString.class]) return [value length] && [value length]<=IKMaxLyricBytes ? [value copy] : nil;
    if ([value isKindOfClass:NSData.class]) return [value length] && [value length]<=IKMaxLyricBytes ? [value copy] : nil;
    if ([value isKindOfClass:NSDictionary.class] && depth<2) {
        NSDictionary *d = value;
        BOOL inherited = *ms;
        if (d[@"timeUnit"]) inherited = [@[@"ms",@"milliseconds",@"millisecond",@YES] containsObject:d[@"timeUnit"]];
        for (NSString *key in @[@"lines",@"timeline",@"lyricsLines",@"lrc",@"qrc",@"yrc",@"lyric",@"lyrics"]) {
            BOOL unit = inherited;
            id inner = IKCuePayload(d[key],&unit,depth+1,previous);
            if (inner) { *ms=unit; return inner; }
        }
        return nil;
    }
    if (![value isKindOfClass:NSArray.class] || ![value count] || [value count]>4000) return nil;
    if (previous && [value isEqual:previous]) return previous;
    static NSSet *columns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        columns = [NSSet setWithArray:@[@"start",@"startMs",@"time",@"timeMs",@"timestamp",@"timestampMs",@"begin",@"beginMs",
            @"end",@"endMs",@"endTime",@"endTimeMs",@"duration",@"durationMs",@"text",@"lyric",@"line",@"timeUnit",@"clearAfter"]];
    });
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger size = 0;
    for (NSDictionary *row in value) {
        if (![row isKindOfClass:NSDictionary.class] || [row count]>40) continue;
        NSMutableDictionary *copy = [NSMutableDictionary dictionary];
        for (id key in row) {
            if (![columns containsObject:key]) continue;
            id v = row[key];
            if ([v isKindOfClass:NSNumber.class]) size += 16;
            else if ([v isKindOfClass:NSString.class] && [v length]<=2048) size += [v lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            else continue;
            size += [key length];
            if (size>IKMaxLyricBytes) return nil;
            copy[key] = [v copy];
        }
        if (copy.count) [rows addObject:copy];
    }
    return rows.count ? rows : nil;
}

static NSArray *IKPublishedInputs(NSDictionary *info, NSArray *previous) {
    NSMutableArray *inputs = [NSMutableArray array];
    for (NSArray<NSString *> *path in IKPublishedLyricPaths(info)) {
        NSString *key = [path componentsJoinedByString:@"."];
        id value = info[path.firstObject];
        BOOL ms = NO;
        if (path.count==2) {
            NSDictionary *group = value;
            ms = [@[@"ms",@"millisecond",@"milliseconds",@YES] containsObject:group[@"timeUnit"] ?: @""];
            value = group[path.lastObject];
        }
        id last = nil;
        for (NSArray *entry in previous) {
            if ([entry[0] isEqual:key]) { last = entry[1]; break; }
        }
        id payload = IKCuePayload(value,&ms,0,last);
        if (payload) [inputs addObject:@[key,payload,@(ms)]];
        if (inputs.count==8) break;
    }
    return inputs;
}

static NSArray *IKPlayerLines(NSArray *inputs, NSURL *assetURL, double duration, NSString **source, NSString **field) {
    NSArray *lines = nil;
    for (NSArray *entry in inputs) {
        id value = entry[1];
        if ([value isKindOfClass:NSData.class]) value = IKDecodeLyricText(value);
        BOOL ms = [entry[2] boolValue];
        NSString *text = IKLyricString(value,IKMaxLyricBytes);
        // Some providers publish a JSON object or a JSON array as a string.
        NSScanner *scanner = text ? [NSScanner scannerWithString:text] : nil;
        BOOL jsonArray = [scanner scanString:@"[" intoString:nil] && [scanner scanString:@"{" intoString:nil];
        if (jsonArray || [text hasPrefix:@"{"]) {
            NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
            id json = bytes.length<=IKMaxLyricBytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
            value = IKCuePayload(json,&ms,0,nil);
        }
        lines = [value isKindOfClass:NSArray.class] ? IKNormalizeLyricLines(value,ms,duration) : IKParseTimedLyrics(value,duration);
        if (lines.count) {
            *field = entry[0];
            *source = [*field isEqual:MPMediaItemPropertyLyrics] ? @"metadata" : @"publishedField";
            return lines;
        }
    }
    if (assetURL.isFileURL) {
        NSURL *stem = assetURL.URLByDeletingPathExtension;
        for (NSString *ext in @[@IK_PLAYER_FORMAT, @"lrc"]) {
            NSData *d = IKReadLyricFile([stem URLByAppendingPathExtension:ext]);
            NSString *s = d ? IKDecodeLyricText(d) : nil;
            lines = IKParseTimedLyrics(s, duration);
            if (lines.count) { *source = @"sidecar"; return lines; }
        }
        lines = IKAssetLyrics(assetURL, duration);
        if (lines.count) { *source = @"audio"; return lines; }
    }
    *source = @"clock";
    return @[];
}

@interface IKPlayerLyrics : NSObject <AVPlayerItemMetadataOutputPushDelegate>
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, weak) AVPlayerItem *candidate;
@property(nonatomic, weak) AVPlayerItem *observedItem;
@property(nonatomic, strong) AVPlayerItemMetadataOutput *output;
@property(nonatomic, copy) NSDictionary *observedTrack;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *streamCues;
@property(nonatomic) NSUInteger streamRevision;
@property(nonatomic, copy) NSArray *lastInput;
@property(nonatomic, copy) NSDictionary *lastClock;
@property(nonatomic) BOOL clearedClock;
@property(nonatomic, copy) NSDictionary *lastTrack;
@property(nonatomic, strong) IKRecordingTracker *tracker;
@property(nonatomic) BOOL publishedRecording;
@property(nonatomic, copy) NSDictionary *lyricEvidence;
@property(nonatomic) NSUInteger accessEvents, jumpEvents;
@property(nonatomic, strong) NSURL *file;
@property(nonatomic, strong) dispatch_source_t timer;
@end

@implementation IKPlayerLyrics
- (void)watchItem:(AVPlayerItem *)item track:(NSDictionary *)track {
    if (self.observedItem == item && (item ? IKSameRecording(track,self.observedTrack) : !self.output)) return;
    if (self.output && self.observedItem) [self.observedItem removeOutput:self.output];
    self.observedItem = item;
    self.observedTrack = track;
    self.output = nil;
    self.streamCues = nil;
    self.streamRevision++;
    if (!item) return;
    NSArray *identifiers = @[AVMetadataIdentifierID3MetadataSynchronizedLyric,
                             AVMetadataIdentifierID3MetadataUnsynchronizedLyric, AVMetadataIdentifieriTunesMetadataLyrics];
    self.output = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:identifiers];
    self.output.advanceIntervalForDelegateInvocation = 0.5;
    [self.output setDelegate:self queue:self.queue];
    [item addOutput:self.output];
    self.streamCues = [NSMutableDictionary dictionary];
}

- (void)metadataOutput:(AVPlayerItemMetadataOutput *)output didOutputTimedMetadataGroups:(NSArray<AVTimedMetadataGroup *> *)groups
   fromPlayerItemTrack:(AVPlayerItemTrack *)itemTrack {
    if (output != self.output) return;
    BOOL changed = NO;
    for (AVTimedMetadataGroup *group in groups) {
        for (AVMetadataItem *tag in group.items) {
            NSString *text = IKLyricString(tag.stringValue, IKMaxLyricBytes);
            if (!text) continue;
            NSArray *rows = IKParseTimedLyrics(text, [self.observedTrack[@"duration"] doubleValue]);
            if (!rows.count) {
                double start = CMTimeGetSeconds(group.timeRange.start);
                if (!isfinite(start) || start < 0 || text.length > 2048) continue;
                double length = CMTimeGetSeconds(group.timeRange.duration);
                rows = @[@{@"start":@(start), @"duration":@(isfinite(length) && length>0 ? length : 0), @"text":text}];
            }
            for (NSDictionary *row in rows) {
                NSNumber *key = row[@"start"];
                if (!self.streamCues[key] && self.streamCues.count >= 4000) continue;
                if (![self.streamCues[key] isEqual:row]) { self.streamCues[key] = row; changed = YES; }
            }
        }
    }
    if (changed) { self.streamRevision++; [self publish]; }
}

- (BOOL)writeInfo:(NSDictionary *)info bundle:(NSString *)bundle {
    NSDictionary *track = IKReportedTrack(info[MPNowPlayingInfoPropertyExternalContentIdentifier],
        info[MPMediaItemPropertyPersistentID], info[MPMediaItemPropertyTitle], info[MPMediaItemPropertyArtist],
        info[MPMediaItemPropertyPlaybackDuration], [info[MPNowPlayingInfoPropertyIsLiveStream] isEqual:@YES]);
    if (!self.tracker) self.tracker = [IKRecordingTracker new];
    if (!track && info.count && self.tracker.recording) track = @{};
    [self.tracker observe:track album:IKLyricString(info[MPMediaItemPropertyAlbumTitle],512)
               queueIndex:info[MPNowPlayingInfoPropertyPlaybackQueueIndex]
                 position:info[MPNowPlayingInfoPropertyElapsedPlaybackTime] bundle:bundle];
    track = self.tracker.recording;
    NSURL *identityFile = [self.file.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"recording.plist"];
    self.publishedRecording = [self.tracker writeSnapshotTo:identityFile canonical:nil force:NO];
    id candidate = info[MPNowPlayingInfoPropertyAssetURL] ?: info[MPMediaItemPropertyAssetURL];
    NSURL *assetURL = [candidate isKindOfClass:NSURL.class] ? candidate : nil;
    AVPlayerItem *item = self.candidate;
    AVURLAsset *asset = [item.asset isKindOfClass:AVURLAsset.class] ? (AVURLAsset *)item.asset : nil;
    // Players may prepare multiple items. Accept events only from the asset actually published as playing.
    if (item && assetURL && [asset.URL isEqual:assetURL] && track) [self watchItem:item track:track];
    else if (![self.observedItem.asset isKindOfClass:AVURLAsset.class] ||
             ![((AVURLAsset *)self.observedItem.asset).URL isEqual:assetURL] || !IKSameRecording(track,self.observedTrack))
        [self watchItem:nil track:nil];
    NSURL *url = assetURL.isFileURL ? assetURL : nil;
    NSArray *published = track ? IKPublishedInputs(info,self.lastInput[1]) : @[];
    NSArray *input = @[track ?: @{}, published, url ?: NSNull.null, @(self.streamRevision)];
    if ([self.lastInput isEqual:input]) return NO;
    NSString *source = @"idle", *field = nil;
    double duration = [track[@"duration"] doubleValue];
    NSArray *lines = track ? IKPlayerLines(published,url,duration,&source,&field) : @[];
    if (!lines.count && self.streamCues.count) {
        lines = IKNormalizeLyricLines(self.streamCues.allValues, NO, duration);
        if (lines.count) source = @"timedAudio";
    }
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithDictionary:track ?: @{}];
    snapshot[@"schema"] = @2;
    snapshot[@"bundleID"] = bundle;
    snapshot[@"active"] = @(track != nil);
    snapshot[@"source"] = source;
    snapshot[@"lines"] = lines;
    if (field) snapshot[@"sourceKey"] = field;
    self.lyricEvidence = @{@"source":@"unwritten",@"lines":@0};
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtURL:self.file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (data.length && data.length <= IKMaxLyricBytes && [data writeToURL:self.file options:NSDataWritingAtomic error:nil]) {
        self.lyricEvidence = @{@"source":source,@"key":field ?: @"",@"lines":@(lines.count)};
        self.lastInput = input;
        self.lastTrack = track;
        return YES;
    }
    return NO;
}

- (void)publishClockForBundle:(NSString *)bundle {
    AVPlayerItem *item = self.observedItem;
    CMTimebaseRef timebase = item.timebase;
    NSDictionary *track = self.observedTrack;
    NSURL *file = [self.file.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"clock.plist"];
    if (!timebase || !IKSameRecording(track,self.lastTrack)) {
        if (self.clearedClock) return;
        if ([NSFileManager.defaultManager fileExistsAtPath:file.path]) {
            if (![NSFileManager.defaultManager removeItemAtURL:file error:nil]) return;
            self.lastClock = nil;
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKClockChangedDarwin), NULL, NULL, true);
        }
        self.clearedClock = YES;
        return;
    }
    double uptime = NSProcessInfo.processInfo.systemUptime;
    double position = CMTimeGetSeconds(item.currentTime);
    double rate = CMTimebaseGetEffectiveRate(timebase);
    if (!isfinite(position) || position < 0 || !isfinite(rate) || rate < 0 || rate > 8) return;
    NSDictionary *last = self.lastClock;
    double dt = uptime - [last[@"uptime"] doubleValue];
    double predicted = [last[@"position"] doubleValue] + dt*[last[@"rate"] doubleValue];
    if (IKSameRecording(last,track) && dt < 4 && fabs(rate-[last[@"rate"] doubleValue]) < 0.001 &&
        fabs(position-predicted) < 0.035) return;
    NSMutableDictionary *sample = [track mutableCopy];
    [sample addEntriesFromDictionary:@{@"bundleID":bundle, @"position":@(position), @"rate":@(rate),
                                       @"uptime":@(uptime), @"wall":@(NSDate.date.timeIntervalSince1970)}];
    if ([sample writeToURL:file atomically:YES]) {
        self.clearedClock = NO;
        self.lastClock = sample;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKClockChangedDarwin), NULL, NULL, true);
    }
}

- (void)publish {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    if ([self writeInfo:info bundle:bundle]) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKLyricsChangedDarwin), NULL, NULL, true);
    }
    IKWritePlaybackSignals(self.file.URLByDeletingLastPathComponent,bundle,info,self.accessEvents,self.jumpEvents,self.lyricEvidence);
    if (self.publishedRecording)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKRecordingChangedDarwin), NULL, NULL, true);
    [self publishClockForBundle:bundle];
}

- (void)start {
    NSURL *library = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
    self.file = [library URLByAppendingPathComponent:@"IslandKit/lyrics.plist"];
    dispatch_queue_t q = dispatch_queue_create("com.islandkit.player.lyrics", DISPATCH_QUEUE_SERIAL);
    self.queue = q;
    for (NSNotificationName name in @[AVPlayerItemNewAccessLogEntryNotification, AVPlayerItemTimeJumpedNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (![note.object isKindOfClass:AVPlayerItem.class]) return;
            dispatch_async(q, ^{
                if ([note.name isEqual:AVPlayerItemTimeJumpedNotification]) self.jumpEvents++;
                else self.accessEvents++;
                self.candidate = note.object;
                [self publish];
            });
        }];
    }
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(self.timer, DISPATCH_TIME_NOW, NSEC_PER_SEC/2, NSEC_PER_SEC/10);
    dispatch_source_set_event_handler(self.timer, ^{ @autoreleasepool { [self publish]; } });
    dispatch_resume(self.timer);
}
@end

__attribute__((constructor)) static void IKStartLyrics(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *bid = NSBundle.mainBundle.bundleIdentifier;
        if (bid.length && [bid caseInsensitiveCompare:@IK_PLAYER_BUNDLE] == NSOrderedSame) {
            static IKPlayerLyrics *player;
            player = [IKPlayerLyrics new];
            [player start];
        }
    });
}
