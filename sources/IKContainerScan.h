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
