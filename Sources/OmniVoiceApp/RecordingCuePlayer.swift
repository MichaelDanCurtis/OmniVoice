import AppKit
import Foundation
import OmniVoiceCore

@MainActor
final class RecordingCuePlayer {
    enum CueKind {
        case start
        case stop
    }

    static let shared = RecordingCuePlayer()

    private let sampleRate = 44_100
    private var currentSound: NSSound?

    @discardableResult
    func playStartCue(preferences: OmniVoicePreferences) -> TimeInterval {
        play(.start, preferences: preferences)
    }

    @discardableResult
    func playStopCue(preferences: OmniVoicePreferences) -> TimeInterval {
        play(.stop, preferences: preferences)
    }

    @discardableResult
    func preview(_ kind: CueKind, preferences: OmniVoicePreferences) -> TimeInterval {
        play(kind, preferences: preferences, respectEnabled: false)
    }

    @discardableResult
    private func play(
        _ kind: CueKind,
        preferences: OmniVoicePreferences,
        respectEnabled: Bool = true
    ) -> TimeInterval {
        guard !respectEnabled || preferences.isRecordingCueEnabled(for: kind.recordingCueEvent) else { return 0 }

        let tones = kind == .start
            ? preferences.recordingCueSet.startTones
            : preferences.recordingCueSet.stopTones
        let duration = tones.reduce(0) { $0 + $1.duration }
        guard !tones.isEmpty, duration > 0 else { return 0 }

        currentSound?.stop()
        guard let sound = NSSound(data: waveData(for: tones)) else { return 0 }
        sound.volume = Float(OmniVoicePreferences.clampedRecordingCueVolume(preferences.recordingCueVolume))
        currentSound = sound
        sound.play()
        return duration
    }

    private func waveData(for tones: [RecordingCueTone]) -> Data {
        var pcm = [Int16]()
        let gapSamples = Int(Double(sampleRate) * 0.012)

        for (index, tone) in tones.enumerated() {
            pcm.append(contentsOf: samples(for: tone))
            if index < tones.count - 1 {
                pcm.append(contentsOf: Array(repeating: 0, count: gapSamples))
            }
        }

        return wavData(pcmSamples: pcm)
    }

    private func samples(for tone: RecordingCueTone) -> [Int16] {
        let count = max(1, Int(Double(sampleRate) * tone.duration))
        let fadeSamples = max(1, min(count / 2, Int(Double(sampleRate) * 0.008)))
        let amplitude = min(max(tone.amplitude, 0), 1) * 0.55
        let endFrequency = tone.endFrequency ?? tone.frequency
        var phase = 0.0
        var noiseState = UInt32(max(1, Int(tone.frequency.rounded()) + Int(tone.duration * 100_000)))

        return (0..<count).map { index in
            let progress = count <= 1 ? 1 : Double(index) / Double(count - 1)
            let frequency = tone.frequency + ((endFrequency - tone.frequency) * progress)
            phase += frequency * 2 * Double.pi / Double(sampleRate)
            let envelope: Double
            if index < fadeSamples {
                envelope = Double(index) / Double(fadeSamples)
            } else if index > count - fadeSamples {
                envelope = Double(count - index) / Double(fadeSamples)
            } else {
                envelope = 1
            }
            let value = sampleValue(for: tone.waveform, phase: phase, noiseState: &noiseState) * amplitude * envelope
            return Int16(max(Double(Int16.min), min(Double(Int16.max), value * Double(Int16.max))))
        }
    }

    private func sampleValue(
        for waveform: RecordingCueWaveform,
        phase: Double,
        noiseState: inout UInt32
    ) -> Double {
        switch waveform {
        case .sine:
            return sin(phase)
        case .triangle:
            return (2 / Double.pi) * asin(sin(phase))
        case .square:
            return sin(phase) >= 0 ? 1 : -1
        case .sawtooth:
            let cycle = phase / (2 * Double.pi)
            return 2 * (cycle - floor(cycle + 0.5))
        case .noise:
            noiseState = 1_664_525 &* noiseState &+ 1_013_904_223
            return (Double(noiseState & 0xFFFF) / 32_767.5) - 1
        }
    }

    private func wavData(pcmSamples: [Int16]) -> Data {
        let byteRate = sampleRate * 2
        let dataByteCount = pcmSamples.count * 2
        let chunkSize = 36 + dataByteCount

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndianUInt32(UInt32(chunkSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndianUInt32(16)
        data.appendLittleEndianUInt16(1)
        data.appendLittleEndianUInt16(1)
        data.appendLittleEndianUInt32(UInt32(sampleRate))
        data.appendLittleEndianUInt32(UInt32(byteRate))
        data.appendLittleEndianUInt16(2)
        data.appendLittleEndianUInt16(16)
        data.appendASCII("data")
        data.appendLittleEndianUInt32(UInt32(dataByteCount))
        for sample in pcmSamples {
            data.appendLittleEndianInt16(sample)
        }
        return data
    }
}

private extension RecordingCuePlayer.CueKind {
    var recordingCueEvent: RecordingCueEvent {
        switch self {
        case .start:
            return .start
        case .stop:
            return .stop
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndianInt16(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
