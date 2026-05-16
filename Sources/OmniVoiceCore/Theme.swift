import Foundation

public enum OmniVoiceThemeID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case auroraBlue
    case obsidianCyan
    case deepSignal
    case arcticGlass
    case cobaltPulse
    case neonLime
    case acidGlass
    case emeraldVoice
    case matrixSoft
    case prismBlue
    case prismPink
    case violetBeam
    case magentaGlass
    case emberWave
    case solarTrace
    case redline
    case graphiteIce
    case steelWhisper
    case monoGlass
    case highContrast
    case custom
}

public enum WaveformMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case bars
    case pulseRing
    case spectrumLine
    case orbMeter
    case glyphStream

    public var displayName: String {
        switch self {
        case .bars:
            "Bars"
        case .pulseRing:
            "Pulse Ring"
        case .spectrumLine:
            "Spectrum Line"
        case .orbMeter:
            "Orb Meter"
        case .glyphStream:
            "Glyph Stream"
        }
    }
}

public enum CommitAnimationMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case glyphStream
    case beamSnap
    case cometCollapse
    case none

    public var displayName: String {
        switch self {
        case .glyphStream:
            "Glyph Stream"
        case .beamSnap:
            "Beam Snap"
        case .cometCollapse:
            "Comet Collapse"
        case .none:
            "None"
        }
    }
}

public enum EngineFrameSide: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case left
    case right

    public var displayName: String {
        switch self {
        case .left:
            "Left"
        case .right:
            "Right"
        }
    }
}

public enum ThemeContrastMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case standard
    case elevated
    case highContrast

    public var displayName: String {
        switch self {
        case .standard:
            "Standard"
        case .elevated:
            "Elevated"
        case .highContrast:
            "High Contrast"
        }
    }
}

public struct ThemeColor: Codable, Equatable, Hashable, Sendable {
    public let hex: String

