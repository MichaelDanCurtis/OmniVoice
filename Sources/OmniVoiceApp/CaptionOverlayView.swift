import SwiftUI
import OmniVoiceCore

enum CaptionOverlayPhase: Equatable {
    case live
    case committing(CommitAnimationMode)

    var mode: CommitAnimationMode? {
        switch self {
        case .live:
            nil
        case .committing(let mode):
            mode
        }
    }

    var duration: TimeInterval {
        switch mode {
        case .some(.glyphStream):
            0.52
        case .some(.beamSnap):
            0.42
        case .some(.cometCollapse):
            0.58
        case .some(.none), nil:
            0
        }
    }
}

struct CaptionOverlayView: View {
    let text: String
    let styleName: String
    let level: Float
    let theme: OmniVoiceTheme
    let phase: CaptionOverlayPhase

    @State private var commitStarted = false

    init(
        text: String,
        styleName: String,
        level: Float,
        theme: OmniVoiceTheme,
        phase: CaptionOverlayPhase = .live
    ) {
        self.text = text
        self.styleName = styleName
        self.level = level
        self.theme = theme
        self.phase = phase
    }

    var body: some View {
        let accent = Color(themeColor: theme.accentColor)
        let secondary = Color(themeColor: theme.secondaryAccentColor)
        let textColor = Color.white
        let mutedTextColor = Color.white

        ZStack {
            if let mode = phase.mode, mode != .none {
                CommitTrail(mode: mode, accent: accent, secondary: secondary, isActive: commitStarted)
            }

            VStack(spacing: 7) {
                Text(text.isEmpty ? "Listening..." : text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.90))
                    .lineLimit(CaptionOverlayLayout.captionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(width: CaptionOverlayLayout.captionWidth)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .captionGlassSurface(accent: accent)
                    .scaleEffect(x: captionScale.width, y: captionScale.height)
                    .opacity(captionOpacity)
                    .blur(radius: commitStarted ? captionBlurRadius : 0)
                    .offset(y: commitStarted ? captionYOffset : 0)

                WaveformPreview(
                    mode: theme.waveformMode,
                    level: level,
                    accent: accent,
                    secondary: secondary,
                    muted: mutedTextColor
                )
                .opacity(commitStarted ? 0 : 1)
                .scaleEffect(commitStarted ? 0.72 : 1)

                Text(styleName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(mutedTextColor.opacity(commitStarted ? 0 : 0.50))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(
            minWidth: CaptionOverlayLayout.windowMinWidth,
            maxWidth: CaptionOverlayLayout.windowMaxWidth
        )
        .onAppear {
            guard let mode = phase.mode, mode != .none else { return }
            commitStarted = false
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: phase.duration)) {
                    commitStarted = true
                }
            }
        }
    }

    private var captionScale: CGSize {
        guard commitStarted, let mode = phase.mode else {
            return CGSize(width: 1, height: 1)
        }

        switch mode {
        case .glyphStream:
            return CGSize(width: 0.32, height: 0.36)
        case .beamSnap:
            return CGSize(width: 0.18, height: 0.18)
        case .cometCollapse:
            return CGSize(width: 0.08, height: 0.08)
        case .none:
            return CGSize(width: 1, height: 1)
        }
    }

    private var captionOpacity: Double {
        guard commitStarted, let mode = phase.mode else {
            return 1
        }

        switch mode {
        case .glyphStream:
            return 0.18
        case .beamSnap:
            return 0.08
        case .cometCollapse:
            return 0.02
        case .none:
            return 1
        }
    }

    private var captionBlurRadius: CGFloat {
        guard let mode = phase.mode else { return 0 }
        switch mode {
        case .glyphStream:
            return 2
        case .beamSnap:
            return 4
        case .cometCollapse:
            return 7
        case .none:
            return 0
        }
    }

    private var captionYOffset: CGFloat {
        guard let mode = phase.mode else { return 0 }
        switch mode {
        case .glyphStream:
            return 20
        case .beamSnap:
            return 8
        case .cometCollapse:
            return 28
        case .none:
            return 0
        }
    }
}

private struct CommitTrail: View {
    let mode: CommitAnimationMode
    let accent: Color
    let secondary: Color
    let isActive: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [secondary.opacity(0), accent.opacity(0.92), secondary.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: isActive ? trailWidth : 0, height: trailHeight)
                .shadow(color: accent.opacity(isActive ? 0.70 : 0), radius: 18)
                .offset(y: isActive ? 19 : 0)

