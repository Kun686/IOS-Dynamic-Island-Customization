#import "IKNetLyrics.h"
#import "IKLyricsTimeline.h"
#import <math.h>

NSString *const IKNetProviderQQ = @"qq";
NSString *const IKNetProviderNetease = @"netease";

// 通用桌面浏览器串，不带任何设备、用户或本工程的信息
static NSString *const IKNetUserAgent =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

#pragma mark - 请求

NSArray<NSString *> *IKNetProviderOrder(NSString *bundleID) {
    return [bundleID.lowercaseString isEqual:@"com.netease.cloudmusic"]
        ? @[IKNetProviderNetease, IKNetProviderQQ] : @[IKNetProviderQQ, IKNetProviderNetease];
}

// 只放行 RFC 3986 的非保留字符，其余（包括 + & = 和所有非 ASCII）一律百分号编码
static NSString *IKNetEscape(NSString *s) {
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSURLRequest *IKNetRequest(NSString *base, NSArray<NSArray<NSString *> *> *query, NSString *referer) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSArray<NSString *> *pair in query) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", IKNetEscape(pair[0]), IKNetEscape(pair[1])]];
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", base, [parts componentsJoinedByString:@"&"]]];
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:IKNetLyricsTimeout];
    request.HTTPMethod = @"GET";
    request.HTTPShouldHandleCookies = NO;
    [request setValue:IKNetUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    [request setValue:referer forHTTPHeaderField:@"Referer"];
    return request;
}

NSURLRequest *IKNetSearchRequest(NSString *provider, NSString *query) {
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!q.length || q.length > 300) return nil;
    if ([provider isEqual:IKNetProviderQQ]) {
        return IKNetRequest(@"https://c.y.qq.com/soso/fcgi-bin/client_search_cp",
                            @[@[@"w", q], @[@"format", @"json"], @[@"n", @"8"], @[@"p", @"1"], @[@"cr", @"1"], @[@"t", @"0"]],
                            @"https://y.qq.com/");
    }
    if ([provider isEqual:IKNetProviderNetease]) {
        return IKNetRequest(@"https://music.163.com/api/search/get/web",
                            @[@[@"s", q], @[@"type", @"1"], @[@"limit", @"8"], @[@"offset", @"0"]],
                            @"https://music.163.com/");
    }
    return nil;
}

NSURLRequest *IKNetLyricRequest(NSString *provider, NSString *songID) {
    if (!songID.length || songID.length > 64) return nil;
    if ([provider isEqual:IKNetProviderQQ]) {
        // 不带 Referer 时接口返回 code=-1310
        return IKNetRequest(@"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
                            @[@[@"songmid", songID], @[@"format", @"json"], @[@"nobase64", @"1"]], @"https://y.qq.com/");
    }
    if ([provider isEqual:IKNetProviderNetease]) {
        return IKNetRequest(@"https://music.163.com/api/song/lyric",
                            @[@[@"id", songID], @[@"lv", @"1"], @[@"kv", @"1"], @[@"tv", @"-1"]], @"https://music.163.com/");
    }
    return nil;
}

#pragma mark - 默认网络层

@interface IKNetSession : NSObject <NSURLSessionDataDelegate>
+ (instancetype)shared;
- (instancetype)initWithProxy:(NSDictionary *)proxy;
- (void)send:(NSURLRequest *)request reply:(IKNetReply)reply;
@end

@implementation IKNetSession {
    NSURLSession *_session;
    NSMutableDictionary<NSNumber *, NSMutableData *> *_buffers;
    NSMutableDictionary<NSNumber *, IKNetReply> *_replies;
    NSMutableSet<NSNumber *> *_overflow;
}

+ (instancetype)shared {
    static IKNetSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ session = [[IKNetSession alloc] initWithProxy:nil]; });
    return session;
}

- (instancetype)initWithProxy:(NSDictionary *)proxy {
    if (!(self = [super init])) return nil;
    _buffers = [NSMutableDictionary dictionary];
    _replies = [NSMutableDictionary dictionary];
    _overflow = [NSMutableSet set];
    // 临时会话：不读写 cookie、不缓存、不存凭据
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    config.URLCache = nil;
    config.URLCredentialStorage = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForRequest = IKNetLyricsTimeout;
    config.timeoutIntervalForResource = IKNetLyricsTimeout;
    config.HTTPMaximumConnectionsPerHost = 2;
    config.waitsForConnectivity = NO;
    if (proxy.count) config.connectionProxyDictionary = proxy;
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
    return self;
}

