#import <Foundation/Foundation.h>

// Register on the main queue. A background launch waits for the first foreground activation.
void IKWhenPlayerIsActive(dispatch_block_t start);
void IKReadPlaybackInfo(dispatch_queue_t receiver, void (^consume)(NSDictionary *info, NSString *issue));
NSString *IKRecordPlaybackPhase(NSURL *directory, NSString *bundle, NSString *previous, NSString *phase);
NSArray<NSArray<NSString *> *> *IKPublishedLyricPaths(NSDictionary *info);
NSDictionary *IKPlaybackSignals(NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents);
void IKWritePlaybackSignals(NSURL *directory, NSString *bundle, NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents, NSDictionary *result);
