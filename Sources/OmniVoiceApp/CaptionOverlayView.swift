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

                // Unified smoked-glass capsule stage housing the live caption, sleek 60fps
                // waveform visualizer, and style pill so the waveform pops crisply over any window.
                VStack(spacing: 7) {
                    Text(text.isEmpty ? "Listening..." : text)
                        .font(.system(size: 14, weight: .medium, design: theme.look.bodyFontDesign))
                        .foregroundStyle(textColor)
                        .shadow(color: captionTextShadowColor.opacity(0.95), radius: 6, x: 0, y: 1)
                        .shadow(color: captionTextShadowColor.opacity(0.70), radius: 14, x: 0, y: 2)
                        .lineLimit(CaptionOverlayLayout.captionLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 196, maxWidth: CaptionOverlayLayout.captionWidth)
                        .fixedSize(horizontal: text.count < 48, vertical: false)

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
                            .foregroundStyle(mutedTextColor.opacity(commitStarted ? 0 : (bloomReady ? max(0.78, theme.mutedTextOpacity) : 0)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 13)
                .padding(.bottom, 10)
                .captionSurface(
                    theme: theme,
                    accent: accent,
                    secondary: secondary,
                    tint: tint,
                    glassOpacity: glassOpacity,
                    colorScheme: effectiveColorScheme
                )
                .overlay {
                    // Swifty stroke-draw outline that sketches the Listening card onto the screen.
                    if drawGlowOpacity > 0.001 {
                        let drawShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
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
        Color.white.opacity(0.96)
    }

    private var captionTextShadowColor: Color {
        Color.black.opacity(0.62)
    }
}

private struct CommitTrail: View {
    let mode: CommitAnimationMode
    let accent: Color
    let secondary: Color
    let isActive: Bool

    var body: some View {
        ZStack {
            if mode == .cometCollapse {
                // Sleek luminous Comet Trail: tapering glowing plasma tail sweeping into a bright starburst head.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                secondary.opacity(0),
                                secondary.opacity(0.35),
                                accent.opacity(0.85),
                                Color.white.opacity(0.95),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: isActive ? 190 : 14, height: isActive ? 3.5 : 8)
                    .blur(radius: isActive ? 2.5 : 1)
                    .shadow(color: accent.opacity(isActive ? 0.85 : 0.2), radius: 14)
                    .offset(x: isActive ? 44 : -48, y: isActive ? 22 : 0)
                    .opacity(isActive ? 0 : 0.95)

                // Bright comet core flash + trailing sparks
                ForEach(0..<6, id: \.self) { idx in
                    let lag = CGFloat(idx)
                    let diameter: CGFloat = max(2.5, 9.0 - lag * 1.1)
                    let sparkColor: Color = idx == 0 ? Color.white : (idx.isMultiple(of: 2) ? accent : secondary)
                    let startX: CGFloat = isActive ? 92.0 : -42.0
                    let spacingX: CGFloat = isActive ? 24.0 : 5.0
                    let offsetX: CGFloat = startX - lag * spacingX
                    let offsetY: CGFloat = (isActive ? 22.0 : 0.0) + CGFloat(sin(Double(idx) * 1.3) * 4.0)
                    let alpha: Double = isActive ? 0.0 : (1.0 - Double(idx) * 0.13)
                    Circle()
                        .fill(sparkColor)
                        .frame(width: diameter, height: diameter)
                        .blur(radius: lag * 0.45)
                        .shadow(color: accent.opacity(0.85), radius: idx == 0 ? 10 : 4)
                        .offset(x: offsetX, y: offsetY)
                        .opacity(alpha)
                }
            } else {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [secondary.opacity(0), accent.opacity(0.90), Color.white.opacity(0.85), secondary.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: isActive ? trailWidth : 0, height: trailHeight)
                    .shadow(color: accent.opacity(isActive ? 0.72 : 0), radius: 16)
                    .offset(y: isActive ? 18 : 0)
                    .opacity(isActive ? 0 : 0.92)

                if mode == .glyphStream {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { idx in
                            Capsule(style: .continuous)
                                .fill(idx.isMultiple(of: 2) ? accent : secondary)
                                .frame(width: idx == 3 ? 14 : 6, height: 2.5)
                                .shadow(color: accent.opacity(0.6), radius: 4)
                                .offset(x: isActive ? CGFloat(idx - 3) * 14 : 0, y: isActive ? 18 : 0)
                                .opacity(isActive ? 0 : 0.85)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var trailWidth: CGFloat {
        switch mode {
        case .magicPoof, .none: 0
        case .glyphStream: 210
        case .beamSnap: 170
        case .cometCollapse: 190
        }
    }

    private var trailHeight: CGFloat {
        switch mode {
        case .magicPoof, .none: 0
        case .glyphStream: 3.5
        case .beamSnap: 5
        case .cometCollapse: 4
        }
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

/// Sleek smoked-glass floating HUD stage with a crisp, subtle frosted edge whose
/// outer fade drops off quickly, responding continuously across the full 0%–100%
/// Listening HUD Glass Opacity slider on every theme.
private struct CaptionGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let accent: Color
    let secondary: Color
    let tint: Color
    let glassOpacity: Double
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        let clamped = min(max(glassOpacity, 0), 1)
        // Full dramatic range from 0% (Crystal Clear light smoked mist) to 100% (Deep Frosted glass).
        let materialOpacity = 0.10 + clamped * 0.86
        let darkCoreOpacity = 0.16 + clamped * 0.72
        let edgeFrostOpacity = 0.28 + clamped * 0.44
        let specularOpacity = 0.07 + clamped * 0.13
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    // Tight, fast-falloff frosted outer rim (fades out within ~4pt so the edge feels
                    // crisp and frosted without a wide foggy halo).
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(edgeFrostOpacity * 0.85),
                                    accent.opacity(edgeFrostOpacity * 0.65),
                                    secondary.opacity(edgeFrostOpacity * 0.50),
                                    Color.white.opacity(edgeFrostOpacity * 0.35),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.2
                        )
                        .blur(radius: 2.8)

                    // Real macOS frosted glass blur layer driven directly by HUD Glass Opacity
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(materialOpacity)

                    // Smoked dark stage tint so glowing 60fps waveforms pop cleanly over any window
                    shape
                        .fill(Color.black.opacity(darkCoreOpacity))

                    // Subtle top specular sheen & theme tint
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(specularOpacity),
                                    tint.opacity(0.06 + clamped * 0.14),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Crisp 1pt inner frosted glass bevel edge
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38 + clamped * 0.20),
                                    accent.opacity(0.28 + clamped * 0.16),
                                    secondary.opacity(0.18 + clamped * 0.14),
                                    Color.white.opacity(0.12 + clamped * 0.12),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }
                .shadow(color: Color.black.opacity(0.16 + clamped * 0.30), radius: 6, x: 0, y: 2)
                .allowsHitTesting(false)
            }
    }
}

private extension View {
    func captionGlassSurface(
        cornerRadius: CGFloat,
        accent: Color,
        secondary: Color,
        tint: Color,
        glassOpacity: Double,
        colorScheme: ColorScheme
    ) -> some View {
        modifier(
            CaptionGlassSurface(
                cornerRadius: cornerRadius,
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
        let radius: CGFloat = theme.look == .liquidGlass
            ? 24
            : theme.look.cardRadius(forRequested: 18)
        captionGlassSurface(
            cornerRadius: radius,
            accent: accent,
            secondary: secondary,
            tint: tint,
            glassOpacity: glassOpacity,
            colorScheme: colorScheme
        )
    }
}

/// Studio-grade, 60fps Canvas-rendered voice waveform visualizer with smooth exponential
/// attack/decay physics, luminous Liquid Glass gradients, and organic harmonic motion.
private struct WaveformPreview: View {
    let mode: WaveformMode
    let level: Float
    let accent: Color
    let secondary: Color
    let muted: Color

    @State private var smoothedLevel: Double = 0.06
    @State private var peakHold: Double = 0.06
    @State private var history: [Double] = Array(repeating: 0.05, count: 28)

    private var targetLevel: Double {
        // Perceptual curve: lifts quiet speech gently while keeping loud peaks lush and controlled.
        let raw = min(max(Double(level) * 34.0, 0), 1)
        return pow(raw, 0.72)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let energy = max(0.05, smoothedLevel)

            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { ctx, size in
                drawWaveform(in: &ctx, size: size, time: t, energy: energy, peak: peakHold)
            }
            .onChange(of: timeline.date) { _, _ in
                let target = targetLevel
                // Crisp attack, velvety decay
                let alpha = target > smoothedLevel ? 0.42 : 0.16
                smoothedLevel += (target - smoothedLevel) * alpha
                if smoothedLevel > peakHold {
                    peakHold = smoothedLevel
                } else {
                    peakHold = max(smoothedLevel, peakHold - 0.012)
                }
                if mode == .sparkline {
                    history.removeFirst()
                    history.append(smoothedLevel)
                }
            }
        }
        .frame(width: 196, height: 32)
    }

    private func drawWaveform(
        in ctx: inout GraphicsContext,
        size: CGSize,
        time t: Double,
        energy: Double,
        peak: Double
    ) {
        switch mode {
        case .bars:
            drawLiquidBars(&ctx, size: size, t: t, energy: energy)
        case .mirrorBars:
            drawMirrorStudioEQ(&ctx, size: size, t: t, energy: energy, peak: peak)
        case .ribbonWave:
            drawSilkRibbons(&ctx, size: size, t: t, energy: energy)
        case .spectrumLine:
            drawOscilloscopeLine(&ctx, size: size, t: t, energy: energy)
        case .pulseRing:
            drawSonarRipples(&ctx, size: size, t: t, energy: energy)
        case .orbMeter:
            drawPlasmaOrbs(&ctx, size: size, t: t, energy: energy)
        case .prismSweep:
            drawAuroraCometBar(&ctx, size: size, t: t, energy: energy, peak: peak)
        case .equalizerBlocks:
            drawStudioLEDMatrix(&ctx, size: size, t: t, energy: energy)
        case .signalDots:
            drawHarmonicPearls(&ctx, size: size, t: t, energy: energy)
        case .haloStack:
            drawGlassHalos(&ctx, size: size, t: t, energy: energy)
        case .needleMeter:
            drawPrecisionVU(&ctx, size: size, t: t, energy: energy, peak: peak)
        case .orbitDots:
            drawOrbitalComets(&ctx, size: size, t: t, energy: energy)
        case .sparkline:
            drawEnergySparkline(&ctx, size: size, t: t, energy: energy)
        case .constellation:
            drawNeuralConstellation(&ctx, size: size, t: t, energy: energy)
        case .glyphStream:
            drawCadenceLightStrip(&ctx, size: size, t: t, energy: energy)
        }
    }

    // 1. Liquid Spectrum Bars: 21 fine center-weighted translucent pill bars with specular tips
    private func drawLiquidBars(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let count = 21
        let barW: CGFloat = 2.8
        let gap = (size.width - 24 - CGFloat(count) * barW) / CGFloat(count - 1)
        let startX: CGFloat = 12
        let midY = size.height / 2

        let grad = Gradient(colors: [secondary.opacity(0.65), accent, Color.white.opacity(0.95), accent, secondary.opacity(0.65)])
        for i in 0..<count {
            let norm = Double(i) / Double(count - 1)
            let bell = sin(norm * .pi) // smooth 0 -> 1 -> 0 envelope
            let harmonic = 0.52
                + 0.28 * sin(t * 5.4 + Double(i) * 0.62)
                + 0.20 * cos(t * 8.9 - Double(i) * 1.15)
            let h = max(3.2, CGFloat(3.5 + (size.height - 8) * energy * pow(bell, 0.85) * max(0.22, harmonic)))
            let x = startX + CGFloat(i) * (barW + gap)
            let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
            let pill = Path(roundedRect: rect, cornerRadius: barW / 2)

            var glowCtx = ctx
            glowCtx.addFilter(.shadow(color: accent.opacity(0.45 * bell * energy), radius: 5))
            glowCtx.fill(
                pill,
                with: .linearGradient(grad, startPoint: CGPoint(x: x, y: rect.minY), endPoint: CGPoint(x: x, y: rect.maxY))
            )
        }
    }

    // 2. Symmetric Studio EQ with hairline horizon & jewel peak caps
    private func drawMirrorStudioEQ(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double, peak: Double) {
        let midY = size.height / 2
        // Subtle hairline horizon
        var horizon = Path()
        horizon.move(to: CGPoint(x: 14, y: midY))
        horizon.addLine(to: CGPoint(x: size.width - 14, y: midY))
        ctx.stroke(horizon, with: .color(muted.opacity(0.16)), lineWidth: 0.75)

        let count = 23
        let barW: CGFloat = 2.4
        let span = size.width - 28
        let step = span / CGFloat(count - 1)
        let centerIdx = Double(count - 1) / 2.0

        for i in 0..<count {
            let dist = abs(Double(i) - centerIdx) / centerIdx
            let bell = pow(max(0, 1.0 - dist * dist), 1.15)
            let ripple = 0.55 + 0.30 * sin(t * 6.5 - dist * 5.2) + 0.15 * cos(t * 10.2 + Double(i) * 0.8)
            let halfH = max(1.6, CGFloat((size.height * 0.44) * energy * bell * max(0.2, ripple)))
            let x = 14 + CGFloat(i) * step - barW / 2
            let rect = CGRect(x: x, y: midY - halfH, width: barW, height: halfH * 2)
            let pill = Path(roundedRect: rect, cornerRadius: barW / 2)

            let color = dist < 0.35 ? accent : secondary
            ctx.fill(
                pill,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.88), Color.white.opacity(0.92), color.opacity(0.88)]),
                    startPoint: CGPoint(x: x, y: rect.minY),
                    endPoint: CGPoint(x: x, y: rect.maxY)
                )
            )

            // Peak jewel dot above center bars
            if energy > 0.15 && dist < 0.72 {
                let peakOffset = max(halfH + 2.5, CGFloat((size.height * 0.45) * peak * bell))
                let dot = Path(ellipseIn: CGRect(x: x, y: midY - peakOffset - 1.2, width: barW, height: barW))
                ctx.fill(dot, with: .color(Color.white.opacity(0.70 * bell)))
            }
        }
    }

    // 3. Siri / Apple Intelligence Layered Silk Ribbons (feathered Gaussian edges!)
    private func drawSilkRibbons(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let midY = size.height / 2
        let layers: [(freq: Double, speed: Double, phase: Double, amp: Double, color: Color, width: CGFloat, blur: CGFloat)] = [
            (2.2, 3.8, 0.0, 0.95, secondary.opacity(0.55), 3.4, 3.5),
            (3.1, -4.6, 1.4, 0.80, accent.opacity(0.85), 2.4, 1.8),
            (4.3, 6.0, 2.7, 0.58, Color.white.opacity(0.90), 1.4, 0.4),
        ]
        let steps = 56
        for layer in layers {
            var path = Path()
            for s in 0...steps {
                let u = Double(s) / Double(steps)
                let x = CGFloat(u) * size.width
                // Smooth Hanning window so ends kiss the centerline cleanly
                let window = pow(sin(u * .pi), 1.7)
                let wave = sin(u * .pi * 2.0 * layer.freq + t * layer.speed + layer.phase)
                let y = midY + CGFloat(wave * window * layer.amp * energy * Double(size.height * 0.43))
                if s == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            var layerCtx = ctx
            if layer.blur > 0.5 {
                layerCtx.addFilter(.shadow(color: layer.color, radius: layer.blur))
            }
            layerCtx.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [layer.color.opacity(0), layer.color, layer.color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: size.width, y: midY)
                ),
                style: StrokeStyle(lineWidth: layer.width, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // 4. Crisp Glowing Oscilloscope Spectrum Line
    private func drawOscilloscopeLine(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let midY = size.height / 2
        let steps = 64
        var path = Path()
        for s in 0...steps {
            let u = Double(s) / Double(steps)
            let x = 8 + CGFloat(u) * (size.width - 16)
            let env = pow(sin(u * .pi), 1.4)
            let yVal = (sin(u * 14.0 + t * 6.4) * 0.58 + sin(u * 27.0 - t * 9.8) * 0.42)
            let y = midY - CGFloat(yVal * env * energy * Double(size.height * 0.42))
            if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }

        // Soft phosphor bloom pass
        var glow = ctx
        glow.addFilter(.shadow(color: accent.opacity(0.75), radius: 6))
        glow.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [secondary.opacity(0.25), accent, Color.white.opacity(0.95), secondary.opacity(0.25)]),
                startPoint: CGPoint(x: 8, y: midY),
                endPoint: CGPoint(x: size.width - 8, y: midY)
            ),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )
    }

    // 5. Sonar Pulse Ripples
    private func drawSonarRipples(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for ring in 0..<3 {
            let phase = (t * 0.85 + Double(ring) / 3.0).truncatingRemainder(dividingBy: 1.0)
            let radius = CGFloat(4.5 + phase * (12.0 + energy * 18.0))
            let alpha = (1.0 - phase) * (0.28 + energy * 0.65)
            let ellipse = Path(ellipseIn: CGRect(x: center.x - radius * 2.2, y: center.y - radius * 0.68, width: radius * 4.4, height: radius * 1.36))
            ctx.stroke(ellipse, with: .color((ring.isMultiple(of: 2) ? accent : secondary).opacity(alpha)), lineWidth: 1.4)
        }
        // Luminous center core orb
        let coreR = CGFloat(3.5 + energy * 4.5)
        var coreCtx = ctx
        coreCtx.addFilter(.shadow(color: accent.opacity(0.85), radius: 7))
        coreCtx.fill(
            Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)),
            with: .radialGradient(
                Gradient(colors: [Color.white, accent, secondary.opacity(0.2)]),
                center: center,
                startRadius: 0.5,
                endRadius: coreR
            )
        )
    }

    // 6. Floating Plasma Energy Orbs
    private func drawPlasmaOrbs(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let count = 7
        let span = size.width - 56
        for i in 0..<count {
            let norm = Double(i) / Double(count - 1)
            let bell = sin(norm * .pi) * 0.7 + 0.3
            let bob = sin(t * 4.4 + Double(i) * 0.95) * (2.0 + energy * 5.0)
            let r = CGFloat(2.8 + (2.5 + energy * 4.8) * bell * (0.75 + 0.25 * cos(t * 5.2 - Double(i))))
            let cx = 28 + CGFloat(norm) * span
            let cy = size.height / 2 + CGFloat(bob)
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            let color = i.isMultiple(of: 2) ? accent : secondary

            var glow = ctx
            glow.addFilter(.shadow(color: color.opacity(0.65 * energy), radius: 6))
            glow.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.95), color.opacity(0.88), color.opacity(0.10)]),
                    center: CGPoint(x: cx - r * 0.2, y: cy - r * 0.2),
                    startRadius: 0.4,
                    endRadius: r
                )
            )
        }
    }

    // 7. Aurora Comet Sweep Bar (glass channel + glowing comet plasma head)
    private func drawAuroraCometBar(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double, peak: Double) {
        let midY = size.height / 2
        let trackRect = CGRect(x: 16, y: midY - 2.2, width: size.width - 32, height: 4.4)
        ctx.fill(Path(roundedRect: trackRect, cornerRadius: 2.2), with: .color(muted.opacity(0.14)))

        let fillW = max(14, trackRect.width * CGFloat(min(1, 0.14 + energy * 0.86)))
        let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: fillW, height: trackRect.height)
        var glow = ctx
        glow.addFilter(.shadow(color: accent.opacity(0.75), radius: 7))
        glow.fill(
            Path(roundedRect: fillRect, cornerRadius: 2.2),
            with: .linearGradient(
                Gradient(colors: [secondary.opacity(0.25), accent.opacity(0.92), Color.white]),
                startPoint: CGPoint(x: fillRect.minX, y: midY),
                endPoint: CGPoint(x: fillRect.maxX, y: midY)
            )
        )

        // Glowing comet head sparkle + peak tick
        let head = CGRect(x: fillRect.maxX - 3.5, y: midY - 3.5, width: 7, height: 7)
        glow.fill(Path(ellipseIn: head), with: .color(Color.white.opacity(0.95)))

        let peakX = trackRect.minX + trackRect.width * CGFloat(min(1, 0.14 + peak * 0.86))
        ctx.fill(Path(roundedRect: CGRect(x: peakX - 1, y: midY - 4.5, width: 2, height: 9), cornerRadius: 1), with: .color(accent.opacity(0.55)))
    }

    // 8. Precision Studio Micro-LED Matrix
    private func drawStudioLEDMatrix(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let cols = 15
        let rows = 5
        let cellW: CGFloat = 6.5
        let cellH: CGFloat = 3.2
        let colGap: CGFloat = 4.0
        let rowGap: CGFloat = 2.4
        let totalW = CGFloat(cols) * cellW + CGFloat(cols - 1) * colGap
        let totalH = CGFloat(rows) * cellH + CGFloat(rows - 1) * rowGap
        let originX = (size.width - totalW) / 2
        let originY = (size.height - totalH) / 2

        for col in 0..<cols {
            let norm = Double(col) / Double(cols - 1)
            let bell = pow(sin(norm * .pi), 0.75)
            let wave = 0.55 + 0.45 * sin(t * 6.8 + Double(col) * 0.72)
            let levelRows = Double(rows) * energy * bell * wave
            for row in 0..<rows {
                let fromBottom = rows - 1 - row
                let lit = Double(fromBottom) < levelRows
                let x = originX + CGFloat(col) * (cellW + colGap)
                let y = originY + CGFloat(row) * (cellH + rowGap)
                let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
                let fill: Color
                if lit {
                    fill = fromBottom == rows - 1 ? Color.white.opacity(0.95) : (fromBottom >= rows - 2 ? accent : secondary.opacity(0.88))
                } else {
                    fill = muted.opacity(0.11)
                }
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.4), with: .color(fill))
            }
        }
    }

    // 9. Harmonic Wave Pearls (19 glowing floating micro-dots)
    private func drawHarmonicPearls(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let count = 19
        let span = size.width - 28
        let midY = size.height / 2
        for i in 0..<count {
            let u = Double(i) / Double(count - 1)
            let env = sin(u * .pi)
            let yOff = sin(u * 9.5 - t * 6.0) * env * (2.5 + energy * 10.5)
            let r = CGFloat(1.6 + env * (1.2 + energy * 2.2))
            let x = 14 + CGFloat(u) * span
            let y = midY + CGFloat(yOff)
            let color = i.isMultiple(of: 2) ? accent : secondary
            var dotCtx = ctx
            dotCtx.addFilter(.shadow(color: color.opacity(0.55 * env), radius: 3.5))
            dotCtx.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(color.opacity(0.35 + 0.65 * env * (0.4 + energy * 0.6)))
            )
        }
    }

    // 10. Layered Liquid Glass Halos
    private func drawGlassHalos(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for i in 0..<4 {
            let breathe = 1.0 + 0.08 * sin(t * 3.8 + Double(i) * 0.9)
            let w = CGFloat((46 + Double(i) * 30) * (0.88 + energy * 0.28) * breathe)
            let h = CGFloat((7 + Double(i) * 5.2) * (0.85 + energy * 0.35))
            let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            let color = i.isMultiple(of: 2) ? accent : secondary
            let alpha = max(0.10, (0.55 - Double(i) * 0.11) * (0.45 + energy * 0.65))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(color.opacity(alpha)), lineWidth: 1.35)
        }
    }

    // 11. Precision Minimalist Analog VU Meter
    private func drawPrecisionVU(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double, peak: Double) {
        let cx = size.width / 2
        let cy = size.height + 16
        let radius: CGFloat = 38
        // Fine brushed arc ticks
        for tick in 0...10 {
            let frac = Double(tick) / 10.0
            let deg = -142.0 + frac * 104.0
            let rad = deg * .pi / 180.0
            let innerR = radius - (tick.isMultiple(of: 5) ? 5.5 : 3.2)
            var p = Path()
            p.move(to: CGPoint(x: cx + cos(rad) * innerR, y: cy + sin(rad) * innerR))
            p.addLine(to: CGPoint(x: cx + cos(rad) * radius, y: cy + sin(rad) * radius))
            let tickColor = frac > 0.78 ? Color.orange.opacity(0.8) : muted.opacity(0.32)
            ctx.stroke(p, with: .color(tickColor), lineWidth: tick.isMultiple(of: 5) ? 1.4 : 0.9)
        }
        // Damped needle with subtle organic tremor
        let jitter = sin(t * 14.0) * 0.015 * energy
        let needleDeg = -138.0 + min(1, max(0, energy + jitter)) * 96.0
        let rad = needleDeg * .pi / 180.0
        var needle = Path()
        needle.move(to: CGPoint(x: cx, y: cy))
        needle.addLine(to: CGPoint(x: cx + cos(rad) * (radius + 2), y: cy + sin(rad) * (radius + 2)))
        var needleCtx = ctx
        needleCtx.addFilter(.shadow(color: accent.opacity(0.75), radius: 5))
        needleCtx.stroke(needle, with: .color(accent), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.5, y: size.height - 4.5, width: 7, height: 7)), with: .color(Color.white.opacity(0.85)))
    }

    // 12. Orbital Comets (twin tilted 3D orbits with luminous comet trails!)
    private func drawOrbitalComets(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let rx: CGFloat = 58
        let ry: CGFloat = 10.5
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)), with: .color(muted.opacity(0.14)), lineWidth: 0.8)

        let speed = 2.6 + energy * 3.8
        for comet in 0..<3 {
            let baseAngle = t * speed + Double(comet) * (Double.pi * 2.0 / 3.0)
            let color = comet == 0 ? Color.white : (comet == 1 ? accent : secondary)
            // Draw tapering comet tail
            for tail in (0..<8).reversed() {
                let a = baseAngle - Double(tail) * 0.14
                let x = cx + CGFloat(cos(a)) * rx
                let y = cy + CGFloat(sin(a)) * ry
                let depth = (sin(a) + 1.0) * 0.5
                let r = CGFloat((3.2 - Double(tail) * 0.34) * (0.75 + depth * 0.45) * (0.85 + energy * 0.45))
                let alpha = (1.0 - Double(tail) / 8.5) * (0.45 + 0.55 * depth)
                if r > 0.4 {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(color.opacity(alpha))
                    )
                }
            }
        }
    }

    // 13. Live Scrolling Energy Sparkline with translucent area wash + live dot
    private func drawEnergySparkline(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        guard history.count >= 2 else { return }
        let left: CGFloat = 12
        let right: CGFloat = size.width - 12
        let baseY: CGFloat = size.height - 4
        let usableH: CGFloat = size.height - 9
        let stepX = (right - left) / CGFloat(history.count - 1)

        var line = Path()
        var area = Path()
        var lastPoint = CGPoint(x: left, y: baseY)

        for (idx, val) in history.enumerated() {
            let x = left + CGFloat(idx) * stepX
            let waveLift = sin(t * 5.0 + Double(idx) * 0.4) * 0.04 * val
            let y = baseY - CGFloat(min(1, max(0.03, val + waveLift))) * usableH
            let pt = CGPoint(x: x, y: y)
            if idx == 0 {
                line.move(to: pt)
                area.move(to: CGPoint(x: x, y: baseY))
                area.addLine(to: pt)
            } else {
                let midX = (lastPoint.x + pt.x) / 2
                line.addCurve(to: pt, control1: CGPoint(x: midX, y: lastPoint.y), control2: CGPoint(x: midX, y: pt.y))
                area.addCurve(to: pt, control1: CGPoint(x: midX, y: lastPoint.y), control2: CGPoint(x: midX, y: pt.y))
            }
            lastPoint = pt
        }
        area.addLine(to: CGPoint(x: right, y: baseY))
        area.closeSubpath()

        ctx.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [accent.opacity(0.28), secondary.opacity(0.02)]),
                startPoint: CGPoint(x: size.width / 2, y: 4),
                endPoint: CGPoint(x: size.width / 2, y: baseY)
            )
        )
        var glow = ctx
        glow.addFilter(.shadow(color: accent.opacity(0.75), radius: 5))
        glow.stroke(
            line,
            with: .linearGradient(Gradient(colors: [secondary.opacity(0.5), accent, Color.white]), startPoint: CGPoint(x: left, y: baseY), endPoint: CGPoint(x: right, y: 4)),
            style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
        )
        glow.fill(Path(ellipseIn: CGRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6)), with: .color(Color.white))
    }

    // 14. Neural Constellation Starfield
    private func drawNeuralConstellation(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let anchors: [(Double, Double)] = [
            (0.10, 0.62), (0.24, 0.28), (0.39, 0.66), (0.52, 0.24),
            (0.67, 0.58), (0.80, 0.30), (0.91, 0.54),
        ]
        let pts: [CGPoint] = anchors.enumerated().map { idx, a in
            let dx = sin(t * 1.8 + Double(idx) * 1.3) * (2.0 + energy * 4.5)
            let dy = cos(t * 2.4 + Double(idx) * 1.7) * (1.8 + energy * 4.5)
            return CGPoint(x: size.width * a.0 + dx, y: size.height * a.1 + dy)
        }
        var net = Path()
        for i in 0..<(pts.count - 1) {
            net.move(to: pts[i])
            net.addLine(to: pts[i + 1])
            if i + 2 < pts.count {
                net.move(to: pts[i])
                net.addLine(to: pts[i + 2])
            }
        }
        ctx.stroke(net, with: .color(secondary.opacity(0.18 + energy * 0.42)), lineWidth: 0.9)

        for (idx, pt) in pts.enumerated() {
            let pulse = 0.65 + 0.35 * sin(t * 4.5 + Double(idx))
            let r = CGFloat(1.8 + (1.4 + energy * 2.2) * pulse)
            var starCtx = ctx
            starCtx.addFilter(.shadow(color: accent.opacity(0.8), radius: 4.5))
            starCtx.fill(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                with: .color(idx.isMultiple(of: 2) ? Color.white.opacity(0.95) : accent)
            )
        }
    }

    // 15. Fluid Acoustic Cadence Light Strip (replaces old clunky text glyphs)
    private func drawCadenceLightStrip(_ ctx: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let count = 11
        let midY = size.height / 2
        let span = size.width - 32
        let step = span / CGFloat(count - 1)
        for i in 0..<count {
            let u = Double(i) / Double(count - 1)
            let bell = sin(u * .pi)
            let phase = sin(t * 6.2 - Double(i) * 0.85)
            let w = CGFloat(3.5 + (phase > 0 ? 7.5 * phase : 0) * energy * bell)
            let h: CGFloat = 3.0
            let cx = 16 + CGFloat(i) * step
            let rect = CGRect(x: cx - w / 2, y: midY - h / 2, width: w, height: h)
            let color = i.isMultiple(of: 2) ? accent : secondary
            var g = ctx
            g.addFilter(.shadow(color: color.opacity(0.65 * energy), radius: 4))
            g.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(color.opacity(0.32 + 0.68 * bell * (0.35 + energy * 0.65))))
        }
    }
}
