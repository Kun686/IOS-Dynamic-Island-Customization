#import <Foundation/Foundation.h>

NSArray<NSArray<NSString *> *> *IKPublishedLyricPaths(NSDictionary *info);
NSDictionary *IKPlaybackSignals(NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents);
void IKWritePlaybackSignals(NSURL *directory, NSString *bundle, NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents, NSDictionary *result);
