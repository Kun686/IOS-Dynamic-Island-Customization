#import "IKMusicCenter.h"
#import "MediaRemote.h"
#import "IKPrefs.h"
#import <objc/message.h>
#include <math.h>

NSString *const IKMusicDidChangeNotification = @"IKMusicDidChangeNotification";

@interface IKMusicCenter ()
@property (nonatomic, copy) NSString *mediaTitle;
@property (nonatomic, copy) NSString *mediaArtist;
@property (nonatomic, copy) NSString *mediaAlbum;
@property (nonatomic) double mediaDuration;
@property (nonatomic) double mediaElapsed;
@property (nonatomic) BOOL mediaIsPlaying;
@property (nonatomic, copy) NSString *mediaApplicationID;
@property (nonatomic, strong) NSDate *mediaTimestamp;
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
@property (nonatomic) BOOL lyricsBridgeActive;
@property (nonatomic, copy) NSString *bridgeLyric;
@property (nonatomic, copy) NSString *bridgeNextLyric;
@property (nonatomic, copy) NSString *bridgeTitle;
@property (nonatomic) double bridgeLyricElapsed;
@property (nonatomic) double bridgeLyricDuration;
@property (nonatomic) double bridgePosition;
@property (nonatomic) double bridgeRate;
@property (nonatomic) CFAbsoluteTime bridgeAnchor;
@property (nonatomic, copy) NSArray<NSDictionary *> *bridgeLines;
@property (nonatomic) NSUInteger bridgeLineIndex;
@property (nonatomic) double bridgeLineStart;
@property (nonatomic) double bridgeLineEnd;
@end

static NSString *IKBridgeString(id value, NSUInteger limit) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return text.length > 0 && text.length <= limit ? text : nil;
}

static double IKBridgeNumber(id value, double fallback) {
    if (![value respondsToSelector:@selector(doubleValue)]) return fallback;
    double number = [value doubleValue];
    return isfinite(number) ? number : fallback;
}

static BOOL IKBridgeUnitIsMilliseconds(id unit) {
    if ([unit isKindOfClass:[NSNumber class]]) return [unit boolValue];
    if (![unit isKindOfClass:[NSString class]]) return NO;
    NSString *normalized = [(NSString *)unit lowercaseString];
    return [normalized isEqualToString:@"ms"]
        || [normalized isEqualToString:@"millisecond"]
        || [normalized isEqualToString:@"milliseconds"];
}

static BOOL IKBridgeMillisecondsForKey(NSString *key, NSDictionary *context, BOOL defaultValue) {
    NSString *normalized = [key.lowercaseString stringByReplacingOccurrencesOfString:@"_" withString:@""];
    if ([normalized hasSuffix:@"ms"] || [normalized hasSuffix:@"millisecond"]
        || [normalized hasSuffix:@"milliseconds"]) return YES;
    if (context[@"timeUnit"] != nil) return IKBridgeUnitIsMilliseconds(context[@"timeUnit"]);
    return defaultValue;
}

static double IKBridgeTimeValue(id value, NSString *key, NSDictionary *context,
                                BOOL defaultMilliseconds, double fallback) {
    double number = IKBridgeNumber(value, fallback);
    if (IKBridgeMillisecondsForKey(key, context, defaultMilliseconds)) number /= 1000.0;
    return number;
}

static id IKBridgeFirstValue(NSDictionary *dict, NSArray<NSString *> *keys, NSString **keyOut) {
    for (NSString *key in keys) {
        id value = dict[key];
        if (value != nil) {
            if (keyOut) *keyOut = key;
            return value;
        }
    }
    if (keyOut) *keyOut = nil;
    return nil;
}

static double IKBridgeDictionaryTime(NSDictionary *dict, NSArray<NSString *> *keys,
                                     BOOL defaultMilliseconds, double fallback) {
    NSString *key = nil;
    id value = IKBridgeFirstValue(dict, keys, &key);
    return key ? IKBridgeTimeValue(value, key, dict, defaultMilliseconds, fallback) : fallback;
}

