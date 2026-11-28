#import <Foundation/Foundation.h>

#define IKPlaybackDiagnosticsName @"playback-diagnostics.plist"
#define IKPlaybackLaunchName @"playback-launch.plist"
#define IKPlaybackDiagnosticsNotification "com.islandkit.lyrics/diagnostic"

#define IKPlaybackHistoryName @"playback-report.plist"

// Retain symbol-shaped field names. Values, absolute paths and arbitrary strings stay out of diagnostics.
BOOL IKMetadataSymbol(id key);
BOOL IKLyricSymbol(NSString *key);
NSDictionary *IKLyricFileShape(NSURL *url);
NSString *IKFileShapeSummary(NSDictionary *shape);
void IKRememberDiagnostic(NSURL *directory, NSDictionary *packet);
NSString *IKDiagnosticHistory(NSURL *directory, NSString *bundle);
static inline NSArray<NSString *> *IKPlaybackFieldNames(void) {
    return @[@"title",@"artist",@"album",@"duration",@"elapsed",@"rate",@"queueIndex",@"queueCount",
             @"externalID",@"persistentID",@"assetURL",@"mediaAssetURL",@"lyrics",@"artwork",@"mediaType",@"live"];
}

static inline NSString *IKPlayerVersion(id version) {
    if (![version isKindOfClass:NSString.class] || ![version length] || [version length] > 32) return @"?";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.-"];
    return [version rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound ? version : @"?";
}

NSString *IKDiagnosticSummary(NSDictionary *snapshot, NSString *bundle, double now, double wall);
