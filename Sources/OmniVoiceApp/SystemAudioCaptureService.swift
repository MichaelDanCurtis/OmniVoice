import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// The audio-source surface `ConversationRecorderService` needs, so a recording
/// lane can be fed by the microphone or by a system-audio tap interchangeably.
protocol ConversationAudioCapturing: AnyObject {
    var onPCMChunk: ((Data) -> Void)? { get set }
    func inputSampleRate(deviceUID: String?) -> Double
    func start(deviceUID: String?) throws -> Double
    func stopWAVData() throws -> Data
}

extension AudioCaptureService: ConversationAudioCapturing {}

/// Captures everything the system plays (the far side of any call app) through
/// a Core Audio process tap — no virtual device, no kernel extension. The tap
/// mixes all processes' output; a private aggregate device delivers buffers via
/// an IO proc, downmixed here to mono float32 chunks like the mic service.
///
/// First use triggers the one-time "System Audio Recording" permission prompt
/// and shows the system recording indicator while active. macOS 14.2+.
@available(macOS 14.2, *)
final class SystemAudioCaptureService: ConversationAudioCapturing, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case tapCreationFailed(OSStatus)
        case tapFormatUnreadable(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let status):
                return "System-audio tap creation failed (\(status)). Allow OmniSpeak under "
                    + "System Settings → Privacy & Security → Screen & System Audio Recording."
            case .tapFormatUnreadable(let status):
                return "System-audio tap format unreadable (\(status))."
            case .aggregateCreationFailed(let status):
                return "System-audio aggregate device failed (\(status))."
            case .ioProcCreationFailed(let status):
                return "System-audio IO proc failed (\(status))."
            case .deviceStartFailed(let status):
                return "System-audio device start failed (\(status))."
            }
        }
    }

    var onPCMChunk: ((Data) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRate: Double = 48_000
    private var running = false

    func inputSampleRate(deviceUID: String?) -> Double {
        sampleRate
    }

    @discardableResult
    func start(deviceUID: String?) throws -> Double {
        guard !running else { return sampleRate }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "OmniSpeak system-audio tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw CaptureError.tapCreationFailed(status) }
        tapID = newTapID

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else {
            teardown()
            throw CaptureError.tapFormatUnreadable(status)
        }
        sampleRate = asbd.mSampleRate

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OmniSpeak system tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr else {
            teardown()
            throw CaptureError.aggregateCreationFailed(status)
        }
        aggregateID = newAggregateID

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { [weak self] _, inputData, _, _, _ in
            self?.emitMonoChunk(from: inputData)
        }
        guard status == noErr, let ioProcID else {
            teardown()
            throw CaptureError.ioProcCreationFailed(status)
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            teardown()
            throw CaptureError.deviceStartFailed(status)
        }

        running = true
        return sampleRate
    }

    /// Stops the tap. The system lane never produces a WAV (nothing downstream
    /// consumes one — recorded audio context is only used for model diarization,
    /// which two-track lanes skip), so this returns empty data.
    func stopWAVData() throws -> Data {
        teardown()
        return Data()
    }

    /// Downmixes an IO-proc buffer list (interleaved or per-channel planar
    /// float32) to mono and forwards it in the same shape the mic service emits.
    private func emitMonoChunk(from list: UnsafePointer<AudioBufferList>) {
        guard running, let onPCMChunk else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard buffers.count > 0 else { return }

        var mono: [Float32] = []
        if buffers.count == 1 {
            let buffer = buffers[0]
            let channels = max(1, Int(buffer.mNumberChannels))
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            guard sampleCount > 0, let base = buffer.mData?.assumingMemoryBound(to: Float32.self) else { return }
            let frames = sampleCount / channels
            mono.reserveCapacity(frames)
            for frame in 0..<frames {
                var sum: Float32 = 0
                for channel in 0..<channels {
                    sum += base[frame * channels + channel]
                }
                mono.append(sum / Float32(channels))
            }
        } else {
            let channelPointers: [(UnsafeMutablePointer<Float32>, Int)] = buffers.compactMap { buffer in
                guard let base = buffer.mData?.assumingMemoryBound(to: Float32.self) else { return nil }
                return (base, Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size)
            }
            guard let frames = channelPointers.map(\.1).min(), frames > 0 else { return }
            mono.reserveCapacity(frames)
            for frame in 0..<frames {
                var sum: Float32 = 0
                for (base, _) in channelPointers {
                    sum += base[frame]
                }
                mono.append(sum / Float32(channelPointers.count))
            }
        }

        guard !mono.isEmpty else { return }
        onPCMChunk(mono.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    private func teardown() {
        running = false
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