static double IKBridgeUnixTimestampValue(id value, NSString *key, NSDictionary *context,
                                         BOOL defaultMilliseconds, double fallback) {
    double number = IKBridgeTimeValue(value, key, context, defaultMilliseconds, fallback);
    // 兼容没有显式单位、但直接写入 Unix 毫秒时间戳的旧插件。
    if (!IKBridgeMillisecondsForKey(key, context, defaultMilliseconds) && number > 100000000000.0) {
        number /= 1000.0;
    }
    return number;
}

static double IKBridgeUpdatedAt(NSDictionary *dict, double fallback) {
    NSString *key = nil;
    id value = IKBridgeFirstValue(dict, @[@"updatedAtMs", @"updatedAt"], &key);
    return key ? IKBridgeUnixTimestampValue(value, key, dict, NO, fallback) : fallback;
}

static double IKBridgeWallClockNow(void) {
    return [[NSDate date] timeIntervalSince1970];
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

static NSDictionary *IKReadLyricsBridge(NSString *bundleID, NSString **pathOut) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *playerPath = IKPlayerLyricsPath(bundleID);
    if (playerPath.length) [paths addObject:playerPath];
    [paths addObject:[IKDataDir stringByAppendingPathComponent:@"lyrics.plist"]];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if (![fm fileExistsAtPath:path]) continue;
        if (pathOut) *pathOut = path;
        // 插件必须用原子替换写文件，避免悬浮进程读到半个 plist。
        return [NSDictionary dictionaryWithContentsOfFile:path];
    }
    if (pathOut) *pathOut = nil;
    return nil;
}

static double IKBridgeLRCFraction(NSString *fraction) {
    if (fraction.length == 0) return 0;
    double value = fraction.doubleValue;
    double divisor = pow(10.0, MIN((NSUInteger)3, fraction.length));
    return value / divisor;
}

// 接受常见的 LRC 时间轴，方便 TrollFools 插件直接转发播放器的原始歌词。
// 每个时间标签都会生成一条记录，多标签同句仍保持播放器给出的先后关系。
static NSArray<NSDictionary *> *IKBridgeLinesFromLRC(NSString *lrc) {
    if (![lrc isKindOfClass:[NSString class]] || lrc.length == 0) return nil;

    static NSRegularExpression *tagExpression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tagExpression = [NSRegularExpression regularExpressionWithPattern:
                         @"\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
                         options:0 error:nil];
    });

    NSMutableArray<NSDictionary *> *lines = [NSMutableArray array];
    [lrc enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSArray<NSTextCheckingResult *> *matches =
            [tagExpression matchesInString:line options:0 range:NSMakeRange(0, line.length)];
        if (matches.count == 0) return;

        NSTextCheckingResult *last = matches.lastObject;
        NSString *text = [[line substringFromIndex:NSMaxRange(last.range)]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length == 0) return;

        for (NSTextCheckingResult *match in matches) {
            NSInteger minute = [[line substringWithRange:[match rangeAtIndex:1]] integerValue];
            NSInteger second = [[line substringWithRange:[match rangeAtIndex:2]] integerValue];
            NSString *fraction = match.numberOfRanges > 3 && [match rangeAtIndex:3].location != NSNotFound
                ? [line substringWithRange:[match rangeAtIndex:3]] : @"";
            double start = minute * 60.0 + second + IKBridgeLRCFraction(fraction);
            [lines addObject:@{ @"text": text, @"start": @(start), @"end": @(HUGE_VAL) }];
        }
    }];
    return lines.count ? lines : nil;
}

static NSDictionary *IKBridgeLineAtPosition(NSArray<NSDictionary *> *lines, double position, NSUInteger *indexOut) {
    if (indexOut) *indexOut = NSNotFound;
    if (lines.count == 0) return nil;

    NSUInteger index = lines.count - 1;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSDictionary *line = lines[i];
        double start = [line[@"start"] doubleValue];
        double end = [line[@"end"] doubleValue];
        if (position < start) {
            // 两句之间的空白保持上一句，第一句开始前显示第一句。
            index = i == 0 ? 0 : i - 1;
            break;
        }
        if (position < end) {
            index = i;
            break;
        }
    }
    if (indexOut) *indexOut = index;
    return lines[index];
}

