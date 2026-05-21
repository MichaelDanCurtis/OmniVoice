import AppKit
import OmniVoiceCore

@MainActor
final class DynamicDockIconController {
    private var lastSignature: String?

    func apply(theme: OmniVoiceTheme, appearanceMode: AppAppearanceMode) {
        let resolvedAppearance = DynamicDockIconRenderer.resolvedAppearance(for: appearanceMode)
        let signature = [
            theme.id.rawValue,
            theme.accentColor.hex,
            theme.secondaryAccentColor.hex,
            theme.surfaceTint.hex,
            resolvedAppearance.rawValue,
        ].joined(separator: "|")

        guard signature != lastSignature else {
            return
        }

        NSApplication.shared.applicationIconImage = DynamicDockIconRenderer.image(
            theme: theme,
            appearance: resolvedAppearance
        )
        lastSignature = signature
    }
}

enum DynamicDockIconRenderer {
    static let canvasSize: CGFloat = 1024

    @MainActor
    static func resolvedAppearance(for mode: AppAppearanceMode) -> ThemeResolvedAppearance {
        switch mode {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            let bestMatch = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return bestMatch == .aqua ? .light : .dark
        }
    }

    static func image(
        theme: OmniVoiceTheme,
        appearance: ThemeResolvedAppearance,
        profile: DockIconSpectrumProfile = .subtleVU
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        let palette = theme.resolvedPalette(for: appearance)
        drawShell(theme: theme, palette: palette)
        drawSpectrum(theme: theme, palette: palette, profile: profile)
        drawGlassFinish(theme: theme, palette: palette)

        image.isTemplate = false
        return image
    }

    private static func drawShell(theme: OmniVoiceTheme, palette: ResolvedThemePalette) {
        let rect = NSRect(x: 48, y: 48, width: 928, height: 928)
        let shell = NSBezierPath(roundedRect: rect, xRadius: 214, yRadius: 214)
        let accent = NSColor(themeColor: palette.accentGraphic)
        let surface = NSColor(themeColor: palette.windowBackground)
        let surfaceTint = NSColor(themeColor: theme.surfaceTint)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 36
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        shell.fillGradient(
            start: surface.mixed(with: surfaceTint, amount: 0.32),
            end: NSColor.black.mixed(with: surfaceTint, amount: 0.18),
            angle: -44
        )
        NSGraphicsContext.restoreGraphicsState()

        let stageRect = rect.insetBy(dx: 36, dy: 36)
        let stage = NSBezierPath(roundedRect: stageRect, xRadius: 184, yRadius: 184)
        stage.fillGradient(
            start: surfaceTint.withAlphaComponent(0.48),
            end: NSColor.black.withAlphaComponent(0.62),
            angle: 38
        )

        shell.lineWidth = 18
        accent.withAlphaComponent(0.48).setStroke()
        shell.stroke()

        let innerStroke = NSBezierPath(roundedRect: stageRect.insetBy(dx: 10, dy: 10), xRadius: 176, yRadius: 176)
        innerStroke.lineWidth = 2
        NSColor.white.withAlphaComponent(0.10).setStroke()
        innerStroke.stroke()
    }

