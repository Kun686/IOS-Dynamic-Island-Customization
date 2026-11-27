#import "IKLyricsTimeline.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

NSString *IKLyricString(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class] || [value length] > limit) return nil;
    NSString *s = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length ? s : nil;
}

NSDictionary *IKTrackIdentity(id externalID, id persistentID, id title, id artist, double duration) {
    NSString *external = IKLyricString(externalID, 512);
    NSString *persistent = [persistentID isKindOfClass:NSNumber.class] ? [persistentID stringValue] : IKLyricString(persistentID, 128);
    if ([persistent isEqualToString:@"0"]) persistent = nil;
    NSString *name = IKLyricString(title, 512);
    if (!external && !persistent && !name) return nil;
    return @{@"externalID":external ?: @"", @"persistentID":persistent ?: @"", @"title":name ?: @"",
             @"artist":IKLyricString(artist, 512) ?: @"", @"duration":@(isfinite(duration) ? MAX(0, duration) : 0)};
}

BOOL IKSameRecording(NSDictionary *a, NSDictionary *b) {
    if (!a || !b) return NO;
    for (NSString *key in @[@"externalID", @"persistentID"]) {
        NSString *x = IKLyricString(a[key], 512), *y = IKLyricString(b[key], 512);
        if (x && y) return [x isEqualToString:y];
    }
    NSString *title = IKLyricString(a[@"title"], 512), *artist = IKLyricString(a[@"artist"], 512);
    if (!title || ![title isEqual:b[@"title"]] || !artist || ![artist isEqual:b[@"artist"]]) return NO;
    if (![a[@"duration"] isKindOfClass:NSNumber.class] || ![b[@"duration"] isKindOfClass:NSNumber.class]) return NO;
    double x = [a[@"duration"] doubleValue], y = [b[@"duration"] doubleValue];
    return x > 0 && y > 0 && fabs(x-y) < 1.0;
}

NSString *IKRecordingFile(NSString *bundleID, NSDictionary *track) {
    if (!bundleID.length || !IKSameRecording(track, track)) return nil;
    NSMutableArray *components = [NSMutableArray arrayWithObject:bundleID.lowercaseString];
    for (NSString *key in @[@"externalID", @"persistentID"]) {
        if ([track[key] length]) { [components addObjectsFromArray:@[key, track[key]]]; break; }
    }
    if (components.count == 1) {
        [components addObjectsFromArray:@[track[@"title"], track[@"artist"], @(llround([track[@"duration"] doubleValue]))]];
    }
    NSData *d = [NSJSONSerialization dataWithJSONObject:components options:0 error:nil];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, hash);
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i=0; i<sizeof(hash); i++) [name appendFormat:@"%02x", hash[i]];
    return [name stringByAppendingPathExtension:@"plist"];
}

NSData *IKReadLyricFile(NSURL *url) {
    NSNumber *regular = nil, *size = nil;
    if (!url.isFileURL || ![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] || !regular.boolValue) return nil;
    if ([url getResourceValue:&size forKey:NSURLFileSizeKey error:nil] && size.unsignedLongLongValue > IKMaxLyricBytes) return nil;
    NSFileHandle *h = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!h) return nil;
    NSData *data = [h readDataUpToLength:IKMaxLyricBytes + 1 error:nil];
    [h closeAndReturnError:nil];
    return data.length && data.length <= IKMaxLyricBytes ? data : nil;
}

static double IKTime(NSDictionary *row, NSArray *keys, BOOL ms, double fallback) {
    for (NSString *key in keys) {
        id v = row[key];
        if (!v) continue;
        double n;
        if ([v isKindOfClass:NSNumber.class]) n = [v doubleValue];
        else if ([v isKindOfClass:NSString.class]) {
            NSScanner *scanner = [NSScanner scannerWithString:v];
            if (![scanner scanDouble:&n] || !scanner.atEnd) return fallback;
        } else return fallback;
        if (!isfinite(n) || n < 0) return fallback;
        return ms || [key hasSuffix:@"Ms"] ? n/1000.0 : n;
    }
    return fallback;
}

