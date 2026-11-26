import SwiftUI

// 与插件共用的配置文件。键名要和 Tweak/IKPrefs.m 保持一致
struct Settings {
    var enabled = true
    var notif = true
    var lyric = true
    var spin = true
    var pauseStops = true
    var transitionStyle = 0    // 0 回弹下落 / 1 柔和滑入 / 2 淡入 / 3 缩放弹出 / 4 果冻
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
    var windowLevelBoost = 0   // 0 标准 / 1 更高 / 2 最高
=======
    var windowLevelBoost = 0   // 0 默认 / 1 更高 / 2 最高
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
    var placement = 0          // 0 岛下方 / 1 覆盖岛
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
    var coverExtraWidth = 3.0  // 覆盖模式：胶囊比开孔多出来的宽度（两侧合计）
    var coverExtraHeight = 3.0 // 覆盖模式：胶囊比开孔多出来的高度（上下合计）
    var coverOffsetY = 0.0     // 覆盖模式：整体上下修正
    var calibrateUntil = 0.0   // 在这个时刻（Unix 时间）之前，悬浮进程画出覆盖范围的描边
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
    var ringColorMode = 1
    var lyricColor = "#B8F34A"
    var ringColor = "#B8F34A"
    var lyricLines = 2
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
    var titleColorMode = 3     // 同上，另有 3 默认白色
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
    var notifDuration = 5.0
    var notifApps: [String] = []
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
    var titleColor = "#FFFFFF"
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
    var songTitleColor = "#FFFFFF"
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
        placement = d["placement"] as? Int ?? placement
        progressRing = d["progressRing"] as? Bool ?? progressRing
        lyricEffect = d["lyricEffect"] as? Int ?? lyricEffect
        lyricFontSize = d["lyricFontSize"] as? Double ?? lyricFontSize
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
        coverExtraWidth = d["coverExtraWidth"] as? Double ?? coverExtraWidth
        coverExtraHeight = d["coverExtraHeight"] as? Double ?? coverExtraHeight
        coverOffsetY = d["coverOffsetY"] as? Double ?? coverOffsetY
        calibrateUntil = d["calibrateUntil"] as? Double ?? calibrateUntil
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
        spinSeconds = d["spinSeconds"] as? Double ?? spinSeconds
        notifDuration = d["notifDuration"] as? Double ?? notifDuration
        notifApps = d["notifApps"] as? [String] ?? notifApps
        accent = d["accent"] as? String ?? accent
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
        titleColorMode = d["titleColorMode"] as? Int ?? titleColorMode
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
        notifTitleColor = d["notifTitleColor"] as? String ?? notifTitleColor
        notifMessageColor = d["notifMessageColor"] as? String ?? notifMessageColor
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
        titleColor = d["titleColor"] as? String ?? titleColor
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift

    var dict: [String: Any] {
        [
            "enabled": enabled, "notif": notif, "lyric": lyric, "spin": spin,
            "pauseStops": pauseStops, "lyricLines": lyricLines,
            "transitionStyle": transitionStyle, "windowLevelBoost": windowLevelBoost,
            "spinSeconds": spinSeconds, "notifDuration": notifDuration,
            "notifApps": notifApps, "accent": accent, "songTitleColor": songTitleColor,
            "placement": placement, "progressRing": progressRing,
            "lyricEffect": lyricEffect, "lyricFontSize": lyricFontSize,
            "lyricColorMode": lyricColorMode, "ringColorMode": ringColorMode,
            "lyricColor": lyricColor, "ringColor": ringColor,
<<<<<<< sources/IKStore.swift
            "notifTitleColor": notifTitleColor, "notifMessageColor": notifMessageColor,
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
            "spinSeconds": spinSeconds, "notifDuration": notifDuration,
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
        ]
    }
}

final class Store: ObservableObject {
    static let path = "/var/mobile/Library/Preferences/com.islandkit.prefs.plist"
    static let darwinName = "com.islandkit.prefs/changed"

    @Published var s = Settings() {
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift

    // 设置界面里的预览没有专辑封面，“跟随封面”时用强调色代替
    func previewColor(mode: Int, custom: String) -> Color {
        switch mode {
        case 2: return Color(hex: custom)
        case 3: return .white
        default: return Color(hex: accent)
        }
    }
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift

    private func save() {
        // 保留插件侧的几何微调等本界面不管的键
        var merged = (NSDictionary(contentsOfFile: Store.path) as? [String: Any]) ?? [:]
        for (k, v) in s.dict { merged[k] = v }
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
    static let demoDarwinName = "com.islandkit.demo/transition"
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
        saveFailed = !ok
        // 通知插件热更新，不需要注销
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Store.darwinName as CFString), nil, nil, true)
    }
}

struct AppInfo: Identifiable {
    let id: String
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
        // 上次如果在校准时被杀掉，描边不能一直留在屏幕上
        if s.calibrateUntil != 0 {
            s.calibrateUntil = 0
            save()
        }
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
    // 安全地读私有属性：属性不存在时返回 nil，而不是抛异常
    private static func read(_ obj: NSObject, _ key: String) -> Any? {
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKStore.swift
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

=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKStore.swift
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
