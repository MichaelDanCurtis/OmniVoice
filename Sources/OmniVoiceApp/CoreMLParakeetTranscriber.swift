import Accelerate
import FluidAudio
import Foundation

/// Native CoreML / Apple Neural Engine Parakeet TDT v3 transcriber powered by `FluidAudio`.
/// Runs directly in-process on Apple Silicon ANE without requiring the Python engine.
actor CoreMLParakeetTranscriber {
    private var manager: AsrManager?
    private var loadingTask: Task<AsrManager, Error>?
    private let converter = AudioConverter(sampleRate: 16_000)

    nonisolated var isModelCached: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3))
    }

    func prepareIfNeeded() async throws {
        _ = try await loadedManager()
    }

    func transcribe(wavData: Data) async throws -> String {
        guard !wavData.isEmpty else { return "" }

        // Fast zero-disk path for standard mono 16-bit PCM WAV buffers produced by AudioCaptureService.
        if let samples = Self.decodeMonoPCM16WAVInMemory(wavData) {
            return try await transcribe(samples16kHz: samples)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-ane-\(UUID().uuidString).wav")
        try wavData.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let samples = try converter.resampleAudioFile(tempURL)
        return try await transcribe(samples16kHz: samples)
    }

    private static func decodeMonoPCM16WAVInMemory(_ data: Data) -> [Float]? {
        guard data.count >= 44 else { return nil }
        return data.withUnsafeBytes { raw -> [Float]? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            // Check "RIFF" ... "WAVEfmt "
            guard base[0] == 0x52, base[1] == 0x49, base[2] == 0x46, base[3] == 0x46,
                  base[8] == 0x57, base[9] == 0x41, base[10] == 0x56, base[11] == 0x45,
                  base[12] == 0x66, base[13] == 0x6D, base[14] == 0x74, base[15] == 0x20 else {
                return nil
            }
            let audioFormat = UInt16(base[20]) | (UInt16(base[21]) << 8)
            let channels = UInt16(base[22]) | (UInt16(base[23]) << 8)
            let sampleRate = UInt32(base[24]) | (UInt32(base[25]) << 8) | (UInt32(base[26]) << 16) | (UInt32(base[27]) << 24)
            let bitsPerSample = UInt16(base[34]) | (UInt16(base[35]) << 8)
            guard audioFormat == 1, channels == 1, bitsPerSample == 16, sampleRate > 0 else { return nil }

            // Locate the "data" chunk (standard offset 36, or scan forward if extra chunks exist)
            var offset = 36
            while offset + 8 <= data.count {
                let isData = base[offset] == 0x64 && base[offset + 1] == 0x61
                    && base[offset + 2] == 0x74 && base[offset + 3] == 0x61
                let chunkSize = Int(UInt32(base[offset + 4])
                    | (UInt32(base[offset + 5]) << 8)
                    | (UInt32(base[offset + 6]) << 16)
                    | (UInt32(base[offset + 7]) << 24))
                offset += 8
                if isData {
                    let byteCount = min(chunkSize, data.count - offset)
                    let sampleCount = byteCount / 2
                    guard sampleCount > 0 else { return [] }
                    var pcm16 = [Int16](repeating: 0, count: sampleCount)
                    for i in 0..<sampleCount {
                        let lo = UInt16(base[offset + i * 2])
                        let hi = UInt16(base[offset + i * 2 + 1])
                        pcm16[i] = Int16(bitPattern: lo | (hi << 8))
                    }
                    return AudioCaptureService.resamplePCM16To16kHzFloat(pcm16, sourceSampleRate: Double(sampleRate))
                }
                offset += chunkSize
            }
            return nil
        }
    }

    func transcribe(samples16kHz: [Float]) async throws -> String {
        // Short-circuit ultra-short taps (< 0.15s) or digital silence before invoking ANE.
        guard samples16kHz.count >= 2_400 else { return "" }
        var peakAmplitude: Float = 0
        samples16kHz.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            vDSP_maxmgv(base, 1, &peakAmplitude, vDSP_Length(buf.count))
        }
        guard peakAmplitude >= 0.0015 else { return "" }

        let asrManager = try await loadedManager()
        var decoderState = try TdtDecoderState(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(samples16kHz, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadedManager() async throws -> AsrManager {
        if let manager, await manager.isAvailable {
            return manager
        }
        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let instance = AsrManager(config: .default)
            try await instance.loadModels(models)
            return instance
        }
        loadingTask = task
        do {
            let loaded = try await task.value
            manager = loaded
            loadingTask = nil
            return loaded
        } catch {
            loadingTask = nil
            throw error
        }
    }
}