NSArray<NSDictionary *> *IKNormalizeLyricLines(NSArray *lines, BOOL milliseconds, double duration) {
    if (![lines isKindOfClass:NSArray.class] || lines.count > 4000) return @[];
    NSMutableArray<NSDictionary *> *cues = [NSMutableArray array];
    for (NSDictionary *item in lines) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id text = item[@"text"] ?: item[@"lyric"] ?: item[@"line"];
        if (![text isKindOfClass:NSString.class] || [text length] > 2048) continue;
        BOOL ms = item[@"timeUnit"] ? [@[@"ms",@"millisecond",@"milliseconds",@YES] containsObject:item[@"timeUnit"]] : milliseconds;
        double start = IKTime(item, @[@"startMs",@"start",@"timeMs",@"time",@"timestampMs",@"timestamp",@"beginMs",@"begin"], ms, -1);
        if (start < 0 || (duration > 0 && start >= duration)) continue;
        double end = IKTime(item, @[@"endMs",@"end",@"endTimeMs",@"endTime"], ms, -1);
        if (end <= start) {
            double length = IKTime(item, @[@"durationMs",@"duration"], ms, 0);
            end = length > 0 ? start + length : HUGE_VAL;
        }
        [cues addObject:@{@"start":@(start), @"end":@(end), @"text":IKLyricString(text, 2048) ?: @""}];
    }
    [cues sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"start"] compare:b[@"start"]];
    }];
    // Some players put a translation at the same timestamp. Keep the first nonempty original.
    NSMutableArray *unique = [NSMutableArray array];
    for (NSDictionary *cue in cues) {
        if ([unique.lastObject[@"start"] isEqual:cue[@"start"]]) {
            if (![unique.lastObject[@"text"] length]) unique[unique.count-1] = cue;
        } else [unique addObject:cue];
    }
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i=0; i<unique.count; i++) {
        NSDictionary *cue = unique[i];
        double start = [cue[@"start"] doubleValue], end = [cue[@"end"] doubleValue];
        double limit = i+1 < unique.count ? [unique[i+1][@"start"] doubleValue] : duration;
        if (limit > start) end = MIN(end, limit);
        if (!isfinite(end)) end = start + 4;
        if ([cue[@"text"] length]) [result addObject:@{@"text":cue[@"text"], @"start":@(start), @"end":@(end)}];
    }
    return result;
}

@interface IKQRCText : NSObject <NSXMLParserDelegate>
@property(nonatomic, copy) NSString *lyrics;
@end
@implementation IKQRCText
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)uri
 qualifiedName:(NSString *)qualified attributes:(NSDictionary *)attrs {
    if (!self.lyrics && attrs[@"LyricContent"]) { self.lyrics = attrs[@"LyricContent"]; [parser abortParsing]; }
}
@end

NSArray<NSDictionary *> *IKParseTimedLyrics(NSString *input, double duration) {
    NSString *text = IKLyricString(input, IKMaxLyricBytes);
    if (!text) return @[];
    if ([text hasPrefix:@"<"]) {
        IKQRCText *delegate = [IKQRCText new];
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding]];
        parser.shouldResolveExternalEntities = NO;
        parser.delegate = delegate;
        [parser parse];
        text = delegate.lyrics;
        if (!text) return @[];
    }
    static NSRegularExpression *lrc, *karaoke, *word, *offset;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lrc = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{1,3}):([0-5]\\d)(?:[.:](\\d{1,3}))?\\]" options:0 error:nil];
        karaoke = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d+),(\\d+)\\]([^\\[\\r\\n]*)" options:0 error:nil];
        word = [NSRegularExpression regularExpressionWithPattern:@"\\(\\d+,\\d+(?:,\\d+)?\\)" options:0 error:nil];
        offset = [NSRegularExpression regularExpressionWithPattern:@"\\[offset:\\s*([+-]?\\d+)\\]" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSRange all = NSMakeRange(0, text.length);
    NSTextCheckingResult *offsetTag = [offset firstMatchInString:text options:0 range:all];
    double shift = offsetTag ? [text substringWithRange:[offsetTag rangeAtIndex:1]].doubleValue / 1000 : 0;
    NSMutableArray *rows = [NSMutableArray array];
    [karaoke enumerateMatchesInString:text options:0 range:all usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSString *line = [text substringWithRange:[m rangeAtIndex:3]];
        NSString *plain = [word stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0, line.length) withTemplate:@""];
        double start = [text substringWithRange:[m rangeAtIndex:1]].doubleValue / 1000 - shift;
        double length = [text substringWithRange:[m rangeAtIndex:2]].doubleValue / 1000;
        if (start + length > 0) [rows addObject:@{@"start":@(MAX(0,start)), @"end":@(start+length), @"text":plain}];
        *stop = rows.count > 4000;
    }];
    if (!rows.count) [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSArray *tags = [lrc matchesInString:line options:0 range:NSMakeRange(0, line.length)];
        NSTextCheckingResult *last = tags.lastObject;
        if (!last) return;
        NSString *plain = [line substringFromIndex:NSMaxRange(last.range)];
        for (NSTextCheckingResult *m in tags) {
            NSRange f = [m rangeAtIndex:3];
            double fraction = f.location == NSNotFound ? 0 : [line substringWithRange:f].doubleValue / pow(10, f.length);
            double start = [line substringWithRange:[m rangeAtIndex:1]].doubleValue * 60
                         + [line substringWithRange:[m rangeAtIndex:2]].doubleValue + fraction - shift;
            [rows addObject:@{@"start":@(MAX(0,start)), @"text":plain}];
            if (rows.count > 4000) { *stop = YES; break; }
        }
    }];
    return IKNormalizeLyricLines(rows, NO, duration);
}

