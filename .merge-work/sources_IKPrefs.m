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

<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKPrefs.m
// 开孔（系统岛待机时的黑色胶囊）的位置和大小。
// 能装巨魔的灵动岛机型只有 393 和 430 两种屏宽，这两种直接用系统自己的数值
// （iOS 16.6 的 SBUISystemApertureLayoutMetrics：sensorRegionSize 为 125 或 125.33 × 36.67，距屏幕顶部 11.33）。
// 其他尺寸先问系统的私有接口 -[UIScreen _exclusionArea]，问不到再用备用值
=======
// 自动识别开孔位置。先问系统（私有接口，可能没有），问不到就按屏幕尺寸查表
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKPrefs.m
    CGFloat sw = MIN(ss.width, ss.height), sh = MAX(ss.width, ss.height);
    NSString *source = @"table";
    CGRect r = CGRectZero;
    @try {
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKPrefs.m
    BOOL (^near)(CGFloat) = ^BOOL(CGFloat w) { return fabs(sw - w) < 0.6; };

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKPrefs.m
            id area = [screen valueForKey:@"_exclusionArea"];
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKPrefs.m
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
=======
    CGRect r = CGRectZero;
    @try {
        SEL sel = NSSelectorFromString(@"_exclusionArea");
        if ([screen respondsToSelector:sel]) {
            id area = [screen valueForKey:@"_exclusionArea"];
            if (area && [area respondsToSelector:NSSelectorFromString(@"rect")]) {
                id v = [area valueForKey:@"rect"];
                if ([v isKindOfClass:[NSValue class]]) r = [v CGRectValue];
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKPrefs.m
+ (double)windowLevelFromFile {
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKPrefs.m
        } @catch (__unused NSException *e) {}
        BOOL sane = r.size.width >= 80 && r.size.width <= 200 && r.size.height >= 25 && r.size.height <= 50
            && r.origin.y >= 0 && r.origin.y < 40;
        if (sane) {
            source = @"system";
            size = r.size;
            top = r.origin.y;
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKPrefs.m
    if (boost == 1) level = 100000000.0;
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKPrefs.m
=======
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
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKPrefs.m
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
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKPrefs.m
    CGRect rect = CGRectMake((sw - size.width) / 2, top, size.width, size.height);

    static NSString *lastLogged;
    NSString *line = [NSString stringWithFormat:@"geometry screen=%.0fx%.0f scale=%.0f island=%@ source=%@",
                      sw, sh, screen.scale, NSStringFromCGRect(rect), source];
    if (![line isEqualToString:lastLogged]) {
        lastLogged = line;
        [IKPrefs log:line];
    }
    return rect;
=======
    [IKPrefs log:[NSString stringWithFormat:@"geometry screen=%.0fx%.0f scale=%.0f island=%@ source=%@",
                  sw, sh, screen.scale, NSStringFromCGRect(r), source]];
    return r;
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKPrefs.m
