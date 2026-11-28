#import "IKLocalAvatar.h"
#import "IKPrefs.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <fcntl.h>
#import <sys/stat.h>

static const unsigned long long IKMaxAvatarSourceBytes = 16 * 1024 * 1024;
// 保存下来的头像最长边
static const size_t IKAvatarMaxPixel = 160;
// 整图解码兜底只处理这么多像素以内的图，再大就不走这条路，免得一次占用几百 MB 内存
static const double IKAvatarMaxDecodedPixels = 50e6;

@interface IKAvatarSaveResult ()
@property (nonatomic, readwrite) BOOL saved;
@property (nonatomic, readwrite, copy, nullable) NSString *message;
@property (nonatomic, readwrite, copy, nullable) NSString *detail;
@end

@implementation IKAvatarSaveResult
+ (instancetype)saved:(BOOL)saved message:(NSString *)message detail:(NSString *)detail {
    IKAvatarSaveResult *result = [self new];
    result.saved = saved;
    result.message = message;
    result.detail = detail;
    return result;
}
+ (instancetype)failure:(NSString *)message {
    return [self saved:NO message:message detail:nil];
}
@end

#pragma mark 位图：重绘、抽样

// 对一张 8 位 sRGB RGBA（预乘）位图的抽样结果。位图最多 160×160，所以每个像素都看
typedef struct {
    size_t width, height;
    double meanLuma;      // 叠在黑底上的平均亮度，0…1
    unsigned maxChannel;  // 叠在黑底上最亮的一个颜色分量，0…255
    unsigned maxAlpha;    // 最不透明的像素，0…255
    double opaque;        // 看得见（alpha 大于 8）的像素占比，0…1
} IKAvatarStats;

// 全透明：没有一个像素看得见。全黑：有看得见的像素，但叠在深色底上没有一处亮过 24/255
//（解码失败得到的是整片 0；透明底上的纯黑图案也算，它在岛上同样是一团黑）
static BOOL IKStatsTransparent(IKAvatarStats s) { return s.maxAlpha <= 8; }
static BOOL IKStatsBlack(IKAvatarStats s) { return !IKStatsTransparent(s) && s.maxChannel <= 24; }
static BOOL IKStatsUsable(IKAvatarStats s) { return !IKStatsTransparent(s) && !IKStatsBlack(s); }

static IKAvatarStats IKMeasureBitmap(CGContextRef bitmap) {
    IKAvatarStats s = {0};
    if (!bitmap) return s;
    const uint8_t *base = CGBitmapContextGetData(bitmap);
    size_t width = CGBitmapContextGetWidth(bitmap), height = CGBitmapContextGetHeight(bitmap);
    size_t stride = CGBitmapContextGetBytesPerRow(bitmap);
    if (!base || !width || !height) return s;
    s.width = width;
    s.height = height;
    double luma = 0;
    size_t visible = 0;
    for (size_t y = 0; y < height; y++) {
        const uint8_t *p = base + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned r = p[0], g = p[1], b = p[2], a = p[3];
            unsigned top = MAX(r, MAX(g, b));
            if (top > s.maxChannel) s.maxChannel = top;
            if (a > s.maxAlpha) s.maxAlpha = a;
            if (a > 8) visible++;
            luma += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }
    }
    s.meanLuma = luma / (255.0 * (double)(width * height));
    s.opaque = (double)visible / (double)(width * height);
    return s;
}

static NSString *IKStatsText(IKAvatarStats s) {
    return [NSString stringWithFormat:@"平均亮度 %.0f%% 最亮 %.0f%% 不透明 %.0f%%",
            s.meanLuma * 100, s.maxChannel / 255.0 * 100, s.opaque * 100];
}

