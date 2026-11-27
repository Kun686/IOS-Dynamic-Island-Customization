#import "IKLyricEvidence.h"
#import "IKPlaybackDiagnostic.h"

BOOL IKProbeSupportedBundle(NSString *bundle) {
    if (![bundle isKindOfClass:NSString.class]) return NO;
    return [@[@"com.tencent.qqmusic", @"com.netease.cloudmusic"] containsObject:bundle.lowercaseString];
}

BOOL IKEvidenceKeyword(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length || name.length > 1024) return NO;
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"lyric"]) return YES;
    lower = [lower stringByReplacingOccurrencesOfString:@"qrcode" withString:@"|"];
    for (NSString *key in @[@"lrc", @"qrc", @"yrc", @"krc"])
        if ([lower containsString:key]) return YES;
    return NO;
}

NSInteger IKEvidenceClassRank(NSString *name) {
    if (!IKEvidenceKeyword(name)) return -1;
    NSString *plain = [name stringByReplacingOccurrencesOfString:@"ViewModel" withString:@""];
    for (NSString *part in @[@"View", @"Cell", @"Button", @"Label", @"Layer"])
        if ([plain containsString:part]) return 1;
    return 0;
}

#pragma mark - Redaction

static BOOL IKDigit(unichar c) { return c >= '0' && c <= '9'; }
static BOOL IKHex(unichar c) { return IKDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
static BOOL IKAlnum(unichar c) { return IKDigit(c) || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }

// 8-4-4-4-12 hex digits starting at `i`, not followed by another letter or digit.
static BOOL IKUUIDAt(const unichar *s, NSUInteger n, NSUInteger i) {
    if (i + 36 > n || (i + 36 < n && IKAlnum(s[i + 36]))) return NO;
    for (NSUInteger k = 0; k < 36; k++) {
        BOOL dash = k == 8 || k == 13 || k == 18 || k == 23;
        if (dash ? s[i + k] != '-' : !IKHex(s[i + k])) return NO;
    }
    return YES;
}

NSString *IKRedactPathSegment(NSString *segment) {
    if (![segment isKindOfClass:NSString.class] || !segment.length) return @"<empty>";
    NSUInteger n = segment.length;
    if (n > 64) return @"<long>";
    unichar s[64];
    [segment getCharacters:s range:NSMakeRange(0, n)];
    for (NSUInteger i = 0; i < n; i++)
        if (s[i] < 0x20 || s[i] > 0x7e) return @"<text>";
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0;
    while (i < n) {
        if (!IKAlnum(s[i])) { [out appendFormat:@"%C", s[i++]]; continue; }
        if (IKUUIDAt(s, n, i)) { [out appendString:@"<uuid>"]; i += 36; continue; }
        NSUInteger j = i, digits = 0;
        BOOL hex = YES;
        for (; j < n && IKAlnum(s[j]); j++) {
            if (IKDigit(s[j])) digits++;
            if (!IKHex(s[j])) hex = NO;
        }
        NSUInteger length = j - i;
        if (digits == length) [out appendString:@"<num>"];
        else if (hex && length >= 8 && (digits || length >= 16)) [out appendString:@"<hex>"];
        else if (length >= 20 && digits >= 4) [out appendString:@"<id>"];
        else {
            // Keep the words. A run of five or more digits inside them may be an account or track number.
            for (NSUInteger k = i; k < j;) {
                NSUInteger run = k;
                while (run < j && IKDigit(s[run])) run++;
                if (run - k >= 5) { [out appendString:@"<num>"]; k = run; continue; }
                if (run == k) run++;
                [out appendString:[NSString stringWithCharacters:s + k length:run - k]];
                k = run;
            }
        }
        i = j;
    }
    return out;
}

NSString *IKRedactFileName(NSString *name, NSString **extension) {
    if (extension) *extension = @"";
    if (![name isKindOfClass:NSString.class] || !name.length) return @"<empty>";
    NSString *stem = name, *ext = @"";
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound && dot.location > 0 && dot.location + 1 < name.length && name.length - dot.location - 1 <= 12) {
        NSString *tail = [name substringFromIndex:dot.location + 1];
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
        if ([tail rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) {
            ext = IKRedactPathSegment(tail.lowercaseString);
            stem = [name substringToIndex:dot.location];
        }
    }
    // A fixed file name does not contain spaces. A title does.
    NSString *shown = [stem containsString:@" "] ? @"<text>" : IKRedactPathSegment(stem);
    if (extension) *extension = ext;
    return ext.length ? [NSString stringWithFormat:@"%@.%@", shown, ext] : shown;
}

#pragma mark - Class inventory text

IKProbeLimits IKProbeDefaultLimits(void) {
    return (IKProbeLimits){.classes = 600, .names = 1500, .members = 300, .symbol = 160, .type = 200,
                           .images = 256, .budget = 640 * 1024};
}

NSString *IKEvidenceSymbol(const char *name, NSUInteger limit) {
    if (!name || !*name) return @"<text>";
    NSUInteger length = 0;
    for (; name[length]; length++) {
        unsigned char c = (unsigned char)name[length];
        if (!IKAlnum(c) && c != '_' && c != '.' && c != '$' && c != ':') return @"<text>";
        if (length == limit) break;
    }
    NSString *kept = [[NSString alloc] initWithBytes:name length:MIN(length, limit) encoding:NSASCIIStringEncoding];
    if (!kept) return @"<text>";
    return name[length] ? [kept stringByAppendingString:@"~"] : kept;
}

NSString *IKEvidenceType(const char *encoding, NSUInteger limit) {
    if (!encoding) return @"";
    NSUInteger length = 0;
    for (; encoding[length]; length++) {
        unsigned char c = (unsigned char)encoding[length];
        if (c < 0x20 || c > 0x7e) return @"?";
        if (length == limit) break;
    }
    NSString *kept = [[NSString alloc] initWithBytes:encoding length:MIN(length, limit) encoding:NSASCIIStringEncoding];
    if (!kept) return @"?";
    // Spaces only occur inside C++ template names. Members are stored as "name type", so the type has none.
    kept = [kept stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    return encoding[length] ? [kept stringByAppendingString:@"~"] : kept;
}

// What IKEvidenceSymbol can have produced.
static BOOL IKSymbolText(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > limit + 1) return NO;
    if ([value isEqual:@"<text>"]) return YES;
    NSUInteger n = [value length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [value characterAtIndex:i];
        if (!IKAlnum(c) && c != '_' && c != '.' && c != '$' && c != ':' && !(c == '~' && i + 1 == n)) return NO;
    }
    return YES;
}

static BOOL IKPrintable(id value, NSUInteger limit, BOOL spaces) {
    if (![value isKindOfClass:NSString.class] || [value length] > limit + 1) return NO;
    NSUInteger n = [value length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [value characterAtIndex:i];
        if (c < 0x20 || c > 0x7e || (c == ' ' && !spaces)) return NO;
    }
    return YES;
}

static NSUInteger IKCount(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSNumber.class]) return 0;
    double n = [value doubleValue];
    return isfinite(n) && n > 0 ? (NSUInteger)MIN(n, (double)limit) : 0;
}

