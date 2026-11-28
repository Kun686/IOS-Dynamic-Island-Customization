import SwiftUI

// 与插件共用的配置文件。键名要和 Tweak/IKPrefs.m 保持一致
struct Settings {
    var enabled = true
    var notif = true
    var lyric = true
    var spin = true
    var pauseStops = true
    var transitionStyle = 0    // 0 回弹下落 / 1 柔和滑入 / 2 淡入 / 3 缩放弹出 / 4 果冻
    var windowLevelBoost = 0   // 0 自动（覆盖模式最高、下挂模式标准）/ 1 更高 / 2 最高
    var placement = 0          // 0 岛下方 / 1 覆盖岛
    var coverExtraWidth = 3.0  // 覆盖模式：胶囊比开孔多出来的宽度（两侧合计）
    var coverExtraHeight = 3.0 // 覆盖模式：胶囊比开孔多出来的高度（上下合计）
    var coverOffsetY = 0.0     // 覆盖模式：整体上下修正
    var calibrateUntil = 0.0   // 在这个时刻（Unix 时间）之前，悬浮进程画出覆盖范围的描边
    var progressRing = true
    var lyricEffect = 1        // 0 无 / 1 逐行填色 / 2 淡入
    var lyricFontSize = 16.0
    var lyricColorMode = 0     // 0 强调色 / 1 跟随封面 / 2 自定义
    var titleColorMode = 3     // 同上，另有 3 默认白色
    var ringColorMode = 1
    var lyricColor = "#B8F34A"
    var titleColor = "#FFFFFF"
    var ringColor = "#B8F34A"
    var lyricLines = 2
    var lyricAlignment = 0     // 0 靠左 / 1 居中（按整个胶囊的中线）/ 2 靠右 / 3 自定义
    var lyricOffsetX = 0.0     // 自定义：文字中心相对胶囊中线的左右偏移，正数向右
    var lyricOffsetY = 0.0     // 自定义：上下偏移，正数向下
    var defaultMusicView = 0   // 0 歌词态 / 1 紧凑态 / 2 悬挂歌词
    var recordIndicator = true // 录屏时在岛上提示
    var netLyrics = true       // 联网匹配逐句歌词时间轴
    var notifDefaultsApplied = false // “通知应用默认全部打开”是否已经做过（只做一次，之后尊重用户的选择）
    var spinSeconds = 8.0
    var notifDuration = 5.0
    var notifApps: [String] = []
    var accent = "#B8F34A"
    var notifTitleColor = "#FFFFFF"
    var notifMessageColor = "#A8A8B0"

    init() {}

    init(dict d: [String: Any]) {
        enabled = d["enabled"] as? Bool ?? enabled
        notif = d["notif"] as? Bool ?? notif
        lyric = d["lyric"] as? Bool ?? lyric
        spin = d["spin"] as? Bool ?? spin
        pauseStops = d["pauseStops"] as? Bool ?? pauseStops
        transitionStyle = d["transitionStyle"] as? Int ?? transitionStyle
        windowLevelBoost = d["windowLevelBoost"] as? Int ?? windowLevelBoost
        lyricLines = d["lyricLines"] as? Int ?? lyricLines
        if let choice = d["lyricAlignment"] as? Int, (0...3).contains(choice) { lyricAlignment = choice }
        lyricOffsetX = max(-120, min(120, d["lyricOffsetX"] as? Double ?? lyricOffsetX))
        lyricOffsetY = max(-12, min(12, d["lyricOffsetY"] as? Double ?? lyricOffsetY))
        if let style = d["defaultMusicView"] as? Int, (0...2).contains(style) { defaultMusicView = style }
        recordIndicator = d["recordIndicator"] as? Bool ?? recordIndicator
        netLyrics = d["netLyrics"] as? Bool ?? netLyrics
        notifDefaultsApplied = d["notifDefaultsApplied"] as? Bool ?? notifDefaultsApplied
        placement = d["placement"] as? Int ?? placement
        coverExtraWidth = d["coverExtraWidth"] as? Double ?? coverExtraWidth
        coverExtraHeight = d["coverExtraHeight"] as? Double ?? coverExtraHeight
        coverOffsetY = d["coverOffsetY"] as? Double ?? coverOffsetY
        calibrateUntil = d["calibrateUntil"] as? Double ?? calibrateUntil
        progressRing = d["progressRing"] as? Bool ?? progressRing
        lyricEffect = d["lyricEffect"] as? Int ?? lyricEffect
        lyricFontSize = d["lyricFontSize"] as? Double ?? lyricFontSize
        lyricColorMode = d["lyricColorMode"] as? Int ?? lyricColorMode
        titleColorMode = d["titleColorMode"] as? Int ?? titleColorMode
        ringColorMode = d["ringColorMode"] as? Int ?? ringColorMode
        lyricColor = d["lyricColor"] as? String ?? lyricColor
        titleColor = d["titleColor"] as? String ?? d["songTitleColor"] as? String ?? titleColor
        ringColor = d["ringColor"] as? String ?? ringColor
        notifTitleColor = d["notifTitleColor"] as? String ?? notifTitleColor
        notifMessageColor = d["notifMessageColor"] as? String ?? notifMessageColor
        spinSeconds = d["spinSeconds"] as? Double ?? spinSeconds
        notifDuration = d["notifDuration"] as? Double ?? notifDuration
        notifApps = d["notifApps"] as? [String] ?? notifApps
        accent = d["accent"] as? String ?? accent
    }