// 把 image 重绘进一张新的 8 位 sRGB RGBA 位图，最长边不超过 maxPixel（小图不放大）。
// 不管来源是 HEIC、HDR、广色域、16 位、CMYK 还是灰度，画完都是同一种最普通的格式。
// orientation 是 EXIF 方向（1…8）：image 是没摆正的原始像素时传它，已经摆正的传 1
static CGContextRef IKCreateAvatarBitmap(CGImageRef image, int orientation, size_t maxPixel) CF_RETURNS_RETAINED {
    size_t rawWidth = image ? CGImageGetWidth(image) : 0, rawHeight = image ? CGImageGetHeight(image) : 0;
    if (!rawWidth || !rawHeight) return NULL;
    BOOL turned = orientation >= 5 && orientation <= 8;   // 这四种方向要转 90 度，宽高互换
    double shownWidth = turned ? rawHeight : rawWidth, shownHeight = turned ? rawWidth : rawHeight;
    double scale = MIN(1.0, (double)maxPixel / MAX(shownWidth, shownHeight));
    size_t width = (size_t)MAX(1.0, round(shownWidth * scale)), height = (size_t)MAX(1.0, round(shownHeight * scale));

    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, width * 4, srgb,
                                                (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(srgb);
    if (!bitmap) return NULL;
    CGContextClearRect(bitmap, CGRectMake(0, 0, width, height));
    CGContextSetInterpolationQuality(bitmap, kCGInterpolationHigh);

    // 原始像素画在 (0,0,w,h)，再用变换摆到位。坐标原点在左下、y 向上；
    // 变换的六个数依次是 a b c d tx ty，即 X = a·x + c·y + tx，Y = b·x + d·y + ty
    CGFloat w = turned ? height : width, h = turned ? width : height;
    CGAffineTransform t = CGAffineTransformIdentity;
    switch (orientation) {
        case 2: t = CGAffineTransformMake(-1, 0, 0, 1, w, 0); break;    // 左右镜像
        case 3: t = CGAffineTransformMake(-1, 0, 0, -1, w, h); break;   // 转 180 度
        case 4: t = CGAffineTransformMake(1, 0, 0, -1, 0, h); break;    // 上下镜像
        case 5: t = CGAffineTransformMake(0, -1, -1, 0, h, w); break;   // 沿左上到右下的对角线翻转
        case 6: t = CGAffineTransformMake(0, -1, 1, 0, 0, w); break;    // 顺时针转 90 度（竖拍的照片）
        case 7: t = CGAffineTransformMake(0, 1, 1, 0, 0, 0); break;     // 沿右上到左下的对角线翻转
        case 8: t = CGAffineTransformMake(0, 1, -1, 0, h, 0); break;    // 逆时针转 90 度
        default: break;
    }
    CGContextConcatCTM(bitmap, t);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, w, h), image);
    return bitmap;
}

#pragma mark 解码

// 来源图片的格式、尺寸、位深、颜色模型、方向，写进自证信息；同时取出方向和像素尺寸
static NSString *IKDescribeSource(CGImageSourceRef source, int *orientation, double *pixelWidth, double *pixelHeight) {
    NSDictionary *p = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
    int o = [p[(__bridge id)kCGImagePropertyOrientation] intValue];
    *orientation = (o >= 1 && o <= 8) ? o : 1;
    *pixelWidth = [p[(__bridge id)kCGImagePropertyPixelWidth] doubleValue];
    *pixelHeight = [p[(__bridge id)kCGImagePropertyPixelHeight] doubleValue];
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@ %.0f×%.0f", type ?: @"未知格式", *pixelWidth, *pixelHeight];
    id depth = p[(__bridge id)kCGImagePropertyDepth], model = p[(__bridge id)kCGImagePropertyColorModel];
    if (depth) [text appendFormat:@" %@位", depth];
    if (model) [text appendFormat:@" %@", model];
    if ([p[(__bridge id)kCGImagePropertyHasAlpha] boolValue]) [text appendString:@" 带透明"];
    if (*orientation != 1) [text appendFormat:@" 方向%d", *orientation];
    return text;
}

