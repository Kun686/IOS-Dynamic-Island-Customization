// A stand-in for a framework inside a player's bundle that is loaded after launch.
#import <Foundation/Foundation.h>

static BOOL touched;
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
