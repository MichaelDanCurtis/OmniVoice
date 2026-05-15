import Foundation

public struct OmniVoicePreferences: Codable, Equatable, Sendable {
    public var asrProvider: ASRProviderKind
    public var style: StyleProfile
    public var dictionaryTerms: [String]
    public var microphoneId: String?
    public var dictationHotkey: HotkeyBinding
    public var styleHotkey: HotkeyBinding

    public var microphoneID: String? {
        get { microphoneId }
        set { microphoneId = newValue }
    }

    public static let defaults = OmniVoicePreferences(
        asrProvider: .parakeetTDT,
        style: .neutral,
        dictionaryTerms: [],
        microphoneID: nil,
        dictationHotkey: .defaultDictation,
        styleHotkey: .defaultStyle
    )

    public init(
        asrProvider: ASRProviderKind,
        style: StyleProfile,
        dictionaryTerms: [String],
        microphoneID: String? = nil,
        dictationHotkey: HotkeyBinding = .defaultDictation,
        styleHotkey: HotkeyBinding = .defaultStyle
    ) {
        self.asrProvider = asrProvider
        self.style = style
        self.dictionaryTerms = dictionaryTerms
        self.microphoneId = microphoneID
        self.dictationHotkey = dictationHotkey
        self.styleHotkey = styleHotkey
    }

    public mutating func cycleStyle() {
        style = style.next()
    }

    public mutating func cycleASRProvider() {
        switch asrProvider {
        case .parakeetTDT:
            asrProvider = .canaryQwen25B
        case .canaryQwen25B:
            asrProvider = .fake
        case .fake:
            asrProvider = .parakeetTDT
        }
    }
}

public struct PreferencesStore {
    public enum StoreError: Error, Equatable {
        case decodingFailed
    }

    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "omnivoice.preferences"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func load() throws -> OmniVoicePreferences {
        guard let data = userDefaults.data(forKey: key) else {
            return .defaults
        }

        do {
            return try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: data)
        } catch {
            throw StoreError.decodingFailed
        }
    }

    public func save(_ preferences: OmniVoicePreferences) throws {
        let data = try EngineCoding.encoder.encode(preferences)
        userDefaults.set(data, forKey: key)
    }
}
