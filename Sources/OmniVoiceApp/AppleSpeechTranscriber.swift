import AVFoundation
import Foundation
import OmniVoiceCore
import Speech

/// Whether the Apple Speech (SpeechAnalyzer) provider can run on this machine.
enum AppleSpeechAvailability {
    static var isSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
}

/// Streaming dictation via Apple's built-in SpeechAnalyzer/SpeechTranscriber
/// (macOS 26+, the same APIs yap uses). Fully on-device; the OS downloads and
/// manages the model (AssetInventory), so this provider needs no engine and no
/// Hugging Face downloads. Volatile results drive live captions; finalized
/// results accumulate via `AppleSpeechTranscriptAssembler`.
///
/// `@unchecked Sendable`: `append(pcm:)` is only called from the audio-capture
/// callback thread, the assembler is only mutated on the results task, and the
/// AsyncStream continuation is thread-safe by contract.
@available(macOS 26.0, *)
final class AppleSpeechTranscriber: @unchecked Sendable {
    enum TranscriberError: LocalizedError {
        case localeNotSupported(String)
        case notStarted

        var errorDescription: String? {
            switch self {
            case .localeNotSupported(let identifier):
                return "Apple Speech does not support the \(identifier) locale on this device."
            case .notStarted:
                return "Apple Speech session was not started."
            }
        }
    }

    /// Fires with the full display transcript (settled + current hypothesis).
    var onPartial: (@Sendable (String) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    // Created eagerly so audio chunks arriving while start() is still preparing
    // the model are buffered by the stream instead of dropped (first-word loss).
    private let inputSequence: AsyncStream<AnalyzerInput>
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    init() {
        let (sequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputSequence = sequence
        self.inputContinuation = continuation
    }
    private var converter: AVAudioConverter?
    private var captureFormat: AVAudioFormat?
    private var analyzerFormat: AVAudioFormat?
    private let assemblerLock = NSLock()
    private var assembler = AppleSpeechTranscriptAssembler()

    /// Prepares the OS model for `locale` (downloading through AssetInventory if
    /// needed) and starts a streaming analysis session.
    func start(locale: Locale, captureSampleRate: Double) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        guard await Self.localeIsSupported(locale) else {
            throw TranscriberError.localeNotSupported(locale.identifier)
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.transcriber = transcriber
        self.analyzer = analyzer

        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        self.captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: captureSampleRate,
            channels: 1,
            interleaved: false
        )
        if let captureFormat, let analyzerFormat, captureFormat != analyzerFormat {
            self.converter = AVAudioConverter(from: captureFormat, to: analyzerFormat)
        }

        assemblerLock.withLock { assembler = AppleSpeechTranscriptAssembler() }

        resultsTask = Task { [weak self] in
            guard let self, let transcriber = self.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let display = self.assemblerLock.withLock {
                        self.assembler.receive(text: text, isFinal: result.isFinal)
                        return self.assembler.displayText
                    }
                    self.onPartial?(display)
                }
            } catch {
                // Stream errors surface from finish()/finalize; partials just stop.
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
    }

    /// Feeds a chunk of mono float32 PCM from the capture callback.
    func append(pcm: Data) {
        guard let inputContinuation, let captureFormat else { return }
        guard let buffer = Self.pcmBuffer(from: pcm, format: captureFormat) else { return }

        if let converter, let analyzerFormat {
            let ratio = analyzerFormat.sampleRate / captureFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
            var fed = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, outStatus in
                if fed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard conversionError == nil, converted.frameLength > 0 else { return }
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        } else {
            inputContinuation.yield(AnalyzerInput(buffer: buffer))
        }
    }

    /// Ends the stream, waits for the analyzer to settle, and returns the final
    /// transcript (settled segments plus any never-finalized tail).
    func finish() async throws -> String {
        guard let analyzer else { throw TranscriberError.notStarted }
        inputContinuation?.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        let text = assemblerLock.withLock { assembler.finishedText }
        teardown()
        return text
    }

    /// Abandons the session without waiting for results.
    func cancel() {
        inputContinuation?.finish()
        resultsTask?.cancel()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        teardown()
    }

    private func teardown() {
        analyzer = nil
        transcriber = nil
        inputContinuation = nil
        resultsTask = nil
        converter = nil
        captureFormat = nil
        analyzerFormat = nil
    }

    static func localeIsSupported(_ locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    static func pcmBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Float32>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: Float32.self).baseAddress,
                  let destination = buffer.floatChannelData?[0] else { return }
            destination.update(from: source, count: Int(frameCount))
        }
        return buffer
    }
}
