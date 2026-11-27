// Runs the probe, the event log, the export text and the container scan on macOS against fixture classes and folders.
#import <MediaPlayer/MediaPlayer.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "IKLyricProbe.h"
#import "IKContainerScan.h"
#import "IKPlaybackDiagnostic.h"
#import <fcntl.h>
#import <sys/stat.h>

static int checks;
static void check(BOOL ok, const char *name) {
    if (!ok) { fprintf(stderr, "FAIL %s\n", name); exit(1); }
    checks++;
}

// Fixture classes in this executable. +initialize records any message sent to them.
static BOOL initialized;

@interface FixtureLyricStore : NSObject {
    NSArray *_lines;
    double _offsetMs;
}
@property(nonatomic, copy) NSString *currentLine;
@property(nonatomic) double startTime;
- (NSArray *)linesForSong:(id)song;
- (void)seekTo:(double)time animated:(BOOL)animated;
- (void)reload;
+ (instancetype)sharedStore;
@end
@implementation FixtureLyricStore
+ (void)initialize { initialized = YES; }
+ (instancetype)sharedStore { return nil; }
- (NSArray *)linesForSong:(id)song { return _lines; }
- (void)seekTo:(double)time animated:(BOOL)animated { _offsetMs = time; }
- (void)reload {}
@end

@interface FixtureKrcParser : FixtureLyricStore
@end
@implementation FixtureKrcParser
- (NSData *)decode:(NSData *)data { return data; }
@end

@interface FixtureLyricCell : NSObject
@end
@implementation FixtureLyricCell
@end

@interface FixtureLyricViewModel : NSObject
@end
@implementation FixtureLyricViewModel
@end

@interface FixtureQRCodeScanner : NSObject
@end
@implementation FixtureQRCodeScanner
@end

@interface FixturePlainModel : NSObject
@end
@implementation FixturePlainModel
@end

#define BULK(n) \
    @interface FixtureYrcBulk##n : NSObject \
    @end \
    @implementation FixtureYrcBulk##n \
    - (void)wordAt:(double)time {} \
    @end
BULK(0) BULK(1) BULK(2) BULK(3) BULK(4) BULK(5) BULK(6) BULK(7)

static NSDictionary *classNamed(NSDictionary *packet, NSString *name) {
    for (NSDictionary *c in packet[@"classes"])
        if ([c[@"name"] isEqual:name]) return c;
    return nil;
}

static BOOL holds(NSData *data, NSString *text) {
    for (NSNumber *encoding in @[@(NSUTF8StringEncoding), @(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding)]) {
        NSData *needle = [text dataUsingEncoding:encoding.unsignedIntegerValue];
        if (needle.length && [data rangeOfData:needle options:0 range:NSMakeRange(0, data.length)].location != NSNotFound) return YES;
    }
    return NO;
}

static void testKeywords(void) {
    for (NSString *name in @[@"QQLyricManager", @"lyricView", @"NELRCParser", @"QrcDecoder", @"YRCLine", @"KrcReader", @"song.qrc", @"LYRICS"])
        check(IKEvidenceKeyword(name), "keyword matches in any case");
    for (NSString *name in @[@"QRCodeScanner", @"PlayerController", @"", @"Lyri", @"qqmusic"])
        check(!IKEvidenceKeyword(name), "unrelated names and QRCode do not match");
    check(IKEvidenceKeyword(@"QRCodeLyricShare") && IKEvidenceKeyword(@"QRCodeForQrcFile"), "QRCode next to a real keyword still matches");
    check(!IKEvidenceKeyword((id)@7) && !IKEvidenceKeyword(nil), "non-strings do not match");
    check(IKEvidenceClassRank(@"QQLyricModel") == 0 && IKEvidenceClassRank(@"QQLyricViewModel") == 0, "data classes rank first");
    check(IKEvidenceClassRank(@"QQLyricView") == 1 && IKEvidenceClassRank(@"LyricCell") == 1 && IKEvidenceClassRank(@"LyricViewController") == 1,
          "view classes rank after data classes");
    check(IKEvidenceClassRank(@"QQPlayerModel") == -1, "no keyword has no rank");
    check(IKProbeSupportedBundle(@"com.tencent.QQMusic") && IKProbeSupportedBundle(@"com.netease.cloudmusic") &&
          IKProbeSupportedBundle(@"COM.TENCENT.QQMUSIC"), "both players are supported");
    check(!IKProbeSupportedBundle(@"com.apple.Music") && !IKProbeSupportedBundle(@"com.tencent.xin") && !IKProbeSupportedBundle(nil) &&
          !IKProbeSupportedBundle(@"com.tencent.QQMusic.widget"), "nothing else is");
}

static void testRedaction(void) {
    NSDictionary *segments = @{
        @"1234567890": @"<num>", @"2024": @"<num>", @"e10adc3949ba59abbe56e057f20f883e": @"<hex>", @"A1B2C3D4": @"<hex>",
        @"周杰伦": @"<text>", @"Lyric缓存": @"<text>", @"LyricCache": @"LyricCache", @"Application Support": @"Application Support",
        @"com.tencent.QQMusic": @"com.tencent.QQMusic", @"user_123456789": @"user_<num>", @"u123456789x": @"u<num>x",
        @"6F9619FF-8B86-D011-B42D-00C04FC964FF": @"<uuid>", @"cache-6f9619ff-8b86-d011-b42d-00c04fc964ff.tmp": @"cache-<uuid>.tmp",
        @"v2": @"v2", @"qrc_v3": @"qrc_v3", @"A1b2C3d4E5f6G7h8I9j0Kz": @"<id>", @"deadbeef": @"<word>",
        @"line\nbreak": @"<text>", @"": @"<empty>",
        // Account-like English names and titles are words outside the vocabulary.
        @"johnsmith": @"<word>", @"JohnSmith": @"<word>", @"john.smith@example.com": @"<text>", @"QQJohnCache": @"QQ<word>Cache",
        @"com.example.johnsmith": @"com.<word>.<word>", @"Abbey Road": @"<word> <word>", @"Yellow": @"<word>",
        // Fixed names: vocabulary, acronyms, lyric keywords.
        @"MMKV": @"MMKV", @"HTTPStorages": @"HTTPStorages", @"Saved Application State": @"Saved Application State",
        @"QRCFiles": @"QRCFiles", @"NELyricDownload": @"NELyricDownload", @"lrc": @"lrc",
        // Redacting a redacted name changes nothing.
        @"<num>": @"<num>", @"u<num>x": @"u<num>x", @"QQ<word>Cache": @"QQ<word>Cache", @"cache-<uuid>.tmp": @"cache-<uuid>.tmp"};
    for (NSString *segment in segments) {
        NSString *shown = IKRedactPathSegment(segment);
        if (![shown isEqual:segments[segment]]) fprintf(stderr, "%s -> %s\n", segment.UTF8String, shown.UTF8String);
        check([shown isEqual:segments[segment]], "path segment redaction");
    }
    check([IKRedactPathSegment([@"" stringByPaddingToLength:65 withString:@"a" startingAtIndex:0]) isEqual:@"<long>"], "very long segment");
    check([IKRedactPathSegment((id)@5) isEqual:@"<empty>"], "non-string segment");
    NSArray *files = @[@[@"123456.qrc", @"<num>.qrc", @"qrc"], @[@"晴天-周杰伦.lrc", @"<text>.lrc", @"lrc"],
                       @[@"Shape of You.lrc", @"<text>.lrc", @"lrc"], @[@"lyric_cache.db", @"lyric_cache.db", @"db"],
                       @[@"README", @"<word>", @""], @[@".hidden", @".<word>", @""], @[@"song.MP3", @"<word>.mp3", @"mp3"],
                       @[@"0a1b2c3d4e5f60718293a4b5c6d7e8f9.yrc", @"<hex>.yrc", @"yrc"], @[@"lyric.歌词", @"<text>", @""],
                       @[@"track.12345", @"<word>.<num>", @"<num>"], @[@"lyric.db-wal", @"lyric.db-wal", @"db-wal"],
                       // A single English title is masked even when it is the only file in its directory.
                       @[@"Hello.lrc", @"<word>.lrc", @"lrc"], @[@"index.json", @"<word>.json", @"json"],
                       @[@"Mr.Brightside", @"<word>.<word>", @"<word>"], @[@"TaylorSwiftLyric.lrc", @"<word>Lyric.lrc", @"lrc"],
                       @[@"QQLyricCache_v2.plist", @"QQLyricCache_v2.plist", @"plist"], @[@"a.lrc", @"a.lrc", @"lrc"],
                       @[@"john@example.com.lrc", @"<text>.lrc", @"lrc"], @[@"cover_lyric_bg.png", @"cover_lyric_bg.png", @"png"]];
    for (NSArray *row in files) {
        NSString *ext = nil, *shown = IKRedactFileName(row[0], &ext);
        if (![shown isEqual:row[1]] || ![ext isEqual:row[2]]) fprintf(stderr, "%s -> %s (%s)\n", [row[0] UTF8String], shown.UTF8String, ext.UTF8String);
        check([shown isEqual:row[1]] && [ext isEqual:row[2]], "file name redaction keeps the extension");
    }
}

