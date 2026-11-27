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
    if (!external && !persistent && !name && !IKLyricString(artist,512) && !(duration > 0)) return nil;
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

NSArray<NSString *> *IKRecordingFilenames(NSString *bundle, NSDictionary *track) {
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary *candidate = [track mutableCopy];
    NSString *name = IKRecordingFile(bundle, candidate);
    if (name) [names addObject:name];
    for (NSString *key in @[@"externalID", @"persistentID"]) {
        if (![candidate[key] length]) continue;
        [candidate removeObjectForKey:key];
        name = IKRecordingFile(bundle, candidate);
        if (name) [names addObject:name];
    }
    return names.array;
}

static NSString *IKRawSignature(NSDictionary *raw) {
    if (!raw) return nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[raw[@"title"] ?: @"", raw[@"artist"] ?: @""] options:0 error:nil];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, hash);
    return [[NSData dataWithBytes:hash length:sizeof(hash)] base64EncodedStringWithOptions:0];
}

BOOL IKConflictingRecordingIDs(NSDictionary *a, NSDictionary *b) {
    for (NSString *key in @[@"externalID", @"persistentID"]) {
        NSString *x = IKLyricString(a[key],512), *y = IKLyricString(b[key],512);
        if (x && y) return ![x isEqual:y];
    }
    return NO;
}

static NSNumber *IKIndex(id value) {
    return [value isKindOfClass:NSNumber.class] && [value doubleValue] >= 0 ? value : nil;
}

@implementation IKRecordingTracker {
    NSString *_bundle;
    NSArray<NSString *> *_baselineFields, *_lastFields;
    NSDictionary *_raw, *_written;
    double _writtenAt;
    NSNumber *_index, *_position;
}

// A queue or persistent identifier is affirmative evidence of a track boundary.
// A seek alone, and a change to either car-display field alone, are not.
- (BOOL)observe:(NSDictionary *)raw album:(NSString *)album queueIndex:(NSNumber *)index
       position:(NSNumber *)position bundle:(NSString *)bundle {
    if (!raw) {
        BOOL changed = _recording != nil;
        _recording = nil; _raw = nil; _lastFields = nil; _baselineFields = nil;
        _carLyric = nil; _lyricField = 0; _index = nil; _position = nil; _bundle = nil;
        return changed;
    }
    index = IKIndex(index);
    if (![position isKindOfClass:NSNumber.class] || !isfinite(position.doubleValue) || position.doubleValue < 0) position = nil;
    NSString *title = IKLyricString(raw[@"title"],512), *artist = IKLyricString(raw[@"artist"],512);
    NSArray *fields = @[title ?: @"", artist ?: @"", album ?: @""];
    double duration = [raw[@"duration"] doubleValue], previous = [_recording[@"duration"] doubleValue];
    BOOL sharedID = NO;
    for (NSString *key in @[@"externalID", @"persistentID"]) {
        if ([raw[key] length] && [raw[key] isEqual:_recording[key]]) sharedID = YES;
    }
    BOOL fresh = !_recording || (bundle.length && _bundle.length && ![_bundle isEqual:bundle]) ||
        IKConflictingRecordingIDs(raw,_recording) || (index && _index && ![index isEqual:_index]);
    if (!fresh && !sharedID) {
        BOOL differentDuration = previous > 0 && duration > 0 && fabs(previous-duration) >= 1.0;
        BOOL titleChanged = title && [_lastFields[0] length] && ![title isEqual:_lastFields[0]] && ![title isEqual:_baselineFields[0]];
        BOOL artistChanged = artist && [_lastFields[1] length] && ![artist isEqual:_lastFields[1]] && ![artist isEqual:_baselineFields[1]];
        BOOL restarted = position && _position.doubleValue > 5 && position.doubleValue <= 2;
        BOOL playedToEnd = previous > 0 && _position.doubleValue >= previous-2;
        BOOL changedSongTitle = titleChanged && _lyricField != 1 && [artist isEqual:_baselineFields[1]];
        fresh = differentDuration || (restarted && (changedSongTitle || (titleChanged && artistChanged) ||
                                                      (playedToEnd && (titleChanged || artistChanged))));
    }
    if (fresh) {
        NSMutableDictionary *base = [raw mutableCopy];
        base[@"playSession"] = NSUUID.UUID.UUIDString;
        _recording = [base copy];
        _baselineFields = fields;
        _lastFields = fields;
        _lyricField = 0;
        _index = nil; _position = nil;
    } else {
        // Fill first observations that arrived late without replacing known baseline values.
        NSMutableDictionary *base = [_recording mutableCopy];
        for (NSString *key in @[@"externalID",@"persistentID",@"title",@"artist"]) {
            if (![base[key] length] && [raw[key] length]) base[key] = raw[key];
        }
        if (previous <= 0 && duration > 0) base[@"duration"] = @(duration);
        if (![base isEqual:_recording]) _recording = [base copy];
        NSMutableArray *baseline = [_baselineFields mutableCopy];
        NSMutableArray *current = [fields mutableCopy];
        NSInteger selected = 0;
        for (NSUInteger i = 0; i < current.count; i++) {
            // A sparse media update can carry the playback position or only one display field.
            if (![current[i] length]) current[i] = _lastFields[i];
            if (![baseline[i] length]) baseline[i] = current[i];
            if ([current[i] isEqual:baseline[i]] || [current[i] isEqual:_lastFields[i]]) continue;
            if (!selected || _lyricField == (NSInteger)i+1) selected = (NSInteger)i+1;
        }
        if (selected) _lyricField = selected;
        if (_lyricField && [current[_lyricField-1] isEqual:baseline[_lyricField-1]]) _lyricField = 0;
        _baselineFields = baseline;
        _lastFields = current;
    }
    NSString *line = _lyricField ? _lastFields[_lyricField-1] : nil;
    if (fresh || ![(line ?: @"") isEqual:(_carLyric ?: @"")]) _lyricUpdatedAt = NSProcessInfo.processInfo.systemUptime;
    _carLyric = line;
    _raw = @{@"title":_lastFields[0], @"artist":_lastFields[1]};
    if (index) _index = index;
    if (position) _position = position;
    if (bundle.length) _bundle = [bundle copy];
    return fresh;
}

