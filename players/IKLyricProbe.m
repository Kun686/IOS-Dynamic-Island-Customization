#import "IKLyricProbe.h"
#import "IKPlaybackDiagnostic.h"
#import <MediaPlayer/MediaPlayer.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#pragma mark - App images

static NSString *IKProbePlainPath(NSString *path) {
    return [path hasPrefix:@"/private/"] ? [path substringFromIndex:8] : path;
}

NSString *IKProbeAppImage(NSString *image, NSString *bundlePath) {
    if (![image isKindOfClass:NSString.class] || ![bundlePath isKindOfClass:NSString.class] || !image.length || !bundlePath.length) return nil;
    NSString *base = IKProbePlainPath(bundlePath);
    while (base.length > 1 && [base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSString *path = IKProbePlainPath(image);
    if (![path hasPrefix:[base stringByAppendingString:@"/"]]) return nil;
    if ([path.lastPathComponent.lowercaseString hasPrefix:@"islandkit"]) return nil;
    NSMutableArray<NSString *> *shown = [NSMutableArray array];
    for (NSString *part in [[path substringFromIndex:base.length + 1] componentsSeparatedByString:@"/"])
        if (part.length && shown.count < 8) [shown addObject:IKRedactImageSegment(part)];
    return shown.count ? [shown componentsJoinedByString:@"/"] : nil;
}

NSArray<NSArray<NSString *> *> *IKProbeAppImages(NSString *bundlePath, NSString *ownImage) {
    unsigned int count = 0;
    const char **names = objc_copyImageNames(&count);
    NSString *own = ownImage.length ? IKProbePlainPath(ownImage) : nil;
    NSMutableArray<NSArray<NSString *> *> *images = [NSMutableArray array];
    for (unsigned int i = 0; names && i < count; i++) {
        NSString *name = names[i] ? [NSString stringWithUTF8String:names[i]] : nil;
        if (!name || [IKProbePlainPath(name) isEqual:own]) continue;
        NSString *shown = IKProbeAppImage(name, bundlePath);
        if (shown) [images addObject:@[name, shown]];
    }
    free(names);
    return images;
}

#pragma mark - Class metadata

// Everything below uses the runtime's copy functions on Class values only. Nothing is sent to a class
// or an instance, so no +initialize and no player code runs.
static NSString *IKProbeMember(const char *name, const char *type, IKProbeLimits limits, NSUInteger *room) {
    NSString *symbol = IKEvidenceSymbol(name, limits.symbol), *kind = IKEvidenceType(type, limits.type);
    NSString *row = kind.length ? [NSString stringWithFormat:@"%@ %@", symbol, kind] : symbol;
    *room -= MIN(*room, row.length + 1);
    return row;
}

static NSArray<NSString *> *IKProbeMethods(Class cls, IKProbeLimits limits, NSUInteger *room, NSUInteger *total) {
    unsigned int count = 0;
    Method *list = cls ? class_copyMethodList(cls, &count) : NULL;
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (unsigned int i = 0; list && i < count && rows.count < limits.members && *room; i++)
        [rows addObject:IKProbeMember(sel_getName(method_getName(list[i])), method_getTypeEncoding(list[i]), limits, room)];
    free(list);
    *total = count;
    return rows;
}

static NSDictionary *IKProbeDescribe(NSString *name, NSString *image, BOOL late, IKProbeLimits limits, NSUInteger *room) {
    Class cls = objc_lookUpClass(name.UTF8String);
    if (!cls) return nil;
    Class parent = class_getSuperclass(cls);
    NSUInteger totals[4] = {0, 0, 0, 0};
    NSArray *instanceMethods = IKProbeMethods(cls, limits, room, &totals[0]);
    NSArray *classMethods = IKProbeMethods(objc_getMetaClass(class_getName(cls)), limits, room, &totals[1]);

    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    NSMutableArray<NSString *> *propertyRows = [NSMutableArray array];
    for (unsigned int i = 0; properties && i < count && propertyRows.count < limits.members && *room; i++)
        [propertyRows addObject:IKProbeMember(property_getName(properties[i]), property_getAttributes(properties[i]), limits, room)];
    free(properties);
    totals[2] = count;

    count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    NSMutableArray<NSString *> *ivarRows = [NSMutableArray array];
    for (unsigned int i = 0; ivars && i < count && ivarRows.count < limits.members && *room; i++)
        [ivarRows addObject:IKProbeMember(ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]), limits, room)];
    free(ivars);
    totals[3] = count;

    return @{@"name": IKEvidenceSymbol(name.UTF8String, limits.symbol),
             @"super": parent ? IKEvidenceSymbol(class_getName(parent), limits.symbol) : @"",
             @"image": image, @"late": @(late),
             @"counts": @[@(totals[0]), @(totals[1]), @(totals[2]), @(totals[3])],
             @"im": instanceMethods, @"cm": classMethods, @"props": propertyRows, @"ivars": ivarRows};
}

