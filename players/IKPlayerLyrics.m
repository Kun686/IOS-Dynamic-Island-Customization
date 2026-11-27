#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "IKLyricsTimeline.h"

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

static NSArray *IKPlayerLines(NSString *published, NSURL *assetURL, double duration, NSString **source) {
    NSArray *lines = IKParseTimedLyrics(published, duration);
    if (lines.count) { *source = @"metadata"; return lines; }
    if (assetURL.isFileURL) {
        NSURL *stem = assetURL.URLByDeletingPathExtension;
        for (NSString *ext in @[@IK_PLAYER_FORMAT, @"lrc"]) {
            NSData *d = IKReadLyricFile([stem URLByAppendingPathExtension:ext]);
            NSString *s = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
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
    NSDictionary *track = IKTrackIdentity(info[MPNowPlayingInfoPropertyExternalContentIdentifier],
        info[MPMediaItemPropertyPersistentID], info[MPMediaItemPropertyTitle], info[MPMediaItemPropertyArtist],
        [info[MPMediaItemPropertyPlaybackDuration] doubleValue]);
    // A car-lyrics field may alternate between the song title and a lyric.
    if (IKSameRecording(track, self.lastTrack) && [self.lastTrack[@"title"] length]) track = self.lastTrack;
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
    NSString *text = IKLyricString(info[MPMediaItemPropertyLyrics], IKMaxLyricBytes);
    NSArray *input = @[track ?: @{}, text ?: @"", url ?: NSNull.null, @(self.streamRevision)];
    if ([self.lastInput isEqual:input]) return NO;
    NSString *source = @"idle";
    double duration = [track[@"duration"] doubleValue];
    NSArray *lines = track ? IKPlayerLines(text, url, duration, &source) : @[];
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
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtURL:self.file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (data.length && data.length <= IKMaxLyricBytes && [data writeToURL:self.file options:NSDataWritingAtomic error:nil]) {
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
    if ([self writeInfo:MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo bundle:bundle]) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(IKLyricsChangedDarwin), NULL, NULL, true);
    }
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
            dispatch_async(q, ^{ self.candidate = note.object; [self publish]; });
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
