#import <Foundation/Foundation.h>

NSDictionary *IKPlaybackSignals(NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents);
void IKWritePlaybackSignals(NSURL *directory, NSString *bundle, NSDictionary *info, NSUInteger accessEvents, NSUInteger jumpEvents);
