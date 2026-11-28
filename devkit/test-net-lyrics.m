// 联网歌词：用 devkit/fixtures/net-lyrics 里裁剪过的真实返回验证解析、打分、LRC 提取和查询流程。
// 网络层换成按 URL 取夹具的 block，不联网。
//   用法：test-net-lyrics <夹具目录>      离线测试
//         test-net-lyrics --live          真实联网冒烟（只发歌名和歌手）
#import "IKNetLyrics.h"
#import "IKLyricsTimeline.h"

static int count;
static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL %s\n", message); exit(1); }
    count++;
}

static NSString *fixtures;
static NSData *fixture(NSString *name) {
    NSData *d = [NSData dataWithContentsOfFile:[fixtures stringByAppendingPathComponent:name]];
    if (!d) { fprintf(stderr, "missing fixture %s\n", name.UTF8String); exit(2); }
    return d;
}
static NSData *json(NSDictionary *object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }

static NSString *param(NSURL *url, NSString *name) {
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)
        if ([item.name isEqual:name]) return item.value;
    return nil;
}
static NSArray *paramNames(NSURL *url) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) [names addObject:item.name];
    return names;
}

static NSDictionary *candidate(NSString *title, NSArray *artists, double duration) {
    return @{@"provider":@"qq", @"id":@"x", @"title":title, @"artists":artists, @"duration":@(duration)};
}
static NSArray *ids(NSArray<NSDictionary *> *ranked) { return [ranked valueForKey:@"id"]; }

#pragma mark 假网络

static NSMutableArray<NSURLRequest *> *requests;
// 路由：返回 nil 表示网络错误
typedef NSData *(^IKRoute)(NSURL *url, NSInteger *status);
static IKNetTransport fakeTransport(IKRoute route) {
    return ^(NSURLRequest *request, IKNetReply reply) {
        [requests addObject:request];
        NSInteger status = 200;
        NSData *data = route(request.URL, &status);
        reply(data, data ? status : 0, data ? nil : [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
    };
}

// 按真实接口的 URL 取夹具
static NSData *fixtureRoute(NSURL *url, NSDictionary<NSString *, NSString *> *lyricOverrides) {
    NSString *host = url.host, *path = url.path;
    if ([host isEqual:@"c.y.qq.com"] && [path hasSuffix:@"client_search_cp"]) {
        NSString *w = param(url, @"w");
        if ([w hasPrefix:@"晴天"]) return fixture(@"qq-search-qingtian.json");
        if ([w hasPrefix:@"Don't Stop Me Now"]) return fixture(@"qq-search-dontstop.json");
        if ([w hasPrefix:@"River Flows"]) return fixture(@"qq-search-river.json");
        return json(@{@"code":@0, @"data":@{@"song":@{@"list":@[]}}});
    }
    if ([host isEqual:@"c.y.qq.com"] && [path hasSuffix:@"fcg_query_lyric_new.fcg"]) {
        NSString *mid = param(url, @"songmid");
        if (lyricOverrides[mid]) return [lyricOverrides[mid] dataUsingEncoding:NSUTF8StringEncoding];
        if ([mid isEqual:@"002JK2Tm09Vorr"]) return fixture(@"qq-lyric-pure.json");
        return fixture(@"qq-lyric-qingtian.json");
    }
    if ([host isEqual:@"music.163.com"] && [path isEqual:@"/api/search/get/web"]) {
        NSString *s = param(url, @"s");
        if ([s hasPrefix:@"晴天"]) return fixture(@"netease-search-qingtian.json");
        if ([s hasPrefix:@"十年"]) return fixture(@"netease-search-shinian.json");
        if ([s hasPrefix:@"River Flows"]) return fixture(@"netease-search-river.json");
        return json(@{@"result":@{@"songCount":@0}, @"code":@200});
    }
    if ([host isEqual:@"music.163.com"] && [path isEqual:@"/api/song/lyric"]) {
        NSString *songID = param(url, @"id");
        if ([songID isEqual:@"66842"]) return fixture(@"netease-lyric-shinian.json");
        if ([songID isEqual:@"22829932"]) return fixture(@"netease-lyric-pure.json");
        return json(@{@"nolyric":@YES, @"code":@200});
    }
    return nil;
}

static IKNetLyricsResult *lookup(IKNetLyricsClient *client, NSString *bid, NSString *title, NSString *artist, BOOL reliable,
                                 double duration, NSArray *evidence, BOOL *started) {
    __block IKNetLyricsResult *out = nil;
    BOOL ok = [client lookupBundle:bid title:title artist:artist artistReliable:reliable duration:duration evidence:evidence
                        completion:^(IKNetLyricsResult *result) { out = result; }];
    if (started) *started = ok;
    return out;
}

static NSString *attemptSummary(IKNetLyricsResult *r) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSDictionary *a in r.attempts) [parts addObject:[NSString stringWithFormat:@"%@:%@:%@", a[@"provider"], a[@"status"], a[@"reason"]]];
    return [parts componentsJoinedByString:@","];
}