static void testAppImages(NSString *bundlePath, NSString *executable) {
    check([IKProbeAppImage(@"/private/var/containers/Bundle/Application/6F9619FF-8B86-D011-B42D-00C04FC964FF/QQMusic.app/QQMusic",
                           @"/var/containers/Bundle/Application/6F9619FF-8B86-D011-B42D-00C04FC964FF/QQMusic.app") isEqual:@"QQMusic"],
          "main executable with and without /private");
    check([IKProbeAppImage(@"/var/containers/Bundle/Application/X/QQMusic.app/Frameworks/QMLyric.framework/QMLyric",
                           @"/private/var/containers/Bundle/Application/X/QQMusic.app/") isEqual:@"Frameworks/QMLyric.framework/QMLyric"],
          "embedded framework keeps its fixed name");
    check(!IKProbeAppImage(@"/System/Library/Frameworks/Foundation.framework/Foundation", @"/var/containers/Bundle/Application/X/QQMusic.app") &&
          !IKProbeAppImage(@"/usr/lib/libobjc.A.dylib", @"/var/containers/Bundle/Application/X/QQMusic.app") &&
          !IKProbeAppImage(@"/var/containers/Bundle/Application/X/QQMusic.appex/QQMusic", @"/var/containers/Bundle/Application/X/QQMusic.app"),
          "system libraries and other bundles are outside");
    check(!IKProbeAppImage(@"/var/containers/Bundle/Application/X/QQMusic.app/Frameworks/IslandKit-PlaybackDiagnostics.dylib",
                           @"/var/containers/Bundle/Application/X/QQMusic.app"), "IslandKit's own libraries are not app images");
    NSArray *images = IKProbeAppImages(bundlePath, nil);
    BOOL own = NO, system = NO;
    for (NSArray<NSString *> *image in images) {
        if ([image[0].lastPathComponent isEqual:executable.lastPathComponent]) own = YES;
        if ([image[0] hasPrefix:@"/System/"] || [image[0] hasPrefix:@"/usr/"]) system = YES;
    }
    check(own && !system, "loaded images are filtered to the bundle");
    check(![[IKProbeAppImages(bundlePath, executable) valueForKey:@"firstObject"] containsObject:executable] &&
          IKProbeAppImages(bundlePath, executable).count == images.count - 1, "the probe's own image is left out");
}

