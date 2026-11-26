import AppKit
import SwiftUI
import OmniVoiceCore

extension Color {
    init(themeColor: ThemeColor) {
        let fallback = 0x38BDF8
        let rawValue = String(themeColor.hex.dropFirst(themeColor.hex.hasPrefix("#") ? 1 : 0))
        let value = rawValue.count == 6 ? Int(rawValue, radix: 16) ?? fallback : fallback

        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

extension ThemeColor {
    init(color: Color) {
        let fallback = ThemeColor(hex: "#38BDF8")
        guard let color = NSColor(color).usingColorSpace(.sRGB) else {
            self = fallback
            return
        }

        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        self.init(hex: String(format: "#%02X%02X%02X", red, green, blue))
    }
}

extension AppAppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .dark:
            .dark
        case .light:
            .light
        }
    }
}

extension ThemeLook {
    var headerFontDesign: Font.Design {
        switch self {
        case .liquidGlass, .studioPro, .brutalistInk, .crystalPrism:
            .default
        case .cyberTerminal, .blueprintGrid:
            .monospaced
        case .editorialPaper, .zenWashi:
            .serif
        case .softClay, .retroSynth:
            .rounded
        }
    }

    var bodyFontDesign: Font.Design {
        switch self {
        case .cyberTerminal:
            .monospaced
        case .softClay:
            .rounded
        case .liquidGlass, .studioPro, .editorialPaper, .brutalistInk,
             .crystalPrism, .blueprintGrid, .retroSynth, .zenWashi:
            .default
        }
    }

    func cardRadius(forRequested requested: CGFloat) -> CGFloat {
        switch self {
        case .liquidGlass:
            requested
        case .studioPro:
            min(requested, 9)
        case .cyberTerminal:
            min(requested, 3)
        case .editorialPaper:
            min(max(requested * 0.75, 6), 11)
        case .softClay:
            max(requested, 18)
        case .brutalistInk:
            min(requested, 6)
        case .crystalPrism:
            max(requested, 15)
        case .blueprintGrid:
            min(requested, 4)
        case .retroSynth:
            min(max(requested * 0.8, 7), 12)
        case .zenWashi:
            min(max(requested * 0.95, 10), 15)
        }
    }

    var pillRadius: CGFloat {
        CGFloat(pillCornerRadius)
    }

    var strokeWidth: CGFloat {
        CGFloat(borderWidth)
    }
}

extension OmniVoiceTheme {
    func resolvedPalette(for colorScheme: ColorScheme) -> ResolvedThemePalette {
        resolvedPalette(for: colorScheme == .dark ? ThemeResolvedAppearance.dark : ThemeResolvedAppearance.light)
    }
}

struct ThemeSurface: ViewModifier {
    let theme: OmniVoiceTheme
    let cornerRadius: CGFloat
    let strong: Bool
    let interactive: Bool

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let effectiveRadius = theme.look.cardRadius(forRequested: cornerRadius)
        let shape = RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
        let accent = Color(themeColor: theme.accentColor)
        let secondary = Color(themeColor: theme.secondaryAccentColor)

        let surface = baseSurface(
            content: content,
            shape: shape,
            accent: accent,
            secondary: secondary
        )

