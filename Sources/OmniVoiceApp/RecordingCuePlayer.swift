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
        guard !respectEnabled || preferences.recordingSoundCuesEnabled else { return 0 }

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

        return (0..<count).map { index in
            let phase = (Double(index) / Double(sampleRate)) * tone.frequency * 2 * Double.pi
            let envelope: Double
            if index < fadeSamples {
                envelope = Double(index) / Double(fadeSamples)
            } else if index > count - fadeSamples {
                envelope = Double(count - index) / Double(fadeSamples)
            } else {
                envelope = 1
            }
            let value = sin(phase) * amplitude * envelope
            return Int16(max(Double(Int16.min), min(Double(Int16.max), value * Double(Int16.max))))
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
