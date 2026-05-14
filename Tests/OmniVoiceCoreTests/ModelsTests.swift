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

    func testCleanupRequestDefaultsDictionaryTermsToEmpty() {
        let request = CleanupRequest(rawTranscript: "hello", style: .neutral)

        XCTAssertEqual(request.dictionaryTerms, [])
    }
}
