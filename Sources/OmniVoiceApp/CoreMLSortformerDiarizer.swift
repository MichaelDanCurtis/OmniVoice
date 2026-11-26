import FluidAudio
import Foundation
import OmniVoiceCore

/// Native CoreML / Apple Neural Engine streaming Sortformer speaker diarizer powered by `FluidAudio`.
actor CoreMLSortformerDiarizer {
    private var diarizer: SortformerDiarizer?
    private var loadingTask: Task<Void, Error>?

    func prepareIfNeeded() async throws {
        _ = try await loadedDiarizer()
    }

    func diarize(samples16kHz: [Float], sessionID: String) async throws -> [SpeakerTurn] {
        guard !samples16kHz.isEmpty else { return [] }
        let activeDiarizer = try await loadedDiarizer()
        activeDiarizer.reset()
        let timeline = try activeDiarizer.processComplete(samples16kHz)

        var turns: [SpeakerTurn] = []
        for speaker in timeline.speakers.values.sorted(by: { $0.index < $1.index }) {
            let speakerID = "speaker_\(speaker.index + 1)"
            for segment in speaker.finalizedSegments {
                let startMs = max(0, Int((segment.startTime * 1_000).rounded()))
                let endMs = max(startMs, Int((segment.endTime * 1_000).rounded()))
                turns.append(
                    SpeakerTurn(
                        id: segment.id.uuidString,
                        sessionID: sessionID,
                        speakerID: speakerID,
                        startMs: startMs,
                        endMs: endMs,
                        confidence: Double(segment.activity),
                        overlap: false,
                        sourceProvider: "sortformer-coreml-ane"
                    )
                )
            }
        }
        return turns.sorted { ($0.startMs, $0.speakerID) < ($1.startMs, $1.speakerID) }
    }

    private func loadedDiarizer() async throws -> SortformerDiarizer {
        if let diarizer {
            return diarizer
        }
        if let loadingTask {
            try await loadingTask.value
            if let diarizer {
                return diarizer
            }
        }

        let task = Task<Void, Error> {
            let config = SortformerConfig.default
            let models = try await SortformerModels.loadFromHuggingFace(config: config)
            let instance = SortformerDiarizer(config: config)
            instance.initialize(models: models)
            self.setLoadedDiarizer(instance)
        }
        loadingTask = task
        do {
            try await task.value
            loadingTask = nil
            guard let diarizer else {
                throw SortformerError.notInitialized
            }
            return diarizer
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private func setLoadedDiarizer(_ instance: SortformerDiarizer) {
        self.diarizer = instance
    }
}
