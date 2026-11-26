import AppKit
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
        case .some(.magicPoof):
            0.58
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

struct CaptionOverlayLiveHost: View {
    @Bindable var state: CaptionOverlayState

    var body: some View {
        CaptionOverlayView(
            text: state.text,
            styleName: state.styleName,
            translationStatus: state.translationStatus,
            level: state.level,
            theme: state.theme,
            appearanceMode: state.appearanceMode,
            glassOpacity: state.glassOpacity,
            phase: state.phase,
            appearanceToken: state.appearanceToken
        )
    }
}

struct CaptionOverlayView: View {
    let text: String
    let styleName: String
    let translationStatus: String?
    let level: Float
    let theme: OmniVoiceTheme
    let appearanceMode: AppAppearanceMode
    let glassOpacity: Double
    let phase: CaptionOverlayPhase
    let appearanceToken: Int

    @State private var commitStarted = false
    @State private var drawProgress: CGFloat = 1
    @State private var drawGlowOpacity: Double = 0
    @State private var bloomReady = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        text: String,
        styleName: String,
        translationStatus: String? = nil,
        level: Float,
        theme: OmniVoiceTheme,
        appearanceMode: AppAppearanceMode = .system,
        glassOpacity: Double = 0.05,
        phase: CaptionOverlayPhase = .live,
        appearanceToken: Int = 0
    ) {
        self.text = text
        self.styleName = styleName
        self.translationStatus = translationStatus
        self.level = level
        self.theme = theme
        self.appearanceMode = appearanceMode
        self.glassOpacity = glassOpacity
        self.phase = phase
        self.appearanceToken = appearanceToken
    }

    var body: some View {
        let palette = theme.resolvedPalette(for: effectiveResolvedAppearance)
        let accent = Color(themeColor: palette.accentGraphic)
        let secondary = Color(themeColor: palette.secondaryAccentGraphic)
        let accentText = Color(themeColor: palette.accentText)
        let tint = Color(themeColor: theme.surfaceTint)
        let textColor = captionTextColor
        let mutedTextColor = captionTextColor

        ZStack {
            if let mode = phase.mode, mode != .none {
                if mode == .magicPoof {
                    MagicPoofEffect(accent: accent, secondary: secondary, isActive: commitStarted)
                } else {
                    CommitTrail(mode: mode, accent: accent, secondary: secondary, isActive: commitStarted)
                }
            }

            VStack(spacing: 7) {
                if let translationStatus {
                    Text(translationStatus)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(accentText.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(accent.opacity(0.24), lineWidth: 1)
                        }
                        .shadow(color: captionTextShadowColor.opacity(0.42), radius: 6, x: 0, y: 2)
                        .opacity(commitStarted ? 0 : (bloomReady ? 1 : 0))
                }

                Text(text.isEmpty ? "Listening..." : text)
                    .font(.system(size: 14, weight: .medium, design: theme.look.bodyFontDesign))
                    .foregroundStyle(textColor)
                    .shadow(color: captionTextShadowColor.opacity(0.95), radius: 6, x: 0, y: 1)
                    .shadow(color: captionTextShadowColor.opacity(0.70), radius: 14, x: 0, y: 2)
                    .lineLimit(CaptionOverlayLayout.captionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 148, maxWidth: CaptionOverlayLayout.captionWidth)
                    .fixedSize(horizontal: text.count < 48, vertical: false)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .captionSurface(
                        theme: theme,
                        accent: accent,
                        secondary: secondary,
                        tint: tint,
                        glassOpacity: glassOpacity,
                        colorScheme: effectiveColorScheme
                    )
                    .overlay {
                        // Swifty stroke-draw outline that sketches the Listening box onto the screen.
                        if drawGlowOpacity > 0.001 {
                            let drawShape = Capsule(style: .continuous)
                            drawShape
                                .trim(from: 0, to: drawProgress)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            accent.opacity(0.95),
                                            Color.white.opacity(0.95),
                                            secondary.opacity(0.90),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                                )
                                .shadow(color: accent.opacity(0.75), radius: 8)
                                .opacity(drawGlowOpacity)
                        }
                    }
                    .scaleEffect(
                        x: bloomReady ? captionScale.width : 0.90,
                        y: bloomReady ? captionScale.height : 0.86
                    )
                    .opacity(bloomReady ? captionOpacity : 0.08)
                    .blur(radius: commitStarted ? captionBlurRadius : (bloomReady ? 0 : 4))
                    .offset(y: commitStarted ? captionYOffset : (bloomReady ? 0 : 6))

                WaveformPreview(
                    mode: theme.waveformMode,
                    level: level,
                    accent: accent,
                    secondary: secondary,
                    muted: mutedTextColor
                )
                .opacity(commitStarted ? 0 : (bloomReady ? 1 : 0))
                .scaleEffect(commitStarted ? 0.72 : (bloomReady ? 1 : 0.85))

                HStack(spacing: 5) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .opacity(commitStarted ? 0 : (bloomReady ? (level > 0.08 ? 1.0 : 0.65) : 0))
                        .scaleEffect(level > 0.15 ? 1.25 : 1.0)
                        .animation(.easeOut(duration: 0.14), value: level)

                    Text(styleName)
                        .font(.caption2.weight(.semibold))
                        .fontDesign(theme.look.bodyFontDesign)
                        .foregroundStyle(mutedTextColor.opacity(commitStarted ? 0 : (bloomReady ? theme.mutedTextOpacity : 0)))
                }
            }
        }
        .padding(.horizontal, CaptionOverlayLayout.haloBleedPaddingHorizontal)
        .padding(.vertical, CaptionOverlayLayout.haloBleedPaddingVertical)
        .frame(
            minWidth: CaptionOverlayLayout.windowMinWidth,
            maxWidth: CaptionOverlayLayout.windowMaxWidth
        )
        .onAppear {
            triggerAppearanceOrCommit()
        }
        .onChange(of: appearanceToken) { _, _ in
            if phase == .live {
                playDrawInAnimation()
            }
        }
        .onChange(of: phase) { _, newPhase in
            if case .committing(let mode) = newPhase, mode != .none {
                playCommitAnimation(mode: mode)
            } else {
                commitStarted = false
            }
        }
    }

    private func triggerAppearanceOrCommit() {
        if case .committing(let mode) = phase, mode != .none {
            bloomReady = true
            drawProgress = 1
            drawGlowOpacity = 0
            playCommitAnimation(mode: mode)
        } else {
            commitStarted = false
            playDrawInAnimation()
        }
    }

    private func playDrawInAnimation() {
        commitStarted = false
        guard !reduceMotion else {
            drawProgress = 1
            drawGlowOpacity = 0
            bloomReady = true
            return
        }
        drawProgress = 0.02
        drawGlowOpacity = 1
        bloomReady = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.38)) {
                drawProgress = 1
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                bloomReady = true
            }
            withAnimation(.easeOut(duration: 0.48).delay(0.22)) {
                drawGlowOpacity = 0
            }
        }
    }

    private func playCommitAnimation(mode: CommitAnimationMode) {
        commitStarted = false
        DispatchQueue.main.async {
            let curve: Animation = mode == .magicPoof
                ? .timingCurve(0.16, 1.0, 0.3, 1.0, duration: phase.duration)
                : .easeInOut(duration: phase.duration)
            withAnimation(curve) {
                commitStarted = true
            }
        }
    }

    private var captionScale: CGSize {
        guard commitStarted, let mode = phase.mode else {
            return CGSize(width: 1, height: 1)
        }

        switch mode {
        case .magicPoof:
            return CGSize(width: 1.12, height: 1.14)
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
        case .magicPoof:
            return 0.0
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
        case .magicPoof:
            return 14
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
        case .magicPoof:
            return -10
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

    private var effectiveColorScheme: ColorScheme {
        if let scheme = appearanceMode.colorScheme {
            return scheme
        }
        // .system: the @Environment(\.colorScheme) is unreliable inside this detached,
        // borderless floating panel (it can report dark under a light system), which made
        // the caption text resolve to the dark-mode white color on the light glass. Resolve
        // from the actual app/system appearance instead.
        return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    private var effectiveResolvedAppearance: ThemeResolvedAppearance {
        effectiveColorScheme == .dark ? .dark : .light
    }

    private var captionTextColor: Color {
        Color(themeColor: theme.resolvedPalette(for: effectiveResolvedAppearance).captionText).opacity(0.94)
    }

    private var captionTextShadowColor: Color {
        switch effectiveColorScheme {
        case .dark:
            Color.black.opacity(0.45)
        case .light:
            Color.white.opacity(0.62)
        @unknown default:
            Color.black.opacity(0.34)
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
        case .magicPoof:
            0
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
        case .magicPoof:
            0
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
        case .magicPoof:
            return 0
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

private struct MagicPoofEffect: View {
    let accent: Color
    let secondary: Color
    let isActive: Bool

    private struct PoofParticle: Identifiable {
        let id: Int
        let angle: Double
        let radiusX: CGFloat
        let radiusY: CGFloat
        let size: CGFloat
        let isStar: Bool
        let useSecondary: Bool
        let upwardDrift: CGFloat
        let spinDegrees: Double
    }

    private static let particles: [PoofParticle] = (0..<18).map { index in
        let fraction = Double(index) / 18.0
        let angle = fraction * Double.pi * 2.0 + (index.isMultiple(of: 2) ? 0.12 : -0.08)
        let ringBoost: CGFloat = index.isMultiple(of: 3) ? 1.22 : (index.isMultiple(of: 2) ? 0.94 : 1.08)
        return PoofParticle(
            id: index,
            angle: angle,
            radiusX: 118 * ringBoost,
            radiusY: 46 * ringBoost,
            size: index.isMultiple(of: 2) ? 11 : 7,
            isStar: index.isMultiple(of: 2),
            useSecondary: index.isMultiple(of: 3),
            upwardDrift: CGFloat(10 + (index % 5) * 5),
            spinDegrees: index.isMultiple(of: 2) ? 95 : -75
        )
    }

    var body: some View {
        ZStack {
            // Ethereal expanding mist capsule
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.85), Color.white.opacity(0.9), secondary.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 1.0 : 3.5
                )
                .frame(width: 240, height: 52)
                .scaleEffect(isActive ? 1.38 : 0.92)
                .blur(radius: isActive ? 10 : 1.5)
                .opacity(isActive ? 0 : 0.85)

            // Secondary luminous puff halo
            Capsule(style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            accent.opacity(0.35),
                            secondary.opacity(0.18),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 120
                    )
                )
                .frame(width: 230, height: 64)
                .scaleEffect(isActive ? 1.55 : 0.78)
                .blur(radius: isActive ? 18 : 4)
                .opacity(isActive ? 0 : 0.78)

            // Stardust sparkles & mist orbs bursting outward
            ForEach(Self.particles) { particle in
                let dx = CGFloat(cos(particle.angle)) * particle.radiusX
                let dy = CGFloat(sin(particle.angle)) * particle.radiusY - particle.upwardDrift
                let color = particle.useSecondary ? secondary : (particle.id.isMultiple(of: 4) ? Color.white : accent)

                Group {
                    if particle.isStar {
                        MagicSparkleShape()
                            .fill(color)
                            .shadow(color: color.opacity(0.85), radius: 4)
                    } else {
                        Circle()
                            .fill(color)
                            .blur(radius: isActive ? 2.4 : 0.5)
                    }
                }
                .frame(width: particle.size, height: particle.size)
                .scaleEffect(isActive ? 0.15 : 1.15)
                .rotationEffect(.degrees(isActive ? particle.spinDegrees : 0))
                .offset(x: isActive ? dx : dx * 0.28, y: isActive ? dy : dy * 0.25)
                .opacity(isActive ? 0 : 0.95)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MagicSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        let innerX = rx * 0.28
        let innerY = ry * 0.28

        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - ry))
        path.addQuadCurve(to: CGPoint(x: cx + rx, y: cy), control: CGPoint(x: cx + innerX, y: cy - innerY))
        path.addQuadCurve(to: CGPoint(x: cx, y: cy + ry), control: CGPoint(x: cx + innerX, y: cy + innerY))
        path.addQuadCurve(to: CGPoint(x: cx - rx, y: cy), control: CGPoint(x: cx - innerX, y: cy + innerY))
        path.addQuadCurve(to: CGPoint(x: cx, y: cy - ry), control: CGPoint(x: cx - innerX, y: cy - innerY))
        path.closeSubpath()
        return path
    }
}

/// Ethereal, truly see-through floating mist surface with soft feathered edges.
/// Avoids macOS `.glassEffect` inside borderless detached `NSPanel`s (which falls back
/// to an opaque matte grey slab with hard edges).
private struct CaptionGlassSurface: ViewModifier {
    let accent: Color
    let secondary: Color
    let tint: Color
    let glassOpacity: Double
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        let clamped = min(max(glassOpacity, 0), 1)
        let isDark = colorScheme == .dark
        let mistBase = isDark ? Color.black : Color.white
        // At 0-10%: whisper-sheer feathered mist (nearly invisible, stars/windows show straight through).
        // Sliding up toward 100% smoothly deepens the soft translucent cloud while keeping edges fuzzy.
        let coreOpacity = 0.05 + clamped * 0.48
        let haloOpacity = 0.12 + clamped * 0.18
        let sheenOpacity = 0.04 + clamped * 0.12

        content
            .background {
                ZStack {
                    // Wide, softly feathered outer glow (accent -> secondary)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(haloOpacity),
                                    secondary.opacity(haloOpacity * 0.78),
                                    accent.opacity(haloOpacity * 0.55),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.horizontal, -14)
                        .padding(.vertical, -8)
                        .blur(radius: 22)

                    // Soft feathered readability cloud behind the text (fuzzy edges, zero hard border)
                    Capsule(style: .continuous)
                        .fill(mistBase.opacity(coreOpacity))
                        .padding(.horizontal, -4)
                        .padding(.vertical, -2)
                        .blur(radius: 14 - CGFloat(clamped * 4))

                    // Delicate luminous glass shimmer inside the cloud
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(sheenOpacity),
                                    tint.opacity(clamped * 0.16),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blur(radius: 8)
                }
                .allowsHitTesting(false)
            }
    }
}