- (void)send:(NSURLRequest *)request reply:(IKNetReply)reply {
    if (![request.URL.scheme.lowercaseString isEqual:@"https"]) {
        reply(nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorAppTransportSecurityRequiresSecureConnection userInfo:nil]);
        return;
    }
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
    @synchronized (self) {
        _replies[@(task.taskIdentifier)] = [reply copy];
        _buffers[@(task.taskIdentifier)] = [NSMutableData data];
    }
    [task resume];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (response.expectedContentLength > IKNetLyricsMaxBytes) {
        @synchronized (self) { [_overflow addObject:@(task.taskIdentifier)]; }
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    BOOL tooLarge = NO;
    @synchronized (self) {
        NSMutableData *buffer = _buffers[@(task.taskIdentifier)];
        if (buffer.length + data.length > IKNetLyricsMaxBytes) {
            tooLarge = YES;
            [_overflow addObject:@(task.taskIdentifier)];
        } else [buffer appendData:data];
    }
    if (tooLarge) [task cancel];
}

// 只跟随 HTTPS 跳转，跳转后的请求同样不带 cookie
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if (![request.URL.scheme.lowercaseString isEqual:@"https"]) { completionHandler(nil); return; }
    NSMutableURLRequest *next = [request mutableCopy];
    next.HTTPShouldHandleCookies = NO;
    completionHandler(next);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSNumber *key = @(task.taskIdentifier);
    IKNetReply reply;
    NSData *data;
    BOOL tooLarge;
    @synchronized (self) {
        reply = _replies[key];
        data = [_buffers[key] copy];
        tooLarge = [_overflow containsObject:key];
        [_replies removeObjectForKey:key];
        [_buffers removeObjectForKey:key];
        [_overflow removeObject:key];
    }
    if (!reply) return;
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    if (tooLarge) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil];
    reply(error ? nil : data, status, error);
}
@end

IKNetTransport IKNetDefaultTransport(void) {
    return ^(NSURLRequest *request, IKNetReply reply) { [[IKNetSession shared] send:request reply:reply]; };
}

IKNetTransport IKNetProxyTransport(NSDictionary *connectionProxy) {
    IKNetSession *session = [[IKNetSession alloc] initWithProxy:connectionProxy];
    return ^(NSURLRequest *request, IKNetReply reply) { [session send:request reply:reply]; };
}

#pragma mark - 归一化与匹配

NSString *IKNetNormalize(NSString *text) {
    if (![text isKindOfClass:NSString.class] || !text.length) return @"";
    NSString *s = text.precomposedStringWithCompatibilityMapping.lowercaseString;
    NSString *simplified = [s stringByApplyingTransform:@"Hant-Hans" reverse:NO];
    if (simplified) s = simplified;
    NSCharacterSet *drop = NSCharacterSet.alphanumericCharacterSet.invertedSet;
    return [[s componentsSeparatedByCharactersInSet:drop] componentsJoinedByString:@""];
}

static NSRegularExpression *IKNetBracketPattern(void) {
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:
                   @"[\\(\\[【〔〈<「『]([^\\(\\)\\[\\]【】〔〕〈〉<>「」『』]*)[\\)\\]】〕〉>」』]" options:0 error:nil];
    });
    return pattern;
}

static NSRegularExpression *IKNetSuffixPattern(void) {
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"\\s+[-–—]\\s+(.+)$" options:0 error:nil];
    });
    return pattern;
}