// 路径一：系统的缩略图接口（自己按方向摆正、缩小），再重绘成统一格式
static CGContextRef IKBitmapViaThumbnail(CGImageSourceRef source) CF_RETURNS_RETAINED {
    NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (__bridge id)kCGImageSourceThumbnailMaxPixelSize:@(IKAvatarMaxPixel)};
    CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    if (!thumb) return NULL;
    CGContextRef bitmap = IKCreateAvatarBitmap(thumb, 1, IKAvatarMaxPixel);
    CGImageRelease(thumb);
    return bitmap;
}

// 路径二：把整张图解码出来，自己按方向摆正、缩小。和路径一不共用缩略图那套代码。
// 先要求用软件解码（kCGImageSourceUseHardwareAcceleration 是 ImageIO 认的一个未公开选项，
// 不认识它的系统会直接忽略）：硬件解码器拿不到时缩略图接口可能给出一张全黑的图。软件解码不出来再按默认方式解一次
static CGContextRef IKBitmapViaFullImage(CGImageSourceRef source, int orientation, double pixelWidth, double pixelHeight) CF_RETURNS_RETAINED {
    if (pixelWidth * pixelHeight > IKAvatarMaxDecodedPixels) return NULL;
    // 很大的图让解码器按 2、4、8 倍抽样（JPEG、HEIF、PNG、TIFF 支持，其余格式照原尺寸解），抽样后仍不小于目标的两倍
    int factor = 1;
    while (factor < 8 && MAX(pixelWidth, pixelHeight) / (factor * 2) >= IKAvatarMaxPixel * 2) factor *= 2;
    for (int attempt = 0; attempt < 2; attempt++) {
        NSMutableDictionary *options = [@{(__bridge id)kCGImageSourceShouldCache:@YES} mutableCopy];
        if (factor > 1) options[(__bridge id)kCGImageSourceSubsampleFactor] = @(factor);
        if (attempt == 0) options[@"kCGImageSourceUseHardwareAcceleration"] = @NO;
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        if (!image) continue;
        CGContextRef bitmap = IKCreateAvatarBitmap(image, orientation, IKAvatarMaxPixel);
        CGImageRelease(image);
        if (bitmap) return bitmap;
    }
    return NULL;
}

static NSData *IKEncodePNG(CGContextRef bitmap) {
    CGImageRef image = CGBitmapContextCreateImage(bitmap);
    if (!image) return nil;
    NSMutableData *png = [NSMutableData data];
    CGImageDestinationRef output = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
    BOOL encoded = NO;
    if (output) {
        CGImageDestinationAddImage(output, image, NULL);
        encoded = CGImageDestinationFinalize(output);
        CFRelease(output);
    }
    CGImageRelease(image);
    return encoded && png.length ? png : nil;
}

// 把一份图片数据解码、摆正后量一遍。尺寸报图片自己的像素尺寸
static BOOL IKMeasureImageData(NSData *data, IKAvatarStats *stats) {
    if (!data.length) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return NO;
    BOOL measured = NO;
    if (CGImageSourceGetCount(source) > 0) {
        int orientation = 1;
        double pixelWidth = 0, pixelHeight = 0;
        IKDescribeSource(source, &orientation, &pixelWidth, &pixelHeight);
        CGContextRef bitmap = IKBitmapViaFullImage(source, orientation, pixelWidth, pixelHeight);
        if (bitmap) {
            *stats = IKMeasureBitmap(bitmap);
            BOOL turned = orientation >= 5;
            if (pixelWidth > 0 && pixelHeight > 0) {
                stats->width = (size_t)(turned ? pixelHeight : pixelWidth);
                stats->height = (size_t)(turned ? pixelWidth : pixelHeight);
            }
            measured = YES;
            CGContextRelease(bitmap);
        }
    }
    CFRelease(source);
    return measured;
}

#pragma mark 读文件

