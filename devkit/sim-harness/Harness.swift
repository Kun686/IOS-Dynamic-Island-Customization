import SwiftUI
import UIKit

// 仅用于模拟器里的验证，不进入产品
@main
final class HarnessAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var token: Int32 = 0
    let env = ProcessInfo.processInfo.environment

    func log(_ s: String) { NSLog("IKH %@", s) }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let scenario = env["IK_SCENARIO"] ?? "home"
        let w = UIWindow(frame: UIScreen.main.bounds)
        window = w
        if scenario.hasPrefix("hud") {
            w.rootViewController = UIViewController()
            w.makeKeyAndVisible()
            var o: [String: Any] = [:]
            for key in ["placement", "transitionStyle", "lyricLines", "lyricEffect", "titleColorMode", "lyricColorMode",
                        "coverExtraWidth", "coverExtraHeight", "coverOffsetY", "coverCompactSide", "calibrateUntil"] {
                if let v = env["IK_" + key], let d = Double(v) { o[key] = d }
            }
            if let c = env["IK_titleColor"] { o["titleColor"] = UIColor(Color(hex: c)) }
            HarnessHUD.install(in: w, overrides: o, systemCompact: env["IK_SYSCOMPACT"] == "1")
            log("geometry | " + HarnessHUD.describeGeometry())
            notify_register_dispatch("com.ikharness.go", &token, DispatchQueue.main) { [weak self] _ in self?.runTimeline() }
        } else {
#if !IK_OLD
            let store = Store()
            if let v = env["IK_placement"], let i = Int(v) { store.s.placement = i }
            if let v = env["IK_titleColorMode"], let i = Int(v) { store.s.titleColorMode = i }
            if let v = env["IK_titleColor"] { store.s.titleColor = v }
            if let v = env["IK_lyricColorMode"], let i = Int(v) { store.s.lyricColorMode = i }
            if let v = env["IK_lyricColor"] { store.s.lyricColor = v }
            if let v = env["IK_transitionStyle"], let i = Int(v) { store.s.transitionStyle = i }
            let root: AnyView
            switch scenario {
            case "lyric": root = AnyView(NavigationStack { LyricView() })
            case "appearance": root = AnyView(NavigationStack { AppearanceView() })
            case "appearance-bottom":
                if #available(iOS 17.0, *) {
                    root = AnyView(NavigationStack { AppearanceView().defaultScrollAnchor(.bottom) })
                } else { root = AnyView(NavigationStack { AppearanceView() }) }
            case "lyric-bottom":
                if #available(iOS 17.0, *) {
                    root = AnyView(NavigationStack { LyricView().defaultScrollAnchor(.bottom) })
                } else { root = AnyView(NavigationStack { LyricView() }) }
            case "about": root = AnyView(NavigationStack { AboutView() })
            default: root = AnyView(NavigationStack { HomeView() })
            }
            w.rootViewController = UIHostingController(rootView: root.environmentObject(store)
                .tint(Color(hex: store.s.accent)).preferredColorScheme(.dark))
            w.makeKeyAndVisible()