NSDictionary *IKProbeCollectClasses(NSArray<NSArray<NSString *> *> *images, IKProbeLimits limits, NSSet<NSString *> *earlier) {
    NSMutableArray<NSArray *> *candidates = [NSMutableArray array], *imageRows = [NSMutableArray array];
    NSUInteger classNames = 0;
    for (NSArray<NSString *> *image in images) {
        if (![image isKindOfClass:NSArray.class] || image.count != 2) continue;
        unsigned int count = 0;
        const char **names = objc_copyClassNamesForImage(image[0].UTF8String, &count);
        NSUInteger hits = 0;
        for (unsigned int i = 0; names && i < count; i++) {
            const char *raw = names[i];
            if (!raw || !(strcasestr(raw, "lyric") || strcasestr(raw, "lrc") || strcasestr(raw, "qrc") ||
                          strcasestr(raw, "yrc") || strcasestr(raw, "krc"))) continue;
            NSString *name = [NSString stringWithUTF8String:raw];
            NSInteger rank = IKEvidenceClassRank(name);
            if (rank < 0) continue;
            hits++;
            [candidates addObject:@[@(rank), name, image[1]]];
        }
        free(names);
        classNames += count;
        if (hits && imageRows.count < limits.images) [imageRows addObject:@[image[1], @(count), @(hits)]];
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSComparisonResult rank = [a[0] compare:b[0]];
        return rank != NSOrderedSame ? rank : [a[1] compare:b[1]];
    }];
    NSMutableArray<NSDictionary *> *classes = [NSMutableArray array];
    NSMutableArray<NSString *> *namesOnly = [NSMutableArray array], *matched = [NSMutableArray array];
    NSUInteger room = limits.budget, dropped = 0;
    for (NSArray *candidate in candidates) {
        NSString *name = candidate[1];
        [matched addObject:name];
        NSDictionary *record = nil;
        if (classes.count < limits.classes && room)
            record = IKProbeDescribe(name, candidate[2], earlier && ![earlier containsObject:name], limits, &room);
        if (record) [classes addObject:record];
        else if (namesOnly.count < limits.names) [namesOnly addObject:IKEvidenceSymbol(name.UTF8String, limits.symbol)];
        else dropped++;
    }
    return @{@"classNames": @(classNames), @"matched": @(candidates.count), @"images": imageRows, @"classes": classes,
             @"names": namesOnly, @"dropped": @(dropped), @"budgetLimited": @(room == 0), @"matchedNames": matched};
}

#pragma mark - Sampling guard

// The guard file holds {version, attempts: {trigger: unfinished count}} for the current player version.
static NSMutableDictionary<NSString *, NSNumber *> *IKProbeGuardCounts(NSURL *file, NSString *version) {
    NSDictionary *old = IKReadEvidence(file);
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSDictionary *attempts = old[@"attempts"];
    if (![old[@"version"] isEqual:version] || ![attempts isKindOfClass:NSDictionary.class]) return counts;
    for (NSString *trigger in @[@"launch", @"playback"]) {
        id value = attempts[trigger];
        if ([value isKindOfClass:NSNumber.class] && [value unsignedIntegerValue] > 0) counts[trigger] = @(MIN([value unsignedIntegerValue], 99));
    }
    return counts;
}

static BOOL IKProbeWriteGuard(NSURL *file, NSString *version, NSDictionary *counts) {
    if (!counts.count) return [NSFileManager.defaultManager removeItemAtURL:file error:nil] || ![NSFileManager.defaultManager fileExistsAtPath:file.path];
    return [@{@"version": version, @"attempts": counts} writeToURL:file atomically:YES];
}

BOOL IKProbeBeginSampling(NSURL *directory, NSString *version, NSString *trigger, NSUInteger *attempts) {
    if (attempts) *attempts = 0;
    if (!directory.isFileURL || ![@[@"launch", @"playback"] containsObject:trigger ?: @""]) return NO;
    version = version ?: @"?";
    NSURL *file = [directory URLByAppendingPathComponent:IKProbeGuardName];
    NSMutableDictionary<NSString *, NSNumber *> *counts = IKProbeGuardCounts(file, version);
    NSUInteger tried = counts[trigger].unsignedIntegerValue;
    if (attempts) *attempts = tried;
    if (tried >= 2) return NO;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    counts[trigger] = @(tried + 1);
    return IKProbeWriteGuard(file, version, counts);
}

