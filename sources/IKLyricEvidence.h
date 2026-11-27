#import <Foundation/Foundation.h>

// Evidence about where a player keeps its lyric data. Shapes and symbols only:
// no lyric text, no account values, no object values leave these functions.

// Written by the probe into <player container>/Library/IslandKit/.
#define IKProbeClassesName @"lyric-probe-classes.plist"
#define IKProbeEventsName @"lyric-probe-events.plist"
// Present while a class sample is running. Left behind when the player was killed during one.
#define IKProbeGuardName @"lyric-probe-sampling.plist"
// Written by the HUD into IKDataDir, one file per player: prefix + lowercased bundle ID + ".plist".
#define IKHUDEventsPrefix @"lyric-hud-events-"

#define IKEvidenceMaxEvents 200
#define IKEvidenceMaxTextLength 4096
#define IKEvidenceMaxFileBytes (2 * 1024 * 1024)

BOOL IKProbeSupportedBundle(NSString *bundle);

// lyric / lrc / qrc / yrc / krc, case-insensitive. "QRCode" alone does not count as qrc.
BOOL IKEvidenceKeyword(NSString *name);
// -1 no keyword, 0 likely data or logic, 1 view-like (View, Cell, Button, Label, Layer). Lower ranks are listed first.
NSInteger IKEvidenceClassRank(NSString *name);

// A directory name from a player's data container. Digits become <num>, long hex <hex>, a UUID <uuid>,
// long mixed tokens <id>; a name with '@' or anything outside printable ASCII becomes <text>.
// Words are kept only when they carry a lyric keyword, are in a vocabulary of technical words,
// have at most two letters, or are a capitalised acronym of at most four; other words become <word>.
// Placeholders already present pass through, so redacting twice gives the same result.
NSString *IKRedactPathSegment(NSString *segment);
// A file name. The stem keeps words only when it contains a lyric keyword ("lyric_cache"), otherwise
// every word of two letters or more becomes <word>; a stem with spaces is <text>. The extension keeps
// short and technical names and is returned lowercased in `extension`, or @"" when there is none.
NSString *IKRedactFileName(NSString *name, NSString **extension);
// A path segment inside the app bundle (framework and executable names). Only numbers and IDs are replaced.
NSString *IKRedactImageSegment(NSString *segment);

typedef struct {
    NSUInteger classes;  // classes listed with members
    NSUInteger names;    // further matching classes listed by name only
    NSUInteger members;  // per class and kind: instance methods, class methods, properties, ivars
    NSUInteger symbol;   // characters kept of a name
    NSUInteger type;     // characters kept of a type encoding
    NSUInteger images;   // images listed
    NSUInteger budget;   // total characters of member detail
} IKProbeLimits;
IKProbeLimits IKProbeDefaultLimits(void);

// A name made of A-Z a-z 0-9 _ . $ : only, cut to `limit`. Returns <text> otherwise.
NSString *IKEvidenceSymbol(const char *name, NSUInteger limit);
// A type encoding in printable ASCII, cut to `limit`. Returns @"" for NULL and ? for anything else.
NSString *IKEvidenceType(const char *encoding, NSUInteger limit);

// Text for the export. `packet` is the probe's class file as read from disk and is treated as untrusted.
NSString *IKClassInventoryReport(NSDictionary *packet, NSString *bundle);
// One line when a class sample did not finish, nil otherwise. `marker` is the guard file as read from disk.
NSString *IKProbeGuardReport(NSDictionary *marker, NSString *bundle);

// An immutable copy of a display string, nil for anything else.
NSString *IKEvidenceText(id value);

// Records when title, artist or album change. Texts are compared in memory and never stored.
@interface IKLyricEventLog : NSObject
- (instancetype)initWithBundle:(NSString *)bundle side:(NSString *)side;
// YES when a field changed and an event was appended. `uptime` is the system uptime of the observation.
- (BOOL)observeTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album
            duration:(NSNumber *)duration elapsed:(NSNumber *)elapsed rate:(NSNumber *)rate uptime:(double)uptime;
- (NSDictionary *)snapshotAtUptime:(double)uptime wall:(double)wall;
- (BOOL)writeTo:(NSURL *)file;
@property(nonatomic, readonly) NSUInteger count;
@end

// `player` and `hud` are event files as read from disk. Either may be nil.
NSString *IKLyricEventsReport(NSDictionary *player, NSDictionary *hud, NSString *bundle);

// A property list of at most IKEvidenceMaxFileBytes from a regular file, nil otherwise.
NSDictionary *IKReadEvidence(NSURL *file);
