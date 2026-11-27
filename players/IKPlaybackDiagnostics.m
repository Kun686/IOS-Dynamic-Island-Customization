#import "IKPlaybackDiagnostics.h"
#import "IKPlaybackDiagnostic.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

static NSString *IKValueKind(id value) {
    if ([value isKindOfClass:NSString.class]) return @"text";
    if ([value isKindOfClass:NSNumber.class]) return @"number";
    if ([value isKindOfClass:NSURL.class]) return @"url";
    if ([value isKindOfClass:MPMediaItemArtwork.class]) return @"artwork";
    if ([value isKindOfClass:NSArray.class]) return @"array";
    if ([value isKindOfClass:NSDictionary.class]) return @"dictionary";
    if ([value isKindOfClass:NSData.class]) return @"data";
    return @"other";
}

// Inspect dictionary field names only at the playback API boundary. Prefer the original text when several tracks are published.
NSArray<NSArray<NSString *> *> *IKPublishedLyricPaths(NSDictionary *info) {
    NSMutableArray *paths = [NSMutableArray array];
    for (id key in info) {
        if (!IKMetadataSymbol(key)) continue;
        if (IKLyricSymbol(key) && ![key isEqual:MPMediaItemPropertyLyrics]) [paths addObject:@[key]];
        NSDictionary *group = info[key];
        if (![group isKindOfClass:NSDictionary.class] || group.count>64) continue;
        for (id child in group) {
            if (IKMetadataSymbol(child) && IKLyricSymbol(child) && [key length]+[child length]+1<=96)
                [paths addObject:@[key,child]];
        }
    }
    [paths sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSString *x = [[a componentsJoinedByString:@"."] lowercaseString], *y = [[b componentsJoinedByString:@"."] lowercaseString];
        BOOL tx = [x containsString:@"trans"] || [x containsString:@"roma"] || [x hasSuffix:@"tlyric"];
        BOOL ty = [y containsString:@"trans"] || [y containsString:@"roma"] || [y hasSuffix:@"tlyric"];
        return tx==ty ? [[a componentsJoinedByString:@"."] compare:[b componentsJoinedByString:@"."]] : (tx ? NSOrderedDescending : NSOrderedAscending);
    }];
    [paths insertObject:@[MPMediaItemPropertyLyrics] atIndex:0];
    return paths;
}

NSDictionary *IKPlaybackSignals(NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{MPMediaItemPropertyTitle:@"title", MPMediaItemPropertyArtist:@"artist", MPMediaItemPropertyAlbumTitle:@"album",
                  MPMediaItemPropertyPlaybackDuration:@"duration", MPNowPlayingInfoPropertyElapsedPlaybackTime:@"elapsed",
                  MPNowPlayingInfoPropertyPlaybackRate:@"rate", MPNowPlayingInfoPropertyPlaybackQueueIndex:@"queueIndex",
                  MPNowPlayingInfoPropertyPlaybackQueueCount:@"queueCount", MPNowPlayingInfoPropertyExternalContentIdentifier:@"externalID",
                  MPMediaItemPropertyPersistentID:@"persistentID", MPNowPlayingInfoPropertyAssetURL:@"assetURL",
                  MPMediaItemPropertyAssetURL:@"mediaAssetURL", MPMediaItemPropertyLyrics:@"lyrics", MPMediaItemPropertyArtwork:@"artwork",
                  MPNowPlayingInfoPropertyMediaType:@"mediaType", MPNowPlayingInfoPropertyIsLiveStream:@"live"};
    });
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *key in names) {
        id value = info[key];
        if (!value) continue;
        fields[names[key]] = IKValueKind(value);
    }
    NSMutableArray *symbols = [NSMutableArray array];
    for (id key in info) {
        if (!names[key] && IKMetadataSymbol(key)) [symbols addObject:key];
    }
    [symbols sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL x = IKLyricSymbol(a), y = IKLyricSymbol(b);
        return x == y ? [a compare:b] : (x ? NSOrderedAscending : NSOrderedDescending);
    }];
    NSMutableDictionary *custom = [NSMutableDictionary dictionary];
    for (NSString *key in symbols) {
        if (custom.count >= 40) break;
        custom[key] = IKValueKind(info[key]);
    }
    NSMutableDictionary *nested = [NSMutableDictionary dictionary];
    NSMutableDictionary *objects = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *path in IKPublishedLyricPaths(info)) {
        NSString *key = [path componentsJoinedByString:@"."];
        id value = info[path[0]];
        if (path.count == 2) {
            value = [(NSDictionary *)value objectForKey:path[1]];
            if (nested.count < 8) nested[key] = IKValueKind(value);
        }
        BOOL array = [value isKindOfClass:NSArray.class];
        id object = array ? [value firstObject] : value;
        if (objects.count < 8 && object && [IKValueKind(object) isEqual:@"other"]) {
            NSString *type = NSStringFromClass([object class]);
            if (IKMetadataSymbol(type)) objects[key] = @{@"type":type, @"array":@(array)};
        }
    }
    id asset = info[MPNowPlayingInfoPropertyAssetURL] ?: info[MPMediaItemPropertyAssetURL];
    NSURL *url = [asset isKindOfClass:NSURL.class] ? asset : nil;
    NSMutableDictionary *packet = [@{@"fields":fields, @"customFields":custom, @"nestedFields":nested, @"lyricObjects":objects, @"unknown":@(MIN(info.count-fields.count,999)),
        @"asset":url ? (url.isFileURL ? @"file" : @"remote") : (asset ? @"other" : @"absent"),
        @"accessEvents":@(MIN(accessEvents,999)), @"jumpEvents":@(MIN(jumpEvents,999))} mutableCopy];
    if (url.isFileURL) {
        NSMutableDictionary *shapes = [NSMutableDictionary dictionary];
        for (NSString *ext in @[@"lrc",@"qrc",@"yrc",@"krc"]) {
            NSURL *sidecar = [url.URLByDeletingPathExtension URLByAppendingPathExtension:ext];
            NSDictionary *shape = IKLyricFileShape(sidecar);
            if (shape) shapes[ext] = shape;
            packet[ext] = @(shape != nil);
        }
        packet[@"sidecarShapes"] = shapes;
    }
    return packet;
}

