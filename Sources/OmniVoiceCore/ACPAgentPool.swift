import Foundation

public enum ACPSessionPurpose: String, Hashable, Sendable {
    /// Primed with fast model selection + dictation-polisher cache warmup.
    case cleanup
    /// Full-capability default model for Ask AI, Conversations, Meeting Co-Pilot, and Editor AI.
    case interactive
}

public enum ACPWorkerState: Equatable, Sendable {
    case idle
    case warming
    case ready(modelID: String?)
    case failed(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isWarming: Bool {
        if case .warming = self { return true }
        return false
    }
}

public enum ACPError: Error, LocalizedError, Equatable, Sendable {
    case unsupported
    case notFound
    case processExited(String)
    case protocolError(String)
    case timedOut(Double)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            "This agent does not support ACP."
        case .notFound:
            "Agent binary not found on PATH."
        case .processExited(let detail):
            detail.isEmpty ? "ACP agent exited unexpectedly." : "ACP agent exited: \(detail)"
        case .protocolError(let detail):
            "ACP protocol error: \(detail)"
        case .timedOut(let seconds):
            "ACP request timed out after \(Int(seconds.rounded()))s."
        case .cancelled:
            "ACP request was cancelled."
        }
    }
}

/// Manages warm, persistent Agent Client Protocol (ACP) stdio workers for any ACP-capable
/// CLI agent (Gemini Antigravity `agy acp`, GitHub Copilot `--acp`, OpenCode `acp`, Goose `acp`,
/// Kimi `acp`, Gemini `--acp`, etc.).
///
/// Key UX guarantees:
/// - **Zero-wait cold start for Dictation Cleanup**: `promptIfReady` returns `nil` in <1ms if the
///   worker is still cold-starting, kicking off background warm-up so the first dictation inserts
///   immediately while subsequent dictations run hot with an already-primed prompt cache.
/// - **Shared warm-up for Interactive AI**: `promptWaitingForWarmup` awaits any in-progress warm-up
///   and streams `agent_message_chunk` updates live over stdio JSON-RPC 2.0.
/// - **Automatic cleanup**: unused workers are terminated when switching agents or quitting.
public actor ACPAgentPool {
    public static let shared = ACPAgentPool()

    private struct WorkerKey: Hashable, Sendable {
        let agentID: String
        let purpose: ACPSessionPurpose
    }

    private struct Entry {
        var state: ACPWorkerState = .idle
        var connection: ACPStdioConnection?
        var sessionID: String?
        var activeModelID: String?
        var turnCount: Int = 0
        var warmupTask: Task<Void, Never>?
        var lastFailureAt: Date?
        var isBusy: Bool = false
    }

    private static let failureCooldownSeconds: TimeInterval = 20
    private static let maxCleanupTurnsBeforeRotate = 25
    private static let cleanupPrimePrompt =
        "You are a fast dictation text polisher. For every subsequent user message containing a raw transcript and instructions, return ONLY the cleaned final text with no commentary, quotes, or markdown fences. Reply OK now."

    private var entries: [WorkerKey: Entry] = [:]
    private let processTracker = ACPProcessTracker()
    private var stateChangeHandler: (@Sendable (String, ACPSessionPurpose, ACPWorkerState) -> Void)?

    public init() {}

    public func setOnStateChange(_ handler: (@Sendable (String, ACPSessionPurpose, ACPWorkerState) -> Void)?) {
        stateChangeHandler = handler
    }

    public func state(for agentID: String, purpose: ACPSessionPurpose = .cleanup) -> ACPWorkerState {
        let key = WorkerKey(agentID: agentID, purpose: purpose)
        guard let entry = entries[key] else { return .idle }
        if case .ready = entry.state, entry.connection?.isAlive != true {
            return .idle
        }
        return entry.state
    }

    /// Starts warming an ACP worker in the background without blocking the caller.
    /// No-op if the descriptor doesn't support ACP, or if the worker is already warm/warming.
    public func warmUpIfSupported(_ descriptor: AgentDescriptor, purpose: ACPSessionPurpose = .cleanup) {
        guard descriptor.supportsACP else { return }
        let key = WorkerKey(agentID: descriptor.id, purpose: purpose)

        if let existing = entries[key] {
            if case .ready = existing.state, existing.connection?.isAlive == true {
                return
            }
            if existing.warmupTask != nil, existing.state == .warming {
                return
            }
            if case .failed = existing.state,
               let failedAt = existing.lastFailureAt,
               Date().timeIntervalSince(failedAt) < Self.failureCooldownSeconds {
                return
            }
        }

        _ = startWarmupTask(for: descriptor, purpose: purpose)
    }

    /// Zero-wait cold-start entrypoint for latency-sensitive paths (Dictation Cleanup):
    /// - If the ACP worker is already `.ready` (and not busy), executes immediately over stdio.
    /// - Otherwise kicks off background warm-up (if idle) and returns `nil` immediately (<1ms)
    ///   so dictation can insert the transcript right away without a cold-start stall.
    public func promptIfReady(
        _ descriptor: AgentDescriptor,
        prompt: String,
        purpose: ACPSessionPurpose = .cleanup,
        timeoutSeconds: Double = 9.0,
        onChunk: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> String? {
        guard descriptor.supportsACP else { return nil }
        let key = WorkerKey(agentID: descriptor.id, purpose: purpose)

        guard var entry = entries[key],
              case .ready = entry.state,
              let connection = entry.connection,
              connection.isAlive,
              let sessionID = entry.sessionID,
              !entry.isBusy else {
            warmUpIfSupported(descriptor, purpose: purpose)
            return nil
        }

        entry.isBusy = true
        entries[key] = entry

        defer {
            if var current = entries[key] {
                current.isBusy = false
                entries[key] = current
            }
        }

        do {
            let reply = try await sendPrompt(
                on: connection,
                sessionID: sessionID,
                prompt: prompt,
                timeoutSeconds: timeoutSeconds,
                onChunk: onChunk
            )
            if var current = entries[key] {
                current.turnCount += 1
                entries[key] = current
                if purpose == .cleanup, current.turnCount >= Self.maxCleanupTurnsBeforeRotate {
                    scheduleSessionRotation(descriptor: descriptor, key: key)
                }
            }
            return reply
        } catch {
            // If the connection died, tear it down and re-warm in the background.
            if !connection.isAlive {
                resetEntry(for: key, newState: .idle)
                warmUpIfSupported(descriptor, purpose: purpose)
            }
            return nil
        }
    }

    /// Interactive entrypoint for Ask AI, Conversation Chat & Insights, Meeting Co-Pilot,
    /// Editor AI, and Command Mode: awaits any in-flight warm-up and runs over the warm ACP session.
    public func promptWaitingForWarmup(
        _ descriptor: AgentDescriptor,
        prompt: String,
        purpose: ACPSessionPurpose = .interactive,
        timeoutSeconds: Double? = nil,
        onChunk: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        guard descriptor.supportsACP else { throw ACPError.unsupported }
        let key = WorkerKey(agentID: descriptor.id, purpose: purpose)

        if let existing = entries[key],
           case .ready = existing.state,
           existing.connection?.isAlive == true {
            // Already warm!
        } else {
            let task: Task<Void, Never>
            if let existing = entries[key], let running = existing.warmupTask, existing.state == .warming {
                task = running
            } else {
                task = startWarmupTask(for: descriptor, purpose: purpose)
            }
            await task.value
            try Task.checkCancellation()
        }

        guard var entry = entries[key],
              let connection = entry.connection,
              connection.isAlive else {
            if case .failed(let reason) = entries[key]?.state {
                throw ACPError.processExited(reason)
            }
            throw ACPError.processExited("Warm-up did not produce a live ACP session.")
        }

        // For interactive requests, create a fresh lightweight session (~0.6s on a warm process)
        // when the primary session is busy or has already been used, so unrelated Ask AI /
        // Conversation threads never bleed context into each other.
        let sessionID: String
        if purpose == .interactive, (entry.isBusy || entry.turnCount > 0) {
            let created = try await connection.createSession(cwd: "/tmp")
            sessionID = created.sessionID
        } else if let existingSessionID = entry.sessionID {
            entry.isBusy = true
            entries[key] = entry
            sessionID = existingSessionID
        } else {
            let created = try await connection.createSession(cwd: "/tmp")
            sessionID = created.sessionID
            entry.sessionID = sessionID
            entry.isBusy = true
            entries[key] = entry
        }

        defer {
            if var current = entries[key] {
                current.isBusy = false
                entries[key] = current
            }
        }

        do {
            let reply = try await sendPrompt(
                on: connection,
                sessionID: sessionID,
                prompt: prompt,
                timeoutSeconds: timeoutSeconds,
                onChunk: onChunk
            )
            if var current = entries[key], current.sessionID == sessionID {
                current.turnCount += 1
                entries[key] = current
            }
            return reply
        } catch {
            if !connection.isAlive {
                resetEntry(for: key, newState: .idle)
            }
            throw error
        }
    }

    /// Shuts down all ACP workers whose agentID is not in `activeAgentIDs`.
    public func shutdownExcept(agentIDs activeAgentIDs: Set<String>) {
        let keysToDrop = entries.keys.filter { !activeAgentIDs.contains($0.agentID) }
        for key in keysToDrop {
            resetEntry(for: key, newState: .idle)
            entries.removeValue(forKey: key)
        }
    }

    public func shutdownAll() {
        for key in Array(entries.keys) {
            resetEntry(for: key, newState: .idle)
        }
        entries.removeAll()
        processTracker.terminateAll()
    }

    /// Synchronous teardown safe to call from `NSApplicationDelegate.applicationWillTerminate`.
    public nonisolated func shutdownAllSynchronously() {
        processTracker.terminateAll()
    }

    // MARK: - Internal Lifecycle

    @discardableResult
    private func startWarmupTask(for descriptor: AgentDescriptor, purpose: ACPSessionPurpose) -> Task<Void, Never> {
        let key = WorkerKey(agentID: descriptor.id, purpose: purpose)
        entries[key]?.warmupTask?.cancel()
        if let oldConn = entries[key]?.connection {
            oldConn.terminate()
        }

        var entry = Entry()
        entry.state = .warming
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performWarmup(descriptor: descriptor, key: key)
        }
        entry.warmupTask = task
        entries[key] = entry
        notifyState(key: key, state: .warming)
        return task
    }

    private func performWarmup(descriptor: AgentDescriptor, key: WorkerKey) async {
        guard let acpArgs = descriptor.acpArgs else {
            markFailed(key: key, reason: "ACP not supported")
            return
        }
        guard let executablePath = ExecutableResolver.resolve(descriptor) else {
            markFailed(key: key, reason: "\(descriptor.binaryName) not found on PATH")
            return
        }

        do {
            let connection = try ACPStdioConnection(
                executablePath: executablePath,
                arguments: acpArgs,
                tracker: processTracker
            )

            // 1. ACP initialize handshake
            try await connection.initialize(timeoutSeconds: 15.0)
            try Task.checkCancellation()

            // 2. Create session
            let sessionInfo = try await connection.createSession(cwd: "/tmp", timeoutSeconds: 15.0)
            try Task.checkCancellation()

            var chosenModelID = sessionInfo.currentModelID

            // 3. For cleanup sessions, select fastest preferred model if available, then prime KV cache.
            if key.purpose == .cleanup {
                if let fastModel = Self.pickFastModel(
                    available: sessionInfo.availableModelIDs,
                    preferences: descriptor.acpFastModelPreference
                ), fastModel != chosenModelID {
                    if (try? await connection.setModel(sessionID: sessionInfo.sessionID, modelID: fastModel, timeoutSeconds: 8.0)) != nil {
                        chosenModelID = fastModel
                    }
                }
                try Task.checkCancellation()

                // Prime provider-side prompt cache so subsequent dictations hit cached prefix immediately.
                _ = try? await connection.prompt(
                    sessionID: sessionInfo.sessionID,
                    text: Self.cleanupPrimePrompt,
                    timeoutSeconds: 25.0,
                    onChunk: { _ in }
                )
            }

            try Task.checkCancellation()
            guard connection.isAlive else {
                markFailed(key: key, reason: "ACP process exited during warm-up")
                return
            }

            var updated = entries[key] ?? Entry()
            updated.connection = connection
            updated.sessionID = sessionInfo.sessionID
            updated.activeModelID = chosenModelID
            updated.turnCount = 0
            updated.warmupTask = nil
            updated.lastFailureAt = nil
            updated.state = .ready(modelID: chosenModelID)
            entries[key] = updated
            notifyState(key: key, state: .ready(modelID: chosenModelID))
        } catch is CancellationError {
            resetEntry(for: key, newState: .idle)
        } catch {
            markFailed(key: key, reason: error.localizedDescription)
        }
    }

    private func scheduleSessionRotation(descriptor: AgentDescriptor, key: WorkerKey) {
        guard let connection = entries[key]?.connection, connection.isAlive else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.rotateCleanupSession(descriptor: descriptor, key: key, connection: connection)
        }
    }

    private func rotateCleanupSession(
        descriptor: AgentDescriptor,
        key: WorkerKey,
        connection: ACPStdioConnection
    ) async {
        guard let entry = entries[key], entry.connection === connection, !entry.isBusy else { return }
        do {
            let newSession = try await connection.createSession(cwd: "/tmp", timeoutSeconds: 12.0)
            if let fastModel = Self.pickFastModel(
                available: newSession.availableModelIDs,
                preferences: descriptor.acpFastModelPreference
            ) {
                _ = try? await connection.setModel(sessionID: newSession.sessionID, modelID: fastModel, timeoutSeconds: 6.0)
            }
            _ = try? await connection.prompt(
                sessionID: newSession.sessionID,
                text: Self.cleanupPrimePrompt,
                timeoutSeconds: 20.0,
                onChunk: { _ in }
            )
            if var current = entries[key], current.connection === connection {
                current.sessionID = newSession.sessionID
                current.turnCount = 0
                entries[key] = current
            }
        } catch {
            // Keep existing session if background rotation fails.
        }
    }

    private func sendPrompt(
        on connection: ACPStdioConnection,
        sessionID: String,
        prompt: String,
        timeoutSeconds: Double?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await connection.prompt(
            sessionID: sessionID,
            text: prompt,
            timeoutSeconds: timeoutSeconds,
            onChunk: onChunk
        )
    }

    private func markFailed(key: WorkerKey, reason: String) {
        if let conn = entries[key]?.connection {
            conn.terminate()
        }
        var entry = entries[key] ?? Entry()
        entry.connection = nil
        entry.sessionID = nil
        entry.warmupTask = nil
        entry.isBusy = false
        entry.lastFailureAt = Date()
        entry.state = .failed(reason)
        entries[key] = entry
        notifyState(key: key, state: .failed(reason))
    }

    private func resetEntry(for key: WorkerKey, newState: ACPWorkerState) {
        entries[key]?.warmupTask?.cancel()
        entries[key]?.connection?.terminate()
        var entry = Entry()
        entry.state = newState
        entries[key] = entry
        notifyState(key: key, state: newState)
    }

    private func notifyState(key: WorkerKey, state: ACPWorkerState) {
        stateChangeHandler?(key.agentID, key.purpose, state)
    }

    static func pickFastModel(available: [String], preferences: [String]) -> String? {
        guard !available.isEmpty, !preferences.isEmpty else { return nil }
        for pref in preferences {
            if let exact = available.first(where: { $0.caseInsensitiveCompare(pref) == .orderedSame }) {
                return exact
            }
            if let partial = available.first(where: { $0.lowercased().contains(pref.lowercased()) }) {
                return partial
            }
        }
        return nil
    }
}