            HStack(spacing: 7) {
                ForEach(glyphs.indices, id: \.self) { index in
                    Text(glyphs[index])
                        .font(.system(size: glyphSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent.opacity(isActive ? glyphOpacity(index) : 0))
                        .offset(x: isActive ? CGFloat(index - glyphs.count / 2) * 10 : 0, y: isActive ? 18 : 0)
                }
            }
        }
        .scaleEffect(isActive ? 1 : 0.5)
    }

    private var trailWidth: CGFloat {
        switch mode {
        case .glyphStream:
            210
        case .beamSnap:
            160
        case .cometCollapse:
            64
        case .none:
            0
        }
    }

    private var trailHeight: CGFloat {
        switch mode {
        case .glyphStream:
            4
        case .beamSnap:
            6
        case .cometCollapse:
            18
        case .none:
            0
        }
    }

    private var glyphSize: CGFloat {
        mode == .cometCollapse ? 9 : 11
    }

    private func glyphOpacity(_ index: Int) -> Double {
        switch mode {
        case .glyphStream:
            return index.isMultiple(of: 2) ? 0.78 : 0.40
        case .beamSnap:
            return 0.26
        case .cometCollapse:
            return 0.12
        case .none:
            return 0
        }
    }

    private var glyphs: [String] {
        ["A", "ov", "7", "tx", "01", ">", "V"]
    }
}

private struct CaptionGlassSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color.black.opacity(0.10), in: shape)
            .overlay {
                shape.stroke(accent.opacity(0.20), lineWidth: 1)
            }
            .shadow(color: accent.opacity(0.12), radius: 12, x: 0, y: 5)
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private extension View {
    func captionGlassSurface(accent: Color) -> some View {
        modifier(CaptionGlassSurface(accent: accent))
    }
}

private struct WaveformPreview: View {
    let mode: WaveformMode
    let level: Float
    let accent: Color
    let secondary: Color
    let muted: Color

    private var normalizedLevel: Double {
        min(max(Double(level) * 45, 0), 1)
    }

    var body: some View {
        Group {
            switch mode {
            case .bars:
                bars
            case .pulseRing:
                pulseRing
            case .spectrumLine:
                spectrumLine
            case .orbMeter:
                orbMeter
            case .glyphStream:
                glyphStream
            }
        }
        .frame(width: 156, height: 28)
    }

    private var bars: some View {
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { index in
                Capsule()
                    .fill(index < activeBars ? accent.opacity(0.82) : muted.opacity(0.16))
                    .frame(width: 5, height: CGFloat(6 + (index % 5) * 3))
            }
        }
    }

    private var pulseRing: some View {
        ZStack {
            Circle()
                .stroke(secondary.opacity(0.20), lineWidth: 2)
                .frame(width: 22, height: 22)

            Circle()
                .stroke(accent.opacity(0.35 + normalizedLevel * 0.45), lineWidth: 2)
                .frame(width: CGFloat(12 + normalizedLevel * 14), height: CGFloat(12 + normalizedLevel * 14))

            Circle()
                .fill(accent.opacity(0.78))
                .frame(width: CGFloat(5 + normalizedLevel * 5), height: CGFloat(5 + normalizedLevel * 5))
        }
    }

    private var spectrumLine: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                let midY = height / 2
                path.move(to: CGPoint(x: 0, y: midY))

                for index in 0...18 {
                    let progress = CGFloat(index) / 18
                    let wave = sin(progress * .pi * 3)
                    let amplitude = CGFloat(3 + normalizedLevel * 8)
                    path.addLine(to: CGPoint(x: width * progress, y: midY - wave * amplitude))
                }
            }
            .stroke(
                LinearGradient(colors: [secondary.opacity(0.75), accent], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var orbMeter: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Double(index + 1) / 5
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(normalizedLevel >= threshold ? 0.95 : 0.26),
                                secondary.opacity(normalizedLevel >= threshold ? 0.34 : 0.10)
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 8
                        )
                    )
                    .frame(width: 12, height: 12)
            }
        }
    }

    private var glyphStream: some View {
        HStack(spacing: 8) {
            ForEach(glyphs.indices, id: \.self) { index in
                Text(glyphs[index])
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(index < activeGlyphs ? accent.opacity(0.86) : muted.opacity(0.24))
                    .frame(width: 10, height: 16)
            }
        }
    }

    private var activeBars: Int {
        Int((normalizedLevel * 14).rounded(.up))
    }

    private var activeGlyphs: Int {
        Int((normalizedLevel * Double(glyphs.count)).rounded(.up))
    }

    private var glyphs: [String] {
        ["ov", "01", "A", "7", "tx", ">", "9", "V", "3"]
    }
}