private extension View {
    func captionGlassSurface(
        accent: Color,
        secondary: Color,
        tint: Color,
        glassOpacity: Double,
        colorScheme: ColorScheme
    ) -> some View {
        modifier(
            CaptionGlassSurface(
                accent: accent,
                secondary: secondary,
                tint: tint,
                glassOpacity: glassOpacity,
                colorScheme: colorScheme
            )
        )
    }

    @ViewBuilder
    func captionSurface(
        theme: OmniVoiceTheme,
        accent: Color,
        secondary: Color,
        tint: Color,
        glassOpacity: Double,
        colorScheme: ColorScheme
    ) -> some View {
        if theme.look == .liquidGlass {
            captionGlassSurface(
                accent: accent,
                secondary: secondary,
                tint: tint,
                glassOpacity: glassOpacity,
                colorScheme: colorScheme
            )
        } else {
            themeSurface(theme, cornerRadius: theme.look.cardRadius(forRequested: 16), strong: true, interactive: false)
        }
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
            case .signalDots:
                signalDots
            case .mirrorBars:
                mirrorBars
            case .haloStack:
                haloStack
            case .prismSweep:
                prismSweep
            case .needleMeter:
                needleMeter
            case .ribbonWave:
                ribbonWave
            case .equalizerBlocks:
                equalizerBlocks
            case .orbitDots:
                orbitDots
            case .sparkline:
                sparkline
            case .constellation:
                constellation
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

    private var signalDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<12, id: \.self) { index in
                let threshold = Double(index + 1) / 12
                Circle()
                    .fill(index.isMultiple(of: 2) ? accent : secondary)
                    .opacity(normalizedLevel >= threshold ? 0.88 : 0.16)
                    .frame(width: CGFloat(4 + (index % 3)), height: CGFloat(4 + (index % 3)))
            }
        }
    }

    private var mirrorBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<13, id: \.self) { index in
                let distance = abs(index - 6)
                let threshold = 1.0 - (Double(distance) / 7.0)
                Capsule()
                    .fill(normalizedLevel >= threshold ? accent.opacity(0.86) : muted.opacity(0.16))
                    .frame(width: 4, height: CGFloat(8 + (6 - distance) * 3))
            }
        }
    }

    private var haloStack: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(index.isMultiple(of: 2) ? accent : secondary, lineWidth: 1.4)
                    .opacity(0.14 + normalizedLevel * Double(4 - index) * 0.12)
                    .frame(width: CGFloat(48 + index * 22), height: CGFloat(8 + index * 4))
            }
        }
    }

    private var prismSweep: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(muted.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [secondary.opacity(0.38), accent.opacity(0.92), secondary.opacity(0.66)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * normalizedLevel))
            }
        }
        .frame(height: 7)
        .padding(.horizontal, 16)
    }

    private var needleMeter: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height + 2)
            let length = min(proxy.size.width, proxy.size.height * 3) * 0.42
            let angle = Angle.degrees(-58 + normalizedLevel * 116)

            ZStack {
                Capsule()
                    .fill(muted.opacity(0.14))
                    .frame(width: proxy.size.width * 0.56, height: 5)
                    .position(x: proxy.size.width / 2, y: proxy.size.height - 4)

                Path { path in
                    path.move(to: center)
                    path.addLine(
                        to: CGPoint(
                            x: center.x + cos(angle.radians) * length,
                            y: center.y + sin(angle.radians) * length
                        )
                    )
                }
                .stroke(accent.opacity(0.88), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                Circle()
                    .fill(secondary.opacity(0.82))
                    .frame(width: 6, height: 6)
                    .position(center)
            }
        }
        .padding(.horizontal, 24)
    }

    private var ribbonWave: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                let midY = height / 2
                let amplitude = CGFloat(2 + normalizedLevel * 8)

                path.move(to: CGPoint(x: 0, y: midY))
                for index in 0...24 {
                    let progress = CGFloat(index) / 24
                    let wave = sin(progress * .pi * 4)
                    path.addLine(to: CGPoint(x: width * progress, y: midY - wave * amplitude))
                }
            }
            .stroke(
                LinearGradient(colors: [accent.opacity(0.35), secondary.opacity(0.9)], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
            .blur(radius: 0.25)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private var equalizerBlocks: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { column in
                VStack(spacing: 2) {
                    ForEach((0..<4).reversed(), id: \.self) { row in
                        let threshold = Double(row + column % 3) / 6.0
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(normalizedLevel >= threshold ? accent.opacity(0.84) : muted.opacity(0.14))
                            .frame(width: 8, height: 4)
                    }
                }
            }
        }
    }

    private var orbitDots: some View {
        ZStack {
            Circle()
                .stroke(muted.opacity(0.18), lineWidth: 1)
                .frame(width: 58, height: 22)

            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) / 6 * Double.pi * 2 + normalizedLevel * Double.pi
                Circle()
                    .fill(index.isMultiple(of: 2) ? accent.opacity(0.88) : secondary.opacity(0.78))
                    .frame(width: 5 + normalizedLevel * 3, height: 5 + normalizedLevel * 3)
                    .offset(x: cos(angle) * 29, y: sin(angle) * 10)
            }
        }
    }

    private var sparkline: some View {
        GeometryReader { proxy in
            Path { path in
                let points = sparklinePoints(in: proxy.size)
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(accent.opacity(0.88), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var constellation: some View {
        GeometryReader { proxy in
            let points = constellationPoints(in: proxy.size)

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(secondary.opacity(0.34 + normalizedLevel * 0.32), lineWidth: 1)

                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(index < activeConstellationPoints ? accent.opacity(0.88) : muted.opacity(0.20))
                        .frame(width: 4, height: 4)
                        .position(points[index])
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 3)
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

    private var activeConstellationPoints: Int {
        Int((normalizedLevel * 6).rounded(.up))
    }

    private func sparklinePoints(in size: CGSize) -> [CGPoint] {
        (0..<9).map { index in
            let progress = CGFloat(index) / 8
            let base = sin((progress * .pi * 2.5) + CGFloat(normalizedLevel * 1.4))
            return CGPoint(
                x: size.width * progress,
                y: size.height / 2 - base * CGFloat(3 + normalizedLevel * 7)
            )
        }
    }

    private func constellationPoints(in size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: size.width * 0.08, y: size.height * 0.66),
            CGPoint(x: size.width * 0.26, y: size.height * 0.28),
            CGPoint(x: size.width * 0.43, y: size.height * 0.52),
            CGPoint(x: size.width * 0.61, y: size.height * 0.22),
            CGPoint(x: size.width * 0.78, y: size.height * 0.58),
            CGPoint(x: size.width * 0.92, y: size.height * 0.34),
        ]
    }
}
