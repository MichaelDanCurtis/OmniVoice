import XCTest
@testable import OmniVoiceCore

final class ExecutableResolverTests: XCTestCase {
    func testReturnsExplicitBinaryPathWhenExecutable() {
        let d = AgentDescriptor(id: "x", displayName: "X", keywords: ["x"],
            binaryName: "x", binaryPath: "/bin/echo",
            invocation: .args(["{prompt}"]), streamFormat: .plainText)
        XCTAssertEqual(ExecutableResolver.resolve(d), "/bin/echo")
    }

    func testResolvesKnownBinaryViaLoginShell() {
        let d = AgentDescriptor(id: "ls", displayName: "ls", keywords: ["ls"],
            binaryName: "ls", invocation: .args(["{prompt}"]), streamFormat: .plainText)
        XCTAssertNotNil(ExecutableResolver.resolve(d))   // ls is on the login PATH
    }
}
