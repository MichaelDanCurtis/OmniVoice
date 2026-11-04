import Foundation

public struct OmniVoicePreferences: Codable, Equatable, Sendable {
    public static let translationQuickTargetLanguageSlotCount = 4
    public static let maxAdditionalDictationHotkeys = 3
    public static let defaultTranslationQuickTargetLanguages = ["zh", "fr", "en"]

    public var asrProvider: ASRProviderKind
    public var style: StyleProfile
    public var dictionaryTerms: [String]
    public var microphoneId: String?
    public var dictationHotkey: HotkeyBinding
    public var additionalDictationHotkeys: [HotkeyBinding]
    public var styleHotkey: HotkeyBinding
    public var hotMenuHotkey: HotkeyBinding
    public var transcriptCacheHotkey: HotkeyBinding
    public var mousePushToTalkEnabled: Bool
    public var mousePushToTalkButton: MouseButtonBinding
    public var transcriptCacheMouseEnabled: Bool
    public var transcriptCacheMouseButton: MouseButtonBinding
    public var hotMenuUpActions: [HotMenuAction]
    public var hotMenuLeftActions: [HotMenuAction]
    public var hotMenuRightActions: [HotMenuAction]
    public var hotMenuDownActions: [HotMenuAction]
    public var themeID: OmniVoiceThemeID
    public var customAccentColor: ThemeColor
    public var appearanceMode: AppAppearanceMode
    public var waveformMode: WaveformMode
    public var commitAnimationMode: CommitAnimationMode
    public var engineFrameSide: EngineFrameSide
    public var engineFrameHandlePosition: Double
    public var customSpeechModelPath: String
    public var customTranslationModelPath: String
    public var translationProvider: TranslationProviderKind
    public var translationModelProviderID: String
    public var conversationDiarizationProvider: String
    public var conversationDiarizationPrecision: DiarizationPrecision
    public var liveConversationDiarizationEnabled: Bool
    public var liveTranslationEnabled: Bool
    public var translationSourceLanguage: String
    public var translationTargetLanguage: String
    public var translationQuickTargetLanguages: [String]
    public var openAICompatibleBaseURL: String
    public var openAICompatibleModel: String
    public var openAICompatibleAPIKey: String
    public var textLLMDefaultProvider: TextLLMProviderKind
    public var textLLMProviders: [TextLLMProviderConfiguration]
    public var mcpServers: [MCPServerConfiguration]
    public var liveDraftInsertionEnabled: Bool
    public var conversationArchiveFolderPath: String
    public var automaticallyArchiveConversations: Bool
    public var recordingSoundCuesEnabled: Bool
    public var recordingStartCueEnabled: Bool
    public var recordingStopCueEnabled: Bool
    public var recordingCueSet: RecordingCueSet
    public var recordingCueVolume: Double
    public var firstRunSetupCompleted: Bool

    public var microphoneID: String? {
        get { microphoneId }
        set { microphoneId = newValue }
    }

    public var hotMenuUpAction: HotMenuAction {
        get { hotMenuAction(for: .up) }
        set { setHotMenuActions([newValue], for: .up) }
    }

    public var hotMenuLeftAction: HotMenuAction {
        get { hotMenuAction(for: .left) }
        set { setHotMenuActions([newValue], for: .left) }
    }

    public var hotMenuRightAction: HotMenuAction {
        get { hotMenuAction(for: .right) }
        set { setHotMenuActions([newValue], for: .right) }
    }

    public var hotMenuDownAction: HotMenuAction {
        get { hotMenuAction(for: .down) }
        set { setHotMenuActions([newValue], for: .down) }
    }

    public var recordingCueTiming: RecordingCueTiming {
        get {
            switch (recordingStartCueEnabled, recordingStopCueEnabled) {
            case (true, false):
                return .start
            case (false, true):
                return .stop
            default:
                return .both
            }
        }
        set {
            switch newValue {
            case .start:
                recordingStartCueEnabled = true
                recordingStopCueEnabled = false
            case .stop:
                recordingStartCueEnabled = false
                recordingStopCueEnabled = true
            case .both:
                recordingStartCueEnabled = true
                recordingStopCueEnabled = true
            }
        }
    }

    public static let defaults = OmniVoicePreferences(
        asrProvider: .parakeetTDTMLX,
        style: .neutral,
        dictionaryTerms: [],
        microphoneID: nil,
        dictationHotkey: .defaultDictation,
        additionalDictationHotkeys: [],
        styleHotkey: .defaultStyle,
        hotMenuHotkey: .defaultHotMenu,
        transcriptCacheHotkey: .defaultTranscriptCache,
        mousePushToTalkEnabled: false,
        mousePushToTalkButton: .defaultPushToTalk,
        transcriptCacheMouseEnabled: false,
        transcriptCacheMouseButton: .defaultTranscriptCache,
        hotMenuUpActions: HotMenuAction.defaultActions(for: .up),
        hotMenuLeftActions: HotMenuAction.defaultActions(for: .left),
        hotMenuRightActions: HotMenuAction.defaultActions(for: .right),
        hotMenuDownActions: HotMenuAction.defaultActions(for: .down),
        themeID: .auroraBlue,
        customAccentColor: ThemeColor(hex: "#38BDF8"),
        appearanceMode: .system,
        waveformMode: .bars,
        commitAnimationMode: .glyphStream,
        engineFrameSide: .right,
        engineFrameHandlePosition: 0.5,
        customSpeechModelPath: "",
        customTranslationModelPath: "",
        translationProvider: .translateGemmaMLX,
        translationModelProviderID: TranslationModelRecommendation.defaultProviderID,
        conversationDiarizationProvider: "none",
        conversationDiarizationPrecision: .fp16,
        liveConversationDiarizationEnabled: false,
        liveTranslationEnabled: false,
        translationSourceLanguage: "en",
        translationTargetLanguage: "es",
        translationQuickTargetLanguages: defaultTranslationQuickTargetLanguages,
        openAICompatibleBaseURL: "",
        openAICompatibleModel: "",
        openAICompatibleAPIKey: "",
        textLLMDefaultProvider: .custom,
        textLLMProviders: TextLLMProviderConfiguration.defaults,
        mcpServers: [],
        liveDraftInsertionEnabled: false,
        conversationArchiveFolderPath: ConversationArchive.defaultRootURL().path,
        automaticallyArchiveConversations: true,
        recordingSoundCuesEnabled: true,
        recordingStartCueEnabled: true,
        recordingStopCueEnabled: true,
        recordingCueSet: .glassTap,
        recordingCueVolume: 0.28,
        firstRunSetupCompleted: false
    )

