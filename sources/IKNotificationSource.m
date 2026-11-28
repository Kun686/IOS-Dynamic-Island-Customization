#import "IKAvatarProxy.h"
#import "IKLocalAvatar.h"
#import "IKNotificationSource.h"
#import "IKController.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#define IKNotifLogPath @"/var/mobile/Library/IslandKit/notif.log"

static void IKNotifLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"MM-dd HH:mm:ss";
        [[NSFileManager defaultManager] createDirectoryAtPath:[IKNotifLogPath stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    });
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], msg];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:IKNotifLogPath];
    if (!h) {
        [line writeToFile:IKNotifLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    // 日志超过 200KB 就清空重写
    if ([h seekToEndOfFile] > 200 * 1024) [h truncateFileAtOffset:0];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

static NSString *IKString(id obj, NSString *key) {
    @try {
        id v = [obj valueForKey:key];
        return [v isKindOfClass:[NSString class]] ? v : nil;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

// 列出一个对象所属类（含父类，到 NSObject 为止）的属性名和类型，只用于诊断
static NSString *IKDescribeProperties(id obj) {
    if (!obj) return @"(nil)";
    NSMutableArray *parts = [NSMutableArray array];
    for (Class c = [obj class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *attr = property_getAttributes(props[i]) ?: "";
            NSString *type = [[[NSString stringWithUTF8String:attr] componentsSeparatedByString:@","] firstObject];
            [parts addObject:[NSString stringWithFormat:@"%s:%@", property_getName(props[i]), type]];
        }
        free(props);
    }
    return [NSString stringWithFormat:@"%@{%@}", NSStringFromClass([obj class]), [parts componentsJoinedByString:@" "]];
}

static id IKValue(id obj, NSString *key) {
    @try {
        if (![obj respondsToSelector:NSSelectorFromString(key)]) return nil;
        return [obj valueForKey:key];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static NSString *IKPathShape(NSString *path) {
    if (path.length == 0) return @"-";
    NSArray<NSString *> *components = path.pathComponents;
    NSUInteger libraryIndex = [components indexOfObject:@"Library"];
    if (libraryIndex != NSNotFound) {
        NSUInteger count = MIN(components.count - libraryIndex, 3);
        return [[components subarrayWithRange:NSMakeRange(libraryIndex, count)]
                componentsJoinedByString:@"/"];
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in components) {
        if (part.length == 0 || [part isEqualToString:@"/"]) continue;
        [parts addObject:part];
        if (parts.count == 2) break;
    }
    return parts.count ? [parts componentsJoinedByString:@"/"] : @"-";
}

// 只记录值的形状和本地文件可读性，不记录通知正文、完整路径或图片内容。
static NSString *IKValueShape(id value) {
    if (!value || value == [NSNull null]) return @"empty";
    if ([value isKindOfClass:[UIImage class]]) {
        UIImage *image = value;
        return [NSString stringWithFormat:@"image %.0fx%.0f", image.size.width, image.size.height];
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"data.len=%lu", (unsigned long)[(NSData *)value length]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [NSString stringWithFormat:@"number=%@", [(NSNumber *)value boolValue] ? @"true" : @"false"];
    }
    NSURL *url = [value isKindOfClass:[NSURL class]] ? value : nil;
    NSString *string = [value isKindOfClass:[NSString class]] ? value : nil;
    if (string.length) {
        NSURL *candidate = [NSURL URLWithString:string];
        if (candidate.scheme.length) url = candidate;
    }
    if (url) {
        NSString *path = url.path ?: @"";
        BOOL readable = url.isFileURL && [[NSFileManager defaultManager] isReadableFileAtPath:path];
        return [NSString stringWithFormat:@"url.scheme=%@ path=%@ ext=%@ readable=%d",
                url.scheme ?: @"-", IKPathShape(path), path.pathExtension ?: @"-", readable];
    }
    if (string) {
        NSString *expanded = [string stringByExpandingTildeInPath];
        BOOL pathLike = [expanded hasPrefix:@"/"] || [expanded containsString:@"/"];
        BOOL readable = pathLike && [[NSFileManager defaultManager] isReadableFileAtPath:expanded];
        return [NSString stringWithFormat:@"string.len=%lu ext=%@%@",
                (unsigned long)string.length, expanded.pathExtension ?: @"-",
                pathLike ? [NSString stringWithFormat:@" path=%@ readable=%d", IKPathShape(expanded), readable] : @""];
    }
    return NSStringFromClass([value class]);
}

static UIImage *IKImageFromValueEnhanced(id value);
static UIImage *IKImageFromRemoteURL(NSURL *url);

static Class IKINImageClass(void) {
    static Class imageClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/Frameworks/Intents.framework/Intents", RTLD_LAZY);
        dlopen("/System/Library/Frameworks/IntentsUI.framework/IntentsUI", RTLD_LAZY);
        imageClass = NSClassFromString(@"INImage");
    });
    return imageClass;
}

static void IKLogINImageMethodsOnce(id imageObject) {
    if (!imageObject) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (Class c = [imageObject class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(c, &count);
            for (unsigned int i = 0; i < count; i++) {
                NSString *name = NSStringFromSelector(method_getName(methods[i]));
                NSString *lower = name.lowercaseString;
                if ([lower containsString:@"image"] || [lower containsString:@"fetch"]
                    || [lower containsString:@"retrieve"] || [lower containsString:@"url"]) {
                    if (![names containsObject:name]) [names addObject:name];
                }
            }
            free(methods);
        }
        [names sortUsingSelector:@selector(compare:)];
        IKNotifLog(@"INImage对象：class=%@ methods=%@", NSStringFromClass([imageObject class]),
                   names.count ? [names componentsJoinedByString:@","] : @"-");
    });
}

static UIImage *IKImageFromNamedValue(NSString *name) {
    if (name.length == 0) return nil;

    if ([name hasPrefix:@"file://"]) {
        NSURL *url = [NSURL URLWithString:name];
        if (url.isFileURL) {
            UIImage *image = [UIImage imageWithContentsOfFile:url.path];
            if (image) return image;
        }
    }

    NSString *expanded = [name stringByExpandingTildeInPath];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    if ([expanded hasPrefix:@"/"]) [paths addObject:expanded];

    NSString *leaf = expanded.lastPathComponent;
    if (leaf.length == 0) leaf = expanded;
    NSArray<NSString *> *directories = @[
        @"/var/mobile/Library/BulletinBoard/Images",
        @"/var/mobile/Library/BulletinBoard/Images/Attachments",
        @"/var/mobile/Library/BulletinBoard/Attachments",
        @"/var/mobile/Library/BulletinBoard",
        @"/var/mobile/Library/SpringBoard/SharedImages",
        @"/var/mobile/Library/SpringBoard/Images",
        @"/var/mobile/Library/Notifications/Images",
        @"/var/mobile/Library/Notifications/Attachments",
        @"/var/mobile/Library/NotificationCenter/Images",
        @"/var/mobile/Library/NotificationCenter/Attachments",
        @"/private/var/mobile/Library/BulletinBoard/Images",
        @"/private/var/mobile/Library/Notifications/Images"
    ];
    for (NSString *directory in directories) {
        [paths addObject:[directory stringByAppendingPathComponent:leaf]];
        if (![leaf isEqualToString:expanded] && ![expanded hasPrefix:@"/"]) {
            [paths addObject:[directory stringByAppendingPathComponent:expanded]];
        }
    }

    BOOL hasExtension = leaf.pathExtension.length > 0;
    NSArray<NSString *> *extensions = hasExtension ? @[@""] : @[@"", @".png", @".jpg", @".jpeg", @"@2x.png", @"@2x.jpg"];
    for (NSString *path in [paths copy]) {
        for (NSString *extension in extensions) {
            NSString *candidate = extension.length ? [path stringByAppendingString:extension] : path;
            if ([[NSFileManager defaultManager] isReadableFileAtPath:candidate]) {
                UIImage *image = [UIImage imageWithContentsOfFile:candidate];
                if (image) return image;
            }
        }
    }

    // 某些系统版本把 imageName 当作 BulletinBoard framework bundle 内的资源名。
    NSBundle *bulletinBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/BulletinBoard.framework"];
    UIImage *image = bulletinBundle
        ? [UIImage imageNamed:name inBundle:bulletinBundle compatibleWithTraitCollection:nil]
        : nil;
    return image ?: [UIImage imageNamed:name];
}

static UIImage *IKImageFromBundleName(NSString *name, NSBundle *bundle) {
    if (name.length == 0 || !bundle) return nil;

    NSString *leaf = name.lastPathComponent.length ? name.lastPathComponent : name;
    NSArray<NSString *> *names = @[name, leaf, [leaf stringByDeletingPathExtension]];
    for (NSString *candidate in names) {
        UIImage *image = [UIImage imageNamed:candidate inBundle:bundle compatibleWithTraitCollection:nil];
        if (image) return image;
    }
    return nil;
}

static void IKAppendIconNames(NSMutableArray<NSString *> *names, id value) {
    if ([value isKindOfClass:[NSString class]]) {
        if ([(NSString *)value length] > 0 && ![names containsObject:value]) [names addObject:value];
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)value) IKAppendIconNames(names, item);
    }
}

// BulletinBoard 的头像代理并不总能被悬浮进程读取。至少保证通知有应用图标，
// 同时保留代理头像的异步替换机会。优先读应用自己的 CFBundle 图标声明，
// 再调用系统已有的图标解析入口。
static UIImage *IKApplicationIconFromBundle(NSBundle *bundle, NSString *bundleID) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSDictionary *info = bundle.infoDictionary;
    IKAppendIconNames(names, info[@"CFBundleIconName"]);
    IKAppendIconNames(names, info[@"CFBundleIconFiles"]);
    for (NSString *key in @[@"CFBundleIcons", @"CFBundleIcons~ipad"]) {
        NSDictionary *icons = [info[key] isKindOfClass:[NSDictionary class]] ? info[key] : nil;
        NSDictionary *primary = [icons[@"CFBundlePrimaryIcon"] isKindOfClass:[NSDictionary class]]
            ? icons[@"CFBundlePrimaryIcon"] : nil;
        IKAppendIconNames(names, primary[@"CFBundleIconName"]);
        IKAppendIconNames(names, primary[@"CFBundleIconFiles"]);
    }
    for (NSString *name in names) {
        UIImage *image = IKImageFromBundleName(name, bundle);
        if (image) return image;
    }

    SEL iconSelector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (bundleID.length && [UIImage respondsToSelector:iconSelector]) {
        @try {
            return ((UIImage *(*)(id, SEL, id, NSUInteger, CGFloat))objc_msgSend)(
                [UIImage class], iconSelector, bundleID, 2, [UIScreen mainScreen].scale);
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

// 在一个对象的属性里找一张图：名字里带 image/avatar/thumbnail 的 NSData、UIImage，或指向本地文件的 URL/路径
static UIImage *IKFindImage(id obj) {
    if (!obj) return nil;
    if ([obj isKindOfClass:[UIImage class]]) return obj;
    for (Class c = [obj class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(c, &count);
        UIImage *found = nil;
        for (unsigned int i = 0; i < count && !found; i++) {
            NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
            NSString *lower = name.lowercaseString;
            NSString *attr = [NSString stringWithUTF8String:property_getAttributes(props[i]) ?: ""];
            if (![attr hasPrefix:@"T@"]) continue; // 只看对象类型
            BOOL imageish = [lower containsString:@"image"] || [lower containsString:@"avatar"] || [lower containsString:@"thumbnail"];
            BOOL pathish = [lower containsString:@"url"] || [lower containsString:@"path"];
            if (!imageish && !pathish) continue;
            id v = IKValue(obj, name);
            if (imageish || pathish) found = IKImageFromValueEnhanced(v);
        }
        free(props);
        if (found) return found;
    }
    return nil;
}

static UIImage *IKImageFromValueEnhanced(id value) {
    if ([value isKindOfClass:[UIImage class]]) return value;
    if ([value isKindOfClass:[NSData class]]) return [UIImage imageWithData:value];
    if ([value isKindOfClass:[NSURL class]] && [(NSURL *)value isFileURL]) {
        return [UIImage imageWithContentsOfFile:[(NSURL *)value path]];
    }
    if ([value isKindOfClass:[NSURL class]] && [[[(NSURL *)value scheme] lowercaseString] isEqualToString:@"data"]) {
        NSString *absolute = [(NSURL *)value absoluteString];
        NSRange comma = [absolute rangeOfString:@","];
        if (comma.location != NSNotFound) {
            NSString *metadata = [absolute substringToIndex:comma.location];
            NSString *payload = [absolute substringFromIndex:comma.location + 1];
            NSDataBase64DecodingOptions options = [metadata.lowercaseString containsString:@";base64"]
                ? NSDataBase64DecodingIgnoreUnknownCharacters : 0;
            NSData *data = options ? [[NSData alloc] initWithBase64EncodedString:payload options:options]
                                   : [[payload stringByRemovingPercentEncoding] dataUsingEncoding:NSUTF8StringEncoding];
            return [UIImage imageWithData:data];
        }
    }
    // INImage 通常是惰性对象。某些系统版本会在 imageWithURL: 后暴露 imageData，
    // 另一些版本只暴露 imageURL，两个属性都尝试一次。
    id imageData = IKValue(value, @"imageData");
    if (imageData && imageData != value) {
        UIImage *image = IKImageFromValueEnhanced(imageData);
        if (image) return image;
    }
    id imageURL = IKValue(value, @"imageURL");
    if (imageURL && imageURL != value) {
        UIImage *image = IKImageFromValueEnhanced(imageURL);
        if (image) return image;
    }
    if ([value isKindOfClass:[NSString class]]) return IKImageFromNamedValue(value);
    return nil;
}

// BBCommunicationContext 在微信通知里给的是 intents-remote-image-proxy URL。
// 这个 URL 不是本地文件名，交给 IntentsUI 的公开回调解码。
// 本地 file/data 资源可以直接解码，避免通知内容触发任意网络请求。
static UIImage *IKImageFromRemoteURL(NSURL *url) {
    if (!url) return nil;
    NSString *scheme = [[url scheme] lowercaseString];
    if ([scheme isEqualToString:@"file"] || [scheme isEqualToString:@"data"]) {
        return IKImageFromValueEnhanced(url);
    }
    return nil;
}

// Keep a late success for another bulletin from the same sender. No image or identity is written to disk.
static NSCache *IKAvatarCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 64; cache.totalCostLimit = 4*1024*1024; });
    return cache;
}

static id IKSenderIntentImage(id bulletin) {
    id context = IKValue(bulletin, @"context");
    if (![context isKindOfClass:NSDictionary.class]) return nil;
    id interaction = context[@"interaction"];
    id intent = IKValue(interaction, @"intent");
    id image = IKValue(IKValue(intent, @"sender"), @"image");
    return [image isKindOfClass:IKINImageClass()] ? image : nil;
}

static void IKFetchIntentsImage(id image, void (^reply)(UIImage *)) {
    SEL fetch = NSSelectorFromString(@"fetchUIImageWithCompletion:");
    if (![image respondsToSelector:fetch]) { reply(nil); return; }
    @try { ((void (*)(id, SEL, id))objc_msgSend)(image, fetch, reply); }
    @catch (__unused NSException *e) { reply(nil); }
}

static void IKResolveSenderImage(id suppliedImage, NSURL *url, NSArray *senderKey, void (^reply)(UIImage *, NSString *)) {
    UIImage *local = IKImageFromRemoteURL(url);
    if (local) { reply(local, @"local"); return; }
    if (!suppliedImage && ![url.scheme.lowercaseString isEqual:@"intents-remote-image-proxy"]) return;
    Class cls = IKINImageClass();
    id proxy = suppliedImage;
    @try {
        SEL withURL = NSSelectorFromString(@"imageWithURL:");
        if (!proxy && [cls respondsToSelector:withURL])
            proxy = ((id (*)(id,SEL,id))objc_msgSend)(cls,withURL,url);
    } @catch (__unused NSException *e) {}
    if (!proxy) { IKNotifLog(@"头像阶段 create=unavailable"); return; }
    IKLogINImageMethodsOnce(proxy);
    __block BOOL delivered = NO;
    __block BOOL timedOut = NO;
    __block BOOL publicDone = NO, proxyDone = NO;
    void (^finish)(UIImage *, NSString *) = ^(UIImage *image, NSString *stage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (delivered) return;
            if ([stage isEqual:@"publicFetch"]) publicDone = YES;
            else proxyDone = YES;
            if (image) {
                delivered = YES;
                reply(image, timedOut ? [stage stringByAppendingString:@".late"] : stage);
            } else IKNotifLog(@"头像阶段 %@=empty", stage);
        });
    };
    IKFetchIntentsImage(proxy, ^(UIImage *image) { finish(image, @"publicFetch"); });
    // Give the public path first chance. The proxy itself stays alive until both paths return.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC*150), dispatch_get_main_queue(), ^{
        if (delivered) return;
        SEL resolve = NSSelectorFromString(@"_proxiedImageWithError:");
        if (!IKCanResolveProxy(proxy, resolve)) { proxyDone = YES; IKNotifLog(@"头像阶段 resolve=unavailable"); return; }
        // The main queue owns the two real outstanding service calls. A UI timeout cannot release one.
        typedef void (^ResultHandler)(id, UIImage *, NSError *, BOOL);
        static NSMutableDictionary<id<NSCopying>,ResultHandler> *pending;
        if (!pending) pending = [NSMutableDictionary dictionary];
        id<NSCopying> key = senderKey && url ? (id)@[senderKey,url] : (id)NSUUID.UUID;
        ResultHandler replyToLatest = ^(id result, UIImage *concrete, NSError *error, BOOL sameProxy) {
            if (delivered) return;
            if (error || !result || sameProxy) {
                proxyDone = YES;
                IKNotifLog(@"头像阶段 resolve=%@ domain=%@ code=%ld",
                           error ? @"error" : (sameProxy ? @"sameProxy" : @"empty"), error.domain ?: @"-", (long)error.code);
            } else if (concrete) finish(concrete, @"resolvedData");
            else IKFetchIntentsImage(result, ^(UIImage *decoded) { finish(decoded, @"resolvedFetch"); });
        };
        IKAvatarAdmission admission = IKAwaitAvatar(pending,key,replyToLatest);
        if (admission == IKAvatarJoined) { IKNotifLog(@"头像阶段 resolve=joined"); return; }
        if (admission == IKAvatarBusy) {
            proxyDone = YES;
            IKNotifLog(@"头像阶段 resolve=busy publicOnly=1");
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            NSError *error = nil;
            id result = IKReadProxyImage(proxy, resolve, &error);
            UIImage *concrete = nil;
            if (result && result != proxy) {
                concrete = IKImageFromValueEnhanced(result);
                if (!concrete) {
                    // INImage's byte accessor is present in the device's method listing.
                    id data = IKValue(result, @"_imageData");
                    if ([data isKindOfClass:NSData.class] && [data length] <= 4*1024*1024)
                        concrete = [UIImage imageWithData:data];
                }
            }
            BOOL sameProxy = result == proxy;
            dispatch_async(dispatch_get_main_queue(), ^{
                ResultHandler handler = pending[key];
                [pending removeObjectForKey:key];
                if (handler) handler(result,concrete,error,sameProxy);
            });
        });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!delivered && (!publicDone || !proxyDone)) {
            timedOut = YES;
            IKNotifLog(@"头像阶段 timeout=5s waitingPublic=%d waitingProxy=%d", !publicDone, !proxyDone);
        }
    });
}

