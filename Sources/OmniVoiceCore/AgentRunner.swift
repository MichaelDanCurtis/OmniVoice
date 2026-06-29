import Foundation

public enum AgentRunError: Error, Equatable, Sendable {
    case notFound
    case failed(String)
}

public protocol AgentRunning: Sendable {
    /// Run the agent CLI for `prompt`, streaming stdout chunks to `onChunk` as they
    /// arrive, and returning the full stdout. Throws `.notFound` if the binary can't
    /// be resolved, `.failed(stderr)` on a non-zero exit.
    func run(_ descriptor: AgentDescriptor, prompt: String,
             onChunk: @escaping @Sendable (String) -> Void) async throws -> String
}

public struct AgentRunner: AgentRunning {
    public init() {}

    public func run(_ descriptor: AgentDescriptor, prompt: String,
                    onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let path = ExecutableResolver.resolve(descriptor) else { throw AgentRunError.notFound }
        let rendered = descriptor.render(prompt: prompt)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = rendered.args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if let stdin = rendered.stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inPipe.fileHandleForWriting.closeFile()
        }

        do { try process.run() } catch { throw AgentRunError.notFound }

        let collected = OutputBox()
        // Resume when stdout reaches EOF (the process closed it / exited). availableData
        // returns empty on EOF; we stream non-empty chunks and resume exactly once.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumer = ResumeOnce(continuation)
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    resumer.fire()
                } else if let chunk = String(data: data, encoding: .utf8) {
                    collected.append(chunk)
                    onChunk(chunk)
                }
            }
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let raw = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentRunError.failed(message.isEmpty ? "exit \(process.terminationStatus)" : message)
        }
        return collected.value
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ s: String) { lock.lock(); storage += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ c: CheckedContinuation<Void, Never>) { continuation = c }
    func fire() {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume()
    }
}
