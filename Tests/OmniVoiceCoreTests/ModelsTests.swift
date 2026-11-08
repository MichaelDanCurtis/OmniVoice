import XCTest
@testable import OmniVoiceCore

final class ModelsTests: XCTestCase {
    func testStyleProfilesCycleInExpectedOrder() {
        XCTAssertEqual(StyleProfile.neutral.next(), .professional)
        XCTAssertEqual(StyleProfile.professional.next(), .concise)
        XCTAssertEqual(StyleProfile.concise.next(), .expanded)
        XCTAssertEqual(StyleProfile.expanded.next(), .raw)
        XCTAssertEqual(StyleProfile.raw.next(), .neutral)
    }

    func testStyleProfilesExposeDisplayNames() {
        XCTAssertEqual(StyleProfile.neutral.displayName, "Neutral")
        XCTAssertEqual(StyleProfile.professional.displayName, "Professional")
        XCTAssertEqual(StyleProfile.concise.displayName, "Concise")
        XCTAssertEqual(StyleProfile.expanded.displayName, "Expanded")
        XCTAssertEqual(StyleProfile.raw.displayName, "Raw Dictation")
    }

    func testASRProviderRawValuesMatchEngineContract() {
        XCTAssertEqual(ASRProviderKind.fake.rawValue, "fake")
        XCTAssertEqual(ASRProviderKind.parakeetTDT.rawValue, "parakeet-tdt")
        XCTAssertEqual(ASRProviderKind.parakeetTDTMLX.rawValue, "parakeet-tdt-mlx")
        XCTAssertEqual(ASRProviderKind.whisperLargeV3TurboMLX6Bit.rawValue, "whisper-large-v3-turbo-mlx-6bit")
        XCTAssertEqual(ASRProviderKind.canaryQwen25B.rawValue, "canary-qwen-2.5b")
    }

    func testASRProviderUserSelectableCasesUseProductionLocalModels() {
        XCTAssertEqual(
            ASRProviderKind.userSelectableCases,
            [.parakeetTDTMLX, .whisperLargeV3TurboMLX6Bit, .canaryQwen25B, .appleSpeech]
        )
        XCTAssertFalse(ASRProviderKind.userSelectableCases.contains(.fake))
        XCTAssertFalse(ASRProviderKind.userSelectableCases.contains(.parakeetTDT))
    }

    func testSpeechModelRecommendationsExposeCuratedASRChoices() {
        XCTAssertEqual(SpeechModelRecommendation.defaultProviderID, "parakeet-tdt-mlx")
        XCTAssertEqual(SpeechModelRecommendation.allCases.map(\.providerID), [
            "parakeet-tdt-mlx",
            "whisper-large-v3-turbo-mlx-6bit",
            "canary-qwen-2.5b",
        ])
        XCTAssertEqual(SpeechModelRecommendation.parakeetTDTMLX.displayName, "Parakeet TDT MLX")
        XCTAssertEqual(SpeechModelRecommendation.parakeetTDTMLX.badge, "Fast / Default")
        XCTAssertEqual(SpeechModelRecommendation.whisperLargeV3TurboMLX6Bit.displayName, "Whisper Large v3 Turbo MLX 6-bit")
        XCTAssertEqual(SpeechModelRecommendation.whisperLargeV3TurboMLX6Bit.badge, "Multilingual")
        XCTAssertEqual(SpeechModelRecommendation.canaryQwen25B.displayName, "Canary-Qwen-2.5B")
        XCTAssertEqual(SpeechModelRecommendation.canaryQwen25B.badge, "English Accuracy")
        XCTAssertEqual(SpeechModelRecommendation.canaryQwen25B.providerKind, .canaryQwen25B)
    }

