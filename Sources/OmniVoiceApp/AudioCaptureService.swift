import Accelerate
@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OmniVoiceCore

final class AudioCaptureService: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case microphoneNotFound(String)
        case inputNodeUnavailable
        case invalidInputFormat
        case setInputDeviceFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .microphoneNotFound(let id):
                "Microphone not found: \(id)"
            case .inputNodeUnavailable:
                "Audio input node is unavailable"
            case .invalidInputFormat:
                "Could not create a compatible microphone format"
            case .setInputDeviceFailed(let status):
                "Could not select microphone (\(status))"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "omnispeak.audio.capture")
    private var samples: [Int16] = []
    private var captureSampleRate: Double = 16_000

    var onLevel: ((Float) -> Void)?
    var onPCMChunk: ((Data) -> Void)?
    var onPCM16Chunk: ((Data) -> Void)?

    func inputSampleRate() -> Double {
        engine.inputNode.outputFormat(forBus: 0).sampleRate
    }

    func inputSampleRate(deviceUID: String?) -> Double {
        MicrophoneDeviceService.nominalSampleRate(for: deviceUID) ?? inputSampleRate()
    }

    @discardableResult
    func start(deviceUID: String?) throws -> Double {
        queue.sync {
            samples.removeAll()
        }

        try configureInputDevice(uid: deviceUID)

        let input = engine.inputNode
        let format = try tapFormat(for: input, deviceUID: deviceUID)
        let captureRate = format.sampleRate
        queue.sync { self.captureSampleRate = captureRate }

        input.removeTap(onBus: 0)
        // Convert each tap buffer to mono PCM16 immediately and accumulate the small Int16
        // samples, rather than retaining a full-rate float copy of every buffer for the whole
        // recording (previously unbounded memory growth + a re-walk of all buffers at stop).
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.level(buffer: buffer)
            let needsChunk = self.onPCMChunk != nil
            let needsPCM16Chunk = self.onPCM16Chunk != nil
            let chunk = needsChunk ? Self.float32MonoData(buffer: buffer) : nil
            var pcm16: [Int16] = []
            Self.appendMonoPCM16Samples(from: buffer, to: &pcm16)
            let capturedPCM16 = pcm16
            let pcm16Chunk: Data? = needsPCM16Chunk
                ? capturedPCM16.withUnsafeBufferPointer { Data(buffer: $0) }
                : nil

            queue.async {
                self.samples.append(contentsOf: capturedPCM16)
                self.onLevel?(level)
                if let chunk {
                    self.onPCMChunk?(chunk)
                }
                if let pcm16Chunk {
                    self.onPCM16Chunk?(pcm16Chunk)
                }
            }
        }

        engine.prepare()
        try engine.start()
        return format.sampleRate
    }

    func snapshotWAVData() -> (wavData: Data, sampleCount: Int) {
        let (captured, rate) = queue.sync { (samples, captureSampleRate) }
        guard !captured.isEmpty else {
            return (Data(), 0)
        }
        return (PCM16WAVEncoder.encode(samples: captured, sampleRate: Int(rate.rounded())), captured.count)
    }

    /// Zero-disk in-memory 16 kHz mono Float32 snapshot for fast CoreML ANE live partials.
    func snapshotFloat16kHz() -> (samples: [Float], rawSampleCount: Int) {
        let (captured, rate) = queue.sync { (samples, captureSampleRate) }
        guard !captured.isEmpty else {
            return ([], 0)
        }
        return (Self.resamplePCM16To16kHzFloat(captured, sourceSampleRate: rate), captured.count)
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        queue.sync {
            samples.removeAll(keepingCapacity: false)
        }
    }

    /// Keeps only the most recent `seconds` of buffered PCM16 audio so hands-free
    /// open-mic VAD maintains a crisp pre-roll without accumulating minutes of silence.
    func trimToTrailingSeconds(_ seconds: Double) {
        queue.async {
            let maxSamples = max(1, Int((self.captureSampleRate * max(0.1, seconds)).rounded()))
            if self.samples.count > maxSamples {
                self.samples.removeFirst(self.samples.count - maxSamples)
            }
        }
    }

    func stopWAVData() throws -> Data {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let (captured, rate) = queue.sync { () -> ([Int16], Double) in
            let copy = samples
            let currentRate = captureSampleRate
            samples.removeAll(keepingCapacity: false)
            return (copy, currentRate)
        }
        return PCM16WAVEncoder.encode(samples: captured, sampleRate: Int(rate.rounded()))
    }

    static func resamplePCM16To16kHzFloat(_ pcm16: [Int16], sourceSampleRate: Double) -> [Float] {
        guard !pcm16.isEmpty else { return [] }
        var scale: Float = 1.0 / 32768.0
        let rate = sourceSampleRate > 0 ? sourceSampleRate : 16_000.0
        if abs(rate - 16_000.0) < 1.0 {
            var out = [Float](repeating: 0, count: pcm16.count)
            pcm16.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    guard let s = src.baseAddress, let d = dst.baseAddress else { return }
                    vDSP_vflt16(s, 1, d, 1, vDSP_Length(pcm16.count))
                    vDSP_vsmul(d, 1, &scale, d, 1, vDSP_Length(pcm16.count))
                }
            }
            return out
        }

        let ratio = rate / 16_000.0
        let outputCount = max(1, Int((Double(pcm16.count) / ratio).rounded(.down)))
        var out = [Float](repeating: 0, count: outputCount)
        let lastIndex = pcm16.count - 1
        for i in 0..<outputCount {
            let srcPos = Double(i) * ratio
            let idx0 = min(Int(srcPos), lastIndex)
            let idx1 = min(idx0 + 1, lastIndex)
            let frac = Float(srcPos - Double(idx0))
            let s0 = Float(pcm16[idx0]) * scale
            let s1 = Float(pcm16[idx1]) * scale
            out[i] = s0 + (s1 - s0) * frac
        }
        return out
    }

    private static func float32MonoData(buffer: AVAudioPCMBuffer) -> Data? {
        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        guard frameCount > 0, let channels = buffer.floatChannelData else { return nil }

        var samples = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var mixed: Float = 0
            for channel in 0..<channelCount {
                mixed += channels[channel][frame]
            }
            samples[frame] = mixed / Float(channelCount)
        }
        return samples.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }
    }

    private static func level(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var meanMagnitude: Float = 0
        vDSP_meamgv(channel, 1, &meanMagnitude, vDSP_Length(frameCount))
        return meanMagnitude
    }

    private static func appendMonoPCM16Samples(from buffer: AVAudioPCMBuffer, to samples: inout [Int16]) {
        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        guard frameCount > 0 else { return }

        samples.reserveCapacity(samples.count + frameCount)

        if let channels = buffer.floatChannelData {
            if channelCount == 1 {
                var clipped = [Float](repeating: 0, count: frameCount)
                var lo: Float = -1.0
                var hi: Float = 1.0
                var scale: Float = Float(Int16.max)
                let startCount = samples.count
                samples.append(contentsOf: repeatElement(0, count: frameCount))
                clipped.withUnsafeMutableBufferPointer { tmp in
                    samples.withUnsafeMutableBufferPointer { dst in
                        guard let t = tmp.baseAddress, let d = dst.baseAddress else { return }
                        vDSP_vclip(channels[0], 1, &lo, &hi, t, 1, vDSP_Length(frameCount))
                        vDSP_vsmul(t, 1, &scale, t, 1, vDSP_Length(frameCount))
                        vDSP_vfix16(t, 1, d.advanced(by: startCount), 1, vDSP_Length(frameCount))
                    }
                }
                return
            }
            for frame in 0..<frameCount {
                var mixed: Float = 0
                for channel in 0..<channelCount {
                    mixed += channels[channel][frame]
                }
                samples.append(Self.floatToInt16(mixed / Float(channelCount)))
            }
            return
        }

        if let channels = buffer.int16ChannelData {
            for frame in 0..<frameCount {
                var mixed = 0
                for channel in 0..<channelCount {
                    mixed += Int(channels[channel][frame])
                }
                samples.append(Int16(clamping: mixed / channelCount))
            }
            return
        }

        if let channels = buffer.int32ChannelData {
            for frame in 0..<frameCount {
                var mixed: Int64 = 0
                for channel in 0..<channelCount {
                    mixed += Int64(channels[channel][frame] >> 16)
                }
                samples.append(Int16(clamping: mixed / Int64(channelCount)))
            }
        }
    }

    private static func floatToInt16(_ value: Float) -> Int16 {
        let clipped = min(max(value, -1), 1)
        if clipped == -1 {
            return Int16.min
        }
        return Int16(clipped * Float(Int16.max))
    }

    private func tapFormat(for input: AVAudioInputNode, deviceUID: String?) throws -> AVAudioFormat {
        let nodeFormat = input.outputFormat(forBus: 0)
        let sampleRate = AudioCaptureFormatResolver.sampleRate(
            selectedDeviceSampleRate: MicrophoneDeviceService.nominalSampleRate(for: deviceUID),
            nodeSampleRate: nodeFormat.sampleRate
        )
        let channelCount = max(AVAudioChannelCount(1), nodeFormat.channelCount)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw CaptureError.invalidInputFormat
        }

        return format
    }

    private func configureInputDevice(uid: String?) throws {
        guard let deviceID = MicrophoneDeviceService.deviceID(for: uid) else {
            throw CaptureError.microphoneNotFound(uid ?? "system default")
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw CaptureError.inputNodeUnavailable
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw CaptureError.setInputDeviceFailed(status)
        }
    }
}