// Called on a single serial queue in the host. Sample at most every five seconds.
void IKWritePlaybackSignals(NSURL *directory, NSString *bundle, NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents, NSDictionary *result) {
    static double sampledAt, writtenAt;
    static NSDictionary *previous;
    double now = NSProcessInfo.processInfo.systemUptime;
    if (sampledAt && now-sampledAt < 5 && (result == previous[@"result"] || [result isEqual:previous[@"result"]])) return;
    sampledAt = now;
    NSMutableDictionary *signals = [IKPlaybackSignals(info,accessEvents,jumpEvents) mutableCopy];
    if (result) signals[@"result"] = result;
    if ([signals isEqual:previous] && now-writtenAt < 30) return;
    NSMutableDictionary *packet = [signals mutableCopy];
    [packet addEntriesFromDictionary:@{@"schema":@1, @"bundleID":bundle, @"uptime":@(now),
        @"wall":@(NSDate.date.timeIntervalSince1970), @"version":IKPlayerVersion(NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"])}];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil] ||
        ![packet writeToURL:[directory URLByAppendingPathComponent:IKPlaybackDiagnosticsName] atomically:YES]) return;
    IKRememberDiagnostic(directory,packet);
    previous = signals;
    writtenAt = now;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR(IKPlaybackDiagnosticsNotification),NULL,NULL,true);
}

#if IK_DIAGNOSTICS_ONLY
// Standalone observer for a field report without enabling the lyric adapter.
__attribute__((constructor)) static void IKStartPlaybackDiagnostics(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *bid = NSBundle.mainBundle.bundleIdentifier;
        if (![@[@"com.tencent.qqmusic",@"com.netease.cloudmusic"] containsObject:bid.lowercaseString ?: @""]) return;
        if (NSClassFromString(@"IKPlayerLyrics")) return; // The full adapter already emits these observations.
        NSURL *library = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *directory = [library URLByAppendingPathComponent:@"IslandKit" isDirectory:YES];
        dispatch_queue_t queue = dispatch_queue_create("com.islandkit.playback-diagnostics",DISPATCH_QUEUE_SERIAL);
        __block NSUInteger accessEvents = 0, jumps = 0;
        for (NSString *name in @[AVPlayerItemNewAccessLogEntryNotification,AVPlayerItemTimeJumpedNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
                if (![n.object isKindOfClass:AVPlayerItem.class]) return;
                dispatch_async(queue, ^{
                    if ([n.name isEqual:AVPlayerItemTimeJumpedNotification]) jumps++;
                    else accessEvents++;
                });
            }];
        }
        static dispatch_source_t timer;
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
        dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,5*NSEC_PER_SEC,NSEC_PER_SEC/4);
        dispatch_source_set_event_handler(timer, ^{
            @autoreleasepool { IKWritePlaybackSignals(directory,bid,MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo,accessEvents,jumps,nil); }
        });
        dispatch_resume(timer);
    });
}
#endif
