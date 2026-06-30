import Foundation

public enum EngineStreamingConnectionState: String, Codable, Equatable, Sendable {
    case idle
    case connecting
    case open
    case closing
    case closed
    case failed
    case cancelled

    public var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .connecting:
            "Connecting"
        case .open:
            "Open"
        case .closing:
            "Closing"
        case .closed:
            "Closed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }
}

public struct EngineStreamingDiagnostics: Codable, Equatable, Sendable {
    public var state: EngineStreamingConnectionState
    public var providerID: String?
    public var sampleRate: Double
    public var chunksSent: Int
    public var bytesSent: Int
    public var updatesReceived: Int
    public var partialsReceived: Int
    public var finalsReceived: Int
    public var droppedChunks: Int
    public var droppedBytes: Int
    public var lastText: String
    public var lastError: String?

    public static let idle = EngineStreamingDiagnostics(
        state: .idle,
        providerID: nil,
        sampleRate: 0,
        chunksSent: 0,
        bytesSent: 0,
        updatesReceived: 0,
        partialsReceived: 0,
        finalsReceived: 0,
        droppedChunks: 0,
        droppedBytes: 0,
        lastText: "",
        lastError: nil
    )

    public init(
        state: EngineStreamingConnectionState,
        providerID: String?,
        sampleRate: Double,
        chunksSent: Int,
        bytesSent: Int,
        updatesReceived: Int,
        partialsReceived: Int,
        finalsReceived: Int,
        droppedChunks: Int,
        droppedBytes: Int,
        lastText: String,
        lastError: String?
    ) {
        self.state = state
        self.providerID = providerID
        self.sampleRate = sampleRate
        self.chunksSent = chunksSent
        self.bytesSent = bytesSent
        self.updatesReceived = updatesReceived
        self.partialsReceived = partialsReceived
        self.finalsReceived = finalsReceived
        self.droppedChunks = droppedChunks
        self.droppedBytes = droppedBytes
        self.lastText = lastText
        self.lastError = lastError
    }
}

public struct TranslationStreamConfiguration: Codable, Equatable, Sendable {
    public let provider: TranslationProviderKind
    public let sourceLanguage: String
    public let targetLanguage: String
    public let modelPath: String

    public init(
        provider: TranslationProviderKind,
        sourceLanguage: String,
        targetLanguage: String,
        modelPath: String = ""
    ) {
        self.provider = provider
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.modelPath = modelPath
    }
}