NSUInteger IKNextLyricIndex(NSArray<NSDictionary *> *lines, double position) {
    NSUInteger low = 0, high = lines.count;
    while (low < high) {
        NSUInteger mid = low + (high-low)/2;
        if ([lines[mid][@"start"] doubleValue] <= position) low = mid+1;
        else high = mid;
    }
    return low;
}

NSUInteger IKCurrentLyricIndex(NSArray<NSDictionary *> *lines, double position) {
    NSUInteger next = IKNextLyricIndex(lines, position);
    if (next == 0 || position >= [lines[next-1][@"end"] doubleValue]) return NSNotFound;
    return next-1;
}

BOOL IKPlayerPosition(NSDictionary *sample, NSString *bundle, NSDictionary *track, BOOL playing,
                      double uptime, double wall, double *position, double *rate) {
    if (!sample || ![sample[@"bundleID"] isEqual:bundle] || !IKSameRecording(sample,track)) return NO;
    for (NSString *key in @[@"position", @"rate", @"uptime", @"wall"]) {
        if (![sample[key] isKindOfClass:NSNumber.class] || !isfinite([sample[key] doubleValue])) return NO;
    }
    double age = uptime - [sample[@"uptime"] doubleValue];
    double speed = [sample[@"rate"] doubleValue], base = [sample[@"position"] doubleValue];
    if (age < 0 || age > 8 || fabs((wall-[sample[@"wall"] doubleValue])-age) > 1 ||
        base < 0 || speed < 0 || speed > 8 || (!playing && speed > 0)) return NO;
    if (position) *position = base + age*speed;
    if (rate) *rate = speed;
    return YES;
}

@implementation IKPlaybackClock {
    double _base, _anchor;
    NSNumber *_lastSample;
    NSDate *_lastStamp;
}
- (double)positionAt:(double)uptime { return MAX(0, _base + MAX(0, uptime-_anchor)*_speed); }
- (void)updatePosition:(NSNumber *)sample stamp:(NSDate *)stamp playing:(BOOL)playing
                  rate:(double)rate sameTrack:(BOOL)same wall:(NSDate *)wall uptime:(double)uptime {
    double speed = playing && isfinite(rate) && rate > 0 ? rate : 0;
    BOOL valid = [sample isKindOfClass:NSNumber.class] && isfinite(sample.doubleValue) && sample.doubleValue >= 0;
    BOOL sameSample = [_lastSample isEqual:sample];
    BOOL toggled = same && ((_speed > 0) != (speed > 0));
    BOOL fresh = valid && (!same || !sameSample || (!toggled && stamp && ![stamp isEqual:_lastStamp]));
    if (toggled && sameSample) _lastStamp = stamp;
    double position = same ? [self positionAt:uptime] : 0;
    if (fresh) {
        position = sample.doubleValue;
        if (stamp && speed > 0) position += MAX(0, [wall timeIntervalSinceDate:stamp])*speed;
        _lastSample = sample;
        _lastStamp = stamp;
    } else if (!same) { _lastSample = nil; _lastStamp = nil; }
    _base = position;
    _anchor = uptime;
    _speed = speed;
}
@end
