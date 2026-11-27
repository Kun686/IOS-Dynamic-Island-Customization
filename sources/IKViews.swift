import SwiftUI
import UniformTypeIdentifiers

// 供 Objective-C 的主程序调用：整个 App 的界面
@objc(IKSettingsFactory)
public final class IKSettingsFactory: NSObject {
    @objc public static func makeSettingsViewController() -> UIViewController {
        if #available(iOS 16.0, *) {
            return UIHostingController(rootView: IKSettingsRoot())
        }
        return UIViewController()
    }
}

@available(iOS 16.0, *)
struct IKSettingsRoot: View {
    @StateObject private var store = Store()
    var body: some View {
        NavigationStack { HomeView() }
            .environmentObject(store)
            .tint(Color(hex: store.s.accent))
            .preferredColorScheme(.dark)
    }
}

// 页面通用外框
@available(iOS 16.0, *)
struct Page<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(20)
        }
        .background(Color.ikGround.ignoresSafeArea())
        .foregroundColor(.ikText)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

@available(iOS 16.0, *)
struct SwitchRow: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(title, isOn: $isOn).font(.system(size: 17, weight: .medium)).frame(minHeight: 44)
    }
}

// MARK: - 首页

@available(iOS 16.0, *)
struct HomeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: PreviewMode = .music
    @State private var running = IsHUDEnabled()
    @State private var busy = false

    // 启动或停止悬浮进程。启动需要一点时间，稍后再确认状态
    private func setRunning(_ on: Bool) {
        busy = true
        SetHUDEnabled(on)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            running = IsHUDEnabled()
            busy = false
        }
    }

    var body: some View {
        let accent = Color(hex: store.s.accent)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("灵动岛").font(.system(size: 30, weight: .bold))
                        HStack(spacing: 6) {
                            Circle().fill(running ? accent : Color.ikMuted).frame(width: 8, height: 8)
                            Text(busy ? "正在切换…" : (running ? "运行中" : "未启动"))
                                .font(.system(size: 13)).foregroundColor(.ikMuted)
                        }
                    }
                    Spacer()
                    Toggle("运行", isOn: Binding(get: { running }, set: { setRunning($0) }))
                        .labelsHidden()
                        .disabled(busy)
                }

                VStack(spacing: 24) {
                    IslandPreview(mode: mode, s: store.s)
                    Segmented(value: $mode, options: [(.idle, "待机"), (.music, "音乐"), (.notif, "通知")], accent: accent)
                }
                .padding(EdgeInsets(top: 28, leading: 16, bottom: 16, trailing: 16))
                .background(Color.ikStage)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(spacing: 12) {
                    FeatureRow(icon: "bell", title: "应用通知", subtitle: "选中的应用改由灵动岛弹出",
                               isOn: $store.s.notif) { NotifyView() }
                    FeatureRow(icon: "text.alignleft", title: "歌词", subtitle: "显示播放器上报的当前歌词",
                               isOn: $store.s.lyric) { LyricView() }
                    FeatureRow(icon: "opticaldisc", title: "封面与进度", subtitle: "封面转动、播放进度环",
                               isOn: $store.s.spin) { CoverView() }
                    LinkRow(icon: "sparkles", title: "外观与动画", subtitle: "显示位置、过渡动画、强调色") { AppearanceView() }
                    LinkRow(icon: "person.crop.circle", title: "关于", subtitle: "开发者信息") { AboutView() }
                }

                Caption(store.saveFailed ? "保存失败：没有写入配置文件的权限。" : "更改即时生效。")
            }
            .padding(20)
        }
        .background(Color.ikGround.ignoresSafeArea())
        .foregroundColor(.ikText)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { phase in
            if phase == .active { running = IsHUDEnabled() }
        }
    }
}

