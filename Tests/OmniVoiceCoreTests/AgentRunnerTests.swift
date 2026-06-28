import XCTest
@testable import OmniVoiceCore

final class AgentRunnerTests: XCTestCase {
    func testStreamsStdoutAndReturnsFullOutput() async throws {
        // /bin/echo writes the prompt to stdout; binaryPath set so the resolver returns it.
        let descriptor = AgentDescriptor(
            id: "echo", displayName: "echo", keywords: ["echo"],
            binaryName: "echo", binaryPath: "/bin/echo",
            invocation: .args(["{prompt}"]), streamFormat: .plainText
        )
        let chunks = ChunkCollector()
        let out = try await AgentRunner().run(descriptor, prompt: "hello world") { chunks.add($0) }
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
        XCTAssertTrue(chunks.value.contains("hello world"))
    }

    func testUnresolvedBinaryThrowsNotFound() async {
        let descriptor = AgentDescriptor(
            id: "nope", displayName: "nope", keywords: ["nope"],
            binaryName: "definitely-not-a-real-binary-xyz",
            invocation: .args(["{prompt}"]), streamFormat: .plainText
        )
        do {
            _ = try await AgentRunner().run(descriptor, prompt: "x") { _ in }
            XCTFail("expected notFound")
        } catch AgentRunError.notFound {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

private final class ChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func add(_ s: String) { lock.lock(); storage += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
}
