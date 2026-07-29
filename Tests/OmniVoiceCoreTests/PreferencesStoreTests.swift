import XCTest
@testable import OmniVoiceCore

final class PreferencesStoreTests: XCTestCase {
    func testDefaultsSeedAskKeywordBindings() {
        let kws = OmniVoicePreferences.defaults.askKeywordBindings.map(\.keyword)
        XCTAssertEqual(kws, ["ai", "claude", "gemini"])
        let ai = OmniVoicePreferences.defaults.askKeywordBindings.first { $0.keyword == "ai" }
        XCTAssertEqual(ai?.target.kind, .textLLM)
        let claude = OmniVoicePreferences.defaults.askKeywordBindings.first { $0.keyword == "claude" }
        XCTAssertEqual(claude?.target, AskTarget(kind: .agent, id: "claude"))
    }

    func testOldPreferencesWithoutBindingsDecodeToSeededDefaults() throws {
        let json = """
        { "asr_provider": "parakeet-tdt-mlx", "style": "neutral", "dictionary_terms": [],
          "microphone_id": null, "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 } }
        """.data(using: .utf8)!
        let prefs = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)
        XCTAssertEqual(prefs.askKeywordBindings.map(\.keyword), ["ai", "claude", "gemini"])
    }

    func testDefaultsUseParakeetMLXAndNeutralStyle() {
        let preferences = OmniVoicePreferences.defaults

        XCTAssertEqual(preferences.asrProvider, .parakeetTDTMLX)
        XCTAssertEqual(preferences.style, .neutral)
        XCTAssertEqual(preferences.dictionaryTerms, [])
        XCTAssertNil(preferences.microphoneID)
        XCTAssertEqual(preferences.dictationHotkey, .defaultDictation)
        XCTAssertEqual(preferences.additionalDictationHotkeys, [])
        XCTAssertEqual(preferences.styleHotkey, .defaultStyle)
        XCTAssertEqual(preferences.hotMenuHotkey, .defaultHotMenu)
        XCTAssertEqual(preferences.additionalDictationHotkeys, [])
        XCTAssertEqual(preferences.transcriptCacheHotkey, .defaultTranscriptCache)
        XCTAssertFalse(preferences.mousePushToTalkEnabled)
        XCTAssertEqual(preferences.mousePushToTalkButton, .defaultPushToTalk)
        XCTAssertFalse(preferences.transcriptCacheMouseEnabled)
        XCTAssertEqual(preferences.transcriptCacheMouseButton, .defaultTranscriptCache)
        XCTAssertEqual(preferences.hotMenuActions(for: .up), [.openConversation, .transcriptionMode, .askAI])
        XCTAssertEqual(preferences.hotMenuActions(for: .left), [.cycleTranslationLanguage])
        XCTAssertEqual(preferences.hotMenuActions(for: .right), [.toggleTranslation])
        XCTAssertEqual(preferences.hotMenuActions(for: .down), [.cycleStyle])
        XCTAssertEqual(preferences.hotMenuUpAction, .openConversation)
        XCTAssertEqual(preferences.hotMenuLeftAction, .cycleTranslationLanguage)
        XCTAssertEqual(preferences.hotMenuRightAction, .toggleTranslation)
        XCTAssertEqual(preferences.hotMenuDownAction, .cycleStyle)
        XCTAssertTrue(preferences.recordingSoundCuesEnabled)
        XCTAssertTrue(preferences.recordingStartCueEnabled)
        XCTAssertTrue(preferences.recordingStopCueEnabled)
        XCTAssertEqual(preferences.recordingCueTiming, .both)
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .start))
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .stop))
        XCTAssertEqual(preferences.recordingCueSet, .glassTap)
        XCTAssertEqual(preferences.recordingCueVolume, 0.28)
        XCTAssertFalse(preferences.firstRunSetupCompleted)
    }

    func testDefaultsIncludeV2ThemeSettings() {
        let preferences = OmniVoicePreferences.defaults

        XCTAssertEqual(preferences.themeID, .auroraBlue)
        XCTAssertEqual(preferences.customAccentColor, ThemeColor(hex: "#38BDF8"))
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.waveformMode, .bars)
        XCTAssertEqual(preferences.commitAnimationMode, .glyphStream)
        XCTAssertEqual(preferences.engineFrameSide, .right)
        XCTAssertEqual(preferences.engineFrameHandlePosition, 0.5)
    }

    func testDefaultsIncludeV2ModelTranslationAndIntegrationSettings() {
        let preferences = OmniVoicePreferences.defaults

        XCTAssertEqual(preferences.customSpeechModelPath, "")
        XCTAssertEqual(preferences.customTranslationModelPath, "")
        XCTAssertEqual(preferences.translationProvider, .translateGemmaMLX)
        XCTAssertEqual(preferences.translationModelProviderID, TranslationModelRecommendation.defaultProviderID)
        XCTAssertEqual(preferences.conversationDiarizationProvider, "none")
        XCTAssertEqual(preferences.conversationDiarizationPrecision, .fp16)
        XCTAssertFalse(preferences.liveConversationDiarizationEnabled)
        XCTAssertFalse(preferences.liveTranslationEnabled)
        XCTAssertEqual(preferences.translationSourceLanguage, "en")
        XCTAssertEqual(preferences.translationTargetLanguage, "es")
        XCTAssertEqual(preferences.translationQuickTargetLanguages, ["zh", "fr", "en"])
        XCTAssertEqual(preferences.openAICompatibleBaseURL, "")
        XCTAssertEqual(preferences.openAICompatibleModel, "")
        XCTAssertEqual(preferences.openAICompatibleAPIKey, "")
        XCTAssertEqual(preferences.textLLMDefaultProvider, .custom)
        XCTAssertEqual(preferences.textLLMProviders.map(\.provider), TextLLMProviderKind.allCases)
        XCTAssertEqual(preferences.textLLMConfiguration(for: TextLLMProviderKind.claude).transport, .anthropic)
        XCTAssertFalse(preferences.textLLMConfiguration(for: TextLLMProviderKind.claude).enabled)
        XCTAssertFalse(preferences.textLLMConfiguration(for: TextLLMProviderKind.openAI).isConfigured)
        XCTAssertFalse(preferences.liveDraftInsertionEnabled)
        XCTAssertEqual(preferences.conversationArchiveFolderPath, ConversationArchive.defaultRootURL().path)
        XCTAssertTrue(preferences.automaticallyArchiveConversations)
        XCTAssertEqual(preferences.hotMenuHotkey, .defaultHotMenu)
        XCTAssertEqual(preferences.transcriptCacheHotkey, .defaultTranscriptCache)
        XCTAssertFalse(preferences.mousePushToTalkEnabled)
        XCTAssertEqual(preferences.mousePushToTalkButton, .defaultPushToTalk)
        XCTAssertFalse(preferences.transcriptCacheMouseEnabled)
        XCTAssertEqual(preferences.transcriptCacheMouseButton, .defaultTranscriptCache)
        XCTAssertEqual(preferences.hotMenuActions(for: .up), [.openConversation, .transcriptionMode, .askAI])
        XCTAssertEqual(preferences.hotMenuActions(for: .left), [.cycleTranslationLanguage])
        XCTAssertEqual(preferences.hotMenuActions(for: .right), [.toggleTranslation])
        XCTAssertEqual(preferences.hotMenuActions(for: .down), [.cycleStyle])
        XCTAssertEqual(preferences.hotMenuUpAction, .openConversation)
        XCTAssertEqual(preferences.hotMenuLeftAction, .cycleTranslationLanguage)
        XCTAssertEqual(preferences.hotMenuRightAction, .toggleTranslation)
        XCTAssertEqual(preferences.hotMenuDownAction, .cycleStyle)
        XCTAssertFalse(preferences.firstRunSetupCompleted)
    }

    func testOldPreferencesDecodeWithThemeDefaults() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 }
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

        XCTAssertEqual(preferences.themeID, .auroraBlue)
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.waveformMode, .bars)
        XCTAssertEqual(preferences.engineFrameSide, .right)
        XCTAssertEqual(preferences.engineFrameHandlePosition, 0.5)
        XCTAssertEqual(preferences.customSpeechModelPath, "")
        XCTAssertEqual(preferences.customTranslationModelPath, "")
        XCTAssertEqual(preferences.translationProvider, .translateGemmaMLX)
        XCTAssertFalse(preferences.liveTranslationEnabled)
        XCTAssertFalse(preferences.liveConversationDiarizationEnabled)
        XCTAssertEqual(preferences.conversationDiarizationPrecision, .fp16)
        XCTAssertEqual(preferences.translationSourceLanguage, "en")
        XCTAssertEqual(preferences.translationTargetLanguage, "es")
        XCTAssertEqual(preferences.translationQuickTargetLanguages, ["zh", "fr", "en"])
        XCTAssertEqual(preferences.openAICompatibleAPIKey, "")
        XCTAssertFalse(preferences.liveDraftInsertionEnabled)
        XCTAssertEqual(preferences.asrProvider, .parakeetTDTMLX)
        XCTAssertEqual(preferences.conversationArchiveFolderPath, ConversationArchive.defaultRootURL().path)
        XCTAssertTrue(preferences.automaticallyArchiveConversations)
        XCTAssertTrue(preferences.recordingSoundCuesEnabled)
        XCTAssertTrue(preferences.recordingStartCueEnabled)
        XCTAssertTrue(preferences.recordingStopCueEnabled)
        XCTAssertEqual(preferences.recordingCueSet, .glassTap)
        XCTAssertEqual(preferences.recordingCueVolume, 0.28)
        XCTAssertEqual(preferences.additionalDictationHotkeys, [])
        XCTAssertEqual(preferences.transcriptCacheHotkey, .defaultTranscriptCache)
        XCTAssertFalse(preferences.mousePushToTalkEnabled)
        XCTAssertEqual(preferences.mousePushToTalkButton, .defaultPushToTalk)
        XCTAssertFalse(preferences.transcriptCacheMouseEnabled)
        XCTAssertEqual(preferences.transcriptCacheMouseButton, .defaultTranscriptCache)
        XCTAssertFalse(preferences.firstRunSetupCompleted)
    }

    func testPreferencesEncodingUsesExplicitSnakeCaseThemeKeys() throws {
        let data = try JSONEncoder().encode(OmniVoicePreferences.defaults)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["theme_id"])
        XCTAssertNotNil(object["custom_accent_color"])
        XCTAssertNotNil(object["appearance_mode"])
        XCTAssertNotNil(object["waveform_mode"])
        XCTAssertNotNil(object["commit_animation_mode"])
        XCTAssertNotNil(object["engine_frame_side"])
        XCTAssertNotNil(object["engine_frame_handle_position"])
        XCTAssertNotNil(object["custom_speech_model_path"])
        XCTAssertNotNil(object["custom_translation_model_path"])
        XCTAssertNotNil(object["translation_provider"])
        XCTAssertNotNil(object["translation_model_provider_id"])
        XCTAssertNotNil(object["conversation_diarization_provider"])
        XCTAssertNotNil(object["conversation_diarization_precision"])
        XCTAssertNotNil(object["live_conversation_diarization_enabled"])
        XCTAssertNotNil(object["live_translation_enabled"])
        XCTAssertNotNil(object["translation_source_language"])
        XCTAssertNotNil(object["translation_target_language"])
        XCTAssertNotNil(object["translation_quick_target_languages"])
        XCTAssertNotNil(object["open_ai_compatible_base_url"])
        XCTAssertNotNil(object["open_ai_compatible_model"])
        XCTAssertNotNil(object["open_ai_compatible_api_key"])
        XCTAssertNotNil(object["text_llm_default_provider"])
        XCTAssertNotNil(object["text_llm_providers"])
        XCTAssertNotNil(object["live_draft_insertion_enabled"])
        XCTAssertNotNil(object["conversation_archive_folder_path"])
        XCTAssertNotNil(object["automatically_archive_conversations"])
        XCTAssertNotNil(object["recording_sound_cues_enabled"])
        XCTAssertNotNil(object["recording_start_cue_enabled"])
        XCTAssertNotNil(object["recording_stop_cue_enabled"])
        XCTAssertNotNil(object["recording_cue_set"])
        XCTAssertNotNil(object["recording_cue_volume"])
        XCTAssertNotNil(object["hot_menu_hotkey"])
        XCTAssertNotNil(object["additional_dictation_hotkeys"])
        XCTAssertNotNil(object["transcript_cache_hotkey"])
        XCTAssertNotNil(object["hot_menu_up_actions"])
        XCTAssertNotNil(object["hot_menu_left_actions"])
        XCTAssertNotNil(object["hot_menu_right_actions"])
        XCTAssertNotNil(object["hot_menu_down_actions"])
        XCTAssertNotNil(object["mouse_push_to_talk_enabled"])
        XCTAssertNotNil(object["mouse_push_to_talk_button"])
        XCTAssertNotNil(object["transcript_cache_mouse_enabled"])
        XCTAssertNotNil(object["transcript_cache_mouse_button"])
        XCTAssertNotNil(object["first_run_setup_completed"])
    }

    func testRecordingCueEventPreferencesCanBeControlledIndependently() {
        var preferences = OmniVoicePreferences.defaults

        preferences.recordingCueTiming = .stop
        XCTAssertFalse(preferences.isRecordingCueEnabled(for: .start))
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .stop))
        XCTAssertEqual(preferences.recordingCueTiming, .stop)

        preferences.recordingCueTiming = .start
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .start))
        XCTAssertFalse(preferences.isRecordingCueEnabled(for: .stop))
        XCTAssertEqual(preferences.recordingCueTiming, .start)

        preferences.recordingCueTiming = .both
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .start))
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .stop))

        preferences.recordingSoundCuesEnabled = false
        XCTAssertFalse(preferences.isRecordingCueEnabled(for: .start))
        XCTAssertFalse(preferences.isRecordingCueEnabled(for: .stop))
    }

    func testRecordingCueTimingExposesThreeWayDisplayNames() {
        XCTAssertEqual(RecordingCueTiming.allCases.map(\.displayName), ["Start", "Stop", "Both"])
    }

    func testRecordingCueTimingNormalizesLegacyBothOffState() {
        let preferences = OmniVoicePreferences(
            asrProvider: .parakeetTDTMLX,
            style: .neutral,
            dictionaryEntries: [],
            recordingStartCueEnabled: false,
            recordingStopCueEnabled: false
        )

        XCTAssertEqual(preferences.recordingCueTiming, .both)
        XCTAssertTrue(preferences.recordingStartCueEnabled)
        XCTAssertTrue(preferences.recordingStopCueEnabled)
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .start))
        XCTAssertTrue(preferences.isRecordingCueEnabled(for: .stop))
    }

    func testLegacyDiarizationPrecisionFallsBackFromProvider() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 },
          "conversation_diarization_provider": "mlx-sortformer-streaming-fp32"
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

        XCTAssertEqual(preferences.conversationDiarizationProvider, "mlx-sortformer-streaming-fp32")
        XCTAssertEqual(preferences.conversationDiarizationPrecision, .fp32)
    }

    func testLegacyOpenAICompatibleSettingsHydrateCustomTextLLMProvider() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 },
          "open_ai_compatible_base_url": "http://127.0.0.1:11434/v1",
          "open_ai_compatible_model": "local-qwen",
          "open_ai_compatible_api_key": "local-key"
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)
        let custom = preferences.textLLMConfiguration(for: TextLLMProviderKind.custom)

        XCTAssertEqual(custom.baseURL, "http://127.0.0.1:11434/v1")
        XCTAssertEqual(custom.model, "local-qwen")
        XCTAssertEqual(custom.apiKey, "local-key")
        XCTAssertTrue(custom.enabled)
        XCTAssertTrue(custom.isConfigured)
    }

    func testLegacySingleHotMenuActionsDecodeIntoActionCycles() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 },
          "hot_menu_hotkey": { "key_code": 123, "modifiers": 2304 },
          "hot_menu_up_action": "open_dashboard",
          "hot_menu_left_action": "cycle_asr_provider",
          "hot_menu_right_action": "dictation",
          "hot_menu_down_action": "cycle_style"
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

        XCTAssertEqual(preferences.hotMenuActions(for: .up), [.openDashboard])
        XCTAssertEqual(preferences.hotMenuActions(for: .left), [.cycleASRProvider])
        XCTAssertEqual(preferences.hotMenuActions(for: .right), [.dictation])
        XCTAssertEqual(preferences.hotMenuActions(for: .down), [.cycleStyle])
    }

    func testLegacyDefaultHotMenuActionDecodesIntoCurrentDefaultCycle() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 },
          "hot_menu_up_action": "open_conversation"
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

        XCTAssertEqual(preferences.hotMenuActions(for: .up), HotMenuAction.defaultActions(for: .up))
    }

    func testSavedLegacyHotMenuDefaultLayoutMigratesToTranslationDefaults() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 },
          "hot_menu_up_actions": ["open_conversation", "dictation", "selection_rewrite"],
          "hot_menu_left_actions": ["selection_rewrite"],
          "hot_menu_right_actions": ["dictation"],
          "hot_menu_down_actions": ["cycle_style"]
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

        XCTAssertEqual(preferences.hotMenuActions(for: .up), [.openConversation, .transcriptionMode, .askAI])
        XCTAssertEqual(preferences.hotMenuActions(for: .left), [.cycleTranslationLanguage])
        XCTAssertEqual(preferences.hotMenuActions(for: .right), [.toggleTranslation])
        XCTAssertEqual(preferences.hotMenuActions(for: .down), [.cycleStyle])
    }

    func testSavedPaddedLegacyHotMenuDefaultLayoutMigratesToTranslationDefaults() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 },
          "hot_menu_up_actions": ["open_conversation", "dictation", "selection_rewrite", "none"],
          "hot_menu_left_actions": ["selection_rewrite"],
          "hot_menu_right_actions": ["dictation"],
          "hot_menu_down_actions": ["cycle_style"]
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

        XCTAssertEqual(preferences.hotMenuActions(for: .up), [.openConversation, .transcriptionMode, .askAI])
        XCTAssertEqual(preferences.hotMenuActions(for: .left), [.cycleTranslationLanguage])
        XCTAssertEqual(preferences.hotMenuActions(for: .right), [.toggleTranslation])
        XCTAssertEqual(preferences.hotMenuActions(for: .down), [.cycleStyle])
    }

    func testSavedTranslationHotMenuDefaultLayoutMigratesToAskAIDefaults() throws {
        let json = """
        {
          "asr_provider": "parakeet-tdt",
          "style": "neutral",
          "dictionary_terms": [],
          "microphone_id": null,
          "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 },
          "hot_menu_up_actions": ["open_conversation", "transcription_mode"],
          "hot_menu_left_actions": ["cycle_translation_language"],
          "hot_menu_right_actions": ["toggle_translation"],
          "hot_menu_down_actions": ["cycle_style"]
        }
        """.data(using: .utf8)!

        let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

        XCTAssertEqual(preferences.hotMenuActions(for: .up), [.openConversation, .transcriptionMode, .askAI])
        XCTAssertEqual(preferences.hotMenuActions(for: .left), [.cycleTranslationLanguage])
        XCTAssertEqual(preferences.hotMenuActions(for: .right), [.toggleTranslation])
        XCTAssertEqual(preferences.hotMenuActions(for: .down), [.cycleStyle])
    }

    func testEffectiveHotMenuLanguagePickerExpandsQuickLanguages() {
        var preferences = OmniVoicePreferences.defaults
        preferences.translationQuickTargetLanguages = ["fr", "zh", "es"]

        XCTAssertEqual(
            preferences.effectiveHotMenuActions(for: .left),
            [.translationQuickTarget3, .translationQuickTarget1, .translationQuickTarget2]
        )

        preferences.translationTargetLanguage = "zh"

        XCTAssertEqual(
            preferences.effectiveHotMenuActions(for: .left),
            [.translationQuickTarget2, .translationQuickTarget3, .translationQuickTarget1]
        )
    }

    func testEffectiveHotMenuActionsExpandStatefulCategoriesFromCurrentState() {
        var preferences = OmniVoicePreferences.defaults
        preferences.liveTranslationEnabled = false
        preferences.style = .professional

        XCTAssertEqual(preferences.effectiveHotMenuActions(for: .right), [.translationOff, .translationOn])
        XCTAssertEqual(
            preferences.effectiveHotMenuActions(for: .down),
            [.styleProfessional, .styleConcise, .styleExpanded, .styleRaw, .styleNeutral]
        )

        preferences.liveTranslationEnabled = true
        preferences.style = .raw

        XCTAssertEqual(preferences.effectiveHotMenuActions(for: .right), [.translationOn, .translationOff])
        XCTAssertEqual(
            preferences.effectiveHotMenuActions(for: .down),
            [.styleRaw, .styleNeutral, .styleProfessional, .styleConcise, .styleExpanded]
        )
    }

    func testEffectiveHotMenuActionsHideNoActionSlots() {
        var preferences = OmniVoicePreferences.defaults
        preferences.setHotMenuActions([.openConversation, .transcriptionMode, .none, .none], for: .up)

        XCTAssertEqual(preferences.effectiveHotMenuActions(for: .up), [.openConversation, .transcriptionMode])
    }

    func testEffectiveHotMenuActionsHideLegacyEditAction() {
        var preferences = OmniVoicePreferences.defaults
        preferences.setHotMenuActions([.selectionRewrite, .cycleASRProvider], for: .left)
        preferences.setHotMenuActions([.selectionRewrite], for: .right)

        XCTAssertEqual(preferences.effectiveHotMenuActions(for: .left), [.cycleASRProvider])
        XCTAssertEqual(preferences.effectiveHotMenuActions(for: .right), [])
    }

    func testHotMenuStatusLabelsUseCurrentPreferenceState() {
        var preferences = OmniVoicePreferences.defaults
        preferences.style = .professional
        preferences.liveTranslationEnabled = true
        preferences.translationQuickTargetLanguages = ["fr", "zh", "es"]

        let languageOptions = [
            TranslationLanguageOption(code: "fr", name: "French"),
            TranslationLanguageOption(code: "zh", name: "Chinese"),
            TranslationLanguageOption(code: "es", name: "Spanish"),
        ]

        XCTAssertEqual(preferences.hotMenuStatusLabel(for: .translationQuickTarget1, targetLanguageOptions: languageOptions), "French")
        XCTAssertEqual(preferences.hotMenuStatusLabel(for: .translationQuickTarget2, targetLanguageOptions: languageOptions), "Chinese")
        XCTAssertEqual(preferences.hotMenuStatusLabel(for: .translationOn, targetLanguageOptions: languageOptions), "Translation On")
        XCTAssertEqual(preferences.hotMenuStatusLabel(for: .translationOff, targetLanguageOptions: languageOptions), "Translation Off")
        XCTAssertEqual(preferences.hotMenuStatusLabel(for: .styleProfessional, targetLanguageOptions: languageOptions), "Professional")
        XCTAssertEqual(preferences.hotMenuStatusLabel(for: .openConversation, targetLanguageOptions: languageOptions), "Conversation")
    }

    func testCaptionTranslationStatusOnlyAppearsWhenLiveTranslationIsEnabled() {
        var preferences = OmniVoicePreferences.defaults
        preferences.translationTargetLanguage = "es"
        let languageOptions = [
            TranslationLanguageOption(code: "es", name: "Spanish"),
        ]

        XCTAssertNil(preferences.captionTranslationStatus(targetLanguageOptions: languageOptions))

        preferences.liveTranslationEnabled = true

        XCTAssertEqual(preferences.captionTranslationStatus(targetLanguageOptions: languageOptions), "Translation On: Spanish")
    }

    func testStyleCycleUpdatesPreference() {
        var preferences = OmniVoicePreferences.defaults

        preferences.cycleStyle()

        XCTAssertEqual(preferences.style, .professional)
    }

    func testProviderCycleUpdatesPreference() {
        var preferences = OmniVoicePreferences.defaults

        preferences.cycleASRProvider()

        XCTAssertEqual(preferences.asrProvider, .whisperLargeV3TurboMLX6Bit)

        preferences.cycleASRProvider()

        XCTAssertEqual(preferences.asrProvider, .canaryQwen25B)

        preferences.cycleASRProvider()

        XCTAssertEqual(preferences.asrProvider, .appleSpeech)

        preferences.cycleASRProvider()

        XCTAssertEqual(preferences.asrProvider, .parakeetTDTMLX)
    }

    func testProviderCycleMigratesLegacyAndFakeSelectionsToParakeetMLX() {
        var legacyPreferences = OmniVoicePreferences.defaults
        legacyPreferences.asrProvider = .parakeetTDT
        legacyPreferences.cycleASRProvider()
        XCTAssertEqual(legacyPreferences.asrProvider, .parakeetTDTMLX)

        var fakePreferences = OmniVoicePreferences.defaults
        fakePreferences.asrProvider = .fake
        fakePreferences.cycleASRProvider()
        XCTAssertEqual(fakePreferences.asrProvider, .parakeetTDTMLX)
    }

    func testDecodedLegacyAndFakeProvidersNormalizeToParakeetMLX() throws {
        for providerID in ["fake", "parakeet-tdt"] {
            let json = """
            {
              "asr_provider": "\(providerID)",
              "style": "neutral",
              "dictionary_terms": [],
              "microphone_id": null,
              "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
              "style_hotkey": { "key_code": 1, "modifiers": 2304 }
            }
            """.data(using: .utf8)!

            let preferences = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)

            XCTAssertEqual(preferences.asrProvider, .parakeetTDTMLX)
            XCTAssertFalse(preferences.firstRunSetupCompleted)
        }
    }

    func testAutoLearnDefaultsTrue() {
        XCTAssertTrue(OmniVoicePreferences.defaults.autoLearnCorrectionsEnabled)
    }

    func testLegacyDictionaryTermsMigrateToEntries() throws {
        // Simulate an old preferences blob: the legacy `dictionary_terms` key, no `dictionary_entries`.
        let data = try JSONEncoder().encode(OmniVoicePreferences.defaults)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["dictionary_entries"] = nil
        object["dictionary_terms"] = ["Figma", "Slack"]
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(OmniVoicePreferences.self, from: legacyData)
        XCTAssertEqual(decoded.dictionaryEntries.map(\.canonical), ["Figma", "Slack"])
        XCTAssertTrue(decoded.dictionaryEntries.allSatisfy { $0.source == .manual })
        XCTAssertEqual(decoded.dictionaryTerms, ["Figma", "Slack"])
    }

    func testPreferencesRoundTripThroughStore() throws {
        let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)
        let preferences = OmniVoicePreferences(
            asrProvider: .fake,
            style: .concise,
            dictionaryEntries: ["CUDA", "SwiftUI"].map { DictionaryEntry(manualTerm: $0, at: Date(timeIntervalSince1970: 0)) },
            microphoneID: "BuiltInMicrophoneDevice",
            dictationHotkey: HotkeyBinding(keyCode: 12, modifiers: 2_304),
            additionalDictationHotkeys: [
                HotkeyBinding(keyCode: 2, modifiers: 2_304),
                HotkeyBinding(keyCode: 3, modifiers: 2_304),
            ],
            styleHotkey: HotkeyBinding(keyCode: 13, modifiers: 2_304),
            hotMenuHotkey: .modifierOnly(HotkeyBinding.carbonModifiers(command: true, option: true, control: true)),
            transcriptCacheHotkey: HotkeyBinding(keyCode: 14, modifiers: 2_304),
            hotMenuUpActions: [.openDashboard, .dictation],
            hotMenuLeftActions: [.toggleTranslation, .cycleASRProvider],
            hotMenuRightActions: [.dictation, .openConversation],
            hotMenuDownActions: [.cycleASRProvider, .cycleStyle],
            themeID: .neonLime,
            customAccentColor: ThemeColor(hex: "#00A3FF"),
            appearanceMode: .dark,
            waveformMode: .glyphStream,
            commitAnimationMode: .beamSnap,
            engineFrameSide: .left,
            engineFrameHandlePosition: 0.72,
            customSpeechModelPath: "/models/custom-stt",
            customTranslationModelPath: "/models/custom-translation",
            translationProvider: .nllbDistilled600M,
            conversationDiarizationProvider: "mlx-sortformer-streaming-fp32",
            conversationDiarizationPrecision: .fp32,
            liveTranslationEnabled: true,
            translationSourceLanguage: "es",
            translationTargetLanguage: "en",
            translationQuickTargetLanguages: ["sv", "fr", "zh", "en"],
            openAICompatibleBaseURL: "http://127.0.0.1:11434/v1",
            openAICompatibleModel: "local-qwen",
            openAICompatibleAPIKey: "test-key",
            liveDraftInsertionEnabled: true,
            conversationArchiveFolderPath: "/Users/tester/Documents/OmniSpeak",
            automaticallyArchiveConversations: false,
            firstRunSetupCompleted: true
        )

        try store.save(preferences)

        XCTAssertEqual(try store.load(), preferences)
    }

    func testEntitlementSnapshotDataRoundTripsThroughStore() throws {
        let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)
        var preferences = OmniVoicePreferences.defaults
        preferences.entitlementSnapshotData = Data("cached-entitlement".utf8)

        try store.save(preferences)

        XCTAssertEqual(try store.load().entitlementSnapshotData, Data("cached-entitlement".utf8))
    }

    func testEntitlementSnapshotDataDefaultsNil() {
        XCTAssertNil(OmniVoicePreferences.defaults.entitlementSnapshotData)
    }

    func testModifierOnlyHotkeysRoundTripThroughStore() throws {
        let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)
        let preferences = OmniVoicePreferences(
            asrProvider: .parakeetTDT,
            style: .neutral,
            dictionaryEntries: [],
            microphoneID: "USBMicDevice",
            dictationHotkey: .modifierOnly(HotkeyBinding.carbonModifiers(option: true, control: true)),
            additionalDictationHotkeys: [
                .modifierOnly(HotkeyBinding.carbonModifiers(command: true, control: true)),
            ],
            styleHotkey: .modifierOnly(HotkeyBinding.carbonModifiers(control: true, shift: true)),
            hotMenuHotkey: .modifierOnly(HotkeyBinding.carbonModifiers(command: true, option: true)),
            transcriptCacheHotkey: .modifierOnly(HotkeyBinding.carbonModifiers(command: true, shift: true))
        )

        try store.save(preferences)

        XCTAssertEqual(try store.load(), preferences)
    }

    func testStoreReturnsDefaultsWhenNoPreferencesAreSaved() throws {
        let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)

        XCTAssertEqual(try store.load(), .defaults)
    }

    func testDefaultsHaveNoCustomAgents() {
        XCTAssertEqual(OmniVoicePreferences.defaults.customAgents, [])
    }

    func testCustomAgentsRoundTripThroughStore() throws {
        let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferencesStore(userDefaults: defaults)
        var prefs = OmniVoicePreferences.defaults
        prefs.customAgents = [AgentConfiguration(id: "glm", displayName: "GLM",
            keyword: "glm", binaryPath: "/x")]
        try store.save(prefs)
        XCTAssertEqual(try store.load().customAgents, prefs.customAgents)
    }

    func testOldPreferencesWithoutCustomAgentsDecodeToEmpty() throws {
        let json = """
        { "asr_provider": "parakeet-tdt-mlx", "style": "neutral", "dictionary_terms": [],
          "microphone_id": null, "dictation_hotkey": { "key_code": 49, "modifiers": 2304 },
          "style_hotkey": { "key_code": 1, "modifiers": 2304 } }
        """.data(using: .utf8)!
        let prefs = try EngineCoding.decoder.decode(OmniVoicePreferences.self, from: json)
        XCTAssertEqual(prefs.customAgents, [])
    }
}