    public init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixed = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        self.hex = prefixed.uppercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hex: try container.decode(String.self, forKey: .hex))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hex, forKey: .hex)
    }

    private enum CodingKeys: String, CodingKey {
        case hex
    }

    fileprivate var rgb: (red: Int, green: Int, blue: Int)? {
        let value = String(hex.dropFirst())
        guard value.count == 6, let number = Int(value, radix: 16) else {
            return nil
        }

        return (
            red: (number >> 16) & 0xFF,
            green: (number >> 8) & 0xFF,
            blue: number & 0xFF
        )
    }

    public static func cssRGBA(red: Int, green: Int, blue: Int, alpha: Double) -> String {
        "rgba(\(red), \(green), \(blue), \(opacityString(alpha)))"
    }

    fileprivate static func cssRGBA(_ color: ThemeColor, alpha: Double) -> String {
        guard let rgb = color.rgb else {
            return cssRGBA(red: 0, green: 0, blue: 0, alpha: alpha)
        }

        return cssRGBA(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    private static func opacityString(_ value: Double) -> String {
        String(format: "%.2f", min(max(value, 0.0), 1.0))
    }
}

public struct OmniVoiceTheme: Codable, Equatable, Sendable, Identifiable {
    public let id: OmniVoiceThemeID
    public let name: String
    public let accentColor: ThemeColor
    public let secondaryAccentColor: ThemeColor
    public let surfaceTint: ThemeColor
    public let glassOpacity: Double
    public let captionOpacity: Double
    public let glowStrength: Double
    public let contrastMode: ThemeContrastMode
    public let waveformMode: WaveformMode
    public let commitAnimationMode: CommitAnimationMode
    public let engineFrameSide: EngineFrameSide
    public let motionIntensity: Double

    public init(
        id: OmniVoiceThemeID,
        name: String,
        accentColor: ThemeColor,
        secondaryAccentColor: ThemeColor,
        surfaceTint: ThemeColor,
        glassOpacity: Double,
        captionOpacity: Double,
        glowStrength: Double,
        contrastMode: ThemeContrastMode,
        waveformMode: WaveformMode,
        commitAnimationMode: CommitAnimationMode,
        engineFrameSide: EngineFrameSide,
        motionIntensity: Double
    ) {
        self.id = id
        self.name = name
        self.accentColor = accentColor
        self.secondaryAccentColor = secondaryAccentColor
        self.surfaceTint = surfaceTint
        self.glassOpacity = glassOpacity
        self.captionOpacity = captionOpacity
        self.glowStrength = glowStrength
        self.contrastMode = contrastMode
        self.waveformMode = waveformMode
        self.commitAnimationMode = commitAnimationMode
        self.engineFrameSide = engineFrameSide
        self.motionIntensity = motionIntensity
    }

    public static let builtIn: [OmniVoiceTheme] = [
        .preset(.auroraBlue, "Aurora Blue", "#38BDF8", "#818CF8", "#06121C", 0.36, 0.14, 0.34, .standard, .bars, .glyphStream, .right, 0.74),
        .preset(.obsidianCyan, "Obsidian Cyan", "#22D3EE", "#0EA5E9", "#071115", 0.38, 0.16, 0.32, .standard, .pulseRing, .beamSnap, .right, 0.68),
        .preset(.deepSignal, "Deep Signal", "#60A5FA", "#14B8A6", "#08111F", 0.34, 0.15, 0.30, .standard, .spectrumLine, .glyphStream, .left, 0.66),
        .preset(.arcticGlass, "Arctic Glass", "#7DD3FC", "#C4B5FD", "#EAF6FF", 0.32, 0.18, 0.28, .elevated, .orbMeter, .beamSnap, .right, 0.58),
        .preset(.cobaltPulse, "Cobalt Pulse", "#2563EB", "#06B6D4", "#08163A", 0.40, 0.17, 0.36, .standard, .pulseRing, .cometCollapse, .right, 0.78),
        .preset(.neonLime, "Neon Lime", "#A3E635", "#22C55E", "#0B160A", 0.35, 0.16, 0.34, .standard, .bars, .beamSnap, .left, 0.72),
        .preset(.acidGlass, "Acid Glass", "#D9F99D", "#84CC16", "#16210B", 0.37, 0.18, 0.31, .elevated, .orbMeter, .glyphStream, .right, 0.63),
        .preset(.emeraldVoice, "Emerald Voice", "#34D399", "#2DD4BF", "#071C16", 0.36, 0.15, 0.33, .standard, .spectrumLine, .beamSnap, .left, 0.70),
        .preset(.matrixSoft, "Matrix Soft", "#4ADE80", "#A3E635", "#06150B", 0.34, 0.14, 0.29, .standard, .glyphStream, .glyphStream, .right, 0.61),
        .preset(.prismBlue, "Prism Blue", "#3B82F6", "#38BDF8", "#071427", 0.35, 0.15, 0.33, .standard, .bars, .cometCollapse, .right, 0.75),
        .preset(.prismPink, "Prism Pink", "#F472B6", "#A78BFA", "#1E0B18", 0.38, 0.17, 0.35, .standard, .pulseRing, .glyphStream, .right, 0.76),
        .preset(.violetBeam, "Violet Beam", "#8B5CF6", "#22D3EE", "#130D26", 0.37, 0.16, 0.34, .standard, .spectrumLine, .beamSnap, .left, 0.73),
        .preset(.magentaGlass, "Magenta Glass", "#D946EF", "#F0ABFC", "#200A20", 0.39, 0.18, 0.36, .elevated, .orbMeter, .cometCollapse, .right, 0.69),
        .preset(.emberWave, "Ember Wave", "#FB923C", "#F97316", "#201006", 0.36, 0.16, 0.34, .standard, .bars, .beamSnap, .left, 0.71),
        .preset(.solarTrace, "Solar Trace", "#FACC15", "#FB923C", "#201A05", 0.34, 0.17, 0.31, .elevated, .spectrumLine, .glyphStream, .right, 0.62),
        .preset(.redline, "Redline", "#F43F5E", "#FB7185", "#22080D", 0.38, 0.16, 0.37, .standard, .pulseRing, .cometCollapse, .left, 0.80),
        .preset(.graphiteIce, "Graphite Ice", "#CBD5E1", "#38BDF8", "#111827", 0.33, 0.14, 0.24, .elevated, .bars, .none, .right, 0.42),
        .preset(.steelWhisper, "Steel Whisper", "#94A3B8", "#67E8F9", "#0F172A", 0.31, 0.13, 0.22, .standard, .spectrumLine, .none, .left, 0.38),
        .preset(.monoGlass, "Mono Glass", "#F8FAFC", "#94A3B8", "#0A0A0A", 0.30, 0.12, 0.18, .elevated, .orbMeter, .none, .right, 0.32),
        .preset(.highContrast, "High Contrast", "#FFFFFF", "#FACC15", "#000000", 0.44, 0.22, 0.42, .highContrast, .bars, .beamSnap, .right, 0.55)
    ]

    public static let defaultTheme = builtInTheme(id: .auroraBlue)!

    public static func builtInTheme(id: OmniVoiceThemeID) -> OmniVoiceTheme? {
        builtIn.first { $0.id == id }
    }

    public static func custom(accent: ThemeColor) -> OmniVoiceTheme {
        OmniVoiceTheme(
            id: .custom,
            name: "Custom",
            accentColor: accent,
            secondaryAccentColor: accent,
            surfaceTint: ThemeColor(hex: "#06121C"),
            glassOpacity: 0.36,
            captionOpacity: 0.14,
            glowStrength: 0.34,
            contrastMode: .standard,
            waveformMode: .bars,
            commitAnimationMode: .glyphStream,
            engineFrameSide: .right,
            motionIntensity: 0.70
        )
    }

    public func withModes(
        waveformMode: WaveformMode,
        commitAnimationMode: CommitAnimationMode,
        engineFrameSide: EngineFrameSide
    ) -> OmniVoiceTheme {
        OmniVoiceTheme(
            id: id,
            name: name,
            accentColor: accentColor,
            secondaryAccentColor: secondaryAccentColor,
            surfaceTint: surfaceTint,
            glassOpacity: glassOpacity,
            captionOpacity: captionOpacity,
            glowStrength: glowStrength,
            contrastMode: contrastMode,
            waveformMode: waveformMode,
            commitAnimationMode: commitAnimationMode,
            engineFrameSide: engineFrameSide,
            motionIntensity: motionIntensity
        )
    }

    public var borderOpacity: Double {
        0.26
    }

    public var textColor: ThemeColor {
        if contrastMode == .highContrast {
            return ThemeColor(hex: "#FFFFFF")
        }

        guard let rgb = surfaceTint.rgb else {
            return ThemeColor(hex: "#F8FAFC")
        }

        let luminance = (0.2126 * Double(rgb.red) + 0.7152 * Double(rgb.green) + 0.0722 * Double(rgb.blue)) / 255.0
        return luminance > 0.60 ? ThemeColor(hex: "#06121C") : ThemeColor(hex: "#F8FAFC")
    }

    public var mutedTextColor: ThemeColor {
        textColor
    }

    public var mutedTextOpacity: Double {
        0.64
    }

    public var cssVariables: [String: String] {
        [
            "--ov-accent": accentColor.hex,
            "--ov-accent-secondary": secondaryAccentColor.hex,
            "--ov-bg": surfaceTint.hex,
            "--ov-surface": rgba(surfaceTint, glassOpacity),
            "--ov-surface-strong": rgba(surfaceTint, min(glassOpacity + 0.18, 1.0)),
            "--ov-text": textColor.hex,
            "--ov-muted": rgba(mutedTextColor, mutedTextOpacity),
            "--ov-border": rgba(accentColor, borderOpacity),
            "--ov-glow": rgba(accentColor, glowStrength),
            "--ov-caption-bg": rgba(surfaceTint, captionOpacity)
        ]
    }

    private static func preset(
        _ id: OmniVoiceThemeID,
        _ name: String,
        _ accentColor: String,
        _ secondaryAccentColor: String,
        _ surfaceTint: String,
        _ glassOpacity: Double,
        _ captionOpacity: Double,
        _ glowStrength: Double,
        _ contrastMode: ThemeContrastMode,
        _ waveformMode: WaveformMode,
        _ commitAnimationMode: CommitAnimationMode,
        _ engineFrameSide: EngineFrameSide,
        _ motionIntensity: Double
    ) -> OmniVoiceTheme {
        OmniVoiceTheme(
            id: id,
            name: name,
            accentColor: ThemeColor(hex: accentColor),
            secondaryAccentColor: ThemeColor(hex: secondaryAccentColor),
            surfaceTint: ThemeColor(hex: surfaceTint),
            glassOpacity: glassOpacity,
            captionOpacity: captionOpacity,
            glowStrength: glowStrength,
            contrastMode: contrastMode,
            waveformMode: waveformMode,
            commitAnimationMode: commitAnimationMode,
            engineFrameSide: engineFrameSide,
            motionIntensity: motionIntensity
        )
    }

    private func rgba(_ color: ThemeColor, _ alpha: Double) -> String {
        ThemeColor.cssRGBA(color, alpha: alpha)
    }
}
