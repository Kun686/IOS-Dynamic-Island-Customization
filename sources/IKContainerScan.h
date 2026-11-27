#import <Foundation/Foundation.h>

// Walks a player's data container from the settings app and reports the shape of lyric-related files.
// Runs on the caller's thread. Call it off the main thread.
typedef struct {
    NSUInteger depth;       // directory levels below the container that are opened; Documents is level 1
    NSUInteger entries;     // directory entries examined
    NSUInteger rows;        // report rows
    NSUInteger headers;     // files whose first 512 bytes are classified
    double seconds;
    double (*clock)(void);  // monotonic seconds; NULL uses the system uptime
} IKScanLimits;
IKScanLimits IKDefaultScanLimits(void);

// Looks in Documents, Library and tmp for files whose own name or a directory above them contains
// lyric / lrc / qrc / yrc / krc. Reports redacted relative paths, extension, size range and header kind.
// Returns nil when the container cannot be opened.
NSString *IKContainerScanReport(NSURL *container, NSString *bundle, IKScanLimits limits);
// The same, keeping directory-name runs in `fixed` (names the probe confirmed in the player's binary) readable.
NSString *IKContainerScanReportKeeping(NSURL *container, NSString *bundle, IKScanLimits limits, NSSet<NSString *> *fixed);

// The distinct directory names below Documents, Library and tmp, with the same depth, entry and time limits and
// the same refusal of symbolic links. Used by the probe inside the player to look for fixed names.
NSArray<NSString *> *IKContainerDirectoryNames(NSURL *container, IKScanLimits limits);
