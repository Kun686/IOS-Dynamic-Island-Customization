#import "IKLocalAvatar.h"
#import "IKPrefs.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

static const unsigned long long IKMaxAvatarSourceBytes = 16 * 1024 * 1024;

@implementation IKLocalAvatar {
    NSURL *_directory;
}

+ (instancetype)shared {
    static IKLocalAvatar *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *root = [NSURL fileURLWithPath:IKDataDir isDirectory:YES];
        store = [[self alloc] initWithDirectory:[root URLByAppendingPathComponent:@"WeChatAvatars" isDirectory:YES]];
    });
    return store;
}

- (instancetype)initWithDirectory:(NSURL *)directory {
    if ((self = [super init])) _directory = [directory copy];
    return self;
}

- (NSURL *)fileForTitle:(NSString *)title {
    NSString *key = [[title precomposedStringWithCanonicalMapping] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!key.length || key.length > 256 || [@[@"微信", @"wechat", @"weixin"] containsObject:key.lowercaseString]) return nil;
    NSData *bytes = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *filename = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [filename appendFormat:@"%02x", digest[i]];
    return [_directory URLByAppendingPathComponent:[filename stringByAppendingPathExtension:@"png"]];
}

- (NSURL *)imageForTitle:(NSString *)title {
    NSURL *file = [self fileForTitle:title];
    return file && [NSFileManager.defaultManager isReadableFileAtPath:file.path] ? file : nil;
}

static NSString *IKErrorText(NSError *error) {
    NSError *posix = error.userInfo[NSUnderlyingErrorKey];
    NSString *text = error.localizedDescription ?: @"未知错误";
    if ([posix.domain isEqualToString:NSPOSIXErrorDomain]) {
        text = [text stringByAppendingFormat:@"，%s", strerror((int)posix.code)];
    }
    return text;
}

- (NSString *)setImage:(NSURL *)source forTitle:(NSString *)title {
    NSURL *dest = [self fileForTitle:title];
    if (!dest) return @"请输入具体会话的通知标题（最多 256 个字符）";
    if (!source) {
        NSError *error = nil;
        if ([NSFileManager.defaultManager removeItemAtURL:dest error:&error] || error.code == NSFileNoSuchFileError) return nil;
        return [NSString stringWithFormat:@"移除头像失败：%@（%@）", IKErrorText(error), dest.path];
    }
    if (!source.isFileURL) return @"图片无法读取：不是本机文件";
    NSNumber *regular = nil, *size = nil;
    NSError *error = nil;
    if (![source getResourceValue:&regular forKey:NSURLIsRegularFileKey error:&error] ||
        ![source getResourceValue:&size forKey:NSURLFileSizeKey error:&error])
        return [NSString stringWithFormat:@"图片无法读取：%@", IKErrorText(error)];
    if (!regular.boolValue) return @"请选择一个图片文件";
    if (size.unsignedLongLongValue > IKMaxAvatarSourceBytes) return @"请选择小于等于 16 MB 的图片文件";
    CGImageSourceRef image = CGImageSourceCreateWithURL((__bridge CFURLRef)source, NULL);
    if (!image) return @"图片无法读取";
    NSString *message = [self storeImageSource:image at:dest];
    CFRelease(image);
    return message;
}

- (NSString *)setImageData:(NSData *)data forTitle:(NSString *)title {
    NSURL *dest = [self fileForTitle:title];
    if (!dest) return @"请输入具体会话的通知标题（最多 256 个字符）";
    if (!data.length) return @"没有读到图片数据";
    if (data.length > IKMaxAvatarSourceBytes) return @"请选择小于等于 16 MB 的图片";
    CGImageSourceRef image = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!image) return @"图片无法读取";
    NSString *message = [self storeImageSource:image at:dest];
    CFRelease(image);
    return message;
}

// 缩成最长边 160 像素的 PNG 再原子写入。任何一步失败都保留原来绑定的那张
- (NSString *)storeImageSource:(CGImageSourceRef)image at:(NSURL *)dest {
    NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES, (__bridge id)kCGImageSourceThumbnailMaxPixelSize:@160};
    CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(image, 0, (__bridge CFDictionaryRef)options);
    if (!thumb) return @"图片无法解码";
    NSMutableData *png = [NSMutableData data];
    CGImageDestinationRef output = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
    BOOL encoded = NO;
    if (output) {
        CGImageDestinationAddImage(output, thumb, NULL);
        encoded = CGImageDestinationFinalize(output);
        CFRelease(output);
    }
    CGImageRelease(thumb);
    if (!encoded) return @"保存头像失败：图片转成 PNG 失败";
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil error:&error])
        return [NSString stringWithFormat:@"保存头像失败：无法创建目录 %@（%@）", _directory.path, IKErrorText(error)];
    if (![png writeToURL:dest options:NSDataWritingAtomic error:&error])
        return [NSString stringWithFormat:@"保存头像失败：无法写入 %@（%@）", _directory.path, IKErrorText(error)];
    return nil;
}
@end
