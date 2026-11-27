// A stand-in for a framework inside a player's bundle that is loaded after launch.
#import <Foundation/Foundation.h>

static BOOL touched;
// A directory name the "player" writes into its container, as a constant string of its own image.
__attribute__((used)) static const char *const FixtureCacheDirectory = "Library/Caches/KaraokeCache";
BOOL FixtureLyricsTouched(void) { return touched; }

@interface FixtureLateLyricProvider : NSObject {
    NSArray *_sentences;
}
@property(nonatomic, copy) NSString *currentSentence;
- (NSString *)sentenceAtTime:(double)time;
@end

@implementation FixtureLateLyricProvider
+ (void)initialize { touched = YES; }
- (NSString *)sentenceAtTime:(double)time { return nil; }
@end
