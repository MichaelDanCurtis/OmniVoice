import XCTest
@testable import OmniVoiceCore

final class AgentConfigurationTests: XCTestCase {
    func testConfigurationMapsToDescriptor() {
        let c = AgentConfiguration(
            id: "glm", displayName: "GLM", keyword: "glm",
            binaryPath: "/Users/me/.glm/bin/glm",
            argsTemplate: ["chat", "{prompt}"], usesStdin: false,
            streamFormat: .plainText
        )
        let d = c.descriptor()
        XCTAssertEqual(d.keywords, ["glm"])
        XCTAssertEqual(d.binaryPath, "/Users/me/.glm/bin/glm")
        XCTAssertEqual(d.render(prompt: "hi").args, ["chat", "hi"])
    }

    func testConfigurationRoundTripsThroughCodable() throws {
        let c = AgentConfiguration(id: "glm", displayName: "GLM", keyword: "glm",
            binaryPath: "/x", argsTemplate: ["{prompt}"], usesStdin: true,
            streamFormat: .plainText)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(AgentConfiguration.self, from: data), c)
    }
}
