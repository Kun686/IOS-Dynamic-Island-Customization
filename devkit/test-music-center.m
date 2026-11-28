// Exercise the real HUD and settings entry points against fixture media events and local directories.
#import "IKPrefs.h"
#import "MediaRemote.h"
#import "IKMusicCenter.h"
#import "IKLocalAvatar.h"
#import <ImageIO/ImageIO.h>
#include <sys/stat.h>

static NSString *store, *bundle;
static NSDictionary *metadata;
static BOOL playing, delayBundle;
static void (^bundleReply)(NSString *);
static NSMutableArray<NSString *> *messages;

@implementation UIImage
+ (instancetype)imageWithData:(NSData *)data { return data.length ? [self new] : nil; }
@end
@implementation IKPrefs
+ (void)log:(NSString *)message { [messages addObject:message]; }
@end

@interface FixtureApp : NSObject
@property(nonatomic, strong) NSURL *dataContainerURL;
@end
@implementation FixtureApp
+ (instancetype)applicationProxyForIdentifier:(NSString *)bid {
    FixtureApp *app = [self new];
    app.dataContainerURL = [NSURL fileURLWithPath:[store stringByAppendingPathComponent:bid] isDirectory:YES];
    return app;
}
@end

// Only the platform callbacks, container locator, image decode and log sink are replaced.
#define NSClassFromString(name) FixtureApp.class
#undef IKDataDir
#define IKDataDir store
#import "../sources/IKMusicCenter.m"
#undef NSClassFromString
#define MRKEY(name) CFStringRef kMRMediaRemoteNowPlayingInfo##name = CFSTR(#name)
MRKEY(Title); MRKEY(Artist); MRKEY(Album); MRKEY(Duration); MRKEY(ElapsedTime); MRKEY(ArtworkData);
MRKEY(Timestamp); MRKEY(PlaybackRate); MRKEY(ExternalContentIdentifier); MRKEY(UniqueIdentifier); MRKEY(QueueIndex);
NSString *kMRMediaRemoteNowPlayingInfoDidChangeNotification = @"info";
NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification = @"playing";
NSString *kMRMediaRemoteNowPlayingApplicationDidChangeNotification = @"application";
void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t q) {}
void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t q, void (^reply)(CFDictionaryRef)) { reply((__bridge CFDictionaryRef)metadata); }
void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t q, void (^reply)(Boolean)) { reply(playing); }
void MRMediaRemoteGetNowPlayingApplicationDisplayID(dispatch_queue_t q, void (^reply)(NSString *)) {
    if (delayBundle) bundleReply = reply;
    else reply(bundle);
}

static int count;
static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr,"FAIL %s\n",message); exit(1); }
    count++;
}

static NSDictionary *settingsTarget(void) {
    __block NSDictionary *result;
    [IKMusicCenter requestImportTarget:^(NSDictionary *target) { result = target; }];
    return result;
}

static void testPublishedHandoff(IKMusicCenter *center, NSString *fixtures, NSString *player, NSString *directory) {
    [center clearPlayerScope];
    bundle = player;
    playing = NO;
    NSString *path = IKPlayerLyricsPath(bundle);
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *source = [[fixtures stringByAppendingPathComponent:directory] stringByAppendingPathComponent:@"custom-output.plist"];
    check([[NSData dataWithContentsOfFile:source] writeToFile:path atomically:YES], "deliver unmodified producer snapshot");
    NSMutableDictionary *event = [@{@"ExternalContentIdentifier":@"fixture", @"Title":@"测试录音", @"Artist":@"测试歌手",
                                    @"Duration":@98, @"QueueIndex":@1, @"ElapsedTime":@2.499} mutableCopy];
    metadata = event;
    [center refresh];
    check([center.bridgeLyric isEqual:@"甲"] && [settingsTarget()[@"mode"] isEqual:@"播放器时间轴"], "actual adapter snapshot at 2.499 seconds");
    event[@"ElapsedTime"] = @2.5;
    [center refresh];
    check([center.bridgeLyric isEqual:@"乙"] && center.bridgeLyricElapsed == 0, "HUD switches at 2.500 seconds");
    check([messages containsObject:[NSString stringWithFormat:@"lyrics timeline app=%@ source=publishedField key=player.syncedLyrics lines=2",bundle]],
          "HUD records the actual field from the adapter");

    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithContentsOfFile:source];
    event[@"ExternalContentIdentifier"] = snapshot[@"externalID"] = @"second-fixture";
    event[@"QueueIndex"] = @2;
    event[@"ElapsedTime"] = @1;
    [snapshot writeToFile:path atomically:YES];
    [center refresh];
    event[@"Title"] = @"迟到的歌名";
    event[@"Artist"] = @"第一句";
    [center refresh];
    check([center.bridgeTitle isEqual:@"迟到的歌名"] && [center.bridgeLyric isEqual:@"甲"],
          "late corrected title also replaces the cached timeline title");

    [snapshot removeObjectForKey:@"externalID"];
    snapshot[@"unstablePersistentID"] = @YES;
    snapshot[@"persistentID"] = @"77";
    [snapshot writeToFile:path atomically:YES];
    metadata = @{@"UniqueIdentifier":@77, @"Title":@"别的录音", @"Artist":@"别的歌手", @"Duration":@102, @"QueueIndex":@3};
    [center refresh];
    check(!center.lyricsBridgeActive, "a stale timeline cannot match a different recording by a quarantined ID");
}