#endif
        }
        return true
    }

    func at(_ t: Double, _ what: String, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            block()
            self?.log(String(format: "t=%.1f %@ | %@", t, what, HarnessHUD.describeIsland()))
        }
    }

    func rows(_ t: Double, _ what: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            self?.log(String(format: "t=%.1f %@ | %@", t, what, HarnessHUD.describeRows()))
        }
    }

    func runTimeline() {
        let m = IKMusicCenter.shared()!
        let long = "从出生那年就飘着 童年的荡秋千 随记忆一直晃到现在 吹着前奏望着天空 我想起花瓣试着掉落"
        log("go | " + HarnessHUD.describeIsland())
        m.h_setArtworkColor(.systemPink)
        if env["IK_TL"] == "adaptive" {
            // 覆盖模式跟着系统岛的实际大小走：读不到 → 按最宽留；读得到 → 刚好盖住；系统岛展开 → 让开
            let p = IKPrefs.shared()!
            let sw = UIScreen.main.bounds.width, top = p.islandTop, h = p.cutoutHeight
            func pill(_ w: CGFloat) -> NSValue { NSValue(cgRect: CGRect(x: (sw - w) / 2, y: top, width: w, height: h)) }
            at(0.3, "track starts, system island unknown") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
            at(1.2, "tap -> compact, still unknown") { IKController.shared().perform(NSSelectorFromString("tapped")) }
            at(2.0, "probe") {}
            at(2.2, "system: inert") { HarnessHUD.setSystemFrames([pill(p.cutoutWidth)]) }
            at(3.0, "probe") {}
            at(3.2, "system: compact 250.67") { HarnessHUD.setSystemFrames([pill(250.67)]) }
            at(4.0, "probe") {}
            at(4.2, "system: compact 320") { HarnessHUD.setSystemFrames([pill(320)]) }
            at(5.0, "probe") {}
            at(5.2, "system: 250.67 + detached circle") {
                HarnessHUD.setSystemFrames([pill(250.67), NSValue(cgRect: CGRect(x: sw / 2 + 125.33 + 8, y: top, width: h, height: h))])
            }
            at(6.0, "probe") {}
            at(6.2, "system: expanded 407x160") {
                HarnessHUD.setSystemFrames([NSValue(cgRect: CGRect(x: (sw - 407.33) / 2, y: top, width: 407.33, height: 160))])
            }
            at(7.0, "probe (should be hidden)") {}
            at(7.4, "system: back to compact 250.67") { HarnessHUD.setSystemFrames([pill(250.67)]) }
            at(8.2, "probe") {}
            at(8.4, "notification while music plays") {
                IKController.shared().showNotification(withBundle: "com.apple.MobileSMS", appName: "信息", title: "小明",
                                                       message: "今晚一起吃饭吗？", avatar: nil)
            }
            at(9.4, "probe notif") {}
            at(9.6, "system: compact 340 during notification") { HarnessHUD.setSystemFrames([pill(340)]) }
            at(10.4, "probe notif widened") {}
            return
        }
        if env["IK_TL"] == "scroll" {
            // 长歌词从头滚到尾：开头时 track 左边缘应在 0（看到文字开头），结尾时右边缘应等于行宽（看到文字末尾）
            at(0.3, "track starts") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
            at(1.0, "lyric 1") { m.h_setTitle("晴天", artist: "故事的小黄花", album: "叶惠美", duration: 269, playing: true) }
            at(5.0, "lyric 2 (long)") { m.h_setTitle("晴天", artist: long, album: "叶惠美", duration: 269, playing: true) }
            for t in [5.4, 5.9, 6.4, 7.6] { rows(t, "rows") }
            return
        }
        if env["IK_TL"] == "marquee" {
            // 没有歌词、歌名很长：来回滚动。暂停时应停在原地，继续后从那里接着滚
            let title = "这是一个特别特别长的歌名用来检查来回滚动在暂停之后会不会跳回开头"
            at(0.3, "track starts") { m.h_setTitle(title, artist: "某某歌手", album: "专辑", duration: 269, playing: true) }
            for t in [1.5, 4.0, 4.8] { rows(t, "rows playing") }
            at(5.0, "pause") { m.h_setTitle(title, artist: "某某歌手", album: "专辑", duration: 269, playing: false) }
            for t in [5.3, 6.8] { rows(t, "rows paused") }
            at(7.0, "resume") { m.h_setTitle(title, artist: "某某歌手", album: "专辑", duration: 269, playing: true) }
            for t in [7.2, 8.6] { rows(t, "rows resumed") }
            return
        }
        if env["IK_TL"] == "resume" {
            // 长歌词唱到一半暂停，过一会儿继续：暂停期间填色和滚动应当停住，继续后接着走
            at(0.3, "track starts") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
            at(1.0, "lyric 1") { m.h_setTitle("晴天", artist: "故事的小黄花", album: "叶惠美", duration: 269, playing: true) }
            at(7.0, "lyric 2 (long)") { m.h_setTitle("晴天", artist: long, album: "叶惠美", duration: 269, playing: true) }
            at(9.0, "pause") { m.h_setTitle("晴天", artist: long, album: "叶惠美", duration: 269, playing: false) }
            at(12.0, "resume") { m.h_setTitle("晴天", artist: long, album: "叶惠美", duration: 269, playing: true) }
            return
        }
        if env["IK_TL"] == "pause" {
            at(0.3, "track starts") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
            at(1.5, "pause") {
                m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: false)
                HarnessHUD.setPauseGrace(0.3)
            }
            for t in [1.9, 2.1, 2.3, 2.6, 3.0, 4.0] { at(t, "probe") {} }
            return
        }
        at(0.5, "track starts") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
        at(2.0, "lyric 1 (short)") { m.h_setTitle("晴天", artist: "故事的小黄花", album: "叶惠美", duration: 269, playing: true) }
        at(6.0, "lyric 2 (long)") { m.h_setTitle("晴天", artist: long, album: "叶惠美", duration: 269, playing: true) }
        at(8.0, "probe mid long line") {}
        at(10.6, "pause") {
            m.h_setTitle("晴天", artist: long, album: "叶惠美", duration: 269, playing: false)
            HarnessHUD.setPauseGrace(1.6)
        }
        at(12.4, "probe during vanish") {}
        at(13.2, "probe hidden") {}
        at(14.0, "demo via darwin") { notify_post("com.islandkit.demo/transition") }
        at(14.4, "probe demo appearing") {}
        at(15.4, "probe demo shown") {}
        at(16.1, "probe demo retracting") {}
        at(17.2, "probe after demo") {}
        at(18.0, "resume playing") { m.h_setTitle("晴天", artist: long, album: "叶惠美", duration: 269, playing: true) }
        at(18.9, "tap (collapse to compact)") { IKController.shared().perform(NSSelectorFromString("tapped")) }
        at(20.0, "probe compact") {}
        at(20.4, "notification") {
            IKController.shared().showNotification(withBundle: "com.apple.MobileSMS", appName: "信息", title: "小明",
                                                   message: "今晚一起吃饭吗？这是一条比较长的通知正文用来看截断效果是否正常", avatar: nil)
        }
        at(21.6, "probe notif") {}
    }
}