// 拆成“正名”和若干条版本说明
static NSString *IKNetSplitTitle(NSString *title, NSMutableArray<NSString *> *extras) {
    if (![title isKindOfClass:NSString.class]) return @"";
    NSString *s = title.precomposedStringWithCompatibilityMapping;
    for (int round = 0; round < 3; round++) {
        NSArray<NSTextCheckingResult *> *matches = [IKNetBracketPattern() matchesInString:s options:0 range:NSMakeRange(0, s.length)];
        if (!matches.count) break;
        NSMutableString *rest = [s mutableCopy];
        for (NSTextCheckingResult *m in matches.reverseObjectEnumerator) {
            [extras addObject:[s substringWithRange:[m rangeAtIndex:1]]];
            [rest replaceCharactersInRange:m.range withString:@" "];
        }
        s = rest;
    }
    NSTextCheckingResult *suffix = [IKNetSuffixPattern() firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (suffix && suffix.range.location > 0) {
        [extras addObject:[s substringWithRange:[suffix rangeAtIndex:1]]];
        s = [s substringToIndex:suffix.range.location];
    }
    // 不成对的括号（如 “晴天 (女声版))”）和多余空白
    static NSCharacterSet *stray;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ stray = [NSCharacterSet characterSetWithCharactersInString:@"()[]【】〔〕〈〉<>「」『』"]; });
    NSString *spaced = [[s componentsSeparatedByCharactersInSet:stray] componentsJoinedByString:@" "];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *w in [spaced componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
        if (w.length) [words addObject:w];
    s = [words componentsJoinedByString:@" "];
    return s.length ? s : title;
}

NSString *IKNetBaseTitle(NSString *title) {
    return IKNetSplitTitle(title, [NSMutableArray array]);
}

NSSet<NSString *> *IKNetVersionTags(NSString *title) {
    // 这些词出现在版本说明里，说明是另一段录音或另一种编排，时间轴对不上
    static NSArray<NSString *> *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        words = @[@"live", @"现场", @"演唱会", @"concert", @"音乐会", @"unplugged", @"不插电",
                  @"remix", @"mix", @"混音", @"dj", @"抖音", @"慢摇", @"电音", @"edm",
                  @"伴奏", @"instrumental", @"inst", @"karaoke", @"卡拉ok", @"纯音乐", @"offvocal", @"消音", @"伴唱",
                  @"钢琴", @"piano", @"吉他", @"guitar", @"八音盒", @"musicbox", @"古筝", @"二胡", @"小提琴", @"violin",
                  @"交响", @"管弦", @"orchestra", @"lofi", @"acoustic", @"清唱", @"acapella", @"cappella",
                  @"cover", @"翻唱", @"翻自", @"原唱", @"女声", @"男声", @"女版", @"男版", @"童声", @"合唱",
                  @"demo", @"试听", @"片段", @"铃声", @"加速", @"降调", @"升调", @"慢速", @"倍速",
                  @"spedup", @"slowed", @"reverb", @"nightcore"];
    });
    NSMutableArray<NSString *> *extras = [NSMutableArray array];
    IKNetSplitTitle(title, extras);
    NSMutableSet *tags = [NSMutableSet set];
    for (NSString *extra in extras) {
        NSString *n = IKNetNormalize(extra);
        if (!n.length) continue;
        for (NSString *word in words) if ([n containsString:word]) [tags addObject:word];
        // “国语版”“女声版”“完整版”……一律当作不同版本
        if ([n containsString:@"版"]) [tags addObject:[@"版:" stringByAppendingString:n]];
    }
    return tags;
}

static NSArray<NSString *> *IKNetArtistTokens(NSString *artist) {
    static NSRegularExpression *separators;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        separators = [NSRegularExpression regularExpressionWithPattern:
                      @"\\s*(?:/|&|,|、|;|，|；|\\+|\\||\\bfeat\\.?\\s|\\bft\\.?\\s|\\bwith\\s|\\sx\\s|\\svs\\.?\\s)\\s*"
                                                               options:NSRegularExpressionCaseInsensitive error:nil];
    });
    if (![artist isKindOfClass:NSString.class] || !artist.length) return @[];
    NSString *s = artist.precomposedStringWithCompatibilityMapping;
    NSString *split = [separators stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"\n"];
    NSMutableOrderedSet *tokens = [NSMutableOrderedSet orderedSet];
    NSMutableArray *pieces = [[split componentsSeparatedByString:@"\n"] mutableCopy];
    [pieces addObject:s];
    for (NSString *piece in pieces) {
        for (NSString *form in @[piece, IKNetBaseTitle(piece)]) {
            NSString *n = IKNetNormalize(form);
            if (n.length) [tokens addObject:n];
        }
    }
    return tokens.array;
}