static void testSampleFolder(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[store stringByAppendingPathComponent:@"chosen-samples"] isDirectory:YES];
    NSURL *sub = [root URLByAppendingPathComponent:@"person-Lyric" isDirectory:YES];
    [fm createDirectoryAtURL:sub withIntermediateDirectories:YES attributes:nil error:nil];
    [@"[00:01]私有句" writeToURL:[root URLByAppendingPathComponent:@"artist.lrc"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSData *binary = [NSData dataWithBytes:"\0\1\2" length:3];
    [binary writeToURL:[sub URLByAppendingPathComponent:@"12345.dat"] atomically:YES];
    [binary writeToURL:[root URLByAppendingPathComponent:@"unrelated.dat"] atomically:YES];
    [fm createSymbolicLinkAtURL:[root URLByAppendingPathComponent:@"linked.lrc"] withDestinationURL:[sub URLByAppendingPathComponent:@"12345.dat"] error:nil];
    NSString *report = [IKMusicCenter sampleReportAtURL:root];
    check([report containsString:@"matched=2"] && [report containsString:@"<sample>/*.lrc bytes="] &&
          [report containsString:@"<sample>/<lyric-dir>/*.dat bytes=3 header=binary"], "report relevant shapes in a selected export folder");
    check(![report containsString:root.path] && ![report containsString:@"12345"] && ![report containsString:@"person"] &&
          ![report containsString:@"artist"] && ![report containsString:@"私有句"], "folder report redacts song names, directory names and content");
    for (int i=0; i<35; i++)
        [binary writeToURL:[root URLByAppendingPathComponent:[NSString stringWithFormat:@"sample-%d.yrc",i]] atomically:YES];
    report = [IKMusicCenter sampleReportAtURL:root];
    check([report containsString:@"matched=32"] && [report containsString:@"limited=1"], "limit reports from large folders");
    check(![IKMusicCenter sampleReportAtURL:[root URLByAppendingPathComponent:@"missing"]], "missing folder is distinct from no matches");
}

#pragma mark 备用头像：各种来源格式

// 现造一张 w×h 的测试图。kind 0：四色（左上红、右上绿、左下蓝、右下白）；1：全黑；2：全透明；
// 3：透明底上一个红色实心圆。bits 是每个颜色分量的位数（8 或 16）
static CGImageRef avatarFixture(size_t w, size_t h, size_t bits, int kind) CF_RETURNS_RETAINED {
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaPremultipliedLast | (bits == 16 ? kCGBitmapByteOrderDefault : kCGBitmapByteOrder32Big);
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, bits, 0, srgb, info);
    CGColorSpaceRelease(srgb);
    CGContextClearRect(c, CGRectMake(0, 0, w, h));
    CGFloat hw = w / 2.0, hh = h / 2.0;   // 坐标原点在左下
    if (kind == 0) {
        CGContextSetRGBFillColor(c, 1, 0, 0, 1); CGContextFillRect(c, CGRectMake(0, hh, hw, hh));
        CGContextSetRGBFillColor(c, 0, 1, 0, 1); CGContextFillRect(c, CGRectMake(hw, hh, hw, hh));
        CGContextSetRGBFillColor(c, 0, 0, 1, 1); CGContextFillRect(c, CGRectMake(0, 0, hw, hh));
        CGContextSetRGBFillColor(c, 1, 1, 1, 1); CGContextFillRect(c, CGRectMake(hw, 0, hw, hh));
    } else if (kind == 1) {
        CGContextSetRGBFillColor(c, 0, 0, 0, 1); CGContextFillRect(c, CGRectMake(0, 0, w, h));
    } else if (kind == 3) {
        CGContextSetRGBFillColor(c, 1, 0, 0, 1); CGContextFillEllipseInRect(c, CGRectMake(w * 0.25, h * 0.25, w * 0.5, h * 0.5));
    }
    CGImageRef image = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return image;
}

