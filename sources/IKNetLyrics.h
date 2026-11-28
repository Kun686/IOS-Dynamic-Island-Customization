#import <Foundation/Foundation.h>

// 联网匹配逐句歌词时间轴。纯 Foundation，可在 macOS 上单测。
//
// 只把歌名和歌手（歌手不可靠时只发歌名）发给 QQ 音乐、网易云的公开网页接口，只取 LRC 歌词：
//   QQ 搜索   GET https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w=…&format=json&n=8&p=1&cr=1&t=0
//   QQ 歌词   GET https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=…&format=json&nobase64=1
//             （必须带 Referer: https://y.qq.com/，否则返回 code=-1310）
//   网易云搜索 GET https://music.163.com/api/search/get/web?s=…&type=1&limit=8&offset=0
//   网易云歌词 GET https://music.163.com/api/song/lyric?id=…&lv=1&kv=1&tv=-1
// QQ 的 POST u.y.qq.com/cgi-bin/musicu.fcg 搜索在 2026-11 实测返回 req_1.code=2001 且列表为空，没有使用。
// 所有请求走 HTTPS、超时 6 秒、响应上限 512KB、不带也不接收 cookie、通用浏览器 User-Agent。

extern NSString *const IKNetProviderQQ;        // @"qq"
extern NSString *const IKNetProviderNetease;   // @"netease"

#define IKNetLyricsTimeout 6.0
#define IKNetLyricsMaxBytes (512 * 1024)
#define IKNetLyricsMaxDurationDelta 3.0

// 网络层。收到完整响应或失败后调用 reply；失败时 data 为 nil。可以在任意线程回调。
typedef void (^IKNetReply)(NSData *data, NSInteger status, NSError *error);
typedef void (^IKNetTransport)(NSURLRequest *request, IKNetReply reply);
// 默认实现：临时会话（无 cookie、无缓存）、超时 6 秒、超过 512KB 立即取消、只跟随 HTTPS 跳转
IKNetTransport IKNetDefaultTransport(void);
// 同样的会话设置，另外经指定的 connectionProxyDictionary 出网。只给 macOS 上的联网冒烟测试用
// （开发机的沙盒只放行本机代理）；iOS 上用系统代理设置，走 IKNetDefaultTransport
IKNetTransport IKNetProxyTransport(NSDictionary *connectionProxy);

// 正在播放的是网易云时先网易云后 QQ，其他先 QQ 后网易云
NSArray<NSString *> *IKNetProviderOrder(NSString *bundleID);
NSURLRequest *IKNetSearchRequest(NSString *provider, NSString *query);
NSURLRequest *IKNetLyricRequest(NSString *provider, NSString *songID);

// 归一化：全半角（NFKC）、大小写、繁简、去掉空白和标点
NSString *IKNetNormalize(NSString *text);
// 去掉括号（含全角）和“ - ”后缀里的版本说明，例如 “晴天 (Live)” → “晴天”
NSString *IKNetBaseTitle(NSString *title);
// 版本说明里出现的、意味着不同录音的标记（live、伴奏、翻唱、某某版……）
NSSet<NSString *> *IKNetVersionTags(NSString *title);
// 两个歌手字段是否指同一位（任一方可以是 “A/B”“A & B” 这类多人写法）
BOOL IKNetArtistMatches(NSString *artist, NSArray<NSString *> *candidateArtists);

// 搜索结果统一成候选：@{provider, id, title, artists:[NSString], duration:秒, album}。响应不可用时返回 nil
NSArray<NSDictionary *> *IKNetParseSearch(NSString *provider, NSData *json);
// 打分。返回负数表示拒绝：
//   歌名归一化后相同，或去掉括号版本说明后相同且两边的版本标记一致；
//   有时长时 |候选 − 播放| ≤ 3 秒；时长未知时歌名歌手都要吻合；
//   歌手可靠（不是被车载歌词占用的字段）时必须吻合；歌手吻合加分，时长越接近分越高。
double IKNetScoreCandidate(NSDictionary *candidate, NSString *title, NSString *artist, BOOL artistReliable, double duration);
// 按分数从高到低返回所有可接受的候选
NSArray<NSDictionary *> *IKNetRankCandidates(NSArray<NSDictionary *> *candidates, NSString *title, NSString *artist,
                                             BOOL artistReliable, double duration);

// 从歌词接口的响应里取原文 LRC。失败返回 nil，*reason 写原因：
//   instrumental 纯音乐；no-lyrics 无歌词；api 接口返回错误码；bad-response 响应不是预期的 JSON
NSString *IKNetParseLyric(NSString *provider, NSData *json, NSString **reason);
// 把 LRC 解析成时间轴（[offset:] 由 IKParseTimedLyrics 处理）。纯音乐提示、不足 3 句的按“没有时间轴”处理
NSArray<NSDictionary *> *IKNetTimedLines(NSString *lrc, double duration, NSString **reason);
// 本地校验：播放器已经上报过的车载歌词里，至少有一句出现在这份时间轴里（归一化后比较）。
// 歌手字段被车载歌词占用、只能按歌名和时长匹配时用它排除同名同长的翻唱。不联网，不外发
BOOL IKNetLinesContainEvidence(NSArray<NSDictionary *> *lines, NSArray<NSString *> *evidence);

@interface IKNetLyricsResult : NSObject
@property (nonatomic, copy) NSString *status;            // hit / miss / error
@property (nonatomic, copy) NSString *provider;          // 命中的提供方
@property (nonatomic, copy) NSString *songID;            // 命中的歌曲在提供方的 ID
@property (nonatomic, copy) NSString *lrc;               // 带时间戳的 LRC 原文
@property (nonatomic, copy) NSArray<NSDictionary *> *lines;
@property (nonatomic) double candidateDuration;
@property (nonatomic) double durationDelta;              // |候选 − 播放|；时长未知为 -1
@property (nonatomic, copy) NSString *reason;            // 失败原因
// 每家依次一条：@{provider, status(hit/miss/error), reason, lines, dt(可缺)}
@property (nonatomic, copy) NSArray<NSDictionary *> *attempts;
@end

@interface IKNetLyricsClient : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) IKNetTransport transport;   // 默认 IKNetDefaultTransport()
@property (nonatomic, copy) double (^clock)(void);      // 负缓存用的时钟，默认 systemUptime
@property (nonatomic) double retryAfter;                 // 失败后多久允许再试一次，默认 300 秒
// 依次查询各提供方。返回 NO 表示歌名为空，或这首歌在本次运行内失败过、还在负缓存里
// （失败后 retryAfter 秒放行一次，再失败就到本次运行结束），此时 completion 不会被调用。
// evidence：歌手不可靠时传入已观察到的车载歌词，命中前用 IKNetLinesContainEvidence 校验；为空则不校验。
// completion 在网络层回调所在的线程调用。
- (BOOL)lookupBundle:(NSString *)bundleID title:(NSString *)title artist:(NSString *)artist
      artistReliable:(BOOL)artistReliable duration:(double)duration evidence:(NSArray<NSString *> *)evidence
          completion:(void (^)(IKNetLyricsResult *result))completion;
@end