static BOOL IKNetASCII(NSString *s) {
    return [s canBeConvertedToEncoding:NSASCIIStringEncoding];
}

BOOL IKNetArtistMatches(NSString *artist, NSArray<NSString *> *candidateArtists) {
    NSArray<NSString *> *mine = IKNetArtistTokens(artist);
    if (!mine.count || ![candidateArtists isKindOfClass:NSArray.class] || !candidateArtists.count) return NO;
    NSMutableArray<NSString *> *theirs = [NSMutableArray array];
    for (NSString *name in candidateArtists) [theirs addObjectsFromArray:IKNetArtistTokens(name)];
    NSString *joined = IKNetNormalize([candidateArtists componentsJoinedByString:@""]);
    if (joined.length) [theirs addObject:joined];
    for (NSString *a in mine) {
        for (NSString *b in theirs) {
            if ([a isEqual:b]) return YES;
            NSString *shorter = a.length < b.length ? a : b;
            // 只认足够长的包含关系：“周杰伦 (Jay Chou)” 含 “周杰伦”
            NSUInteger least = IKNetASCII(shorter) ? 3 : 2;
            if (shorter.length >= least && ([a containsString:b] || [b containsString:a])) return YES;
        }
    }
    return NO;
}

double IKNetScoreCandidate(NSDictionary *candidate, NSString *title, NSString *artist, BOOL artistReliable, double duration) {
    NSString *theirs = candidate[@"title"];
    NSString *a = IKNetNormalize(title), *b = IKNetNormalize(theirs);
    if (!a.length || !b.length) return -1;
    double score;
    if ([a isEqual:b]) score = 100;
    else {
        NSString *baseA = IKNetNormalize(IKNetBaseTitle(title)), *baseB = IKNetNormalize(IKNetBaseTitle(theirs));
        if (!baseA.length || ![baseA isEqual:baseB] || ![IKNetVersionTags(title) isEqual:IKNetVersionTags(theirs)]) return -1;
        score = 70;
    }
    BOOL hasArtist = IKNetNormalize(artist).length > 0;
    BOOL artistMatches = hasArtist && IKNetArtistMatches(artist, candidate[@"artists"]);
    if (artistMatches) score += 50;
    else if (artistReliable && hasArtist) return -1;   // 同名翻唱：宁可不匹配
    double theirDuration = [candidate[@"duration"] isKindOfClass:NSNumber.class] ? [candidate[@"duration"] doubleValue] : 0;
    if (duration > 0 && isfinite(duration)) {
        if (!(theirDuration > 0) || !isfinite(theirDuration)) return -1;
        double delta = fabs(theirDuration - duration);
        if (delta > IKNetLyricsMaxDurationDelta) return -1;
        score += (IKNetLyricsMaxDurationDelta - delta) * 10;
    } else if (!artistMatches) return -1;
    return score;
}

NSArray<NSDictionary *> *IKNetRankCandidates(NSArray<NSDictionary *> *candidates, NSString *title, NSString *artist,
                                             BOOL artistReliable, double duration) {
    NSMutableArray *scored = [NSMutableArray array];
    for (NSDictionary *c in candidates) {
        double s = IKNetScoreCandidate(c, title, artist, artistReliable, duration);
        if (s >= 0) [scored addObject:@[@(s), c]];
    }
    [scored sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *x, NSArray *y) {
        return [y[0] compare:x[0]];
    }];
    NSMutableArray *ranked = [NSMutableArray array];
    for (NSArray *pair in scored) [ranked addObject:pair[1]];
    return ranked;
}

#pragma mark - 解析

static NSDictionary *IKNetJSON(NSData *data) {
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > IKNetLyricsMaxBytes) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!value) {
        // 兼容 JSONP 回调包装
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSRange open = [text rangeOfString:@"{"], close = [text rangeOfString:@"}" options:NSBackwardsSearch];
        if (open.location != NSNotFound && close.location != NSNotFound && close.location > open.location) {
            NSString *body = [text substringWithRange:NSMakeRange(open.location, close.location - open.location + 1)];
            value = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        }
    }
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSString *IKNetString(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *s = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length && s.length <= 512 ? s : nil;
}

