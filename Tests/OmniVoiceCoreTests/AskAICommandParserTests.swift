import XCTest
@testable import OmniVoiceCore

final class AskAICommandParserTests: XCTestCase {
    let kws = ["claude", "gemini"]

    func testAskPrefixExtractsAgentAndQuestion() {
        let i = AskAICommandParser.parse("ask Claude how many names rhyme with Bill",
            knownKeywords: kws, bubbleOpen: false)
        guard case let .ask(k, q) = i else { return XCTFail() }
        XCTAssertEqual(k, "claude")
        XCTAssertEqual(q, "how many names rhyme with Bill")
    }

    func testUnknownAgentIsNotAnAskWhenClosed() {
        XCTAssertEqual(AskAICommandParser.parse("ask Frank a question",
            knownKeywords: kws, bubbleOpen: false), .none)
    }

    func testActionsRecognizedWhileBubbleOpen() {
        XCTAssertEqual(AskAICommandParser.parse("copy that", knownKeywords: kws, bubbleOpen: true),
            .action(.insert))
        XCTAssertEqual(AskAICommandParser.parse("copy to clipboard", knownKeywords: kws, bubbleOpen: true),
            .action(.copy))
        XCTAssertEqual(AskAICommandParser.parse("never mind", knownKeywords: kws, bubbleOpen: true),
            .action(.dismiss))
    }

    func testPlainTranscriptWhileOpenIsFollowUp() {
        XCTAssertEqual(AskAICommandParser.parse("how many have the first name Jack",
            knownKeywords: kws, bubbleOpen: true), .followUp("how many have the first name Jack"))
    }
}
