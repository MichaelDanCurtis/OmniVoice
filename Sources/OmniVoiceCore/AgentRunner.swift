import Foundation

public enum AgentRunError: Error, Equatable, Sendable {
    case notFound
    case failed(String)
    case timedOut(Double)
    case cancelled
}

public protocol AgentRunning: Sendable {
    /// Run the agent CLI for `prompt`, streaming stdout chunks to `onChunk` as they
    /// arrive, and returning the full stdout. Throws `.notFound` if the binary can't
    /// be resolved, `.failed(stderr)` on a non-zero exit, `.timedOut` if `timeoutSeconds`
    /// elapses, or `.cancelled` if the enclosing task is cancelled.
    func run(
        _ descriptor: AgentDescriptor,
        prompt: String,
        timeoutSeconds: Double?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

public extension AgentRunning {
    func run(
        _ descriptor: AgentDescriptor,
        prompt: String,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await run(descriptor, prompt: prompt, timeoutSeconds: nil, onChunk: onChunk)
    }
}

public struct AgentRunner: AgentRunning {
    public init() {}

    public func run(
        _ descriptor: AgentDescriptor,
        prompt: String,
        timeoutSeconds: Double? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try Task.checkCancellation()
        guard let path = ExecutableResolver.resolve(descriptor) else { throw AgentRunError.notFound }
        let rendered = descriptor.render(prompt: prompt)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = rendered.args

        var env = ProcessInfo.processInfo.environment
        if env["GEMINI_CLI_TRUST_WORKSPACE"] == nil {
            env["GEMINI_CLI_TRUST_WORKSPACE"] = "true"
        }
        process.environment = env

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
        let abortState = AbortState()
        let outRead = outPipe.fileHandleForReading
        let errRead = errPipe.fileHandleForReading
        let latchBox = LatchBox()

        let terminateProcess: @Sendable (AbortReason) -> Void = { reason in
            abortState.mark(reason)
            outRead.readabilityHandler = nil
            errRead.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
            latchBox.forceResume()
        }

        var timeoutItem: DispatchWorkItem?
        if let timeoutSeconds, timeoutSeconds > 0 {
            let item = DispatchWorkItem {
                terminateProcess(.timedOut(timeoutSeconds))
            }
            timeoutItem = item
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeoutSeconds,
                execute: item
            )
        }
        defer { timeoutItem?.cancel() }

        // Drain BOTH stdout and stderr concurrently and resume once both reach EOF,
        // or immediately if the enclosing Swift Task is cancelled or timeoutSeconds elapses.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let latch = EOFLatch(count: 2, continuation: continuation)
                latchBox.set(latch)
                if abortState.reason != nil {
                    latch.forceResume()
                    return
                }
                outRead.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        latch.signal()
                    } else if let chunk = String(data: data, encoding: .utf8) {
                        collected.append(chunk)
                        onChunk(chunk)
                    }
                }
                errRead.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        latch.signal()
                    } else if let chunk = String(data: data, encoding: .utf8) {
                        errBox.append(chunk)
                    }
                }
            }
        } onCancel: {
            terminateProcess(.cancelled)
        }

        outRead.readabilityHandler = nil
        errRead.readabilityHandler = nil

        if let reason = abortState.reason {
            if process.isRunning {
                process.terminate()
            }
            switch reason {
            case .timedOut(let seconds):
                throw AgentRunError.timedOut(seconds)
            case .cancelled:
                throw AgentRunError.cancelled
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

private enum AbortReason: Sendable {
    case timedOut(Double)
    case cancelled
}

private final class AbortState: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: AbortReason?
    func mark(_ r: AbortReason) {
        lock.lock()
        if storage == nil { storage = r }
        lock.unlock()
    }
    var reason: AbortReason? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LatchBox: @unchecked Sendable {
    private let lock = NSLock()
    private var latch: EOFLatch?
    func set(_ l: EOFLatch) {
        lock.lock()
        latch = l
        lock.unlock()
    }
    func forceResume() {
        lock.lock()
        let l = latch
        lock.unlock()
        l?.forceResume()
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ s: String) { lock.lock(); storage += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
}

/// Resumes the continuation once `count` EOF signals have arrived (stdout + stderr),
/// or immediately on `forceResume()`, strictly once, in a thread-safe way.
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
    func forceResume() {
        lock.lock()
        let c = continuation
        continuation = nil
        remaining = 0
        lock.unlock()
        c?.resume()
    }
}