static NSArray<NSString *> *IKNetNames(id list) {
    NSMutableArray *names = [NSMutableArray array];
    if (![list isKindOfClass:NSArray.class]) return names;
    for (NSDictionary *item in list) {
        NSString *name = [item isKindOfClass:NSDictionary.class] ? IKNetString(item[@"name"]) : nil;
        if (name) [names addObject:name];
    }
    return names;
}

static BOOL IKNetCode(NSDictionary *root, NSString *key, NSInteger expected) {
    return [root[key] respondsToSelector:@selector(integerValue)] && [root[key] integerValue] == expected;
}

NSArray<NSDictionary *> *IKNetParseSearch(NSString *provider, NSData *json) {
    NSDictionary *root = IKNetJSON(json);
    if (!root) return nil;
    NSMutableArray *candidates = [NSMutableArray array];
    if ([provider isEqual:IKNetProviderQQ]) {
        if (!IKNetCode(root, @"code", 0)) return nil;
        NSDictionary *data = [root[@"data"] isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
        NSDictionary *song = [data[@"song"] isKindOfClass:NSDictionary.class] ? data[@"song"] : nil;
        if (!song) return nil;
        NSArray *list = [song[@"list"] isKindOfClass:NSArray.class] ? song[@"list"] : @[];
        for (NSDictionary *s in list) {
            if (![s isKindOfClass:NSDictionary.class]) continue;
            NSString *mid = IKNetString(s[@"songmid"]), *name = IKNetString(s[@"songname"]);
            if (!mid || !name) continue;
            double seconds = [s[@"interval"] respondsToSelector:@selector(doubleValue)] ? [s[@"interval"] doubleValue] : 0;
            [candidates addObject:@{@"provider":IKNetProviderQQ, @"id":mid, @"title":name, @"artists":IKNetNames(s[@"singer"]),
                                    @"duration":@(isfinite(seconds) ? seconds : 0), @"album":IKNetString(s[@"albumname"]) ?: @""}];
        }
        return candidates;
    }
    if ([provider isEqual:IKNetProviderNetease]) {
        // 境外 IP 会拿到 abroad=true 和加密的 result，当作接口不可用
        if (!IKNetCode(root, @"code", 200) || [root[@"abroad"] isEqual:@YES]) return nil;
        NSDictionary *result = root[@"result"];
        if (![result isKindOfClass:NSDictionary.class]) return result ? nil : candidates;
        NSArray *songs = [result[@"songs"] isKindOfClass:NSArray.class] ? result[@"songs"] : @[];
        for (NSDictionary *s in songs) {
            if (![s isKindOfClass:NSDictionary.class]) continue;
            NSString *songID = IKNetString(s[@"id"]), *name = IKNetString(s[@"name"]);
            if (!songID || !name) continue;
            id ms = s[@"duration"] ?: s[@"dt"];
            double seconds = [ms respondsToSelector:@selector(doubleValue)] ? [ms doubleValue] / 1000.0 : 0;
            NSDictionary *album = [s[@"album"] ?: s[@"al"] isKindOfClass:NSDictionary.class] ? (s[@"album"] ?: s[@"al"]) : nil;
            [candidates addObject:@{@"provider":IKNetProviderNetease, @"id":songID, @"title":name,
                                    @"artists":IKNetNames(s[@"artists"] ?: s[@"ar"]), @"duration":@(isfinite(seconds) ? seconds : 0),
                                    @"album":IKNetString(album[@"name"]) ?: @""}];
        }
        return candidates;
    }
    return nil;
}

static BOOL IKNetInstrumentalText(NSString *text) {
    return [text containsString:@"纯音乐"] && ([text containsString:@"欣赏"] || [text containsString:@"没有填词"]);
}

static NSString *IKNetDecodeEntities(NSString *s) {
    if (![s containsString:@"&"]) return s;
    static NSRegularExpression *entity;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        entity = [NSRegularExpression regularExpressionWithPattern:@"&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|apos|quot|amp|lt|gt|nbsp);"
                                                           options:0 error:nil];
    });
    NSDictionary *named = @{@"apos":@"'", @"quot":@"\"", @"amp":@"&", @"lt":@"<", @"gt":@">", @"nbsp":@" "};
    NSMutableString *out = [s mutableCopy];
    NSArray *matches = [entity matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    for (NSTextCheckingResult *m in matches.reverseObjectEnumerator) {
        NSString *body = [s substringWithRange:[m rangeAtIndex:1]];
        NSString *replacement = named[body];
        if (!replacement) {
            unsigned long long code = 0;
            NSScanner *scanner = [NSScanner scannerWithString:[body substringFromIndex:[body hasPrefix:@"#x"] ? 2 : 1]];
            BOOL ok = [body hasPrefix:@"#x"] ? [scanner scanHexLongLong:&code] : [scanner scanUnsignedLongLong:&code];
            if (!ok || code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) continue;
            UTF32Char c = (UTF32Char)code;
            replacement = [[NSString alloc] initWithBytes:&c length:sizeof(c) encoding:NSUTF32LittleEndianStringEncoding];
            if (!replacement) continue;
        }
        [out replaceCharactersInRange:m.range withString:replacement];
    }
    return out;
}

