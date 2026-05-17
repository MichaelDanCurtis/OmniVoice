import XCTest
@testable import OmniVoiceCore

final class TextInsertionTargetPolicyTests: XCTestCase {
    func testCodexNamedAppUsesPasteboardOnlyInsertion() {
        let strategy = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.openai.codex",
            applicationName: "Codex",
            currentValue: "Build iOS Apps",
            selectedRange: NSRange(location: 14, length: 0)
        )

        XCTAssertEqual(strategy, .pasteboardOnly)
    }

    func testBrowserRichComposerUsesPasteboardOnlyInsertion() {
        let strategy = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            currentValue: "Build macOS Apps",
            selectedRange: NSRange(location: 16, length: 0)
        )

        XCTAssertEqual(strategy, .pasteboardOnly)
    }

    func testPlainNativeTextTargetUsesDirectAccessibilityInsertion() {
        let strategy = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            currentValue: "Hello",
            selectedRange: NSRange(location: 5, length: 0)
        )

        XCTAssertEqual(strategy, .directAccessibility)
    }
}