public final class EngineStreamingClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let queue = DispatchQueue(label: "omnivoice.engine.streaming")
    private var task: URLSessionWebSocketTask?
    private let connectionGate = EngineStreamingConnectionGate()
    private var connectionToken: EngineStreamingConnectionToken?
    private var onUpdate: (@Sendable (TranscriptUpdate) -> Void)?
    private var onDiagnostics: (@Sendable (EngineStreamingDiagnostics) -> Void)?
    private var diagnostics: EngineStreamingDiagnostics = .idle
    private var lastDiagnosticsEmit: DispatchTime = .now()

    public init(baseURL: URL = URL(string: "ws://127.0.0.1:8765")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func setOnUpdate(_ handler: (@Sendable (TranscriptUpdate) -> Void)?) {
        queue.async {
            self.onUpdate = handler
        }
    }

    public func setOnDiagnostics(
        _ handler: (@Sendable (EngineStreamingDiagnostics) -> Void)?,
        emitCurrent: Bool = true
    ) {
        queue.async {
            self.onDiagnostics = handler
            if emitCurrent {
                handler?(self.diagnostics)
            }
        }
    }

    public func connect(
        provider: ASRProviderKind,
        sampleRate: Double,
        translation: TranslationStreamConfiguration? = nil
    ) {
        queue.async {
            self.task?.cancel(with: .normalClosure, reason: nil)
            let token = self.connectionGate.start()
            self.connectionToken = token
            self.updateDiagnostics {
                $0 = EngineStreamingDiagnostics(
                    state: .connecting,
                    providerID: provider.rawValue,
                    sampleRate: sampleRate,
                    chunksSent: 0,
                    bytesSent: 0,
                    updatesReceived: 0,
                    partialsReceived: 0,
                    finalsReceived: 0,
                    droppedChunks: 0,
                    droppedBytes: 0,
                    lastText: "",
                    lastError: nil
                )
            }

            let task = self.session.webSocketTask(
                with: Self.streamURL(
                    baseURL: self.baseURL,
                    provider: provider,
                    sampleRate: sampleRate,
                    translation: translation
                )
            )
            self.task = task
            task.resume()
            self.updateDiagnostics { $0.state = .open }
            self.receiveNext(task: task, token: token)
        }
    }

    public static func streamURL(
        baseURL: URL,
        provider: ASRProviderKind,
        sampleRate: Double,
        translation: TranslationStreamConfiguration? = nil
    ) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "stream"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "sample_rate", value: String(Int(sampleRate.rounded()))),
        ]

        if let translation {
            queryItems.append(contentsOf: [
                URLQueryItem(name: "translate", value: "true"),
                URLQueryItem(name: "translation_provider", value: translation.provider.rawValue),
                URLQueryItem(name: "source_language", value: translation.sourceLanguage),
                URLQueryItem(name: "target_language", value: translation.targetLanguage),
                URLQueryItem(name: "translation_model_path", value: translation.modelPath),
            ])
        }

        components.queryItems = queryItems
        return components.url!
    }

    public func sendPCMFloat32(_ data: Data) {
        queue.async {
            guard let task = self.task, let token = self.connectionToken else {
                self.updateDiagnostics {
                    $0.droppedChunks += 1
                    $0.droppedBytes += data.count
                }
                return
            }

            self.updateDiagnostics {
                $0.chunksSent += 1
                $0.bytesSent += data.count
            }
            task.send(.data(data)) { [weak self] error in
                guard let self, let error else { return }
                self.queue.async {
                    guard self.isCurrent(task: task, token: token) else { return }
                    self.updateDiagnostics {
                        $0.state = .failed
                        $0.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    public func finish() {
        queue.async {
            guard let task = self.task, let token = self.connectionToken else {
                self.updateDiagnostics { $0.state = .closed }
                return
            }

            self.updateDiagnostics { $0.state = .closing }
            task.send(.string("__finish__")) { [weak self] error in
                guard let self, let error else { return }
                self.queue.async {
                    guard self.isCurrent(task: task, token: token) else { return }
                    self.updateDiagnostics {
                        $0.state = .failed
                        $0.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    public func cancel() {
        queue.async {
            self.task?.cancel(with: .normalClosure, reason: nil)
            if let token = self.connectionToken {
                self.connectionGate.clear(token)
            }
            self.connectionToken = nil
            self.task = nil
            self.updateDiagnostics { $0.state = .cancelled }
        }
    }

    private func receiveNext(task: URLSessionWebSocketTask, token: EngineStreamingConnectionToken) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.isCurrent(task: task, token: token) else { return }
                if case let .success(message) = result, case let .string(json) = message {
                    if let update = Self.decode(json) {
                        self.updateDiagnostics {
                            $0.updatesReceived += 1
                            if update.isFinal {
                                $0.finalsReceived += 1
                            } else {
                                $0.partialsReceived += 1
                            }
                            $0.lastText = update.text
                        }
                        self.onUpdate?(update)
                    }
                    self.receiveNext(task: task, token: token)
                } else if case .success = result {
                    self.receiveNext(task: task, token: token)
                } else {
                    if case let .failure(error) = result,
                       self.diagnostics.state != .closing,
                       self.diagnostics.state != .cancelled {
                        self.updateDiagnostics {
                            $0.state = .failed
                            $0.lastError = error.localizedDescription
                        }
                    } else if self.diagnostics.state == .closing {
                        self.updateDiagnostics { $0.state = .closed }
                    }
                    self.connectionGate.clear(token)
                    self.connectionToken = nil
                    self.task = nil
                }
            }
        }
    }

    private func isCurrent(task: URLSessionWebSocketTask, token: EngineStreamingConnectionToken) -> Bool {
        self.task === task && connectionGate.isCurrent(token)
    }

    // Called on the serial `queue` for every mutation, including per-audio-chunk counter
    // bumps (~15/s). Emitting each one writes the @Observable AppModel and re-renders the
    // whole SwiftUI tree during dictation. Emit immediately on important changes (state or a
    // new error), but coalesce high-frequency counter updates to ~4/s.
    private func updateDiagnostics(_ update: (inout EngineStreamingDiagnostics) -> Void) {
        let previousState = diagnostics.state
        let previousError = diagnostics.lastError
        update(&diagnostics)
        let important = diagnostics.state != previousState || diagnostics.lastError != previousError
        let now = DispatchTime.now()
        let elapsedMs = (now.uptimeNanoseconds &- lastDiagnosticsEmit.uptimeNanoseconds) / 1_000_000
        if important || elapsedMs >= 250 {
            lastDiagnosticsEmit = now
            onDiagnostics?(diagnostics)
        }
    }

    private static let streamingDecoder = JSONDecoder()

    private static func decode(_ json: String) -> TranscriptUpdate? {
        struct StreamingPayload: Decodable {
            let type: String
            let text: String
        }

        guard
            let data = json.data(using: .utf8),
            let payload = try? streamingDecoder.decode(StreamingPayload.self, from: data)
        else {
            return nil
        }

        return TranscriptUpdate(text: payload.text, isFinal: payload.type == "final")
    }
}
