import XCTest
@testable import OmniVoiceApp

final class AccessibilityPromptGateTests: XCTestCase {
    func testPromptsOnceWhileAccessibilityIsMissing() {
        var gate = AccessibilityPromptGate()

        XCTAssertTrue(gate.shouldPromptAutomatically(isTrusted: false))
        XCTAssertFalse(gate.shouldPromptAutomatically(isTrusted: false))
    }

    func testTrustedStateResetsAutomaticPromptGate() {
        var gate = AccessibilityPromptGate()

        XCTAssertTrue(gate.shouldPromptAutomatically(isTrusted: false))
        XCTAssertFalse(gate.shouldPromptAutomatically(isTrusted: true))
        XCTAssertTrue(gate.shouldPromptAutomatically(isTrusted: false))
    }

    func testManualPromptSuppressesNextAutomaticPrompt() {
        var gate = AccessibilityPromptGate()

        gate.markPrompted()

        XCTAssertFalse(gate.shouldPromptAutomatically(isTrusted: false))
    }
}