        if interactive {
            surface.liquidGlassMotion(theme, strong: strong)
        } else {
            surface
        }
    }

    @ViewBuilder
    private func baseSurface<S: InsettableShape>(
        content: Content,
        shape: S,
        accent: Color,
        secondary: Color
    ) -> some View {
        switch theme.look {
        case .liquidGlass:
            liquidGlassBody(content: content, shape: shape, accent: accent)

        case .studioPro:
            let fillColor = colorScheme == .dark
                ? Color(red: strong ? 0.11 : 0.085, green: strong ? 0.125 : 0.098, blue: strong ? 0.155 : 0.128)
                : Color(red: strong ? 0.985 : 0.955, green: strong ? 0.99 : 0.962, blue: strong ? 1.0 : 0.978)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: fillColor,
                stroke: LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.85),
                        accent.opacity(strong ? 0.34 : 0.18),
                        Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: theme.look.strokeWidth,
                shadowColor: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.07),
                shadowRadius: strong ? 8 : 4,
                shadowOffset: CGSize(width: 0, height: 2)
            )

        case .cyberTerminal:
            let fillColor = colorScheme == .dark
                ? Color(red: 0.025, green: 0.052, blue: 0.042).opacity(strong ? 0.96 : 0.88)
                : Color(red: 0.935, green: 0.97, blue: 0.945).opacity(strong ? 0.98 : 0.92)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: fillColor,
                stroke: accent.opacity(strong ? 0.72 : 0.44),
                lineWidth: theme.look.strokeWidth,
                shadowColor: accent.opacity(strong ? 0.22 : 0.12),
                shadowRadius: strong ? 10 : 5,
                shadowOffset: .zero
            )

        case .editorialPaper:
            let fillColor = colorScheme == .dark
                ? Color(red: strong ? 0.145 : 0.12, green: strong ? 0.128 : 0.106, blue: strong ? 0.112 : 0.094)
                : Color(red: 0.992, green: 0.976, blue: strong ? 0.952 : 0.942)
            let ruleColor = colorScheme == .dark
                ? Color(red: 0.82, green: 0.74, blue: 0.62).opacity(strong ? 0.28 : 0.18)
                : Color(red: 0.45, green: 0.36, blue: 0.26).opacity(strong ? 0.24 : 0.16)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: fillColor,
                stroke: ruleColor,
                lineWidth: theme.look.strokeWidth,
                shadowColor: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.07),
                shadowRadius: strong ? 7 : 3,
                shadowOffset: CGSize(width: 0, height: 2)
            )

        case .softClay:
            let fillColor = colorScheme == .dark
                ? Color(red: strong ? 0.145 : 0.12, green: strong ? 0.135 : 0.115, blue: strong ? 0.185 : 0.158)
                : Color(red: strong ? 0.975 : 0.952, green: strong ? 0.96 : 0.94, blue: strong ? 0.99 : 0.972)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: LinearGradient(
                    colors: [
                        fillColor,
                        secondary.opacity(colorScheme == .dark ? 0.10 : 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                stroke: Color.white.opacity(colorScheme == .dark ? 0.14 : 0.85),
                lineWidth: 1.0,
                shadowColor: (colorScheme == .dark ? Color.black : accent).opacity(colorScheme == .dark ? 0.35 : 0.12),
                shadowRadius: strong ? 14 : 10,
                shadowOffset: CGSize(width: 0, height: strong ? 7 : 4)
            )

        case .brutalistInk:
            let fillColor = colorScheme == .dark
                ? Color(red: strong ? 0.06 : 0.03, green: strong ? 0.06 : 0.03, blue: strong ? 0.06 : 0.03)
                : Color.white
            let strokeColor = strong ? accent : Color.primary.opacity(colorScheme == .dark ? 0.72 : 0.85)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: fillColor,
                stroke: strokeColor,
                lineWidth: theme.look.strokeWidth,
                shadowColor: (strong ? accent : Color.primary).opacity(colorScheme == .dark ? 0.40 : 0.22),
                shadowRadius: 0,
                shadowOffset: CGSize(width: 3, height: 3)
            )

        case .crystalPrism:
            crystalPrismBody(content: content, shape: shape, accent: accent, secondary: secondary)

        case .blueprintGrid:
            let fillColor = colorScheme == .dark
                ? Color(red: 0.045, green: 0.135, blue: 0.235).opacity(strong ? 0.90 : 0.76)
                : Color(red: 0.925, green: 0.962, blue: 0.995).opacity(strong ? 0.96 : 0.88)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: fillColor,
                stroke: LinearGradient(
                    colors: [
                        accent.opacity(strong ? 0.78 : 0.48),
                        secondary.opacity(strong ? 0.50 : 0.25),
                        accent.opacity(strong ? 0.65 : 0.36)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: theme.look.strokeWidth,
                shadowColor: accent.opacity(colorScheme == .dark ? 0.18 : 0.08),
                shadowRadius: strong ? 6 : 3,
                shadowOffset: CGSize(width: 0, height: 1)
            )

        case .retroSynth:
            let fillColor = colorScheme == .dark
                ? Color(red: strong ? 0.105 : 0.075, green: strong ? 0.045 : 0.032, blue: strong ? 0.185 : 0.145).opacity(0.92)
                : Color(red: 0.98, green: 0.945, blue: 0.995).opacity(strong ? 0.96 : 0.88)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: LinearGradient(
                    colors: [
                        fillColor,
                        (colorScheme == .dark ? secondary : accent).opacity(colorScheme == .dark ? 0.12 : 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                stroke: LinearGradient(
                    colors: [
                        accent.opacity(strong ? 0.92 : 0.62),
                        secondary.opacity(strong ? 0.88 : 0.56)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: theme.look.strokeWidth,
                shadowColor: accent.opacity(colorScheme == .dark ? (strong ? 0.34 : 0.18) : 0.12),
                shadowRadius: strong ? 12 : 6,
                shadowOffset: CGSize(width: 0, height: 3)
            )

        case .zenWashi:
            let fillColor = colorScheme == .dark
                ? Color(red: strong ? 0.115 : 0.095, green: strong ? 0.128 : 0.108, blue: strong ? 0.105 : 0.09)
                : Color(red: strong ? 0.972 : 0.955, green: strong ? 0.968 : 0.952, blue: strong ? 0.942 : 0.928)
            let hairline = colorScheme == .dark
                ? accent.opacity(strong ? 0.34 : 0.20)
                : Color(red: 0.38, green: 0.42, blue: 0.34).opacity(strong ? 0.28 : 0.16)
            styledCardSurface(
                content: content,
                shape: shape,
                fill: fillColor,
                stroke: hairline,
                lineWidth: theme.look.strokeWidth,
                shadowColor: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.05),
                shadowRadius: strong ? 8 : 4,
                shadowOffset: CGSize(width: 0, height: 2)
            )
        }
    }

    /// Applies background fill, scoped card drop-shadow (only on the backdrop shape, never child text), and border stroke.
    private func styledCardSurface<S: Shape, Fill: ShapeStyle, Stroke: ShapeStyle>(
        content: Content,
        shape: S,
        fill: Fill,
        stroke: Stroke,
        lineWidth: CGFloat,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowOffset: CGSize
    ) -> some View {
        content
            .background {
                shape
                    .fill(fill)
                    .shadow(
                        color: shadowColor,
                        radius: shadowRadius,
                        x: shadowOffset.width,
                        y: shadowOffset.height
                    )
            }
            .overlay {
                shape.stroke(stroke, lineWidth: lineWidth)
            }
    }

    @ViewBuilder
    private func crystalPrismBody<S: InsettableShape>(
        content: Content,
        shape: S,
        accent: Color,
        secondary: Color
    ) -> some View {
        let prismRim = LinearGradient(
            colors: [
                Color(red: 0.40, green: 0.92, blue: 1.0).opacity(strong ? 0.78 : 0.46),
                accent.opacity(strong ? 0.72 : 0.44),
                Color(red: 0.98, green: 0.54, blue: 0.92).opacity(strong ? 0.68 : 0.38),
                Color(red: 1.0, green: 0.86, blue: 0.46).opacity(strong ? 0.58 : 0.32),
                secondary.opacity(strong ? 0.70 : 0.40)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let glassFill = LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? (strong ? 0.12 : 0.07) : (strong ? 0.68 : 0.52)),
                accent.opacity(colorScheme == .dark ? 0.08 : 0.06),
                secondary.opacity(colorScheme == .dark ? 0.06 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(accent.opacity(strong ? 0.08 : 0.04)),
                    in: shape
                )
                .background(glassFill, in: shape)
                .overlay {
                    shape.stroke(prismRim, lineWidth: strong ? 1.25 : 0.95)
                }
                .shadow(
                    color: secondary.opacity(colorScheme == .dark ? 0.22 : 0.10),
                    radius: strong ? 16 : 9,
                    x: 0,
                    y: strong ? 7 : 3
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(glassFill, in: shape)
                .overlay {
                    shape.stroke(prismRim, lineWidth: strong ? 1.25 : 0.95)
                }
                .shadow(
                    color: secondary.opacity(colorScheme == .dark ? 0.24 : 0.12),
                    radius: strong ? 16 : 9,
                    x: 0,
                    y: strong ? 7 : 3
                )
        }
    }

    @ViewBuilder
    private func liquidGlassBody<S: InsettableShape>(content: Content, shape: S, accent: Color) -> some View {
        let surfaceOpacity = min(max(theme.glassOpacity + (strong ? 0.18 : 0), 0), 1)
        let borderOpacity = min(max(theme.borderOpacity, 0), 1)
        let shadowOpacity = min(max(theme.glowStrength * (strong ? 0.55 : 0.35), 0), 1)
        let glassTintOpacity = min(max(theme.glassOpacity * (strong ? 0.16 : 0.10), 0.018), strong ? 0.095 : 0.065)

        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Color(themeColor: theme.surfaceTint).opacity(glassTintOpacity * 1.4)),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.72),
                                accent.opacity(strong ? 0.34 : 0.18),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strong ? 1.1 : 0.85
                    )
                }
                .shadow(
                    color: accent.opacity(shadowOpacity * 0.48),
                    radius: strong ? 16 : 9,
                    x: 0,
                    y: strong ? 8 : 4
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color(themeColor: theme.surfaceTint).opacity(surfaceOpacity), in: shape)
                .overlay {
                    shape.stroke(accent.opacity(borderOpacity), lineWidth: strong ? 1.2 : 1)
                }
                .shadow(
                    color: accent.opacity(shadowOpacity),
                    radius: strong ? 18 : 10,
                    x: 0,
                    y: strong ? 8 : 4
                )
        }
    }
}

