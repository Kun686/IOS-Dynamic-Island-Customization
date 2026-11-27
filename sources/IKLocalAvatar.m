#import "IKLocalAvatar.h"
#import "IKPrefs.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

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

- (NSString *)setImage:(NSURL *)source forTitle:(NSString *)title {
    NSURL *dest = [self fileForTitle:title];
    if (!dest) return @"请输入具体会话的通知标题（最多 256 个字符）";
    NSFileManager *fm = NSFileManager.defaultManager;
    if (!source) {
        NSError *error = nil;
        if ([fm removeItemAtURL:dest error:&error] || error.code == NSFileNoSuchFileError) return nil;
        return @"移除头像失败";
    }
    NSNumber *regular = nil, *size = nil;
    if (!source.isFileURL || ![source getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] || !regular.boolValue ||
        ![source getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > 16*1024*1024)
        return @"请选择小于等于 16 MB 的图片文件";
    CGImageSourceRef image = CGImageSourceCreateWithURL((__bridge CFURLRef)source, NULL);
    if (!image) return @"图片无法读取";
    NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES, (__bridge id)kCGImageSourceThumbnailMaxPixelSize:@160};
    CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(image, 0, (__bridge CFDictionaryRef)options);
    CFRelease(image);
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
    if (!encoded || ![fm createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil error:nil] ||
        ![png writeToURL:dest options:NSDataWritingAtomic error:nil]) return @"保存头像失败";
    return nil;
}
@end
