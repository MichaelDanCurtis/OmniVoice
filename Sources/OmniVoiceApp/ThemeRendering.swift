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

struct ThemeSurface: ViewModifier {
    let theme: OmniVoiceTheme
    let cornerRadius: CGFloat
    let strong: Bool

    func body(content: Content) -> some View {
        let surfaceOpacity = surfaceOpacity(for: theme, strong: strong)
        let borderOpacity = accentBorderOpacity(for: theme)
        let shadowOpacity = accentShadowOpacity(for: theme, strong: strong)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
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

    private func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

extension View {
    func themeSurface(
        _ theme: OmniVoiceTheme,
        cornerRadius: CGFloat = 8,
        strong: Bool = false
    ) -> some View {
        modifier(ThemeSurface(theme: theme, cornerRadius: cornerRadius, strong: strong))
    }
}