    func testASRProviderDisplayNamesAreReadableBeforeEngineRefresh() {
        XCTAssertEqual(ASRProviderKind.fake.displayName, "Fake ASR")
        XCTAssertEqual(ASRProviderKind.parakeetTDT.displayName, "Parakeet TDT")
        XCTAssertEqual(ASRProviderKind.parakeetTDTMLX.displayName, "Parakeet TDT MLX")
        XCTAssertEqual(ASRProviderKind.whisperLargeV3TurboMLX6Bit.displayName, "Whisper Large v3 Turbo MLX 6-bit")
        XCTAssertEqual(ASRProviderKind.canaryQwen25B.displayName, "Canary-Qwen-2.5B")
    }

    func testEngineProviderContractDetectsStaleEngineProviderList() {
        let staleProviders = [
            EngineProviderInfo(id: "fake", label: "Fake ASR", available: true),
            EngineProviderInfo(id: "parakeet-tdt-mlx", label: "Parakeet TDT MLX", available: true),
            EngineProviderInfo(id: "canary-qwen-2.5b", label: "Canary-Qwen-2.5B", available: false),
        ]

        XCTAssertEqual(
            EngineProviderContract.missingRequiredASRProviderIDs(in: staleProviders),
            ["whisper-large-v3-turbo-mlx-6bit"]
        )

        let currentProviders = ASRProviderKind.userSelectableCases.map {
            EngineProviderInfo(id: $0.rawValue, label: $0.displayName, available: true)
        }
        XCTAssertTrue(EngineProviderContract.missingRequiredASRProviderIDs(in: currentProviders).isEmpty)
    }

    func testDiarizationPrecisionMapsToMLXProviderIDs() {
        XCTAssertEqual(DiarizationPrecision.fp16.providerID, "mlx-sortformer-streaming-fp16")
        XCTAssertEqual(DiarizationPrecision.fp32.providerID, "mlx-sortformer-streaming-fp32")
        XCTAssertEqual(DiarizationPrecision(providerID: "mlx-sortformer-streaming-fp32"), .fp32)
        XCTAssertEqual(DiarizationPrecision(providerID: "unknown"), .fp16)
    }

    func testTranslationProviderMapsToDownloadableModelProviderIDs() {
        XCTAssertNil(TranslationProviderKind.fake.modelProviderID)
        XCTAssertEqual(TranslationProviderKind.translateGemmaMLX.modelProviderID, "translategemma-mlx")
        XCTAssertNil(TranslationProviderKind.nllbDistilled600M.modelProviderID)
    }

    func testTranslationModelRecommendationsExposeCuratedChoices() {
        XCTAssertEqual(TranslationModelRecommendation.defaultProviderID, "translategemma-mlx")
        XCTAssertEqual(TranslationModelRecommendation.allCases.map(\.providerID), [
            "translategemma-mlx",
            "translategemma-mlx-4b-8bit",
            "translategemma-mlx-12b-4bit",
            "sarvam-translate-mlx-4bit",
            "plamo-2-translate-mlx",
        ])
        XCTAssertEqual(TranslationModelRecommendation.translateGemma4B4Bit.displayName, "TranslateGemma 4B 4-bit")
        XCTAssertEqual(TranslationModelRecommendation.translateGemma4B4Bit.badge, "Fast / Recommended")
    }

