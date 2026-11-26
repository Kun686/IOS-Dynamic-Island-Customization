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

// 开孔（系统岛待机时的黑色胶囊）的位置和大小。
// 能装巨魔的灵动岛机型只有 393 和 430 两种屏宽，这两种直接用系统自己的数值
// （iOS 16.6 的 SBUISystemApertureLayoutMetrics：sensorRegionSize 为 125 或 125.33 × 36.67，距屏幕顶部 11.33）。
// 其他尺寸先问系统的私有接口 -[UIScreen _exclusionArea]，问不到再用备用值
+ (CGRect)detectedIslandRect {
    UIScreen *screen = [UIScreen mainScreen];
    CGSize ss = screen.bounds.size;
    CGFloat sw = MIN(ss.width, ss.height), sh = MAX(ss.width, ss.height);
    BOOL (^near)(CGFloat) = ^BOOL(CGFloat w) { return fabs(sw - w) < 0.6; };

    NSString *source = @"table";
    CGSize size = CGSizeMake(126, 37.33);
    CGFloat top = 11.33;
    if (near(393)) {
        size = CGSizeMake(125.0, 36.67);
    } else if (near(430)) {
        size = CGSizeMake(125.33, 36.67);
    } else {
        // 备用值。402、440、420 宽的三组是在 iOS 26.5 模拟器（iPhone 17 Pro、17 Pro Max、Air）里
        // 用 _exclusionArea 读到的，没有在真机上核实；这些机型出厂就是 iOS 18 以上，本来也装不了巨魔。
        // 再其他的尺寸用稍大一点的默认值
        if (near(402))      { size = CGSizeMake(125.0, 36.67);  top = 14.0; }
        else if (near(440)) { size = CGSizeMake(125.33, 36.67); top = 14.0; }
        else if (near(420)) { size = CGSizeMake(125.33, 36.67); top = 20.0; }
        source = @"fallback";
        CGRect r = CGRectZero;
        @try {
            if ([screen respondsToSelector:NSSelectorFromString(@"_exclusionArea")]) {
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
            size = r.size;
            top = r.origin.y;
        }
    }
    CGRect rect = CGRectMake((sw - size.width) / 2, top, size.width, size.height);

    static NSString *lastLogged;
    NSString *line = [NSString stringWithFormat:@"geometry screen=%.0fx%.0f scale=%.0f island=%@ source=%@",
                      sw, sh, screen.scale, NSStringFromCGRect(rect), source];
    if (![line isEqualToString:lastLogged]) {
        lastLogged = line;
        [IKPrefs log:line];
    }
    return rect;
}

+ (double)windowLevelFromFile {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:IKPrefsPath];
    NSInteger boost = [d[@"windowLevelBoost"] integerValue];
    if (boost == 1) return IKWindowLevelHigher;
    if (boost >= 2) return IKWindowLevelHighest;
    return IKWindowLevelStandard;
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
    double (^clamp)(double, double, double) = ^double(double v, double lo, double hi) {
        return MIN(hi, MAX(lo, v));
    };

    self.enabled        = b(@"enabled", YES);
    self.notifEnabled   = b(@"notif", YES);
    self.lyricEnabled   = b(@"lyric", YES);
    self.spinEnabled    = b(@"spin", YES);
    self.pauseStopsSpin = b(@"pauseStops", YES);
    self.lyricLines     = n(@"lyricLines", 2) >= 2 ? 2 : 1;
    self.spinSeconds    = MAX(1.0, n(@"spinSeconds", 8));
    self.notifDuration  = MAX(1.0, n(@"notifDuration", 5));
    // 岛的位置和大小：plist 里写了就用写的，否则按机型识别
    CGRect auto_ = [IKPrefs detectedIslandRect];
    self.islandTop      = n(@"islandTop", auto_.origin.y);
    self.cutoutWidth    = n(@"cutoutWidth", auto_.size.width);
    self.cutoutHeight   = n(@"cutoutHeight", auto_.size.height);
    self.coverExtraWidth  = clamp(n(@"coverExtraWidth", 3), -12, 40);
    self.coverExtraHeight = clamp(n(@"coverExtraHeight", 3), -8, 16);
    self.coverOffsetY     = clamp(n(@"coverOffsetY", 0), -10, 10);
    self.coverCompactSide = clamp(n(@"coverCompactSide", 66), 40, 120);
    self.calibrateUntil   = n(@"calibrateUntil", 0);
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
    self.titleColorMode = (NSInteger)n(@"titleColorMode", 3);
    self.ringColorMode  = (NSInteger)n(@"ringColorMode", 1);
    self.lyricColor     = IKColorFromHex(d[@"lyricColor"], lime);
    self.titleColor     = IKColorFromHex(d[@"titleColor"] ?: d[@"songTitleColor"], [UIColor whiteColor]);
    self.ringColor      = IKColorFromHex(d[@"ringColor"], lime);
    self.lyricEffect    = (NSInteger)n(@"lyricEffect", 1);
    self.lyricFontSize  = MIN(18, MAX(13, n(@"lyricFontSize", 16)));
}

@end
