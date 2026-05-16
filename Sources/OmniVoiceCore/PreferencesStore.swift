import Foundation

public struct OmniVoicePreferences: Codable, Equatable, Sendable {
    public var asrProvider: ASRProviderKind
    public var style: StyleProfile
    public var dictionaryTerms: [String]
    public var microphoneId: String?
    public var dictationHotkey: HotkeyBinding
    public var styleHotkey: HotkeyBinding
    public var themeID: OmniVoiceThemeID
    public var customAccentColor: ThemeColor
    public var waveformMode: WaveformMode
    public var commitAnimationMode: CommitAnimationMode
    public var engineFrameSide: EngineFrameSide

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
        styleHotkey: .defaultStyle,
        themeID: .auroraBlue,
        customAccentColor: ThemeColor(hex: "#38BDF8"),
        waveformMode: .bars,
        commitAnimationMode: .glyphStream,
        engineFrameSide: .right
    )

    public init(
        asrProvider: ASRProviderKind,
        style: StyleProfile,
        dictionaryTerms: [String],
        microphoneID: String? = nil,
        dictationHotkey: HotkeyBinding = .defaultDictation,
        styleHotkey: HotkeyBinding = .defaultStyle,
        themeID: OmniVoiceThemeID = .auroraBlue,
        customAccentColor: ThemeColor = ThemeColor(hex: "#38BDF8"),
        waveformMode: WaveformMode = .bars,
        commitAnimationMode: CommitAnimationMode = .glyphStream,
        engineFrameSide: EngineFrameSide = .right
    ) {
        self.asrProvider = asrProvider
        self.style = style
        self.dictionaryTerms = dictionaryTerms
        self.microphoneId = microphoneID
        self.dictationHotkey = dictationHotkey
        self.styleHotkey = styleHotkey
        self.themeID = themeID
        self.customAccentColor = customAccentColor
        self.waveformMode = waveformMode
        self.commitAnimationMode = commitAnimationMode
        self.engineFrameSide = engineFrameSide
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(snakeCaseContainer: container)
        } catch DecodingError.keyNotFound {
            let container = try decoder.container(keyedBy: ConvertedCodingKeys.self)
            try self.init(convertedContainer: container)
        }
    }

    private init(snakeCaseContainer container: KeyedDecodingContainer<CodingKeys>) throws {
        self.init(
            asrProvider: try container.decode(ASRProviderKind.self, forKey: .asrProvider),
            style: try container.decode(StyleProfile.self, forKey: .style),
            dictionaryTerms: try container.decode([String].self, forKey: .dictionaryTerms),
            microphoneID: try container.decodeIfPresent(String.self, forKey: .microphoneId),
            dictationHotkey: try container.decode(HotkeyBinding.self, forKey: .dictationHotkey),
            styleHotkey: try container.decode(HotkeyBinding.self, forKey: .styleHotkey),
            themeID: try container.decodeIfPresent(OmniVoiceThemeID.self, forKey: .themeID) ?? .auroraBlue,
            customAccentColor: try container.decodeIfPresent(ThemeColor.self, forKey: .customAccentColor) ?? ThemeColor(hex: "#38BDF8"),
            waveformMode: try container.decodeIfPresent(WaveformMode.self, forKey: .waveformMode) ?? .bars,
            commitAnimationMode: try container.decodeIfPresent(CommitAnimationMode.self, forKey: .commitAnimationMode) ?? .glyphStream,
            engineFrameSide: try container.decodeIfPresent(EngineFrameSide.self, forKey: .engineFrameSide) ?? .right
        )
    }

    private init(convertedContainer container: KeyedDecodingContainer<ConvertedCodingKeys>) throws {
        self.init(
            asrProvider: try container.decode(ASRProviderKind.self, forKey: .asrProvider),
            style: try container.decode(StyleProfile.self, forKey: .style),
            dictionaryTerms: try container.decode([String].self, forKey: .dictionaryTerms),
            microphoneID: try container.decodeIfPresent(String.self, forKey: .microphoneId),
            dictationHotkey: try container.decode(HotkeyBinding.self, forKey: .dictationHotkey),
            styleHotkey: try container.decode(HotkeyBinding.self, forKey: .styleHotkey),
            themeID: try container.decodeIfPresent(OmniVoiceThemeID.self, forKey: .themeID) ?? .auroraBlue,
            customAccentColor: try container.decodeIfPresent(ThemeColor.self, forKey: .customAccentColor) ?? ThemeColor(hex: "#38BDF8"),
            waveformMode: try container.decodeIfPresent(WaveformMode.self, forKey: .waveformMode) ?? .bars,
            commitAnimationMode: try container.decodeIfPresent(CommitAnimationMode.self, forKey: .commitAnimationMode) ?? .glyphStream,
            engineFrameSide: try container.decodeIfPresent(EngineFrameSide.self, forKey: .engineFrameSide) ?? .right
        )
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

    private enum CodingKeys: String, CodingKey {
        case asrProvider = "asr_provider"
        case style = "style"
        case dictionaryTerms = "dictionary_terms"
        case microphoneId = "microphone_id"
        case dictationHotkey = "dictation_hotkey"
        case styleHotkey = "style_hotkey"
        case themeID = "theme_id"
        case customAccentColor = "custom_accent_color"
        case waveformMode = "waveform_mode"
        case commitAnimationMode = "commit_animation_mode"
        case engineFrameSide = "engine_frame_side"
    }

    private enum ConvertedCodingKeys: String, CodingKey {
        case asrProvider
        case style
        case dictionaryTerms
        case microphoneId
        case dictationHotkey
        case styleHotkey
        case themeID = "themeId"
        case customAccentColor
        case waveformMode
        case commitAnimationMode
        case engineFrameSide
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
