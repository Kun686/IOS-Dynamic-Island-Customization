#import "IKPrefs.h"

static UIColor *IKColorFromHex(NSString *hex, UIColor *fallback) {
    if (![hex isKindOfClass:[NSString class]]) return fallback;
    NSString *s = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (s.length != 6) return fallback;
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) return fallback;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation IKPrefs

+ (instancetype)shared {
    static IKPrefs *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [IKPrefs new];
        [s reload];
    });
    return s;
}

+ (void)log:(NSString *)message {
    NSString *path = [IKDataDir stringByAppendingPathComponent:@"island.log"];
    [[NSFileManager defaultManager] createDirectoryAtPath:IKDataDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], message];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; return; }
    if ([h seekToEndOfFile] > 200 * 1024) [h truncateFileAtOffset:0];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

// 自动识别开孔位置。先问系统（私有接口，可能没有），问不到就按屏幕尺寸查表
+ (CGRect)detectedIslandRect {
    UIScreen *screen = [UIScreen mainScreen];
    CGSize ss = screen.bounds.size;
    CGFloat sw = MIN(ss.width, ss.height), sh = MAX(ss.width, ss.height);
    NSString *source = @"table";
    CGRect r = CGRectZero;
    @try {
        SEL sel = NSSelectorFromString(@"_exclusionArea");
        if ([screen respondsToSelector:sel]) {
            id area = [screen valueForKey:@"_exclusionArea"];
            if (area && [area respondsToSelector:NSSelectorFromString(@"rect")]) {
                id v = [area valueForKey:@"rect"];
                if ([v isKindOfClass:[NSValue class]]) r = [v CGRectValue];
            }
        }
    } @catch (__unused NSException *e) {}
    BOOL sane = r.size.width >= 80 && r.size.width <= 200 && r.size.height >= 25 && r.size.height <= 50
        && r.origin.y >= 0 && r.origin.y < 40;
    if (sane) {
        source = @"system";
        // 私有接口返回的横向坐标可能属于屏幕坐标系，统一按当前竖屏宽度居中。
        r.origin.x = (sw - r.size.width) / 2.0;
    } else {
        // 动态岛机型的开孔宽度基本固定，顶部位置随屏幕宽度档位变化。
        CGFloat top = (sw >= 401.5 && sw <= 402.5) || (sw >= 439.5 && sw <= 440.5) ? 14.0 : 11.33;
        r = CGRectMake((sw - 126) / 2, top, 126, 37.33);
    }
    [IKPrefs log:[NSString stringWithFormat:@"geometry screen=%.0fx%.0f scale=%.0f island=%@ source=%@",
                  sw, sh, screen.scale, NSStringFromCGRect(r), source]];
    return r;
}

+ (double)windowLevelFromFile {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:IKPrefsPath];
    NSInteger boost = [d[@"windowLevelBoost"] integerValue];
    NSInteger placement = [d[@"placement"] integerValue];
    // 覆盖模式默认启用最高层级，避免用户还要手动试验层级才能盖住系统岛。
    // NSNumber(0) 仍然是非 nil 对象，不能用 !d[key] 判断“默认值”。
    if (placement != 0 && boost <= 0) boost = 2;
    double level = 10000010.0; // TrollSpeed 原来的值
    if (boost == 1) level = 100000000.0;
    if (boost >= 2) level = 2147483000.0;
    [IKPrefs log:[NSString stringWithFormat:@"windowLevel placement=%ld boost=%ld level=%.0f",
                  (long)placement, (long)boost, level]];
    return level;
}

- (void)reload {
    // 直接读文件，避开 cfprefsd 缓存；配置 App 也是直接写这个文件
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:IKPrefsPath] ?: @{};
    BOOL (^b)(NSString *, BOOL) = ^BOOL(NSString *k, BOOL def) {
        id v = d[k];
        return v ? [v boolValue] : def;
    };
    double (^n)(NSString *, double) = ^double(NSString *k, double def) {
        id v = d[k];
        return v ? [v doubleValue] : def;
    };

    self.enabled        = b(@"enabled", YES);
    self.notifEnabled   = b(@"notif", YES);
    self.lyricEnabled   = b(@"lyric", YES);
    self.spinEnabled    = b(@"spin", YES);
    self.pauseStopsSpin = b(@"pauseStops", YES);
    self.lyricLines     = n(@"lyricLines", 2) >= 2 ? 2 : 1;
    self.spinSeconds    = MAX(1.0, n(@"spinSeconds", 8));
    self.notifDuration  = MAX(1.0, n(@"notifDuration", 5));
    // 岛的位置和大小：plist 里写了就用写的，否则按机型自动识别
    CGRect auto_ = [IKPrefs detectedIslandRect];
    self.islandTop      = n(@"islandTop", auto_.origin.y);
    self.cutoutWidth    = n(@"cutoutWidth", auto_.size.width);
    self.cutoutHeight   = n(@"cutoutHeight", auto_.size.height);
    self.transitionStyle  = (NSInteger)n(@"transitionStyle", 0);
    self.windowLevelBoost = (NSInteger)n(@"windowLevelBoost", 0);
    self.placement      = (NSInteger)n(@"placement", 0);
    self.belowTop       = n(@"belowTop", 54);
    self.progressRing   = b(@"progressRing", YES);

    NSArray *apps = [d[@"notifApps"] isKindOfClass:[NSArray class]] ? d[@"notifApps"] : @[];
    self.notifApps = [NSSet setWithArray:apps];

    UIColor *lime = [UIColor colorWithRed:0xB8 / 255.0 green:0xF3 / 255.0 blue:0x4A / 255.0 alpha:1];
    self.accent = IKColorFromHex(d[@"accent"], lime);
    self.notifTitleColor = IKColorFromHex(d[@"notifTitleColor"], [UIColor whiteColor]);
    self.notifMessageColor = IKColorFromHex(d[@"notifMessageColor"], [UIColor colorWithWhite:1 alpha:0.66]);

    self.lyricColorMode = (NSInteger)n(@"lyricColorMode", 0);
    self.ringColorMode  = (NSInteger)n(@"ringColorMode", 1);
    self.lyricColor     = IKColorFromHex(d[@"lyricColor"], lime);
    self.ringColor      = IKColorFromHex(d[@"ringColor"], lime);
    self.lyricEffect    = (NSInteger)n(@"lyricEffect", 1);
    self.lyricFontSize  = MIN(18, MAX(13, n(@"lyricFontSize", 16)));
}

@end
