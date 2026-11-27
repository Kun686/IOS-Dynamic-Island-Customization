#import <Foundation/Foundation.h>

#define IKLyricsChangedDarwin "com.islandkit.lyrics/changed"
#define IKClockChangedDarwin "com.islandkit.lyrics/clock"
#define IKRecordingChangedDarwin "com.islandkit.lyrics/recording"
#define IKRequestRecordingDarwin "com.islandkit.lyrics/request-recording"
#define IKMaxLyricBytes (512 * 1024)

NSString *IKLyricString(id value, NSUInteger limit);
NSDictionary *IKTrackIdentity(id externalID, id persistentID, id title, id artist, double duration);
BOOL IKConflictingRecordingIDs(NSDictionary *a, NSDictionary *b);
BOOL IKSameRecording(NSDictionary *a, NSDictionary *b);
NSString *IKRecordingFile(NSString *bundleID, NSDictionary *track);
NSArray<NSDictionary *> *IKParseTimedLyrics(NSString *text, double duration);
NSArray<NSDictionary *> *IKNormalizeLyricLines(NSArray *lines, BOOL milliseconds, double duration);
NSUInteger IKNextLyricIndex(NSArray<NSDictionary *> *lines, double position);
NSUInteger IKCurrentLyricIndex(NSArray<NSDictionary *> *lines, double position);
NSData *IKReadLyricFile(NSURL *url);

NSString *IKDecodeLyricText(NSData *data);
NSArray<NSString *> *IKRecordingFilenames(NSString *bundle, NSDictionary *track);

// The baseline stays fixed while car lyrics change the raw display fields.
@interface IKRecordingTracker : NSObject
@property(nonatomic, readonly, copy) NSDictionary *recording;
@property(nonatomic, readonly, copy) NSString *carLyric;
@property(nonatomic, readonly) double lyricUpdatedAt;
@property(nonatomic, readonly) NSInteger lyricField;
- (BOOL)observe:(NSDictionary *)raw album:(NSString *)album queueIndex:(NSNumber *)index
       position:(NSNumber *)position bundle:(NSString *)bundle;
- (NSDictionary *)snapshotAtUptime:(double)uptime wall:(double)wall;
- (BOOL)writeSnapshotTo:(NSURL *)file canonical:(NSDictionary *)canonical force:(BOOL)force;
@end

NSString *IKFreshPlayerLyric(NSDictionary *snapshot, IKRecordingTracker *local, NSDictionary *raw);
NSDictionary *IKLiveRecording(NSDictionary *snapshot, NSString *bundle, NSDictionary *raw,
                              NSNumber *index, NSString *pairedSession, double uptime, double wall);

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
