#import "IKPlaybackDiagnostics.h"
#import "IKPlaybackDiagnostic.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

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
        NSString *type = @"other";
        if ([value isKindOfClass:NSString.class]) type = @"text";
        else if ([value isKindOfClass:NSNumber.class]) type = @"number";
        else if ([value isKindOfClass:NSURL.class]) type = @"url";
        else if ([value isKindOfClass:MPMediaItemArtwork.class]) type = @"artwork";
        fields[names[key]] = type;
    }
    id asset = info[MPNowPlayingInfoPropertyAssetURL] ?: info[MPMediaItemPropertyAssetURL];
    NSURL *url = [asset isKindOfClass:NSURL.class] ? asset : nil;
    NSMutableDictionary *packet = [@{@"fields":fields, @"unknown":@(MIN(info.count-fields.count,999)),
        @"asset":url ? (url.isFileURL ? @"file" : @"remote") : (asset ? @"other" : @"absent"),
        @"accessEvents":@(MIN(accessEvents,999)), @"jumpEvents":@(MIN(jumpEvents,999))} mutableCopy];
    if (url.isFileURL) {
        for (NSString *ext in @[@"lrc",@"qrc",@"yrc"]) {
            NSURL *sidecar = [url.URLByDeletingPathExtension URLByAppendingPathExtension:ext];
            NSNumber *regular = nil;
            packet[ext] = @([sidecar getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] && regular.boolValue);
        }
    }
    return packet;
}

// Called on a single serial queue in the host. Sample at most every five seconds.
void IKWritePlaybackSignals(NSURL *directory, NSString *bundle, NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents) {
    static double sampledAt, writtenAt;
    static NSDictionary *previous;
    double now = NSProcessInfo.processInfo.systemUptime;
    if (sampledAt && now-sampledAt < 5) return;
    sampledAt = now;
    NSDictionary *signals = IKPlaybackSignals(info,accessEvents,jumpEvents);
    if ([signals isEqual:previous] && now-writtenAt < 30) return;
    NSMutableDictionary *packet = [signals mutableCopy];
    [packet addEntriesFromDictionary:@{@"schema":@1, @"bundleID":bundle, @"uptime":@(now),
        @"wall":@(NSDate.date.timeIntervalSince1970), @"version":IKPlayerVersion(NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"])}];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil] ||
        ![packet writeToURL:[directory URLByAppendingPathComponent:IKPlaybackDiagnosticsName] atomically:YES]) return;
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
            @autoreleasepool { IKWritePlaybackSignals(directory,bid,MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo,accessEvents,jumps); }
        });
        dispatch_resume(timer);
    });
}
#endif
