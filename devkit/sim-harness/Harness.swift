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
                        "coverExtraWidth", "coverExtraHeight", "coverOffsetY", "coverCompactSide", "calibrateUntil",
                        "lyricAlignment", "lyricOffsetX", "lyricOffsetY", "musicStyle"] {
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
            if let v = env["IK_defaultMusicView"], let i = Int(v) { store.s.defaultMusicView = i }
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
            case "notify": root = AnyView(NavigationStack { NotifyView() })
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
        if env["IK_TL"] == "interrupt" {
            let ctl = IKController.shared()!
            var clipped = 0
            let t0 = CACurrentMediaTime()
            let sampler = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
                if !HarnessHUD.expandedContentFitsPresentation() {
                    clipped += 1
                    self?.log(String(format: "clipped at t=%.3f | %@ | %@", CACurrentMediaTime() - t0,
                                     HarnessHUD.describeIsland(), HarnessHUD.describeRows()))
                }
            }
            at(0.1, "start") { m.h_setTitle("歌曲", artist: "歌手", album: "专辑", duration: 150, playing: true) }
            at(0.16, "same geometry refresh") { ctl.refresh() }
            at(0.22, "compact") { ctl.perform(NSSelectorFromString("tapped")) }
            at(0.30, "expand again") { ctl.perform(NSSelectorFromString("tapped")) }
            at(0.37, "demo") { ctl.perform(NSSelectorFromString("playTransitionDemo")) }
            at(0.45, "restart demo") { ctl.perform(NSSelectorFromString("playTransitionDemo")) }
            at(0.55, "interrupt with notification") {
                ctl.showNotification(withBundle: "example.test", appName: "测试", title: "通知", message: "正文", avatar: nil)
            }
            at(0.61, "refresh during retraction") { ctl.refresh() }
            at(1.9, "end notification") { ctl.perform(NSSelectorFromString("dismissNotification")) }
            at(3.8, "width change while lyrics fit") {
                let prefs = IKPrefs.shared()!
                let sw = UIScreen.main.bounds.width
                let f = CGRect(x: 9, y: prefs.islandTop, width: sw - 18, height: prefs.cutoutHeight)
                HarnessHUD.setSystemFrames([NSValue(cgRect: f)])
            }
            at(3.95, "text remains visible during resize") { precondition(HarnessHUD.expandedRowsVisible()) }
            at(4.5, "check") {
                sampler.invalidate()
                precondition(clipped == 0, "clipped content in \(clipped) frames")
            }
            return
        }
        if env["IK_TL"] == "morph" {
            // 0.6.6：音乐 ↔ 通知直接变形、紧凑 ↔ 歌词时进度环跟着胶囊。逐帧检查：
            //   胶囊始终盖住模拟的系统岛紧凑态；环和胶囊同尺寸同圆角；紧凑 ↔ 歌词期间环一直可见
            let ctl = IKController.shared()!
            let p = IKPrefs.shared()!
            let sw = UIScreen.main.bounds.width
            let sys = CGRect(x: (sw - 250.67) / 2, y: p.islandTop, width: 250.67, height: p.cutoutHeight)
            var sampling = false, ringPhase = false
            var frames = 0, coverFail = 0, ringFail = 0, ringFrames = 0
            var minRing = 1.0
            var firstCover: String?, firstRing: String?
            let sampler = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
                guard sampling else { return }
                frames += 1
                if let problem = HarnessHUD.coverageProblem(forSystemRect: sys) { coverFail += 1; firstCover = firstCover ?? problem }
                if let problem = HarnessHUD.ringProblem() { ringFail += 1; firstRing = firstRing ?? problem }
                if ringPhase { ringFrames += 1; minRing = min(minRing, HarnessHUD.ringOpacity()) }
            }
            at(0.2, "system compact 250.67") { HarnessHUD.setSystemFrames([NSValue(cgRect: sys)]) }
            at(0.3, "track starts") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
            at(1.0, "lyric") { m.h_setTitle("晴天", artist: "故事的小黄花", album: "叶惠美", duration: 269, playing: true) }
            at(2.0, "start sampling") { sampling = true }
            at(2.2, "notification while lyric") {
                ctl.showNotification(withBundle: "com.tencent.xin", appName: "微信", title: "小明", message: "今晚一起吃饭吗？", avatar: nil)
            }
            at(4.0, "dismiss -> lyric") { ctl.perform(NSSelectorFromString("dismissNotification")) }
            at(5.2, "tap -> compact") { ringPhase = true; ctl.perform(NSSelectorFromString("tapped")) }
            at(6.4, "tap -> lyric") { ctl.perform(NSSelectorFromString("tapped")) }
            at(7.4, "tap -> compact") { ctl.perform(NSSelectorFromString("tapped")) }
            at(8.4, "notification while compact") {
                ringPhase = false
                ctl.showNotification(withBundle: "com.tencent.xin", appName: "微信", title: "小红", message: "收到", avatar: nil)
            }
            at(9.8, "dismiss -> compact") { ctl.perform(NSSelectorFromString("dismissNotification")) }
            at(11.0, "report") {
                sampling = false
                sampler.invalidate()
                self.log(String(format: "morph frames=%d coverFail=%d ringFail=%d ringFrames=%d minRingOpacity=%.2f firstCover=%@ firstRing=%@",
                                frames, coverFail, ringFail, ringFrames, minRing, firstCover ?? "-", firstRing ?? "-"))
            }
            return
        }
        if env["IK_TL"] == "hang" || env["IK_TL"] == "record" {
            // 悬挂歌词（IK_musicStyle=2）、通知弹出、录屏提示。逐帧检查胶囊始终盖住模拟的系统岛紧凑态
            let ctl = IKController.shared()!
            let p = IKPrefs.shared()!
            let sw = UIScreen.main.bounds.width
            let sys = CGRect(x: (sw - 250.67) / 2, y: p.islandTop, width: 250.67, height: p.cutoutHeight)
            var sampling = false, frames = 0, coverFail = 0
            var firstCover: String?
            let sampler = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
                guard sampling else { return }
                frames += 1
                if let problem = HarnessHUD.coverageProblem(forSystemRect: sys) { coverFail += 1; firstCover = firstCover ?? problem }
            }
            at(0.2, "system compact 250.67") { HarnessHUD.setSystemFrames([NSValue(cgRect: sys)]) }
            if env["IK_TL"] == "hang" {
                at(0.3, "track starts") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
                at(1.0, "lyric") { m.h_setTitle("晴天", artist: "故事的小黄花 从出生那年就飘着", album: "叶惠美", duration: 269, playing: true) }
                at(2.0, "start sampling") { sampling = true }
                at(2.2, "notification while hang") {
                    ctl.showNotification(withBundle: "com.tencent.xin", appName: "微信", title: "小明", message: "今晚一起吃饭吗？", avatar: nil)
                }
                at(4.0, "dismiss -> hang") { ctl.perform(NSSelectorFromString("dismissNotification")) }
                at(5.2, "tap -> compact") { ctl.perform(NSSelectorFromString("tapped")) }
                at(6.4, "tap -> hang") { ctl.perform(NSSelectorFromString("tapped")) }
                at(7.6, "recording starts while hang") { HarnessHUD.setScreenCaptured(true) }
                at(10.8, "probe hang with record dot") {}
                at(11.0, "recording stops") { HarnessHUD.setScreenCaptured(false) }
            } else {
                // 第一次从开孔里长出来那一段不算（模拟的系统岛画成了紧凑态，长出来途中本来就盖不住）
                at(0.6, "recording starts, no music") { HarnessHUD.setScreenCaptured(true) }
                at(1.4, "probe banner") { sampling = true }
                at(4.0, "probe record state") {}
                at(6.5, "probe timer") {}
                at(7.0, "music starts while recording") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
                at(8.5, "probe lyric with dot") {}
                at(9.0, "recording stops") { HarnessHUD.setScreenCaptured(false) }
                at(10.0, "probe end banner") {}
            }
            at(14.5, "report") {
                sampling = false
                sampler.invalidate()
                self.log(String(format: "%@ frames=%d coverFail=%d firstCover=%@", self.env["IK_TL"]!, frames, coverFail, firstCover ?? "-"))
            }
            return
        }
        if env["IK_TL"] == "align" {
            at(0.3, "track starts") { m.h_setTitle("晴天", artist: "周杰伦", album: "叶惠美", duration: 269, playing: true) }
            at(1.0, "lyric") { m.h_setTitle("晴天", artist: "故事的小黄花", album: "叶惠美", duration: 269, playing: true) }
            at(2.0, "probe") { self.log(String(format: "align firstRowCenterOffset=%.2f", HarnessHUD.firstRowCenterOffset())) }
            return
        }
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