void IKProbeEndSampling(NSURL *directory, NSString *trigger) {
    if (!directory.isFileURL || !trigger) return;
    NSURL *file = [directory URLByAppendingPathComponent:IKProbeGuardName];
    NSDictionary *old = IKReadEvidence(file);
    NSString *version = [old[@"version"] isKindOfClass:NSString.class] ? old[@"version"] : @"?";
    NSMutableDictionary *counts = IKProbeGuardCounts(file, version);
    [counts removeObjectForKey:trigger];
    IKProbeWriteGuard(file, version, counts);
}

BOOL IKProbePlaybackStarted(NSDictionary *previous, NSDictionary *current) {
    if (![current[@"title"] isKindOfClass:NSString.class] || ![current[@"title"] length]) return NO;
    id rate = current[@"rate"];
    if ([rate isKindOfClass:NSNumber.class]) return [rate doubleValue] > 0 && isfinite([rate doubleValue]);
    if (![previous[@"title"] isEqual:current[@"title"]]) return NO;
    id before = previous[@"elapsed"], after = current[@"elapsed"];
    if (![before isKindOfClass:NSNumber.class] || ![after isKindOfClass:NSNumber.class]) return NO;
    double moved = [after doubleValue] - [before doubleValue];
    double passed = [current[@"uptime"] doubleValue] - [previous[@"uptime"] doubleValue];
    return isfinite(moved) && isfinite(passed) && passed > 0 && moved >= 0.25 && moved <= passed * 2 + 1;
}

#pragma mark - Now-playing hook

static void (*IKProbeOriginalSetInfo)(id, SEL, NSDictionary *);
static void (^IKProbeObserver)(NSDictionary *, double);

static void IKProbeSetNowPlayingInfo(id self, SEL _cmd, NSDictionary *info) {
    double uptime = NSProcessInfo.processInfo.systemUptime;
    IKProbeOriginalSetInfo(self, _cmd, info);
    @try {
        IKProbeObserver(info, uptime);
    } @catch (__unused id exception) {
    }
}

BOOL IKProbeHookNowPlaying(Class center, void (^observer)(NSDictionary *, double)) {
    static BOOL installed;
    if (installed || !center || !observer) return NO;
    Method method = class_getInstanceMethod(center, sel_registerName("setNowPlayingInfo:"));
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    if (!types || types[0] != 'v' || method_getNumberOfArguments(method) != 3) return NO;
    IKProbeObserver = [observer copy];
    IKProbeOriginalSetInfo = (void (*)(id, SEL, NSDictionary *))method_getImplementation(method);
    if (!IKProbeOriginalSetInfo) return NO;
    installed = YES;
    method_setImplementation(method, (IMP)IKProbeSetNowPlayingInfo);
    return YES;
}

#pragma mark - Probe

static dispatch_queue_t IKProbeQueue;
static IKLyricEventLog *IKProbeLog;
static NSURL *IKProbeDirectory;
static NSString *IKProbeBundle, *IKProbeBundlePath, *IKProbeOwnImage;
static NSSet<NSString *> *IKProbeFirstNames;
static NSMutableArray<NSDictionary *> *IKProbeSamples;
static NSDictionary *IKProbeLastCall;  // title, rate, elapsed, uptime of the previous call; in memory only
static BOOL IKProbeFlushPending, IKProbePlaybackSeen;
static double IKProbePlaybackDelay, IKProbeFlushDelay;

// Runs on the probe queue.
static void IKProbeSample(NSString *trigger) {
    @autoreleasepool {
        @try {
            NSString *version = IKPlayerVersion(NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]);
            if (!IKProbeBeginSampling(IKProbeDirectory, version, trigger, NULL)) return;
            double started = NSProcessInfo.processInfo.systemUptime;
            NSArray *images = IKProbeAppImages(IKProbeBundlePath, IKProbeOwnImage);
            NSMutableDictionary *packet = [IKProbeCollectClasses(images, IKProbeDefaultLimits(), IKProbeFirstNames) mutableCopy];
            if (!IKProbeFirstNames) IKProbeFirstNames = [NSSet setWithArray:packet[@"matchedNames"]];
            [packet removeObjectForKey:@"matchedNames"];
            NSDictionary *sample = @{@"trigger": trigger, @"uptime": @(started), @"images": @(images.count),
                                     @"classNames": packet[@"classNames"], @"matched": packet[@"matched"]};
            NSUInteger old = [IKProbeSamples indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger i, BOOL *stop) {
                return [item[@"trigger"] isEqual:trigger];
            }];
            if (old != NSNotFound) [IKProbeSamples removeObjectAtIndex:old];
            [IKProbeSamples addObject:sample];
            [packet addEntriesFromDictionary:@{@"schema": @1, @"bundleID": IKProbeBundle, @"version": version, @"uptime": @(started),
                @"wall": @(NSDate.date.timeIntervalSince1970), @"samples": [IKProbeSamples copy], @"appImages": @(images.count)}];
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:packet format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            if (data.length && data.length <= IKEvidenceMaxFileBytes)
                [data writeToURL:[IKProbeDirectory URLByAppendingPathComponent:IKProbeClassesName] options:NSDataWritingAtomic error:nil];
            IKProbeEndSampling(IKProbeDirectory, trigger);
        } @catch (__unused id exception) {
        }
    }
}