static void testClasses(NSString *bundlePath) {
    NSArray *images = IKProbeAppImages(bundlePath, nil);
    NSDictionary *packet = IKProbeCollectClasses(images, IKProbeDefaultLimits(), nil);
    check(!initialized, "collecting metadata sends no message to the classes");
    NSArray *names = [packet[@"classes"] valueForKey:@"name"];
    check([names containsObject:@"FixtureLyricStore"] && [names containsObject:@"FixtureKrcParser"] && [names containsObject:@"FixtureYrcBulk0"] &&
          [names containsObject:@"FixtureLyricCell"], "keyword classes are listed");
    check(![names containsObject:@"FixtureQRCodeScanner"] && ![names containsObject:@"FixturePlainModel"] && ![names containsObject:@"NSObject"],
          "other classes are not");
    check([names indexOfObject:@"FixtureLyricViewModel"] < [names indexOfObject:@"FixtureLyricCell"] &&
          [names indexOfObject:@"FixtureYrcBulk7"] < [names indexOfObject:@"FixtureLyricCell"], "data classes come before view classes");
    NSDictionary *store = classNamed(packet, @"FixtureLyricStore"), *parser = classNamed(packet, @"FixtureKrcParser");
    check([store[@"super"] isEqual:@"NSObject"] && [parser[@"super"] isEqual:@"FixtureLyricStore"], "superclass");
    check([store[@"image"] isEqual:@"test-lyric-probe"] && [store[@"late"] isEqual:@NO], "image inside the bundle");
    BOOL lines = NO, seek = NO, shared = NO, property = NO, ivar = NO, offset = NO;
    for (NSString *row in store[@"im"]) {
        if ([row hasPrefix:@"linesForSong: @"]) lines = YES;
        if ([row hasPrefix:@"seekTo:animated: v"]) seek = YES;
    }
    for (NSString *row in store[@"cm"]) if ([row hasPrefix:@"sharedStore @"]) shared = YES;
    for (NSString *row in store[@"props"]) if ([row hasPrefix:@"currentLine T@\"NSString\""]) property = YES;
    for (NSString *row in store[@"ivars"]) {
        if ([row isEqual:@"_lines @\"NSArray\""]) ivar = YES;
        if ([row isEqual:@"_offsetMs d"]) offset = YES;
    }
    check(lines && seek && shared, "instance and class method names with their signatures");
    check(property && ivar && offset, "property and ivar names with type encodings");
    check([store[@"counts"][0] unsignedIntegerValue] == [store[@"im"] count] && [store[@"counts"][2] unsignedIntegerValue] == 2, "member totals");
    check([packet[@"matched"] unsignedIntegerValue] == [packet[@"matchedNames"] count] && [packet[@"classNames"] unsignedIntegerValue] > [names count],
          "sample totals");

    IKProbeLimits limits = IKProbeDefaultLimits();
    limits.classes = 3; limits.names = 4;
    NSDictionary *few = IKProbeCollectClasses(images, limits, nil);
    NSUInteger all = [packet[@"matched"] unsignedIntegerValue];
    check([few[@"classes"] count] == 3 && [few[@"names"] count] == 4 && [few[@"dropped"] unsignedIntegerValue] == all - 7 && all > 7,
          "class limit, name-only overflow and dropped count");
    limits = IKProbeDefaultLimits();
    limits.members = 2;
    NSDictionary *capped = classNamed(IKProbeCollectClasses(images, limits, nil), @"FixtureLyricStore");
    check([capped[@"im"] count] == 2 && [capped[@"counts"][0] unsignedIntegerValue] > 2 && [capped[@"ivars"] count] == 2, "member limit keeps the real total");
    limits = IKProbeDefaultLimits();
    limits.symbol = 8; limits.type = 4;
    NSDictionary *cut = IKProbeCollectClasses(images, limits, nil);
    check(classNamed(cut, @"FixtureL~") != nil, "long names are cut and marked");
    BOOL typeCut = NO;
    for (NSString *row in classNamed(cut, @"FixtureL~")[@"props"]) if ([row hasSuffix:@" T@\"N~"]) typeCut = YES;
    check(typeCut, "long type encodings are cut and marked");
    limits = IKProbeDefaultLimits();
    limits.budget = 60;
    NSDictionary *small = IKProbeCollectClasses(images, limits, nil);
    NSUInteger characters = 0;
    for (NSDictionary *c in small[@"classes"])
        for (NSString *key in @[@"im", @"cm", @"props", @"ivars"])
            for (NSString *row in c[key]) characters += row.length + 1;
    check([small[@"budgetLimited"] isEqual:@YES] && characters <= 60 + 80 && [small[@"classes"] count] < all &&
          [small[@"classes"] count] + [small[@"names"] count] == all, "detail budget, the rest by name only");
    NSSet *earlier = [NSSet setWithObject:@"FixtureLyricStore"];
    NSDictionary *later = IKProbeCollectClasses(images, IKProbeDefaultLimits(), earlier);
    check([classNamed(later, @"FixtureLyricStore")[@"late"] isEqual:@NO] && [classNamed(later, @"FixtureKrcParser")[@"late"] isEqual:@YES],
          "classes missing from the first sample are marked late");
    check(!initialized, "still no message after every collection");

    check([IKEvidenceSymbol("setLine:atTime:", 160) isEqual:@"setLine:atTime:"] && [IKEvidenceSymbol("QQMusic.LyricManager", 160) isEqual:@"QQMusic.LyricManager"] &&
          [IKEvidenceSymbol("歌词", 160) isEqual:@"<text>"] && [IKEvidenceSymbol("has space", 160) isEqual:@"<text>"] && [IKEvidenceSymbol(NULL, 160) isEqual:@"<text>"],
          "only symbol characters are kept");
    check([IKEvidenceType("{CGRect={CGPoint=dd}{CGSize=dd}}", 200) isEqual:@"{CGRect={CGPoint=dd}{CGSize=dd}}"] && [IKEvidenceType(NULL, 200) isEqual:@""] &&
          [IKEvidenceType("@\"歌词\"", 200) isEqual:@"?"], "type encodings stay printable");

    NSMutableDictionary *saved = [packet mutableCopy];
    [saved removeObjectForKey:@"matchedNames"];
    [saved addEntriesFromDictionary:@{@"schema": @1, @"bundleID": @"com.tencent.QQMusic", @"version": @"13.5.0", @"wall": @1795780000, @"uptime": @50,
        @"appImages": @2, @"samples": @[@{@"trigger": @"launch", @"uptime": @50, @"images": @2, @"classNames": @900, @"matched": @14}]}];
    NSString *report = IKClassInventoryReport(saved, @"com.tencent.qqmusic");
    check([report hasPrefix:@"lyric probe app=com.tencent.qqmusic version=13.5.0 captured=2026-"] && [report containsString:@"samples=[launch uptime=50.0 images=2 classNames=900 matched=14]"],
          "report header");
    check([report containsString:@"\nimage test-lyric-probe classNames="] &&
          [report containsString:@"\nclass FixtureLyricStore : NSObject image=test-lyric-probe instanceMethods="] &&
          [report containsString:@"\n  - linesForSong: @"] && [report containsString:@"\n  + sharedStore @"] &&
          [report containsString:@"\n  @ currentLine T@\"NSString\""] && [report containsString:@"\n  . _lines @\"NSArray\""], "report lists members");
    check([report containsString:@"invalid=0"] && [report containsString:@"budgetLimited=0"], "clean file has no invalid entries");
    NSMutableArray *tampered = [saved[@"classes"] mutableCopy];
    [tampered addObject:@{@"name": @"这是一句歌词", @"super": @"NSObject", @"image": @"X", @"im": @[]}];
    [tampered addObject:@{@"name": @"OKClass", @"super": @"NSObject", @"image": @"X", @"counts": @[@1, @0, @0, @0],
                          @"im": @[@"good: v24@0:8@16", @"lyric text here", @"歌词 @", @7]}];
    // The image path must already be in redacted form: no spaces, no non-ASCII, relative, at most eight segments.
    for (NSString *image in @[@"some lyric text", @"歌词", @"/private/var/x", @"a/b/c/d/e/f/g/h/i", @"Frameworks//X"])
        [tampered addObject:@{@"name": @"BadImageLyric", @"super": @"NSObject", @"image": image, @"im": @[]}];
    saved[@"classes"] = tampered;
    saved[@"names"] = @[@"FineName", @"一句", @"with space"];
    NSMutableArray *imageRows = [saved[@"images"] mutableCopy];
    [imageRows addObject:@[@"free text in an image row", @1, @1]];
    [imageRows addObject:@[@"Frameworks/<num>.framework/<num>", @3, @1]];
    saved[@"images"] = imageRows;
    report = IKClassInventoryReport(saved, @"com.tencent.QQMusic");
    check([report containsString:@"\nclass OKClass : NSObject"] && [report containsString:@"  - good: v24@0:8@16"] &&
          [report containsString:@"class names only: FineName"] && [report containsString:@"image Frameworks/<num>.framework/<num> classNames=3"] &&
          [report containsString:@"invalid=12"], "valid rows of a damaged file survive");
    check(![report containsString:@"歌词"] && ![report containsString:@"一句"] && ![report containsString:@"with space"] && ![report containsString:@"lyric text"] &&
          ![report containsString:@"BadImageLyric"] && ![report containsString:@"free text"] && ![report containsString:@"/private"],
          "free text in the file never reaches the report");
    check(!IKClassInventoryReport(saved, @"com.netease.cloudmusic") && !IKClassInventoryReport((id)@"x", @"com.tencent.QQMusic") &&
          !IKClassInventoryReport(@{@"schema": @2, @"bundleID": @"com.tencent.QQMusic"}, @"com.tencent.QQMusic"), "wrong app or schema is refused");
    check([IKProbeGuardReport(@{@"version": @"13.5.0", @"attempts": @{@"launch": @1, @"playback": @2}}, @"com.tencent.QQMusic")
              containsString:@"version=13.5.0 class sampling unfinished launch=1 playback=2 (playback sampling stopped for this version)"] &&
          !IKProbeGuardReport(@{@"attempts": @2}, @"com.tencent.QQMusic") && !IKProbeGuardReport(@{@"attempts": @{}}, @"com.tencent.QQMusic") &&
          !IKProbeGuardReport(@{}, @"com.tencent.QQMusic") && !IKProbeGuardReport(nil, @"com.tencent.QQMusic"), "unfinished sampling is reported per trigger");
}

