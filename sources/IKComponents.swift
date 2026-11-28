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
                let compact = s.defaultMusicView == 1 || !s.lyric
                if compact {
                    HStack(spacing: 12) {
                        Disc(size: 27, spinning: s.spin, seconds: s.spinSeconds, accent: accent)
                        Spacer(minLength: 0)
                        Image(systemName: "waveform").foregroundColor(accent).accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: s.placement == 1 ? 240 : 88)
                    .frame(height: 38)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                } else if s.defaultMusicView == 2 {
                    HangCapsulePreview(s: s, accent: accent)
                } else {
                    LyricCapsulePreview(s: s, accent: accent)
                }
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

// 歌词态的预览。文字位置和岛上的算法一致：居中、自定义都以整个胶囊的中线为准，
// 自定义再加偏移；文字只在封面右边那块区域里移动，到边就停住
@available(iOS 16.0, *)
struct LyricCapsulePreview: View {
    var s: Settings
    var accent: Color

    private static let sample = "正在唱的这一句歌词"

    private func width(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]).width) + 1
    }

    var body: some View {
        let size = CGFloat(s.lyricFontSize)
        let two = s.lyricLines >= 2
        let titleColor = s.previewColor(mode: s.titleColorMode, custom: s.titleColor)
        let lyricColor = s.previewColor(mode: s.lyricColorMode, custom: s.lyricColor)
        let lyricSize = two ? max(11, size - 3) : size
        let lines: [(String, CGFloat, UIFont.Weight)] = two
            ? [("歌名", size, .bold), (Self.sample, lyricSize, .regular)]
            : [(Self.sample, lyricSize, .bold)]
        let custom = s.lyricAlignment == 3
        let disc: CGFloat = two ? 54 : 38
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let areaX = 12 + disc + 12, areaW = max(0, W - areaX - 16)
            let mid = W / 2 + (custom ? CGFloat(s.lyricOffsetX) : 0)
            let lineHeight: [CGFloat] = two ? [size + 6, lyricSize + 5] : [size + 6]
            let blockH = lineHeight.reduce(0, +)
            let dy = custom ? max(-(H - blockH) / 2 + 3, min((H - blockH) / 2 - 3, CGFloat(s.lyricOffsetY))) : 0
            ZStack(alignment: .topLeading) {
                Disc(size: disc, spinning: s.spin, seconds: s.spinSeconds, accent: accent)
                    .position(x: 12 + disc / 2, y: H / 2)
                ForEach(lines.indices, id: \.self) { i in
                    let line = lines[i]
                    let tw = min(areaW, width(line.0, size: line.1, weight: line.2))
                    let spare = areaW - tw
                    let x: CGFloat = s.lyricAlignment == 0 ? 0
                        : (s.lyricAlignment == 2 ? spare : max(0, min(spare, mid - areaX - tw / 2)))
                    let y = (H - blockH) / 2 + dy + lineHeight[..<i].reduce(0, +) + lineHeight[i] / 2
                    Group {
                        if two && i == 0 {
                            Text(line.0).font(.system(size: line.1, weight: .bold)).foregroundColor(titleColor).lineLimit(1)
                        } else {
                            LyricSample(color: lyricColor, font: .system(size: line.1, weight: two ? .regular : .bold),
                                        filled: s.lyricEffect == 1)
                        }
                    }
                    .frame(width: tw, alignment: .leading)
                    .position(x: areaX + x + tw / 2, y: y)
                }
                // 胶囊中线，方便看出“居中”是对着哪里
                if s.lyricAlignment == 1 || custom {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: H - 16)
                        .position(x: W / 2, y: H / 2)
                }
            }
        }
        .frame(maxWidth: 320)
        .frame(height: two ? 76 : 58)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .accessibilityHidden(true)
    }
}

// 悬挂歌词的预览：比系统岛只高一点的胶囊，左边方形专辑图、右边音柱，
// 中间上半部是开孔（用深灰示意），开孔正下方一行居中的小字歌词
@available(iOS 16.0, *)
struct HangCapsulePreview: View {
    var s: Settings
    var accent: Color

