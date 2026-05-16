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

struct ThemeSurface: ViewModifier {
    let theme: OmniVoiceTheme
    let cornerRadius: CGFloat
    let strong: Bool

    func body(content: Content) -> some View {
        let surfaceOpacity = clampedOpacity(strong ? theme.glassOpacity + 0.18 : theme.glassOpacity)
        let borderOpacity = strong ? 0.36 : 0.24
        let shadowOpacity = clampedOpacity(theme.glowStrength * (strong ? 0.55 : 0.35))
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