static NSString *IKErrorText(NSError *error) {
    NSError *posix = error.userInfo[NSUnderlyingErrorKey];
    NSString *text = error.localizedDescription ?: @"未知错误";
    if ([posix.domain isEqualToString:NSPOSIXErrorDomain]) {
        text = [text stringByAppendingFormat:@"，%s", strerror((int)posix.code)];
    }
    if (error) text = [text stringByAppendingFormat:@" [%@ %ld]", error.domain, (long)error.code];
    return text;
}

// 把一个普通文件整个读进内存，之后解码不再碰这个文件（不用内存映射，也不让解码器按需回头读）。
// 返回 nil 时 failure 是原因；final 为 YES 表示换一种读法也没用（不是普通文件、超过 16 MB）
static NSData *IKReadWholeFile(NSURL *url, NSString **failure, BOOL *final) {
    *final = NO;
    const char *path = url.fileSystemRepresentation;
    struct stat st;
    if (stat(path, &st) != 0) {
        *failure = [NSString stringWithFormat:@"%s [errno %d]", strerror(errno), errno];
        return nil;
    }
    if (!S_ISREG(st.st_mode)) {
        *final = YES;
        *failure = @"请选择一个图片文件";
        return nil;
    }
    if ((unsigned long long)st.st_size > IKMaxAvatarSourceBytes) {
        *final = YES;
        *failure = @"请选择小于等于 16 MB 的图片文件";
        return nil;
    }
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        *failure = [NSString stringWithFormat:@"%s [errno %d]", strerror(errno), errno];
        return nil;
    }
    // 最多读 16 MB 加 1 字节：多出来的这一个字节说明文件在读的过程中变大、超限了
    NSMutableData *data = [NSMutableData dataWithCapacity:(NSUInteger)st.st_size];
    uint8_t buffer[64 * 1024];
    int failed = 0;
    while (data.length <= IKMaxAvatarSourceBytes) {
        ssize_t got = read(fd, buffer, sizeof(buffer));
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) { failed = errno; break; }
        if (got == 0) break;
        [data appendBytes:buffer length:(NSUInteger)got];
    }
    close(fd);
    if (failed) {
        *failure = [NSString stringWithFormat:@"%s [errno %d]", strerror(failed), failed];
        return nil;
    }
    if (data.length > IKMaxAvatarSourceBytes) {
        *final = YES;
        *failure = @"请选择小于等于 16 MB 的图片文件";
        return nil;
    }
    if (!data.length) {
        *failure = @"文件是空的";
        return nil;
    }
    return data;
}

// 先直接读；读不到或读到空文件（文件还没从 iCloud 下载下来、属于别的 App 的文件提供方）时，
// 让系统协调一次读取再试
static NSData *IKReadImageFile(NSURL *source, NSString **failure) {
    BOOL final = NO;
    NSString *direct = nil;
    NSData *data = IKReadWholeFile(source, &direct, &final);
    if (data || final) {
        *failure = direct;
        return data;
    }
    __block NSData *coordinated = nil;
    __block NSString *inner = nil;
    NSError *error = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:source options:NSFileCoordinatorReadingWithoutChanges error:&error
                                 byAccessor:^(NSURL *actual) {
        BOOL ignored = NO;
        NSString *reason = nil;
        coordinated = IKReadWholeFile(actual, &reason, &ignored);
        inner = reason;
    }];
    if (coordinated) return coordinated;
    NSString *second = inner ?: (error ? IKErrorText(error) : @"没有读到内容");
    *failure = [direct isEqualToString:second] ? direct
        : [NSString stringWithFormat:@"直接读取：%@；协调读取：%@", direct, second];
    return nil;
}

#pragma mark -

@interface IKLocalAvatar ()
// 只给宿主测试用（通过 KVC 设置）：1 当作缩略图接口没有结果，2 当作缩略图接口给出了一张全黑的图。
// 真机上的“全黑”在电脑上造不出来，用它走到整图解码那条路
@property (nonatomic) NSInteger simulatedThumbnailFault;
@end

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