#pragma mark 离线测试

static void testNormalize(void) {
    check([IKNetNormalize(@"Ｄｏｎ’ｔ　Ｓｔｏｐ Ｍｅ Ｎｏｗ") isEqual:@"dontstopmenow"] &&
          [IKNetNormalize(@"Don't stop me now") isEqual:@"dontstopmenow"], "full-width, case, space and punctuation");
    check([IKNetNormalize(@"陳奕迅") isEqual:IKNetNormalize(@"陈奕迅")], "traditional and simplified Chinese compare equal");
    check([IKNetBaseTitle(@"晴天（Live）") isEqual:@"晴天"] && [IKNetBaseTitle(@"晴天 (女声版))") isEqual:@"晴天"] &&
          [IKNetBaseTitle(@"Don't Stop Me Now - Remastered 2011") isEqual:@"Don't Stop Me Now"], "strip bracketed and dashed version notes");
    check([IKNetVersionTags(@"晴天 (Live)") containsObject:@"live"] && [IKNetVersionTags(@"晴天 (原唱 周杰伦)") containsObject:@"原唱"] &&
          [IKNetVersionTags(@"十年 (国语版)") containsObject:@"版:国语版"] && !IKNetVersionTags(@"Don't Stop Me Now (2011 Remaster)").count &&
          !IKNetVersionTags(@"Live While We're Young").count, "version tags only come from version notes");
    check(IKNetArtistMatches(@"林俊杰/周杰伦", @[@"周杰伦"]) && IKNetArtistMatches(@"周杰伦 (Jay Chou)", @[@"周杰伦"]) &&
          IKNetArtistMatches(@"Queen & Adam Lambert", @[@"Queen"]) && IKNetArtistMatches(@"陳奕迅", @[@"陈奕迅"]),
          "multi-artist and annotated artist fields");
    check(!IKNetArtistMatches(@"故事的小黄花", @[@"周杰伦"]) && !IKNetArtistMatches(@"Jay", @[@"周杰伦"]) &&
          !IKNetArtistMatches(@"", @[@"周杰伦"]) && !IKNetArtistMatches(@"ab", @[@"abc"]), "unrelated or too-short artists");
    check([IKNetProviderOrder(@"com.netease.cloudmusic") isEqual:(@[@"netease", @"qq"])] &&
          [IKNetProviderOrder(@"com.tencent.QQMusic") isEqual:(@[@"qq", @"netease"])] &&
          [IKNetProviderOrder(@"com.apple.Music") isEqual:(@[@"qq", @"netease"])], "provider order follows the playing app");
}