static void testEvents(NSURL *folder) {
    IKLyricEventLog *log = [[IKLyricEventLog alloc] initWithBundle:@"com.netease.cloudmusic" side:@"player"];
    check(![log observeTitle:nil artist:nil album:nil duration:nil elapsed:nil rate:nil uptime:10], "empty info is not a change");
    check([log observeTitle:@"歌名" artist:@"歌手" album:@"专辑" duration:@200 elapsed:@0 rate:@1 uptime:100], "first fields");
    check(![log observeTitle:@"歌名" artist:@"歌手" album:@"专辑" duration:@200 elapsed:@3 rate:@1 uptime:103], "same text is not a change");
    check([log observeTitle:@"歌名" artist:@"第一句歌词很长" album:@"专辑" duration:@200 elapsed:@12.5 rate:@1 uptime:112.5], "artist carries a line");
    check([log observeTitle:@"第二句" artist:@"第二句" album:@"专辑" duration:@200 elapsed:nil rate:nil uptime:118], "two fields at once");
    check([log observeTitle:@"下一首" artist:@"歌手乙" album:@"专辑" duration:@251 elapsed:@0 rate:@1 uptime:130], "next track");
    check(![log observeTitle:@"下一首" artist:@"歌手乙" album:@"专辑" duration:@251 elapsed:@1 rate:@1 uptime:NAN] && log.count == 4, "bad clock is ignored");
    NSDictionary *snapshot = [log snapshotAtUptime:140 wall:1795780140];
    NSArray<NSArray<NSNumber *> *> *events = snapshot[@"events"];
    check(events.count == 4 && [events[0] isEqual:@[@100, @0, @1, @200, @7, @2, @2, @2, @1]], "first event: all fields, lengths, first flag");
    check([events[1] isEqual:@[@112.5, @12.5, @1, @200, @2, @2, @7, @2, @0]], "artist change with position and length");
    check([events[2] isEqual:@[@118, @-1, @-1, @200, @3, @3, @3, @2, @0]], "missing position and rate are marked");
    check([events[3][8] isEqual:@2] && [events[3][4] isEqual:@3], "a new duration is flagged");
    NSURL *file = [folder URLByAppendingPathComponent:@"events/lyric-probe-events.plist"];
    check([log writeTo:file], "events are saved");
    NSData *bytes = [NSData dataWithContentsOfURL:file];
    for (NSString *text in @[@"歌名", @"歌手", @"专辑", @"第一句歌词很长", @"第二句", @"下一首"]) check(!holds(bytes, text), "saved events hold no text");
    for (id element in events) for (id value in element) check([value isKindOfClass:NSNumber.class], "events are numbers only");

    IKLyricEventLog *ring = [[IKLyricEventLog alloc] initWithBundle:@"com.netease.cloudmusic" side:@"hud"];
    for (int i = 0; i < 250; i++)
        [ring observeTitle:@"歌名" artist:[NSString stringWithFormat:@"line %d", i] album:nil duration:@200 elapsed:@(i) rate:@1 uptime:1000 + i];
    NSDictionary *full = [ring snapshotAtUptime:2000 wall:1795782000];
    check(ring.count == IKEvidenceMaxEvents && [full[@"total"] isEqual:@250] && [full[@"events"][0][0] isEqual:@1050] &&
          [[full[@"events"] lastObject][0] isEqual:@1249], "the newest 200 events are kept");

    // The same changes as seen by the HUD 20 ms, 40 ms and 300 ms later.
    IKLyricEventLog *hud = [[IKLyricEventLog alloc] initWithBundle:@"com.netease.cloudmusic" side:@"hud"];
    [hud observeTitle:@"歌名" artist:@"歌手" album:@"专辑" duration:@200 elapsed:@0 rate:@1 uptime:100.5];
    [hud observeTitle:@"歌名" artist:@"第一句歌词很长" album:@"专辑" duration:@200 elapsed:@12.5 rate:@1 uptime:112.52];
    [hud observeTitle:@"第二句" artist:@"第二句" album:@"专辑" duration:@200 elapsed:nil rate:nil uptime:118.04];
    [hud observeTitle:@"下一首" artist:@"歌手乙" album:@"专辑" duration:@251 elapsed:@0 rate:@1 uptime:130.3];
    NSString *report = IKLyricEventsReport(snapshot, [hud snapshotAtUptime:141 wall:1795780141], @"com.netease.cloudmusic");
    check([report containsString:@"lyric events app=com.netease.cloudmusic side=player captured=2026-"] && [report containsString:@"kept=4 total=4"] &&
          [report containsString:@"\n  t=100.000 pos=0.00 rate=1.00 dur=200.0 changed=title+artist+album len=2+2+2 first"] &&
          [report containsString:@"\n  t=112.500 pos=12.50 rate=1.00 dur=200.0 changed=artist len=7\n"] &&
          [report containsString:@"\n  t=118.000 pos=- rate=- dur=200.0 changed=title+artist len=3+3\n"] &&
          [report containsString:@"\n  t=130.000 pos=0.00 rate=1.00 dur=251.0 changed=title+artist len=3+3 newDuration"], "player lines");
    check([report containsString:@"side=hud captured="] && [report containsString:@"\n  t=112.520 pos=12.50"], "HUD lines");
    check([report containsString:@"lyric latency app=com.netease.cloudmusic paired=3 ambiguous=0 unmatched=0 player=4 hud=4 match=state+position "
                                  "min=0.020 median=0.040 p90=0.300 max=0.300"], "latency pairs each HUD change with the player's");

    // #117: two lines of equal length 4 s apart. The HUD missed the first and got the second 30 ms late.
    NSDictionary *(^pair)(BOOL, BOOL) = ^NSDictionary *(BOOL playerPositions, BOOL hudPositions) {
        IKLyricEventLog *sender = [[IKLyricEventLog alloc] initWithBundle:@"com.netease.cloudmusic" side:@"player"];
        IKLyricEventLog *receiver = [[IKLyricEventLog alloc] initWithBundle:@"com.netease.cloudmusic" side:@"hud"];
        NSNumber *(^at)(double, BOOL) = ^NSNumber *(double position, BOOL known) { return known ? @(position) : nil; };
        [sender observeTitle:@"歌名" artist:@"歌手" album:nil duration:@200 elapsed:at(0, playerPositions) rate:@1 uptime:100];
        [sender observeTitle:@"歌名" artist:@"第一句七个字啊" album:nil duration:@200 elapsed:at(10, playerPositions) rate:@1 uptime:110];
        [sender observeTitle:@"歌名" artist:@"第二句七个字啊" album:nil duration:@200 elapsed:at(14, playerPositions) rate:@1 uptime:114];
        [receiver observeTitle:@"歌名" artist:@"歌手" album:nil duration:@200 elapsed:at(0, hudPositions) rate:@1 uptime:100.5];
        [receiver observeTitle:@"歌名" artist:@"第二句七个字啊" album:nil duration:@200 elapsed:at(14, hudPositions) rate:@1 uptime:114.03];
        return @{@"player": [sender snapshotAtUptime:120 wall:1795780120], @"hud": [receiver snapshotAtUptime:120 wall:1795780120]};
    };
    NSDictionary *logs = pair(YES, YES);
    report = IKLyricEventsReport(logs[@"player"], logs[@"hud"], @"com.netease.cloudmusic");
    check([report containsString:@"paired=1 ambiguous=0 unmatched=0 player=3 hud=2 match=state+position min=0.030 median=0.030"],
          "the position tells two equal-length lines apart");
    logs = pair(NO, NO);
    report = IKLyricEventsReport(logs[@"player"], logs[@"hud"], @"com.netease.cloudmusic");
    check([report containsString:@"lyric latency app=com.netease.cloudmusic paired=0 ambiguous=1 unmatched=0 reason=ambiguous"] &&
          ![report containsString:@" min="], "without positions the two lines are ambiguous and not paired");
    logs = pair(YES, NO);
    report = IKLyricEventsReport(logs[@"player"], logs[@"hud"], @"com.netease.cloudmusic");
    check([report containsString:@"paired=0 ambiguous=1"], "a position on one side only does not decide");

    // If the system rewrote the position, fall back to the state without it, still refusing ties.
    IKLyricEventLog *sender = [[IKLyricEventLog alloc] initWithBundle:@"com.netease.cloudmusic" side:@"player"];
    IKLyricEventLog *receiver = [[IKLyricEventLog alloc] initWithBundle:@"com.netease.cloudmusic" side:@"hud"];
    [sender observeTitle:@"歌名" artist:@"短句" album:nil duration:@200 elapsed:@10 rate:@1 uptime:200];
    [sender observeTitle:@"歌名" artist:@"长一些的一句" album:nil duration:@200 elapsed:@14 rate:@1 uptime:204];
    [receiver observeTitle:@"歌名" artist:@"歌手" album:nil duration:@200 elapsed:@0 rate:@1 uptime:190];
    [receiver observeTitle:@"歌名" artist:@"短句" album:nil duration:@200 elapsed:@10.5 rate:@1 uptime:200.05];
    [receiver observeTitle:@"歌名" artist:@"长一些的一句" album:nil duration:@200 elapsed:@14.5 rate:@1 uptime:204.08];
    report = IKLyricEventsReport([sender snapshotAtUptime:210 wall:1795780210], [receiver snapshotAtUptime:210 wall:1795780210], @"com.netease.cloudmusic");
    check([report containsString:@"paired=2 ambiguous=0 unmatched=0 player=2 hud=3 match=state min=0.050 median=0.080 p90=0.080 max=0.080"],
          "positions that never agree fall back to the other fields");
    for (NSString *text in @[@"歌名", @"第一句", @"第二句", @"下一首"]) check(![report containsString:text], "event report holds no text");
    check([IKLyricEventsReport(snapshot, nil, @"com.netease.cloudmusic") containsString:@"side=hud absent"] &&
          [IKLyricEventsReport(snapshot, nil, @"com.netease.cloudmusic") containsString:@"paired=0 reason=no-hud-events"], "HUD not running");
    check([IKLyricEventsReport(nil, [hud snapshotAtUptime:141 wall:1795780141], @"com.netease.cloudmusic") containsString:@"side=player absent"] &&
          [IKLyricEventsReport(nil, nil, @"com.netease.cloudmusic") containsString:@"reason=no-player-events"], "probe not running");
    check([IKLyricEventsReport(snapshot, [hud snapshotAtUptime:141 wall:1795790000], @"com.netease.cloudmusic") containsString:@"reason=different-boot"],
          "events from another boot are not paired");
    check([IKLyricEventsReport(snapshot, [hud snapshotAtUptime:141 wall:1795780141], @"com.tencent.QQMusic") containsString:@"side=player absent"],
          "another player's file is not used");
    NSMutableDictionary *damaged = [snapshot mutableCopy];
    damaged[@"events"] = @[@[@100, @0, @1, @200, @7, @2, @2, @2, @1], @[@"一句歌词", @0, @1, @200, @2, @2, @2, @2, @0], @[@1, @2], @"歌词",
                           @[@101, @0, @1, @200, @9, @2, @2, @2, @0], @[@102, @0, @1, @200, @2, @2, @99999, @2, @0]];
    report = IKLyricEventsReport(damaged, nil, @"com.netease.cloudmusic");
    check([report containsString:@"kept=1 total=4"] && ![report containsString:@"歌词"], "damaged events are dropped");
    check(IKReadEvidence(file) != nil && !IKReadEvidence([folder URLByAppendingPathComponent:@"missing.plist"]) && !IKReadEvidence(folder), "reading evidence files");
}