    public init(
        asrProvider: ASRProviderKind,
        style: StyleProfile,
        dictionaryTerms: [String],
        microphoneID: String? = nil,
        dictationHotkey: HotkeyBinding = .defaultDictation,
        additionalDictationHotkeys: [HotkeyBinding] = [],
        styleHotkey: HotkeyBinding = .defaultStyle,
        hotMenuHotkey: HotkeyBinding = .defaultHotMenu,
        transcriptCacheHotkey: HotkeyBinding = .defaultTranscriptCache,
        mousePushToTalkEnabled: Bool = false,
        mousePushToTalkButton: MouseButtonBinding = .defaultPushToTalk,
        transcriptCacheMouseEnabled: Bool = false,
        transcriptCacheMouseButton: MouseButtonBinding = .defaultTranscriptCache,
        hotMenuUpAction: HotMenuAction? = nil,
        hotMenuLeftAction: HotMenuAction? = nil,
        hotMenuRightAction: HotMenuAction? = nil,
        hotMenuDownAction: HotMenuAction? = nil,
        hotMenuUpActions: [HotMenuAction]? = nil,
        hotMenuLeftActions: [HotMenuAction]? = nil,
        hotMenuRightActions: [HotMenuAction]? = nil,
        hotMenuDownActions: [HotMenuAction]? = nil,
        themeID: OmniVoiceThemeID = .auroraBlue,
        customAccentColor: ThemeColor = ThemeColor(hex: "#38BDF8"),
        appearanceMode: AppAppearanceMode = .system,
        waveformMode: WaveformMode = .bars,
        commitAnimationMode: CommitAnimationMode = .glyphStream,
        engineFrameSide: EngineFrameSide = .right,
        engineFrameHandlePosition: Double = 0.5,
        customSpeechModelPath: String = "",
        customTranslationModelPath: String = "",
        translationProvider: TranslationProviderKind = .translateGemmaMLX,
        translationModelProviderID: String = TranslationModelRecommendation.defaultProviderID,
        conversationDiarizationProvider: String = "none",
        conversationDiarizationPrecision: DiarizationPrecision? = nil,
        liveConversationDiarizationEnabled: Bool = false,
        liveTranslationEnabled: Bool = false,
        translationSourceLanguage: String = "en",
        translationTargetLanguage: String = "es",
        translationQuickTargetLanguages: [String] = OmniVoicePreferences.defaultTranslationQuickTargetLanguages,
        openAICompatibleBaseURL: String = "",
        openAICompatibleModel: String = "",
        openAICompatibleAPIKey: String = "",
        textLLMDefaultProvider: TextLLMProviderKind = .custom,
        textLLMProviders: [TextLLMProviderConfiguration]? = nil,
        mcpServers: [MCPServerConfiguration] = [],
        liveDraftInsertionEnabled: Bool = false,
        conversationArchiveFolderPath: String = ConversationArchive.defaultRootURL().path,
        automaticallyArchiveConversations: Bool = true,
        recordingSoundCuesEnabled: Bool = true,
        recordingStartCueEnabled: Bool = true,
        recordingStopCueEnabled: Bool = true,
        recordingCueSet: RecordingCueSet = .glassTap,
        recordingCueVolume: Double = 0.28,
        firstRunSetupCompleted: Bool = false
    ) {
        self.asrProvider = asrProvider.normalizedForUserSelection
        self.style = style
        self.dictionaryTerms = dictionaryTerms
        self.microphoneId = microphoneID
        self.dictationHotkey = dictationHotkey
        self.additionalDictationHotkeys = Self.normalizedAdditionalDictationHotkeys(
            additionalDictationHotkeys,
            primary: dictationHotkey
        )
        self.styleHotkey = styleHotkey
        self.hotMenuHotkey = hotMenuHotkey
        self.transcriptCacheHotkey = transcriptCacheHotkey
        self.mousePushToTalkEnabled = mousePushToTalkEnabled
        self.mousePushToTalkButton = mousePushToTalkButton
        self.transcriptCacheMouseEnabled = transcriptCacheMouseEnabled
        self.transcriptCacheMouseButton = transcriptCacheMouseButton
        self.hotMenuUpActions = Self.resolvedHotMenuActions(
            actions: hotMenuUpActions,
            legacyAction: hotMenuUpAction,
            direction: .up
        )
        self.hotMenuLeftActions = Self.resolvedHotMenuActions(
            actions: hotMenuLeftActions,
            legacyAction: hotMenuLeftAction,
            direction: .left
        )
        self.hotMenuRightActions = Self.resolvedHotMenuActions(
            actions: hotMenuRightActions,
            legacyAction: hotMenuRightAction,
            direction: .right
        )
        self.hotMenuDownActions = Self.resolvedHotMenuActions(
            actions: hotMenuDownActions,
            legacyAction: hotMenuDownAction,
            direction: .down
        )
        self.themeID = themeID
        self.customAccentColor = customAccentColor
        self.appearanceMode = appearanceMode
        self.waveformMode = waveformMode
        self.commitAnimationMode = commitAnimationMode
        self.engineFrameSide = engineFrameSide
        self.engineFrameHandlePosition = Self.clampedHandlePosition(engineFrameHandlePosition)
        self.customSpeechModelPath = customSpeechModelPath
        self.customTranslationModelPath = customTranslationModelPath
        self.translationProvider = translationProvider
        self.translationModelProviderID = translationModelProviderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? TranslationModelRecommendation.defaultProviderID
            : translationModelProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conversationDiarizationProvider = conversationDiarizationProvider
        self.conversationDiarizationPrecision = conversationDiarizationPrecision
            ?? DiarizationPrecision(providerID: conversationDiarizationProvider)
        self.liveConversationDiarizationEnabled = liveConversationDiarizationEnabled
        self.liveTranslationEnabled = liveTranslationEnabled
        self.translationSourceLanguage = translationSourceLanguage
        self.translationTargetLanguage = translationTargetLanguage
        self.translationQuickTargetLanguages = Self.normalizedTranslationQuickTargetLanguages(translationQuickTargetLanguages)
        self.openAICompatibleBaseURL = openAICompatibleBaseURL
        self.openAICompatibleModel = openAICompatibleModel
        self.openAICompatibleAPIKey = openAICompatibleAPIKey
        self.textLLMDefaultProvider = textLLMDefaultProvider
        self.textLLMProviders = (textLLMProviders ?? []).normalizedTextLLMConfigurations(
            legacyBaseURL: openAICompatibleBaseURL,
            legacyModel: openAICompatibleModel,
            legacyAPIKey: openAICompatibleAPIKey
        )
        self.mcpServers = mcpServers.map { $0.normalized() }
        self.liveDraftInsertionEnabled = liveDraftInsertionEnabled
        self.conversationArchiveFolderPath = conversationArchiveFolderPath
        self.automaticallyArchiveConversations = automaticallyArchiveConversations
        self.recordingSoundCuesEnabled = recordingSoundCuesEnabled
        self.recordingStartCueEnabled = recordingStartCueEnabled
        self.recordingStopCueEnabled = recordingStopCueEnabled
        self.recordingCueSet = recordingCueSet
        self.recordingCueVolume = Self.clampedRecordingCueVolume(recordingCueVolume)
        self.firstRunSetupCompleted = firstRunSetupCompleted
        self.normalizeRecordingCueTiming()
        self.migrateLegacyHotMenuDefaultsIfNeeded()
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let acronymContainer = try decoder.container(keyedBy: AcronymCodingKeys.self)
            let legacyHotMenuContainer = try decoder.container(keyedBy: LegacyHotMenuCodingKeys.self)
            try self.init(
                snakeCaseContainer: container,
                acronymContainer: acronymContainer,
                legacyHotMenuContainer: legacyHotMenuContainer
            )
        } catch DecodingError.keyNotFound {
            let container = try decoder.container(keyedBy: ConvertedCodingKeys.self)
            let legacyHotMenuContainer = try decoder.container(keyedBy: LegacyConvertedHotMenuCodingKeys.self)
            try self.init(convertedContainer: container, legacyHotMenuContainer: legacyHotMenuContainer)
        }
    }

    private init(
        snakeCaseContainer container: KeyedDecodingContainer<CodingKeys>,
        acronymContainer: KeyedDecodingContainer<AcronymCodingKeys>,
        legacyHotMenuContainer: KeyedDecodingContainer<LegacyHotMenuCodingKeys>
    ) throws {
        self.init(
            asrProvider: try container.decode(ASRProviderKind.self, forKey: .asrProvider),
            style: try container.decode(StyleProfile.self, forKey: .style),
            dictionaryTerms: try container.decode([String].self, forKey: .dictionaryTerms),
            microphoneID: try container.decodeIfPresent(String.self, forKey: .microphoneId),
            dictationHotkey: try container.decode(HotkeyBinding.self, forKey: .dictationHotkey),
            additionalDictationHotkeys: try container.decodeIfPresent(
                [HotkeyBinding].self,
                forKey: .additionalDictationHotkeys
            ) ?? [],
            styleHotkey: try container.decode(HotkeyBinding.self, forKey: .styleHotkey),
            hotMenuHotkey: try container.decodeIfPresent(HotkeyBinding.self, forKey: .hotMenuHotkey) ?? .defaultHotMenu,
            transcriptCacheHotkey: try container.decodeIfPresent(HotkeyBinding.self, forKey: .transcriptCacheHotkey)
                ?? .defaultTranscriptCache,
            mousePushToTalkEnabled: try container.decodeIfPresent(Bool.self, forKey: .mousePushToTalkEnabled) ?? false,
            mousePushToTalkButton: try container.decodeIfPresent(MouseButtonBinding.self, forKey: .mousePushToTalkButton)
                ?? .defaultPushToTalk,
            transcriptCacheMouseEnabled: try container.decodeIfPresent(Bool.self, forKey: .transcriptCacheMouseEnabled) ?? false,
            transcriptCacheMouseButton: try container.decodeIfPresent(MouseButtonBinding.self, forKey: .transcriptCacheMouseButton)
                ?? .defaultTranscriptCache,
            hotMenuUpAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuUpAction),
            hotMenuLeftAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuLeftAction),
            hotMenuRightAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuRightAction),
            hotMenuDownAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuDownAction),
            hotMenuUpActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuUpActions),
            hotMenuLeftActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuLeftActions),
            hotMenuRightActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuRightActions),
            hotMenuDownActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuDownActions),
            themeID: try container.decodeIfPresent(OmniVoiceThemeID.self, forKey: .themeID) ?? .auroraBlue,
            customAccentColor: try container.decodeIfPresent(ThemeColor.self, forKey: .customAccentColor) ?? ThemeColor(hex: "#38BDF8"),
            appearanceMode: try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system,
            waveformMode: try container.decodeIfPresent(WaveformMode.self, forKey: .waveformMode) ?? .bars,
            commitAnimationMode: try container.decodeIfPresent(CommitAnimationMode.self, forKey: .commitAnimationMode) ?? .glyphStream,
            engineFrameSide: try container.decodeIfPresent(EngineFrameSide.self, forKey: .engineFrameSide) ?? .right,
            engineFrameHandlePosition: try container.decodeIfPresent(Double.self, forKey: .engineFrameHandlePosition) ?? 0.5,
            customSpeechModelPath: try container.decodeIfPresent(String.self, forKey: .customSpeechModelPath) ?? "",
            customTranslationModelPath: try container.decodeIfPresent(String.self, forKey: .customTranslationModelPath) ?? "",
            translationProvider: try container.decodeIfPresent(TranslationProviderKind.self, forKey: .translationProvider) ?? .translateGemmaMLX,
            translationModelProviderID: try container.decodeIfPresent(String.self, forKey: .translationModelProviderID)
                ?? TranslationModelRecommendation.defaultProviderID,
            conversationDiarizationProvider: try container.decodeIfPresent(String.self, forKey: .conversationDiarizationProvider)
                ?? "none",
            conversationDiarizationPrecision: try container.decodeIfPresent(
                DiarizationPrecision.self,
                forKey: .conversationDiarizationPrecision
            ),
            liveConversationDiarizationEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveConversationDiarizationEnabled)
                ?? false,
            liveTranslationEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveTranslationEnabled) ?? false,
            translationSourceLanguage: try container.decodeIfPresent(String.self, forKey: .translationSourceLanguage) ?? "en",
            translationTargetLanguage: try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? "es",
            translationQuickTargetLanguages: try container.decodeIfPresent([String].self, forKey: .translationQuickTargetLanguages)
                ?? Self.defaultTranslationQuickTargetLanguages,
            openAICompatibleBaseURL: try container.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL)
                ?? acronymContainer.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL)
                ?? "",
            openAICompatibleModel: try container.decodeIfPresent(String.self, forKey: .openAICompatibleModel)
                ?? acronymContainer.decodeIfPresent(String.self, forKey: .openAICompatibleModel)
                ?? "",
            openAICompatibleAPIKey: try container.decodeIfPresent(String.self, forKey: .openAICompatibleAPIKey)
                ?? acronymContainer.decodeIfPresent(String.self, forKey: .openAICompatibleAPIKey)
                ?? "",
            textLLMDefaultProvider: try container.decodeIfPresent(TextLLMProviderKind.self, forKey: .textLLMDefaultProvider)
                ?? .custom,
            textLLMProviders: try container.decodeIfPresent([TextLLMProviderConfiguration].self, forKey: .textLLMProviders),
            mcpServers: try container.decodeIfPresent([MCPServerConfiguration].self, forKey: .mcpServers) ?? [],
            liveDraftInsertionEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveDraftInsertionEnabled) ?? false,
            conversationArchiveFolderPath: try container.decodeIfPresent(String.self, forKey: .conversationArchiveFolderPath)
                ?? ConversationArchive.defaultRootURL().path,
            automaticallyArchiveConversations: try container.decodeIfPresent(Bool.self, forKey: .automaticallyArchiveConversations)
                ?? true,
            recordingSoundCuesEnabled: try container.decodeIfPresent(Bool.self, forKey: .recordingSoundCuesEnabled) ?? true,
            recordingStartCueEnabled: try container.decodeIfPresent(Bool.self, forKey: .recordingStartCueEnabled) ?? true,
            recordingStopCueEnabled: try container.decodeIfPresent(Bool.self, forKey: .recordingStopCueEnabled) ?? true,
            recordingCueSet: try container.decodeIfPresent(RecordingCueSet.self, forKey: .recordingCueSet) ?? .glassTap,
            recordingCueVolume: try container.decodeIfPresent(Double.self, forKey: .recordingCueVolume) ?? 0.28,
            firstRunSetupCompleted: try container.decodeIfPresent(Bool.self, forKey: .firstRunSetupCompleted) ?? false
        )
    }

    private init(
        convertedContainer container: KeyedDecodingContainer<ConvertedCodingKeys>,
        legacyHotMenuContainer: KeyedDecodingContainer<LegacyConvertedHotMenuCodingKeys>
    ) throws {
        self.init(
            asrProvider: try container.decode(ASRProviderKind.self, forKey: .asrProvider),
            style: try container.decode(StyleProfile.self, forKey: .style),
            dictionaryTerms: try container.decode([String].self, forKey: .dictionaryTerms),
            microphoneID: try container.decodeIfPresent(String.self, forKey: .microphoneId),
            dictationHotkey: try container.decode(HotkeyBinding.self, forKey: .dictationHotkey),
            additionalDictationHotkeys: try container.decodeIfPresent(
                [HotkeyBinding].self,
                forKey: .additionalDictationHotkeys
            ) ?? [],
            styleHotkey: try container.decode(HotkeyBinding.self, forKey: .styleHotkey),
            hotMenuHotkey: try container.decodeIfPresent(HotkeyBinding.self, forKey: .hotMenuHotkey) ?? .defaultHotMenu,
            transcriptCacheHotkey: try container.decodeIfPresent(HotkeyBinding.self, forKey: .transcriptCacheHotkey)
                ?? .defaultTranscriptCache,
            mousePushToTalkEnabled: try container.decodeIfPresent(Bool.self, forKey: .mousePushToTalkEnabled) ?? false,
            mousePushToTalkButton: try container.decodeIfPresent(MouseButtonBinding.self, forKey: .mousePushToTalkButton)
                ?? .defaultPushToTalk,
            transcriptCacheMouseEnabled: try container.decodeIfPresent(Bool.self, forKey: .transcriptCacheMouseEnabled) ?? false,
            transcriptCacheMouseButton: try container.decodeIfPresent(MouseButtonBinding.self, forKey: .transcriptCacheMouseButton)
                ?? .defaultTranscriptCache,
            hotMenuUpAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuUpAction),
            hotMenuLeftAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuLeftAction),
            hotMenuRightAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuRightAction),
            hotMenuDownAction: try legacyHotMenuContainer.decodeIfPresent(HotMenuAction.self, forKey: .hotMenuDownAction),
            hotMenuUpActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuUpActions),
            hotMenuLeftActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuLeftActions),
            hotMenuRightActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuRightActions),
            hotMenuDownActions: try container.decodeIfPresent([HotMenuAction].self, forKey: .hotMenuDownActions),
            themeID: try container.decodeIfPresent(OmniVoiceThemeID.self, forKey: .themeID) ?? .auroraBlue,
            customAccentColor: try container.decodeIfPresent(ThemeColor.self, forKey: .customAccentColor) ?? ThemeColor(hex: "#38BDF8"),
            appearanceMode: try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system,
            waveformMode: try container.decodeIfPresent(WaveformMode.self, forKey: .waveformMode) ?? .bars,
            commitAnimationMode: try container.decodeIfPresent(CommitAnimationMode.self, forKey: .commitAnimationMode) ?? .glyphStream,
            engineFrameSide: try container.decodeIfPresent(EngineFrameSide.self, forKey: .engineFrameSide) ?? .right,
            engineFrameHandlePosition: try container.decodeIfPresent(Double.self, forKey: .engineFrameHandlePosition) ?? 0.5,
            customSpeechModelPath: try container.decodeIfPresent(String.self, forKey: .customSpeechModelPath) ?? "",
            customTranslationModelPath: try container.decodeIfPresent(String.self, forKey: .customTranslationModelPath) ?? "",
            translationProvider: try container.decodeIfPresent(TranslationProviderKind.self, forKey: .translationProvider) ?? .translateGemmaMLX,
            translationModelProviderID: try container.decodeIfPresent(String.self, forKey: .translationModelProviderID)
                ?? TranslationModelRecommendation.defaultProviderID,
            conversationDiarizationProvider: try container.decodeIfPresent(String.self, forKey: .conversationDiarizationProvider)
                ?? "none",
            conversationDiarizationPrecision: try container.decodeIfPresent(
                DiarizationPrecision.self,
                forKey: .conversationDiarizationPrecision
            ),
            liveConversationDiarizationEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveConversationDiarizationEnabled)
                ?? false,
            liveTranslationEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveTranslationEnabled) ?? false,
            translationSourceLanguage: try container.decodeIfPresent(String.self, forKey: .translationSourceLanguage) ?? "en",
            translationTargetLanguage: try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? "es",
            translationQuickTargetLanguages: try container.decodeIfPresent([String].self, forKey: .translationQuickTargetLanguages)
                ?? Self.defaultTranslationQuickTargetLanguages,
            openAICompatibleBaseURL: try container.decodeIfPresent(String.self, forKey: .openAICompatibleBaseURL) ?? "",
            openAICompatibleModel: try container.decodeIfPresent(String.self, forKey: .openAICompatibleModel) ?? "",
            openAICompatibleAPIKey: try container.decodeIfPresent(String.self, forKey: .openAICompatibleAPIKey) ?? "",
            textLLMDefaultProvider: try container.decodeIfPresent(TextLLMProviderKind.self, forKey: .textLLMDefaultProvider)
                ?? .custom,
            textLLMProviders: try container.decodeIfPresent([TextLLMProviderConfiguration].self, forKey: .textLLMProviders),
            mcpServers: try container.decodeIfPresent([MCPServerConfiguration].self, forKey: .mcpServers) ?? [],
            liveDraftInsertionEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveDraftInsertionEnabled) ?? false,
            conversationArchiveFolderPath: try container.decodeIfPresent(String.self, forKey: .conversationArchiveFolderPath)
                ?? ConversationArchive.defaultRootURL().path,
            automaticallyArchiveConversations: try container.decodeIfPresent(Bool.self, forKey: .automaticallyArchiveConversations)
                ?? true,
            recordingSoundCuesEnabled: try container.decodeIfPresent(Bool.self, forKey: .recordingSoundCuesEnabled) ?? true,
            recordingStartCueEnabled: try container.decodeIfPresent(Bool.self, forKey: .recordingStartCueEnabled) ?? true,
            recordingStopCueEnabled: try container.decodeIfPresent(Bool.self, forKey: .recordingStopCueEnabled) ?? true,
            recordingCueSet: try container.decodeIfPresent(RecordingCueSet.self, forKey: .recordingCueSet) ?? .glassTap,
            recordingCueVolume: try container.decodeIfPresent(Double.self, forKey: .recordingCueVolume) ?? 0.28,
            firstRunSetupCompleted: try container.decodeIfPresent(Bool.self, forKey: .firstRunSetupCompleted) ?? false
        )
    }

    public mutating func cycleStyle() {
        style = style.next()
    }

    public mutating func cycleASRProvider() {
        switch asrProvider {
        case .parakeetTDTMLX:
            asrProvider = .whisperLargeV3TurboMLX6Bit
        case .whisperLargeV3TurboMLX6Bit:
            asrProvider = .senseVoiceSmall
        case .senseVoiceSmall:
            asrProvider = .canaryQwen25B
        case .canaryQwen25B:
            asrProvider = .parakeetTDTMLX
        case .fake, .parakeetTDT:
            asrProvider = .parakeetTDTMLX
        }
    }

    public func normalizedTranslationQuickTargetLanguages() -> [String] {
        Self.normalizedTranslationQuickTargetLanguages(translationQuickTargetLanguages)
    }

    @discardableResult
    public mutating func cycleTranslationTargetLanguage() -> String {
        let languages = normalizedTranslationQuickTargetLanguages()
        translationQuickTargetLanguages = languages
        guard let currentIndex = languages.firstIndex(of: translationTargetLanguage.lowercased()) else {
            translationTargetLanguage = languages.first ?? Self.defaultTranslationQuickTargetLanguages[0]
            return translationTargetLanguage
        }

        translationTargetLanguage = languages[(currentIndex + 1) % languages.count]
        return translationTargetLanguage
    }

    public func hotMenuAction(for direction: HotMenuDirection) -> HotMenuAction {
        hotMenuActions(for: direction).first ?? .none
    }

    public func hotMenuActions(for direction: HotMenuDirection) -> [HotMenuAction] {
        switch direction {
        case .up:
            hotMenuUpActions
        case .left:
            hotMenuLeftActions
        case .right:
            hotMenuRightActions
        case .down:
            hotMenuDownActions
        }
    }

    public func effectiveHotMenuActions(for direction: HotMenuDirection) -> [HotMenuAction] {
        hotMenuActions(for: direction).flatMap { action -> [HotMenuAction] in
            switch action {
            case .cycleTranslationLanguage:
                return effectiveTranslationLanguageActions()
            case .toggleTranslation:
                return liveTranslationEnabled ? [.translationOn, .translationOff] : [.translationOff, .translationOn]
            case .cycleStyle:
                return effectiveStyleActions()
            default:
                return [action]
            }
        }
        .filter(\.isRuntimeSelectable)
    }

    public func effectiveTranslationLanguageActions() -> [HotMenuAction] {
        let quickTargets = normalizedTranslationQuickTargetLanguages()
        let indexedTargets = Array(quickTargets.enumerated())
        let startIndex = indexedTargets.firstIndex { _, code in
            code == translationTargetLanguage
        } ?? 0
        let orderedTargets = Array(indexedTargets[startIndex...]) + Array(indexedTargets[..<startIndex])
        return orderedTargets.compactMap { index, _ in
            HotMenuAction.quickTranslationTargetAction(forSlot: index)
        }
    }

    public func effectiveStyleActions() -> [HotMenuAction] {
        let styles = StyleProfile.allCases
        let startIndex = styles.firstIndex(of: style) ?? 0
        let orderedStyles = Array(styles[startIndex...]) + Array(styles[..<startIndex])
        return orderedStyles.map(HotMenuAction.styleAction(for:))
    }

    public func hotMenuStatusLabel(
        for action: HotMenuAction,
        targetLanguageOptions: [TranslationLanguageOption]
    ) -> String {
        switch action {
        case .toggleTranslation:
            return liveTranslationEnabled ? "Translation On" : "Translation Off"
        case .translationOn:
            return "Translation On"
        case .translationOff:
            return "Translation Off"
        case .cycleStyle:
            return style.displayName
        case .styleNeutral, .styleProfessional, .styleConcise, .styleExpanded, .styleRaw:
            return action.styleProfile?.displayName ?? action.displayName
        case .translationQuickTarget1, .translationQuickTarget2, .translationQuickTarget3, .translationQuickTarget4:
            guard let slot = action.quickTranslationTargetSlot else {
                return action.displayName
            }
            let quickTargets = normalizedTranslationQuickTargetLanguages()
            guard quickTargets.indices.contains(slot) else {
                return action.displayName
            }
            return Self.translationLanguageName(for: quickTargets[slot], in: targetLanguageOptions)
        default:
            return action.displayName
        }
    }

    public func captionTranslationStatus(targetLanguageOptions: [TranslationLanguageOption]) -> String? {
        guard liveTranslationEnabled else {
            return nil
        }
        let target = Self.translationLanguageName(for: translationTargetLanguage, in: targetLanguageOptions)
        return "Translation On: \(target)"
    }

    public static func translationLanguageName(
        for code: String,
        in options: [TranslationLanguageOption]
    ) -> String {
        options.first { $0.code == code }?.name ?? code
    }

    public mutating func setHotMenuActions(_ actions: [HotMenuAction], for direction: HotMenuDirection) {
        let normalized = HotMenuAction.normalizedActions(actions, for: direction)
        switch direction {
        case .up:
            hotMenuUpActions = normalized
        case .left:
            hotMenuLeftActions = normalized
        case .right:
            hotMenuRightActions = normalized
        case .down:
            hotMenuDownActions = normalized
        }
    }

    public func textLLMConfiguration(for provider: TextLLMProviderKind) -> TextLLMProviderConfiguration {
        textLLMProviders.configuration(for: provider)
    }

    public func textLLMConfiguration(for target: AIHandoffTarget) -> TextLLMProviderConfiguration {
        if target == .custom {
            return textLLMConfiguration(for: textLLMDefaultProvider)
        }
        return textLLMConfiguration(for: TextLLMProviderKind(target: target))
    }

    public mutating func setTextLLMDefaultProvider(_ provider: TextLLMProviderKind) {
        textLLMDefaultProvider = provider
    }

    public mutating func setTextLLMConfiguration(_ configuration: TextLLMProviderConfiguration) {
        let normalized = configuration.normalized()
        if let index = textLLMProviders.firstIndex(where: { $0.provider == normalized.provider }) {
            textLLMProviders[index] = normalized
        } else {
            textLLMProviders.append(normalized)
            textLLMProviders = textLLMProviders.normalizedTextLLMConfigurations()
        }

        if normalized.provider == .custom {
            openAICompatibleBaseURL = normalized.baseURL
            openAICompatibleModel = normalized.model
            openAICompatibleAPIKey = normalized.apiKey
        }
    }

    public mutating func setMCPServer(_ server: MCPServerConfiguration) {
        let normalized = server.normalized()
        if let index = mcpServers.firstIndex(where: { $0.id == normalized.id }) {
            mcpServers[index] = normalized
        } else {
            mcpServers.append(normalized)
        }
    }

    public mutating func removeMCPServer(id: UUID) {
        mcpServers.removeAll { $0.id == id }
    }

    public static func clampedHandlePosition(_ value: Double) -> Double {
        min(max(value, 0.08), 0.92)
    }

    public static func clampedRecordingCueVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private mutating func normalizeRecordingCueTiming() {
        if !recordingStartCueEnabled && !recordingStopCueEnabled {
            recordingCueTiming = .both
        }
    }

    public func isRecordingCueEnabled(for event: RecordingCueEvent) -> Bool {
        guard recordingSoundCuesEnabled else {
            return false
        }

        switch event {
        case .start:
            return recordingStartCueEnabled
        case .stop:
            return recordingStopCueEnabled
        }
    }

    private enum CodingKeys: String, CodingKey {
        case asrProvider = "asr_provider"
        case style = "style"
        case dictionaryTerms = "dictionary_terms"
        case microphoneId = "microphone_id"
        case dictationHotkey = "dictation_hotkey"
        case additionalDictationHotkeys = "additional_dictation_hotkeys"
        case styleHotkey = "style_hotkey"
        case hotMenuHotkey = "hot_menu_hotkey"
        case transcriptCacheHotkey = "transcript_cache_hotkey"
        case mousePushToTalkEnabled = "mouse_push_to_talk_enabled"
        case mousePushToTalkButton = "mouse_push_to_talk_button"
        case transcriptCacheMouseEnabled = "transcript_cache_mouse_enabled"
        case transcriptCacheMouseButton = "transcript_cache_mouse_button"
        case hotMenuUpActions = "hot_menu_up_actions"
        case hotMenuLeftActions = "hot_menu_left_actions"
        case hotMenuRightActions = "hot_menu_right_actions"
        case hotMenuDownActions = "hot_menu_down_actions"
        case themeID = "theme_id"
        case customAccentColor = "custom_accent_color"
        case appearanceMode = "appearance_mode"
        case waveformMode = "waveform_mode"
        case commitAnimationMode = "commit_animation_mode"
        case engineFrameSide = "engine_frame_side"
        case engineFrameHandlePosition = "engine_frame_handle_position"
        case customSpeechModelPath = "custom_speech_model_path"
        case customTranslationModelPath = "custom_translation_model_path"
        case translationProvider = "translation_provider"
        case translationModelProviderID = "translation_model_provider_id"
        case conversationDiarizationProvider = "conversation_diarization_provider"
        case conversationDiarizationPrecision = "conversation_diarization_precision"
        case liveConversationDiarizationEnabled = "live_conversation_diarization_enabled"
        case liveTranslationEnabled = "live_translation_enabled"
        case translationSourceLanguage = "translation_source_language"
        case translationTargetLanguage = "translation_target_language"
        case translationQuickTargetLanguages = "translation_quick_target_languages"
        case openAICompatibleBaseURL = "open_ai_compatible_base_url"
        case openAICompatibleModel = "open_ai_compatible_model"
        case openAICompatibleAPIKey = "open_ai_compatible_api_key"
        case textLLMDefaultProvider = "text_llm_default_provider"
        case textLLMProviders = "text_llm_providers"
        case mcpServers = "mcp_servers"
        case liveDraftInsertionEnabled = "live_draft_insertion_enabled"
        case conversationArchiveFolderPath = "conversation_archive_folder_path"
        case automaticallyArchiveConversations = "automatically_archive_conversations"
        case recordingSoundCuesEnabled = "recording_sound_cues_enabled"
        case recordingStartCueEnabled = "recording_start_cue_enabled"
        case recordingStopCueEnabled = "recording_stop_cue_enabled"
        case recordingCueSet = "recording_cue_set"
        case recordingCueVolume = "recording_cue_volume"
        case firstRunSetupCompleted = "first_run_setup_completed"
    }

    private enum ConvertedCodingKeys: String, CodingKey {
        case asrProvider
        case style
        case dictionaryTerms
        case microphoneId
        case dictationHotkey
        case additionalDictationHotkeys
        case styleHotkey
        case hotMenuHotkey
        case transcriptCacheHotkey
        case mousePushToTalkEnabled
        case mousePushToTalkButton
        case transcriptCacheMouseEnabled
        case transcriptCacheMouseButton
        case hotMenuUpActions
        case hotMenuLeftActions
        case hotMenuRightActions
        case hotMenuDownActions
        case themeID = "themeId"
        case customAccentColor
        case appearanceMode
        case waveformMode
        case commitAnimationMode
        case engineFrameSide
        case engineFrameHandlePosition
        case customSpeechModelPath
        case customTranslationModelPath
        case translationProvider
        case translationModelProviderID
        case conversationDiarizationProvider
        case conversationDiarizationPrecision
        case liveConversationDiarizationEnabled
        case liveTranslationEnabled
        case translationSourceLanguage
        case translationTargetLanguage
        case translationQuickTargetLanguages
        case openAICompatibleBaseURL = "openAiCompatibleBaseUrl"
        case openAICompatibleModel = "openAiCompatibleModel"
        case openAICompatibleAPIKey = "openAiCompatibleApiKey"
        case textLLMDefaultProvider
        case textLLMProviders
        case mcpServers
        case liveDraftInsertionEnabled
        case conversationArchiveFolderPath
        case automaticallyArchiveConversations
        case recordingSoundCuesEnabled
        case recordingStartCueEnabled
        case recordingStopCueEnabled
        case recordingCueSet
        case recordingCueVolume
        case firstRunSetupCompleted
    }

    private enum AcronymCodingKeys: String, CodingKey {
        case openAICompatibleBaseURL = "openAiCompatibleBaseUrl"
        case openAICompatibleModel = "openAiCompatibleModel"
        case openAICompatibleAPIKey = "openAiCompatibleApiKey"
    }

    private enum LegacyHotMenuCodingKeys: String, CodingKey {
        case hotMenuUpAction = "hot_menu_up_action"
        case hotMenuLeftAction = "hot_menu_left_action"
        case hotMenuRightAction = "hot_menu_right_action"
        case hotMenuDownAction = "hot_menu_down_action"
    }

    private enum LegacyConvertedHotMenuCodingKeys: String, CodingKey {
        case hotMenuUpAction
        case hotMenuLeftAction
        case hotMenuRightAction
        case hotMenuDownAction
    }

    private static func resolvedHotMenuActions(
        actions: [HotMenuAction]?,
        legacyAction: HotMenuAction?,
        direction: HotMenuDirection
    ) -> [HotMenuAction] {
        if let actions {
            return HotMenuAction.normalizedActions(actions, for: direction)
        }

        if let legacyAction {
            if legacyAction == HotMenuAction.defaultAction(for: direction) {
                return HotMenuAction.defaultActions(for: direction)
            }
            return [legacyAction]
        }

        return HotMenuAction.defaultActions(for: direction)
    }

    private mutating func migrateLegacyHotMenuDefaultsIfNeeded() {
        let legacyInitialDefaults = Self.hotMenuActionsMatch(hotMenuUpActions, [.openConversation, .dictation, .selectionRewrite])
            && Self.hotMenuActionsMatch(hotMenuLeftActions, [.selectionRewrite])
            && Self.hotMenuActionsMatch(hotMenuRightActions, [.dictation])
            && Self.hotMenuActionsMatch(hotMenuDownActions, [.cycleStyle])
        let translationDefaultsBeforeAskAI = Self.hotMenuActionsMatch(hotMenuUpActions, [.openConversation, .transcriptionMode])
            && Self.hotMenuActionsMatch(hotMenuLeftActions, [.cycleTranslationLanguage])
            && Self.hotMenuActionsMatch(hotMenuRightActions, [.toggleTranslation])
            && Self.hotMenuActionsMatch(hotMenuDownActions, [.cycleStyle])

        guard legacyInitialDefaults || translationDefaultsBeforeAskAI else {
            return
        }

        hotMenuUpActions = HotMenuAction.defaultActions(for: .up)
        hotMenuLeftActions = HotMenuAction.defaultActions(for: .left)
        hotMenuRightActions = HotMenuAction.defaultActions(for: .right)
        hotMenuDownActions = HotMenuAction.defaultActions(for: .down)
    }

    private static func hotMenuActionsMatch(_ lhs: [HotMenuAction], _ rhs: [HotMenuAction]) -> Bool {
        Array(lhs.reversed().drop(while: { $0 == .none }).reversed()) == rhs
    }

    public static func normalizedTranslationQuickTargetLanguages(_ languages: [String]) -> [String] {
        var seen = Set<String>()
        let normalized = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .prefix(translationQuickTargetLanguageSlotCount)

        return normalized.isEmpty ? defaultTranslationQuickTargetLanguages : Array(normalized)
    }

    public static func normalizedAdditionalDictationHotkeys(
        _ hotkeys: [HotkeyBinding],
        primary: HotkeyBinding
    ) -> [HotkeyBinding] {
        var seen: Set<HotkeyBinding> = [primary]
        return hotkeys
            .filter { $0.hasModifier }
            .filter { seen.insert($0).inserted }
            .prefix(maxAdditionalDictationHotkeys)
            .map { $0 }
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