    private static func drawSpectrum(
        theme: OmniVoiceTheme,
        palette: ResolvedThemePalette,
        profile: DockIconSpectrumProfile
    ) {
        let accent = NSColor(themeColor: palette.accentGraphic)
        let secondary = NSColor(themeColor: palette.secondaryAccentGraphic)
        let centerY: CGFloat = 512
        let maxHeight: CGFloat = 574
        let minHeight: CGFloat = 132
        let barWidth: CGFloat = 58
        let gap: CGFloat = 24
        let totalWidth = (CGFloat(profile.normalizedLevels.count) * barWidth)
            + (CGFloat(profile.normalizedLevels.count - 1) * gap)
        let startX = (canvasSize - totalWidth) / 2

        for (index, level) in profile.normalizedLevels.enumerated() {
            let height = minHeight + ((maxHeight - minHeight) * CGFloat(level))
            let x = startX + (CGFloat(index) * (barWidth + gap))
            let y = centerY - (height / 2)
            let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
            let bar = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            let distanceFromCenter = abs(CGFloat(index) - CGFloat(profile.normalizedLevels.count - 1) / 2)
            let normalizedDistance = distanceFromCenter / (CGFloat(profile.normalizedLevels.count) / 2)
            let opacity = 0.82 - (normalizedDistance * 0.28)
            let topColor = accent.mixed(with: .white, amount: 0.24).withAlphaComponent(opacity)
            let bottomColor = secondary.mixed(with: accent, amount: 0.45).withAlphaComponent(opacity * 0.74)

            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = accent.withAlphaComponent(profile.glowOpacity)
            glow.shadowBlurRadius = 30 + (CGFloat(level) * 18)
            glow.shadowOffset = .zero
            glow.set()
            bar.fillGradient(start: topColor, end: bottomColor, angle: 90)
            NSGraphicsContext.restoreGraphicsState()

            let highlightRect = barRect.insetBy(dx: 14, dy: 18)
            let highlight = NSBezierPath(
                roundedRect: NSRect(
                    x: highlightRect.minX,
                    y: highlightRect.midY,
                    width: highlightRect.width,
                    height: max(18, highlightRect.height * 0.40)
                ),
                xRadius: highlightRect.width / 2,
                yRadius: highlightRect.width / 2
            )
            NSColor.white.withAlphaComponent(0.14).setFill()
            highlight.fill()
        }

        drawSubtleSpectrumFloor(accent: accent, secondary: secondary)
    }

    private static func drawSubtleSpectrumFloor(accent: NSColor, secondary: NSColor) {
        let baselineY: CGFloat = 210
        let count = 27
        let width: CGFloat = 11
        let gap: CGFloat = 12
        let totalWidth = CGFloat(count) * width + CGFloat(count - 1) * gap
        let startX = (canvasSize - totalWidth) / 2

        for index in 0..<count {
            let phase = CGFloat(index) / CGFloat(count - 1)
            let level = 0.25 + (sin(phase * .pi) * 0.75)
            let height = 18 + (level * 72)
            let x = startX + CGFloat(index) * (width + gap)
            let rect = NSRect(x: x, y: baselineY, width: width, height: height)
            let bar = NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2)
            let color = accent.mixed(with: secondary, amount: phase)
            color.withAlphaComponent(0.13).setFill()
            bar.fill()
        }
    }

    private static func drawGlassFinish(theme: OmniVoiceTheme, palette: ResolvedThemePalette) {
        let accent = NSColor(themeColor: palette.accentGraphic)
        let shell = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 214, yRadius: 214)

        let topSheen = NSBezierPath()
        topSheen.move(to: NSPoint(x: 178, y: 840))
        topSheen.curve(
            to: NSPoint(x: 846, y: 822),
            controlPoint1: NSPoint(x: 338, y: 910),
            controlPoint2: NSPoint(x: 646, y: 918)
        )
        topSheen.lineWidth = 8
        NSColor.white.withAlphaComponent(0.08).setStroke()
        topSheen.stroke()

        shell.lineWidth = 5
        accent.withAlphaComponent(0.28).setStroke()
        shell.stroke()
    }
}

private extension NSBezierPath {
    func fillGradient(start: NSColor, end: NSColor, angle: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        addClip()
        NSGradient(starting: start, ending: end)?.draw(in: bounds, angle: angle)
        NSGraphicsContext.restoreGraphicsState()
    }
}

private extension NSColor {
    convenience init(themeColor: ThemeColor) {
        let rawValue = String(themeColor.hex.dropFirst(themeColor.hex.hasPrefix("#") ? 1 : 0))
        let fallback = 0x38BDF8
        let value = rawValue.count == 6 ? Int(rawValue, radix: 16) ?? fallback : fallback
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }

    func mixed(with target: NSColor, amount: CGFloat) -> NSColor {
        guard let source = usingColorSpace(.sRGB),
              let target = target.usingColorSpace(.sRGB) else {
            return self
        }

        let clampedAmount = min(max(amount, 0), 1)
        return NSColor(
            srgbRed: source.redComponent + ((target.redComponent - source.redComponent) * clampedAmount),
            green: source.greenComponent + ((target.greenComponent - source.greenComponent) * clampedAmount),
            blue: source.blueComponent + ((target.blueComponent - source.blueComponent) * clampedAmount),
            alpha: source.alphaComponent + ((target.alphaComponent - source.alphaComponent) * clampedAmount)
        )
    }
}