struct LiquidGlassMotion: ViewModifier {
    let theme: OmniVoiceTheme
    let strong: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let motionMultiplier: CGFloat = switch theme.look {
        case .brutalistInk, .cyberTerminal: 0.0
        case .blueprintGrid: 0.25
        case .studioPro, .editorialPaper, .zenWashi: 0.4
        case .retroSynth: 0.8
        case .liquidGlass, .softClay, .crystalPrism: 1.0
        }
        let scale: CGFloat = if isHovering, !reduceMotion {
            1.0 + ((strong ? 0.008 : 0.004) * motionMultiplier)
        } else {
            1.0
        }

        content
            .scaleEffect(scale)
            .animation(.snappy(duration: 0.20), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

struct ThemePillSurface: ViewModifier {
    let theme: OmniVoiceTheme
    let interactive: Bool
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let radius = theme.look.pillRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tint = Color(themeColor: theme.surfaceTint)
        let accent = Color(themeColor: theme.accentColor)

        if theme.look.usesGlassMaterial, #available(macOS 26.0, *) {
            let surface = content
                .glassEffect(
                    .regular
                        .tint(tint.opacity(0.04))
                        .interactive(interactive),
                    in: shape
                )
                .shadow(color: accent.opacity(0.06), radius: 9, x: 0, y: 4)
            if interactive {
                surface.liquidGlassMotion(theme, strong: true)
            } else {
                surface
            }
        } else {
            let bgColor: Color = switch theme.look {
            case .liquidGlass, .softClay, .crystalPrism:
                tint.opacity(colorScheme == .dark ? 0.16 : 0.08)
            case .studioPro:
                colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
            case .cyberTerminal, .blueprintGrid:
                accent.opacity(colorScheme == .dark ? 0.10 : 0.08)
            case .retroSynth:
                accent.opacity(colorScheme == .dark ? 0.16 : 0.10)
            case .editorialPaper:
                Color(red: 0.72, green: 0.62, blue: 0.48).opacity(colorScheme == .dark ? 0.14 : 0.12)
            case .zenWashi:
                Color(red: 0.54, green: 0.60, blue: 0.48).opacity(colorScheme == .dark ? 0.15 : 0.12)
            case .brutalistInk:
                colorScheme == .dark ? Color.black : Color.white
            }
            let surface = content
                .background(bgColor, in: shape)
                .overlay {
                    shape.stroke(accent.opacity(theme.look == .brutalistInk ? 0.85 : 0.28), lineWidth: theme.look.strokeWidth)
                }
            if interactive {
                surface.liquidGlassMotion(theme, strong: true)
            } else {
                surface
            }
        }
    }
}

