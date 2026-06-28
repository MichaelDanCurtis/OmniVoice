import XCTest
@testable import OmniVoiceCore

final class AskKeywordResolverTests: XCTestCase {
    let bindings = [
        AskKeywordBinding(id: "1", keyword: "claude", target: AskTarget(kind: .agent, id: "claude")),
        AskKeywordBinding(id: "2", keyword: "ai", target: AskTarget(kind: .textLLM, id: "custom")),
    ]

    func testResolvesCaseInsensitivelyAndTrimmed() {
        XCTAssertEqual(AskKeywordResolver.resolve("  Claude ", in: bindings),
                       AskTarget(kind: .agent, id: "claude"))
        XCTAssertEqual(AskKeywordResolver.resolve("AI", in: bindings),
                       AskTarget(kind: .textLLM, id: "custom"))
    }

    func testReturnsNilWhenUnbound() {
        XCTAssertNil(AskKeywordResolver.resolve("frank", in: bindings))
    }
}
