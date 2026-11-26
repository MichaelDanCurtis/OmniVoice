import SwiftUI
import OmniVoiceCore

struct OmniGlassCard<Content: View>: View {
    let theme: OmniVoiceTheme
    var cornerRadius: CGFloat = 14
    var strong: Bool = false
    var interactive: Bool = false
    var padding: CGFloat = 14
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let effectiveRadius = theme.look.cardRadius(forRequested: cornerRadius)
        let shape = RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
        let accent = Color(themeColor: theme.resolvedPalette(for: colorScheme).accentText)

        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fontDesign(theme.look.bodyFontDesign)
            .themeSurface(theme, cornerRadius: effectiveRadius, strong: strong, interactive: interactive)
            .overlay {
                if theme.look == .liquidGlass {
                    shape.stroke(
                        accent.opacity(colorScheme == .dark ? (strong ? 0.24 : 0.14) : (strong ? 0.22 : 0.14)),
                        lineWidth: 0.75
                    )
                }
            }
    }
}

struct OmniStatusPill: View {
    let title: String
    let tint: Color
    var systemImage: String? = nil
    var pulsing: Bool = false
    var theme: OmniVoiceTheme? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let cornerRadius = theme?.look.pillRadius ?? 999
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let useGlass = theme?.look.usesGlassMaterial ?? true
        let borderWidth = theme?.look.strokeWidth ?? 0.75

        HStack(spacing: 5) {
            if pulsing {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .overlay {
                        Circle()
                            .stroke(tint.opacity(0.35), lineWidth: 2)
                            .frame(width: 10, height: 10)
                    }
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.caption2.weight(.semibold))
                .fontDesign(theme?.look.bodyFontDesign ?? .default)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .modifier(OmniPillLookModifier(
            tint: tint,
            shape: shape,
            useGlass: useGlass,
            borderWidth: borderWidth,
            isDark: colorScheme == .dark
        ))
    }
}

struct OmniKeycapBadge: View {
    let shortcut: String
    let theme: OmniVoiceTheme

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let radius = min(6, max(2, theme.look.pillRadius))
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let accent = Color(themeColor: theme.resolvedPalette(for: colorScheme).accentText)

        Text(shortcut)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                shape.fill(accent.opacity(colorScheme == .dark ? 0.14 : 0.10))
            )
            .overlay {
                shape.stroke(accent.opacity(theme.look == .brutalistInk ? 0.80 : 0.28), lineWidth: theme.look.strokeWidth)
            }
    }
}

struct OmniWorkspaceTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let theme: OmniVoiceTheme
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let effectiveRadius = theme.look.cardRadius(forRequested: 12)
        let shape = RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
        let accent = Color(themeColor: theme.resolvedPalette(for: colorScheme).accentText)
        let iconRadius = min(13, max(3, theme.look.pillRadius))

        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: iconRadius, style: .continuous)
                            .fill(accent.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    )

                Text(title)
                    .font(.caption.weight(.semibold))
                    .fontDesign(theme.look.headerFontDesign)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .fontDesign(theme.look.bodyFontDesign)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .themeSurface(theme, cornerRadius: effectiveRadius, strong: false, interactive: true)
            .overlay {
                if theme.look == .liquidGlass {
                    shape.stroke(
                        accent.opacity(isHovered ? 0.42 : 0.16),
                        lineWidth: isHovered ? 1 : 0.75
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct OmniPillLookModifier<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S
    let useGlass: Bool
    let borderWidth: CGFloat
    let isDark: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useGlass, #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint.opacity(0.08)), in: shape)
                .overlay {
                    shape.stroke(tint.opacity(isDark ? 0.28 : 0.24), lineWidth: borderWidth)
                }
        } else {
            content
                .background(tint.opacity(isDark ? 0.16 : 0.11), in: shape)
                .overlay {
                    shape.stroke(tint.opacity(0.35), lineWidth: borderWidth)
                }
        }
    }
}