static void testSearchParsing(void) {
    NSArray *qq = IKNetParseSearch(@"qq", fixture(@"qq-search-qingtian.json"));
    check(qq.count == 8 && [qq[0][@"id"] isEqual:@"0039MnYb0qxYhV"] && [qq[0][@"title"] isEqual:@"晴天"] &&
          [qq[0][@"duration"] doubleValue] == 269 && [qq[0][@"artists"] isEqual:@[@"周杰伦"]] && [qq[0][@"album"] isEqual:@"叶惠美"],
          "QQ client_search_cp song list");
    check([qq[3][@"artists"] isEqual:(@[@"林俊杰", @"周杰伦"])], "QQ multi-singer candidate");
    NSArray *ne = IKNetParseSearch(@"netease", fixture(@"netease-search-qingtian.json"));
    check(ne.count == 8 && [ne[0][@"id"] isEqual:@"2668397359"] && fabs([ne[0][@"duration"] doubleValue] - 270.738) < 0.001 &&
          [ne[0][@"artists"] isEqual:@[@"RyaVocal"]], "NetEase search/get/web song list with millisecond durations");
    check(IKNetParseSearch(@"netease", fixture(@"netease-search-shinian.json")).count == 8, "NetEase second fixture");
    // 实测：musicu.fcg 不签名时 req_1.code=2001、列表为空
    NSData *musicu = json(@{@"code":@0, @"req_1":@{@"code":@2001, @"data":@{@"body":@{@"song":@{@"list":@[]}}}}});
    check(!IKNetParseSearch(@"qq", musicu), "unsigned musicu response is treated as unusable, not as zero results");
    check(!IKNetParseSearch(@"qq", json(@{@"code":@-1})) && !IKNetParseSearch(@"netease", json(@{@"code":@-460, @"msg":@"Cheating"})) &&
          !IKNetParseSearch(@"netease", json(@{@"abroad":@YES, @"code":@200, @"result":@"ENCRYPTED"})) &&
          !IKNetParseSearch(@"qq", [@"<html>" dataUsingEncoding:NSUTF8StringEncoding]), "error codes, abroad payloads and HTML");
    check([IKNetParseSearch(@"netease", json(@{@"result":@{@"songCount":@0}, @"code":@200})) isEqual:@[]] &&
          [IKNetParseSearch(@"qq", json(@{@"code":@0, @"data":@{@"song":@{@"list":@[]}}})) isEqual:@[]], "empty results are not errors");
    NSMutableData *huge = [NSMutableData dataWithData:fixture(@"qq-search-qingtian.json")];
    [huge increaseLengthBy:IKNetLyricsMaxBytes];
    check(!IKNetParseSearch(@"qq", huge), "response over 512KB is rejected");
    NSData *jsonp = [@"callback({\"code\":0,\"data\":{\"song\":{\"list\":[]}}})" dataUsingEncoding:NSUTF8StringEncoding];
    check([IKNetParseSearch(@"qq", jsonp) isEqual:@[]], "JSONP wrapper");
}

