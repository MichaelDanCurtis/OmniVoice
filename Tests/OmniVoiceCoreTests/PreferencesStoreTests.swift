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
        XCTAssertEqual(preferences.waveformMode, .bars)
        XCTAssertEqual(preferences.commitAnimationMode, .glyphStream)
        XCTAssertEqual(preferences.engineFrameSide, .right)
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
        XCTAssertEqual(preferences.waveformMode, .bars)
        XCTAssertEqual(preferences.engineFrameSide, .right)
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
            waveformMode: .glyphStream,
            commitAnimationMode: .beamSnap,
            engineFrameSide: .left
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
