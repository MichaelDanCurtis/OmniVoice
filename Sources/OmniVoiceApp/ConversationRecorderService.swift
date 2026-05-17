import Foundation
import OmniVoiceCore

@MainActor
final class ConversationRecorderService {
    enum RecorderError: LocalizedError {
        case alreadyRecording
        case noActiveSession
        case streamUnavailable

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                "Conversation recording is already active"
            case .noActiveSession:
                "No conversation session is active"
            case .streamUnavailable:
                "Conversation stream did not open"
            }
        }
    }

    private let audioCapture: AudioCaptureService
    private let streamingClient: EngineStreamingClient
    private var startedAt = Date()
    private var segmentIndex = 0
    private var isRecording = false
    private var isStopping = false
    private var activeSessionID: String?
    private var onSegment: ((ConversationSegmentCreateRequest) -> Void)?
    private var onAssistCard: ((ConversationAssistCardCreateRequest) -> Void)?
    private var diagnostics: EngineStreamingDiagnostics = .idle
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var openContinuation: CheckedContinuation<Void, Never>?
    private let speakerCycler = MockConversationDiarizer()

    var recordingActive: Bool { isRecording || isStopping }

    init(
        audioCapture: AudioCaptureService = AudioCaptureService(),
        streamingClient: EngineStreamingClient = EngineStreamingClient()
    ) {
        self.audioCapture = audioCapture
        self.streamingClient = streamingClient
    }

    func start(
        sessionID: String,
        provider: ASRProviderKind,
        microphoneID: String?,
        onSegment: @escaping (ConversationSegmentCreateRequest) -> Void,
        onAssistCard: @escaping (ConversationAssistCardCreateRequest) -> Void
    ) async throws {
        guard !isRecording, !isStopping else { throw RecorderError.alreadyRecording }

        activeSessionID = sessionID
        self.onSegment = onSegment
        self.onAssistCard = onAssistCard
        diagnostics = .idle
        startedAt = Date()
        segmentIndex = 0
        isRecording = true
        isStopping = false

        streamingClient.setOnUpdate { [weak self] update in
            Task { @MainActor in
                self?.handle(update)
            }
        }
        streamingClient.setOnDiagnostics { [weak self] diagnostics in
            Task { @MainActor in
                self?.handle(diagnostics)
            }
        }
        audioCapture.onPCMChunk = { [weak streamingClient] data in
            streamingClient?.sendPCMFloat32(data)
        }

        do {
            let sampleRate = audioCapture.inputSampleRate(deviceUID: microphoneID)
            streamingClient.connect(provider: provider, sampleRate: sampleRate)
            await waitForStreamOpen()
            guard diagnostics.state == .open else { throw RecorderError.streamUnavailable }
            _ = try audioCapture.start(deviceUID: microphoneID)
        } catch {
            cancel()
            throw error
        }
    }

    func stop() async throws {
        guard isRecording, !isStopping else { return }
        isStopping = true

        audioCapture.onPCMChunk = nil
        var stopError: Error?
        do {
            _ = try audioCapture.stopWAVData()
        } catch {
            stopError = error
        }

        streamingClient.finish()
        await waitForStreamFinalization()
        clearRecordingState()

        if let stopError {
            throw stopError
        }
    }

    func cancel() {
        streamingClient.cancel()
        audioCapture.onPCMChunk = nil
        _ = try? audioCapture.stopWAVData()
        clearRecordingState()
    }

    private func clearRecordingState() {
        audioCapture.onPCMChunk = nil
        streamingClient.setOnUpdate(nil)
        streamingClient.setOnDiagnostics(nil)
        activeSessionID = nil
        onSegment = nil
        onAssistCard = nil
        isRecording = false
        isStopping = false
        diagnostics = .idle
        resumeOpenWaiterIfNeeded(force: true)
        resumeStopWaiterIfNeeded()
    }

    private func handle(_ update: TranscriptUpdate) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, activeSessionID != nil else { return }

        let nowMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let speaker = speakerCycler.speaker(forSegmentIndex: segmentIndex, text: text)
        let request = ConversationSegmentCreateRequest(
            speakerID: speaker.id,
            speakerDisplayName: speaker.displayName,
            startMs: max(0, nowMs - 2_500),
            endMs: update.isFinal ? nowMs : nil,
            text: text,
            state: update.isFinal ? .settled : .live,
            confidence: nil
        )
        onSegment?(request)

        if update.isFinal {
            segmentIndex += 1
            if let card = ConversationAssistCardDetector.card(for: text) {
                onAssistCard?(card)
            }
        }
    }

    private func handle(_ diagnostics: EngineStreamingDiagnostics) {
        self.diagnostics = diagnostics
        resumeOpenWaiterIfNeeded()
        resumeStopWaiterIfNeeded()
    }

    private func waitForStreamOpen() async {
        if diagnostics.state == .open {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            openContinuation = continuation
            resumeOpenWaiterIfNeeded()

            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    resumeOpenWaiterIfNeeded(force: true)
                }
            }
        }
    }

    private func waitForStreamFinalization() async {
        if isStreamFinalized {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stopContinuation = continuation
            resumeStopWaiterIfNeeded()

            Task {
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    resumeStopWaiterIfNeeded(force: true)
                }
            }
        }
    }

    private var isStreamFinalized: Bool {
        switch diagnostics.state {
        case .closed, .failed, .cancelled:
            true
        case .idle, .connecting, .open, .closing:
            false
        }
    }

    private func resumeStopWaiterIfNeeded(force: Bool = false) {
        guard force || isStreamFinalized else { return }
        stopContinuation?.resume()
        stopContinuation = nil
    }

    private func resumeOpenWaiterIfNeeded(force: Bool = false) {
        guard let openContinuation else { return }
        if diagnostics.state == .open {
            openContinuation.resume()
            self.openContinuation = nil
        } else if force || diagnostics.state == .failed || diagnostics.state == .cancelled || diagnostics.state == .closed {
            openContinuation.resume()
            self.openContinuation = nil
        }
    }
}

private struct MockConversationDiarizer {
    private let speakers = [
        (id: "speaker-1", displayName: "Speaker 1"),
        (id: "speaker-2", displayName: "Speaker 2"),
        (id: "speaker-3", displayName: "Speaker 3"),
    ]

    func speaker(forSegmentIndex index: Int, text: String) -> (id: String, displayName: String) {
        let normalized = text.lowercased()
        if normalized.hasPrefix("i ") || normalized.hasPrefix("i'm ") {
            return (id: "you", displayName: "You")
        }
        return speakers[index % speakers.count]
    }
}

private enum ConversationAssistCardDetector {
    static func card(for text: String) -> ConversationAssistCardCreateRequest? {
        let normalized = text.lowercased()
        if normalized.contains("how many") || normalized.contains("?") {
            return ConversationAssistCardCreateRequest(
                kind: .question,
                title: "Question Detected",
                body: text,
                sourceReferences: [],
                confidence: 0.6
            )
        }

        if normalized.contains("pst") || normalized.contains("pacific") {
            return ConversationAssistCardCreateRequest(
                kind: .timeZone,
                title: "Time Zone Assist",
                body: "3:00 PM Pacific = 6:00 PM Eastern = 11:00 PM London.",
                sourceReferences: [],
                confidence: 0.75
            )
        }

        return nil
    }
}
