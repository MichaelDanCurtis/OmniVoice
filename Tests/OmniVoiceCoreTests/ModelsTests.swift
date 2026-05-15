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
        XCTAssertEqual(ASRProviderKind.canaryQwen25B.rawValue, "canary-qwen-2.5b")
    }

    func testDefaultHotkeyBindingsMatchPlannedShortcuts() {
        XCTAssertEqual(HotkeyBinding.defaultDictation.keyCode, 49)
        XCTAssertEqual(HotkeyBinding.defaultStyle.keyCode, 1)
        XCTAssertEqual(HotkeyBinding.defaultDictation.modifiers, 2_304)
        XCTAssertEqual(HotkeyBinding.defaultStyle.modifiers, 2_304)
    }

    func testHotkeyBindingsExposeReadableLabels() {
        XCTAssertEqual(HotkeyBinding.defaultDictation.displayName, "⌥⌘Space")
        XCTAssertEqual(HotkeyBinding.defaultStyle.displayName, "⌥⌘S")
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

    func testCleanupRequestDefaultsDictionaryTermsToEmpty() {
        let request = CleanupRequest(rawTranscript: "hello", style: .neutral)

        XCTAssertEqual(request.dictionaryTerms, [])
    }
}
