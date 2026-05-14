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

public struct HotkeyBinding: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultDictation = HotkeyBinding(keyCode: 49, modifiers: 2_304)
    public static let defaultStyle = HotkeyBinding(keyCode: 1, modifiers: 2_304)
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