static void testScoring(void) {
    NSArray *qq = IKNetParseSearch(@"qq", fixture(@"qq-search-qingtian.json"));
    NSArray *ranked = IKNetRankCandidates(qq, @"晴天", @"周杰伦", YES, 269.4);
    check([ids(ranked) isEqual:(@[@"0039MnYb0qxYhV", @"004OmEt53sLWcn"])], "studio versions ranked by duration, Live versions dropped");
    ranked = IKNetRankCandidates(qq, @"晴天 (Live)", @"周杰伦", YES, 249.2);
    check([ids(ranked) isEqual:@[@"004Fs2FP1EvZYc"]], "playing the Live version picks the matching Live recording only");
    // 现场版和录音室版时长碰巧接近：版本标记决定
    NSArray *same = @[candidate(@"晴天 (Live)", @[@"周杰伦"], 269), candidate(@"晴天", @[@"周杰伦"], 270)];
    check([IKNetRankCandidates(same, @"晴天", @"周杰伦", YES, 269.2).firstObject[@"title"] isEqual:@"晴天"] &&
          IKNetRankCandidates(same, @"晴天", @"周杰伦", YES, 269.2).count == 1, "studio playback never takes a same-length Live");
    check([IKNetRankCandidates(same, @"晴天 (Live)", @"周杰伦", YES, 269.2).firstObject[@"title"] isEqual:@"晴天 (Live)"] &&
          IKNetRankCandidates(same, @"晴天（Live）", @"周杰伦", YES, 269.2).count == 1, "Live playback never takes the studio take");
    check(!IKNetRankCandidates(qq, @"晴天", @"周杰伦", YES, 275).count, "duration difference over 3 seconds rejects");
    check(IKNetScoreCandidate(candidate(@"晴天", @[@"周杰伦"], 272.4), @"晴天", @"周杰伦", YES, 269.4) >= 0 &&
          IKNetScoreCandidate(candidate(@"晴天", @[@"周杰伦"], 272.5), @"晴天", @"周杰伦", YES, 269.4) < 0, "3 second boundary");
    check(IKNetScoreCandidate(candidate(@"晴天", @[@"周杰伦"], 0), @"晴天", @"周杰伦", YES, 269.4) < 0, "candidate without duration");
    // 歌手字段被车载歌词占用
    ranked = IKNetRankCandidates(qq, @"晴天", @"故事的小黄花", NO, 269.2);
    check([ids(ranked).firstObject isEqual:@"0039MnYb0qxYhV"], "unreliable artist falls back to title and duration");
    check(!IKNetRankCandidates(qq, @"晴天", @"故事的小黄花", YES, 269.2).count, "reliable but different artist rejects");
    ranked = IKNetRankCandidates(qq, @"晴天", @"晴天 - 周杰伦 (Jay Chou)", NO, 269.2);
    check([ids(ranked).firstObject isEqual:@"0039MnYb0qxYhV"], "car lyric that names the singer still earns the artist bonus");
    // 时长未知
    check([ids(IKNetRankCandidates(qq, @"晴天", @"周杰伦", YES, 0)) isEqual:(@[@"0039MnYb0qxYhV", @"004OmEt53sLWcn"])] &&
          !IKNetRankCandidates(qq, @"晴天", @"故事的小黄花", NO, 0).count && !IKNetRankCandidates(qq, @"晴天", nil, NO, 0).count,
          "unknown duration accepts only title and artist together");
    // 网易云没有原唱版权，搜到的全是翻唱
    NSArray *ne = IKNetParseSearch(@"netease", fixture(@"netease-search-qingtian.json"));
    check(!IKNetRankCandidates(ne, @"晴天", @"周杰伦", YES, 269.4).count, "same-title covers by other singers are rejected");
    check(!IKNetRankCandidates(ne, @"晴天", @"故事的小黄花", NO, 270.5).count && !IKNetRankCandidates(ne, @"晴天", @"", NO, 268.8).count,
          "\"(原唱 周杰伦)\" and \"(女声版)\" covers rejected even within 3 seconds");
    NSArray *shinian = IKNetParseSearch(@"netease", fixture(@"netease-search-shinian.json"));
    check([ids(IKNetRankCandidates(shinian, @"十年", @"陈奕迅", YES, 205.4)) isEqual:(@[@"66842", @"65326"])],
          "NetEase picks the closest same recording, not 国语版 or Live");
    check([ids(IKNetRankCandidates(shinian, @"十年 (国语版)", @"陈奕迅", YES, 205.5)) isEqual:@[@"26608828"]], "explicit 国语版 playback");
    NSArray *queen = IKNetParseSearch(@"qq", fixture(@"qq-search-dontstop.json"));
    ranked = IKNetRankCandidates(queen, @"Ｄｏｎ’ｔ Ｓｔｏｐ Ｍｅ Ｎｏｗ", @"Queen", YES, 209.3);
    check([ids(ranked).firstObject isEqual:@"001sdIRl2GOEO3"] && [ids(ranked) containsObject:@"002POuXj2LtQkt"] &&
          ![ids(ranked) containsObject:@"000aWvC20Hvssg"], "exact title beats a remaster note; Live dropped");
}

