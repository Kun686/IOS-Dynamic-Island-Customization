import SwiftUI

// 与插件共用的配置文件。键名要和 Tweak/IKPrefs.m 保持一致
struct Settings {
    var enabled = true
    var notif = true
    var lyric = true
    var spin = true
    var pauseStops = true
    var transitionStyle = 0    // 0 回弹下落 / 1 柔和滑入 / 2 淡入 / 3 缩放弹出 / 4 果冻
    var windowLevelBoost = 0   // 0 默认 / 1 更高 / 2 最高
    var placement = 0          // 0 岛下方 / 1 覆盖岛
    var progressRing = true
    var lyricEffect = 1        // 0 无 / 1 逐行填色 / 2 淡入
    var lyricFontSize = 16.0
    var lyricColorMode = 0     // 0 强调色 / 1 跟随封面 / 2 自定义
    var ringColorMode = 1
    var lyricColor = "#B8F34A"
    var ringColor = "#B8F34A"
    var lyricLines = 2
    var spinSeconds = 8.0
    var notifDuration = 5.0
    var notifApps: [String] = []
    var accent = "#B8F34A"

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
        placement = d["placement"] as? Int ?? placement
        progressRing = d["progressRing"] as? Bool ?? progressRing
        lyricEffect = d["lyricEffect"] as? Int ?? lyricEffect
        lyricFontSize = d["lyricFontSize"] as? Double ?? lyricFontSize
        lyricColorMode = d["lyricColorMode"] as? Int ?? lyricColorMode
        ringColorMode = d["ringColorMode"] as? Int ?? ringColorMode
        lyricColor = d["lyricColor"] as? String ?? lyricColor
        ringColor = d["ringColor"] as? String ?? ringColor
        spinSeconds = d["spinSeconds"] as? Double ?? spinSeconds
        notifDuration = d["notifDuration"] as? Double ?? notifDuration
        notifApps = d["notifApps"] as? [String] ?? notifApps
        accent = d["accent"] as? String ?? accent
    }

    var dict: [String: Any] {
        [
            "enabled": enabled, "notif": notif, "lyric": lyric, "spin": spin,
            "pauseStops": pauseStops, "lyricLines": lyricLines,
            "transitionStyle": transitionStyle, "windowLevelBoost": windowLevelBoost,
            "spinSeconds": spinSeconds, "notifDuration": notifDuration,
            "notifApps": notifApps, "accent": accent, "placement": placement, "progressRing": progressRing,
            "lyricEffect": lyricEffect, "lyricFontSize": lyricFontSize,
            "lyricColorMode": lyricColorMode, "ringColorMode": ringColorMode,
            "lyricColor": lyricColor, "ringColor": ringColor,
        ]
    }
}

final class Store: ObservableObject {
    static let path = "/var/mobile/Library/Preferences/com.islandkit.prefs.plist"
    static let darwinName = "com.islandkit.prefs/changed"

    @Published var s = Settings() {
        didSet { save() }
    }
    @Published var saveFailed = false

    init() {
        if let d = NSDictionary(contentsOfFile: Store.path) as? [String: Any] {
            s = Settings(dict: d)
        }
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
    static func load() -> [AppInfo] {
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
            let icon = UIImage._applicationIconImage(forBundleIdentifier: id, format: 0, scale: scale)
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
