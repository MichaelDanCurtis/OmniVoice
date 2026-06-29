import XCTest
@testable import OmniVoiceCore

final class AskPromptBuilderTests: XCTestCase {
    func testBuildsPreambleHistoryAndQuestion() {
        let p = AskPromptBuilder.build(
            history: [AskTurn(role: .user, text: "names like Bill"),
                      AskTurn(role: .assistant, text: "Bill, Will, Jill")],
            question: "how about Jack")
        XCTAssertTrue(p.contains("plain text"))
        XCTAssertTrue(p.contains("do not use tools"))
        XCTAssertTrue(p.contains("User: names like Bill"))
        XCTAssertTrue(p.contains("Assistant: Bill, Will, Jill"))
        XCTAssertTrue(p.hasSuffix("User: how about Jack"))
    }

    func testTrimsToLastMaxTurns() {
        let history = (0..<40).map { AskTurn(role: .user, text: "q\($0)") }
        let p = AskPromptBuilder.build(history: history, question: "now", maxTurns: 4)
        XCTAssertFalse(p.contains("q0"))
        XCTAssertTrue(p.contains("q39"))
    }
}
