import XCTest
@testable import OmniVoiceCore

final class AgentDescriptorTests: XCTestCase {
    func testArgsTemplateReplacesPromptAsSingleArgument() {
        let d = AgentDescriptor(
            id: "claude", displayName: "Claude", keywords: ["claude"],
            binaryName: "claude",
            invocation: .args(["-p", "{prompt}"]),
            streamFormat: .plainText
        )
        let r = d.render(prompt: "rhymes with bill; rm -rf /")
        XCTAssertEqual(r.args, ["-p", "rhymes with bill; rm -rf /"])
        XCTAssertNil(r.stdin)
    }

    func testStdinModeSendsPromptOnStdinNotArgs() {
        let d = AgentDescriptor(
            id: "x", displayName: "X", keywords: ["x"], binaryName: "x",
            invocation: .stdin(["chat"]), streamFormat: .plainText
        )
        let r = d.render(prompt: "hello")
        XCTAssertEqual(r.args, ["chat"])
        XCTAssertEqual(r.stdin, "hello")
    }
}