static NSURL *IKRemoteImageURLFromValue(id value, NSInteger depth) {
    if (!value || depth > 3) return nil;
    if ([value isKindOfClass:[NSURL class]]) {
        NSString *scheme = [[(NSURL *)value scheme] lowercaseString];
        if ([scheme isEqualToString:@"intents-remote-image-proxy"] || [scheme isEqualToString:@"file"]
            || [scheme isEqualToString:@"data"]) return value;
        return nil;
    }
    if ([value isKindOfClass:[NSString class]]) {
        if ([(NSString *)value hasPrefix:@"/"]) {
            return IKRemoteImageURLFromValue([NSURL fileURLWithPath:(NSString *)value], depth + 1);
        }
        NSURL *url = [NSURL URLWithString:(NSString *)value];
        return IKRemoteImageURLFromValue(url, depth + 1);
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"URL", @"url", @"contentURL", @"imageURL", @"thumbnailURL", @"fileURL", @"uri", @"data", @"path"]) {
            NSURL *url = IKRemoteImageURLFromValue(((NSDictionary *)value)[key], depth + 1);
            if (url) return url;
        }
        return nil;
    }
    for (NSString *key in @[@"URL", @"contentURL", @"imageURL", @"thumbnailURL", @"fileURL", @"thumbnailGeneratorUserInfo"]) {
        NSURL *url = IKRemoteImageURLFromValue(IKValue(value, key), depth + 1);
        if (url) return url;
    }
    return nil;
}