static void IKLyricsBridgeChanged(CFNotificationCenterRef center, void *observer,
                                  CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        IKMusicCenter *music = [IKMusicCenter shared];
        [music refreshLyricsBridge];
        [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:music];
    });
}

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
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, IKLyricsBridgeChanged,
                                    CFSTR(IKLyricsChangedDarwin), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    [self refresh];
}

- (BOOL)hasTrack {
    return self.title.length > 0;
}

- (BOOL)refreshLyricsBridge {
    NSString *path = nil;
    NSDictionary *data = IKReadLyricsBridge(self.mediaApplicationID, &path);
    BOOL oldActive = self.lyricsBridgeActive;
    NSString *oldLyric = self.bridgeLyric;
    if (![data isKindOfClass:[NSDictionary class]] || ([data[@"active"] respondsToSelector:@selector(boolValue)] && ![data[@"active"] boolValue])) {
        self.lyricsBridgeActive = NO;
        self.bridgeLyric = nil;
        self.bridgeNextLyric = nil;
        self.bridgeTitle = nil;
        self.bridgeLines = nil;
        self.bridgeLineIndex = NSNotFound;
        self.bridgeLyricElapsed = 0;
        self.bridgeLyricDuration = 0;
        self.bridgePosition = 0;
        self.bridgeRate = 1;
        self.title = self.mediaTitle;
        self.artist = self.mediaArtist;
        self.album = self.mediaAlbum;
        self.duration = self.mediaDuration;
        self.elapsed = self.mediaElapsed;
        self.isPlaying = self.mediaIsPlaying;
        self.timestamp = self.mediaTimestamp;
        return oldActive || oldLyric.length > 0;
    }

    NSString *title = IKBridgeString(data[@"title"] ?: data[@"trackTitle"], 256)
        ?: IKBridgeString(self.mediaTitle, 256);
    NSString *artist = IKBridgeString(data[@"artist"], 256) ?: IKBridgeString(self.mediaArtist, 256);
    BOOL defaultMilliseconds = IKBridgeUnitIsMilliseconds(data[@"timeUnit"]);
    double duration = IKBridgeDictionaryTime(data, @[@"durationMs", @"duration"], defaultMilliseconds, self.mediaDuration);
    if (duration < 0) duration = 0;
    // 播放器的 MediaRemote 状态是实际时钟的唯一来源。文件里的 playing 只用于诊断，
    // 这样插件偶尔漏写暂停时，悬浮窗不会继续推进或停在错误位置。
    BOOL filePlaying = data[@"playing"] ? [data[@"playing"] boolValue] : self.mediaIsPlaying;
    BOOL playing = self.mediaIsPlaying;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double wallNow = IKBridgeWallClockNow();
    double updatedAt = IKBridgeUpdatedAt(data, 0);
    if (updatedAt <= 0) updatedAt = wallNow;

    double position = IKBridgeDictionaryTime(data, @[@"positionMs", @"position", @"elapsedMs", @"elapsed"],
                                              defaultMilliseconds, self.mediaElapsed);
    double rate = IKBridgeNumber(data[@"rate"] ?: data[@"playbackRate"], 1.0);
    rate = MAX(0, MIN(4, rate));
    if (playing) position += MAX(0, wallNow - updatedAt) * rate;
    position = MAX(0, duration > 0 ? MIN(duration, position) : position);

    NSString *current = nil;
    NSString *next = nil;
    double lineStart = IKBridgeDictionaryTime(data, @[@"currentStartMs", @"currentStart"],
                                               defaultMilliseconds, position);
    double lineEnd = IKBridgeDictionaryTime(data, @[@"currentEndMs", @"currentEnd"],
                                             defaultMilliseconds, 0);
    id rawLines = data[@"lines"] ?: data[@"timeline"] ?: data[@"lyricsLines"];
    NSArray *lines = [rawLines isKindOfClass:[NSArray class]] ? rawLines : nil;
    BOOL linesFromLRC = NO;
    if (!lines) {
        NSString *lrc = IKBridgeString(data[@"lrc"] ?: data[@"lyrics"], 200000);
        lines = IKBridgeLinesFromLRC(lrc);
        linesFromLRC = lines != nil;
    }
    NSMutableArray *ordered = [NSMutableArray array];
    if (lines.count > 0 && lines.count <= 2000) {
        for (id item in lines) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *text = IKBridgeString(item[@"text"] ?: item[@"lyric"] ?: item[@"line"], 512);
            if (!text) continue;
            NSString *startKey = nil;
            id startValue = IKBridgeFirstValue(item, @[@"startMs", @"start", @"timeMs", @"time",
                                                        @"timestampMs", @"timestamp", @"beginMs", @"begin"], &startKey);
            BOOL itemMilliseconds = linesFromLRC
                ? NO
                : (item[@"timeUnit"] != nil ? IKBridgeUnitIsMilliseconds(item[@"timeUnit"]) : defaultMilliseconds);
            double start = startKey ? IKBridgeTimeValue(startValue, startKey, item, itemMilliseconds, -1) : -1;
            if (start < 0) continue;
            NSString *endKey = nil;
            id endValue = IKBridgeFirstValue(item, @[@"endMs", @"end", @"endTimeMs", @"endTime"], &endKey);
            double end = endKey ? IKBridgeTimeValue(endValue, endKey, item, itemMilliseconds, -1) : -1;
            if (end < 0) {
                NSString *durationKey = nil;
                id durationValue = IKBridgeFirstValue(item, @[@"durationMs", @"duration"], &durationKey);
                double lineDuration = durationKey
                    ? IKBridgeTimeValue(durationValue, durationKey, item, itemMilliseconds, -1) : -1;
                end = lineDuration > 0 ? start + lineDuration : HUGE_VAL;
            }
            [ordered addObject:@{ @"text": text, @"start": @(start), @"end": @(end) }];
        }
        [ordered sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"start"] compare:b[@"start"]];
        }];
        // 没有显式 end 的句子以下一句 start 为结束，最后一句使用合理的短暂兜底。
        NSMutableArray *normalized = [NSMutableArray arrayWithCapacity:ordered.count];
        for (NSUInteger i = 0; i < ordered.count; i++) {
            NSDictionary *line = ordered[i];
            double start = [line[@"start"] doubleValue];
            double end = [line[@"end"] doubleValue];
            if (!isfinite(end) || end <= start) {
                end = i + 1 < ordered.count ? [ordered[i + 1][@"start"] doubleValue] : start + 4;
            }
            if (end <= start) continue;
            [normalized addObject:@{ @"text": line[@"text"], @"start": @(start), @"end": @(end) }];
        }
        ordered = normalized;
        NSUInteger index = NSNotFound;
        NSDictionary *line = IKBridgeLineAtPosition(ordered, position, &index);
        if (line) {
            current = line[@"text"];
            lineStart = [line[@"start"] doubleValue];
            lineEnd = [line[@"end"] doubleValue];
            if (index + 1 < ordered.count) next = ordered[index + 1][@"text"];
        }
    }
    if (!current) {
        current = IKBridgeString(data[@"current"] ?: data[@"lyric"], 512);
        next = IKBridgeString(data[@"next"], 512);
        double lineDuration = IKBridgeDictionaryTime(data, @[@"lineDurationMs", @"lineDuration"],
                                                      defaultMilliseconds, 4);
        if (lineEnd <= lineStart) lineEnd = lineStart + MAX(1.5, lineDuration);
    }
    if (!title || !current) {
        self.lyricsBridgeActive = NO;
        self.bridgeLyric = nil;
        self.bridgeNextLyric = nil;
        self.bridgeTitle = nil;
        self.bridgeLines = nil;
        self.bridgeLineIndex = NSNotFound;
        self.bridgeRate = 1;
        self.title = self.mediaTitle;
        self.artist = self.mediaArtist;
        self.album = self.mediaAlbum;
        self.duration = self.mediaDuration;
        self.elapsed = self.mediaElapsed;
        self.isPlaying = self.mediaIsPlaying;
        self.timestamp = self.mediaTimestamp;
        return oldActive || oldLyric.length > 0;
    }

    self.lyricsBridgeActive = YES;
    self.bridgeLyric = current;
    self.bridgeNextLyric = next;
    self.bridgeTitle = title;
    self.bridgeLines = [ordered copy];
    self.bridgePosition = position;
    self.bridgeRate = rate;
    self.bridgeAnchor = now;
    self.bridgeLyricElapsed = MAX(0, position - lineStart);
    self.bridgeLyricDuration = MAX(0.01, MIN(60, lineEnd - lineStart));
    self.bridgeLineStart = lineStart;
    self.bridgeLineEnd = lineEnd;
    NSUInteger currentIndex = NSNotFound;
    IKBridgeLineAtPosition(self.bridgeLines, position, &currentIndex);
    self.bridgeLineIndex = currentIndex;
    self.title = title;
    self.artist = artist ?: self.mediaArtist;
    self.album = self.mediaAlbum;
    self.duration = duration;
    self.elapsed = position;
    self.isPlaying = playing;
    self.timestamp = [NSDate date];
    if (!oldActive || ![oldLyric isEqualToString:current]) {
        [IKPrefs log:[NSString stringWithFormat:@"lyrics bridge active app=%@ source=%@ title.len=%lu lines=%lu position=%.2f line.len=%lu filePlaying=%d mediaPlaying=%d",
                      self.mediaApplicationID ?: @"-", path.length && [path hasPrefix:IKDataDir] ? @"global" : @"player",
                      (unsigned long)title.length, (unsigned long)self.bridgeLines.count,
                      position, (unsigned long)current.length, filePlaying, playing]];
    }
    return !oldActive || ![oldLyric isEqualToString:current];
}