@available(iOS 16.0, *)
struct FeatureRow<Destination: View>: View {
    var icon: String
    var title: String
    var subtitle: String
    @Binding var isOn: Bool
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: destination) {
                RowLabel(icon: icon, title: title, subtitle: subtitle)
            }
            .buttonStyle(.plain)
            Toggle(title, isOn: $isOn).labelsHidden()
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 14))
        .background(Color.ikCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

@available(iOS 16.0, *)
struct LinkRow<Destination: View>: View {
    var icon: String
    var title: String
    var subtitle: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                RowLabel(icon: icon, title: title, subtitle: subtitle)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(.ikMuted)
                    .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .background(Color.ikCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 16.0, *)
struct RowLabel: View {
    var icon: String
    var title: String
    var subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .medium))
                Text(subtitle).font(.system(size: 13)).foregroundColor(.ikMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - 应用通知

@available(iOS 16.0, *)
struct NotifyView: View {
    @EnvironmentObject var store: Store
    @State private var apps: [AppInfo] = []
    @State private var query = ""
    @State private var loading = true
    @State private var avatarTitle = ""
    @State private var selectedAvatarTitle = ""
    @State private var choosingAvatar = false
    @State private var savingAvatar = false
    @State private var avatarStatus = ""

    private var shown: [AppInfo] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { store.s.notifApps.contains(id) },
            set: { on in
                if on { if !store.s.notifApps.contains(id) { store.s.notifApps.append(id) } }
                else { store.s.notifApps.removeAll { $0 == id } }
            })
    }

    var body: some View {
        let accent = Color(hex: store.s.accent)
        Page(title: "应用通知") {
            Card {
                Caption("停留时长")
                Segmented(value: $store.s.notifDuration, options: [(3.0, "3 秒"), (5.0, "5 秒"), (8.0, "8 秒")], accent: accent)
            }

            Card {
                Caption("通知文字颜色")
                ColorPicker("标题和应用名", selection: Binding(
                    get: { Color(hex: store.s.notifTitleColor) },
                    set: { store.s.notifTitleColor = $0.hexString }), supportsOpacity: false)
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
                ColorPicker("正文", selection: Binding(
                    get: { Color(hex: store.s.notifMessageColor) },
                    set: { store.s.notifMessageColor = $0.hexString }), supportsOpacity: false)
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
                Caption("颜色会即时应用到标题、应用名和通知正文。")
            }

            Card {
                DisclosureGroup("微信备用头像") {
                    VStack(alignment: .leading, spacing: 12) {
                        Caption("系统没有提供头像时，用通知标题匹配本地图片。同名会话会共用这张头像。")
                        TextField("微信通知中显示的会话标题", text: $avatarTitle)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: avatarTitle) { _ in avatarStatus = "" }
                        HStack {
                            Button("选择图片") {
                                selectedAvatarTitle = avatarTitle
                                choosingAvatar = true
                            }
                            Spacer()
                            Button("移除绑定") {
                                avatarStatus = IKLocalAvatar.shared().setImage(nil, for: avatarTitle) ?? "已移除绑定"
                            }
                        }.disabled(avatarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || savingAvatar)
                        if !avatarStatus.isEmpty { Caption(avatarStatus) }
                    }.padding(.top, 8)
                }
            }
            .fileImporter(isPresented: $choosingAvatar, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let title = selectedAvatarTitle
                    savingAvatar = true
                    Task {
                        let message = await Task.detached {
                            let scoped = url.startAccessingSecurityScopedResource()
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            return IKLocalAvatar.shared().setImage(url, for: title)
                        }.value
                        savingAvatar = false
                        avatarStatus = message ?? "已为所选会话保存头像"
                    }
                } catch {
                    if (error as NSError).code != NSUserCancelledError { avatarStatus = error.localizedDescription }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Caption("使用灵动岛通知的应用（已选 \(store.s.notifApps.count) 个）")
                TextField("搜索应用", text: $query)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.ikCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            LazyVStack(spacing: 0) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                } else if shown.isEmpty {
                    Caption(apps.isEmpty ? "没有读到应用列表。" : "没有匹配的应用")
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                ForEach(shown) { app in
                    HStack(spacing: 12) {
                        Group {
                            if let icon = app.icon { Image(uiImage: icon).resizable() }
                            else { Color(hex: "2A2A31") }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                        Toggle(app.name, isOn: binding(app.id)).font(.system(size: 16, weight: .medium))
                    }
                    .frame(minHeight: 60)
                    Divider().overlay(Color(hex: "2A2A31"))
                }
            }
            .padding(.horizontal, 16)
            .background(Color.ikCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Caption("系统横幅无法由本应用关闭。想只看岛上的显示，请到 系统设置 → 通知 里把对应应用的“横幅”关掉。聊天类通知会优先显示发送者头像。")
        }
        .task {
            let list = await Task.detached { AppList.load() }.value
            apps = list
            loading = false
        }
    }
}

// MARK: - 歌词

private struct PlaybackReportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@available(iOS 16.0, *)
struct LyricView: View {
    @EnvironmentObject var store: Store
    @State private var choosingLyrics = false
    @State private var target: [AnyHashable: Any] = [:]
    @State private var lyricStatus = ""
    @State private var queryingTrack = false
    @State private var exportingReport = false
    @State private var reportDocument: PlaybackReportDocument?
    @State private var selectingSamples = false
    @State private var sampleReport: String?

    private func currentTrack(_ action: @escaping ([AnyHashable: Any]) -> Void) {
        queryingTrack = true
        IKMusicCenter.importTarget { track in
            queryingTrack = false
            guard let track = track else {
                lyricStatus = "请打开悬浮窗或播放器联动，再在 QQ 音乐或网易云音乐播放歌曲"
                target = [:]
                return
            }
            target = track
            lyricStatus = [track["title"] as? String, track["mode"] as? String].compactMap { $0 }.joined(separator: " · ")
            action(track)
        }
    }

    var body: some View {
        let accent = Color(hex: store.s.accent)
        Page(title: "歌词") {
            IslandPreview(mode: .music, s: store.s)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(Color.ikStage)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Card {
                SwitchRow(title: "显示歌词", isOn: $store.s.lyric)
                Caption("默认播放样式")
                Segmented(value: $store.s.defaultMusicView, options: [(0, "歌词态"), (1, "紧凑态")], accent: accent)
                    .disabled(!store.s.lyric)
                Caption("紧凑态只显示封面和音柱。播放时点按或长按屏幕顶部的胶囊可以切换。")
                Caption("播放器时间轴按播放位置换句。只有蓝牙或车载歌词时，显示播放器上报的当前句。")
            }

            Card {
                Button("为当前歌曲选择歌词文件") {
                    currentTrack { selection in
                        if selection["live"] as? Bool == true { lyricStatus = "当前是电台或直播节目，无法按录音绑定时间轴" }
                        else { selectingSamples = false; choosingLyrics = true }
                    }
                }
                    .disabled(queryingTrack)
                Caption(lyricStatus.isEmpty ? "支持带时间标签的 LRC 和明文 QRC、YRC。" : lyricStatus)
                Button("导出播放诊断") {
                    let sample = sampleReport
                    Task {
                        let history = await Task.detached { IKMusicCenter.playbackDiagnosticReport() }.value
                        let parts = [history, sample].compactMap { $0 }
                        reportDocument = PlaybackReportDocument(text: parts.joined(separator: "\n"))
                        exportingReport = true
                    }
                }
                .fileExporter(isPresented: $exportingReport, document: reportDocument, contentType: .plainText,
                              defaultFilename: "IslandKit-播放诊断") { result in
                    if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                        lyricStatus = error.localizedDescription
                    }
                }
                Button("检查已导出的歌词样本文件夹") {
                    selectingSamples = true
                    choosingLyrics = true
                }.disabled(queryingTrack)
                if target["mode"] as? String == "已绑定本地时间轴" {
                    Button("移除这首歌的绑定") {
                        lyricStatus = IKMusicCenter.removeImport(for: target) ?? "已移除本地时间轴"
                        target["mode"] = nil
                    }.disabled(queryingTrack)
                }
            }

            Card {
                Caption("行数")
                Segmented(value: $store.s.lyricLines, options: [(1, "单行"), (2, "双行")], accent: accent)
                Caption("单行只显示当前这句歌词；双行第一行显示歌名，第二行显示当前歌词。")
                Caption("文字对齐")
                Segmented(value: $store.s.lyricAlignment, options: [(0, "靠左"), (1, "居中"), (2, "靠右")], accent: accent)
            }

            Card {
                Caption("动效")
                Segmented(value: $store.s.lyricEffect, options: [(1, "逐行填色"), (2, "淡入"), (0, "无")], accent: accent)
                Caption("动效只作用在歌词这一行，歌名不跟着变。比胶囊宽的歌词不截断，会跟着进度向左滚动。")
                SliderRow(title: "字号", value: $store.s.lyricFontSize, range: 13...18, step: 1)
            }

            Card {
                ColorModeRow(title: "歌词颜色", mode: $store.s.lyricColorMode, hex: $store.s.lyricColor, accent: accent)
                ColorModeRow(title: "歌名颜色", mode: $store.s.titleColorMode, hex: $store.s.titleColor, accent: accent,
                             allowsDefault: true)
                Caption("歌名和歌词各用各的颜色。歌名显示在双行的第一行；播放器没有上报歌词时，单行也显示歌名。")
            }
        }
        .onAppear { currentTrack { _ in } }
        .fileImporter(isPresented: $choosingLyrics, allowedContentTypes: selectingSamples ? [.folder] : [.data]) { result in
            do {
                let url = try result.get()
                let selectedTrack = target
                let inspecting = selectingSamples
                queryingTrack = true
                Task {
                    let message: String? = await Task.detached {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return inspecting ? IKMusicCenter.sampleReport(at: url) : IKMusicCenter.importLyrics(at: url, target: selectedTrack)
                    }.value
                    queryingTrack = false
                    if inspecting {
                        sampleReport = message
                        lyricStatus = message == nil ? "样本文件夹无法读取" : "样本已检查，请在离开本页前点“导出播放诊断”保存结果。"
                    } else if let message = message {
                        lyricStatus = message
                    } else {
                        target = selectedTrack
                        target["mode"] = "已绑定本地时间轴"
                        lyricStatus = "已绑定到《\(selectedTrack["title"] as? String ?? "")》"
                    }
                }
            } catch {
                if (error as NSError).code != NSUserCancelledError { lyricStatus = error.localizedDescription }
            }
        }
    }
}