// 兼容聊天通知把头像放在 communicationContext、userInfo 或附件字典中的情况。
static UIImage *IKFindImageEnhanced(id obj, NSInteger depth) {
    if (!obj || depth > 3) return nil;
    UIImage *direct = IKImageFromValueEnhanced(obj);
    if (direct) return direct;

    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            UIImage *found = IKFindImageEnhanced(item, depth + 1);
            if (found) return found;
        }
        return nil;
    }

    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            NSString *name = [key isKindOfClass:[NSString class]] ? [key lowercaseString] : @"";
            BOOL relevant = [name containsString:@"image"] || [name containsString:@"avatar"]
                || [name containsString:@"photo"] || [name containsString:@"thumbnail"]
                || [name containsString:@"attachment"]
                || [name containsString:@"sender"] || [name containsString:@"contact"]
                || [name containsString:@"user"];
            if (!relevant) continue;
            UIImage *found = IKFindImageEnhanced(((NSDictionary *)obj)[key], depth + 1);
            if (found) return found;
        }
        return nil;
    }

    NSArray<NSString *> *knownKeys = @[
        @"image", @"imageData", @"avatar", @"avatarImage", @"senderImage",
        @"contactImage", @"contactAvatar", @"photo", @"photoImage",
        @"thumbnail", @"userInfo", @"userInfoDictionary",
        @"context", @"communicationContext", @"sender", @"contact", @"imageName",
        @"fileURL", @"filePath", @"contentURL", @"data", @"content",
        @"modalAlertContent", @"starkBannerContent", @"accessoryImage",
        @"accessoryIconMask", @"primaryAttachment",
        @"additionalAttachments", @"attachments", @"recipients"
    ];
    for (NSString *key in knownKeys) {
        UIImage *found = IKFindImageEnhanced(IKValue(obj, key), depth + 1);
        if (found) return found;
    }
    return IKFindImage(obj);
}

