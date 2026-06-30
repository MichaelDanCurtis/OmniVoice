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
        let inPipe: Pipe?
        if rendered.stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inPipe = pipe
        } else {
            inPipe = nil
        }

        do { try process.run() } catch { throw AgentRunError.notFound }

        // Feed stdin off the calling thread: a prompt larger than the pipe buffer (~64KB,
        // easy with context history + attachments) would otherwise block here before the
        // stdout/stderr readers below start draining → deadlock.
        if let stdin = rendered.stdin, let inPipe {
            let handle = inPipe.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                handle.write(Data(stdin.utf8))
                try? handle.close()
            }
        }

        let collected = OutputBox()
        let errBox = OutputBox()
        // Drain BOTH stdout and stderr concurrently and resume only once both reach EOF.
        // Draining stderr is essential: a chatty CLI (sign-in warnings, progress logs) that
        // fills the 64KB stderr buffer would otherwise block the child, so it never closes
        // stdout and we'd hang forever. Reading both to EOF also leaves errBox complete with
        // no concurrent-read race after waitUntilExit.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let latch = EOFLatch(count: 2, continuation: continuation)
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    latch.signal()
                } else if let chunk = String(data: data, encoding: .utf8) {
                    collected.append(chunk)
                    onChunk(chunk)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    latch.signal()
                } else if let chunk = String(data: data, encoding: .utf8) {
                    errBox.append(chunk)
                }
            }
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = errBox.value.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// Resumes the continuation once `count` EOF signals have arrived (stdout + stderr),
/// exactly once, in a thread-safe way.
private final class EOFLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var continuation: CheckedContinuation<Void, Never>?
    init(count: Int, continuation: CheckedContinuation<Void, Never>) {
        self.remaining = count
        self.continuation = continuation
    }
    func signal() {
        lock.lock()
        remaining -= 1
        let c = remaining <= 0 ? continuation : nil
        if remaining <= 0 { continuation = nil }
        lock.unlock()
        c?.resume()
    }
}