static void testLyrics(void) {
    NSString *reason = nil;
    NSString *lrc = IKNetParseLyric(@"qq", fixture(@"qq-lyric-qingtian.json"), &reason);
    NSArray *lines = IKNetTimedLines(lrc, 269.4, &reason);
    check([lrc containsString:@"[offset:0]"] && lines.count == 24 && [lines[0][@"text"] isEqual:@"晴天 - 周杰伦 (Jay Chou)"],
          "QQ LRC extraction");
    NSUInteger i = IKCurrentLyricIndex(lines, 30);
    check(i != NSNotFound && [lines[i][@"text"] isEqual:@"故事的小黄花"] && fabs([lines[i][@"start"] doubleValue] - 29.26) < 0.001,
          "QQ timeline selects the line by position");
    lrc = IKNetParseLyric(@"netease", fixture(@"netease-lyric-shinian.json"), &reason);
    lines = IKNetTimedLines(lrc, 205.4, &reason);
    check(lines.count == 14 && [lines[7][@"text"] isEqual:@"如果那两个字没有颤抖"] && fabs([lines[7][@"start"] doubleValue] - 15.54) < 0.001,
          "NetEase LRC extraction");
    reason = nil;
    check(!IKNetParseLyric(@"qq", fixture(@"qq-lyric-pure.json"), &reason) && [reason isEqual:@"instrumental"], "QQ pure-music notice");
    reason = nil;
    check(!IKNetParseLyric(@"netease", fixture(@"netease-lyric-pure.json"), &reason) && [reason isEqual:@"instrumental"], "NetEase pureMusic flag");
    reason = nil;
    check(!IKNetParseLyric(@"qq", fixture(@"qq-lyric-noreferer.json"), &reason) && [reason isEqual:@"api"], "QQ -1310 without Referer");
    reason = nil;
    check(!IKNetParseLyric(@"netease", json(@{@"nolyric":@YES, @"code":@200}), &reason) && [reason isEqual:@"no-lyrics"] &&
          !IKNetParseLyric(@"netease", json(@{@"uncollected":@YES, @"code":@200}), nil), "NetEase nolyric and uncollected");
    reason = nil;
    check(!IKNetTimedLines(@"[00:00.00]纯音乐，请欣赏", 200, &reason) && [reason isEqual:@"instrumental"], "notice inside LRC text");
    reason = nil;
    check(!IKNetTimedLines(@"没有时间标签的一行\n又一行", 200, &reason) && [reason isEqual:@"no-timeline"] &&
          !IKNetTimedLines(@"[00:01.00]甲\n[00:02.00]乙", 200, nil), "untimed or too short");
    // [offset:] 正数提前、负数推后（IKParseTimedLyrics 已处理）
    NSData *early = json(@{@"code":@0, @"lyric":@"[offset:500]\n[00:10.00]甲\n[00:20.00]乙\n[00:30.00]丙"});
    lines = IKNetTimedLines(IKNetParseLyric(@"qq", early, nil), 200, nil);
    check(lines.count == 3 && fabs([lines[0][@"start"] doubleValue] - 9.5) < 1e-9 && fabs([lines[2][@"start"] doubleValue] - 29.5) < 1e-9,
          "positive offset shows lines earlier");
    NSData *late = json(@{@"lrc":@{@"lyric":@"[offset:-250]\n[00:10.00]甲\n[00:20.00]乙\n[00:30.00]丙"}, @"code":@200});
    lines = IKNetTimedLines(IKNetParseLyric(@"netease", late, nil), 200, nil);
    check(lines.count == 3 && fabs([lines[0][@"start"] doubleValue] - 10.25) < 1e-9, "negative offset shows lines later");
    NSData *entities = json(@{@"code":@0, @"lyric":@"[00:01.00]Don&apos;t&#32;stop&#x21;\n[00:02.00]b\n[00:03.00]c"});
    lines = IKNetTimedLines(IKNetParseLyric(@"qq", entities, nil), 200, nil);
    check([lines[0][@"text"] isEqual:@"Don't stop!"], "HTML entities in old QQ responses");
    NSString *b64 = [[@"[00:01.00]甲\n[00:02.00]乙\n[00:03.00]丙" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    check(IKNetTimedLines(IKNetParseLyric(@"qq", json(@{@"code":@0, @"lyric":b64}), nil), 200, nil).count == 3, "Base64 lyric fallback");
    lines = IKNetTimedLines(IKNetParseLyric(@"qq", fixture(@"qq-lyric-qingtian.json"), nil), 269.4, nil);
    check(IKNetLinesContainEvidence(lines, @[@"故事的小黄花"]) && IKNetLinesContainEvidence(lines, @[@"故事的 小黄花！"]) &&
          !IKNetLinesContainEvidence(lines, @[@"完全不相干的一句"]) && !IKNetLinesContainEvidence(lines, @[]), "local car-lyric evidence");
}

static void testRequests(void) {
    NSURLRequest *search = IKNetSearchRequest(@"qq", @"晴天 周杰伦");
    check([search.URL.scheme isEqual:@"https"] && [search.URL.host isEqual:@"c.y.qq.com"] && [param(search.URL, @"w") isEqual:@"晴天 周杰伦"] &&
          [paramNames(search.URL) isEqual:(@[@"w", @"format", @"n", @"p", @"cr", @"t"])], "QQ search carries only the query");
    check(search.timeoutInterval == 6 && !search.HTTPShouldHandleCookies && ![search valueForHTTPHeaderField:@"Cookie"] &&
          [[search valueForHTTPHeaderField:@"User-Agent"] hasPrefix:@"Mozilla/5.0"] &&
          [[search valueForHTTPHeaderField:@"Referer"] isEqual:@"https://y.qq.com/"], "timeout, no cookie, generic UA, Referer");
    NSURLRequest *plus = IKNetSearchRequest(@"netease", @"C++ & A=B");
    check([plus.URL.absoluteString containsString:@"s=C%2B%2B%20%26%20A%3DB&"] && [param(plus.URL, @"s") isEqual:@"C++ & A=B"],
          "reserved characters are percent-encoded");
    NSURLRequest *lyric = IKNetLyricRequest(@"netease", @"66842");
    check([lyric.URL.absoluteString isEqual:@"https://music.163.com/api/song/lyric?id=66842&lv=1&kv=1&tv=-1"], "NetEase lyric URL");
    check([IKNetLyricRequest(@"qq", @"0039MnYb0qxYhV").URL.absoluteString
              isEqual:@"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=0039MnYb0qxYhV&format=json&nobase64=1"],
          "QQ lyric URL");
    check(!IKNetSearchRequest(@"qq", @"  ") && !IKNetSearchRequest(@"other", @"x") && !IKNetLyricRequest(@"qq", @""), "invalid requests");
}

static void testClient(void) {
    __block double now = 1000;
    IKNetLyricsClient *client = [IKNetLyricsClient new];
    client.clock = ^double { return now; };
    client.transport = fakeTransport(^NSData *(NSURL *url, NSInteger *status) { return fixtureRoute(url, nil); });

    requests = [NSMutableArray array];
    IKNetLyricsResult *r = lookup(client, @"com.tencent.QQMusic", @"晴天", @"周杰伦", YES, 269.4, nil, NULL);
    check([r.status isEqual:@"hit"] && [r.provider isEqual:@"qq"] && [r.songID isEqual:@"0039MnYb0qxYhV"] && r.lines.count == 24 &&
          fabs(r.durationDelta - 0.4) < 1e-6 && r.attempts.count == 1 && [r.lrc hasPrefix:@"[ti:"], "QQ app: QQ hit");
    check(requests.count == 2 && [param(requests[0].URL, @"w") isEqual:@"晴天 周杰伦"] &&
          [param(requests[1].URL, @"songmid") isEqual:@"0039MnYb0qxYhV"], "search then lyric, query is title and artist only");
    for (NSURLRequest *q in requests)
        check([q.URL.scheme isEqual:@"https"] && !q.HTTPShouldHandleCookies && q.timeoutInterval == 6 && !q.HTTPBody, "every request is a bare HTTPS GET");

    requests = [NSMutableArray array];
    r = lookup(client, @"com.netease.cloudmusic", @"晴天", @"周杰伦", YES, 269.4, nil, NULL);
    check([r.status isEqual:@"hit"] && [r.provider isEqual:@"qq"] && [attemptSummary(r) isEqual:@"netease:miss:no-match,qq:hit:"] &&
          [requests[0].URL.host isEqual:@"music.163.com"], "NetEase app: NetEase first, only covers there, then QQ");
    check([r.attempts[1][@"dt"] doubleValue] > 0.39 && !r.attempts[0][@"dt"], "attempt dt only when a candidate was chosen");

    r = lookup(client, @"com.netease.cloudmusic", @"十年", @"陈奕迅", YES, 205.4, nil, NULL);
    check([r.status isEqual:@"hit"] && [r.provider isEqual:@"netease"] && [r.songID isEqual:@"66842"] && r.lines.count == 14, "NetEase hit");

    r = lookup(client, @"com.netease.cloudmusic", @"River Flows in You", @"Yiruma", YES, 214.9, nil, NULL);
    check([r.status isEqual:@"miss"] && [attemptSummary(r) isEqual:@"netease:miss:instrumental,qq:miss:no-match"],
          "pure music is no timeline; QQ singer spelling differs and is rejected");
    r = lookup(client, @"com.tencent.QQMusic", @"River Flows in You", @"李闰珉", YES, 218.2, nil, NULL);
    check([attemptSummary(r) hasPrefix:@"qq:miss:instrumental"], "QQ pure-music notice");

    // 第一首候选没有歌词，换同名同长的第二首
    client.transport = fakeTransport(^NSData *(NSURL *url, NSInteger *status) {
        return fixtureRoute(url, @{@"0039MnYb0qxYhV":@"{\"code\":0,\"lyric\":\"\"}"});
    });
    r = lookup(client, @"com.tencent.QQMusic", @"晴天", @"周杰伦", YES, 269.4, nil, NULL);
    check([r.songID isEqual:@"004OmEt53sLWcn"] && fabs(r.durationDelta - 1.4) < 1e-6, "falls through to the next accepted candidate");

    // 歌手字段被车载歌词占用：只按歌名搜，用已上报的句子本地核对
    client.transport = fakeTransport(^NSData *(NSURL *url, NSInteger *status) { return fixtureRoute(url, nil); });
    requests = [NSMutableArray array];
    r = lookup(client, @"com.tencent.QQMusic", @"晴天", @"故事的小黄花", NO, 269.2, @[@"故事的小黄花"], NULL);
    check([r.status isEqual:@"hit"] && [param(requests[0].URL, @"w") isEqual:@"晴天"], "unreliable artist is not sent; evidence confirms");
    r = lookup(client, @"com.tencent.QQMusic", @"晴天", @"别的句子", NO, 269.2, @[@"完全不相干的一句"], NULL);
    check([r.status isEqual:@"miss"] && [attemptSummary(r) isEqual:@"qq:miss:lyric-mismatch,netease:miss:no-match"],
          "car lyric not in the candidate's lyrics rejects a same-title, same-length song");

    // 失败负缓存：几分钟后放行一次，再失败就到本次运行结束
    client.transport = fakeTransport(^NSData *(NSURL *url, NSInteger *status) { return nil; });
    BOOL started = NO;
    r = lookup(client, @"com.tencent.QQMusic", @"离线歌曲", @"歌手", YES, 200, nil, &started);
    check(started && [r.status isEqual:@"error"] && [attemptSummary(r) isEqual:@"qq:error:network,netease:error:network"], "network error");
    requests = [NSMutableArray array];
    lookup(client, @"com.tencent.QQMusic", @"离线歌曲", @"歌手", YES, 200, nil, &started);
    check(!started && !requests.count, "failure is cached negatively without network");
    now += 301;
    lookup(client, @"com.tencent.QQMusic", @"离线歌曲", @"歌手", YES, 200, nil, &started);
    check(started && requests.count == 2, "one retry after a few minutes");
    now += 3600;
    lookup(client, @"com.tencent.QQMusic", @"离线歌曲", @"歌手", YES, 200, nil, &started);
    check(!started, "second failure blocks for the rest of the run");
    client.transport = fakeTransport(^NSData *(NSURL *url, NSInteger *status) { *status = 500; return [NSData data]; });
    r = lookup(client, @"com.tencent.QQMusic", @"另一首", @"歌手", YES, 200, nil, &started);
    check(started && [attemptSummary(r) isEqual:@"qq:error:http,netease:error:http"], "HTTP status errors");
    // 命中清掉失败记录
    __block BOOL online = NO;
    client.transport = fakeTransport(^NSData *(NSURL *url, NSInteger *status) { return online ? fixtureRoute(url, nil) : nil; });
    lookup(client, @"com.tencent.QQMusic", @"晴天", @"周杰伦", YES, 269.1, nil, &started);
    now += 301; online = YES;
    r = lookup(client, @"com.tencent.QQMusic", @"晴天", @"周杰伦", YES, 269.1, nil, &started);
    check(started && [r.status isEqual:@"hit"], "retry succeeds");
    lookup(client, @"com.tencent.QQMusic", @"晴天", @"周杰伦", YES, 269.1, nil, &started);
    check(started, "a hit clears the negative cache");
    check(!lookup(client, @"com.tencent.QQMusic", @" ", @"x", YES, 1, nil, &started) && !started, "empty title is refused");
}

#pragma mark 真实联网冒烟

static int live(void) {
    IKNetLyricsClient *client = [IKNetLyricsClient new];
    // 开发机沙盒只放行本机代理：有 HTTPS_PROXY 时经它出网，会话的其余设置与默认网络层相同
    NSString *proxyVar = NSProcessInfo.processInfo.environment[@"HTTPS_PROXY"] ?: NSProcessInfo.processInfo.environment[@"https_proxy"];
    NSURL *proxy = proxyVar.length ? [NSURL URLWithString:proxyVar] : nil;
    if (proxy.host.length && proxy.port) {
        client.transport = IKNetProxyTransport(@{@"HTTPSEnable":@1, @"HTTPSProxy":proxy.host, @"HTTPSPort":proxy.port,
                                                 @"HTTPEnable":@1, @"HTTPProxy":proxy.host, @"HTTPPort":proxy.port});
        printf("via proxy %s:%d\n", proxy.host.UTF8String, proxy.port.intValue);
    } else printf("direct (default transport)\n");
    struct { const char *bid, *title, *artist; BOOL reliable; double duration; const char *evidence, *expect; } cases[] = {
        {"com.tencent.QQMusic", "晴天", "周杰伦", YES, 269.4, NULL, "hit:qq"},
        {"com.netease.cloudmusic", "晴天", "周杰伦", YES, 269.4, NULL, "hit:qq"},
        {"com.netease.cloudmusic", "十年", "陈奕迅", YES, 205.4, NULL, "hit:netease"},
        {"com.tencent.QQMusic", "晴天", "故事的小黄花", NO, 269.4, "故事的小黄花", "hit:qq"},
        {"com.tencent.QQMusic", "Don't Stop Me Now", "Queen", YES, 209.3, NULL, "hit:qq"},
        {"com.netease.cloudmusic", "River Flows in You", "Yiruma", YES, 214.9, NULL, "miss"},
    };
    int failures = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block IKNetLyricsResult *result = nil;
        NSArray *evidence = cases[i].evidence ? @[@(cases[i].evidence)] : nil;
        double start = NSProcessInfo.processInfo.systemUptime;
        BOOL ok = [client lookupBundle:@(cases[i].bid) title:@(cases[i].title) artist:@(cases[i].artist)
                        artistReliable:cases[i].reliable duration:cases[i].duration evidence:evidence
                            completion:^(IKNetLyricsResult *r) { result = r; dispatch_semaphore_signal(done); }];
        if (ok) dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
        double ms = (NSProcessInfo.processInfo.systemUptime - start) * 1000;
        NSString *got = [result.status isEqual:@"hit"] ? [@"hit:" stringByAppendingString:result.provider] : result.status ?: @"none";
        BOOL pass = [got isEqual:@(cases[i].expect)];
        failures += !pass;
        NSUInteger at = result.lines.count ? IKCurrentLyricIndex(result.lines, 35) : NSNotFound;
        printf("%s %-22s %-18s -> %-11s attempts=[%s] lines=%lu dt=%.2f id=%s t35=%s %.0fms\n", pass ? "PASS" : "FAIL",
               cases[i].bid, cases[i].title, got.UTF8String, attemptSummary(result).UTF8String, (unsigned long)result.lines.count,
               result.durationDelta, result.songID.UTF8String ?: "-",
               at == NSNotFound ? "-" : [result.lines[at][@"text"] UTF8String], ms);
    }
    printf("live smoke: %d failure(s)\n", failures);
    return failures ? 1 : 0;
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc == 2 && !strcmp(argv[1], "--live")) return live();
    if (argc != 2) return 2;
    fixtures = @(argv[1]);
    testNormalize();
    testSearchParsing();
    testScoring();
    testLyrics();
    testRequests();
    testClient();
    printf("net lyrics: %d checks passed\n", count);
    return 0;
} }
