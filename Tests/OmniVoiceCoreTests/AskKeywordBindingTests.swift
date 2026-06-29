import XCTest
@testable import OmniVoiceCore

final class AskKeywordBindingTests: XCTestCase {
    func testBindingRoundTripsThroughCodable() throws {
        let b = AskKeywordBinding(id: "1", keyword: "claude",
            target: AskTarget(kind: .agent, id: "claude"))
        let data = try JSONEncoder().encode(b)
        XCTAssertEqual(try JSONDecoder().decode(AskKeywordBinding.self, from: data), b)
    }

    func testTextLLMTargetCarriesProviderID() {
        let t = AskTarget(kind: .textLLM, id: "anthropic")
        XCTAssertEqual(t.kind, .textLLM)
        XCTAssertEqual(t.id, "anthropic")
    }
}