// Runs on the thread that called -setNowPlayingInfo:. Copies what is needed and returns.
static void IKProbeObserve(NSDictionary *info, double uptime) {
    if (![info isKindOfClass:NSDictionary.class]) info = nil;
    NSString *title = IKEvidenceText(info[MPMediaItemPropertyTitle]);
    NSString *artist = IKEvidenceText(info[MPMediaItemPropertyArtist]);
    NSString *album = IKEvidenceText(info[MPMediaItemPropertyAlbumTitle]);
    id duration = info[MPMediaItemPropertyPlaybackDuration], elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    id rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    if (![duration isKindOfClass:NSNumber.class]) duration = nil;
    if (![elapsed isKindOfClass:NSNumber.class]) elapsed = nil;
    if (![rate isKindOfClass:NSNumber.class]) rate = nil;
    dispatch_async(IKProbeQueue, ^{
        BOOL changed = [IKProbeLog observeTitle:title artist:artist album:album duration:duration elapsed:elapsed rate:rate uptime:uptime];
        if (changed && !IKProbeFlushPending) {
            IKProbeFlushPending = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(IKProbeFlushDelay * NSEC_PER_SEC)), IKProbeQueue, ^{
                IKProbeFlushPending = NO;
                [IKProbeLog writeTo:[IKProbeDirectory URLByAppendingPathComponent:IKProbeEventsName]];
            });
        }
        NSMutableDictionary *call = [NSMutableDictionary dictionaryWithObject:@(uptime) forKey:@"uptime"];
        if (title) call[@"title"] = title;
        if (rate) call[@"rate"] = rate;
        if (elapsed) call[@"elapsed"] = elapsed;
        BOOL playing = IKProbePlaybackStarted(IKProbeLastCall, call);
        IKProbeLastCall = call;
        // A player may publish the next track's title while paused. Only a confirmed start uses up the playback sample.
        if (playing && !IKProbePlaybackSeen) {
            IKProbePlaybackSeen = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(IKProbePlaybackDelay * NSEC_PER_SEC)), IKProbeQueue, ^{
                IKProbeSample(@"playback");
            });
        }
    });
}

BOOL IKProbeStart(NSString *bundle, NSString *bundlePath, NSURL *directory, double launchDelay, double playbackDelay, double flushDelay) {
    // One probe per process, also when the library is loaded twice under different names.
    Class marker = objc_lookUpClass("IKProbeProcessMarker") ? Nil : objc_allocateClassPair(objc_getClass("NSObject"), "IKProbeProcessMarker", 0);
    if (!marker) return NO;
    objc_registerClassPair(marker);
    IKProbeBundle = [bundle copy];
    IKProbeBundlePath = [bundlePath copy];
    IKProbePlaybackDelay = playbackDelay;
    IKProbeFlushDelay = flushDelay;
    Dl_info own;
    if (dladdr((const void *)&IKProbeStart, &own) && own.dli_fname) IKProbeOwnImage = [NSString stringWithUTF8String:own.dli_fname];
    IKProbeLog = [[IKLyricEventLog alloc] initWithBundle:bundle side:@"player"];
    IKProbeSamples = [NSMutableArray array];
    IKProbeQueue = dispatch_queue_create("com.islandkit.lyric-probe",
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    dispatch_async(IKProbeQueue, ^{
        NSURL *library = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
        IKProbeDirectory = directory ?: [library URLByAppendingPathComponent:@"IslandKit" isDirectory:YES];
    });
    IKProbeHookNowPlaying(objc_getClass("MPNowPlayingInfoCenter"), ^(NSDictionary *info, double uptime) { IKProbeObserve(info, uptime); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(launchDelay * NSEC_PER_SEC)), IKProbeQueue, ^{ IKProbeSample(@"launch"); });
    return YES;
}

__attribute__((constructor)) static void IKStartLyricProbe(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (IKProbeSupportedBundle(bundle)) IKProbeStart(bundle, NSBundle.mainBundle.bundlePath, nil, 6, 3, 1.5);
    }
}
