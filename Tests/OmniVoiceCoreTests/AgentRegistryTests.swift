import XCTest
@testable import OmniVoiceCore

final class AgentRegistryTests: XCTestCase {
    func testResolvesBuiltInKeywordCaseInsensitively() {
        let r = AgentRegistry(custom: [])
        XCTAssertEqual(r.resolve(keyword: "Claude")?.id, "claude")
        XCTAssertEqual(r.resolve(keyword: "gemini")?.id, "gemini")
        XCTAssertNil(r.resolve(keyword: "nope"))
    }

    func testCustomAgentKeywordResolves() {
        let r = AgentRegistry(custom: [AgentConfiguration(id: "glm",
            displayName: "GLM", keyword: "glm", binaryPath: "/x")])
        XCTAssertEqual(r.resolve(keyword: "glm")?.binaryPath, "/x")
    }

    func testBuiltInsUsePlainTextForV1() {
        for d in AgentRegistry.defaultBuiltIns { XCTAssertEqual(d.streamFormat, .plainText) }
    }
}
