import Foundation
import OmniVoiceCore

@MainActor
final class ConversationRecorderService {
    private static let diarizationContextWindowMs = 12_000
    private static let liveDiarizationContextWindowMs = 6_000
    private static let liveDiarizationMinimumIntervalMs = 3_000
    private static let liveDiarizationMinimumAudioMs = 1_500

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
    private var isRecording = false
    private var isStopping = false
    private var activeSessionID: String?
    private var activeGeneration: UUID?
    private var onSegment: ((ConversationSegmentCreateRequest) async -> Void)?
    private var onAssistCard: ((ConversationAssistCardCreateRequest) async -> Void)?
    private var diagnostics: EngineStreamingDiagnostics = .idle
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var openContinuation: CheckedContinuation<Void, Never>?
    private var transcriptAccumulator = ConversationTranscriptAccumulator()
    private var audioBuffer = ConversationAudioBuffer()
    private var segmentTiming = ConversationSegmentTiming()
    private var activeSampleRate = 16_000
    private var liveDiarizationEnabled = false
    private var lastLiveDiarizationRequestMs: Int?
    private var lastLiveSegmentRequest: ConversationSegmentCreateRequest?
    private var settledSegmentEmitted = false
    private let pendingUpdates = ConversationUpdateTracker()

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
        liveDiarizationEnabled: Bool,
        onSegment: @escaping (ConversationSegmentCreateRequest) async -> Void,
        onAssistCard: @escaping (ConversationAssistCardCreateRequest) async -> Void
    ) async throws {
        guard !isRecording, !isStopping else { throw RecorderError.alreadyRecording }

        let generation = UUID()
        activeSessionID = sessionID
        activeGeneration = generation
        self.onSegment = onSegment
        self.onAssistCard = onAssistCard
        diagnostics = .idle
        transcriptAccumulator = ConversationTranscriptAccumulator()
        audioBuffer.reset()
        segmentTiming = ConversationSegmentTiming()
        self.liveDiarizationEnabled = liveDiarizationEnabled
        lastLiveDiarizationRequestMs = nil
        lastLiveSegmentRequest = nil
        settledSegmentEmitted = false
        startedAt = Date()
        isRecording = true
        isStopping = false
        pendingUpdates.start(generation: generation)

        streamingClient.setOnUpdate { [weak self, pendingUpdates] update in
            guard let self else { return }
            guard let token = pendingUpdates.begin(generation: generation) else { return }
            Task { @MainActor in
                defer {
                    pendingUpdates.end(token)
                }
                await self.handle(update, sessionID: sessionID, generation: generation)
            }
        }
        streamingClient.setOnDiagnostics({ [weak self] diagnostics in
            Task { @MainActor in
                guard self?.activeSessionID == sessionID, self?.activeGeneration == generation else { return }
                self?.handle(diagnostics)
            }
        }, emitCurrent: false)
        do {
            let sampleRate = Int(audioCapture.inputSampleRate(deviceUID: microphoneID).rounded())
            activeSampleRate = sampleRate
            audioCapture.onPCMChunk = { [weak self, weak streamingClient] data in
                streamingClient?.sendPCMFloat32(data)
                Task { @MainActor in
                    self?.audioBuffer.appendPCMFloat32(data, sampleRate: sampleRate)
                }
            }
            streamingClient.connect(provider: provider, sampleRate: Double(sampleRate))
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
        let generation = activeGeneration
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
        if let generation {
            await waitForPendingUpdates(generation: generation)
        }
        await emitFallbackFinalSegmentIfNeeded()
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
        if let activeGeneration {
            pendingUpdates.retire(generation: activeGeneration)
        }
        activeGeneration = nil
        onSegment = nil
        onAssistCard = nil
        isRecording = false
        isStopping = false
        diagnostics = .idle
        transcriptAccumulator = ConversationTranscriptAccumulator()
        segmentTiming = ConversationSegmentTiming()
        liveDiarizationEnabled = false
        lastLiveDiarizationRequestMs = nil
        lastLiveSegmentRequest = nil
        settledSegmentEmitted = false
        resumeOpenWaiterIfNeeded(force: true)
        resumeStopWaiterIfNeeded()
    }

    private func handle(_ update: TranscriptUpdate, sessionID: String, generation: UUID) async {
        guard activeSessionID == sessionID, activeGeneration == generation else { return }
        let decision = transcriptAccumulator.ingest(update)
        guard case let .segment(text, isFinal) = decision else { return }
        guard !isFinal || !settledSegmentEmitted else { return }

        let nowMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let timing = segmentTiming.segment(
            nowMs: nowMs,
            isFinal: isFinal,
            audioContextWindowMs: Self.diarizationContextWindowMs
        )
        let liveDiarizationAudioStartMs = max(0, nowMs - Self.liveDiarizationContextWindowMs)
        let shouldIncludeLiveDiarizationAudio = !isFinal && shouldRequestLiveDiarizationPreview(nowMs: nowMs)
        let audio = audioPayload(
            isFinal: isFinal,
            timing: timing,
            nowMs: nowMs,
            liveDiarizationAudioStartMs: liveDiarizationAudioStartMs,
            shouldIncludeLiveDiarizationAudio: shouldIncludeLiveDiarizationAudio
        )
        let request = ConversationSegmentCreateRequest(
            audioStartMs: audioStartMs(
                isFinal: isFinal,
                timing: timing,
                liveDiarizationAudioStartMs: liveDiarizationAudioStartMs,
                audio: audio
            ),
            startMs: timing.startMs,
            endMs: isFinal ? timing.endMs : (audio == nil ? timing.endMs : nowMs),
            text: text,
            state: isFinal ? .settled : .live,
            confidence: nil,
            audioPCMFloat32: audio,
            audioSampleRate: activeSampleRate
        )
        if isFinal {
            settledSegmentEmitted = true
        } else {
            lastLiveSegmentRequest = request
        }

        if let onSegment {
            await onSegment(request)
        }

        if isFinal {
            if let card = ConversationAssistCardDetector.card(for: text) {
                if let onAssistCard {
                    await onAssistCard(card)
                }
            }
        }
    }

    private func emitFallbackFinalSegmentIfNeeded() async {
        guard !settledSegmentEmitted, let onSegment else {
            return
        }

        let nowMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let audioEndMs = max(audioBuffer.durationMs, lastLiveSegmentRequest?.endMs ?? 0)
        let recordingEndMs = audioEndMs > 0 ? audioEndMs : nowMs
        let audio = audioBuffer.audioPCMFloat32(from: 0, to: recordingEndMs)
        guard let request = ConversationSegmentFinalization.fallbackSettledRequest(
            from: lastLiveSegmentRequest,
            recordingEndMs: recordingEndMs,
            audioPCMFloat32: audio,
            audioSampleRate: activeSampleRate
        ) else {
            return
        }

        settledSegmentEmitted = true
        await onSegment(request)
    }

    private func shouldRequestLiveDiarizationPreview(nowMs: Int) -> Bool {
        guard liveDiarizationEnabled, nowMs >= Self.liveDiarizationMinimumAudioMs else {
            return false
        }

        if let lastLiveDiarizationRequestMs,
           nowMs - lastLiveDiarizationRequestMs < Self.liveDiarizationMinimumIntervalMs {
            return false
        }

        lastLiveDiarizationRequestMs = nowMs
        return true
    }

    private func audioPayload(
        isFinal: Bool,
        timing: ConversationSegmentTiming.Segment,
        nowMs: Int,
        liveDiarizationAudioStartMs: Int,
        shouldIncludeLiveDiarizationAudio: Bool
    ) -> Data? {
        if isFinal {
            return audioBuffer.audioPCMFloat32(from: timing.audioStartMs ?? timing.startMs, to: timing.endMs ?? nowMs)
        }

        guard shouldIncludeLiveDiarizationAudio else {
            return nil
        }
        return audioBuffer.audioPCMFloat32(from: liveDiarizationAudioStartMs, to: nowMs)
    }

    private func audioStartMs(
        isFinal: Bool,
        timing: ConversationSegmentTiming.Segment,
        liveDiarizationAudioStartMs: Int,
        audio: Data?
    ) -> Int? {
        guard audio != nil else {
            return nil
        }
        return isFinal ? timing.audioStartMs : liveDiarizationAudioStartMs
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
                try? await Task.sleep(for: .seconds(15))
                await MainActor.run {
                    resumeStopWaiterIfNeeded(force: true)
                }
            }
        }
    }

    private func waitForPendingUpdates(generation: UUID) async {
        await pendingUpdates.waitForIdle(generation: generation)
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
