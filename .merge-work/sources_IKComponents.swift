import SwiftUI

// 旋转的唱片占位。真机上岛里显示的是实际专辑封面
@available(iOS 16.0, *)
struct Disc: View {
    var size: CGFloat
    var spinning: Bool
    var seconds: Double
    var accent: Color

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let angle = (t / max(seconds, 1)).truncatingRemainder(dividingBy: 1) * 360
            ZStack {
                Circle().fill(AngularGradient(
                    stops: [
                        .init(color: Color(hex: "3A3A44"), location: 0), .init(color: Color(hex: "3A3A44"), location: 0.25),
                        .init(color: Color(hex: "1C1C22"), location: 0.25), .init(color: Color(hex: "1C1C22"), location: 0.5),
                        .init(color: Color(hex: "3A3A44"), location: 0.5), .init(color: Color(hex: "3A3A44"), location: 0.75),
                        .init(color: Color(hex: "1C1C22"), location: 0.75), .init(color: Color(hex: "1C1C22"), location: 1),
                    ], center: .center))
                Circle().fill(accent).frame(width: size * 0.36, height: size * 0.36)
                    .overlay(Circle().stroke(Color.black, lineWidth: size * 0.06))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
        }
        .accessibilityHidden(true)
    }
}

// 分段选择
@available(iOS 16.0, *)
struct Segmented<T: Hashable>: View {
    @Binding var value: T
    var options: [(T, String)]
    var accent: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                let on = (opt.0 == value)
                Button {
                    value = opt.0
                } label: {
                    Text(opt.1)
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? accent : Color.clear)
                        .foregroundColor(on ? .ikGround : Color(hex: "C9C9D1"))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.ikGround)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@available(iOS 16.0, *)
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ikCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

@available(iOS 16.0, *)
struct Caption: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundColor(.ikMuted)
    }
}

// 岛的预览
enum PreviewMode: Hashable { case idle, music, notif }

@available(iOS 16.0, *)
struct TransitionDemo: View {
    var style: Int
    var settings: Settings
    var run: Int
    @State private var visible = false
    @State private var offset: CGFloat = -28
    @State private var scale: CGFloat = 1

    private func entrance(for style: Int) -> Animation {
        switch style {
        case 1: return .spring(response: 0.42, dampingFraction: 1.0)
<<<<<<< /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKComponents.swift
                let size = CGFloat(s.lyricFontSize)
                let titleColor = s.previewColor(mode: s.titleColorMode, custom: s.titleColor)
                let lyricColor = s.previewColor(mode: s.lyricColorMode, custom: s.lyricColor)
=======
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKComponents.swift
        default: return .spring(response: 0.62, dampingFraction: 0.62)
        }
    }

    @MainActor
    private func reset(for style: Int) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            visible = false
            offset = style == 2 ? 0 : -28
            scale = style == 3 ? 0.6 : 1
        }
    }

    @MainActor
    private func play(style: Int) async {
        reset(for: style)
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(entrance(for: style)) {
                visible = true
                offset = 0
                scale = 1
            }

            try await Task.sleep(nanoseconds: 1_650_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.28)) {
                visible = false
                offset = style == 2 ? 0 : -24
                scale = style == 3 ? 0.7 : 1
            }
        } catch {
            // 新的演示触发时，SwiftUI 会取消旧任务，保持当前帧等待新任务接管。
        }
    }

    var body: some View {
        IslandPreview(mode: .music, s: settings)
            .opacity(visible ? 1 : 0)
            .offset(y: offset)
            .scaleEffect(scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: run) { await play(style: style) }
    }
}

@available(iOS 16.0, *)
struct IslandPreview: View {
    var mode: PreviewMode
    var s: Settings

    var body: some View {
        let accent = Color(hex: s.accent)
        VStack(spacing: 10) {
            switch mode {
            case .idle:
                Capsule().fill(Color.black).frame(width: 126, height: 37)
            case .music:
                HStack(spacing: 12) {
                    Disc(size: 52, spinning: s.spin, seconds: s.spinSeconds, accent: accent)
                    VStack(alignment: .leading, spacing: 2) {
<<<<<<< sources/IKComponents.swift
                        if s.lyric {
                            if s.lyricLines >= 2 {
                                Text("歌曲名").font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(hex: s.songTitleColor))
                                Text("当前歌词行").font(.system(size: 13))
                                    .foregroundColor(accent)
                            } else {
                                Text("当前歌词行").font(.system(size: 16, weight: .bold))
                                    .foregroundColor(accent)
                            }
||||||| /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.6.0-fixed/IslandKit-TS/sources/IKComponents.swift
        } else {
            text.foregroundColor(color)
        }
    }
}

// 颜色来源：强调色 / 跟随封面 / 自定义（自定义时出现取色器）。allowsDefault 时多一个“默认”（白色）
@available(iOS 16.0, *)
struct ColorModeRow: View {
    var title: String
=======
                        if s.lyric {
                            Text("当前歌词行").font(.system(size: 16, weight: .bold)).foregroundColor(accent)
                            if s.lyricLines >= 2 {
                                Text("下一句歌词").font(.system(size: 13)).foregroundColor(.ikMuted)
                            }
>>>>>>> /Users/yichen/Desktop/协作/workspaces/duo/7609e8fb/1d2cb572/write/灵动岛美化/IslandKit-TS-0.5.0-fixed/IslandKit-TS/sources/IKComponents.swift