// 按 type 编码，orientation 写进 EXIF/TIFF 方向（1 表示不写）。编码器不支持这种格式时返回 nil
static NSData *avatarEncode(CGImageRef image, NSString *type, int orientation) {
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef out = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, (__bridge CFStringRef)type, 1, NULL);
    if (!out) return nil;
    NSDictionary *props = orientation > 1 ? @{(__bridge id)kCGImagePropertyOrientation:@(orientation)} : @{};
    CGImageDestinationAddImage(out, image, (__bridge CFDictionaryRef)props);
    BOOL ok = CGImageDestinationFinalize(out);
    CFRelease(out);
    return ok && data.length ? data : nil;
}

// 把保存下来的头像读回来：尺寸、文件属性，以及四个象限中心和正中心的颜色（R G B W K=黑 .=透明 ?=其他）
static NSString *avatarReadBack(NSURL *file, size_t *width, size_t *height, NSDictionary **props) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)file, NULL);
    if (!src) return nil;
    if (props) *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
    CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!image) return nil;
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, w * 4, srgb, (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(srgb);
    CGContextClearRect(c, CGRectMake(0, 0, w, h));
    CGContextDrawImage(c, CGRectMake(0, 0, w, h), image);
    CGImageRelease(image);
    const uint8_t *base = CGBitmapContextGetData(c);
    size_t stride = CGBitmapContextGetBytesPerRow(c);
    NSMutableString *out = [NSMutableString string];
    size_t points[5][2] = {{w / 4, h / 4}, {w * 3 / 4, h / 4}, {w / 4, h * 3 / 4}, {w * 3 / 4, h * 3 / 4}, {w / 2, h / 2}};
    for (int i = 0; i < 5; i++) {   // 内存里第 0 行是图片的最上面一行
        const uint8_t *p = base + points[i][1] * stride + points[i][0] * 4;
        unsigned r = p[0], g = p[1], b = p[2], a = p[3];
        char k = a < 16 ? '.' : (r > 200 && g > 200 && b > 200) ? 'W' : (r < 40 && g < 40 && b < 40) ? 'K'
            : (r > 170 && g < 90 && b < 90) ? 'R' : (g > 170 && r < 90 && b < 90) ? 'G' : (b > 170 && r < 90 && g < 90) ? 'B' : '?';
        [out appendFormat:@"%c", k];
    }
    CGContextRelease(c);
    *width = w; *height = h;
    return out;
}

