#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface IKLocalAvatar : NSObject
+ (instancetype)shared;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (nullable NSURL *)imageForTitle:(NSString *)title;
// A nil source removes the binding. Returns an error suitable for display.
- (nullable NSString *)setImage:(nullable NSURL *)source forTitle:(NSString *)title NS_SWIFT_NAME(setImage(_:for:));
@end
NS_ASSUME_NONNULL_END
