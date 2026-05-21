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

    @ViewBuilder
    func body(content: Content) -> some View {
        let surfaceOpacity = surfaceOpacity(for: theme, strong: strong)
        let borderOpacity = accentBorderOpacity(for: theme)
        let shadowOpacity = accentShadowOpacity(for: theme, strong: strong)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            let surface = content
                .glassEffect(
                    .regular.tint(Color(themeColor: theme.surfaceTint).opacity(liquidGlassTintOpacity(for: theme, strong: strong))),
                    in: shape
                )
                .shadow(
                    color: Color(themeColor: theme.accentColor).opacity(shadowOpacity * 0.46),
                    radius: strong ? 16 : 9,
                    x: 0,
                    y: strong ? 8 : 4
                )
            if interactive {
                surface.liquidGlassMotion(theme, strong: strong)
            } else {
                surface
            }
        } else {
            let surface = content
                .background(.ultraThinMaterial, in: shape)
                .background(Color(themeColor: theme.surfaceTint).opacity(surfaceOpacity), in: shape)
                .overlay {
                    shape.stroke(Color(themeColor: theme.accentColor).opacity(borderOpacity), lineWidth: strong ? 1.2 : 1)
                }
                .shadow(
                    color: Color(themeColor: theme.accentColor).opacity(shadowOpacity),
                    radius: strong ? 18 : 10,
                    x: 0,
                    y: strong ? 8 : 4
                )
            if interactive {
                surface.liquidGlassMotion(theme, strong: strong)
            } else {
                surface
            }
        }
    }

    private func surfaceOpacity(for theme: OmniVoiceTheme, strong: Bool) -> Double {
        clampedOpacity(theme.glassOpacity + (strong ? 0.18 : 0))
    }

    private func accentBorderOpacity(for theme: OmniVoiceTheme) -> Double {
        clampedOpacity(theme.borderOpacity)
    }

    private func accentShadowOpacity(for theme: OmniVoiceTheme, strong: Bool) -> Double {
        clampedOpacity(theme.glowStrength * (strong ? 0.55 : 0.35))
    }

    private func liquidGlassTintOpacity(for theme: OmniVoiceTheme, strong: Bool) -> Double {
        let multiplier = strong ? 0.16 : 0.10
        let cap = strong ? 0.095 : 0.065
        return min(max(theme.glassOpacity * multiplier, 0.018), cap)
    }

    private func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct LiquidGlassMotion: ViewModifier {
    let theme: OmniVoiceTheme
    let strong: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let accent = Color(themeColor: theme.accentColor)
        content
            .scaleEffect(motionScale)
            .shadow(
                color: accent.opacity(isHovering && !reduceMotion ? (strong ? 0.18 : 0.11) : 0),
                radius: isHovering ? (strong ? 16 : 10) : 0,
                x: 0,
                y: isHovering ? (strong ? 7 : 4) : 0
            )
            .animation(.snappy(duration: 0.22), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var motionScale: CGFloat {
        guard isHovering, !reduceMotion else {
            return 1
        }
        return strong ? 1.008 : 1.004
    }
}

struct ThemePillSurface: ViewModifier {
    let theme: OmniVoiceTheme
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        let tint = Color(themeColor: theme.surfaceTint)
        let accent = Color(themeColor: theme.accentColor)

        if #available(macOS 26.0, *) {
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
            let surface = content
                .background(.thinMaterial, in: shape)
                .background(tint.opacity(0.08), in: shape)
                .overlay {
                    shape.stroke(accent.opacity(0.16), lineWidth: 1)
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
                OmniVoiceWindowBackground(theme: theme, colorScheme: colorScheme)
                    .ignoresSafeArea()
            }
            .tint(Color(themeColor: palette.accentText))
    }
}

struct OmniVoiceWindowBackground: View {
    let theme: OmniVoiceTheme
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(themeColor: theme.surfaceTint).opacity(surfaceOpacity),
                    Color(themeColor: theme.secondaryAccentColor).opacity(secondaryOpacity)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(themeColor: theme.accentColor).opacity(accentOpacity),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 520
            )
            .blendMode(colorScheme == .dark ? .screen : .multiply)
        }
    }

    private var surfaceOpacity: Double {
        colorScheme == .dark ? 0.16 : 0.07
    }

    private var secondaryOpacity: Double {
        colorScheme == .dark ? 0.07 : 0.035
    }

    private var accentOpacity: Double {
        min(max(theme.glowStrength * (colorScheme == .dark ? 0.18 : 0.08), 0.015), 0.16)
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
