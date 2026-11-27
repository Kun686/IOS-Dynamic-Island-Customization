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
static BOOL IKUpper(unichar c) { return c >= 'A' && c <= 'Z'; }
static BOOL IKLower(unichar c) { return c >= 'a' && c <= 'z'; }
static BOOL IKHex(unichar c) { return IKDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
static BOOL IKAlnum(unichar c) { return IKDigit(c) || IKUpper(c) || IKLower(c); }

typedef NS_ENUM(NSInteger, IKRedactMode) {
    IKRedactDirectory,  // words outside the vocabulary become <word>
    IKRedactStem,       // file names: words survive only next to a lyric keyword
    IKRedactExtension,  // short format names survive
    IKRedactImage,      // paths inside the app bundle carry no user data: only numbers and IDs are replaced
};

// Words that occur in fixed directory and file names of iOS apps. Lowercase.
static NSSet<NSString *> *IKVocabulary(void) {
    static NSSet *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        words = [NSSet setWithArray:[@"documents library caches cache cached tmp temp temporary preferences preference application applications "
            "app apps support saved state splash board snapshot snapshots http https storage storages store stores web webkit kit cookie cookies "
            "fs data database databases db sqlite sqlite3 realm mmkv kv plist json xml txt bin dat raw file files folder dir dirs directory inbox "
            "synced sync download downloads downloaded downloading upload uploads offline online local remote cloud song songs audio audios media "
            "track tracks album albums artist artists playlist playlists play player playing playback queue lyric lyrics trans translate translation "
            "translated roma romaji image images img imgs pic pics picture pictures photo photos cover covers thumb thumbs thumbnail thumbnails video "
            "videos mv log logs crash crashes report reports config configs configuration setting settings user users account accounts profile "
            "profiles common shared share global default main index manifest meta metadata info list lists version versions backup backups value "
            "values resource resources res asset assets bundle bundles plugin plugins module modules html js css font fonts sound sounds effect "
            "effects voice radio podcast program programs comment comments search history recent favorite favorites like likes collect collection "
            "collections task tasks job jobs encrypt encrypted decrypt decrypted key keys cert certs framework frameworks lib libs core sdk api "
            "network request response session sessions url urls analytics stat stats statistics event events trace tracking ad ads launch boot new "
            "old test debug release vip quality lossless flac mp3 m4a aac ogg wav ape opus pcm mp4 hls m3u8 seg segment segments chunk chunks part "
            "parts piece pieces block blocks item items entry entries table tables dict array object objects model models manager center service "
            "services provider helper util utils tool tools parser decoder encoder loader reader writer handler view views controller page pages "
            "widget widgets extension extensions group groups container containers private public internal external system device devices code "
            "wal shm journal tencent qqmusic tme netease cloudmusic music apple com"
            componentsSeparatedByString:@" "]];
    });
    return words;
}

static NSString *const IKPlaceholders[] = {@"<num>", @"<hex>", @"<uuid>", @"<id>", @"<word>", @"<text>", @"<long>", @"<empty>"};

// A placeholder starting at `i`, so redacting a redacted name changes nothing.
static NSString *IKPlaceholderAt(const unichar *s, NSUInteger n, NSUInteger i) {
    for (NSUInteger k = 0; k < sizeof(IKPlaceholders) / sizeof(IKPlaceholders[0]); k++) {
        NSString *mark = IKPlaceholders[k];
        if (i + mark.length > n) continue;
        BOOL same = YES;
        for (NSUInteger m = 0; same && m < mark.length; m++) same = s[i + m] == [mark characterAtIndex:m];
        if (same) return mark;
    }
    return nil;
}

// 8-4-4-4-12 hex digits starting at `i`, not followed by another letter or digit.
static BOOL IKUUIDAt(const unichar *s, NSUInteger n, NSUInteger i) {
    if (i + 36 > n || (i + 36 < n && IKAlnum(s[i + 36]))) return NO;
    for (NSUInteger k = 0; k < 36; k++) {
        BOOL dash = k == 8 || k == 13 || k == 18 || k == 23;
        if (dash ? s[i + k] != '-' : !IKHex(s[i + k])) return NO;
    }
    return YES;
}

static BOOL IKKeepWord(NSString *word, IKRedactMode mode, BOOL keywordStem) {
    if (mode == IKRedactImage || IKEvidenceKeyword(word)) return YES;
    BOOL known = [IKVocabulary() containsObject:word.lowercaseString];
    BOOL acronym = word.length <= 4 && IKUpper([word characterAtIndex:0]) && IKUpper([word characterAtIndex:word.length - 1]);
    switch (mode) {
        case IKRedactDirectory: return known || word.length <= 2 || acronym;
        case IKRedactStem: return word.length == 1 || (keywordStem && (known || word.length <= 2));
        case IKRedactExtension: return known || word.length <= 4;
        default: return YES;
    }
}