static void testAvatarFormats(NSString *root) {
    NSFileManager *fm = NSFileManager.defaultManager;
    IKLocalAvatar *avatars = [[IKLocalAvatar alloc] initWithDirectory:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"formats"]]];
    NSString *title = @"格式会话";
    size_t w = 0, h = 0;
    NSDictionary *props = nil;

    // 方向：左上红、右上绿、左下蓝、右下白的 200×100 原始像素，按 EXIF 1…8 摆正后四个象限（左上 右上 左下 右下）应该是
    NSArray<NSString *> *expected = @[@"RGBW", @"GRWB", @"WBGR", @"BWRG", @"RBGW", @"BRWG", @"WGBR", @"GWRB"];
    CGImageRef quad = avatarFixture(200, 100, 8, 0);
    for (int o = 1; o <= 8; o++) {
        NSData *tiff = avatarEncode(quad, @"public.tiff", o);
        for (NSInteger fault = 0; fault <= 2; fault++) {
            [avatars setValue:@(fault) forKey:@"simulatedThumbnailFault"];
            IKAvatarSaveResult *r = [avatars saveImageData:tiff forTitle:title];
            NSString *seen = r.saved ? avatarReadBack([avatars imageForTitle:title], &w, &h, NULL) : nil;
            BOOL turned = o >= 5;
            BOOL ok = r.saved && !r.message && [[seen substringToIndex:4] isEqual:expected[o - 1]] &&
                w == (turned ? 80 : 160) && h == (turned ? 160 : 80) &&
                [r.detail containsString:fault == 0 ? @"缩略图接口，" : fault == 1 ? @"整图解码（缩略图接口没有结果）" : @"整图解码（缩略图接口全黑）"];
            if (!ok) fprintf(stderr, "orientation %d fault %ld: saved=%d seen=%s %zux%zu detail=%s\n", o, (long)fault, r.saved,
                             seen.UTF8String, w, h, r.detail.UTF8String);
            check(ok, "avatar is turned upright for every EXIF orientation on both decode routes");
        }
    }
    [avatars setValue:@0 forKey:@"simulatedThumbnailFault"];
    CGImageRelease(quad);

    // 大图走整图解码时按 8 倍抽样解码，方向照样摆正
    CGImageRef big = avatarFixture(3000, 2000, 8, 0);
    NSData *bigJPEG = avatarEncode(big, @"public.jpeg", 8);
    CGImageRelease(big);
    [avatars setValue:@1 forKey:@"simulatedThumbnailFault"];
    IKAvatarSaveResult *rBig = [avatars saveImageData:bigJPEG forTitle:title];
    [avatars setValue:@0 forKey:@"simulatedThumbnailFault"];
    NSString *seenBig = avatarReadBack([avatars imageForTitle:title], &w, &h, NULL);
    check(rBig.saved && [seenBig hasPrefix:@"GWRB"] && w == 107 && h == 160 && [rBig.detail containsString:@"public.jpeg 3000×2000"],
          "large JPEG on the full-decode route is subsampled and turned upright");

    // HEIC（带方向 6，相机竖拍的样子）。本机没有 HEIC 编码器时跳过
    CGImageRef photo = avatarFixture(400, 300, 8, 0);
    NSData *heic = avatarEncode(photo, @"public.heic", 6);
    if (heic) {
        NSURL *heicFile = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"photo.heic"]];
        [heic writeToURL:heicFile atomically:YES];
        IKAvatarSaveResult *r = [avatars saveImageAtURL:heicFile forTitle:title];
        NSString *seen = avatarReadBack([avatars imageForTitle:title], &w, &h, &props);
        check(r.saved && !r.message && [seen hasPrefix:@"BRWG"] && w == 120 && h == 160 &&
              [r.detail containsString:@"public.heic 400×300"] && [r.detail containsString:@"方向6"] &&
              [r.detail containsString:@"头像 120×160"] && [r.detail containsString:@"已回读校验"],
              "HEIC file is read whole, turned upright and described");
        check([props[(__bridge id)kCGImagePropertyDepth] intValue] == 8 &&
              [props[(__bridge id)kCGImagePropertyColorModel] isEqual:(__bridge id)kCGImagePropertyColorModelRGB],
              "stored avatar is an 8-bit RGB PNG");
    } else {
        printf("note: no HEIC encoder on this host, HEIC case skipped\n");
    }
    CGImageRelease(photo);

    // 16 位 PNG：存下来是 8 位
    CGImageRef deep = avatarFixture(320, 320, 16, 0);
    NSData *png16 = avatarEncode(deep, @"public.png", 1);
    CGImageRelease(deep);
    IKAvatarSaveResult *r16 = [avatars saveImageData:png16 forTitle:title];
    NSString *seen16 = avatarReadBack([avatars imageForTitle:title], &w, &h, &props);
    check(r16.saved && [r16.detail containsString:@"16位"] && [seen16 hasPrefix:@"RGBW"] && w == 160 && h == 160 &&
          [props[(__bridge id)kCGImagePropertyDepth] intValue] == 8, "16-bit PNG is stored as an 8-bit avatar");
    NSData *good = [NSData dataWithContentsOfURL:[avatars imageForTitle:title]];
    NSString *described = [IKLocalAvatar describeImageData:good];
    check([described hasPrefix:@"160×160 平均亮度 "] && [described containsString:@"不透明 100%"], "describe a stored avatar");
    check(![IKLocalAvatar describeImageData:[@"x" dataUsingEncoding:NSUTF8StringEncoding]], "describe rejects non-images");

    // 透明底上的红圆：保存，角上透明、中间红
    CGImageRef dot = avatarFixture(300, 300, 8, 3);
    IKAvatarSaveResult *rDot = [avatars saveImageData:avatarEncode(dot, @"public.png", 1) forTitle:title];
    CGImageRelease(dot);
    NSString *seenDot = avatarReadBack([avatars imageForTitle:title], &w, &h, NULL);
    check(rDot.saved && !rDot.message && [rDot.detail containsString:@"带透明"] && [seenDot isEqual:@"....R"] &&
          ![rDot.detail containsString:@"不透明 100%"], "transparent picture keeps its alpha");
    good = [NSData dataWithContentsOfURL:[avatars imageForTitle:title]];

    // 全透明：不保存，原来那张不变
    CGImageRef clear = avatarFixture(120, 120, 8, 2);
    IKAvatarSaveResult *rClear = [avatars saveImageData:avatarEncode(clear, @"public.png", 1) forTitle:title];
    CGImageRelease(clear);
    check(!rClear.saved && [rClear.message containsString:@"全透明"] &&
          [[NSData dataWithContentsOfURL:[avatars imageForTitle:title]] isEqual:good], "fully transparent picture is refused and old avatar kept");

    // 全黑：照常保存但给出提示；缩略图接口给黑图时也能分清两条路都黑
    CGImageRef black = avatarFixture(200, 200, 8, 1);
    NSData *blackJPEG = avatarEncode(black, @"public.jpeg", 1);
    CGImageRelease(black);
    IKAvatarSaveResult *rBlack = [avatars saveImageData:blackJPEG forTitle:title];
    check(rBlack.saved && [rBlack.message isEqual:@"图片看起来是全黑的"] && [rBlack.detail containsString:@"public.jpeg"] &&
          [rBlack.detail containsString:@"缩略图接口（整图解码也是全黑）"], "a genuinely black picture is saved with a warning");
    [avatars setValue:@1 forKey:@"simulatedThumbnailFault"];
    rBlack = [avatars saveImageData:blackJPEG forTitle:title];
    check(rBlack.saved && [rBlack.message isEqual:@"图片看起来是全黑的"] && [rBlack.detail containsString:@"整图解码（缩略图接口没有结果）"],
          "black picture without a thumbnail still names the route");
    [avatars setValue:@0 forKey:@"simulatedThumbnailFault"];

    // 文件入口：目录、超过 16 MB、空文件、不是图片
    IKAvatarSaveResult *rDir = [avatars saveImageAtURL:[NSURL fileURLWithPath:root isDirectory:YES] forTitle:title];
    check(!rDir.saved && [rDir.message isEqual:@"请选择一个图片文件"], "a folder is not an image file");
    NSString *huge = [root stringByAppendingPathComponent:@"huge.png"];
    [fm createFileAtPath:huge contents:nil attributes:nil];
    truncate(huge.fileSystemRepresentation, 17 * 1024 * 1024);
    IKAvatarSaveResult *rHuge = [avatars saveImageAtURL:[NSURL fileURLWithPath:huge] forTitle:title];
    check(!rHuge.saved && [rHuge.message containsString:@"16 MB"], "files above 16 MB are refused before decoding");
    NSString *empty = [root stringByAppendingPathComponent:@"empty.png"];
    [fm createFileAtPath:empty contents:[NSData data] attributes:nil];
    IKAvatarSaveResult *rEmpty = [avatars saveImageAtURL:[NSURL fileURLWithPath:empty] forTitle:title];
    check(!rEmpty.saved && [rEmpty.message containsString:@"文件是空的"], "an empty file names the reason");
    IKAvatarSaveResult *rText = [avatars saveImageData:[@"not an image" dataUsingEncoding:NSUTF8StringEncoding] forTitle:title];
    check(!rText.saved && [rText.message containsString:@"不是能识别的图片格式"], "non-image data names the reason");
    IKAvatarSaveResult *rGone = [avatars saveImageAtURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"missing.png"]] forTitle:title];
    check(!rGone.saved && [rGone.message hasPrefix:@"图片无法读取："] && [rGone.message containsString:@"errno"], "a missing file names errno");
    IKAvatarSaveResult *rRemove = [avatars saveImageAtURL:nil forTitle:title];
    IKAvatarSaveResult *rRemoveAgain = [avatars saveImageAtURL:nil forTitle:title];
    check(rRemove.saved && rRemoveAgain.saved && ![avatars imageForTitle:title], "removing twice is fine");
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    store = [@(argv[1]) stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    bundle = @"com.tencent.QQMusic";
    messages = [NSMutableArray array];
    playing = YES;
    metadata = @{@"Title":@"歌曲", @"Artist":@"歌手", @"Duration":@180, @"ElapsedTime":@42,
                 @"QueueIndex":@1, @"ArtworkData":[@"cover" dataUsingEncoding:NSUTF8StringEncoding]};
    IKMusicCenter *m = IKMusicCenter.shared;
    NSString *emptyExport = [IKMusicCenter playbackDiagnosticReport];
    check([emptyExport containsString:@"未读到启动记录"] && [emptyExport containsString:@"悬浮窗尚无可导出"],
          "empty first launch can export the absence of each source");
    [m refresh];
    UIImage *cover = m.artwork;
    NSString *session = m.recording[@"playSession"];
    check(m.hasTrack && m.isPlaying && cover && session, "initial song and cover");
    metadata = @{@"Title":@"甲", @"Artist":@"歌手", @"Duration":@180};
    [m refresh];
    metadata = @{@"Title":@"乙", @"Artist":@"歌手", @"Duration":@180};
    [m refresh];
    metadata = @{@"Title":@"乙", @"Artist":@"丙", @"Duration":@180};
    [m refresh];
    check([m.reportedLyric isEqual:@"丙"] && [m.recording[@"title"] isEqual:@"歌曲"], "alternate car fields use latest line and stable title");
    check([session isEqual:m.recording[@"playSession"]] && m.currentElapsed >= 42 && m.artwork == cover, "line-only packets retain session, position and cover");
    NSDictionary *target = settingsTarget();
    check([target[@"title"] isEqual:@"歌曲"] && [target[@"artist"] isEqual:@"歌手"], "settings opened mid-song sees same canonical target");
    NSURL *file = [NSURL fileURLWithPath:[store stringByAppendingPathComponent:@"fixture.lrc"]];
    NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    check([@"[00:00]首句\n[00:40]当前\n[01:00]下句" writeToURL:file atomically:YES encoding:gb error:nil], "write GBK fixture");
    check(![IKMusicCenter importLyricsAtURL:file target:target], "normal settings import");
    [m refresh];
    check(m.lyricsBridgeActive && [m.bridgeLyric isEqual:@"当前"] && [m.bridgeTitle isEqual:@"歌曲"], "matching imported line at real clock");
    metadata = @{@"Title":@"丁", @"Artist":@"丙", @"UniqueIdentifier":@75, @"Duration":@180};
    [m refresh];
    check([m.bridgeLyric isEqual:@"当前"] && m.artwork == cover && m.currentElapsed >= 42, "late stable ID preserves old import and artwork");
    check([settingsTarget()[@"mode"] isEqual:@"已绑定本地时间轴"], "settings can find original metadata filename after ID arrives");
    playing = NO; [m refresh];
    double parked = m.currentElapsed;
    check(m.playbackSpeed == 0 && parked >= 42, "missing position on pause stays at playhead");
    playing = YES; [m refresh];
    check(fabs(m.currentElapsed-parked)<0.5 && m.playbackSpeed > 0, "resume has no jump");
    check(![IKMusicCenter removeImport:settingsTarget()], "remove through actual settings entry");
    [m refresh];
    check(!m.lyricsBridgeActive && [m.reportedLyric isEqual:@"丁"], "remove old filename returns to current car line");
    metadata = @{@"Title":@"同长歌曲", @"Artist":@"歌手", @"Duration":@180, @"QueueIndex":@2};
    [m refresh];
    check(![session isEqual:m.recording[@"playSession"]] && !m.artwork && m.currentElapsed < 1, "real track switch clears artwork and resets a missing position");
    check([[messages filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@",@"recording app="]] count] == 2,
          "identity availability logged once per track");
    bundle = @"com.netease.cloudmusic";
    metadata = @{@"Title":@"网易曲目",@"Artist":@"歌手",@"Duration":@180,@"ElapsedTime":@28};
    delayBundle = YES;
    [m applicationChanged];
    check([m.title isEqual:@"网易曲目"] && m.currentElapsed >= 28 && !m.lyricsBridgeActive && !m.mediaApplicationID,
          "now-playing display does not depend on app-ID callback");
    delayBundle = NO; bundleReply(bundle);
    check([settingsTarget()[@"bundleID"] isEqual:bundle] && !m.artwork, "late app-ID scopes handoff to new player");
    IKRecordingTracker *producer = [IKRecordingTracker new];
    [producer observe:IKTrackIdentity(nil,nil,@"原曲",@"原唱",212) album:nil queueIndex:@3 position:@0 bundle:bundle];
    NSDictionary *raw = IKTrackIdentity(nil,nil,@"原曲",@"播放器当前句",212);
    [producer observe:raw album:nil queueIndex:@3 position:@63 bundle:bundle];
    NSURL *recordingFile = [NSURL fileURLWithPath:IKAdjacentFile(IKPlayerLyricsPath(bundle),@"recording.plist")];
    check([producer writeSnapshotTo:recordingFile canonical:nil force:YES], "host publishes no-ID handoff in its container");
    metadata = @{@"Title":@"原曲",@"Artist":@"播放器当前句",@"Duration":@212,@"QueueIndex":@3,@"ElapsedTime":@63};
    [m refresh];
    check([m.reportedLyric isEqual:@"播放器当前句"] && [m.recording[@"artist"] isEqual:@"原唱"], "HUD joins host mid-verse");
    check([settingsTarget()[@"mode"] isEqual:@"播放器单句（无时间标签）"], "settings distinguishes host single cue from a timeline");
    metadata = @{@"Title":@"原曲",@"Artist":@"系统新句",@"Duration":@212,@"UniqueIdentifier":@98};
    [m refresh];
    check([m.reportedLyric isEqual:@"系统新句"] && [m.recording[@"persistentID"] isEqual:@"98"], "HUD keeps newer line and fills late ID with a paired host");
    check([settingsTarget()[@"artist"] isEqual:@"原唱"], "settings still has canonical artist on staggered callbacks");
    // When the host restarts, its new session ID alone does not imply a different song.
    IKRecordingTracker *restarted = [IKRecordingTracker new];
    [restarted observe:IKTrackIdentity(nil,@98,@"原曲",@"原唱",212) album:nil queueIndex:@3 position:@63 bundle:bundle];
    [restarted writeSnapshotTo:recordingFile canonical:nil force:YES];
    [m refresh];
    check(m.currentElapsed >= 63, "reopening adapter during same recording preserves playhead");
    metadata = @{@"Title":@"播放标题",@"Artist":@"演唱者",@"Duration":@100,@"QueueIndex":@8,
                 @"UniqueIdentifier":@400,@"ElapsedTime":@18,@"ArtworkData":[@"cover" dataUsingEncoding:NSUTF8StringEncoding]};
    [m refresh];
    session = m.recording[@"playSession"]; cover = m.artwork;
    metadata = @{@"Title":@"车载标题",@"Artist":@"第一句",@"Duration":@100,@"QueueIndex":@8,
                 @"UniqueIdentifier":@401,@"ElapsedTime":@21};
    [m refresh];
    check([m.recording[@"playSession"] isEqual:session] && m.artwork == cover && [m.reportedLyric isEqual:@"第一句"],
          "changing persistent ID during continuous car playback preserves track, cover and lyric");
    check([m.recording[@"unstablePersistentID"] isEqual:@YES] && ![IKMusicCenter importLyricsAtURL:file target:settingsTarget()],
          "bind the canonical recording after its ID becomes unstable");
    metadata = @{@"Title":@"播放标题",@"Artist":@"第二句",@"Duration":@100,@"QueueIndex":@8,@"UniqueIdentifier":@402};
    [m refresh];
    check([session isEqual:m.recording[@"playSession"]] && [settingsTarget()[@"mode"] isEqual:@"已绑定本地时间轴"] && m.currentElapsed>=21,
          "sparse next lyric keeps binding and clock despite another new ID");
    check([messages containsObject:@"lyric field=2"], "log selected numeric car field");
    metadata = @{@"Title":@"播放标题",@"Artist":@"演唱者乙",@"Duration":@121,@"QueueIndex":@9,@"ElapsedTime":@0};
    [m refresh]; session = m.recording[@"playSession"];
    metadata = @{@"Title":@"新歌名",@"Artist":@"新歌第一句",@"Duration":@121,@"QueueIndex":@9,@"ElapsedTime":@2};
    [m refresh];
    check([m.recording[@"title"] isEqual:@"新歌名"] && [m.reportedLyric isEqual:@"新歌第一句"] &&
          [session isEqual:m.recording[@"playSession"]], "correct inherited stale title, select artist on simultaneous first update");
    metadata = @{@"Title":@"电台节目一",@"Artist":@"电台",@"Duration":@0,@"QueueIndex":@12}; [m refresh];
    metadata = @{@"Title":@"电台节目二",@"Artist":@"电台",@"Duration":@0,@"QueueIndex":@12}; [m refresh];
    check([m.recording[@"title"] isEqual:@"电台节目二"] && !m.reportedLyric, "zero-duration program changes display as titles");
    metadata = @{@"Title":@"播报一",@"Artist":@"电台",@"UniqueIdentifier":@912,@"QueueIndex":@13}; [m refresh];
    metadata = @{@"Title":@"播报二",@"Artist":@"电台",@"UniqueIdentifier":@912,@"QueueIndex":@13}; [m refresh];
    check([m.recording[@"title"] isEqual:@"播报二"] && [settingsTarget()[@"mode"] isEqual:@"电台 / 直播节目"],
          "missing duration and a reused station ID cannot bind a program to an old timeline");
    metadata = @{@"Title":@"播报二",@"Artist":@"电台",@"Duration":@130,@"UniqueIdentifier":@912,@"QueueIndex":@13}; [m refresh];
    check(![m.recording[@"live"] boolValue] && m.duration == 130, "a delayed positive duration restores timed playback");
    metadata = @{@"Title":@"播放标题",@"Artist":@"演唱者",@"Duration":@100,@"QueueIndex":@14,@"UniqueIdentifier":@800,@"ElapsedTime":@10};
    [m refresh];
    metadata = @{@"Title":@"播放标题",@"Artist":@"重播第一句",@"Duration":@100,@"QueueIndex":@14,@"UniqueIdentifier":@801,@"ElapsedTime":@11};
    [m refresh];
    check(m.lyricsBridgeActive && [settingsTarget()[@"mode"] isEqual:@"已绑定本地时间轴"], "replay with different unstable ID finds metadata binding");
    NSString *diagnosticDir = IKPlayerLyricsPath(bundle).stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:diagnosticDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *launchFile = [diagnosticDir stringByAppendingPathComponent:IKPlaybackLaunchName];
    [@{@"bundleID":bundle, @"phase":@"loaded", @"version":@"15.2.3", @"wall":@1000} writeToFile:launchFile atomically:YES];
    NSString *launchOnly = [IKMusicCenter playbackDiagnosticReport];
    check([launchOnly containsString:@"等待播放器前台"] && [launchOnly containsString:@"播放器版本=15.2.3"] &&
          [launchOnly containsString:@"未读到可用的播放器采样"], "early exit report identifies version before first sample");
    NSDictionary *diagnostic = @{@"bundleID":bundle,@"schema":@1,@"fields":@{@"title":@"text"},@"customFields":@{@"vendorLyrics":@"text"},
        @"unknown":@1,@"jumpEvents":@1,@"accessEvents":@2,@"asset":@"remote",@"wall":@1000,@"uptime":@10,
        @"result":@{@"source":@"publishedField",@"key":@"vendorLyrics",@"lines":@3}};
    IKRememberDiagnostic([NSURL fileURLWithPath:diagnosticDir],diagnostic);
    [m clearPlayerScope];
    NSString *logPath = [store stringByAppendingPathComponent:@"island.log"];
    NSString *log = @"11-27 21:22:36 recording app=com.tencent.QQMusic externalID=0 persistentID=0 queueIndex=0\n11-27 21:22:44 lyric field=2\n11-27 21:24:37 interaction longPress state=compact\n11-27 21:24:38 lyric field=1 private-text\nprivate-text";
    [log writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *report = [IKMusicCenter playbackDiagnosticReport];
    check([report containsString:@"queueIndex=0"] && [report containsString:@"lyric field=2"] &&
          [report containsString:@"longPress state=compact"] && ![report containsString:@"private-text"], "export recovers only whitelisted historical HUD events");
    check([report containsString:@"1970-"] && [report containsString:@"vendorLyrics/text"] &&
          [report containsString:@"timeline=publishedField key=vendorLyrics lines=3"], "settings exports old host evidence with no active player");
    check([report containsString:@"selected/*.lrc bytes="] && ![report containsString:@"fixture.lrc"] && ![report containsString:@"当前"],
          "settings exports selected file shape without real file name or lyrics");
    metadata = @{}; [m refresh];
    check(!m.hasTrack && !m.reportedLyric && !m.recording, "empty playback clears song");
    testPublishedHandoff(m,@(argv[1]),@"com.tencent.QQMusic",@"qq");
    testPublishedHandoff(m,@(argv[1]),@"com.netease.cloudmusic",@"netease");
    testSampleFolder();
    IKLocalAvatar *avatars = [[IKLocalAvatar alloc] initWithDirectory:[NSURL fileURLWithPath:[store stringByAppendingPathComponent:@"avatars"]]];
    NSURL *picture = [NSURL fileURLWithPath:@"Resources/icon.png"];
    check(![avatars setImage:picture forTitle:@" 测试会话 "], "save chosen image under normalized notification title");
    NSURL *saved = [avatars imageForTitle:@"测试会话"];
    check(saved && ![saved.path containsString:@"测试会话"] && ![avatars imageForTitle:@"另一个会话"], "title digest isolates two conversations");
    CGImageSourceRef icon = CGImageSourceCreateWithURL((__bridge CFURLRef)saved,NULL);
    NSDictionary *dimensions = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(icon,0,NULL));
    CFRelease(icon);
    check([dimensions[(__bridge id)kCGImagePropertyPixelWidth] intValue] == 160, "stored picture is a downsampled thumbnail");
    check([avatars setImage:file forTitle:@"测试会话"] && [avatars imageForTitle:@"测试会话"], "invalid replacement preserves selected photo");
    check([avatars setImage:picture forTitle:@"微信"] != nil, "generic hidden notification title cannot receive a shared photo");
    check(![avatars setImage:nil forTitle:@"测试会话"] && ![avatars imageForTitle:@"测试会话"], "removing binding restores automatic fallback");
    NSData *pictureData = [NSData dataWithContentsOfURL:picture];
    check(pictureData && ![avatars setImageData:pictureData forTitle:@"相册会话"] && [avatars imageForTitle:@"相册会话"],
          "photo library data is stored as a bound avatar");
    check([avatars setImageData:[@"not an image" dataUsingEncoding:NSUTF8StringEncoding] forTitle:@"相册会话"] != nil &&
          [avatars imageForTitle:@"相册会话"], "undecodable photo data keeps the previous avatar");
    check([avatars setImageData:[NSData data] forTitle:@"相册会话"] != nil, "empty photo data is rejected");
    NSString *lockedRoot = [store stringByAppendingPathComponent:@"locked"];
    [NSFileManager.defaultManager createDirectoryAtPath:lockedRoot withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(lockedRoot.fileSystemRepresentation, 0555);
    IKLocalAvatar *locked = [[IKLocalAvatar alloc] initWithDirectory:[NSURL fileURLWithPath:[lockedRoot stringByAppendingPathComponent:@"WeChatAvatars"]]];
    NSString *lockedMessage = [locked setImageData:pictureData forTitle:@"相册会话"];
    check([lockedMessage containsString:@"无法创建目录"] && [lockedMessage containsString:@"WeChatAvatars"],
          "an unwritable data directory names the failing step and path");
    chmod(lockedRoot.fileSystemRepresentation, 0755);
    testAvatarFormats(store);
    if (![NSFileManager.defaultManager removeItemAtPath:store error:nil]) return 2;
    printf("HUD and settings: %d checks passed\n",count);
    return 0;
} }