// MARK: - 封面与进度

@available(iOS 16.0, *)
struct CoverView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let accent = Color(hex: store.s.accent)
        Page(title: "封面与进度") {
            Card {
                SwitchRow(title: "封面转动", isOn: $store.s.spin)
                HStack {
                    Caption("转一圈用时")
                    Spacer()
                    Text("\(Int(store.s.spinSeconds)) 秒").font(.system(size: 13))
                }
                Slider(value: $store.s.spinSeconds, in: 3...20, step: 1) { Text("转一圈用时") }
                    .frame(minHeight: 44)
                SwitchRow(title: "暂停播放时停转", isOn: $store.s.pauseStops)
            }

            Card {
                SwitchRow(title: "播放进度环", isOn: $store.s.progressRing)
                Caption("进度沿胶囊边缘从顶部顺时针走，走满一圈表示这首歌播完。")
                ColorModeRow(title: "进度环颜色", mode: $store.s.ringColorMode, hex: $store.s.ringColor, accent: accent)
            }
        }
    }
}

// MARK: - 外观与动画

@available(iOS 16.0, *)
struct AppearanceView: View {
    @EnvironmentObject var store: Store
    @State private var demoTick = 0
    @State private var calibrating = false

    private let styles: [(Int, String, String)] = [
        (0, "回弹下落", "从岛里落下，轻微回弹"),
        (1, "柔和滑入", "从岛里平滑滑出，不回弹"),
        (2, "淡入", "原地淡入淡出"),
        (3, "缩放弹出", "原地由小变大"),
        (4, "果冻", "下落后明显晃动几下"),
    ]
    private let renew = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // 悬浮进程换层级要先向 SpringBoard 注销窗口再重新登记。系统里有注销接口时它自己就能即时完成；
    // 没有的话（目前见过的 iOS 14.2、16.6、18.7 都有）由这里把悬浮进程重启一遍，效果一样只是慢一点
    private let liveLevel: Bool = (NSClassFromString("SBSAccessibilityWindowHostingController") as? NSObject.Type)?
        .instancesRespond(to: NSSelectorFromString("unregisterWindowWithContextID:")) ?? false