struct ThemeAccentForeground: ViewModifier {
    let theme: OmniVoiceTheme
    let secondary: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = theme.resolvedPalette(for: colorScheme)
        content.foregroundStyle(Color(themeColor: secondary ? palette.secondaryAccentText : palette.accentText))
    }
}

struct ThemedWindowBackground: ViewModifier {
    let theme: OmniVoiceTheme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = theme.resolvedPalette(for: colorScheme)
        content
            .background {
                ZStack {
                    WindowTranslucencyBridge(isTranslucent: theme.look.usesGlassMaterial)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                    OmniVoiceWindowBackground(theme: theme, colorScheme: colorScheme)
                    WildThemeArtBackdrop(theme: theme, colorScheme: colorScheme)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            }
            .tint(Color(themeColor: palette.accentText))
            .fontDesign(theme.look.bodyFontDesign)
    }
}

struct OmniVoiceWindowBackground: View {
    let theme: OmniVoiceTheme
    let colorScheme: ColorScheme

    var body: some View {
        let accent = Color(themeColor: theme.accentColor)
        let secondary = Color(themeColor: theme.secondaryAccentColor)
        let tint = Color(themeColor: theme.surfaceTint)

        switch theme.look {
        case .liquidGlass:
            ZStack {
                LiquidGlassBehindWindowBackdrop()
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        tint.opacity(colorScheme == .dark ? 0.22 : 0.14),
                        secondary.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        accent.opacity(min(max(theme.glowStrength * (colorScheme == .dark ? 0.30 : 0.18), 0.08), 0.28)),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 480
                )
                .blendMode(colorScheme == .dark ? .screen : .multiply)

                RadialGradient(
                    colors: [
                        secondary.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        .clear
                    ],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 420
                )
                .blendMode(colorScheme == .dark ? .screen : .multiply)
            }

        case .studioPro:
            ZStack {
                (colorScheme == .dark
                    ? Color(red: 0.055, green: 0.065, blue: 0.085)
                    : Color(red: 0.915, green: 0.925, blue: 0.945))

                Canvas { context, size in
                    let step: CGFloat = 18
                    let dotColor = (colorScheme == .dark ? Color.white : Color.black).opacity(0.055)
                    var dots = Path()
                    var y: CGFloat = 9
                    while y < size.height {
                        var x: CGFloat = 9
                        while x < size.width {
                            dots.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                            x += step
                        }
                        y += step
                    }
                    context.fill(dots, with: .color(dotColor))
                }
                .drawingGroup()
            }

        case .cyberTerminal:
            ZStack {
                (colorScheme == .dark
                    ? Color(red: 0.018, green: 0.036, blue: 0.028)
                    : Color(red: 0.89, green: 0.94, blue: 0.90))

                Canvas { context, size in
                    let gridColor = accent.opacity(colorScheme == .dark ? 0.06 : 0.08)
                    let scanColor = Color.black.opacity(colorScheme == .dark ? 0.16 : 0.025)
                    var gridPath = Path()
                    var x: CGFloat = 0
                    while x < size.width {
                        gridPath.move(to: CGPoint(x: x, y: 0))
                        gridPath.addLine(to: CGPoint(x: x, y: size.height))
                        x += 48
                    }
                    context.stroke(gridPath, with: .color(gridColor), lineWidth: 0.5)

                    var scanPath = Path()
                    var y: CGFloat = 0
                    while y < size.height {
                        scanPath.move(to: CGPoint(x: 0, y: y))
                        scanPath.addLine(to: CGPoint(x: size.width, y: y))
                        y += 4
                    }
                    context.stroke(scanPath, with: .color(scanColor), lineWidth: 1)
                }
                .drawingGroup()
            }

        case .editorialPaper:
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.085, green: 0.075, blue: 0.068),
                        Color(red: 0.115, green: 0.098, blue: 0.085)
                    ]
                    : [
                        Color(red: 0.962, green: 0.938, blue: 0.895),
                        Color(red: 0.935, green: 0.906, blue: 0.855)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .softClay:
            ZStack {
                (colorScheme == .dark
                    ? Color(red: 0.09, green: 0.085, blue: 0.125)
                    : Color(red: 0.925, green: 0.912, blue: 0.95))

                RadialGradient(
                    colors: [
                        accent.opacity(colorScheme == .dark ? 0.14 : 0.12),
                        secondary.opacity(colorScheme == .dark ? 0.08 : 0.06),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 600
                )
            }

        case .brutalistInk:
            colorScheme == .dark ? Color.black : Color(red: 0.96, green: 0.96, blue: 0.96)

        case .crystalPrism:
            ZStack {
                LiquidGlassBehindWindowBackdrop()
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        Color(red: 0.28, green: 0.88, blue: 1.0).opacity(colorScheme == .dark ? 0.14 : 0.12),
                        accent.opacity(colorScheme == .dark ? 0.15 : 0.10),
                        Color(red: 0.98, green: 0.48, blue: 0.88).opacity(colorScheme == .dark ? 0.13 : 0.09),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        secondary.opacity(colorScheme == .dark ? 0.22 : 0.14),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 420
                )
                .blendMode(colorScheme == .dark ? .screen : .multiply)
            }

        case .blueprintGrid:
            ZStack {
                (colorScheme == .dark
                    ? Color(red: 0.032, green: 0.102, blue: 0.195)
                    : Color(red: 0.905, green: 0.95, blue: 0.99))

                Canvas { context, size in
                    let minorStep: CGFloat = 14
                    let majorStep: CGFloat = 70
                    var minor = Path()
                    var major = Path()
                    var x: CGFloat = 0
                    while x < size.width {
                        minor.move(to: CGPoint(x: x, y: 0))
                        minor.addLine(to: CGPoint(x: x, y: size.height))
                        x += minorStep
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        minor.move(to: CGPoint(x: 0, y: y))
                        minor.addLine(to: CGPoint(x: size.width, y: y))
                        y += minorStep
                    }
                    x = 0
                    while x < size.width {
                        major.move(to: CGPoint(x: x, y: 0))
                        major.addLine(to: CGPoint(x: x, y: size.height))
                        x += majorStep
                    }
                    y = 0
                    while y < size.height {
                        major.move(to: CGPoint(x: 0, y: y))
                        major.addLine(to: CGPoint(x: size.width, y: y))
                        y += majorStep
                    }
                    context.stroke(minor, with: .color(accent.opacity(colorScheme == .dark ? 0.075 : 0.09)), lineWidth: 0.5)
                    context.stroke(major, with: .color(accent.opacity(colorScheme == .dark ? 0.17 : 0.16)), lineWidth: 0.9)
                }
                .drawingGroup()
            }

        case .retroSynth:
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.065, green: 0.025, blue: 0.14),
                            Color(red: 0.11, green: 0.035, blue: 0.21),
                            Color(red: 0.045, green: 0.02, blue: 0.10)
                        ]
                        : [
                            Color(red: 0.96, green: 0.92, blue: 0.99),
                            Color(red: 0.93, green: 0.96, blue: 1.0)
                        ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas { context, size in
                    let horizonY = size.height * 0.62
                    let vanish = CGPoint(x: size.width * 0.5, y: horizonY)
                    var grid = Path()
                    for i in -6...6 {
                        let bottomX = size.width * 0.5 + CGFloat(i) * (size.width * 0.16)
                        grid.move(to: vanish)
                        grid.addLine(to: CGPoint(x: bottomX, y: size.height))
                    }
                    for row in 0...5 {
                        let t = pow(Double(row) / 5.0, 1.65)
                        let y = horizonY + CGFloat(t) * (size.height - horizonY)
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(secondary.opacity(colorScheme == .dark ? 0.16 : 0.12)), lineWidth: 0.8)
                    var horizon = Path()
                    horizon.move(to: CGPoint(x: 0, y: horizonY))
                    horizon.addLine(to: CGPoint(x: size.width, y: horizonY))
                    context.stroke(horizon, with: .color(accent.opacity(colorScheme == .dark ? 0.34 : 0.20)), lineWidth: 1.2)
                }
                .drawingGroup()
            }

        case .zenWashi:
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.068, green: 0.082, blue: 0.066),
                            Color(red: 0.095, green: 0.105, blue: 0.085)
                        ]
                        : [
                            Color(red: 0.942, green: 0.94, blue: 0.908),
                            Color(red: 0.916, green: 0.918, blue: 0.88)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Canvas { context, size in
                    var fibers = Path()
                    var y: CGFloat = 10
                    while y < size.height {
                        fibers.move(to: CGPoint(x: 0, y: y))
                        fibers.addLine(to: CGPoint(x: size.width, y: y + 1.5))
                        y += 14
                    }
                    let fiberColor = (colorScheme == .dark ? accent : Color(red: 0.35, green: 0.40, blue: 0.32)).opacity(0.05)
                    context.stroke(fibers, with: .color(fiberColor), lineWidth: 0.7)
                }
                .drawingGroup()
            }
        }
    }
}