- (void)advanceLyricsBridge {
    if (!self.lyricsBridgeActive) return;

    double position = self.bridgePosition;
    if (self.isPlaying) position += MAX(0, CFAbsoluteTimeGetCurrent() - self.bridgeAnchor) * self.bridgeRate;
    position = MAX(0, self.duration > 0 ? MIN(self.duration, position) : position);

    NSUInteger index = NSNotFound;
    NSDictionary *line = IKBridgeLineAtPosition(self.bridgeLines, position, &index);
    if (line && index != self.bridgeLineIndex) {
        self.bridgeLineIndex = index;
        self.bridgeLyric = line[@"text"];
        self.bridgeLineStart = [line[@"start"] doubleValue];
        self.bridgeLineEnd = [line[@"end"] doubleValue];
        self.bridgeLyricDuration = MAX(0.01, MIN(60, self.bridgeLineEnd - self.bridgeLineStart));
        self.bridgeNextLyric = index + 1 < self.bridgeLines.count ? self.bridgeLines[index + 1][@"text"] : nil;
    }
    self.bridgeLyricElapsed = MAX(0, position - self.bridgeLineStart);
}

- (void)refresh {
    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        NSDictionary *d = (__bridge NSDictionary *)info;
        self.mediaTitle  = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle];
        self.mediaArtist = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist];
        self.mediaAlbum  = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum];
        self.mediaDuration  = [d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDuration] doubleValue];
        self.mediaElapsed   = [d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime] doubleValue];
        self.mediaTimestamp = d[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTimestamp];
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

        MRMediaRemoteGetNowPlayingApplicationDisplayID(dispatch_get_main_queue(), ^(NSString *displayID) {
            self.mediaApplicationID = [displayID isKindOfClass:[NSString class]] ? displayID : nil;
            MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
                self.mediaIsPlaying = playing;
                [self refreshLyricsBridge];
                if (!self.lyricsBridgeActive) {
                    self.title = self.mediaTitle;
                    self.artist = self.mediaArtist;
                    self.album = self.mediaAlbum;
                    self.duration = self.mediaDuration;
                    self.elapsed = self.mediaElapsed;
                    self.isPlaying = self.mediaIsPlaying;
                    self.timestamp = self.mediaTimestamp;
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:IKMusicDidChangeNotification object:self];
            });
        });
    });
}

- (double)currentElapsed {
    if (self.lyricsBridgeActive) {
        double elapsed = self.bridgePosition;
        if (self.isPlaying) elapsed += MAX(0, CFAbsoluteTimeGetCurrent() - self.bridgeAnchor) * self.bridgeRate;
        return MAX(0, self.duration > 0 ? MIN(self.duration, elapsed) : elapsed);
    }
    double e = self.elapsed;
    if (self.isPlaying && [self.timestamp isKindOfClass:[NSDate class]]) {
        e += -[self.timestamp timeIntervalSinceNow] * (self.rate > 0 ? self.rate : 1.0);
    }
    return MAX(0, e);
}

@end