    func testTextLLMProviderDefaultsExposeUsableProfiles() {
        let configurations = TextLLMProviderConfiguration.defaults

        XCTAssertEqual(configurations.map(\.provider), TextLLMProviderKind.allCases)
        XCTAssertEqual(configurations.configuration(for: .claude).transport, .anthropic)
        XCTAssertEqual(configurations.configuration(for: .githubCopilot).transport, .githubCopilotOAuth)
        XCTAssertEqual(configurations.configuration(for: .githubCopilot).authMode, .oauth)
        XCTAssertEqual(configurations.configuration(for: .codex).transport, .openAICodexOAuth)
        XCTAssertEqual(configurations.configuration(for: .codex).authMode, .oauth)
        XCTAssertFalse(configurations.configuration(for: .codex).enabled)
        XCTAssertFalse(configurations.configuration(for: .codex).isVisibleInSettings)
        XCTAssertEqual(configurations.configuration(for: .codex).model, "")
        XCTAssertEqual(configurations.configuration(for: .githubCopilot).model, "")
        XCTAssertEqual(configurations.configuration(for: .githubCopilot).resolvedOAuthClientID, "Iv1.b507a08c87ecfe98")
        XCTAssertEqual(configurations.configuration(for: .claude).resolvedBaseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(configurations.configuration(for: .openAI).resolvedBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(configurations.configuration(for: .openRouter).resolvedBaseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(TextLLMProviderKind(providerID: "github_copilot"), .githubCopilot)
        XCTAssertEqual(TextLLMProviderKind(providerID: "openai_codex"), .codex)
        XCTAssertEqual(TextLLMProviderKind(providerID: "openrouter"), .openRouter)
        XCTAssertEqual(TextLLMProviderKind(providerID: "unknown"), .custom)
    }

    func testTextLLMConfigurationAllowsCopilotOAuthClientOverride() {
        let configuration = TextLLMProviderConfiguration(
            provider: .githubCopilot,
            oauthClientID: "  custom-client  "
        )

        XCTAssertEqual(configuration.resolvedOAuthClientID, "custom-client")
    }

    func testTextLLMConfigurationTracksAddedProviderVisibility() {
        XCTAssertTrue(
            TextLLMProviderConfiguration(provider: .openAI, enabled: true, manuallyAdded: true)
                .isVisibleInSettings
        )
        XCTAssertFalse(
            TextLLMProviderConfiguration(provider: .openAI, enabled: true)
                .isVisibleInSettings
        )
        XCTAssertTrue(
            TextLLMProviderConfiguration(provider: .codex, enabled: true, oauthAccessToken: "codex-token")
                .isVisibleInSettings
        )
    }

    func testTextLLMProviderSelectionChoicesIncludeAddedProvidersWhenOneIsConfigured() {
        let configurations = [
            TextLLMProviderConfiguration(
                provider: .codex,
                enabled: true,
                model: "gpt-5.4",
                oauthAccessToken: "codex-token"
            ),
            TextLLMProviderConfiguration(
                provider: .claude,
                enabled: true,
                manuallyAdded: true
            ),
            TextLLMProviderConfiguration(provider: .openAI),
        ].normalizedTextLLMConfigurations()

        let choices = configurations.providerSelectionChoices(
            selected: .claude,
            defaultProvider: .codex
        )

        XCTAssertEqual(choices.prefix(2), [.claude, .codex])
        XCTAssertTrue(choices.contains(.claude))
        XCTAssertTrue(choices.contains(.codex))
        XCTAssertFalse(choices.contains(.openAI))
    }

    func testTextLLMConfigurationReportsConfiguredState() {
        XCTAssertFalse(TextLLMProviderConfiguration(provider: TextLLMProviderKind.openAI, model: "").isConfigured)
        XCTAssertTrue(TextLLMProviderConfiguration(provider: TextLLMProviderKind.openAI, model: "gpt-test", apiKey: "key").isConfigured)
        XCTAssertTrue(
            TextLLMProviderConfiguration(
                provider: TextLLMProviderKind.custom,
                baseURL: "http://127.0.0.1:11434/v1",
                model: "local-qwen"
            )
            .isConfigured
        )
        XCTAssertFalse(
            TextLLMProviderConfiguration(
                provider: TextLLMProviderKind.githubCopilot,
                model: "gpt-4.1",
                authMode: .oauth
            )
            .isConfigured
        )
        XCTAssertTrue(
            TextLLMProviderConfiguration(
                provider: TextLLMProviderKind.githubCopilot,
                model: "gpt-4.1",
                authMode: .oauth,
                oauthAccessToken: "gho_test"
            )
            .isConfigured
        )
        XCTAssertFalse(
            TextLLMProviderConfiguration(
                provider: TextLLMProviderKind.codex,
                model: "gpt-5.4",
                authMode: .oauth,
                oauthAccessToken: ""
            )
            .isConfigured
        )
        XCTAssertTrue(
            TextLLMProviderConfiguration(
                provider: TextLLMProviderKind.codex,
                model: "gpt-5.4",
                authMode: .oauth,
                oauthAccessToken: "codex-token"
            )
            .isConfigured
        )
    }

    func testTextLLMConfigurationResolvesCustomNameAndHeaders() {
        let configuration = TextLLMProviderConfiguration(
            provider: .custom,
            customName: "  Kimi Code  ",
            baseURL: "https://api.moonshot.ai/v1",
            model: "kimi-k2",
            headers: [
                TextLLMHeader(name: "  X-Moonshot-Header  ", value: "  enabled  "),
                TextLLMHeader(name: "", value: "ignored"),
                TextLLMHeader(name: "X-Disabled", value: "ignored", enabled: false),
            ]
        )
        let normalized = configuration.normalized()

        XCTAssertEqual(normalized.displayName, "Kimi Code")
        XCTAssertEqual(normalized.resolvedHeaders, ["X-Moonshot-Header": "enabled"])
        XCTAssertEqual(normalized.transport, .openAICompatible)
        XCTAssertEqual(normalized.authMode, .apiKey)
    }

    func testDefaultHotkeyBindingsMatchPlannedShortcuts() {
        XCTAssertEqual(HotkeyBinding.defaultDictation.keyCode, 49)
        XCTAssertEqual(HotkeyBinding.defaultStyle.keyCode, 1)
        XCTAssertEqual(HotkeyBinding.defaultTranscriptCache.keyCode, 8)
        XCTAssertEqual(HotkeyBinding.defaultDictation.modifiers, 2_304)
        XCTAssertEqual(HotkeyBinding.defaultStyle.modifiers, 2_304)
        XCTAssertEqual(HotkeyBinding.defaultTranscriptCache.modifiers, 2_304)
    }

    func testHotkeyBindingsExposeReadableLabels() {
        XCTAssertEqual(HotkeyBinding.defaultDictation.displayName, "⌥⌘Space")
        XCTAssertEqual(HotkeyBinding.defaultStyle.displayName, "⌥⌘S")
        XCTAssertEqual(HotkeyBinding.defaultTranscriptCache.displayName, "⌥⌘C")
    }

    func testHotkeyPresetsIncludeDefaultsAndReadableNames() {
        XCTAssertTrue(HotkeyBinding.dictationPresets.contains(.defaultDictation))
        XCTAssertTrue(HotkeyBinding.stylePresets.contains(.defaultStyle))
        XCTAssertEqual(HotkeyBinding.dictationPresets.map(\.displayName), ["⌥⌘Space", "⌥⌘D", "⌥⌘F", "⌃⌥Space"])
        XCTAssertEqual(HotkeyBinding.stylePresets.map(\.displayName), ["⌥⌘S", "⌥⌘T", "⌥⌘Y", "⌃⌥S"])
    }

    func testHotkeyBindingsBuildCarbonModifiers() {
        XCTAssertEqual(HotkeyBinding.carbonModifiers(command: true, option: true), 2_304)
        XCTAssertEqual(HotkeyBinding.carbonModifiers(option: true, control: true), 6_144)
        XCTAssertEqual(HotkeyBinding.carbonModifiers(command: true, shift: true), 768)
    }

    func testHotkeyBindingsReportModifierPresence() {
        XCTAssertTrue(HotkeyBinding(keyCode: 49, modifiers: 2_304).hasModifier)
        XCTAssertTrue(HotkeyBinding.modifierOnly(6_144).hasModifier)
        XCTAssertFalse(HotkeyBinding(keyCode: 49, modifiers: 0).hasModifier)
    }

    func testMouseButtonBindingsPreferExtraButtons() {
        XCTAssertEqual(MouseButtonBinding.defaultPushToTalk.buttonNumber, 3)
        XCTAssertEqual(MouseButtonBinding.defaultPushToTalk.displayName, "Mouse Button 4")
        XCTAssertEqual(MouseButtonBinding.defaultTranscriptCache.buttonNumber, 4)
        XCTAssertEqual(MouseButtonBinding.defaultTranscriptCache.displayName, "Mouse Button 5")
        XCTAssertFalse(MouseButtonBinding(buttonNumber: 0).isUsableShortcut)
        XCTAssertFalse(MouseButtonBinding(buttonNumber: 2).isUsableShortcut)
        XCTAssertTrue(MouseButtonBinding(buttonNumber: 3).isUsableShortcut)
    }

    func testTranscriptCacheSelectionWrapsThroughItems() {
        var selection = TranscriptCacheSelectionState()

        selection.move(delta: 1, count: 3)
        XCTAssertEqual(selection.selectedIndex, 1)

        selection.move(delta: 3, count: 3)
        XCTAssertEqual(selection.selectedIndex, 1)

        selection.move(delta: -2, count: 3)
        XCTAssertEqual(selection.selectedIndex, 2)

        XCTAssertEqual(selection.selected(from: ["a", "b", "c"]), "c")
        selection.reset(count: 2)
        XCTAssertEqual(selection.selectedIndex, 1)
        selection.reset(count: 0)
        XCTAssertEqual(selection.selectedIndex, 0)
        XCTAssertNil(selection.selected(from: [String]()))
    }

    func testHotkeyBindingsSupportModifierOnlyChords() {
        let controlOption = HotkeyBinding.modifierOnly(
            HotkeyBinding.carbonModifiers(option: true, control: true)
        )
        let controlOptionCommand = HotkeyBinding.modifierOnly(
            HotkeyBinding.carbonModifiers(command: true, option: true, control: true)
        )
        let controlShift = HotkeyBinding.modifierOnly(
            HotkeyBinding.carbonModifiers(control: true, shift: true)
        )

        XCTAssertTrue(controlOption.isModifierOnly)
        XCTAssertEqual(controlOption.displayName, "⌃⌥")
        XCTAssertEqual(controlOption.modifierCount, 2)
        XCTAssertEqual(controlOptionCommand.displayName, "⌃⌥⌘")
        XCTAssertEqual(controlOptionCommand.modifierCount, 3)
        XCTAssertEqual(controlShift.displayName, "⌃⇧")
    }

    func testHotkeyBindingsExposeLiveModifierLabels() {
        let modifiers = HotkeyBinding.carbonModifiers(
            command: true,
            option: true,
            control: true,
            shift: true
        )

        XCTAssertEqual(HotkeyBinding.displayName(forModifiers: modifiers), "⌃⌥⇧⌘")
    }

    func testHotMenuDefaultsUseControlOptionAndActionCycles() {
        XCTAssertEqual(HotkeyBinding.defaultHotMenu, .modifierOnly(HotkeyBinding.carbonModifiers(option: true, control: true)))
        XCTAssertEqual(HotMenuAction.defaultActions(for: .up), [.openConversation, .transcriptionMode, .askAI])
        XCTAssertEqual(HotMenuAction.defaultActions(for: .left), [.cycleTranslationLanguage])
        XCTAssertEqual(HotMenuAction.defaultActions(for: .right), [.toggleTranslation])
        XCTAssertEqual(HotMenuAction.defaultActions(for: .down), [.cycleStyle])
        XCTAssertEqual(HotMenuAction.defaultAction(for: .up), .openConversation)
        XCTAssertEqual(HotMenuAction.defaultAction(for: .left), .cycleTranslationLanguage)
        XCTAssertEqual(HotMenuAction.defaultAction(for: .right), .toggleTranslation)
        XCTAssertEqual(HotMenuAction.defaultAction(for: .down), .cycleStyle)
    }

    func testHotMenuActionCyclesHaveFourVisibleSlotsAndFallbackWhenEmpty() {
        XCTAssertEqual(HotMenuAction.visibleSlotCount, 4)
        XCTAssertEqual(HotMenuAction.configurationCases.contains(.translationQuickTarget1), false)
        XCTAssertEqual(HotMenuAction.configurationCases.contains(.translationOn), false)
        XCTAssertEqual(HotMenuAction.configurationCases.contains(.styleProfessional), false)
        XCTAssertEqual(HotMenuAction.configurationCases.contains(.selectionRewrite), false)
        XCTAssertEqual(
            HotMenuAction.normalizedActions(
                [.openDashboard, .cycleStyle, .dictation, .toggleTranslation, .cycleASRProvider],
                for: .left
            ),
            [.openDashboard, .cycleStyle, .dictation, .toggleTranslation]
        )
        XCTAssertEqual(HotMenuAction.normalizedActions([], for: .up), HotMenuAction.defaultActions(for: .up))
    }

    func testHotMenuActionRingStateIgnoresNoActionSlots() {
        let actions: [HotMenuDirection: [HotMenuAction]] = [
            .up: [.openConversation, .selectionRewrite, .transcriptionMode, .none],
            .left: [.none, .none],
        ]
        var state = HotMenuActionRingState()

        XCTAssertEqual(state.actionsForDirection(.up, actions: actions), [.openConversation, .transcriptionMode])
        XCTAssertEqual(state.actionsForDirection(.left, actions: actions), [])

        state.select(.up, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .openConversation)

        state.select(.up, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .transcriptionMode)

        state.select(.up, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .openConversation)

        state.select(.left, cycleIfSameDirection: true, actions: actions)
        XCTAssertNil(state.selectedAction(in: actions))
    }

    func testHotMenuActionRingStateCyclesRepeatedDirectionSelections() {
        let actions: [HotMenuDirection: [HotMenuAction]] = [
            .up: [.openConversation, .dictation, .askAI],
            .left: [.cycleASRProvider],
        ]
        var state = HotMenuActionRingState()

        XCTAssertNil(state.selectedAction(in: actions))

        state.select(.up, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .openConversation)

        state.select(.up, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .dictation)

        state.select(.up, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .askAI)

        state.select(.up, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .openConversation)

        state.select(.left, cycleIfSameDirection: true, actions: actions)
        XCTAssertEqual(state.selectedAction(in: actions), .cycleASRProvider)
    }

    func testHotMenuDirectionSelectionUsesDeadZoneAndDominantAxis() {
        XCTAssertNil(HotMenuSelection.direction(deltaX: 8, deltaY: 4, deadZoneRadius: 24))
        XCTAssertEqual(HotMenuSelection.direction(deltaX: 3, deltaY: 42, deadZoneRadius: 24), .up)
        XCTAssertEqual(HotMenuSelection.direction(deltaX: -44, deltaY: 8, deadZoneRadius: 24), .left)
        XCTAssertEqual(HotMenuSelection.direction(deltaX: 52, deltaY: -10, deadZoneRadius: 24), .right)
        XCTAssertEqual(HotMenuSelection.direction(deltaX: 2, deltaY: -36, deadZoneRadius: 24), .down)
    }

    func testHotMenuActionsExposeLabels() {
        XCTAssertEqual(HotMenuAction.openConversation.displayName, "Conversation")
        XCTAssertEqual(HotMenuAction.transcriptionMode.displayName, "Transcription")
        XCTAssertEqual(HotMenuAction.askAI.displayName, "Ask AI")
        XCTAssertEqual(HotMenuAction.dictation.displayName, "Dictation")
        XCTAssertEqual(HotMenuAction.toggleTranslation.displayName, "Translation State")
        XCTAssertEqual(HotMenuAction.translationOn.displayName, "Translation On")
        XCTAssertEqual(HotMenuAction.translationOff.displayName, "Translation Off")
        XCTAssertEqual(HotMenuAction.cycleTranslationLanguage.displayName, "Translation Language")
        XCTAssertEqual(HotMenuAction.translationQuickTarget1.displayName, "Hot Language 1")
        XCTAssertEqual(HotMenuAction.cycleStyle.displayName, "Dictation Style")
        XCTAssertEqual(HotMenuAction.styleProfessional.displayName, "Professional")
        XCTAssertEqual(HotMenuAction.none.displayName, "No Action")
    }

    func testHotMenuStyleActionsMapToProfiles() {
        XCTAssertEqual(HotMenuAction.styleAction(for: .neutral), .styleNeutral)
        XCTAssertEqual(HotMenuAction.styleAction(for: .professional), .styleProfessional)
        XCTAssertEqual(HotMenuAction.styleAction(for: .concise), .styleConcise)
        XCTAssertEqual(HotMenuAction.styleAction(for: .expanded), .styleExpanded)
        XCTAssertEqual(HotMenuAction.styleAction(for: .raw), .styleRaw)
        XCTAssertEqual(HotMenuAction.styleProfessional.styleProfile, .professional)
        XCTAssertNil(HotMenuAction.cycleStyle.styleProfile)
    }

    func testTranslationQuickTargetLanguagesNormalizeAndCycle() {
        var preferences = OmniVoicePreferences.defaults
        preferences.translationQuickTargetLanguages = [" ZH ", "fr", "FR", "", "en", "es"]

        XCTAssertEqual(preferences.normalizedTranslationQuickTargetLanguages(), ["zh", "fr", "en", "es"])

        preferences.translationTargetLanguage = "es"
        XCTAssertEqual(preferences.cycleTranslationTargetLanguage(), "zh")
        XCTAssertEqual(preferences.translationTargetLanguage, "zh")

        XCTAssertEqual(preferences.cycleTranslationTargetLanguage(), "fr")
        XCTAssertEqual(preferences.cycleTranslationTargetLanguage(), "en")
        XCTAssertEqual(preferences.cycleTranslationTargetLanguage(), "es")
        XCTAssertEqual(preferences.cycleTranslationTargetLanguage(), "zh")
    }

    func testConversationAudioBufferReturnsWindowedPCMData() {
        var buffer = ConversationAudioBuffer()
        let first = floatPCMData([0.1, 0.2, 0.3, 0.4])
        let second = floatPCMData([0.5, 0.6, 0.7, 0.8])

        buffer.appendPCMFloat32(first, sampleRate: 1_000)
        buffer.appendPCMFloat32(second, sampleRate: 1_000)

        XCTAssertEqual(buffer.durationMs, 8)
        XCTAssertEqual(buffer.audioPCMFloat32(from: 2, to: 6), floatPCMData([0.3, 0.4, 0.5, 0.6]))
        XCTAssertEqual(buffer.audioPCMFloat32(from: 4, to: 8), second)
        XCTAssertNil(buffer.audioPCMFloat32(from: 12, to: 16))
    }

    func testHotMenuTriggerMomentaryReleaseCommitsAndArmsDoubleTap() {
        var state = HotMenuTriggerState()

        XCTAssertEqual(state.press(at: 10.0), .momentary)
        XCTAssertTrue(state.release(at: 10.12))
        XCTAssertEqual(state.mode, nil)
        XCTAssertTrue(state.canLatch(onPressAt: 10.30))
    }

    func testHotMenuTriggerSecondPressWithinIntervalLatchesOpen() {
        var state = HotMenuTriggerState()

        XCTAssertEqual(state.press(at: 10.0), .momentary)
        XCTAssertTrue(state.release(at: 10.10))
        XCTAssertEqual(state.press(at: 10.32), .latched)
        XCTAssertFalse(state.release(at: 10.42))
        XCTAssertEqual(state.mode, .latched)

        state.finish()

        XCTAssertEqual(state.mode, nil)
        XCTAssertFalse(state.canLatch(onPressAt: 10.50))
    }

    func testHotMenuTriggerSlowSecondPressStaysMomentary() {
        var state = HotMenuTriggerState()

        XCTAssertEqual(state.press(at: 10.0), .momentary)
        XCTAssertTrue(state.release(at: 10.10))
        XCTAssertEqual(state.press(at: 10.80), .momentary)
    }

    func testCleanupRequestDefaultsDictionaryTermsToEmpty() {
        let request = CleanupRequest(rawTranscript: "hello", style: .neutral)

        XCTAssertEqual(request.dictionaryTerms, [])
    }
}

private func floatPCMData(_ samples: [Float]) -> Data {
    samples.withUnsafeBufferPointer { pointer in
        Data(buffer: pointer)
    }
}
