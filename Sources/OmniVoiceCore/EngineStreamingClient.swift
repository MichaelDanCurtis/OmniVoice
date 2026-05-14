import Foundation

public final class EngineStreamingClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let queue = DispatchQueue(label: "omnivoice.engine.streaming")
    private var task: URLSessionWebSocketTask?
    private var onUpdate: (@Sendable (TranscriptUpdate) -> Void)?

    public init(baseURL: URL = URL(string: "ws://127.0.0.1:8765")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func setOnUpdate(_ handler: (@Sendable (TranscriptUpdate) -> Void)?) {
        queue.async {
            self.onUpdate = handler
        }
    }

    public func connect(provider: ASRProviderKind, sampleRate: Double) {
        queue.async {
            self.task?.cancel(with: .normalClosure, reason: nil)

            var components = URLComponents(url: self.baseURL.appending(path: "stream"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "provider", value: provider.rawValue),
                URLQueryItem(name: "sample_rate", value: String(Int(sampleRate.rounded()))),
            ]
            let task = self.session.webSocketTask(with: components.url!)
            self.task = task
            task.resume()
            self.receiveNext()
        }
    }

    public func sendPCMFloat32(_ data: Data) {
        queue.async {
            self.task?.send(.data(data)) { _ in }
        }
    }

    public func finish() {
        queue.async {
            self.task?.send(.string("__finish__")) { _ in }
        }
    }

    public func cancel() {
        queue.async {
            self.task?.cancel(with: .normalClosure, reason: nil)
            self.task = nil
        }
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.task != nil else { return }
                if case let .success(message) = result, case let .string(json) = message {
                    if let update = Self.decode(json) {
                        self.onUpdate?(update)
                    }
                    self.receiveNext()
                } else {
                    self.task = nil
                }
            }
        }
    }

    private static func decode(_ json: String) -> TranscriptUpdate? {
        struct StreamingPayload: Decodable {
            let type: String
            let text: String
        }

        guard
            let data = json.data(using: .utf8),
            let payload = try? JSONDecoder().decode(StreamingPayload.self, from: data)
        else {
            return nil
        }

        return TranscriptUpdate(text: payload.text, isFinal: payload.type == "final")
    }
}