@interface IKNotificationSource ()
@property (nonatomic, strong) NSMutableSet<NSString *> *dumpedSections; // 每个应用只记一次结构
@property (nonatomic, strong) id observer;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *seen; // 同一条通知会从多个 feed 各来一次
@end

@implementation IKNotificationSource

+ (instancetype)shared {
    static IKNotificationSource *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IKNotificationSource new]; });
    return s;
}

- (void)start {
    if (self.observer) return;
    self.seen = [NSMutableOrderedSet orderedSet];
    self.dumpedSections = [NSMutableSet set];

    dlopen("/System/Library/PrivateFrameworks/BulletinBoard.framework/BulletinBoard", RTLD_NOW);
    Class cls = NSClassFromString(@"BBObserver");
    if (!cls) {
        IKNotifLog(@"启动失败：找不到 BBObserver 类");
        return;
    }

    @try {
        id obs = nil;
        SEL initQ = NSSelectorFromString(@"initWithQueue:");
        if ([cls instancesRespondToSelector:initQ]) {
            obs = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], initQ, dispatch_get_main_queue());
        } else {
            obs = [[cls alloc] init];
        }
        if (!obs) {
            IKNotifLog(@"启动失败：BBObserver 创建失败");
            return;
        }

        SEL setDelegate = NSSelectorFromString(@"setDelegate:");
        if ([obs respondsToSelector:setDelegate]) {
            ((void (*)(id, SEL, id))objc_msgSend)(obs, setDelegate, self);
        }
        // 订阅全部 feed，再按通知 ID 去重
        SEL setFeed = NSSelectorFromString(@"setObserverFeed:");
        if ([obs respondsToSelector:setFeed]) {
            ((void (*)(id, SEL, unsigned long long))objc_msgSend)(obs, setFeed, 0xFFFFULL);
        }
        self.observer = obs;
        IKNotifLog(@"已启动：observer=%@ setDelegate=%d setObserverFeed=%d", NSStringFromClass([obs class]),
                   [obs respondsToSelector:setDelegate], [obs respondsToSelector:setFeed]);
    } @catch (NSException *e) {
        IKNotifLog(@"启动异常：%@", e);
    }
}

