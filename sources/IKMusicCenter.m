#import "IKMusicCenter.h"
#import "MediaRemote.h"

NSString *const IKMusicDidChangeNotification = @"IKMusicDidChangeNotification";

@interface IKMusicCenter ()
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic) BOOL isPlaying;
@property (nonatomic) double duration;
@property (nonatomic) double elapsed;
@property (nonatomic) double rate;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic) NSUInteger artworkLength;
@end

@implementation IKMusicCenter

+ (instancetype)shared {
    static IKMusicCenter *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IKMusicCenter new]; });
    return s;
}

- (void)start {
    MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refresh)
               name:kMRMediaRemoteNowPlayingInfoDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(refresh)
               name:kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification object:nil];
    [self refresh];
}

- (BOOL)hasTrack {
    return self.title.length > 0;
}

- (void)refresh {
    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        NSDictionary *d = (__bridge NSDictionary *)info;
        self.title  = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle];
        self.artist = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist];
        self.album  = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum];
        self.duration  = [d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDuration] doubleValue];
        self.elapsed   = [d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime] doubleValue];
        self.timestamp = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTimestamp];
        id rate = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoPlaybackRate];
        self.rate = rate ? [rate doubleValue] : 1.0;

        // 封面只在数据变化时重新解码
        NSData *art = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtworkData];
        if (![art isKindOfClass:[NSData class]] || art.length == 0) {
            if (!self.hasTrack) { self.artwork = nil; self.artworkLength = 0; }
        } else if (art.length != self.artworkLength) {
            self.artwork = [UIImage imageWithData:art];
            self.artworkLength = art.length;
        }

        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
            self.isPlaying = playing;
            [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:self];
        });
    });
}

- (double)currentElapsed {
    double e = self.elapsed;
    if (self.isPlaying && [self.timestamp isKindOfClass:[NSDate class]]) {
        e += -[self.timestamp timeIntervalSinceNow] * (self.rate > 0 ? self.rate : 1.0);
    }
    return MAX(0, e);
}

@end
