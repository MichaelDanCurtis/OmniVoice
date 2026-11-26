import AudioToolbox
import CoreAudio
import Foundation

/// Strategy-agnostic control surface for muting/restoring the default macOS system output device.
public protocol SystemAudioOutputControl: AnyObject {
    /// Attempts to mute the current default output device and returns a token
    /// describing how to restore it, or `.alreadyMuted` if the device was already silent.
    func captureAndMuteDefaultOutput() -> BackgroundAudioMuteSnapshot?

    /// Restores the default output device to the exact state captured in `snapshot`.
    func restore(_ snapshot: BackgroundAudioMuteSnapshot)
}

/// Captured pre-dictation state of the default system output device.
public enum BackgroundAudioMuteSnapshot: Equatable, Sendable {
    /// Output was already muted (or volume == 0) before dictation started; do not unmute on release.
    case alreadyMuted
    /// Muted via `kAudioDevicePropertyMute` on the listed output element(s) (e.g. `[0]` or `[1, 2]`).
    case hardwareMute(deviceID: UInt32, elements: [UInt32])
    /// Muted via virtual main volume (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`) fallback.
    case virtualMainVolume(deviceID: UInt32, previousVolume: Float)
    /// Muted via per-element `kAudioDevicePropertyVolumeScalar` fallback.
    case scalarVolumes(deviceID: UInt32, previousVolumes: [UInt32: Float])
}

/// Manages temporary muting of system media playback while push-to-talk / dictation is active,
/// guaranteeing the user's original mute/volume state is faithfully restored on release, error,
/// cancellation, or app termination.
@MainActor
public final class BackgroundAudioMuteController {
    private let outputControl: SystemAudioOutputControl
    private var activeSnapshot: BackgroundAudioMuteSnapshot?

    public init(outputControl: SystemAudioOutputControl = CoreAudioSystemOutputControl()) {
        self.outputControl = outputControl
    }

    public var isHoldingMute: Bool {
        activeSnapshot != nil
    }

    /// Mutes the default output device if not already holding an active mute snapshot.
    /// Re-entrant calls preserve the original pre-dictation snapshot.
    public func beginDictationMute() {
        guard activeSnapshot == nil else { return }
        activeSnapshot = outputControl.captureAndMuteDefaultOutput()
    }

    /// Restores the default output device to its pre-dictation state (no-op if not active
    /// or if the device was already muted before dictation started).
    public func endDictationMute() {
        guard let snapshot = activeSnapshot else { return }
        activeSnapshot = nil
        guard snapshot != .alreadyMuted else { return }
        outputControl.restore(snapshot)
    }
}

/// Concrete CoreAudio / AudioToolbox implementation that works across built-in speakers,
/// AirPods/Bluetooth headsets, USB DACs, DisplayPort/HDMI monitors, and aggregate devices.
public final class CoreAudioSystemOutputControl: SystemAudioOutputControl {
    public init() {}

    public func captureAndMuteDefaultOutput() -> BackgroundAudioMuteSnapshot? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }

        // 1. Prefer hardware mute on Main element (0), then stereo channels [1, 2].
        if let snapshot = captureAndMuteHardware(deviceID: deviceID, candidateElements: [kAudioObjectPropertyElementMain]) {
            return snapshot
        }
        if let snapshot = captureAndMuteHardware(deviceID: deviceID, candidateElements: [1, 2]) {
            return snapshot
        }

        // 2. Fallback: AudioToolbox virtual main volume (handles USB DACs / Bluetooth / monitors).
        if let snapshot = captureAndMuteVirtualMainVolume(deviceID: deviceID) {
            return snapshot
        }

        // 3. Fallback: per-channel scalar volume on Main element (0) or stereo channels [1, 2].
        if let snapshot = captureAndMuteScalarVolume(deviceID: deviceID, candidateElements: [kAudioObjectPropertyElementMain]) {
            return snapshot
        }
        if let snapshot = captureAndMuteScalarVolume(deviceID: deviceID, candidateElements: [1, 2]) {
            return snapshot
        }

        return nil
    }

    public func restore(_ snapshot: BackgroundAudioMuteSnapshot) {
        switch snapshot {
        case .alreadyMuted:
            return
        case .hardwareMute(let deviceID, let elements):
            for element in elements {
                setMute(deviceID: AudioDeviceID(deviceID), element: element, muted: false)
            }
        case .virtualMainVolume(let deviceID, let previousVolume):
            setVirtualMainVolume(deviceID: AudioDeviceID(deviceID), volume: previousVolume)
        case .scalarVolumes(let deviceID, let previousVolumes):
            for (element, volume) in previousVolumes {
                setScalarVolume(deviceID: AudioDeviceID(deviceID), element: element, volume: volume)
            }
        }
    }

    // MARK: - CoreAudio Helpers

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func captureAndMuteHardware(
        deviceID: AudioDeviceID,
        candidateElements: [AudioObjectPropertyElement]
    ) -> BackgroundAudioMuteSnapshot? {
        var settableElements: [AudioObjectPropertyElement] = []
        var unmutedElements: [AudioObjectPropertyElement] = []

        for element in candidateElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
                  settable.boolValue else { continue }

            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr else { continue }

            settableElements.append(element)
            if muted == 0 {
                unmutedElements.append(element)
            }
        }

        guard !settableElements.isEmpty else { return nil }
        if unmutedElements.isEmpty {
            return .alreadyMuted
        }

        var actuallyMuted: [UInt32] = []
        for element in unmutedElements {
            if setMute(deviceID: deviceID, element: element, muted: true) {
                actuallyMuted.append(element)
            }
        }
        guard !actuallyMuted.isEmpty else { return nil }
        return .hardwareMute(deviceID: deviceID, elements: actuallyMuted)
    }

    @discardableResult
    private func setMute(deviceID: AudioDeviceID, element: AudioObjectPropertyElement, muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    private func captureAndMuteVirtualMainVolume(deviceID: AudioDeviceID) -> BackgroundAudioMuteSnapshot? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else { return nil }

        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else { return nil }
        if volume <= 0.0001 {
            return .alreadyMuted
        }
        guard setVirtualMainVolume(deviceID: deviceID, volume: 0) else { return nil }
        return .virtualMainVolume(deviceID: deviceID, previousVolume: volume)
    }

    @discardableResult
    private func setVirtualMainVolume(deviceID: AudioDeviceID, volume: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var clamped = min(max(volume, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped) == noErr
    }

    private func captureAndMuteScalarVolume(
        deviceID: AudioDeviceID,
        candidateElements: [AudioObjectPropertyElement]
    ) -> BackgroundAudioMuteSnapshot? {
        var settableElements: [AudioObjectPropertyElement] = []
        var nonZeroVolumes: [UInt32: Float] = [:]

        for element in candidateElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
                  settable.boolValue else { continue }

            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else { continue }

            settableElements.append(element)
            if volume > 0.0001 {
                nonZeroVolumes[element] = volume
            }
        }

        guard !settableElements.isEmpty else { return nil }
        if nonZeroVolumes.isEmpty {
            return .alreadyMuted
        }

        var mutedVolumes: [UInt32: Float] = [:]
        for (element, previousVolume) in nonZeroVolumes {
            if setScalarVolume(deviceID: deviceID, element: element, volume: 0) {
                mutedVolumes[element] = previousVolume
            }
        }
        guard !mutedVolumes.isEmpty else { return nil }
        return .scalarVolumes(deviceID: deviceID, previousVolumes: mutedVolumes)
    }

    @discardableResult
    private func setScalarVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement, volume: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        var clamped = min(max(volume, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped) == noErr
    }
}
