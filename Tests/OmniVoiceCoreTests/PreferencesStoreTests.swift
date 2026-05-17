import XCTest
@testable import OmniVoiceCore

final class PreferencesStoreTests: XCTestCase {
    func testDefaultsUseParakeetAndNeutralStyle() {
        let preferences = OmniVoicePreferences.defaults

        XCTAssertEqual(preferences.asrProvider, .parakeetTDT)
        XCTAssertEqual(preferences.style, .neutral)
        XCTAssertEqual(preferences.dictionaryTerms, [])
        XCTAssertNil(preferences.microphoneID)
        XCTAssertEqual(preferences.dictationHotkey, .defaultDictation)
        XCTAssertEqual(preferences.styleHotkey, .defaultStyle)
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
        XCTAssertFalse(preferences.liveTranslationEnabled)
        XCTAssertEqual(preferences.translationSourceLanguage, "auto")
        XCTAssertEqual(preferences.translationTargetLanguage, "en")
        XCTAssertEqual(preferences.openAICompatibleBaseURL, "")
        XCTAssertEqual(preferences.openAICompatibleModel, "")
        XCTAssertEqual(preferences.openAICompatibleAPIKey, "")
        XCTAssertFalse(preferences.liveDraftInsertionEnabled)
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
        XCTAssertFalse(preferences.liveTranslationEnabled)
        XCTAssertEqual(preferences.translationSourceLanguage, "auto")
        XCTAssertEqual(preferences.translationTargetLanguage, "en")
        XCTAssertEqual(preferences.openAICompatibleAPIKey, "")
        XCTAssertFalse(preferences.liveDraftInsertionEnabled)
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
        XCTAssertNotNil(object["live_translation_enabled"])
        XCTAssertNotNil(object["translation_source_language"])
        XCTAssertNotNil(object["translation_target_language"])
        XCTAssertNotNil(object["open_ai_compatible_base_url"])
        XCTAssertNotNil(object["open_ai_compatible_model"])
        XCTAssertNotNil(object["open_ai_compatible_api_key"])
        XCTAssertNotNil(object["live_draft_insertion_enabled"])
    }

    func testStyleCycleUpdatesPreference() {
        var preferences = OmniVoicePreferences.defaults

        preferences.cycleStyle()

        XCTAssertEqual(preferences.style, .professional)
    }

    func testProviderCycleUpdatesPreference() {
        var preferences = OmniVoicePreferences.defaults

        preferences.cycleASRProvider()

        XCTAssertEqual(preferences.asrProvider, .canaryQwen25B)
    }

    func testPreferencesRoundTripThroughStore() throws {
        let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)
        let preferences = OmniVoicePreferences(
            asrProvider: .fake,
            style: .concise,
            dictionaryTerms: ["CUDA", "SwiftUI"],
            microphoneID: "BuiltInMicrophoneDevice",
            dictationHotkey: HotkeyBinding(keyCode: 12, modifiers: 2_304),
            styleHotkey: HotkeyBinding(keyCode: 13, modifiers: 2_304),
            themeID: .neonLime,
            customAccentColor: ThemeColor(hex: "#00A3FF"),
            appearanceMode: .dark,
            waveformMode: .glyphStream,
            commitAnimationMode: .beamSnap,
            engineFrameSide: .left,
            engineFrameHandlePosition: 0.72,
            customSpeechModelPath: "/models/custom-stt",
            customTranslationModelPath: "/models/custom-translation",
            liveTranslationEnabled: true,
            translationSourceLanguage: "es",
            translationTargetLanguage: "en",
            openAICompatibleBaseURL: "http://127.0.0.1:11434/v1",
            openAICompatibleModel: "local-qwen",
            openAICompatibleAPIKey: "test-key",
            liveDraftInsertionEnabled: true
        )

        try store.save(preferences)

        XCTAssertEqual(try store.load(), preferences)
    }

    func testModifierOnlyHotkeysRoundTripThroughStore() throws {
        let suiteName = "OmniVoicePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(userDefaults: defaults)
        let preferences = OmniVoicePreferences(
            asrProvider: .parakeetTDT,
            style: .neutral,
            dictionaryTerms: [],
            microphoneID: "USBMicDevice",
            dictationHotkey: .modifierOnly(HotkeyBinding.carbonModifiers(option: true, control: true)),
            styleHotkey: .modifierOnly(HotkeyBinding.carbonModifiers(control: true, shift: true))
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
}