static double fakeNow;
static double fakeClock(void) { return fakeNow += 0.5; }

static void put(NSURL *root, NSString *path, NSData *data) {
    NSURL *file = [root URLByAppendingPathComponent:path];
    [NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if (![data writeToURL:file atomically:YES]) { fprintf(stderr, "cannot write %s\n", path.UTF8String); exit(2); }
}

static int swapAt, swapCalls;
static NSURL *swapRoot, *swapOutside;
// Each call happens before a directory is opened. On call `swapAt`, Documents/a becomes a link to a folder outside the container.
static double swappingClock(void) {
    if (++swapCalls == swapAt) {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *a = [swapRoot URLByAppendingPathComponent:@"Documents/a"];
        [fm moveItemAtURL:a toURL:[swapRoot URLByAppendingPathComponent:@"Documents/a-moved"] error:nil];
        [fm createSymbolicLinkAtURL:a withDestinationURL:[swapOutside URLByAppendingPathComponent:@"a"] error:nil];
    }
    return swapCalls * 0.001;
}

static void testSwappedDirectory(NSURL *folder) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSData *timed = [@"[00:01.00]x" dataUsingEncoding:NSUTF8StringEncoding];
    swapOutside = [folder URLByAppendingPathComponent:@"outside" isDirectory:YES];
    // Names are redacted, so the file outside is told apart by its extension.
    put(swapOutside, @"a/b/Lyric/outside.krc", timed);
    BOOL raced = NO;
    for (swapAt = 1; swapAt <= 12; swapAt++) {
        swapRoot = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"swap-%d", swapAt] isDirectory:YES];
        put(swapRoot, @"Documents/a/b/Lyric/inside_lyric.lrc", timed);
        swapCalls = 0;
        IKScanLimits limits = IKDefaultScanLimits();
        limits.clock = swappingClock;
        NSString *report = IKContainerScanReport(swapRoot, @"com.tencent.QQMusic", limits);
        if (!report || [report containsString:@"krc"]) fprintf(stderr, "swap at %d:\n%s\n", swapAt, report.UTF8String);
        check(report && ![report containsString:@"krc"], "a directory swapped for a link mid-scan never leads outside");
        // Documents and Documents/a were read, then Documents/a/b, already queued, could not be opened through the link.
        if ([report containsString:@" directories=2 "] && [report containsString:@" unreadable=1 "]) raced = YES;
        [fm removeItemAtURL:swapRoot error:nil];
    }
    check(raced, "the swap hit a directory that was already queued");
    NSString *fifo = [folder URLByAppendingPathComponent:@"pipe.lrc"].path;
    check(mkfifo(fifo.fileSystemRepresentation, 0600) == 0 && !IKLyricShapeAt(AT_FDCWD, fifo.fileSystemRepresentation, @"lrc"),
          "a FIFO is refused without blocking");
    NSString *link = [folder URLByAppendingPathComponent:@"link.lrc"].path;
    [fm createSymbolicLinkAtPath:link withDestinationPath:[swapOutside URLByAppendingPathComponent:@"a/b/Lyric/outside.krc"].path error:nil];
    check(!IKLyricShapeAt(AT_FDCWD, link.fileSystemRepresentation, @"lrc") && !IKLyricFileShape([NSURL fileURLWithPath:link]), "a link is refused");
    check([IKLyricFileShape([swapOutside URLByAppendingPathComponent:@"a/b/Lyric/outside.krc"])[@"header"] isEqual:@"timed-text"],
          "a regular file is classified from its first bytes");
}