    var dict: [String: Any] {
        [
            "enabled": enabled, "notif": notif, "lyric": lyric, "spin": spin,
            "pauseStops": pauseStops, "lyricLines": lyricLines,
            "lyricAlignment": lyricAlignment, "defaultMusicView": defaultMusicView,
            "lyricOffsetX": lyricOffsetX, "lyricOffsetY": lyricOffsetY,
            "transitionStyle": transitionStyle, "windowLevelBoost": windowLevelBoost,
            "spinSeconds": spinSeconds, "notifDuration": notifDuration,
            "notifApps": notifApps, "accent": accent, "placement": placement, "progressRing": progressRing,
            "lyricEffect": lyricEffect, "lyricFontSize": lyricFontSize,
            "lyricColorMode": lyricColorMode, "ringColorMode": ringColorMode,
            "lyricColor": lyricColor, "ringColor": ringColor,
            "titleColorMode": titleColorMode, "titleColor": titleColor, "songTitleColor": titleColor,
            "coverExtraWidth": coverExtraWidth, "coverExtraHeight": coverExtraHeight,
            "coverOffsetY": coverOffsetY, "calibrateUntil": calibrateUntil,
            "notifTitleColor": notifTitleColor, "notifMessageColor": notifMessageColor,
            "recordIndicator": recordIndicator, "netLyrics": netLyrics, "notifDefaultsApplied": notifDefaultsApplied,
        ]
    }

    // 设置界面里的预览没有专辑封面，“跟随封面”时用强调色代替
    func previewColor(mode: Int, custom: String) -> Color {
        switch mode {
        case 2: return Color(hex: custom)
        case 3: return .white
        default: return Color(hex: accent)
        }
    }
}

final class Store: ObservableObject {
    static let path = "/var/mobile/Library/Preferences/com.islandkit.prefs.plist"
    static let darwinName = "com.islandkit.prefs/changed"
    static let demoDarwinName = "com.islandkit.demo/transition"

    @Published var s = Settings() {
        didSet { save() }
    }
    @Published var saveFailed = false
    // 启动时配置文件里的通知应用列表是不是空的（文件不存在也算空）。在 init 里第一次写文件之前记下来
    let notifAppsEmptyAtLaunch: Bool

    init() {
        let d = NSDictionary(contentsOfFile: Store.path) as? [String: Any]
        notifAppsEmptyAtLaunch = ((d?["notifApps"] as? [String]) ?? []).isEmpty
        if let d = d {
            s = Settings(dict: d)
        }
        // 上次如果在校准时被杀掉，描边不能一直留在屏幕上
        if s.calibrateUntil != 0 {
            s.calibrateUntil = 0
            save()
        }
    }

    // 让悬浮进程用当前选中的过渡动画把“出现 → 收起”演示一遍。配置已经在改动时写入并通知过了
    func demoTransition() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Store.demoDarwinName as CFString), nil, nil, true)
    }

    // 校准描边：开着的时候定期续期，关掉或离开页面时清零
    var calibrating: Bool { s.calibrateUntil > Date().timeIntervalSince1970 }

    func setCalibrating(_ on: Bool) {
        s.calibrateUntil = on ? Date().timeIntervalSince1970 + 90 : 0
    }

    private func save() {
        // 保留插件侧的几何微调等本界面不管的键
        var merged = (NSDictionary(contentsOfFile: Store.path) as? [String: Any]) ?? [:]
        for (k, v) in s.dict { merged[k] = v }
        let ok = (merged as NSDictionary).write(toFile: Store.path, atomically: true)
        saveFailed = !ok
        // 通知插件热更新，不需要注销
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Store.darwinName as CFString), nil, nil, true)
    }
}

struct AppInfo: Identifiable {
    let id: String
    let name: String
    let icon: UIImage?
}

enum AppList {
    // 安全地读私有属性：属性不存在时返回 nil，而不是抛异常
    private static func read(_ obj: NSObject, _ key: String) -> Any? {
        obj.responds(to: NSSelectorFromString(key)) ? obj.value(forKey: key) : nil
    }

    // 通过 LSApplicationWorkspace 读取已安装的应用。
    // 巨魔安装的应用在系统里登记为 System 类型，所以不能只取 User 类型；
    // 这里取所有未隐藏的应用，自己安装的（含巨魔安装的）排在前面，系统自带的排在后面。
    // icons 为 NO 时不取图标，只要应用列表（启动时“默认全部打开”用，快很多）
    static func load(icons: Bool = true) -> [AppInfo] {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let ws = cls.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
              let proxies = ws.perform(NSSelectorFromString("allApplications"))?.takeUnretainedValue() as? [NSObject]
        else { return [] }

        let scale = UIScreen.main.scale
        var mine: [AppInfo] = []
        var system: [AppInfo] = []
        for p in proxies {
            guard let id = read(p, "applicationIdentifier") as? String else { continue }
            if let tags = read(p, "appTags") as? [String], tags.contains("hidden") { continue }
            let name = (read(p, "localizedName") as? String) ?? id
            if name.isEmpty { continue }
            let path = (read(p, "bundleURL") as? URL)?.path ?? ""
            let installed = (read(p, "applicationType") as? String) == "User" || path.contains("/containers/Bundle/Application/")
            let icon = icons ? UIImage._applicationIconImage(forBundleIdentifier: id, format: 0, scale: scale) : nil
            let info = AppInfo(id: id, name: name, icon: icon)
            if installed { mine.append(info) } else { system.append(info) }
        }
        let byName: (AppInfo, AppInfo) -> Bool = { $0.name.localizedCompare($1.name) == .orderedAscending }
        return mine.sorted(by: byName) + system.sorted(by: byName)
    }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    // 转成 #RRGGBB，写进配置文件
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let c: (CGFloat) -> Int = { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
    static let ikGround = Color(hex: "0B0B0D")
    static let ikCard = Color(hex: "17171B")
    static let ikStage = Color(hex: "1E1E24")
    static let ikMuted = Color(hex: "A0A0A8")
    static let ikText = Color(hex: "F2F2F0")
}