// One run of letters and digits, split into words: "QQLyricCache2x" is QQ, Lyric, Cache, 2, x.
static void IKAppendRun(NSMutableString *out, const unichar *s, NSUInteger i, NSUInteger end, IKRedactMode mode, BOOL keywordStem) {
    BOOL masked = NO;
    while (i < end) {
        NSUInteger j = i + 1;
        if (IKDigit(s[i])) {
            while (j < end && IKDigit(s[j])) j++;
        } else if (IKUpper(s[i]) && j < end && IKUpper(s[j])) {
            while (j < end && IKUpper(s[j])) j++;
            if (j < end && IKLower(s[j])) j--;  // the last capital starts the next word
        } else {
            while (j < end && IKLower(s[j])) j++;
        }
        NSString *word = [NSString stringWithCharacters:s + i length:j - i];
        if (IKDigit(s[i])) {
            [out appendString:word.length >= 5 ? @"<num>" : word];
            masked = NO;
        } else if (IKKeepWord(word, mode, keywordStem)) {
            [out appendString:word];
            masked = NO;
        } else if (!masked) {
            [out appendString:@"<word>"];
            masked = YES;
        }
        i = j;
    }
}

static NSString *IKRedact(NSString *segment, IKRedactMode mode, NSSet<NSString *> *fixed, NSMutableArray<NSString *> *masked) {
    if (![segment isKindOfClass:NSString.class] || !segment.length) return @"<empty>";
    NSUInteger n = segment.length;
    if (n > 64) return @"<long>";
    unichar s[64];
    [segment getCharacters:s range:NSMakeRange(0, n)];
    for (NSUInteger i = 0; i < n; i++)
        if (s[i] < 0x20 || s[i] > 0x7e || s[i] == '@' || (s[i] == ' ' && mode != IKRedactDirectory)) return @"<text>";
    BOOL keywordStem = mode == IKRedactStem && IKEvidenceKeyword(segment);
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0;
    while (i < n) {
        NSString *mark = s[i] == '<' ? IKPlaceholderAt(s, n, i) : nil;
        if (mark) { [out appendString:mark]; i += mark.length; continue; }
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
            NSString *run = [NSString stringWithCharacters:s + i length:length];
            if (mode == IKRedactDirectory && [fixed containsObject:run]) {
                [out appendString:run];
            } else {
                NSUInteger before = out.length;
                IKAppendRun(out, s, i, j, mode, keywordStem);
                if (masked && [[out substringFromIndex:before] containsString:@"<word>"]) [masked addObject:run];
            }
        }
        i = j;
    }
    return out;
}

NSString *IKRedactPathSegment(NSString *segment) { return IKRedact(segment, IKRedactDirectory, nil, nil); }
NSString *IKRedactImageSegment(NSString *segment) { return IKRedact(segment, IKRedactImage, nil, nil); }
NSString *IKRedactPathSegmentKeeping(NSString *segment, NSSet<NSString *> *fixed) {
    return IKRedact(segment, IKRedactDirectory, [fixed isKindOfClass:NSSet.class] ? fixed : nil, nil);
}

NSArray<NSString *> *IKMaskedRuns(NSString *segment) {
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    IKRedact(segment, IKRedactDirectory, nil, runs);
    return runs;
}

static BOOL IKNameText(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 64) return NO;
    BOOL letter = NO;
    for (NSUInteger i = 0; i < [value length]; i++) {
        unichar c = [value characterAtIndex:i];
        if (!IKAlnum(c)) return NO;
        letter |= !IKDigit(c);
    }
    return letter;
}

NSSet<NSString *> *IKProbeConfirmedNames(NSDictionary *p, NSString *bundle) {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    if (![p isKindOfClass:NSDictionary.class] || ![p[@"schema"] isEqual:@1] || ![bundle isKindOfClass:NSString.class] ||
        ![p[@"bundleID"] isKindOfClass:NSString.class] || [p[@"bundleID"] caseInsensitiveCompare:bundle] != NSOrderedSame ||
        ![p[@"names"] isKindOfClass:NSArray.class]) return names;
    for (id name in p[@"names"]) {
        if (names.count >= 2000) break;
        if (IKNameText(name)) [names addObject:name];
    }
    return names;
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
            ext = IKRedact(tail.lowercaseString, IKRedactExtension, nil, nil);
            stem = [name substringToIndex:dot.location];
        }
    }
    NSString *shown = IKRedact(stem, IKRedactStem, nil, nil);
    if (extension) *extension = ext;
    return ext.length ? [NSString stringWithFormat:@"%@.%@", shown, ext] : shown;
}