#pragma mark BBObserverDelegate（按运行时方法名响应，不依赖头文件）

- (void)observer:(id)observer addBulletin:(id)bulletin forFeed:(unsigned long long)feed
    playLightsAndSirens:(BOOL)playLightsAndSirens withReply:(void (^)(BOOL))reply {
    [self handleBulletin:bulletin feed:feed fresh:playLightsAndSirens];
    // 回复 NO：声音和横幅仍由系统自己处理
    if (reply) reply(NO);
}

- (void)observer:(id)observer addBulletin:(id)bulletin forFeed:(unsigned long long)feed {
    // 这个回调多用于补发已有通知，只记录不显示
    IKNotifLog(@"补发：%@ feed=%llu", IKString(bulletin, @"sectionID"), feed);
}

- (void)observer:(id)observer modifyBulletin:(id)bulletin {}
- (void)observer:(id)observer removeBulletin:(id)bulletin {}
- (void)observer:(id)observer noteServerConnectionStateChanged:(BOOL)connected {
    IKNotifLog(@"与通知服务的连接：%@", connected ? @"已连接" : @"已断开");
}

- (void)handleBulletin:(id)bulletin feed:(unsigned long long)feed fresh:(BOOL)fresh {
    NSString *bundleID = IKString(bulletin, @"sectionID");
    NSString *bulletinID = IKString(bulletin, @"bulletinID");
    NSString *title = IKString(bulletin, @"title");
    NSString *subtitle = IKString(bulletin, @"subtitle");
    NSString *message = IKString(bulletin, @"message");
    // 日志里不写通知正文，只记来源和长度
    IKNotifLog(@"收到：%@ feed=%llu fresh=%d title.len=%lu message.len=%lu", bundleID, feed, fresh,
               (unsigned long)title.length, (unsigned long)message.length);

    if (!fresh || bundleID.length == 0) return;
    if (bulletinID.length) {
        if ([self.seen containsObject:bulletinID]) return;
        [self.seen addObject:bulletinID];
        if (self.seen.count > 200) [self.seen removeObjectAtIndex:0];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        IKController *ctl = [IKController shared];
        if (![ctl shouldTakeBundle:bundleID]) return;

        // 发送者头像（聊天类通知）。不同应用放的位置不一样，逐个地方找
        id context = IKValue(bulletin, @"communicationContext");
        id sender = IKValue(context, @"sender");
        id content = IKValue(bulletin, @"content");
        id modalContent = IKValue(bulletin, @"modalAlertContent");
        id starkContent = IKValue(bulletin, @"starkBannerContent");
        id attachment = IKValue(bulletin, @"primaryAttachment");
        id attachments = IKValue(bulletin, @"additionalAttachments");
        id accessoryImage = IKValue(bulletin, @"accessoryImage");
        id icon = IKValue(bulletin, @"icon");
        NSString *imageName = IKString(context, @"imageName");
        NSString *sectionBundlePath = IKString(bulletin, @"sectionBundlePath");
        NSBundle *sectionBundle = sectionBundlePath.length ? [NSBundle bundleWithPath:sectionBundlePath] : nil;
        NSString *appName = nil;
        @try {
            Class proxyCls = NSClassFromString(@"LSApplicationProxy");
            SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
            if ([proxyCls respondsToSelector:make]) {
                id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyCls, make, bundleID);
                appName = IKString(proxy, @"localizedName");
                if (!sectionBundle) {
                    NSURL *bundleURL = IKValue(proxy, @"bundleURL");
                    if ([bundleURL isKindOfClass:[NSURL class]]) sectionBundle = [NSBundle bundleWithURL:bundleURL];
                }
            }
        } @catch (__unused NSException *e) {}
        UIImage *avatar = nil;
        NSString *avatarFrom = @"-";
        @try {
            if ((avatar = IKFindImageEnhanced(sender, 0))) avatarFrom = @"sender";
            else if ((avatar = IKFindImageEnhanced(context, 0))) avatarFrom = @"communicationContext";
            else if ((avatar = IKImageFromNamedValue(imageName))) avatarFrom = @"communicationContext.imageName";
            else if ((avatar = IKImageFromBundleName(imageName, sectionBundle))) avatarFrom = @"sectionBundle.imageName";
            else if ((avatar = IKFindImageEnhanced(content, 0))) avatarFrom = @"content";
            else if ((avatar = IKFindImageEnhanced(modalContent, 0))) avatarFrom = @"modalAlertContent";
            else if ((avatar = IKFindImageEnhanced(starkContent, 0))) avatarFrom = @"starkBannerContent";
            else if ((avatar = IKFindImageEnhanced(accessoryImage, 0))) avatarFrom = @"accessoryImage";
            else if ((avatar = IKFindImageEnhanced(attachment, 0))) avatarFrom = @"primaryAttachment";
            else if ((avatar = IKFindImageEnhanced(attachments, 0))) avatarFrom = @"additionalAttachments";
            else if ((avatar = IKFindImageEnhanced(IKValue(bulletin, @"userInfo"), 0))) avatarFrom = @"userInfo";
        } @catch (__unused NSException *e) {}
        NSString *senderID = IKString(sender, @"customIdentifier");
        if (!senderID.length) senderID = IKString(sender, @"handle");
        NSArray *senderKey = senderID.length ? @[bundleID, senderID] : nil;
        if (avatar && senderKey && ([avatarFrom isEqual:@"sender"] || [avatarFrom isEqual:@"communicationContext"])) {
            [IKAvatarCache() setObject:avatar forKey:senderKey cost:avatar.CGImage ?
                CGImageGetBytesPerRow(avatar.CGImage) * CGImageGetHeight(avatar.CGImage) : 65536];
        }
        if (!avatar && senderKey) {
            avatar = [IKAvatarCache() objectForKey:senderKey];
            if (avatar) avatarFrom = @"senderCache";
        }
        if (!avatar && [bundleID isEqual:@"com.tencent.xin"]) {
            NSURL *file = [IKLocalAvatar.shared imageForTitle:title.length ? title : subtitle];
            if (file) avatar = [UIImage imageWithContentsOfFile:file.path];
            if (avatar) {
                avatarFrom = @"localChoice";
                // 和设置页保存时那一行自证信息对照：两边亮度一致说明文件没问题，岛上发黑就是显示那一步的事
                NSData *bytes = [NSData dataWithContentsOfURL:file];
                IKNotifLog(@"备用头像 %@ size=%.0fx%.0f", [IKLocalAvatar describeImageData:bytes] ?: @"无法解码",
                           avatar.size.width * avatar.scale, avatar.size.height * avatar.scale);
            } else if (file) {
                IKNotifLog(@"备用头像 文件存在但读不出图片");
            }
        }
        if (!avatar) {
            UIImage *appIcon = IKApplicationIconFromBundle(sectionBundle, bundleID);
            if (appIcon) {
                avatar = appIcon;
                avatarFrom = @"applicationIcon";
            }
        }
        IKNotifLog(@"头像：%@ from=%@ imageName.len=%lu bundle=%d candidates=sender:%d context:%d content:%d attachment:%d accessory:%d icon:%d",
                   bundleID, avatarFrom, (unsigned long)imageName.length, sectionBundle != nil,
                   sender != nil, context != nil, content != nil, attachment != nil,
                   accessoryImage != nil, icon != nil);

        // 第一次遇到这个应用时，把通知对象的结构记下来（只有属性名和类型，没有内容），方便定位头像在哪
        if (![self.dumpedSections containsObject:bundleID]) {
            [self.dumpedSections addObject:bundleID];
            id contentURL = IKValue(context, @"contentURL") ?: IKValue(bulletin, @"contentURL");
            id systemImage = IKValue(context, @"systemImage") ?: IKValue(bulletin, @"systemImage");
            id contactIdentifier = IKValue(sender, @"cnContactIdentifier") ?: IKValue(context, @"cnContactIdentifier");
            IKNotifLog(@"值形状 %@ imageName=%@ contentURL=%@ systemImage=%@ sender.cnContactIdentifier=%@ content=%@ accessoryImage=%@ attachment=%@ additionalAttachments=%@",
                       bundleID, IKValueShape(imageName), IKValueShape(contentURL),
                       IKValueShape(systemImage), IKValueShape(contactIdentifier),
                       IKValueShape(content), IKValueShape(accessoryImage),
                       IKValueShape(attachment), IKValueShape(attachments));
            IKNotifLog(@"结构 bulletin=%@", IKDescribeProperties(bulletin));
            IKNotifLog(@"结构 communicationContext=%@", IKDescribeProperties(context));
            IKNotifLog(@"结构 sender=%@", IKDescribeProperties(sender));
            IKNotifLog(@"结构 content=%@", IKDescribeProperties(content));
            IKNotifLog(@"结构 primaryAttachment=%@", IKDescribeProperties(attachment));
            IKNotifLog(@"结构 additionalAttachments=%@", IKDescribeProperties([attachments isKindOfClass:NSArray.class] ? [attachments firstObject] : attachments));
            IKNotifLog(@"结构 accessoryImage=%@", IKDescribeProperties(accessoryImage));
            IKNotifLog(@"结构 icon=%@", IKDescribeProperties(icon));
        }

        BOOL avatarIsSender = avatar != nil && ![avatarFrom isEqualToString:@"applicationIcon"];
        NSUInteger notificationToken = [ctl showNotificationWithBundle:bundleID
                                                                appName:appName ?: bundleID
                                                                  title:title.length ? title : subtitle
                                                                message:message
                                                                 avatar:avatar
                                                         avatarIsSender:avatarIsSender];

        // 微信的 contentURL 是系统代理 URL，头像需要异步从代理解码，避免阻塞 BBObserver 主线程。
        if (!avatar || [avatarFrom isEqualToString:@"applicationIcon"] || [avatarFrom isEqualToString:@"senderCache"] ||
            [avatarFrom isEqualToString:@"localChoice"]) {
            id contentURL = IKValue(context, @"contentURL");
            NSURL *remoteURL = IKRemoteImageURLFromValue(contentURL, 0);
            if (!remoteURL) remoteURL = IKRemoteImageURLFromValue(context, 0);
            if (!remoteURL) remoteURL = IKRemoteImageURLFromValue(bulletin, 0);
            if (!remoteURL) remoteURL = IKRemoteImageURLFromValue(attachment, 0);
            if (!remoteURL) remoteURL = IKRemoteImageURLFromValue(attachments, 0);
            id original = IKSenderIntentImage(bulletin);
            if (remoteURL || original) {
                IKNotifLog(@"头像阶段 request=%@ original=%d scheme=%@", bundleID, original != nil, remoteURL.scheme ?: @"-");
                IKResolveSenderImage(original, remoteURL, senderKey, ^(UIImage *resolved, NSString *source) {
                    if (senderKey) [IKAvatarCache() setObject:resolved forKey:senderKey
                        cost:(resolved.CGImage ? CGImageGetBytesPerRow(resolved.CGImage) * CGImageGetHeight(resolved.CGImage) : 65536)];
                    BOOL applied = [ctl updateNotificationAvatar:resolved forBundle:bundleID
                                     title:title.length ? title : subtitle message:message token:notificationToken];
                    IKNotifLog(@"头像阶段 source=%@ display=%@", source, applied ? @"applied" : @"superseded");
                });
            }
        }
    });
}

@end
