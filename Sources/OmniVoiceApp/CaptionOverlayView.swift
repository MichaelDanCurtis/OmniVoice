import SwiftUI
import OmniVoiceCore

struct CaptionOverlayView: View {
    let text: String
    let styleName: String
    let level: Float
    let theme: OmniVoiceTheme

    var body: some View {
        let accent = Color(themeColor: theme.accentColor)
        let secondary = Color(themeColor: theme.secondaryAccentColor)
        let textColor = Color(themeColor: theme.textColor)
        let mutedTextColor = Color(themeColor: theme.mutedTextColor)

        VStack(spacing: 8) {
            Text(styleName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(mutedTextColor.opacity(theme.mutedTextOpacity))

            VStack(spacing: 8) {
                Text(text.isEmpty ? "Listening..." : text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.88))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                WaveformPreview(
                    mode: theme.waveformMode,
                    level: level,
                    accent: accent,
                    secondary: secondary,
                    muted: mutedTextColor
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .themeSurface(theme, cornerRadius: 8, strong: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minWidth: 320, maxWidth: 760)
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