    private func restartHUD() {
        guard IsHUDEnabled() else { return }
        SetHUDEnabled(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { SetHUDEnabled(true) }
    }

    private func setCalibrating(_ on: Bool) {
        calibrating = on
        store.setCalibrating(on)
    }

    var body: some View {
        let accent = Color(hex: store.s.accent)
        Page(title: "外观与动画") {
            Card {
                Caption("过渡动画")
                TransitionStage(style: store.s.transitionStyle, trigger: demoTick, accent: accent)
                ForEach(styles.indices, id: \.self) { i in
                    let item = styles[i]
                    let on = store.s.transitionStyle == item.0
                    Button {
                        // 选中并马上演示：这里播一遍，悬浮窗在运行时屏幕顶部的岛也播一遍
                        store.s.transitionStyle = item.0
                        demoTick += 1
                        store.demoTransition()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(on ? accent : .ikMuted)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.1).font(.system(size: 16, weight: .medium))
                                Text(item.2).font(.system(size: 13)).foregroundColor(.ikMuted)
                            }
                            Spacer()
                            Image(systemName: "play.circle")
                                .font(.system(size: 20))
                                .foregroundColor(on ? accent : .ikMuted)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint("选中并演示")
                }
                Caption("点任意一项会选中它并演示一遍；再点一次可以重播。悬浮窗在运行时，屏幕顶部的岛会同步演示。")
            }

            Card {
                Caption("显示位置")
                Segmented(value: $store.s.placement, options: [(0, "系统岛下方"), (1, "覆盖系统岛")], accent: accent)
                Caption(store.s.placement == 0
                        ? "系统岛照常显示，歌词和通知挂在它下面，不遮挡状态栏时间。"
                        : "盖在系统岛上，把系统岛自己显示的内容（专辑图、波形等）挡住。收起时整个缩回开孔里面。")
            }

            if store.s.placement == 1 {
                Card {
                    Caption("覆盖范围")
                    SliderRow(title: "比开孔宽出", value: $store.s.coverExtraWidth, range: -6...40, step: 0.5, format: "%.1f")
                    SliderRow(title: "比开孔高出", value: $store.s.coverExtraHeight, range: -4...16, step: 0.5, format: "%.1f")
                    SliderRow(title: "上下位置", value: $store.s.coverOffsetY, range: -8...8, step: 0.5, format: "%.1f")
                    Toggle("显示校准描边", isOn: Binding(get: { calibrating }, set: { setCalibrating($0) }))
                        .font(.system(size: 15))
                        .frame(minHeight: 44)
                    Caption("打开后，没有歌曲和通知时会在屏幕顶部用红线画出胶囊在开孔处的范围，本页顶部同时变成白底，方便对着真正的系统岛调整：红线刚好把黑色的系统岛包住就合适。离开本页或 90 秒后自动关闭。")
                    Caption("左右方向不用手动调：悬浮窗会读取系统岛此刻的实际大小，把胶囊加宽到刚好盖住它；读不到时按系统岛紧凑显示最宽的情况留宽度。系统岛展开（长按、来电等）时胶囊会先让开，等它收回去再出现。")
                    Button("恢复默认") {
                        store.s.coverExtraWidth = 3
                        store.s.coverExtraHeight = 3
                        store.s.coverOffsetY = 0
                    }
                    .font(.system(size: 15, weight: .medium))
                    .frame(minHeight: 44)
                }
            }

            Card {
                Caption("悬浮窗层级")
                Segmented(value: $store.s.windowLevelBoost, options: [(0, "自动"), (1, "更高"), (2, "最高")], accent: accent)
                Caption((liveLevel ? "改动立即生效。" : "改动后会自动重启悬浮窗，大约 1 秒。")
                        + (store.s.placement == 1
                           ? "自动档在覆盖系统岛时使用最高层级，确保系统岛内容和开孔遮罩都不会压住胶囊；下挂模式的自动档使用标准层级。“更高”“最高”会连隐私指示灯一起盖住。如果切换后岛没有再出现，到首页把运行开关关掉再打开。"
                           : "自动档使用标准层级，已经在系统岛内容之上；“更高”“最高”会连开孔遮罩和隐私指示灯一起盖住。如果切换后岛没有再出现，到首页把运行开关关掉再打开。"))
            }

            Card {
                Caption("强调色")
                ColorPicker("选择颜色", selection: Binding(
                    get: { Color(hex: store.s.accent) },
                    set: { store.s.accent = $0.hexString }), supportsOpacity: false)
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
            }
        }
        // 校准时把导航栏（一直延伸到屏幕顶端）换成白底，黑色的系统岛才看得清
        .toolbarBackground(calibrating ? Color.white : Color.ikGround, for: .navigationBar)
        .toolbarBackground(calibrating ? .visible : .automatic, for: .navigationBar)
        .toolbarColorScheme(calibrating ? .light : .dark, for: .navigationBar)
        .onReceive(renew) { _ in
            if calibrating { store.setCalibrating(true) }
        }
        .onChange(of: store.s.windowLevelBoost) { _ in
            if !liveLevel { restartHUD() }
        }
        .onChange(of: store.s.placement) { value in
            if value != 1 && calibrating { setCalibrating(false) }
        }
        .onAppear { demoTick += 1 }
        .onDisappear {
            if calibrating { setCalibrating(false) }
        }
    }
}

// MARK: - 关于

@available(iOS 16.0, *)
struct AboutView: View {
    @State private var copied = false
    private let wechat = "-6-6-6666"

    var body: some View {
        Page(title: "关于") {
            Card {
                Text("亦辰").font(.system(size: 22, weight: .bold))
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                   let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    Caption("灵动岛美化 \(version) (\(build))")
                }
                Text("灵动岛美化的作者。使用中遇到问题或有新想法，欢迎通过微信联系。")
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card {
                Caption("微信")
                HStack {
                    Text(wechat).font(.system(size: 17, weight: .medium)).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "已复制" : "复制") {
                        UIPasteboard.general.string = wechat
                        copied = true
                    }
                    .font(.system(size: 15, weight: .medium))
                    .frame(minWidth: 64, minHeight: 44)
                }
            }

            Card {
                Caption("致谢")
                Text("悬浮窗部分基于 Lessica 的开源项目 TrollSpeed（MIT 许可证）。")
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