// Image paths read back from the probe's file. Each segment must already be in redacted form.
static BOOL IKImagePathText(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 240) return NO;
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@"/"];
    if (parts.count > 8) return NO;
    for (NSString *part in parts)
        if (!part.length || ![IKRedact(part, IKRedactImage, nil, nil) isEqual:part]) return NO;
    return YES;
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

// Type encodings: printable ASCII without spaces.
static BOOL IKPrintable(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class] || [value length] > limit + 1) return NO;
    NSUInteger n = [value length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [value characterAtIndex:i];
        if (c <= 0x20 || c > 0x7e) return NO;
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
        if (!IKSymbolText(name, limits.symbol) || !IKPrintable(type, limits.type)) { (*invalid)++; continue; }
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
        if (![image isKindOfClass:NSArray.class] || image.count != 3 || !IKImagePathText(image[0])) { invalid++; continue; }
        [lines addObject:[NSString stringWithFormat:@"image %@ classNames=%lu matched=%lu", image[0],
            (unsigned long)IKCount(image[1], 100000000), (unsigned long)IKCount(image[2], 100000000)]];
    }
    NSUInteger detailed = 0;
    for (NSDictionary *c in IKList(p[@"classes"], limits.classes)) {
        if (![c isKindOfClass:NSDictionary.class] || !IKSymbolText(c[@"name"], limits.symbol) || !IKImagePathText(c[@"image"])) {
            invalid++;
            continue;
        }
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
    if (![marker isKindOfClass:NSDictionary.class] || ![bundle isKindOfClass:NSString.class] ||
        (![marker[@"attempts"] isKindOfClass:NSDictionary.class] && ![marker[@"attempts"] isKindOfClass:NSNumber.class])) return nil;
    id raw = marker[@"attempts"];
    // The first format kept one count for both triggers; the probe applies it to both.
    NSDictionary *counts = [raw isKindOfClass:NSNumber.class] ? @{@"launch": raw, @"playback": raw} : raw;
    NSMutableArray<NSString *> *parts = [NSMutableArray array], *stopped = [NSMutableArray array];
    for (NSString *trigger in @[@"launch", @"playback"]) {
        NSUInteger attempts = IKCount(counts[trigger], 99);
        if (!attempts) continue;
        [parts addObject:[NSString stringWithFormat:@"%@=%lu", trigger, (unsigned long)attempts]];
        if (attempts >= 2) [stopped addObject:trigger];
    }
    if (!parts.count) return nil;
    NSString *note = stopped.count ? [NSString stringWithFormat:@" (%@ sampling stopped for this version)", [stopped componentsJoinedByString:@"+"]] : @"";
    return [NSString stringWithFormat:@"lyric probe app=%@ version=%@ class sampling unfinished %@%@", bundle,
            IKPlayerVersion(marker[@"version"]), [parts componentsJoinedByString:@" "], note];
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

// The HUD sees the player's dictionary, possibly after several quick calls were merged. So the two sides match on
// the state after the change, not on which fields changed: the three text lengths, the duration and, when both
// recorded one, the position. Positions come from the same published dictionary and are compared to 10 ms.
static BOOL IKSameState(NSArray<NSNumber *> *p, NSArray<NSNumber *> *h, BOOL position) {
    for (NSUInteger i = 5; i < 8; i++)
        if (p[i].unsignedIntegerValue != h[i].unsignedIntegerValue) return NO;
    if (fabs(p[3].doubleValue - h[3].doubleValue) > 0.5) return NO;
    if (position && p[1].doubleValue >= 0 && h[1].doubleValue >= 0 && fabs(p[1].doubleValue - h[1].doubleValue) > 0.01) return NO;
    return YES;
}

typedef struct {
    NSUInteger positionMatched;  // both sides recorded the same position
    NSUInteger positionMissing;  // at least one side recorded no position
    NSUInteger positionIgnored;  // found only after ignoring a position that differed
    NSUInteger ambiguous, unmatched;
} IKPairCounts;

// Whether player call k can be the state the HUD saw with change mask `mask`. With a known `base` (the call the
// HUD's previous observation showed), the fields changed by calls base+1...k together must be exactly the fields
// the HUD saw change. Without a base, call k's own changes must be among them. The probe's first call has no real mask.
static BOOL IKMaskFits(NSArray<NSArray<NSNumber *> *> *sent, NSUInteger base, NSUInteger k, NSUInteger mask) {
    if (sent[k][8].unsignedIntegerValue & 1) return YES;
    if (base == NSNotFound || base >= k) return (sent[k][4].unsignedIntegerValue & ~mask) == 0;
    NSUInteger changed = 0;
    for (NSUInteger i = base + 1; i <= k; i++) changed |= sent[i][4].unsignedIntegerValue;
    return changed == mask;
}

// Pairs each HUD change with the one player call in the ten seconds before it that left the same state and
// changed the same fields. Several candidates cannot be told apart and are counted as ambiguous instead of
// guessed. Pairs keep their order: a later HUD change never pairs with a player call before the previous pair.
// Each change is tried with positions first and, only when that finds nothing, once more without them.
static NSArray<NSNumber *> *IKPairEvents(NSArray<NSArray<NSNumber *> *> *sent, NSArray<NSArray<NSNumber *> *> *seen, IKPairCounts *counts) {
    NSMutableArray<NSNumber *> *deltas = [NSMutableArray array];
    *counts = (IKPairCounts){0};
    NSUInteger floor = 0, base = NSNotFound;
    for (NSArray<NSNumber *> *h in seen) {
        double at = h[0].doubleValue;
        if (h[8].unsignedIntegerValue & 1) {
            // The HUD's first observation is no delivery to time, but it shows a known state: one of the last two
            // player calls before it. It anchors the masks of the changes that follow.
            base = NSNotFound;
            NSUInteger tried = 0;
            for (NSUInteger k = sent.count; k-- > 0 && tried < 2;) {
                if (sent[k][0].doubleValue > at) continue;
                tried++;
                if (IKSameState(sent[k], h, YES)) { base = k; break; }
            }
            if (base != NSNotFound) floor = MAX(floor, base + 1);
            continue;
        }
        NSUInteger found = NSNotFound, candidates = 0;
        BOOL withPosition = YES;
        for (int pass = 0; pass < 2 && !candidates; pass++) {
            withPosition = pass == 0;
            for (NSUInteger k = floor; k < sent.count && sent[k][0].doubleValue <= at; k++) {
                if (sent[k][0].doubleValue < at - 10 || !IKSameState(sent[k], h, withPosition) || !IKMaskFits(sent, base, k, h[4].unsignedIntegerValue)) continue;
                candidates++;
                found = k;
            }
        }
        if (candidates == 1) {
            [deltas addObject:@(at - sent[found][0].doubleValue)];
            BOOL bothPositions = sent[found][1].doubleValue >= 0 && h[1].doubleValue >= 0;
            if (!withPosition) counts->positionIgnored++;
            else if (bothPositions) counts->positionMatched++;
            else counts->positionMissing++;
            floor = found + 1;
            base = found;
        } else {
            if (candidates) counts->ambiguous++;
            else counts->unmatched++;
            base = NSNotFound;
        }
    }
    return deltas;
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
    IKPairCounts counts;
    NSArray<NSNumber *> *deltas = IKPairEvents(sent, seen, &counts);
    if (!deltas.count) {
        [lines addObject:[NSString stringWithFormat:@"lyric latency app=%@ paired=0 ambiguous=%lu unmatched=%lu reason=%@", bundle,
            (unsigned long)counts.ambiguous, (unsigned long)counts.unmatched, counts.ambiguous ? @"ambiguous" : @"no-overlap"]];
        return [lines componentsJoinedByString:@"\n"];
    }
    deltas = [deltas sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger n = deltas.count;
    [lines addObject:[NSString stringWithFormat:
        @"lyric latency app=%@ paired=%lu positionMatched=%lu positionMissing=%lu positionIgnored=%lu ambiguous=%lu unmatched=%lu player=%lu hud=%lu "
         "min=%.3f median=%.3f p90=%.3f max=%.3f (seconds, HUD seen minus player set)",
        bundle, (unsigned long)n, (unsigned long)counts.positionMatched, (unsigned long)counts.positionMissing, (unsigned long)counts.positionIgnored,
        (unsigned long)counts.ambiguous, (unsigned long)counts.unmatched, (unsigned long)sent.count, (unsigned long)seen.count,
        deltas[0].doubleValue, deltas[n / 2].doubleValue, deltas[MIN(n - 1, (n * 9) / 10)].doubleValue, deltas[n - 1].doubleValue]];
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
