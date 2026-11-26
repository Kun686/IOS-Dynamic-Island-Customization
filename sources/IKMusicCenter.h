#import <UIKit/UIKit.h>

extern NSString *const IKMusicDidChangeNotification;
#define IKLyricsChangedDarwin "com.islandkit.lyrics/changed"

// 封装系统“正在播放”信息
@interface IKMusicCenter : NSObject
+ (instancetype)shared;
- (void)start;
- (void)refresh;

@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *artist;
@property (nonatomic, readonly, copy) NSString *album;
@property (nonatomic, readonly, strong) UIImage *artwork;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL hasTrack;
@property (nonatomic, readonly) double duration;

// 可选的 TrollFools 歌词桥接。播放器插件优先把时间轴原子写入自己容器的
// Library/IslandKit/lyrics.plist，再发送 IKLyricsChangedDarwin。仍兼容
// /var/mobile/Library/IslandKit/lyrics.plist 这个全局回退路径。
// 没有有效桥接数据时，控制器继续使用 MediaRemote。
@property (nonatomic, readonly) BOOL lyricsBridgeActive;
@property (nonatomic, readonly, copy) NSString *bridgeLyric;
@property (nonatomic, readonly, copy) NSString *bridgeNextLyric;
@property (nonatomic, readonly, copy) NSString *bridgeTitle;
@property (nonatomic, readonly) double bridgeLyricElapsed;
@property (nonatomic, readonly) double bridgeLyricDuration;
- (BOOL)refreshLyricsBridge;
// 用已缓存的时间轴推进当前句，不读文件；由悬浮窗的 0.25 秒计时器调用。
- (void)advanceLyricsBridge;

// 按上报的进度、时间戳和速率推算当前播放位置（秒）
- (double)currentElapsed;
@end
