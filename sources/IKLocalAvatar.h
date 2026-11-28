#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface IKLocalAvatar : NSObject
+ (instancetype)shared;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (nullable NSURL *)imageForTitle:(NSString *)title;
// A nil source removes the binding. Returns an error suitable for display.
- (nullable NSString *)setImage:(nullable NSURL *)source forTitle:(NSString *)title NS_SWIFT_NAME(setImage(_:for:));
// 相册选来的图片数据（HEIC、JPEG、PNG 等），同样缩成 160 像素的 PNG 保存。返回错误说明
- (nullable NSString *)setImageData:(NSData *)data forTitle:(NSString *)title NS_SWIFT_NAME(setImageData(_:for:));
@end
NS_ASSUME_NONNULL_END
