#import <Foundation/Foundation.h>

// 试验性：免越狱读取其他应用的通知。
// 通过私有框架 BulletinBoard 的 BBObserver 监听新通知，命中白名单就交给 IKController 显示。
// 它压不掉系统横幅；想只看岛上的显示，需要在系统设置里把对应应用的“横幅”关掉。
// 运行情况会写到 /var/mobile/Library/IslandKit/notif.log，便于排查。
@interface IKNotificationSource : NSObject
+ (instancetype)shared;
- (void)start;
@end