static NSArray *IKList(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    return [value count] > limit ? [value subarrayWithRange:NSMakeRange(0, limit)] : value;
}

static NSString *IKCaptured(id wall) {
    double stamp = [wall isKindOfClass:NSNumber.class] ? [wall doubleValue] : 0;
    if (!isfinite(stamp) || stamp <= 0 || stamp > 1e11) return @"?";
    return [[NSISO8601DateFormatter new] stringFromDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
}

// Members are stored as "name" or "name type".
static void IKAppendMembers(NSMutableArray<NSString *> *lines, id list, NSString *mark, IKProbeLimits limits, NSUInteger *invalid) {
    for (id item in IKList(list, limits.members)) {
        if (![item isKindOfClass:NSString.class]) { (*invalid)++; continue; }
        NSRange space = [item rangeOfString:@" "];
        NSString *name = space.location == NSNotFound ? item : [item substringToIndex:space.location];
        NSString *type = space.location == NSNotFound ? @"" : [item substringFromIndex:space.location + 1];
        if (!IKSymbolText(name, limits.symbol) || !IKPrintable(type, limits.type, NO)) { (*invalid)++; continue; }
        [lines addObject:type.length ? [NSString stringWithFormat:@"  %@ %@ %@", mark, name, type]
                                     : [NSString stringWithFormat:@"  %@ %@", mark, name]];
    }
}

NSString *IKClassInventoryReport(NSDictionary *p, NSString *bundle) {
    if (![p isKindOfClass:NSDictionary.class] || ![p[@"schema"] isEqual:@1] || ![p[@"bundleID"] isKindOfClass:NSString.class] ||
        ![bundle isKindOfClass:NSString.class] || [p[@"bundleID"] caseInsensitiveCompare:bundle] != NSOrderedSame) return nil;
    IKProbeLimits limits = IKProbeDefaultLimits();
    NSUInteger invalid = 0;
    NSMutableArray<NSString *> *samples = [NSMutableArray array], *lines = [NSMutableArray array];
    for (NSDictionary *s in IKList(p[@"samples"], 4)) {
        if (![s isKindOfClass:NSDictionary.class] || ![@[@"launch", @"playback"] containsObject:s[@"trigger"] ?: @""]) { invalid++; continue; }
        [samples addObject:[NSString stringWithFormat:@"%@ uptime=%.1f images=%lu classNames=%lu matched=%lu", s[@"trigger"],
            (double)IKCount(s[@"uptime"], 1000000000), (unsigned long)IKCount(s[@"images"], 100000),
            (unsigned long)IKCount(s[@"classNames"], 100000000), (unsigned long)IKCount(s[@"matched"], 100000000)]];
    }
    for (NSArray *image in IKList(p[@"images"], limits.images)) {
        if (![image isKindOfClass:NSArray.class] || image.count != 3 || !IKPrintable(image[0], 240, YES) || ![image[0] length]) { invalid++; continue; }
        [lines addObject:[NSString stringWithFormat:@"image %@ classNames=%lu matched=%lu", image[0],
            (unsigned long)IKCount(image[1], 100000000), (unsigned long)IKCount(image[2], 100000000)]];
    }
    NSUInteger detailed = 0;
    for (NSDictionary *c in IKList(p[@"classes"], limits.classes)) {
        if (![c isKindOfClass:NSDictionary.class] || !IKSymbolText(c[@"name"], limits.symbol) ||
            !IKPrintable(c[@"image"], 240, YES)) { invalid++; continue; }
        NSString *parent = IKSymbolText(c[@"super"], limits.symbol) ? c[@"super"] : @"-";
        NSArray *counts = IKList(c[@"counts"], 4);
        NSMutableArray *totals = [NSMutableArray array];
        for (NSUInteger i = 0; i < 4; i++) [totals addObject:@(i < counts.count ? IKCount(counts[i], 1000000) : 0)];
        detailed++;
        [lines addObject:[NSString stringWithFormat:@"class %@ : %@ image=%@ instanceMethods=%@ classMethods=%@ properties=%@ ivars=%@%@",
            c[@"name"], parent, c[@"image"], totals[0], totals[1], totals[2], totals[3], [c[@"late"] isEqual:@YES] ? @" late" : @""]];
        IKAppendMembers(lines, c[@"im"], @"-", limits, &invalid);
        IKAppendMembers(lines, c[@"cm"], @"+", limits, &invalid);
        IKAppendMembers(lines, c[@"props"], @"@", limits, &invalid);
        IKAppendMembers(lines, c[@"ivars"], @".", limits, &invalid);
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id name in IKList(p[@"names"], limits.names)) {
        if (IKSymbolText(name, limits.symbol)) [names addObject:name];
        else invalid++;
    }
    for (NSUInteger i = 0; i < names.count; i += 6)
        [lines addObject:[@"class names only: " stringByAppendingString:
            [[names subarrayWithRange:NSMakeRange(i, MIN(6, names.count - i))] componentsJoinedByString:@" "]]];
    NSString *head = [NSString stringWithFormat:
        @"lyric probe app=%@ version=%@ captured=%@ samples=[%@] appImages=%lu detailed=%lu namesOnly=%lu dropped=%lu budgetLimited=%d invalid=%lu",
        bundle, IKPlayerVersion(p[@"version"]), IKCaptured(p[@"wall"]), [samples componentsJoinedByString:@"; "],
        (unsigned long)IKCount(p[@"appImages"], 100000), (unsigned long)detailed, (unsigned long)names.count,
        (unsigned long)IKCount(p[@"dropped"], 100000000), [p[@"budgetLimited"] isEqual:@YES], (unsigned long)invalid];
    [lines insertObject:head atIndex:0];
    return [lines componentsJoinedByString:@"\n"];
}

NSString *IKProbeGuardReport(NSDictionary *marker, NSString *bundle) {
    if (![marker isKindOfClass:NSDictionary.class] || ![bundle isKindOfClass:NSString.class]) return nil;
    NSUInteger attempts = IKCount(marker[@"attempts"], 99);
    if (!attempts) return nil;
    return [NSString stringWithFormat:@"lyric probe app=%@ version=%@ class sampling unfinished attempts=%lu%@", bundle,
            IKPlayerVersion(marker[@"version"]), (unsigned long)attempts, attempts >= 2 ? @" (stopped retrying for this version)" : @""];
}

#pragma mark - Field change events

NSString *IKEvidenceText(id value) {
    return [value isKindOfClass:NSString.class] && [value length] && [value length] <= IKEvidenceMaxTextLength ? [value copy] : nil;
}

static double IKFinite(id value, double low, double high, double fallback) {
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    double n = [value doubleValue];
    return isfinite(n) && n >= low && n <= high ? n : fallback;
}

@implementation IKLyricEventLog {
    NSString *_bundle, *_side;
    NSArray<NSString *> *_last;
    NSMutableArray<NSArray<NSNumber *> *> *_events;
    double _duration;
    NSUInteger _total;
}

- (instancetype)initWithBundle:(NSString *)bundle side:(NSString *)side {
    if ((self = [super init])) {
        _bundle = [bundle copy] ?: @"";
        _side = [side copy] ?: @"";
        _events = [NSMutableArray array];
    }
    return self;
}

- (NSUInteger)count { return _events.count; }

- (BOOL)observeTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album
            duration:(NSNumber *)duration elapsed:(NSNumber *)elapsed rate:(NSNumber *)rate uptime:(double)uptime {
    NSArray<NSString *> *fields = @[IKEvidenceText(title) ?: @"", IKEvidenceText(artist) ?: @"", IKEvidenceText(album) ?: @""];
    NSUInteger mask = 0;
    for (NSUInteger i = 0; i < 3; i++)
        if (![fields[i] isEqual:_last ? _last[i] : @""]) mask |= 1u << i;
    double length = IKFinite(duration, 0, 1e6, 0);
    NSUInteger flags = !_total ? 1 : (fabs(length - _duration) > 1 ? 2 : 0);
    _last = fields;
    _duration = length;
    if (!mask || !isfinite(uptime) || uptime < 0) return NO;
    // Positions and lengths only. The compared texts stay in `_last`.
    [_events addObject:@[@(uptime), @(IKFinite(elapsed, 0, 1e6, -1)), @(IKFinite(rate, 0, 64, -1)), @(length), @(mask),
                         @(fields[0].length), @(fields[1].length), @(fields[2].length), @(flags)]];
    if (_events.count > IKEvidenceMaxEvents) [_events removeObjectAtIndex:0];
    _total++;
    return YES;
}

- (NSDictionary *)snapshotAtUptime:(double)uptime wall:(double)wall {
    return @{@"schema": @1, @"bundleID": _bundle, @"side": _side, @"uptime": @(uptime), @"wall": @(wall),
             @"total": @(_total), @"events": [_events copy]};
}

- (BOOL)writeTo:(NSURL *)file {
    if (!file.isFileURL) return NO;
    NSDictionary *packet = [self snapshotAtUptime:NSProcessInfo.processInfo.systemUptime wall:NSDate.date.timeIntervalSince1970];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:packet format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!data.length || ![NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent
                                              withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    return [data writeToURL:file options:NSDataWritingAtomic error:nil];
}
@end

static NSArray<NSArray<NSNumber *> *> *IKValidEvents(NSDictionary *p, NSString *bundle, NSString *side) {
    if (![p isKindOfClass:NSDictionary.class] || ![p[@"schema"] isEqual:@1] || ![p[@"side"] isEqual:side] ||
        ![p[@"bundleID"] isKindOfClass:NSString.class] || [p[@"bundleID"] caseInsensitiveCompare:bundle] != NSOrderedSame ||
        ![p[@"events"] isKindOfClass:NSArray.class]) return nil;
    NSArray *events = p[@"events"];
    if (events.count > IKEvidenceMaxEvents)
        events = [events subarrayWithRange:NSMakeRange(events.count - IKEvidenceMaxEvents, IKEvidenceMaxEvents)];
    static const double low[9] = {0, -1, -1, 0, 1, 0, 0, 0, 0};
    static const double high[9] = {1e9, 1e6, 64, 1e6, 7, IKEvidenceMaxTextLength, IKEvidenceMaxTextLength, IKEvidenceMaxTextLength, 3};
    NSMutableArray *valid = [NSMutableArray array];
    for (NSArray *e in events) {
        BOOL ok = [e isKindOfClass:NSArray.class] && e.count == 9;
        for (NSUInteger i = 0; ok && i < 9; i++) ok = isfinite(IKFinite(e[i], low[i], high[i], NAN));
        if (ok) [valid addObject:e];
    }
    [valid sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    return valid;
}

static NSString *IKEventLine(NSArray<NSNumber *> *e) {
    NSUInteger mask = e[4].unsignedIntegerValue, flags = e[8].unsignedIntegerValue;
    NSMutableArray *names = [NSMutableArray array], *lengths = [NSMutableArray array];
    NSArray *fields = @[@"title", @"artist", @"album"];
    for (NSUInteger i = 0; i < 3; i++) {
        if (!(mask & (1u << i))) continue;
        [names addObject:fields[i]];
        [lengths addObject:[NSString stringWithFormat:@"%lu", (unsigned long)e[5 + i].unsignedIntegerValue]];
    }
    NSString *position = e[1].doubleValue < 0 ? @"-" : [NSString stringWithFormat:@"%.2f", e[1].doubleValue];
    NSString *rate = e[2].doubleValue < 0 ? @"-" : [NSString stringWithFormat:@"%.2f", e[2].doubleValue];
    return [NSString stringWithFormat:@"  t=%.3f pos=%@ rate=%@ dur=%.1f changed=%@ len=%@%@", e[0].doubleValue, position, rate,
            e[3].doubleValue, [names componentsJoinedByString:@"+"], [lengths componentsJoinedByString:@"+"],
            flags & 1 ? @" first" : (flags & 2 ? @" newDuration" : @"")];
}

// Both sides saw the same change when a field changed on both and has the same length.
static BOOL IKSameChange(NSArray<NSNumber *> *a, NSArray<NSNumber *> *b) {
    NSUInteger shared = a[4].unsignedIntegerValue & b[4].unsignedIntegerValue;
    for (NSUInteger i = 0; i < 3; i++)
        if ((shared & (1u << i)) && [a[5 + i] isEqual:b[5 + i]]) return YES;
    return NO;
}

static double IKBoot(NSDictionary *p) {
    double wall = IKFinite(p[@"wall"], 1, 1e11, NAN), uptime = IKFinite(p[@"uptime"], 0, 1e9, NAN);
    return wall - uptime;
}

NSString *IKLyricEventsReport(NSDictionary *player, NSDictionary *hud, NSString *bundle) {
    if (![bundle isKindOfClass:NSString.class]) return nil;
    NSArray<NSArray<NSNumber *> *> *sent = IKValidEvents(player, bundle, @"player"), *seen = IKValidEvents(hud, bundle, @"hud");
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSArray *sides = @[@[@"player", sent ?: NSNull.null, player ?: @{}], @[@"hud", seen ?: NSNull.null, hud ?: @{}]];
    for (NSArray *side in sides) {
        if (side[1] == NSNull.null) {
            [lines addObject:[NSString stringWithFormat:@"lyric events app=%@ side=%@ absent", bundle, side[0]]];
            continue;
        }
        NSArray *events = side[1];
        [lines addObject:[NSString stringWithFormat:@"lyric events app=%@ side=%@ captured=%@ kept=%lu total=%lu", bundle, side[0],
            IKCaptured(side[2][@"wall"]), (unsigned long)events.count, (unsigned long)IKCount(side[2][@"total"], 1000000000)]];
        for (NSArray *e in events) [lines addObject:IKEventLine(e)];
    }
    NSString *reason = !sent.count ? @"no-player-events" : !seen.count ? @"no-hud-events" : nil;
    double drift = IKBoot(player) - IKBoot(hud);
    if (!reason && !(fabs(drift) <= 5)) reason = @"different-boot";
    if (reason) {
        [lines addObject:[NSString stringWithFormat:@"lyric latency app=%@ paired=0 reason=%@", bundle, reason]];
        return [lines componentsJoinedByString:@"\n"];
    }
    // Keep the order: a change the HUD saw pairs with the first unpaired change the player set in the ten seconds before it.
    // Both sides read the same uptime clock, so the HUD is never earlier.
    NSMutableArray<NSNumber *> *deltas = [NSMutableArray array];
    NSUInteger next = 0;
    for (NSArray<NSNumber *> *h in seen) {
        if (h[8].unsignedIntegerValue & 1) continue;
        double at = h[0].doubleValue;
        while (next < sent.count && sent[next][0].doubleValue < at - 10) next++;
        for (NSUInteger k = next; k < sent.count && sent[k][0].doubleValue <= at; k++) {
            if ((sent[k][8].unsignedIntegerValue & 1) || !IKSameChange(sent[k], h)) continue;
            [deltas addObject:@(at - sent[k][0].doubleValue)];
            next = k + 1;
            break;
        }
    }
    if (!deltas.count) {
        [lines addObject:[NSString stringWithFormat:@"lyric latency app=%@ paired=0 reason=no-overlap", bundle]];
        return [lines componentsJoinedByString:@"\n"];
    }
    [deltas sortUsingSelector:@selector(compare:)];
    NSUInteger n = deltas.count;
    [lines addObject:[NSString stringWithFormat:
        @"lyric latency app=%@ paired=%lu player=%lu hud=%lu min=%.3f median=%.3f p90=%.3f max=%.3f (seconds, HUD seen minus player set)",
        bundle, (unsigned long)n, (unsigned long)sent.count, (unsigned long)seen.count, deltas[0].doubleValue,
        deltas[n / 2].doubleValue, deltas[MIN(n - 1, (n * 9) / 10)].doubleValue, deltas[n - 1].doubleValue]];
    return [lines componentsJoinedByString:@"\n"];
}

NSDictionary *IKReadEvidence(NSURL *file) {
    NSNumber *regular = nil, *size = nil;
    if (!file.isFileURL || ![file getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] || !regular.boolValue ||
        ![file getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > IKEvidenceMaxFileBytes) return nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:file error:nil];
    NSData *bytes = [handle readDataUpToLength:IKEvidenceMaxFileBytes + 1 error:nil];
    [handle closeAndReturnError:nil];
    if (!bytes.length || bytes.length > IKEvidenceMaxFileBytes) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable format:NULL error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