static void testContainer(NSURL *folder) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [folder URLByAppendingPathComponent:@"Data/Application/6F9619FF-8B86-D011-B42D-00C04FC964FF" isDirectory:YES];
    NSData *binary = [NSData dataWithBytes:"\x02\x00\x1f\x8b\x00" length:5];
    NSData *timed = [@"[00:01.00]私有歌词一句\n[00:05.20]第二句" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *plain = [@"just words" dataUsingEncoding:NSUTF8StringEncoding];
    put(root, @"Documents/Lyric/123456789.qrc", binary);
    put(root, @"Documents/Lyric/987654321.qrc", [NSData dataWithBytes:"\x02\x00\x1f\x8b\x00\x01\x02\x03" length:8]);
    put(root, @"Documents/Lyric/晴天-周杰伦.lrc", timed);
    put(root, @"Documents/QQLyricCache/abcdef0123456789abcdef0123456789.dat", binary);
    for (NSString *name in @[@"Hello", @"Yesterday", @"Imagine", @"Halo", @"Faded", @"Believer"])
        put(root, [NSString stringWithFormat:@"Library/Caches/com.tencent.QQMusic/lrc/%@.lrc", name], timed);
    put(root, @"Library/Caches/com.tencent.QQMusic/lrc/index.json", plain);
    put(root, @"Library/Caches/Images/1.png", binary);
    put(root, @"Library/Caches/Images/cover_lyric_bg.png", binary);
    put(root, @"Library/Application Support/1234567/yrc/5.yrc", timed);
    put(root, @"Library/IslandKit/lyric-probe-classes.plist", plain);
    put(root, @"Library/Preferences/com.tencent.QQMusic.plist", plain);
    put(root, @"tmp/QRCode/share.png", binary);
    put(root, @"Documents/a/b/c/Lyric/deep.lrc", timed);
    put(root, @"Documents/johnsmith/Lyric/12.qrc", binary);
    put(root, @"Library/Caches/john.smith@example.com/lyric/1.lrc", timed);
    put(root, @"Library/Caches/single/lrc/Yellow.lrc", timed);
    [fm createSymbolicLinkAtURL:[root URLByAppendingPathComponent:@"tmp/linked.lrc"]
             withDestinationURL:[root URLByAppendingPathComponent:@"Documents/Lyric/123456789.qrc"] error:nil];
    [fm createSymbolicLinkAtURL:[root URLByAppendingPathComponent:@"tmp/LyricLink"]
             withDestinationURL:[root URLByAppendingPathComponent:@"Documents/Lyric"] error:nil];

    NSString *report = IKContainerScanReport(root, @"com.tencent.QQMusic", IKDefaultScanLimits());
    NSArray<NSString *> *expected = @[
        @"\n  Documents/Lyric/ directory",
        @"\n  Documents/Lyric/<num>.qrc ext=qrc files=2 bytes=5..8 header=binary sampled=2",
        @"\n  Documents/Lyric/<text>.lrc ext=lrc files=1 bytes=",
        @"\n  Documents/QQLyricCache/<hex>.dat ext=dat files=1 bytes=5 header=binary sampled=1",
        @"\n  Library/Caches/com.tencent.QQMusic/lrc/<word>.lrc ext=lrc files=6 bytes=",
        @"\n  Library/Caches/com.tencent.QQMusic/lrc/<word>.json ext=json files=1 bytes=10 header=text sampled=1",
        @"\n  Library/Caches/Images/cover_lyric_bg.png ext=png files=1",
        @"\n  Library/Application Support/<num>/yrc/<num>.yrc ext=yrc files=1",
        @"\n  Documents/a/b/c/Lyric/<word>.lrc ext=lrc files=1",
        @"\n  Documents/<word>/Lyric/<num>.qrc ext=qrc files=1",
        @"\n  Library/Caches/<text>/lyric/<num>.lrc ext=lrc files=1",
        @"\n  Library/Caches/<word>/lrc/<word>.lrc ext=lrc files=1"];
    for (NSString *row in expected) {
        if (![report containsString:row]) fprintf(stderr, "missing row %s in\n%s\n", row.UTF8String, report.UTF8String);
        check([report containsString:row], "container rows: fixed names kept, account-like parts replaced");
    }
    check([report containsString:@"header=timed-text"] && [report hasPrefix:@"container scan app=com.tencent.QQMusic directories="] &&
          [report containsString:@"matched=17 rows=19 unlisted=0 symlinks=2 unreadable=0 tooDeep=0 complete=1 limited=none"], "container summary");
    for (NSString *secret in @[@"123456789", @"987654321", @"晴天", @"周杰伦", @"私有歌词", @"abcdef0123", @"1234567", @"IslandKit", @"QRCode",
                               @"Hello", @"Yesterday", @"Imagine", @"Halo", @"Faded", @"Believer", @"index", @"deep", @"Yellow", @"single",
                               @"john", @"smith", @"example", @"6F9619FF", root.path, @"Preferences", @"linked", @"1.png"])
        check(![report containsString:secret], "container report leaves out names, numbers, text and unrelated files");

    IKScanLimits limits = IKDefaultScanLimits();
    limits.depth = 3;
    report = IKContainerScanReport(root, @"com.tencent.QQMusic", limits);
    check(![report containsString:@"Lyric/<word>.lrc"] && ![report containsString:@"<num>.yrc"] && [report containsString:@"limited=depth"] &&
          [report containsString:@"tooDeep=5"] && [report containsString:@"complete=0"] && [report containsString:@"Documents/Lyric/<num>.qrc"] &&
          [report containsString:@"\n  Library/Application Support/<num>/yrc/ directory"], "depth limit still names the directory it did not open");

    for (int i = 0; i < 120; i++) put(root, [NSString stringWithFormat:@"Library/Junk/item-%d.bin", i], binary);
    put(root, @"tmp/yrc/7.yrc", timed);
    limits = IKDefaultScanLimits();
    limits.entries = 60;
    report = IKContainerScanReport(root, @"com.tencent.QQMusic", limits);
    check([report containsString:@"entries=60 "] && [report containsString:@"limited=entries"] && [report containsString:@"complete=0"], "entry limit");
    check([report containsString:@"\n  tmp/yrc/<num>.yrc ext=yrc"] && [report containsString:@"Documents/Lyric/<num>.qrc"],
          "keyword directories are read before a large unrelated one");

    limits = IKDefaultScanLimits();
    limits.clock = fakeClock;
    limits.seconds = 1.2;
    fakeNow = 0;
    report = IKContainerScanReport(root, @"com.tencent.QQMusic", limits);
    check([report containsString:@"limited=time"] && [report containsString:@"complete=0"] && [report containsString:@"directories=2 "], "time limit");

    limits = IKDefaultScanLimits();
    limits.rows = 4;
    report = IKContainerScanReport(root, @"com.tencent.QQMusic", limits);
    check([report containsString:@"rows=4 "] && [report containsString:@"limited=rows"] && ![report containsString:@"unlisted=0"] &&
          [report containsString:@"complete=0"] && [report containsString:@"<num>.qrc"] && ![report containsString:@"cover_lyric_bg"],
          "row limit keeps lyric-looking rows");

    limits = IKDefaultScanLimits();
    limits.headers = 2;
    report = IKContainerScanReport(root, @"com.tencent.QQMusic", limits);
    check([report containsString:@"limited=headers"] && [report containsString:@"header=unsampled sampled=0"] && [report containsString:@"matched=18"] &&
          [report containsString:@"complete=0"], "header limit still lists the files");

    for (int i = 0; i < 12; i++) put(root, [NSString stringWithFormat:@"Documents/Lyric/%d.qrc", 5000 + i], binary);
    report = IKContainerScanReport(root, @"com.tencent.QQMusic", IKDefaultScanLimits());
    check([report containsString:@"Documents/Lyric/<num>.qrc ext=qrc files=14 bytes=5..8 header=binary sampled=8"], "at most eight headers per row");
    check(!IKContainerScanReport([root URLByAppendingPathComponent:@"missing"], @"com.tencent.QQMusic", IKDefaultScanLimits()) &&
          !IKContainerScanReport([NSURL URLWithString:@"https://example.com/"], @"com.tencent.QQMusic", IKDefaultScanLimits()), "missing container");
    NSURL *empty = [folder URLByAppendingPathComponent:@"Data/Application/empty" isDirectory:YES];
    [fm createDirectoryAtURL:empty withIntermediateDirectories:YES attributes:nil error:nil];
    check([IKContainerScanReport(empty, @"com.netease.cloudmusic", IKDefaultScanLimits()) containsString:@"directories=0 entries=0 matched=0 rows=0"],
          "a container without the three folders");
}

