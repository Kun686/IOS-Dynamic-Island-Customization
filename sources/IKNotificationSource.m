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
            if ([v isKindOfClass:[UIImage class]]) {
                found = v;
            } else if ([v isKindOfClass:[NSData class]] && imageish) {
                found = [UIImage imageWithData:v];
            } else if ([v isKindOfClass:[NSURL class]] && [(NSURL *)v isFileURL]) {
                found = [UIImage imageWithContentsOfFile:[(NSURL *)v path]];
            } else if ([v isKindOfClass:[NSString class]] && [(NSString *)v hasPrefix:@"/"]) {
                found = [UIImage imageWithContentsOfFile:v];
            }
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
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value hasPrefix:@"/"]) {
        return [UIImage imageWithContentsOfFile:value];
    }
    return nil;
}

// 兼容聊天通知把头像放在 communicationContext、userInfo 或附件字典中的情况。
static UIImage *IKFindImageEnhanced(id obj, NSInteger depth) {
    if (!obj || depth > 3) return nil;
    UIImage *direct = IKImageFromValueEnhanced(obj);
    if (direct) return direct;

    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)obj) {
            NSString *name = [key isKindOfClass:[NSString class]] ? [key lowercaseString] : @"";
            BOOL relevant = [name containsString:@"image"] || [name containsString:@"avatar"]
                || [name containsString:@"photo"] || [name containsString:@"thumbnail"]
                || [name containsString:@"icon"] || [name containsString:@"attachment"]
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
        @"thumbnail", @"icon", @"userInfo", @"userInfoDictionary",
        @"context", @"communicationContext", @"sender", @"contact"
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
        id attachment = IKValue(bulletin, @"primaryAttachment");
        id icon = IKValue(bulletin, @"icon");
        UIImage *avatar = nil;
        NSString *avatarFrom = @"-";
        @try {
            if ((avatar = IKFindImageEnhanced(sender, 0))) avatarFrom = @"sender";
            else if ((avatar = IKFindImageEnhanced(context, 0))) avatarFrom = @"communicationContext";
            else if ((avatar = IKFindImageEnhanced(attachment, 0))) avatarFrom = @"primaryAttachment";
            else if ((avatar = IKFindImageEnhanced(IKValue(bulletin, @"userInfo"), 0))) avatarFrom = @"userInfo";
        } @catch (__unused NSException *e) {}
        IKNotifLog(@"头像：%@ from=%@", bundleID, avatarFrom);

        // 第一次遇到这个应用时，把通知对象的结构记下来（只有属性名和类型，没有内容），方便定位头像在哪
        if (![self.dumpedSections containsObject:bundleID]) {
            [self.dumpedSections addObject:bundleID];
            IKNotifLog(@"结构 bulletin=%@", IKDescribeProperties(bulletin));
            IKNotifLog(@"结构 communicationContext=%@", IKDescribeProperties(context));
            IKNotifLog(@"结构 sender=%@", IKDescribeProperties(sender));
            IKNotifLog(@"结构 primaryAttachment=%@", IKDescribeProperties(attachment));
            IKNotifLog(@"结构 icon=%@", IKDescribeProperties(icon));
        }

        // 应用名
        NSString *appName = nil;
        @try {
            Class proxyCls = NSClassFromString(@"LSApplicationProxy");
            SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
            if ([proxyCls respondsToSelector:make]) {
                id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyCls, make, bundleID);
                appName = IKString(proxy, @"localizedName");
            }
        } @catch (__unused NSException *e) {}

        [ctl showNotificationWithBundle:bundleID
                                appName:appName ?: bundleID
                                  title:title.length ? title : subtitle
                                message:message
                                 avatar:avatar];
    });
}

@end
