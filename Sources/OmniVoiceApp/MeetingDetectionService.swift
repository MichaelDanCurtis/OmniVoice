import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import OmniVoiceCore

/// Lightweight background monitor that detects when the user starts a Teams,
/// FaceTime, Phone, Zoom, Google Meet, Slack Huddle, Webex, or Discord call
/// using native CoreAudio mic-activity status and on-screen window metadata.
@MainActor
final class MeetingDetectionService {
    var onMeetingDetected: ((DetectedMeetingEvent) -> Void)?
    var onMeetingEnded: ((DetectedMeetingEvent) -> Void)?
    var isEnabled: () -> Bool = { true }
    var isRecordingConversation: () -> Bool = { false }

    private var timer: Timer?
    private var activeCall: DetectedMeetingEvent?
    private var dismissedCallKey: String?
    private var consecutiveIdleChecks = 0

    func start() {
        guard timer == nil else { return }
        let poll = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollOnce()
            }
        }
        poll.tolerance = 1.0
        timer = poll
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activeCall = nil
        dismissedCallKey = nil
        consecutiveIdleChecks = 0
    }

    func dismissCurrentPrompt() {
        if let activeCall {
            dismissedCallKey = callKey(for: activeCall)
        }
    }

    private func pollOnce() {
        guard isEnabled() else { return }

        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIDs = Set(runningApps.compactMap(\.bundleIdentifier))
        let pidToApp: [pid_t: NSRunningApplication] = Dictionary(
            runningApps.compactMap { app in
                let pid = app.processIdentifier
                return pid > 0 ? (pid, app) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        let windows = Self.captureOnScreenWindows(pidToApp: pidToApp)
        // If OmniSpeak itself is recording, the mic is obviously active; still inspect
        // meeting windows so we can detect when the call ends.
        let micActive = Self.isDefaultInputDeviceRunning()
        let effectiveMicActive = isRecordingConversation() ? false : micActive

        if let detected = MeetingAppMatcher.detect(
            runningBundleIDs: runningBundleIDs,
            windows: windows,
            microphoneActive: effectiveMicActive
        ) {
            consecutiveIdleChecks = 0
            let key = callKey(for: detected)
            if activeCall == nil {
                activeCall = detected
                if !isRecordingConversation(), dismissedCallKey != key {
                    onMeetingDetected?(detected)
                }
            }
        } else if let previous = activeCall {
            consecutiveIdleChecks += 1
            if consecutiveIdleChecks >= 3 {
                activeCall = nil
                dismissedCallKey = nil
                consecutiveIdleChecks = 0
                onMeetingEnded?(previous)
            }
        }
    }

    private func callKey(for event: DetectedMeetingEvent) -> String {
        "\(event.app.rawValue)|\(event.bundleIdentifier.lowercased())"
    }

    private static func captureOnScreenWindows(pidToApp: [pid_t: NSRunningApplication]) -> [RunningWindowSnapshot] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var snapshots: [RunningWindowSnapshot] = []
        snapshots.reserveCapacity(infoList.count)
        for info in infoList {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(pidNumber.int32Value)
            guard let app = pidToApp[pid], let bundleID = app.bundleIdentifier else { continue }
            let title = (info[kCGWindowName as String] as? String) ?? ""
            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? app.localizedName ?? ""
            snapshots.append(
                RunningWindowSnapshot(
                    bundleIdentifier: bundleID,
                    localizedName: ownerName,
                    windowTitle: title
                )
            )
        }
        return snapshots
    }

    private static func isDefaultInputDeviceRunning() -> Bool {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return false
        }

        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let runningStatus = AudioObjectGetPropertyData(
            deviceID,
            &runningAddress,
            0,
            nil,
            &runningSize,
            &isRunning
        )
        return runningStatus == noErr && isRunning != 0
    }
}
