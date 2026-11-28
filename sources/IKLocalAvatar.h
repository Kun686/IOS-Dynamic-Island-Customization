#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 保存（或移除）头像的结果。
// saved=NO：没有保存，原来绑定的那张保持不变，message 是失败原因。
// saved=YES：已经保存；message 非空时是提示（例如“图片看起来是全黑的”）。
// detail 是一行自证信息：来源格式和尺寸、走的哪条解码路径、结果尺寸、抽样得到的亮度和不透明比例。
// 真机上“头像是黑的”时，看这一行就能分清是图片本身黑，还是存下来的图正常、黑在显示那一步
@interface IKAvatarSaveResult : NSObject
@property (nonatomic, readonly) BOOL saved;
@property (nonatomic, readonly, copy, nullable) NSString *message;
@property (nonatomic, readonly, copy, nullable) NSString *detail;
@end

@interface IKLocalAvatar : NSObject
+ (instancetype)shared;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (nullable NSURL *)imageForTitle:(NSString *)title;
// A nil source removes the binding. Returns an error suitable for display.
- (nullable NSString *)setImage:(nullable NSURL *)source forTitle:(NSString *)title NS_SWIFT_NAME(setImage(_:for:));
// 相册选来的图片数据（HEIC、JPEG、PNG 等），同样缩成 160 像素的 PNG 保存。返回错误说明
- (nullable NSString *)setImageData:(NSData *)data forTitle:(NSString *)title NS_SWIFT_NAME(setImageData(_:for:));

// 上面两个接口只能表达“成功 / 失败”。下面两个做同样的事，另外能返回“成功但有提示”和自证信息。
// 文件先整个读进内存（最多 16 MB，直接读不到时用 NSFileCoordinator 再读一次）再解码；
// 解码结果统一重绘成 8 位 sRGB 的 RGBA 位图（最长边 160 像素）后编码成 PNG。
// 结果全透明时不保存；系统缩略图接口给出全黑而整图解码不是全黑时用整图解码的结果；
// 两条路都全黑时照常保存，message 里注明。source 传 nil 表示移除绑定
- (IKAvatarSaveResult *)saveImageAtURL:(nullable NSURL *)source forTitle:(NSString *)title NS_SWIFT_NAME(saveImage(at:for:));
- (IKAvatarSaveResult *)saveImageData:(NSData *)data forTitle:(NSString *)title NS_SWIFT_NAME(saveImageData(_:for:));

// 一行文字描述一张图片解码后的样子：“160×120 平均亮度 43% 最亮 98% 不透明 100%”。解码不了返回 nil。
// 设置页预览和悬浮进程读到头像文件后各记一次，两边对得上就说明文件本身没问题
+ (nullable NSString *)describeImageData:(NSData *)data;
@end
NS_ASSUME_NONNULL_END