NSString *IKNetParseLyric(NSString *provider, NSData *json, NSString **reason) {
    NSString *why = @"bad-response";
    NSString *lyric = nil;
    NSDictionary *root = IKNetJSON(json);
    if ([provider isEqual:IKNetProviderQQ] && root) {
        if (!IKNetCode(root, @"code", 0) && !IKNetCode(root, @"retcode", 0)) why = @"api";
        else {
            lyric = [root[@"lyric"] isKindOfClass:NSString.class] ? root[@"lyric"] : nil;
            if (lyric.length && ![lyric containsString:@"["]) {
                // nobase64 不生效时仍是 Base64
                NSData *decoded = [[NSData alloc] initWithBase64EncodedString:lyric options:NSDataBase64DecodingIgnoreUnknownCharacters];
                NSString *text = decoded.length ? [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] : nil;
                if (text) lyric = text;
            }
            lyric = lyric.length ? IKNetDecodeEntities(lyric) : nil;
            why = @"no-lyrics";
        }
    } else if ([provider isEqual:IKNetProviderNetease] && root) {
        if (!IKNetCode(root, @"code", 200)) why = @"api";
        else if ([root[@"pureMusic"] isEqual:@YES]) why = @"instrumental";
        else {
            NSDictionary *lrc = [root[@"lrc"] isKindOfClass:NSDictionary.class] ? root[@"lrc"] : nil;
            lyric = [lrc[@"lyric"] isKindOfClass:NSString.class] && [lrc[@"lyric"] length] ? lrc[@"lyric"] : nil;
            why = @"no-lyrics";
        }
    }
    if (lyric && IKNetInstrumentalText(lyric) && lyric.length < 200) { lyric = nil; why = @"instrumental"; }
    if (!lyric && reason) *reason = why;
    return lyric;
}

NSArray<NSDictionary *> *IKNetTimedLines(NSString *lrc, double duration, NSString **reason) {
    NSArray<NSDictionary *> *lines = IKParseTimedLyrics(lrc, duration);
    if (lines.count <= 3) {
        for (NSDictionary *line in lines) {
            if (IKNetInstrumentalText(line[@"text"])) { if (reason) *reason = @"instrumental"; return nil; }
        }
    }
    if (lines.count < 3) { if (reason) *reason = @"no-timeline"; return nil; }
    return lines;
}

BOOL IKNetLinesContainEvidence(NSArray<NSDictionary *> *lines, NSArray<NSString *> *evidence) {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSDictionary *line in lines) {
        NSString *n = IKNetNormalize(line[@"text"]);
        if (n.length) [texts addObject:n];
    }
    for (NSString *seen in evidence) {
        NSString *a = IKNetNormalize(seen);
        if (a.length < 2) continue;
        for (NSString *b in texts) {
            if ([a isEqual:b] || [b containsString:a] || (b.length >= 4 && [a containsString:b])) return YES;
        }
    }
    return NO;
}

#pragma mark - 查询流程

@implementation IKNetLyricsResult
@end

