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

    func testMergedAskKeywordBindingsAddsDiscoveredAgentsWithoutDuplicates() {
        let existing = [
            AskKeywordBinding(id: "builtin-claude", keyword: "claude", target: AskTarget(kind: .agent, id: "claude")),
            AskKeywordBinding(id: "builtin-ai", keyword: "ai", target: AskTarget(kind: .textLLM, id: "openai")),
        ]
        let discovered = [
            DiscoveredAgent(descriptor: AgentRegistry.defaultBuiltIns[0], resolvedPath: "/usr/local/bin/claude"),
            DiscoveredAgent(
                descriptor: AgentRegistry.defaultBuiltIns.first(where: { $0.id == "codex" })!,
                resolvedPath: "/usr/local/bin/codex"
            ),
            DiscoveredAgent(
                descriptor: AgentRegistry.defaultBuiltIns.first(where: { $0.id == "antigravity" })!,
                resolvedPath: "/usr/local/bin/agy"
            ),
        ]

        let merged = AgentRegistry.mergedAskKeywordBindings(existing: existing, discovered: discovered)
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(merged.filter { $0.target == AskTarget(kind: .agent, id: "claude") }.count, 1)
        XCTAssertTrue(merged.contains { $0.keyword == "codex" && $0.target == AskTarget(kind: .agent, id: "codex") })
        XCTAssertTrue(merged.contains { $0.keyword == "antigravity" && $0.target == AskTarget(kind: .agent, id: "antigravity") })
    }
}