- (NSDictionary *)snapshotAtUptime:(double)uptime wall:(double)wall {
    if (!_recording || !_bundle.length) return nil;
    NSMutableDictionary *state = [_recording mutableCopy];
    state[@"bundleID"] = _bundle;
    state[@"observed"] = IKRawSignature(_raw);
    if (_index) state[@"queueIndex"] = _index;
    state[@"uptime"] = @(uptime);
    state[@"wall"] = @(wall);
    if (_carLyric.length) {
        state[@"carLyric"] = _carLyric;
        state[@"lyricUptime"] = @(_lyricUpdatedAt);
    }
    return state;
}

- (BOOL)writeSnapshotTo:(NSURL *)file canonical:(NSDictionary *)canonical force:(BOOL)force {
    if (!file.isFileURL) return NO;
    double now = NSProcessInfo.processInfo.systemUptime;
    NSMutableDictionary *s = [[self snapshotAtUptime:0 wall:0] mutableCopy] ?: [@{@"active":@NO} mutableCopy];
    if (canonical && _recording) [s addEntriesFromDictionary:canonical];
    if (!force && [_written isEqual:s] && (!_recording || now-_writtenAt < 4)) return NO;
    NSDictionary *key = [s copy];
    s[@"uptime"] = @(now);
    s[@"wall"] = @(NSDate.date.timeIntervalSince1970);
    if (![NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent
                               withIntermediateDirectories:YES attributes:nil error:nil] || ![s writeToURL:file atomically:YES]) return NO;
    _written = key;
    _writtenAt = now;
    return YES;
}

@end

