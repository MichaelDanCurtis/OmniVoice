import Foundation
import OmniVoiceCore

/// Native Swift Deepgram REST + real-time WebSocket client for Service Mode (Cloud / Outbound).
enum DeepgramClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpError(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Deepgram API key is missing. Add it in Settings → Models → Service Mode."
        case .invalidURL:
            "Could not build Deepgram request URL."
        case .httpError(let code, let message):
            message.isEmpty ? "Deepgram returned HTTP \(code)." : "Deepgram (\(code)): \(message)"
        case .invalidResponse:
            "Deepgram returned an unexpected response."
        }
    }
}

enum DeepgramClient {
    static func transcribe(
        wavData: Data,
        config: ServiceModeConfiguration,
        apiKey: String
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepgramClientError.missingAPIKey }
        guard !wavData.isEmpty else { return "" }
        guard let url = DeepgramAPIHelper.restListenURL(config: config) else {
            throw DeepgramClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepgramClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = parseErrorMessage(from: data)
            throw DeepgramClientError.httpError(statusCode: http.statusCode, message: body)
        }
        return DeepgramAPIHelper.parseRESTTranscript(from: data) ?? ""
    }

    /// Lightweight API-key validation via `/v1/projects` (consumes zero audio credits).
    static func testConnection(apiKey: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepgramClientError.missingAPIKey }
        guard let url = URL(string: "https://api.deepgram.com/v1/projects") else {
            throw DeepgramClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepgramClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = parseErrorMessage(from: data)
            throw DeepgramClientError.httpError(statusCode: http.statusCode, message: body)
        }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let projects = root["projects"] as? [[String: Any]],
           let first = projects.first,
           let name = first["name"] as? String, !name.isEmpty {
            return "Connected to Deepgram (\(name))"
        }
        return "Connected to Deepgram"
    }

    private static func parseErrorMessage(from data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errMsg = root["err_msg"] as? String, !errMsg.isEmpty { return errMsg }
            if let message = root["message"] as? String, !message.isEmpty { return message }
            if let error = root["error"] as? String, !error.isEmpty { return error }
        }
        return String(data: data.prefix(200), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// Real-time Deepgram WebSocket streaming session for sub-200ms live captions & live draft typing.
final class DeepgramStreamingSession: @unchecked Sendable {
    private let lock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var committedSegments: [String] = []
    private var latestInterim: String = ""
    private var isClosed = false
    private var finishContinuation: CheckedContinuation<String, Never>?

    var onPartial: (@Sendable (String) -> Void)?

    func start(config: ServiceModeConfiguration, sampleRate: Int, apiKey: String) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DeepgramClientError.missingAPIKey }
        guard let url = DeepgramAPIHelper.streamingListenURL(config: config, sampleRate: sampleRate) else {
            throw DeepgramClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.webSocketTask(with: request)
        lock.withLock {
            webSocketTask = task
            committedSegments = []
            latestInterim = ""
            isClosed = false
        }
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task)
        }
    }

    func sendPCM16(_ data: Data) {
        guard !data.isEmpty else { return }
        let task: URLSessionWebSocketTask? = lock.withLock {
            isClosed ? nil : webSocketTask
        }
        task?.send(.data(data)) { _ in }
    }

    /// Tells Deepgram to flush remaining speech, waits briefly for final segments, and returns
    /// the combined transcript (empty string if socket closed before any words arrived).
    func finish() async -> String {
        let task: URLSessionWebSocketTask? = lock.withLock {
            guard !isClosed else { return nil }
            return webSocketTask
        }
        guard let task else {
            return combinedTranscript()
        }

        // Ask Deepgram to finalize any buffered audio.
        try? await task.send(.string(#"{"type":"CloseStream"}"#))

        return await withTaskGroup(of: String.self) { group in
            group.addTask { [weak self] in
                guard let self else { return "" }
                return await withCheckedContinuation { continuation in
                    let immediateResult: String? = self.lock.withLock {
                        if self.isClosed {
                            return self.buildTranscriptLocked()
                        }
                        self.finishContinuation = continuation
                        return nil
                    }
                    if let immediateResult {
                        continuation.resume(returning: immediateResult)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(900))
                return self.combinedTranscript()
            }
            let first = await group.next() ?? self.combinedTranscript()
            group.cancelAll()
            self.cancel()
            return first
        }
    }

    func cancel() {
        let (task, cont): (URLSessionWebSocketTask?, CheckedContinuation<String, Never>?) = lock.withLock {
            isClosed = true
            let t = webSocketTask
            webSocketTask = nil
            let c = finishContinuation
            finishContinuation = nil
            return (t, c)
        }
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        cont?.resume(returning: combinedTranscript())
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleServerMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleServerMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }

        let cont: CheckedContinuation<String, Never>? = lock.withLock {
            isClosed = true
            let c = finishContinuation
            finishContinuation = nil
            return c
        }
        cont?.resume(returning: combinedTranscript())
    }

    private func handleServerMessage(_ text: String) {
        guard let event = DeepgramAPIHelper.parseStreamEvent(from: text) else { return }

        let (combined, callback): (String, (@Sendable (String) -> Void)?) = lock.withLock {
            if event.isFinal {
                if !event.transcript.isEmpty {
                    committedSegments.append(event.transcript)
                }
                latestInterim = ""
            } else {
                latestInterim = event.transcript
            }
            return (buildTranscriptLocked(), onPartial)
        }

        if !combined.isEmpty {
            callback?(combined)
        }
    }

    private func combinedTranscript() -> String {
        lock.withLock { buildTranscriptLocked() }
    }

    private func buildTranscriptLocked() -> String {
        var parts = committedSegments
        if !latestInterim.isEmpty {
            parts.append(latestInterim)
        }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
