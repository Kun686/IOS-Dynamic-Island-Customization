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
    @State private var tilt: Double = 0

    private var entrance: Animation {
        switch style {
        case 1: return .easeOut(duration: 0.42)
        case 2: return .easeInOut(duration: 0.3)
        case 3: return .spring(response: 0.5, dampingFraction: 0.7)
        case 4: return .spring(response: 0.78, dampingFraction: 0.48)
        default: return .spring(response: 0.62, dampingFraction: 0.72)
        }
    }

    private func play() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            visible = false
            offset = style == 2 ? 0 : -28
            scale = style == 3 ? 0.64 : 1
            tilt = style == 4 ? -6 : 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(entrance) {
                visible = true
                offset = 0
                scale = 1
                tilt = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            withAnimation(.easeIn(duration: 0.28)) {
                visible = false
                offset = style == 2 ? 0 : -24
                scale = style == 3 ? 0.72 : 1
            }
        }
    }

    var body: some View {
        IslandPreview(mode: .music, s: settings)
            .opacity(visible ? 1 : 0)
            .offset(y: offset)
            .scaleEffect(scale)
            .rotationEffect(.degrees(tilt))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: play)
            .onChange(of: run) { _ in play() }
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
                        if s.lyric {
                            Text("当前歌词行").font(.system(size: 16, weight: .bold)).foregroundColor(accent)
                            if s.lyricLines >= 2 {
                                Text("下一句歌词").font(.system(size: 13)).foregroundColor(.ikMuted)
                            }
                        } else {
                            Text("歌曲名").font(.system(size: 15, weight: .medium)).foregroundColor(.ikText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(width: 320, height: 76)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            case .notif:
                if s.notif {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "2A2A31"))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("发送者").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: s.notifTitleColor))
                            Text("通知内容预览").font(.system(size: 13)).foregroundColor(Color(hex: s.notifMessageColor))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 320, height: 76)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                } else {
                    Capsule().fill(Color.black).frame(width: 126, height: 37)
                    Caption("已关闭，通知仍走系统横幅")
                }
            }
        }
        .frame(height: 96)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mode)
    }
}

// 颜色来源：强调色 / 跟随封面 / 自定义（自定义时出现取色器）
@available(iOS 16.0, *)
struct ColorModeRow: View {
    var title: String
    @Binding var mode: Int
    @Binding var hex: String
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caption(title)
            Segmented(value: $mode, options: [(0, "强调色"), (1, "跟随封面"), (2, "自定义")], accent: accent)
            if mode == 2 {
                ColorPicker("选择颜色", selection: Binding(
                    get: { Color(hex: hex) },
                    set: { hex = $0.hexString }), supportsOpacity: false)
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
            }
        }
    }
}