@interface IKNetLookup : NSObject
@property (nonatomic, copy) IKNetTransport transport;
@property (nonatomic, copy) NSArray<NSString *> *providers;
@property (nonatomic, copy) NSString *title, *artist;
@property (nonatomic) BOOL artistReliable;
@property (nonatomic) double duration;
@property (nonatomic, copy) NSArray<NSString *> *evidence;
@property (nonatomic) NSUInteger providerIndex, candidateIndex;
@property (nonatomic, copy) NSArray<NSDictionary *> *ranked;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *attempts;
@property (nonatomic, strong) IKNetLyricsResult *result;
@property (nonatomic, copy) void (^done)(IKNetLyricsResult *result);
@end

@implementation IKNetLookup

- (NSString *)provider { return self.providers[self.providerIndex]; }

- (double)deltaFor:(NSDictionary *)candidate {
    double theirs = [candidate[@"duration"] doubleValue];
    return self.duration > 0 && theirs > 0 ? fabs(theirs - self.duration) : -1;
}

- (void)record:(NSString *)status reason:(NSString *)reason candidate:(NSDictionary *)candidate lines:(NSUInteger)lines {
    NSMutableDictionary *attempt = [@{@"provider":self.provider, @"status":status, @"reason":reason ?: @"", @"lines":@(lines)} mutableCopy];
    double delta = candidate ? [self deltaFor:candidate] : -1;
    if (delta >= 0) attempt[@"dt"] = @(delta);
    [self.attempts addObject:attempt];
    if (![status isEqual:@"hit"]) self.result.reason = reason;
}

- (void)nextProvider {
    if (self.providerIndex >= self.providers.count) { [self finish]; return; }
    NSString *query = self.title;
    if (self.artistReliable && self.artist.length) query = [NSString stringWithFormat:@"%@ %@", self.title, self.artist];
    NSURLRequest *request = IKNetSearchRequest(self.provider, query);
    if (!request) { [self record:@"error" reason:@"bad-request" candidate:nil lines:0]; [self advance]; return; }
    self.transport(request, ^(NSData *data, NSInteger status, NSError *error) {
        [self searched:data status:status error:error];
    });
}

- (void)advance {
    self.providerIndex++;
    [self nextProvider];
}

- (void)searched:(NSData *)data status:(NSInteger)status error:(NSError *)error {
    if (error || status != 200) {
        [self record:@"error" reason:error ? @"network" : @"http" candidate:nil lines:0];
        [self advance];
        return;
    }
    NSArray *candidates = IKNetParseSearch(self.provider, data);
    if (!candidates) { [self record:@"error" reason:@"bad-response" candidate:nil lines:0]; [self advance]; return; }
    self.ranked = IKNetRankCandidates(candidates, self.title, self.artist, self.artistReliable, self.duration);
    if (!self.ranked.count) { [self record:@"miss" reason:@"no-match" candidate:nil lines:0]; [self advance]; return; }
    self.candidateIndex = 0;
    [self fetchLyric];
}

- (void)fetchLyric {
    NSDictionary *candidate = self.ranked[self.candidateIndex];
    NSURLRequest *request = IKNetLyricRequest(self.provider, candidate[@"id"]);
    if (!request) { [self record:@"error" reason:@"bad-request" candidate:candidate lines:0]; [self advance]; return; }
    self.transport(request, ^(NSData *data, NSInteger status, NSError *error) {
        [self fetched:data status:status error:error candidate:candidate];
    });
}

- (void)fetched:(NSData *)data status:(NSInteger)status error:(NSError *)error candidate:(NSDictionary *)candidate {
    if (error || status != 200) {
        [self record:@"error" reason:error ? @"network" : @"http" candidate:candidate lines:0];
        [self advance];
        return;
    }
    NSString *reason = nil;
    NSString *lrc = IKNetParseLyric(self.provider, data, &reason);
    NSArray *lines = lrc ? IKNetTimedLines(lrc, self.duration, &reason) : nil;
    if (lines && self.evidence.count && !IKNetLinesContainEvidence(lines, self.evidence)) {
        lines = nil;
        reason = @"lyric-mismatch";
    }
    if (!lines) {
        // 同一首歌在别的专辑里可能有歌词、同名候选可能是另一首；纯音乐和接口错误不再试
        BOOL retry = ([reason isEqual:@"no-lyrics"] || [reason isEqual:@"no-timeline"] || [reason isEqual:@"lyric-mismatch"]) &&
                     self.candidateIndex + 1 < MIN(self.ranked.count, (NSUInteger)3);
        if (retry) { self.candidateIndex++; [self fetchLyric]; return; }
        BOOL failed = [reason isEqual:@"api"] || [reason isEqual:@"bad-response"];
        [self record:failed ? @"error" : @"miss" reason:reason candidate:candidate lines:0];
        [self advance];
        return;
    }
    IKNetLyricsResult *r = self.result;
    r.status = @"hit";
    r.provider = self.provider;
    r.songID = candidate[@"id"];
    r.lrc = lrc;
    r.lines = lines;
    r.candidateDuration = [candidate[@"duration"] doubleValue];
    r.durationDelta = [self deltaFor:candidate];
    r.reason = nil;
    [self record:@"hit" reason:nil candidate:candidate lines:lines.count];
    [self finish];
}