extension View {
    func themeSurface(
        _ theme: OmniVoiceTheme,
        cornerRadius: CGFloat = 8,
        strong: Bool = false,
        interactive: Bool = true
    ) -> some View {
        modifier(ThemeSurface(theme: theme, cornerRadius: cornerRadius, strong: strong, interactive: interactive))
    }

    func themePillSurface(
        _ theme: OmniVoiceTheme,
        interactive: Bool = false
    ) -> some View {
        modifier(ThemePillSurface(theme: theme, interactive: interactive))
    }

    func themeAccentForeground(_ theme: OmniVoiceTheme) -> some View {
        modifier(ThemeAccentForeground(theme: theme, secondary: false))
    }

    func themeSecondaryAccentForeground(_ theme: OmniVoiceTheme) -> some View {
        modifier(ThemeAccentForeground(theme: theme, secondary: true))
    }

    func liquidGlassMotion(
        _ theme: OmniVoiceTheme,
        strong: Bool = false
    ) -> some View {
        modifier(LiquidGlassMotion(theme: theme, strong: strong))
    }

    func themeWindowBackground(_ theme: OmniVoiceTheme) -> some View {
        modifier(ThemedWindowBackground(theme: theme))
    }
}

private struct LiquidGlassBehindWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassthroughVisualEffectView(frame: .zero)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != .hudWindow { nsView.material = .hudWindow }
        if nsView.blendingMode != .behindWindow { nsView.blendingMode = .behindWindow }
        if nsView.state != .active { nsView.state = .active }
    }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct WindowTranslucencyBridge: NSViewRepresentable {
    let isTranslucent: Bool

    func makeNSView(context: Context) -> NSView {
        PassthroughWindowConfigView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let translucent = isTranslucent
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let needsChange = window.isOpaque == translucent || window.titlebarAppearsTransparent != translucent
            guard needsChange else { return }
            if translucent {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
            } else {
                window.isOpaque = true
                window.backgroundColor = .windowBackgroundColor
                window.titlebarAppearsTransparent = false
            }
        }
    }
}

