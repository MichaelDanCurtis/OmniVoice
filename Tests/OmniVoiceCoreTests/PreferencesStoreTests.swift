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
            styleHotkey: HotkeyBinding(keyCode: 13, modifiers: 2_304)
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
