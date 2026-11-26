import AppKit
import Foundation
import OmniVoiceCore

@MainActor
final class RecordingCuePlayer {
    enum CueKind {
        case start
        case stop
        case empty
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
    func playEmptyCue(preferences: OmniVoicePreferences) -> TimeInterval {
        play(.empty, preferences: preferences)
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

        let tones: [RecordingCueTone]
        switch kind {
        case .start:
            tones = preferences.recordingCueSet.startTones
        case .stop:
            tones = preferences.recordingCueSet.stopTones
        case .empty:
            tones = preferences.recordingCueSet.emptyTones
        }
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
        var smoothedNoise = 0.0

        return (0..<count).map { index in
            let progress = count <= 1 ? 1 : Double(index) / Double(count - 1)
            let frequency = tone.frequency + ((endFrequency - tone.frequency) * progress)
            phase += frequency * 2 * Double.pi / Double(sampleRate)

            let envelope = envelopeValue(
                for: tone.waveform,
                index: index,
                count: count,
                fadeSamples: fadeSamples,
                progress: progress
            )
            let value = sampleValue(
                for: tone.waveform,
                phase: phase,
                progress: progress,
                noiseState: &noiseState,
                smoothedNoise: &smoothedNoise
            ) * amplitude * envelope
            return Int16(max(Double(Int16.min), min(Double(Int16.max), value * Double(Int16.max))))
        }
    }

    private func envelopeValue(
        for waveform: RecordingCueWaveform,
        index: Int,
        count: Int,
        fadeSamples: Int,
        progress: Double
    ) -> Double {
        let attackSamples = max(1, min(count / 3, Int(Double(sampleRate) * 0.004)))
        let attack = index < attackSamples ? Double(index) / Double(attackSamples) : 1.0

        switch waveform {
        case .bell:
            return attack * exp(-3.4 * progress) * (1.0 - pow(progress, 6))
        case .marimba:
            return attack * exp(-5.2 * progress) * (1.0 - pow(progress, 6))
        case .pluck:
            return attack * exp(-4.4 * progress) * (1.0 - pow(progress, 6))
        case .drop:
            return attack * sin(Double.pi * pow(progress, 0.72)) * exp(-2.2 * progress)
        case .pad:
            return sin(Double.pi * progress) * (0.85 + 0.15 * sin(Double.pi * progress))
        case .sine, .triangle, .square, .sawtooth, .noise:
            if index < fadeSamples {
                return Double(index) / Double(fadeSamples)
            } else if index > count - fadeSamples {
                return Double(count - index) / Double(fadeSamples)
            }
            return 1.0
        }
    }

    private func sampleValue(
        for waveform: RecordingCueWaveform,
        phase: Double,
        progress: Double,
        noiseState: inout UInt32,
        smoothedNoise: inout Double
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
            let raw = (Double(noiseState & 0xFFFF) / 32_767.5) - 1
            smoothedNoise = smoothedNoise * 0.65 + raw * 0.35
            return smoothedNoise
        case .bell:
            // Pure fundamental + gentle 2nd & crystalline 2.756 overtone that shimmers out
            let overtoneDecay = exp(-4.5 * progress)
            return 0.72 * sin(phase)
                + 0.20 * sin(phase * 2.0) * overtoneDecay
                + 0.08 * sin(phase * 2.756) * overtoneDecay * overtoneDecay
        case .marimba:
            // Woody marimba fundamental + quick-decaying 4th harmonic mallet strike
            let strike = exp(-12.0 * progress)
            return 0.80 * sin(phase)
                + 0.16 * sin(phase * 4.0) * strike
                + 0.04 * sin(phase * 2.0) * exp(-6.0 * progress)
        case .pluck:
            // Warm plucked string / kalimba with natural harmonic damping
            let h2 = exp(-3.5 * progress)
            let h3 = exp(-7.0 * progress)
            return 0.68 * sin(phase)
                + 0.22 * sin(phase * 2.0) * h2
                + 0.10 * sin(phase * 3.0) * h3
        case .pad:
            // Silky warm chord shimmer (fundamental + octave + soft fifth)
            return 0.62 * sin(phase)
                + 0.24 * sin(phase * 1.5)
                + 0.14 * sin(phase * 2.0)
        case .drop:
            // Clean resonant droplet sine with subtle 2nd harmonic warmth
            return 0.88 * sin(phase) + 0.12 * sin(phase * 2.0) * exp(-5.0 * progress)
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
        case .empty:
            return .empty
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