// Pair independent observers even when the settings UI or HUD opens mid-verse.
// Only the live handoff uses session evidence. Persisted timelines still require a strict recording match.
NSDictionary *IKLiveRecording(NSDictionary *s, NSString *bundle, NSDictionary *raw,
                              NSNumber *index, NSString *pairedSession, double uptime, double wall) {
    if (!raw || !bundle.length || ![s[@"bundleID"] isEqual:bundle] || !IKLyricString(s[@"playSession"],64) ||
        ![s[@"uptime"] isKindOfClass:NSNumber.class] || ![s[@"wall"] isKindOfClass:NSNumber.class]) return nil;
    double age = uptime - [s[@"uptime"] doubleValue];
    double wallAge = wall - [s[@"wall"] doubleValue];
    if (!isfinite(age) || !isfinite(wallAge) || age < 0 || age > 10 || fabs(wallAge-age) > 1) return nil;
    if (IKConflictingRecordingIDs(s,raw) || (IKIndex(index) && IKIndex(s[@"queueIndex"]) && ![s[@"queueIndex"] isEqual:index])) return nil;
    NSDictionary *base = IKTrackIdentity(s[@"externalID"],s[@"persistentID"],s[@"title"],s[@"artist"],
                                         [s[@"duration"] isKindOfClass:NSNumber.class] ? [s[@"duration"] doubleValue] : 0);
    double d = [raw[@"duration"] doubleValue], baselineDuration = [base[@"duration"] doubleValue];
    if (!base || (d > 0 && baselineDuration > 0 && fabs(d-baselineDuration) >= 1)) return nil;
    if (!(pairedSession && [s[@"playSession"] isEqual:pairedSession]) && !IKSameRecording(raw,base) &&
        ![s[@"observed"] isEqual:IKRawSignature(raw)]) return nil;
    NSMutableDictionary *canonical = [base mutableCopy];
    canonical[@"playSession"] = s[@"playSession"];
    return canonical;
}

NSString *IKFreshPlayerLyric(NSDictionary *snapshot, IKRecordingTracker *local, NSDictionary *raw) {
    NSString *line = IKLyricString(snapshot[@"carLyric"],512);
    if (!line) return nil;
    double change = [snapshot[@"lyricUptime"] isKindOfClass:NSNumber.class] ? [snapshot[@"lyricUptime"] doubleValue] : 0;
    if ([snapshot[@"observed"] isEqual:IKRawSignature(raw)] ||
        (change > 0 && change <= [snapshot[@"uptime"] doubleValue] && change >= local.lyricUpdatedAt)) return line;
    return nil;
}

NSString *IKDecodeLyricText(NSData *d) {
    if (!d.length || d.length > IKMaxLyricBytes) return nil;
    const uint8_t *bytes = d.bytes;
    if (d.length >= 2 && ((bytes[0]==0xff && bytes[1]==0xfe) || (bytes[0]==0xfe && bytes[1]==0xff)))
        return [[NSString alloc] initWithData:d encoding:NSUnicodeStringEncoding];
    if (d.length >= 4 && d.length % 2 == 0) {
        if (bytes[1] == 0 && (bytes[0] == '[' || bytes[0] == '<'))
            return [[NSString alloc] initWithData:d encoding:NSUTF16LittleEndianStringEncoding];
        if (bytes[0] == 0 && (bytes[1] == '[' || bytes[1] == '<'))
            return [[NSString alloc] initWithData:d encoding:NSUTF16BigEndianStringEncoding];
    }
    NSString *utf = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (utf) return utf;
    NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    return [[NSString alloc] initWithData:d encoding:gb];
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
        [cues addObject:@{@"start":@(start), @"end":@(end), @"text":IKLyricString(text, 2048) ?: @"",
                         @"clearAfter":@([item[@"clearAfter"] isEqual:@YES])}];
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
        if (![cue[@"text"] length]) continue;
        NSDictionary *next = i+1 < unique.count ? unique[i+1] : nil;
        BOOL clear = [cue[@"clearAfter"] boolValue] || (next && ![next[@"text"] length]);
        // Keep the completed fill across a short musical breath. An explicit empty cue ends it.
        double displayEnd = next && !clear && limit-end < 2.0 ? limit : end;
        [result addObject:@{@"text":cue[@"text"], @"start":@(start), @"end":@(end),
                            @"displayEnd":@(displayEnd), @"clearAfter":@(clear)}];
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
    if (!next) return NSNotFound;
    NSDictionary *line = lines[next-1];
    if (position >= [line[@"displayEnd"] ?: line[@"end"] doubleValue]) return NSNotFound;
    return next-1;
}

BOOL IKPlayerPosition(NSDictionary *sample, NSString *bundle, NSDictionary *track, BOOL playing,
                      double uptime, double wall, double *position, double *rate) {
    if (!sample || ![sample[@"bundleID"] isEqual:bundle] || !IKSameRecording(sample,track)) return NO;
    if (sample[@"playSession"] && track[@"playSession"] && ![sample[@"playSession"] isEqual:track[@"playSession"]]) return NO;
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
