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
    private let queue = DispatchQueue(label: "omnivoice.audio.capture")
    private var buffers: [AVAudioPCMBuffer] = []

    var onLevel: ((Float) -> Void)?
    var onPCMChunk: ((Data) -> Void)?

    func inputSampleRate() -> Double {
        engine.inputNode.outputFormat(forBus: 0).sampleRate
    }

    func inputSampleRate(deviceUID: String?) -> Double {
        MicrophoneDeviceService.nominalSampleRate(for: deviceUID) ?? inputSampleRate()
    }

    @discardableResult
    func start(deviceUID: String?) throws -> Double {
        queue.sync {
            buffers.removeAll()
        }

        try configureInputDevice(uid: deviceUID)

        let input = engine.inputNode
        let format = try tapFormat(for: input, deviceUID: deviceUID)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let copied = Self.copy(buffer: buffer)
            let level = Self.level(buffer: buffer)
            let chunk = Self.float32MonoData(buffer: buffer)

            queue.async {
                if let copied {
                    self.buffers.append(copied)
                }
                self.onLevel?(level)
                if let chunk {
                    self.onPCMChunk?(chunk)
                }
            }
        }

        engine.prepare()
        try engine.start()
        return format.sampleRate
    }

    func stopWAVData() throws -> Data {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let captured = queue.sync { buffers }
        guard let first = captured.first else {
            return PCM16WAVEncoder.encode(samples: [], sampleRate: 16_000)
        }

        var samples: [Int16] = []
        for buffer in captured {
            Self.appendMonoPCM16Samples(from: buffer, to: &samples)
        }
        return PCM16WAVEncoder.encode(samples: samples, sampleRate: Int(first.format.sampleRate.rounded()))
    }

    private static func copy(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copied.frameLength = buffer.frameLength

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if let source = buffer.floatChannelData, let destination = copied.floatChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
        } else if let source = buffer.int16ChannelData, let destination = copied.int16ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
        } else if let source = buffer.int32ChannelData, let destination = copied.int32ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
        }

        return copied
    }

    private static func float32MonoData(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        return Data(bytes: channel, count: frameCount * MemoryLayout<Float>.size)
    }

    private static func level(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameCount {
            sum += abs(channel[index])
        }
        return sum / Float(frameCount)
    }

    private static func appendMonoPCM16Samples(from buffer: AVAudioPCMBuffer, to samples: inout [Int16]) {
        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        guard frameCount > 0 else { return }

        samples.reserveCapacity(samples.count + frameCount)

        if let channels = buffer.floatChannelData {
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
