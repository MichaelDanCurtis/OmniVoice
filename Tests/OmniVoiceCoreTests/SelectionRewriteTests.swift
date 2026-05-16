import XCTest
@testable import OmniVoiceCore

final class SelectionRewriteTests: XCTestCase {
    func testTurnsSelectionIntoBullets() {
        XCTAssertEqual(
            SelectionRewrite.rewrite(selectedText: "First item. Second item.", instruction: "turn this into bullets"),
            "- First item\n- Second item"
        )
    }

    func testMakesSelectionShorter() {
        XCTAssertEqual(
            SelectionRewrite.rewrite(selectedText: "First sentence. Second sentence.", instruction: "make this shorter"),
            "First sentence"
        )
    }

    func testCreatesPoliteReplyFromInstruction() {
        XCTAssertEqual(
            SelectionRewrite.rewrite(selectedText: "Can we meet Tuesday?", instruction: "reply politely that Tuesday works"),
            "Thanks for the note. Tuesday works."
        )
    }

    func testReturnsNilForUnsupportedInstruction() {
        XCTAssertNil(
            SelectionRewrite.rewrite(selectedText: "Keep this.", instruction: "make it sparkle")
        )
    }
}
