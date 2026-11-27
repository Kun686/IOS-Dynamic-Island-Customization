#import <Foundation/Foundation.h>
#import "IKLyricEvidence.h"

// Evidence probe for QQ Music and NetEase Cloud Music. It reads Objective-C runtime metadata and the
// dictionaries the player hands to MPNowPlayingInfoCenter. It calls no player method and reads no player object.

// Path of `image` inside the app bundle with each segment redacted. nil for system libraries,
// for IslandKit's own libraries and for anything outside the bundle.
NSString *IKProbeAppImage(NSString *image, NSString *bundlePath);

// Loaded images that belong to the app, as pairs of (name known to the runtime, name to print).
NSArray<NSArray<NSString *> *> *IKProbeAppImages(NSString *bundlePath, NSString *ownImage);

// Class names containing lyric / lrc / qrc / yrc / krc in `images`, with superclass, methods, properties and ivars.
// `earlier` holds the names an earlier sample found; classes outside it are marked late.
// The result also carries "matchedNames", which callers remove before saving.
NSDictionary *IKProbeCollectClasses(NSArray<NSArray<NSString *> *> *images, IKProbeLimits limits, NSSet<NSString *> *earlier);

// Wraps -setNowPlayingInfo: of `center`. `observer` runs on the caller's thread after the original,
// with the dictionary and the system uptime taken before the original ran. Installs once per process.
BOOL IKProbeHookNowPlaying(Class center, void (^observer)(NSDictionary *info, double uptime));

// At most two unfinished attempts per player version and per trigger ("launch" or "playback").
// Returns NO when this trigger's class sampling should be skipped. Finishing one trigger leaves the other's count alone.
BOOL IKProbeBeginSampling(NSURL *directory, NSString *version, NSString *trigger, NSUInteger *attempts);
void IKProbeEndSampling(NSURL *directory, NSString *trigger);

// `recent` holds the last -setNowPlayingInfo: calls, oldest first, each with the keys title, rate, elapsed and
// uptime (each optional). Playback has started when the newest call publishes a positive rate, or, without a rate,
// when the same title's position advanced with the clock over the last two intervals: each interval at least
// 0.2 s long and moving between half and twice the time that passed. A title alone, a zero rate, a seek
// (also a small one while paused) or a single interval does not count.
BOOL IKProbePlaybackStarted(NSArray<NSDictionary *> *recent);

// Writes a class sample and clears this trigger's unfinished mark only when the file was written.
BOOL IKProbeSaveSample(NSURL *directory, NSDictionary *packet, NSString *trigger);

// Directory-name runs from `runs` that occur as a whole run of letters and digits in the __TEXT,__cstring section
// of `images` (pairs from IKProbeAppImages). Such a name is written into the player itself, not chosen by the user.
// Only membership is checked; nothing from the section is kept. `complete` is NO when `seconds` ran out.
NSSet<NSString *> *IKProbeConfirmNames(NSArray<NSString *> *runs, NSArray<NSArray<NSString *> *> *images, double seconds, BOOL *complete);

// Starts the probe in this process: hooks the now-playing setter, samples classes `launchDelay` seconds from now and
// `playbackDelay` seconds after playback is first published, and saves field-change events at most every `flushDelay` seconds.
// `directory` nil means Library/IslandKit in the current container. The library's constructor calls this
// only inside com.tencent.QQMusic and com.netease.cloudmusic.
BOOL IKProbeStart(NSString *bundle, NSString *bundlePath, NSURL *directory, double launchDelay, double playbackDelay, double flushDelay);
