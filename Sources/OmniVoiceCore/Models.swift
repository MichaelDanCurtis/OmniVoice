import Foundation

public enum StyleProfile: String, CaseIterable, Codable, Equatable, Sendable {
    case neutral = "neutral"
    case professional = "professional"
    case concise = "concise"
    case expanded = "expanded"
    case raw = "raw"

    public var displayName: String {
        switch self {
        case .neutral:
            "Neutral"
        case .professional:
            "Professional"
        case .concise:
            "Concise"
        case .expanded:
            "Expanded"
        case .raw:
            "Raw Dictation"
        }
    }

    public func next() -> StyleProfile {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }
}

public enum ASRProviderKind: String, CaseIterable, Codable, Equatable, Sendable {
    case fake = "fake"
    case parakeetTDT = "parakeet-tdt"
    case canaryQwen25B = "canary-qwen-2.5b"
}

public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultDictation = HotkeyBinding(keyCode: 49, modifiers: 2_304)
    public static let defaultStyle = HotkeyBinding(keyCode: 1, modifiers: 2_304)
    public static let dictationPresets = [
        HotkeyBinding(keyCode: 49, modifiers: 2_304),
        HotkeyBinding(keyCode: 2, modifiers: 2_304),
        HotkeyBinding(keyCode: 3, modifiers: 2_304),
        HotkeyBinding(keyCode: 49, modifiers: 6_144),
    ]
    public static let stylePresets = [
        HotkeyBinding(keyCode: 1, modifiers: 2_304),
        HotkeyBinding(keyCode: 17, modifiers: 2_304),
        HotkeyBinding(keyCode: 16, modifiers: 2_304),
        HotkeyBinding(keyCode: 1, modifiers: 6_144),
    ]

    public var displayName: String {
        "\(modifierDisplayName)\(keyDisplayName)"
    }

    public var hasModifier: Bool {
        modifiers & 6_912 != 0
    }

    public static func carbonModifiers(
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) -> UInt32 {
        var result: UInt32 = 0
        if command { result |= 256 }
        if option { result |= 2_048 }
        if control { result |= 4_096 }
        if shift { result |= 512 }
        return result
    }

    private var modifierDisplayName: String {
        var parts: [String] = []
        if modifiers & 4_096 != 0 { parts.append("⌃") }
        if modifiers & 2_048 != 0 { parts.append("⌥") }
        if modifiers & 512 != 0 { parts.append("⇧") }
        if modifiers & 256 != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private var keyDisplayName: String {
        switch keyCode {
        case 49: "Space"
        case 36: "Return"
        case 48: "Tab"
        case 51: "Delete"
        case 53: "Esc"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 23: "5"
        case 22: "6"
        case 26: "7"
        case 28: "8"
        case 25: "9"
        case 29: "0"
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 4: "H"
        case 5: "G"
        case 6: "Z"
        case 7: "X"
        case 8: "C"
        case 9: "V"
        case 11: "B"
        case 12: "Q"
        case 13: "W"
        case 14: "E"
        case 15: "R"
        case 16: "Y"
        case 17: "T"
        case 31: "O"
        case 32: "U"
        case 34: "I"
        case 35: "P"
        case 37: "L"
        case 38: "J"
        case 40: "K"
        case 45: "N"
        case 46: "M"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: "Key \(keyCode)"
        }
    }
}

public struct TranscriptUpdate: Codable, Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public struct CleanupRequest: Codable, Equatable, Sendable {
    public let rawTranscript: String
    public let style: StyleProfile
    public let dictionaryTerms: [String]

    public init(rawTranscript: String, style: StyleProfile, dictionaryTerms: [String] = []) {
        self.rawTranscript = rawTranscript
        self.style = style
        self.dictionaryTerms = dictionaryTerms
    }
}

public struct CleanupResult: Codable, Equatable, Sendable {
    public let text: String
    public let cleanupApplied: Bool

    public init(text: String, cleanupApplied: Bool) {
        self.text = text
        self.cleanupApplied = cleanupApplied
    }
}