// MARK: - Process Tracking (for synchronous app-exit teardown)

private final class ACPProcessTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func register(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        lock.unlock()
    }

    func unregister(_ process: Process) {
        lock.lock()
        processes.removeValue(forKey: ObjectIdentifier(process))
        lock.unlock()
    }

    func terminateAll() {
        lock.lock()
        let active = Array(processes.values)
        processes.removeAll()
        lock.unlock()
        for proc in active where proc.isRunning {
            proc.terminate()
        }
    }
}

// MARK: - Low-level JSON-RPC 2.0 ACP Stdio Connection

private struct ACPSessionInfo: Sendable {
    let sessionID: String
    let currentModelID: String?
    let availableModelIDs: [String]
}

private final class ACPStdioConnection: @unchecked Sendable {
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let sessionID: String?
        let onChunk: (@Sendable (String) -> Void)?
        var collectedText: String
    }

    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private weak var tracker: ACPProcessTracker?

    private let ioQueue = DispatchQueue(label: "com.omnispeak.acp.io", qos: .userInitiated)
    private let lock = NSLock()
    private var nextID: Int = 1
    private var pending: [Int: PendingRequest] = [:]
    private var activePromptBySession: [String: Int] = [:]
    private var lineBuffer = Data()
    private var stderrSnippet = ""
    private var closed = false

    var isAlive: Bool {
        lock.lock()
        let c = closed
        lock.unlock()
        return !c && process.isRunning
    }

    init(executablePath: String, arguments: [String], tracker: ACPProcessTracker) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        if env["GEMINI_CLI_TRUST_WORKSPACE"] == nil {
            env["GEMINI_CLI_TRUST_WORKSPACE"] = "true"
        }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            throw ACPError.notFound
        }

        self.process = proc
        self.stdinHandle = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading
        self.stderrHandle = errPipe.fileHandleForReading
        self.tracker = tracker
        tracker.register(proc)

        startReading()
    }

    deinit {
        terminate()
    }

    func terminate() {
        lock.lock()
        let wasClosed = closed
        closed = true
        let pendingMap = pending
        pending.removeAll()
        activePromptBySession.removeAll()
        let errNote = stderrSnippet
        lock.unlock()

        if !wasClosed {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            try? stdinHandle.close()
            if process.isRunning {
                process.terminate()
            }
            tracker?.unregister(process)
        }

        for (_, req) in pendingMap {
            req.continuation.resume(throwing: ACPError.processExited(errNote))
        }
    }

    func initialize(timeoutSeconds: Double) async throws {
        let params: [String: Any] = [
            "protocolVersion": 1,
            "clientCapabilities": [String: Any](),
        ]
        _ = try await sendRequest(method: "initialize", params: params, timeoutSeconds: timeoutSeconds)
    }

    func createSession(cwd: String, timeoutSeconds: Double = 15.0) async throws -> ACPSessionInfo {
        let params: [String: Any] = [
            "cwd": cwd,
            "mcpServers": [Any](),
        ]
        let resultData = try await sendRequest(method: "session/new", params: params, timeoutSeconds: timeoutSeconds)
        guard let root = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
              let sessionID = root["sessionId"] as? String, !sessionID.isEmpty else {
            throw ACPError.protocolError("session/new did not return a sessionId")
        }

        var currentModelID: String?
        var availableIDs: [String] = []
        if let models = root["models"] as? [String: Any] {
            currentModelID = models["currentModelId"] as? String
            if let list = models["availableModels"] as? [[String: Any]] {
                availableIDs = list.compactMap { $0["modelId"] as? String }
            }
        }
        return ACPSessionInfo(
            sessionID: sessionID,
            currentModelID: currentModelID,
            availableModelIDs: availableIDs
        )
    }

    func setModel(sessionID: String, modelID: String, timeoutSeconds: Double) async throws {
        let params: [String: Any] = [
            "sessionId": sessionID,
            "modelId": modelID,
        ]
        _ = try await sendRequest(method: "session/set_model", params: params, timeoutSeconds: timeoutSeconds)
    }

    func prompt(
        sessionID: String,
        text: String,
        timeoutSeconds: Double?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let params: [String: Any] = [
            "sessionId": sessionID,
            "prompt": [
                ["type": "text", "text": text],
            ],
        ]
        let resultData = try await sendRequest(
            method: "session/prompt",
            params: params,
            sessionIDForStreaming: sessionID,
            timeoutSeconds: timeoutSeconds,
            onChunk: onChunk
        )
        // Result data from prompt contains streamed text encoded as UTF-8 when chunks arrived,
        // or fallback extraction if an implementation puts text in the final result payload.
        if let streamed = String(data: resultData, encoding: .utf8) {
            return streamed
        }
        return ""
    }

    // MARK: - JSON-RPC Framing

    private func sendRequest(
        method: String,
        params: [String: Any],
        sessionIDForStreaming: String? = nil,
        timeoutSeconds: Double?,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> Data {
        try Task.checkCancellation()
        guard isAlive else { throw ACPError.processExited("Process is not running") }

        let requestID: Int = lock.withLock {
            let id = nextID
            nextID += 1
            return id
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params,
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: encoded, encoding: .utf8) else {
            throw ACPError.protocolError("Failed to serialize JSON-RPC request")
        }
        line.append("\n")
        let wireData = Data(line.utf8)

        var timeoutItem: DispatchWorkItem?
        if let timeoutSeconds, timeoutSeconds > 0 {
            let item = DispatchWorkItem { [weak self] in
                self?.abortPendingRequest(id: requestID, sessionID: sessionIDForStreaming, error: ACPError.timedOut(timeoutSeconds))
            }
            timeoutItem = item
            ioQueue.asyncAfter(deadline: .now() + timeoutSeconds, execute: item)
        }
        defer { timeoutItem?.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let shouldWrite: Bool = lock.withLock {
                    guard !closed else { return false }
                    pending[requestID] = PendingRequest(
                        continuation: continuation,
                        sessionID: sessionIDForStreaming,
                        onChunk: onChunk,
                        collectedText: ""
                    )
                    if let sid = sessionIDForStreaming {
                        activePromptBySession[sid] = requestID
                    }
                    return true
                }
                guard shouldWrite else {
                    continuation.resume(throwing: ACPError.processExited("ACP connection closed"))
                    return
                }
                ioQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        try self.stdinHandle.write(contentsOf: wireData)
                    } catch {
                        self.abortPendingRequest(id: requestID, sessionID: sessionIDForStreaming, error: ACPError.processExited(error.localizedDescription))
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.abortPendingRequest(id: requestID, sessionID: sessionIDForStreaming, error: ACPError.cancelled)
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: encoded, encoding: .utf8) else {
            return
        }
        line.append("\n")
        let wireData = Data(line.utf8)
        ioQueue.async { [weak self] in
            try? self?.stdinHandle.write(contentsOf: wireData)
        }
    }

    private func sendErrorResponse(id: Any, code: Int, message: String) {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: encoded, encoding: .utf8) else {
            return
        }
        line.append("\n")
        let wireData = Data(line.utf8)
        ioQueue.async { [weak self] in
            try? self?.stdinHandle.write(contentsOf: wireData)
        }
    }

    private func abortPendingRequest(id: Int, sessionID: String?, error: Error) {
        let req: PendingRequest? = lock.withLock {
            if let sid = sessionID, activePromptBySession[sid] == id {
                activePromptBySession.removeValue(forKey: sid)
            }
            return pending.removeValue(forKey: id)
        }
        guard let req else { return }
        if let sid = sessionID {
            sendNotification(method: "session/cancel", params: ["sessionId": sid])
        }
        req.continuation.resume(throwing: error)
    }

    private func startReading() {
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.terminate()
                return
            }
            self.processStdoutChunk(chunk)
        }
        stderrHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: chunk, encoding: .utf8) {
                self.lock.withLock {
                    if self.stderrSnippet.count < 2048 {
                        self.stderrSnippet.append(text)
                    }
                }
            }
        }
    }

    private func processStdoutChunk(_ chunk: Data) {
        var lines: [Data] = []
        lock.withLock {
            lineBuffer.append(chunk)
            let newline = UInt8(ascii: "\n")
            while let idx = lineBuffer.firstIndex(of: newline) {
                let line = Data(lineBuffer[lineBuffer.startIndex..<idx])
                lineBuffer.removeSubrange(lineBuffer.startIndex...idx)
                if !line.isEmpty {
                    lines.append(line)
                }
            }
        }
        for line in lines {
            handleJSONLine(line)
        }
    }

    private func handleJSONLine(_ line: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return
        }

        // 1. Server-initiated request (has BOTH `id` and `method`, e.g. `session/request_permission`).
        if let reqID = root["id"], let method = root["method"] as? String {
            if method == "session/request_permission" {
                let cancelled: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": reqID,
                    "result": ["outcome": ["outcome": "cancelled"]],
                ]
                if let data = try? JSONSerialization.data(withJSONObject: cancelled),
                   var out = String(data: data, encoding: .utf8) {
                    out.append("\n")
                    let wire = Data(out.utf8)
                    ioQueue.async { [weak self] in try? self?.stdinHandle.write(contentsOf: wire) }
                }
            } else {
                sendErrorResponse(id: reqID, code: -32601, message: "Client method not supported: \(method)")
            }
            return
        }

        // 2. Response to one of our requests (has integer `id`, no `method`).
        if let id = root["id"] as? Int {
            let req: PendingRequest? = lock.withLock {
                guard let found = pending.removeValue(forKey: id) else { return nil }
                if let sid = found.sessionID, activePromptBySession[sid] == id {
                    activePromptBySession.removeValue(forKey: sid)
                }
                return found
            }
            guard let req else { return }

            if let errorObj = root["error"] as? [String: Any] {
                let message = (errorObj["message"] as? String) ?? "Unknown JSON-RPC error"
                req.continuation.resume(throwing: ACPError.protocolError(message))
                return
            }

            if req.sessionID != nil {
                // Streaming prompt completed — return collected text.
                req.continuation.resume(returning: Data(req.collectedText.utf8))
                return
            }

            let resultObj = root["result"] ?? [String: Any]()
            let data = (try? JSONSerialization.data(withJSONObject: resultObj)) ?? Data("{}".utf8)
            req.continuation.resume(returning: data)
            return
        }

        // 3. Notification (`session/update`).
        if let method = root["method"] as? String,
           method == "session/update",
           let params = root["params"] as? [String: Any],
           let sid = params["sessionId"] as? String,
           let update = params["update"] as? [String: Any],
           let updateKind = update["sessionUpdate"] as? String,
           updateKind == "agent_message_chunk",
           let content = update["content"] as? [String: Any],
           let text = content["text"] as? String,
           !text.isEmpty {
            let chunkCallback: (@Sendable (String) -> Void)? = lock.withLock {
                guard let reqID = activePromptBySession[sid], var req = pending[reqID] else {
                    return nil
                }
                req.collectedText.append(text)
                pending[reqID] = req
                return req.onChunk
            }
            chunkCallback?(text)
        }
    }
}
