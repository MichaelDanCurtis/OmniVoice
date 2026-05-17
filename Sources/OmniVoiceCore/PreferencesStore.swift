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
    public var appearanceMode: AppAppearanceMode
    public var waveformMode: WaveformMode
    public var commitAnimationMode: CommitAnimationMode
    public var engineFrameSide: EngineFrameSide
    public var engineFrameHandlePosition: Double
    public var customSpeechModelPath: String
    public var customTranslationModelPath: String
    public var liveTranslationEnabled: Bool
    public var translationSourceLanguage: String
    public var translationTargetLanguage: String
    public var aiProviderPresetID: AIProviderPresetID
    public var openAICompatibleBaseURL: String
    public var openAICompatibleModel: String
    public var liveDraftInsertionEnabled: Bool

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
        appearanceMode: .system,
        waveformMode: .bars,
        commitAnimationMode: .glyphStream,
        engineFrameSide: .right,
        engineFrameHandlePosition: 0.5,
        customSpeechModelPath: "",
        customTranslationModelPath: "",
        liveTranslationEnabled: false,
        translationSourceLanguage: "auto",
        translationTargetLanguage: "en",
        aiProviderPresetID: .custom,
        openAICompatibleBaseURL: "",
        openAICompatibleModel: "",
        liveDraftInsertionEnabled: false
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
        appearanceMode: AppAppearanceMode = .system,
        waveformMode: WaveformMode = .bars,
        commitAnimationMode: CommitAnimationMode = .glyphStream,
        engineFrameSide: EngineFrameSide = .right,
        engineFrameHandlePosition: Double = 0.5,
        customSpeechModelPath: String = "",
        customTranslationModelPath: String = "",
        liveTranslationEnabled: Bool = false,
        translationSourceLanguage: String = "auto",
        translationTargetLanguage: String = "en",
        aiProviderPresetID: AIProviderPresetID = .custom,
        openAICompatibleBaseURL: String = "",
        openAICompatibleModel: String = "",
        liveDraftInsertionEnabled: Bool = false
    ) {
        self.asrProvider = asrProvider
        self.style = style
        self.dictionaryTerms = dictionaryTerms
        self.microphoneId = microphoneID
        self.dictationHotkey = dictationHotkey
        self.styleHotkey = styleHotkey
        self.themeID = themeID
        self.customAccentColor = customAccentColor
        self.appearanceMode = appearanceMode
        self.waveformMode = waveformMode
        self.commitAnimationMode = commitAnimationMode
        self.engineFrameSide = engineFrameSide
        self.engineFrameHandlePosition = Self.clampedHandlePosition(engineFrameHandlePosition)
        self.customSpeechModelPath = customSpeechModelPath
        self.customTranslationModelPath = customTranslationModelPath
        self.liveTranslationEnabled = liveTranslationEnabled
        self.translationSourceLanguage = translationSourceLanguage
        self.translationTargetLanguage = translationTargetLanguage
        self.aiProviderPresetID = aiProviderPresetID
        self.openAICompatibleBaseURL = openAICompatibleBaseURL
        self.openAICompatibleModel = openAICompatibleModel
        self.liveDraftInsertionEnabled = liveDraftInsertionEnabled
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let acronymContainer = try decoder.container(keyedBy: AcronymCodingKeys.self)
            try self.init(snakeCaseContainer: container, acronymContainer: acronymContainer)
        } catch DecodingError.keyNotFound {
            let container = try decoder.container(keyedBy: ConvertedCodingKeys.self)
            try self.init(convertedContainer: container)
        }
    }

    private init(
        snakeCaseContainer container: KeyedDecodingContainer<CodingKeys>,
        acronymContainer: KeyedDecodingContainer<AcronymCodingKeys>
    ) throws {
        self.init(
            asrProvider: try container.decode(ASRProviderKind.self, forKey: .asrProvider),
            style: try container.decode(StyleProfile.self, forKey: .style),
            dictionaryTerms: try container.decode([String].self, forKey: .dictionaryTerms),
            microphoneID: try container.decodeIfPresent(String.self, forKey: .microphoneId),
            dictationHotkey: try container.decode(HotkeyBinding.self, forKey: .dictationHotkey),
            styleHotkey: try container.decode(HotkeyBinding.self, forKey: .styleHotkey),
            themeID: try container.decodeIfPresent(OmniVoiceThemeID.self, forKey: .themeID) ?? .auroraBlue,
            customAccentColor: try container.decodeIfPresent(ThemeColor.self, forKey: .customAccentColor) ?? ThemeColor(hex: "#38BDF8"),
            appearanceMode: try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system,
            waveformMode: try container.decodeIfPresent(WaveformMode.self, forKey: .waveformMode) ?? .bars,
            commitAnimationMode: try container.decodeIfPresent(CommitAnimationMode.self, forKey: .commitAnimationMode) ?? .glyphStream,
            engineFrameSide: try container.decodeIfPresent(EngineFrameSide.self, forKey: .engineFrameSide) ?? .right,
            engineFrameHandlePosition: try container.decodeIfPresent(Double.self, forKey: .engineFrameHandlePosition) ?? 0.5,
            customSpeechModelPath: try container.decodeIfPresent(String.self, forKey: .customSpeechModelPath) ?? "",
            customTranslationModelPath: try container.decodeIfPresent(String.self, forKey: .customTranslationModelPath) ?? "",
            liveTranslationEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveTranslationEnabled) ?? false,
            translationSourceLanguage: try container.decodeIfPresent(String.self, forKey: .translationSourceLanguage) ?? "auto",
            translationTargetLanguage: try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? "en",
            aiProviderPresetID: try container.decodeIfPresent(AIProviderPresetID.self, forKey: .aiProviderPresetID)
                ?? acronymContainer.decodeIfPresent(AIProviderPresetID.self, forKey: .aiProviderPresetID)
                ?? .custom,
            openAICompatibleBaseURL: try container.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL)
                ?? acronymContainer.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL)
                ?? "",
            openAICompatibleModel: try container.decodeIfPresent(String.self, forKey: .openAICompatibleModel)
                ?? acronymContainer.decodeIfPresent(String.self, forKey: .openAICompatibleModel)
                ?? "",
            liveDraftInsertionEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveDraftInsertionEnabled) ?? false
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
            appearanceMode: try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system,
            waveformMode: try container.decodeIfPresent(WaveformMode.self, forKey: .waveformMode) ?? .bars,
            commitAnimationMode: try container.decodeIfPresent(CommitAnimationMode.self, forKey: .commitAnimationMode) ?? .glyphStream,
            engineFrameSide: try container.decodeIfPresent(EngineFrameSide.self, forKey: .engineFrameSide) ?? .right,
            engineFrameHandlePosition: try container.decodeIfPresent(Double.self, forKey: .engineFrameHandlePosition) ?? 0.5,
            customSpeechModelPath: try container.decodeIfPresent(String.self, forKey: .customSpeechModelPath) ?? "",
            customTranslationModelPath: try container.decodeIfPresent(String.self, forKey: .customTranslationModelPath) ?? "",
            liveTranslationEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveTranslationEnabled) ?? false,
            translationSourceLanguage: try container.decodeIfPresent(String.self, forKey: .translationSourceLanguage) ?? "auto",
            translationTargetLanguage: try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? "en",
            aiProviderPresetID: try container.decodeIfPresent(AIProviderPresetID.self, forKey: .aiProviderPresetID) ?? .custom,
            openAICompatibleBaseURL: try container.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL) ?? "",
            openAICompatibleModel: try container.decodeIfPresent(String.self, forKey: .openAICompatibleModel) ?? "",
            liveDraftInsertionEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveDraftInsertionEnabled) ?? false
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

    public static func clampedHandlePosition(_ value: Double) -> Double {
        min(max(value, 0.08), 0.92)
    }

    public mutating func applyAIProviderPreset(_ preset: AIProviderPreset) {
        aiProviderPresetID = preset.id
        openAICompatibleBaseURL = preset.baseURL
        if !preset.defaultModel.isEmpty {
            openAICompatibleModel = preset.defaultModel
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
        case appearanceMode = "appearance_mode"
        case waveformMode = "waveform_mode"
        case commitAnimationMode = "commit_animation_mode"
        case engineFrameSide = "engine_frame_side"
        case engineFrameHandlePosition = "engine_frame_handle_position"
        case customSpeechModelPath = "custom_speech_model_path"
        case customTranslationModelPath = "custom_translation_model_path"
        case liveTranslationEnabled = "live_translation_enabled"
        case translationSourceLanguage = "translation_source_language"
        case translationTargetLanguage = "translation_target_language"
        case aiProviderPresetID = "ai_provider_preset_id"
        case openAICompatibleBaseURL = "open_ai_compatible_base_url"
        case openAICompatibleModel = "open_ai_compatible_model"
        case liveDraftInsertionEnabled = "live_draft_insertion_enabled"
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
        case appearanceMode
        case waveformMode
        case commitAnimationMode
        case engineFrameSide
        case engineFrameHandlePosition
        case customSpeechModelPath
        case customTranslationModelPath
        case liveTranslationEnabled
        case translationSourceLanguage
        case translationTargetLanguage
        case aiProviderPresetID = "aiProviderPresetId"
        case openAICompatibleBaseURL = "openAiCompatibleBaseUrl"
        case openAICompatibleModel = "openAiCompatibleModel"
        case liveDraftInsertionEnabled
    }

    private enum AcronymCodingKeys: String, CodingKey {
        case aiProviderPresetID = "aiProviderPresetId"
        case openAICompatibleBaseURL = "openAiCompatibleBaseUrl"
        case openAICompatibleModel = "openAiCompatibleModel"
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

    public func legacyOpenAICompatibleAPIKey() -> String? {
        guard let data = userDefaults.data(forKey: key),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let candidates = [
            object["open_ai_compatible_api_key"],
            object["openAiCompatibleApiKey"],
            object["openAICompatibleAPIKey"],
        ]
        return candidates.compactMap { $0 as? String }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