+ (NSString *)describeImageData:(NSData *)data {
    IKAvatarStats stats;
    if (!IKMeasureImageData(data, &stats)) return nil;
    return [NSString stringWithFormat:@"%zu×%zu %@", stats.width, stats.height, IKStatsText(stats)];
}

#pragma mark 旧接口：nil 表示成功

- (NSString *)setImage:(NSURL *)source forTitle:(NSString *)title {
    IKAvatarSaveResult *result = [self saveImageAtURL:source forTitle:title];
    return result.saved ? nil : (result.message ?: @"保存头像失败");
}

- (NSString *)setImageData:(NSData *)data forTitle:(NSString *)title {
    IKAvatarSaveResult *result = [self saveImageData:data forTitle:title];
    return result.saved ? nil : (result.message ?: @"保存头像失败");
}

#pragma mark 新接口

- (IKAvatarSaveResult *)saveImageAtURL:(NSURL *)source forTitle:(NSString *)title {
    NSURL *dest = [self fileForTitle:title];
    if (!dest) return [IKAvatarSaveResult failure:@"请输入具体会话的通知标题（最多 256 个字符）"];
    if (!source) {
        NSError *error = nil;
        if ([NSFileManager.defaultManager removeItemAtURL:dest error:&error] || error.code == NSFileNoSuchFileError)
            return [IKAvatarSaveResult saved:YES message:nil detail:nil];
        return [IKAvatarSaveResult failure:[NSString stringWithFormat:@"移除头像失败：%@（%@）", IKErrorText(error), dest.path]];
    }
    if (!source.isFileURL) return [IKAvatarSaveResult failure:@"图片无法读取：不是本机文件"];
    NSString *failure = nil;
    NSData *data = IKReadImageFile(source, &failure);
    if (!data) {
        BOOL plain = [failure hasPrefix:@"请选择"];
        return [IKAvatarSaveResult failure:plain ? failure : [NSString stringWithFormat:@"图片无法读取：%@", failure ?: @"未知错误"]];
    }
    return [self storeImageData:data at:dest];
}

- (IKAvatarSaveResult *)saveImageData:(NSData *)data forTitle:(NSString *)title {
    NSURL *dest = [self fileForTitle:title];
    if (!dest) return [IKAvatarSaveResult failure:@"请输入具体会话的通知标题（最多 256 个字符）"];
    if (!data.length) return [IKAvatarSaveResult failure:@"没有读到图片数据"];
    if (data.length > IKMaxAvatarSourceBytes) return [IKAvatarSaveResult failure:@"请选择小于等于 16 MB 的图片"];
    return [self storeImageData:data at:dest];
}