static BOOL waitFor(BOOL (^done)(void)) {
    for (int i = 0; i < 400; i++) {
        if (done()) return YES;
        usleep(25000);
    }
    return NO;
}

// The whole probe as it runs inside a player: hook, two class samples, saved events.
static void testProbe(NSURL *folder, NSString *bundlePath) {
    NSURL *directory = [folder URLByAppendingPathComponent:@"Library/IslandKit" isDirectory:YES];
    NSUInteger attempts = 9;
    NSURL *guard = [directory URLByAppendingPathComponent:IKProbeGuardName];
    check(IKProbeBeginSampling(directory, @"1.0", @"launch", &attempts) && attempts == 0, "first launch attempt");
    IKProbeEndSampling(directory, @"launch");
    check(IKProbeBeginSampling(directory, @"1.0", @"playback", &attempts) && attempts == 0, "first playback attempt");  // the player dies here
    check(IKProbeBeginSampling(directory, @"1.0", @"launch", &attempts) && attempts == 0, "the next launch sample starts clean");
    IKProbeEndSampling(directory, @"launch");
    check(IKProbeBeginSampling(directory, @"1.0", @"playback", &attempts) && attempts == 1,
          "a finished launch sample does not clear the playback count");  // and dies again
    check(!IKProbeBeginSampling(directory, @"1.0", @"playback", &attempts) && attempts == 2, "no third playback attempt for this version");
    check(IKProbeBeginSampling(directory, @"1.0", @"launch", &attempts) && attempts == 0, "launch sampling still runs");
    check([IKProbeGuardReport(IKReadEvidence(guard), @"com.tencent.QQMusic")
              containsString:@"unfinished launch=1 playback=2 (playback sampling stopped for this version)"], "the export names the stuck trigger");
    IKProbeEndSampling(directory, @"launch");
    check(IKProbeBeginSampling(directory, @"1.1", @"playback", &attempts) && attempts == 0, "a new player version may try again");
    IKProbeEndSampling(directory, @"playback");
    check(![NSFileManager.defaultManager fileExistsAtPath:guard.path], "finished sampling clears the mark");
    check(!IKProbeBeginSampling(directory, @"1.0", @"other", NULL) && ![NSFileManager.defaultManager fileExistsAtPath:guard.path], "unknown trigger");

    NSDictionary *paused = @{@"title": @"x", @"elapsed": @10, @"uptime": @100};
    check(!IKProbePlaybackStarted(nil, paused), "a title alone is not playback");
    check(!IKProbePlaybackStarted(paused, @{@"title": @"x", @"elapsed": @10, @"uptime": @103}), "a position that stays put is paused");
    check(IKProbePlaybackStarted(paused, @{@"title": @"x", @"elapsed": @12, @"uptime": @102}), "a position that moves with the clock is playback");
    check(!IKProbePlaybackStarted(paused, @{@"title": @"y", @"elapsed": @12, @"uptime": @102}), "another title is a new track, not progress");
    check(!IKProbePlaybackStarted(paused, @{@"title": @"x", @"elapsed": @90, @"uptime": @102}), "a seek is not progress");
    check(!IKProbePlaybackStarted(paused, @{@"title": @"x", @"elapsed": @12, @"uptime": @100}), "no time passed");
    check(IKProbePlaybackStarted(nil, @{@"title": @"x", @"rate": @1, @"uptime": @1}), "a positive rate is playback");
    check(!IKProbePlaybackStarted(paused, @{@"title": @"x", @"rate": @0, @"elapsed": @12, @"uptime": @102}), "a zero rate wins over a moving position");
    check(!IKProbePlaybackStarted(nil, @{@"rate": @1, @"uptime": @1}), "no title, no playback");

    Class center = objc_getClass("MPNowPlayingInfoCenter");
    check(center != Nil, "MediaPlayer is loaded");
    NSURL *classes = [directory URLByAppendingPathComponent:IKProbeClassesName], *events = [directory URLByAppendingPathComponent:IKProbeEventsName];
    check(IKProbeStart(@"com.tencent.QQMusic", bundlePath, directory, 0.1, 0.2, 0.1), "probe starts");
    check(!IKProbeStart(@"com.tencent.QQMusic", bundlePath, directory, 0.1, 0.2, 0.1), "only once per process");
    check(!IKProbeHookNowPlaying(center, ^(NSDictionary *info, double uptime) {}), "the setter is hooked only once");
    check(waitFor(^BOOL { return [[IKReadEvidence(classes)[@"samples"] valueForKey:@"trigger"] isEqual:@[@"launch"]]; }), "launch sample is saved");
    NSDictionary *launch = IKReadEvidence(classes);
    check([launch[@"bundleID"] isEqual:@"com.tencent.QQMusic"] && [launch[@"classes"] count] == 0 && [launch[@"matched"] isEqual:@0],
          "the launch sample leaves out the library that carries the probe");

    NSString *framework = [bundlePath stringByAppendingPathComponent:@"Frameworks/FixtureLyrics.framework/FixtureLyrics"];
    void *handle = dlopen(framework.fileSystemRepresentation, RTLD_NOW);
    check(handle != NULL, "a framework inside the bundle loads after launch");
    BOOL (*touched)(void) = dlsym(handle, "FixtureLyricsTouched");

    MPNowPlayingInfoCenter *shared = MPNowPlayingInfoCenter.defaultCenter;
    // The player prepares the next track while paused: a title without a rate, then the same position, then rate 0.
    NSMutableDictionary *info = [@{MPMediaItemPropertyTitle: @"探针歌名", MPMediaItemPropertyArtist: @"探针歌手",
        MPMediaItemPropertyPlaybackDuration: @200, MPNowPlayingInfoPropertyElapsedPlaybackTime: @1} mutableCopy];
    double before = NSProcessInfo.processInfo.systemUptime;
    shared.nowPlayingInfo = info;
    usleep(100000);
    shared.nowPlayingInfo = info;
    info[MPNowPlayingInfoPropertyPlaybackRate] = @0;
    shared.nowPlayingInfo = info;
    usleep(700000);
    check([[IKReadEvidence(classes)[@"samples"] valueForKey:@"trigger"] isEqual:@[@"launch"]],
          "a preloaded or paused title does not use up the playback sample");
    info[MPNowPlayingInfoPropertyPlaybackRate] = @1;
    info[MPMediaItemPropertyArtist] = @"第一句车载歌词";
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @12.25;
    shared.nowPlayingInfo = info;
    shared.nowPlayingInfo = info;
    shared.nowPlayingInfo = nil;
    shared.nowPlayingInfo = info;
    double after = NSProcessInfo.processInfo.systemUptime;
    check([shared.nowPlayingInfo[MPMediaItemPropertyArtist] isEqual:@"第一句车载歌词"], "the player's own call still reaches the system");

    check(waitFor(^BOOL { return [IKReadEvidence(events)[@"events"] count] == 4; }), "field changes are saved");
    NSDictionary *saved = IKReadEvidence(events);
    NSArray<NSArray<NSNumber *> *> *rows = saved[@"events"];
    check([saved[@"side"] isEqual:@"player"] && [rows[0][4] isEqual:@3] && [rows[0][8] isEqual:@1] && [rows[1][4] isEqual:@2] && [rows[1][6] isEqual:@7] &&
          [rows[1][1] isEqual:@12.25] && [rows[2][5] isEqual:@0] && [rows[3][6] isEqual:@7], "which field changed, its length and the position");
    check(rows[0][0].doubleValue >= before && rows[3][0].doubleValue <= after && rows[0][0].doubleValue <= rows[1][0].doubleValue, "times are taken at the call");
    check(waitFor(^BOOL { return [IKReadEvidence(classes)[@"samples"] count] == 2; }), "playback sample is saved");
    NSDictionary *playback = IKReadEvidence(classes);
    NSDictionary *late = classNamed(playback, @"FixtureLateLyricProvider");
    check([[playback[@"samples"] valueForKey:@"trigger"] isEqual:@[@"launch", @"playback"]] && [late[@"late"] isEqual:@YES] &&
          [late[@"image"] isEqual:@"Frameworks/FixtureLyrics.framework/FixtureLyrics"], "a class loaded after launch is found and marked late");
    BOOL method = NO, ivar = NO;
    for (NSString *row in late[@"im"]) if ([row hasPrefix:@"sentenceAtTime: @"]) method = YES;
    for (NSString *row in late[@"ivars"]) if ([row isEqual:@"_sentences @\"NSArray\""]) ivar = YES;
    check(method && ivar && touched && !touched(), "its members are read without sending it a message");
    // The class file is written before the mark is cleared, so wait for the probe queue to finish.
    check(waitFor(^BOOL { return ![NSFileManager.defaultManager fileExistsAtPath:guard.path]; }), "no sampling mark is left");
    for (NSURL *file in @[classes, events])
        for (NSString *text in @[@"探针歌名", @"探针歌手", @"第一句车载歌词"])
            check(!holds([NSData dataWithContentsOfURL:file], text), "nothing the probe saves holds a title or a line");
    NSString *report = IKClassInventoryReport(playback, @"com.tencent.QQMusic");
    check([report containsString:@"samples=[launch uptime="] && [report containsString:@"; playback uptime="] &&
          [report containsString:@"\nclass FixtureLateLyricProvider : NSObject image=Frameworks/FixtureLyrics.framework/FixtureLyrics"] &&
          [report containsString:@" late\n"], "saved file exports");
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    // The same way the probe finds its own image inside a player.
    Dl_info own;
    if (!dladdr((const void *)&check, &own) || !own.dli_fname) return 2;
    NSString *executable = [NSString stringWithUTF8String:own.dli_fname];
    NSString *bundlePath = executable.stringByDeletingLastPathComponent;
    NSURL *folder = [NSURL fileURLWithPath:[@(argv[1]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    testKeywords();
    testRedaction();
    testAppImages(bundlePath, executable);
    testClasses(bundlePath);
    testEvents(folder);
    testContainer(folder);
    testSwappedDirectory(folder);
    testProbe(folder, bundlePath);
    check(!initialized, "the fixture classes never received a message");
    if (![NSFileManager.defaultManager removeItemAtURL:folder error:nil]) return 2;
    printf("lyric probe: %d checks passed\n", checks);
    return 0;
} }
