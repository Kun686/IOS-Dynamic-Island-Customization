#import <UIKit/UIKit.h>

extern NSString *const IKMusicDidChangeNotification;

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

// 按上报的进度、时间戳和速率推算当前播放位置（秒）
- (double)currentElapsed;
@end