    private var artwork: some View {
        RoundedRectangle(cornerRadius: s.placement == 1 ? 6 : 4, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "3A3A44"), accent.opacity(0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var body: some View {
        let lyricColor = s.previewColor(mode: s.lyricColorMode, custom: s.lyricColor)
        let small = CGFloat(max(11, min(13, s.lyricFontSize - 4)))
        let lyric = LyricSample(color: lyricColor, font: .system(size: small, weight: .medium), filled: s.lyricEffect == 1)
        Group {
            if s.placement == 1 {
                ZStack(alignment: .top) {
                    HStack(spacing: 8) {
                        artwork.frame(width: 27, height: 27)
                        Spacer(minLength: 0)
                        Image(systemName: "waveform").font(.system(size: 16, weight: .semibold)).foregroundColor(accent)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    // 开孔示意
                    Capsule().fill(Color(hex: "16161A")).frame(width: 96, height: 28).padding(.top, 5)
                    lyric.padding(.top, 35)
                }
                .frame(width: 250, height: 54)
            } else {
                HStack(spacing: 8) {
                    artwork.frame(width: 20, height: 20)
                    lyric.frame(maxWidth: .infinity)
                    Image(systemName: "waveform").font(.system(size: 13, weight: .semibold)).foregroundColor(accent)
                }
                .padding(.horizontal, 6)
                .frame(width: 230, height: 30)
            }
        }
        .background(Color.black)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// 一句示例歌词。填色动效时前半句是歌词颜色、后半句是没唱到的底色
@available(iOS 16.0, *)
struct LyricSample: View {
    var color: Color
    var font: Font
    var filled: Bool

    var body: some View {
        let text = Text("正在唱的这一句歌词").font(font).lineLimit(1)
        if filled {
            text.foregroundColor(Color.white.opacity(0.5))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        text.foregroundColor(color)
                            .fixedSize()
                            .frame(width: geo.size.width * 0.55, alignment: .leading)
                            .clipped()
                    }
                }
        } else {
            text.foregroundColor(color)
        }
    }
}

// 颜色来源：强调色 / 跟随封面 / 自定义（自定义时出现取色器）。allowsDefault 时多一个“默认”（白色）
@available(iOS 16.0, *)
struct ColorModeRow: View {
    var title: String
    @Binding var mode: Int
    @Binding var hex: String
    var accent: Color
    var allowsDefault = false

    var body: some View {
        let base: [(Int, String)] = [(0, "强调色"), (1, "跟随封面"), (2, "自定义")]
        VStack(alignment: .leading, spacing: 8) {
            Caption(title)
            Segmented(value: $mode, options: allowsDefault ? [(3, "默认")] + base : base, accent: accent)
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

// 带标题和当前数值的滑块
@available(iOS 16.0, *)
struct SliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format = "%.0f"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Caption(title)
                Spacer()
                Text(String(format: format, value)).font(.system(size: 13)).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step) { Text(title) }
                .frame(minHeight: 44)
        }
    }
}

// 过渡动画的演示：一个模拟的系统岛，下面的胶囊按所选风格出现、停留、收起、再出现。
// trigger 每变一次就从头播一遍
@available(iOS 16.0, *)
struct TransitionStage: View {
    var style: Int
    var trigger: Int
    var accent: Color

    @State private var shown = true
    @State private var run = 0

    private var appear: Animation {
        switch style {
        case 1: return .spring(response: 0.42, dampingFraction: 1.0)
        case 2: return .easeInOut(duration: 0.3)
        case 3: return .spring(response: 0.45, dampingFraction: 0.58)
        case 4: return .spring(response: 0.6, dampingFraction: 0.4)
        default: return .spring(response: 0.5, dampingFraction: 0.62)
        }
    }

    // 淡入和缩放是原地出现，其余是从岛里长出来
    private var inPlace: Bool { style == 2 || style == 3 }

    private func play() {
        run += 1
        let current = run
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard current == run else { return }
            withAnimation(appear) { shown = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            guard current == run else { return }
            withAnimation(.easeIn(duration: 0.3)) { shown = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard current == run else { return }
            withAnimation(appear) { shown = true }
        }
    }

    var body: some View {
        let tucked = !shown && !inPlace
        ZStack(alignment: .top) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: "3A3A44")).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: 92, height: 8)
                    Capsule().fill(accent).frame(width: 136, height: 7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .opacity(tucked ? 0 : 1)
            .frame(width: tucked ? 112 : 248, height: tucked ? 26 : 54)
            .background(Color.black)
            .clipShape(Capsule())
            .scaleEffect(!shown && style == 3 ? 0.6 : 1)
            .opacity(!shown && inPlace ? 0 : 1)
            .offset(y: tucked ? 5 : 48)

            // 模拟的系统岛，盖在上面
            Capsule().fill(Color.black).frame(width: 126, height: 37)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112, alignment: .top)
        .padding(.top, 10)
        .background(Color.ikStage)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: trigger) {
            guard trigger != 0 else { return }
            play()
        }
        .accessibilityHidden(true)
    }
}
