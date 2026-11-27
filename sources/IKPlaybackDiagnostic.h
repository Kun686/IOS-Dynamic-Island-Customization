#import <Foundation/Foundation.h>

#define IKPlaybackDiagnosticsName @"playback-diagnostics.plist"
#define IKPlaybackDiagnosticsNotification "com.islandkit.lyrics/diagnostic"

// Both ends use this vocabulary. A player-provided key, URL or metadata value never becomes log text.
static inline NSArray<NSString *> *IKPlaybackFieldNames(void) {
    return @[@"title",@"artist",@"album",@"duration",@"elapsed",@"rate",@"queueIndex",@"queueCount",
             @"externalID",@"persistentID",@"assetURL",@"mediaAssetURL",@"lyrics",@"artwork",@"mediaType",@"live"];
}

static inline NSString *IKPlayerVersion(id version) {
    if (![version isKindOfClass:NSString.class] || ![version length] || [version length] > 32) return @"?";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.-"];
    return [version rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound ? version : @"?";
}

static inline NSString *IKDiagnosticSummary(NSDictionary *snapshot, NSString *bundle, double now, double wall) {
    if (![snapshot[@"schema"] isEqual:@1] || ![snapshot[@"bundleID"] isEqual:bundle] ||
        ![snapshot[@"uptime"] isKindOfClass:NSNumber.class] || ![snapshot[@"wall"] isKindOfClass:NSNumber.class]) return nil;
    double age = now - [snapshot[@"uptime"] doubleValue];
    if (!isfinite(age) || age < 0 || age > 90 || fabs((wall-[snapshot[@"wall"] doubleValue])-age) > 2) return nil;
    NSDictionary *fields = snapshot[@"fields"];
    if (![fields isKindOfClass:NSDictionary.class]) return nil;
    NSMutableArray *shapes = [NSMutableArray array];
    for (NSString *key in IKPlaybackFieldNames()) {
        if ([@[@"text",@"number",@"url",@"artwork",@"other"] containsObject:fields[key] ?: @""])
            [shapes addObject:[NSString stringWithFormat:@"%@/%@",key,fields[key]]];
    }
    NSString *asset = snapshot[@"asset"];
    if (![@[@"absent",@"file",@"remote",@"other"] containsObject:asset ?: @""]) return nil;
    for (NSString *key in @[@"unknown",@"accessEvents",@"jumpEvents"]) {
        if (![snapshot[key] isKindOfClass:NSNumber.class] || [snapshot[key] integerValue] < 0 ||
            [snapshot[key] integerValue] > 999) return nil;
    }
    NSMutableArray *sidecars = [NSMutableArray array];
    for (NSString *ext in @[@"lrc",@"qrc",@"yrc"]) {
        if ([snapshot[ext] isEqual:@YES]) [sidecars addObject:ext];
    }
    return [NSString stringWithFormat:@"player diagnostic app=%@ version=%@ fields=[%@] otherKeys=%ld asset=%@ sidecars=[%@] avAccess=%ld avJump=%ld",
            bundle,IKPlayerVersion(snapshot[@"version"]),[shapes componentsJoinedByString:@","],
            (long)[snapshot[@"unknown"] integerValue],asset,[sidecars componentsJoinedByString:@","],
            (long)[snapshot[@"accessEvents"] integerValue],(long)[snapshot[@"jumpEvents"] integerValue]];
}
