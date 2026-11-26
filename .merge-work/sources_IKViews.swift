import SwiftUI

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

            Caption("系统横幅无法由本应用关闭。想只看岛上的显示，请到 系统设置 → 通知 里把对应应用的“横幅”关掉。覆盖模式下长按自定义胶囊可在歌词态和紧凑态之间切换。")
        }
        .task {
            let list = await Task.detached { AppList.load() }.value
            apps = list
            loading = false
        }
    }
}

// MARK: - 歌词

@available(iOS 16.0, *)
struct LyricView: View {
    @EnvironmentObject var store: Store
    var body: some View {
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKViews.swift
                Caption("单行只显示当前这句歌词；双行第一行显示歌名，第二行显示当前歌词。")
=======
                Caption("单行显示当前这句歌词；双行第一行显示歌名，第二行显示当前歌词。")
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKViews.swift
        Page(title: "歌词") {
            IslandPreview(mode: .music, s: store.s)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(Color.ikStage)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Card {
                SwitchRow(title: "显示歌词", isOn: $store.s.lyric)
                Caption("歌词直接取自系统的“正在播放”信息，不联网。需要音乐 App 把当前歌词上报给系统：请在音乐 App 的设置里打开“蓝牙歌词”或“车载歌词”。播放器不上报歌词时，这里显示歌名和歌手。")
            }

            Card {
                Caption("行数")
                Segmented(value: $store.s.lyricLines, options: [(1, "单行"), (2, "双行")], accent: accent)
                Caption("单行显示当前这句歌词；双行第一行显示歌名，第二行显示当前歌词。")
            }

            Card {
                Caption("动效")
                Segmented(value: $store.s.lyricEffect, options: [(1, "逐行填色"), (2, "淡入"), (0, "无")], accent: accent)
<<<<<<< sources/IKViews.swift
                HStack {
                    Caption("字号")
                    Spacer()
                    Text("\(Int(store.s.lyricFontSize))").font(.system(size: 13))
                }
                Slider(value: $store.s.lyricFontSize, in: 13...18, step: 1) { Text("字号") }
                    .frame(minHeight: 44)
                ColorPicker("歌名颜色", selection: Binding(
                    get: { Color(hex: store.s.songTitleColor) },
                    set: { store.s.songTitleColor = $0.hexString }), supportsOpacity: false)
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKViews.swift

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
=======
                HStack {
                    Caption("字号")
                    Spacer()
                    Text("\(Int(store.s.lyricFontSize))").font(.system(size: 13))
                }
                Slider(value: $store.s.lyricFontSize, in: 13...18, step: 1) { Text("字号") }
                    .frame(minHeight: 44)
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKViews.swift