- (void)finish {
    IKNetLyricsResult *r = self.result;
    if (![r.status isEqual:@"hit"]) {
        BOOL answered = NO;
        for (NSDictionary *a in self.attempts) answered |= [a[@"status"] isEqual:@"miss"];
        r.status = answered ? @"miss" : @"error";
    }
    r.attempts = self.attempts;
    void (^done)(IKNetLyricsResult *) = self.done;
    self.done = nil;
    if (done) done(r);
}
@end

@implementation IKNetLyricsClient {
    NSMutableDictionary<NSString *, NSDictionary *> *_failures;
}

+ (instancetype)shared {
    static IKNetLyricsClient *client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ client = [IKNetLyricsClient new]; });
    return client;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _failures = [NSMutableDictionary dictionary];
    _retryAfter = 300;
    _clock = ^double { return NSProcessInfo.processInfo.systemUptime; };
    return self;
}

static NSString *IKNetFailureKey(NSString *bundleID, NSString *title, NSString *artist, double duration) {
    return [NSString stringWithFormat:@"%@\n%@\n%@\n%lld", bundleID.lowercaseString ?: @"", IKNetNormalize(title),
            IKNetNormalize(artist), (long long)llround(isfinite(duration) ? MAX(0, duration) : 0)];
}

- (BOOL)lookupBundle:(NSString *)bundleID title:(NSString *)title artist:(NSString *)artist
      artistReliable:(BOOL)artistReliable duration:(double)duration evidence:(NSArray<NSString *> *)evidence
          completion:(void (^)(IKNetLyricsResult *result))completion {
    if (!IKNetNormalize(title).length || !completion) return NO;
    BOOL reliable = artistReliable && IKNetNormalize(artist).length > 0;
    NSString *key = IKNetFailureKey(bundleID, title, reliable ? artist : @"", duration);
    double (^clock)(void) = self.clock ?: ^double { return NSProcessInfo.processInfo.systemUptime; };
    @synchronized (self) {
        NSDictionary *failure = _failures[key];
        // 失败过一次：retryAfter 之后放行一次；再失败就到本次运行结束都不再查
        if (failure && ([failure[@"count"] integerValue] >= 2 || clock() - [failure[@"at"] doubleValue] < self.retryAfter)) return NO;
    }
    IKNetLookup *lookup = [IKNetLookup new];
    lookup.transport = self.transport ?: IKNetDefaultTransport();
    lookup.providers = IKNetProviderOrder(bundleID);
    lookup.title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    lookup.artist = [artist isKindOfClass:NSString.class] ? artist : @"";
    lookup.artistReliable = reliable;
    lookup.duration = isfinite(duration) && duration > 0 ? duration : 0;
    lookup.evidence = [evidence isKindOfClass:NSArray.class] ? evidence : nil;
    lookup.attempts = [NSMutableArray array];
    lookup.result = [IKNetLyricsResult new];
    lookup.result.durationDelta = -1;
    lookup.done = ^(IKNetLyricsResult *result) {
        @synchronized (self) {
            if ([result.status isEqual:@"hit"]) [self->_failures removeObjectForKey:key];
            else {
                NSInteger count = [self->_failures[key][@"count"] integerValue] + 1;
                self->_failures[key] = @{@"count":@(count), @"at":@(clock())};
            }
        }
        completion(result);
    };
    [lookup nextProvider];
    return YES;
}
@end