// 解码 → 重绘成 8 位 sRGB RGBA（最长边 160）→ 自检 → 编码 PNG → 回读校验 → 原子写入 → 再回读。
// 任何一步失败都保留原来绑定的那张
- (IKAvatarSaveResult *)storeImageData:(NSData *)data at:(NSURL *)dest {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source || CGImageSourceGetCount(source) == 0) {
        if (source) CFRelease(source);
        return [IKAvatarSaveResult failure:[NSString stringWithFormat:@"图片无法读取：不是能识别的图片格式（%lu 字节）",
                                            (unsigned long)data.length]];
    }
    int orientation = 1;
    double pixelWidth = 0, pixelHeight = 0;
    NSString *origin = IKDescribeSource(source, &orientation, &pixelWidth, &pixelHeight);

    // 路径一：缩略图接口
    CGContextRef thumb = self.simulatedThumbnailFault == 1 ? NULL : IKBitmapViaThumbnail(source);
    if (thumb && self.simulatedThumbnailFault == 2) {
        CGContextSetRGBFillColor(thumb, 0, 0, 0, 1);
        CGContextFillRect(thumb, CGRectMake(0, 0, 1e6, 1e6));
    }
    IKAvatarStats thumbStats = IKMeasureBitmap(thumb);
    // 路径二：只在路径一没有结果、全黑或全透明时才走
    CGContextRef full = NULL;
    IKAvatarStats fullStats = {0};
    if (!thumb || !IKStatsUsable(thumbStats)) {
        full = IKBitmapViaFullImage(source, orientation, pixelWidth, pixelHeight);
        fullStats = IKMeasureBitmap(full);
    }
    CFRelease(source);

    NSString *thumbState = !thumb ? @"没有结果" : IKStatsTransparent(thumbStats) ? @"全透明" : IKStatsBlack(thumbStats) ? @"全黑" : @"正常";
    CGContextRef chosen = NULL;
    IKAvatarStats stats = {0};
    NSString *route = nil, *warning = nil, *failure = nil;
    if (thumb && IKStatsUsable(thumbStats)) {
        chosen = thumb; stats = thumbStats; route = @"缩略图接口";
    } else if (full && IKStatsUsable(fullStats)) {
        chosen = full; stats = fullStats;
        route = [NSString stringWithFormat:@"整图解码（缩略图接口%@）", thumbState];
    } else if (thumb && IKStatsBlack(thumbStats)) {
        chosen = thumb; stats = thumbStats;
        route = [NSString stringWithFormat:@"缩略图接口（整图解码%@）", !full ? @"没有结果" : IKStatsBlack(fullStats) ? @"也是全黑" : @"全透明"];
        warning = @"图片看起来是全黑的";
    } else if (full && IKStatsBlack(fullStats)) {
        chosen = full; stats = fullStats;
        route = [NSString stringWithFormat:@"整图解码（缩略图接口%@）", thumbState];
        warning = @"图片看起来是全黑的";
    } else if (thumb || full) {
        failure = [NSString stringWithFormat:@"图片是全透明的，没有保存（来源 %@）", origin];
    } else {
        failure = [NSString stringWithFormat:@"图片无法解码（来源 %@）", origin];
    }

    NSData *png = chosen ? IKEncodePNG(chosen) : nil;
    if (thumb) CGContextRelease(thumb);
    if (full) CGContextRelease(full);
    if (failure) return [IKAvatarSaveResult failure:failure];
    if (!png) return [IKAvatarSaveResult failure:@"保存头像失败：图片转成 PNG 失败"];

    // 自证：把刚编码出来的 PNG 再解码量一遍，要和编码前的位图对得上
    IKAvatarStats check = {0};
    if (!IKMeasureImageData(png, &check) || check.width != stats.width || check.height != stats.height ||
        fabs(check.meanLuma - stats.meanLuma) > 0.02 || fabs(check.opaque - stats.opaque) > 0.02) {
        return [IKAvatarSaveResult failure:[NSString stringWithFormat:@"保存头像失败：PNG 回读校验不一致（编码前 %zu×%zu %@，回读 %zu×%zu %@）",
                                            stats.width, stats.height, IKStatsText(stats), check.width, check.height, IKStatsText(check)]];
    }

    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil error:&error])
        return [IKAvatarSaveResult failure:[NSString stringWithFormat:@"保存头像失败：无法创建目录 %@（%@）", _directory.path, IKErrorText(error)]];
    if (![png writeToURL:dest options:NSDataWritingAtomic error:&error])
        return [IKAvatarSaveResult failure:[NSString stringWithFormat:@"保存头像失败：无法写入 %@（%@）", _directory.path, IKErrorText(error)]];
    NSData *stored = [NSData dataWithContentsOfURL:dest options:0 error:&error];
    if (![stored isEqualToData:png])
        return [IKAvatarSaveResult failure:[NSString stringWithFormat:@"保存头像失败：写入后读回来的内容不一致（写入 %lu 字节，读到 %lu 字节）",
                                            (unsigned long)png.length, (unsigned long)stored.length]];

    NSString *detail = [NSString stringWithFormat:@"来源 %@ → 头像 %zu×%zu，%@，%@，PNG %lu 字节已回读校验",
                        origin, stats.width, stats.height, route, IKStatsText(stats), (unsigned long)png.length];
    return [IKAvatarSaveResult saved:YES message:warning detail:detail];
}
@end
