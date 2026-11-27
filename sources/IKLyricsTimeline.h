#import <Foundation/Foundation.h>

#define IKLyricsChangedDarwin "com.islandkit.lyrics/changed"
#define IKClockChangedDarwin "com.islandkit.lyrics/clock"
#define IKMaxLyricBytes (512 * 1024)

NSString *IKLyricString(id value, NSUInteger limit);
NSDictionary *IKTrackIdentity(id externalID, id persistentID, id title, id artist, double duration);
BOOL IKSameRecording(NSDictionary *a, NSDictionary *b);
NSString *IKRecordingFile(NSString *bundleID, NSDictionary *track);
NSArray<NSDictionary *> *IKParseTimedLyrics(NSString *text, double duration);
NSArray<NSDictionary *> *IKNormalizeLyricLines(NSArray *lines, BOOL milliseconds, double duration);
NSUInteger IKNextLyricIndex(NSArray<NSDictionary *> *lines, double position);
NSUInteger IKCurrentLyricIndex(NSArray<NSDictionary *> *lines, double position);
NSData *IKReadLyricFile(NSURL *url);

// Read a public AVPlayerItem timebase sample from the same active recording and boot.
BOOL IKPlayerPosition(NSDictionary *sample, NSString *bundle, NSDictionary *track, BOOL playing,
                      double uptime, double wall, double *position, double *rate);

// A player's last elapsed-time sample may be repeated verbatim on pause and resume.
@interface IKPlaybackClock : NSObject
- (void)updatePosition:(NSNumber *)sample stamp:(NSDate *)stamp playing:(BOOL)playing
                  rate:(double)rate sameTrack:(BOOL)same wall:(NSDate *)wall uptime:(double)uptime;
- (double)positionAt:(double)uptime;
@property (nonatomic, readonly) double speed;
@end