private final class PassthroughWindowConfigView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Bespoke ambient canvas art layers for OmniSpeak's 5 wild signature themes
/// (Synthwave Sunset, Bioluminescent Reef, Tokyo Neon Rain, Kintsugi Gold, Architect Blueprint).
private struct WildThemeArtBackdrop: View {
    let theme: OmniVoiceTheme
    let colorScheme: ColorScheme

    var body: some View {
        let accent = Color(themeColor: theme.accentColor)
        let secondary = Color(themeColor: theme.secondaryAccentColor)

        switch theme.id {
        case .synthwaveHorizon:
            Canvas { ctx, size in
                let horizonY = size.height * 0.58
                // Glowing segmented outrun sun
                let sunRadius = min(size.width, size.height) * 0.19
                let sunCenter = CGPoint(x: size.width * 0.5, y: horizonY - sunRadius * 0.25)
                let sunRect = CGRect(
                    x: sunCenter.x - sunRadius,
                    y: sunCenter.y - sunRadius,
                    width: sunRadius * 2,
                    height: sunRadius * 2
                )
                ctx.fill(
                    Path(ellipseIn: sunRect),
                    with: .linearGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.28).opacity(0.32), accent.opacity(0.28)]),
                        startPoint: CGPoint(x: sunCenter.x, y: sunRect.minY),
                        endPoint: CGPoint(x: sunCenter.x, y: sunRect.maxY)
                    )
                )
                // Perspective neon grid below horizon
                let vanish = CGPoint(x: size.width * 0.5, y: horizonY)
                var gridPath = Path()
                for i in -8...8 {
                    let bottomX = size.width * 0.5 + CGFloat(i) * (size.width * 0.14)
                    gridPath.move(to: vanish)
                    gridPath.addLine(to: CGPoint(x: bottomX, y: size.height))
                }
                for row in 0...7 {
                    let t = pow(Double(row) / 7.0, 1.75)
                    let y = horizonY + CGFloat(t) * (size.height - horizonY)
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(gridPath, with: .color(secondary.opacity(colorScheme == .dark ? 0.20 : 0.14)), lineWidth: 1)
                // Horizon glow beam
                var horizonLine = Path()
                horizonLine.move(to: CGPoint(x: 0, y: horizonY))
                horizonLine.addLine(to: CGPoint(x: size.width, y: horizonY))
                ctx.stroke(horizonLine, with: .color(accent.opacity(0.45)), lineWidth: 1.5)
            }
            .drawingGroup()

        case .bioluminescentReef:
            Canvas { ctx, size in
                let orbs: [(CGFloat, CGFloat, CGFloat, Bool)] = [
                    (0.14, 0.22, 68, true),
                    (0.82, 0.18, 92, false),
                    (0.74, 0.72, 76, true),
                    (0.22, 0.80, 108, false),
                    (0.52, 0.42, 52, true),
                    (0.38, 0.15, 34, true),
                    (0.88, 0.52, 42, false),
                    (0.10, 0.56, 38, true),
                ]
                for (rx, ry, radius, isPrimary) in orbs {
                    let center = CGPoint(x: size.width * rx, y: size.height * ry)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    let color = isPrimary ? accent : secondary
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(colorScheme == .dark ? 0.22 : 0.13), .clear]),
                            center: center,
                            startRadius: 2,
                            endRadius: radius
                        )
                    )
                    ctx.stroke(
                        Path(ellipseIn: rect.insetBy(dx: radius * 0.55, dy: radius * 0.55)),
                        with: .color(color.opacity(0.14)),
                        lineWidth: 0.75
                    )
                }
            }
            .drawingGroup()

        case .tokyoRain:
            Canvas { ctx, size in
                var rain = Path()
                var reflections = Path()
                for i in 0..<26 {
                    let fx = CGFloat((i * 47 + 13) % 100) / 100.0
                    let fy = CGFloat((i * 29 + 7) % 100) / 100.0
                    let length = CGFloat(38 + (i % 5) * 18)
                    let x = fx * size.width
                    let y = fy * size.height
                    rain.move(to: CGPoint(x: x, y: y))
                    rain.addLine(to: CGPoint(x: x - length * 0.22, y: y + length))
                }
                for col in 0..<6 {
                    let x = size.width * (0.12 + CGFloat(col) * 0.16)
                    reflections.move(to: CGPoint(x: x, y: size.height * 0.65))
                    reflections.addLine(to: CGPoint(x: x, y: size.height))
                }
                ctx.stroke(rain, with: .color(secondary.opacity(colorScheme == .dark ? 0.22 : 0.15)), lineWidth: 1.0)
                ctx.stroke(reflections, with: .color(accent.opacity(colorScheme == .dark ? 0.16 : 0.10)), lineWidth: 4.0)
            }
            .drawingGroup()

        case .kintsugiGold:
            Canvas { ctx, size in
                let cracks: [[CGPoint]] = [
                    [
                        CGPoint(x: 0, y: size.height * 0.28),
                        CGPoint(x: size.width * 0.22, y: size.height * 0.34),
                        CGPoint(x: size.width * 0.41, y: size.height * 0.24),
                        CGPoint(x: size.width * 0.68, y: size.height * 0.42),
                        CGPoint(x: size.width, y: size.height * 0.36),
                    ],
                    [
                        CGPoint(x: size.width * 0.41, y: size.height * 0.24),
                        CGPoint(x: size.width * 0.48, y: size.height * 0.58),
                        CGPoint(x: size.width * 0.34, y: size.height * 0.84),
                        CGPoint(x: size.width * 0.28, y: size.height),
                    ],
                    [
                        CGPoint(x: size.width * 0.68, y: size.height * 0.42),
                        CGPoint(x: size.width * 0.76, y: size.height * 0.72),
                        CGPoint(x: size.width * 0.92, y: size.height * 0.90),
                    ],
                ]
                for points in cracks {
                    var vein = Path()
                    guard let first = points.first else { continue }
                    vein.move(to: first)
                    for pt in points.dropFirst() {
                        vein.addLine(to: pt)
                    }
                    ctx.stroke(vein, with: .color(accent.opacity(0.16)), lineWidth: 5.5)
                    ctx.stroke(vein, with: .color(accent.opacity(colorScheme == .dark ? 0.44 : 0.34)), lineWidth: 1.4)
                }
            }
            .drawingGroup()

        case .blueprintDraft:
            Canvas { ctx, size in
                let minorStep: CGFloat = 18
                let majorStep: CGFloat = 90
                var minor = Path()
                var major = Path()
                for x in stride(from: CGFloat(0), through: size.width, by: minorStep) {
                    minor.move(to: CGPoint(x: x, y: 0))
                    minor.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat(0), through: size.height, by: minorStep) {
                    minor.move(to: CGPoint(x: 0, y: y))
                    minor.addLine(to: CGPoint(x: size.width, y: y))
                }
                for x in stride(from: CGFloat(0), through: size.width, by: majorStep) {
                    major.move(to: CGPoint(x: x, y: 0))
                    major.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat(0), through: size.height, by: majorStep) {
                    major.move(to: CGPoint(x: 0, y: y))
                    major.addLine(to: CGPoint(x: size.width, y: y))
                }
                let baseAlpha: Double = colorScheme == .dark ? 1.0 : 0.65
                ctx.stroke(minor, with: .color(accent.opacity(0.08 * baseAlpha)), lineWidth: 0.6)
                ctx.stroke(major, with: .color(accent.opacity(0.18 * baseAlpha)), lineWidth: 1.0)
                // Architectural drafting compass arc in top-right corner
                let arcCenter = CGPoint(x: size.width * 0.86, y: size.height * 0.22)
                let r1: CGFloat = 110
                let r2: CGFloat = 155
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: arcCenter.x - r1, y: arcCenter.y - r1, width: r1 * 2, height: r1 * 2)),
                    with: .color(secondary.opacity(0.16 * baseAlpha)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: arcCenter.x - r2, y: arcCenter.y - r2, width: r2 * 2, height: r2 * 2)),
                    with: .color(accent.opacity(0.14 * baseAlpha)),
                    lineWidth: 0.8
                )
            }
            .drawingGroup()

        default:
            EmptyView()
        }
    }
}
