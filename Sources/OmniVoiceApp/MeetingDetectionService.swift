import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import OmniVoiceCore

/// Lightweight background monitor that detects active and about-to-join Teams,
/// FaceTime, Phone, Zoom, Google Meet, Slack Huddle, Webex, Discord, WhatsApp,
/// Signal, Telegram, RingCentral, Dialpad, Chime, upcoming Calendar meetings, and
/// any generic two-way audio conversation using CoreAudio input+output activity and
/// on-screen window metadata.
@MainActor
final class MeetingDetectionService {
    var onMeetingDetected: ((DetectedMeetingEvent) -> Void)?
    var onMeetingEnded: ((DetectedMeetingEvent) -> Void)?
    var isEnabled: () -> Bool = { true }
    var isRecordingConversation: () -> Bool = { false }
    var isDictating: () -> Bool = { false }
    var upcomingMeetingSoon: () -> MeetingCalendarContext? = { nil }

    private var timer: Timer?
    private var activeCall: DetectedMeetingEvent?
    private var dismissedCallKey: String?
    private var consecutiveIdleChecks = 0
    private var consecutiveGenericTwoWayChecks = 0
    private var promptedCalendarKeys: Set<String> = []

    func start() {
        guard timer == nil else { return }
        let poll = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollOnce()
            }
        }
        poll.tolerance = 0.5
        timer = poll
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activeCall = nil
        dismissedCallKey = nil
        consecutiveIdleChecks = 0
        consecutiveGenericTwoWayChecks = 0
    }

    func dismissCurrentPrompt() {
        if let activeCall {
            dismissedCallKey = callKey(for: activeCall)
        }
    }

    private static let passiveWindowCallBundleIDs: Set<String> = [
        "com.apple.facetime",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "us.zoom.xos",
        "cisco-systems.spark",
        "com.webex.meetingmanager",
        "com.tinyspeck.slackmacgap",
        "net.whatsapp.whatsapp",
        "desktop.whatsapp",
        "org.whispersystems.signal-desktop",
        "com.ringcentral.glip",
        "com.ringcentral.ringcentral",
        "com.dialpad.dialpad",
        "com.amazon.amazonchime",
    ]

    private static let browserBundleIDs: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "company.thebrowser.browser",
        "org.mozilla.firefox",
        "com.vivaldi.vivaldi",
        "com.operasoftware.opera",
    ]

    private func pollOnce() {
        guard isEnabled() else { return }

        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIDs = Set(runningApps.compactMap(\.bundleIdentifier))
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let frontLower = frontmostBundleID?.lowercased() ?? ""

        // Ignore OmniSpeak's own push-to-talk dictation mic usage so dictating never
        // falsely triggers the two-way call popup.
        let micActive = Self.isDefaultAudioDeviceRunning(selector: kAudioHardwarePropertyDefaultInputDevice)
        let effectiveMicActive = (isRecordingConversation() || isDictating()) ? false : micActive
        let systemAudioActive = Self.isDefaultAudioDeviceRunning(selector: kAudioHardwarePropertyDefaultOutputDevice)

        // Check if an upcoming Calendar meeting starts within the next 2 minutes
        // (catches "about to join a Teams/Zoom meeting" before the user even clicks Join!).
        if activeCall == nil, !isRecordingConversation(), let upcoming = upcomingMeetingSoon() {
            let stamp = Int((upcoming.startDate ?? Date()).timeIntervalSince1970 / 60)
            let calKey = "cal|\(upcoming.title.lowercased())|\(stamp)"
            if promptedCalendarKeys.insert(calKey).inserted {
                let isTeams = upcoming.title.lowercased().contains("teams")
                    || (upcoming.notes?.lowercased().contains("teams.microsoft.com") ?? false)
                    || (upcoming.notes?.lowercased().contains("teams.live.com") ?? false)
                let event = DetectedMeetingEvent(
                    app: isTeams ? .teams : .upcomingMeeting,
                    bundleIdentifier: isTeams ? "com.microsoft.teams2" : "com.apple.iCal",
                    windowTitle: upcoming.title,
                    isPreJoin: true
                )
                activeCall = event
                if dismissedCallKey != callKey(for: event) {
                    onMeetingDetected?(event)
                }
                return
            }
        }

        // Inspect windows when in a call, mic is active, a comms app is running, or a browser/PWA is frontmost
        // (so we catch Teams Web / Meet / Zoom pre-join lobbies immediately while staying idle otherwise).
        let hasPassiveCallApp = runningBundleIDs.contains { Self.passiveWindowCallBundleIDs.contains($0.lowercased()) }
        let frontIsBrowserOrPWA = Self.browserBundleIDs.contains(frontLower)
            || frontLower.hasPrefix("com.google.chrome.app.")
            || frontLower.hasPrefix("com.microsoft.edgemac.app.")
            || frontLower.hasPrefix("com.brave.browser.app.")

        guard activeCall != nil || effectiveMicActive || hasPassiveCallApp || frontIsBrowserOrPWA else {
            consecutiveGenericTwoWayChecks = 0
            return
        }

        let pidToApp: [pid_t: NSRunningApplication] = Dictionary(
            runningApps.compactMap { app in
                let pid = app.processIdentifier
                return pid > 0 ? (pid, app) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        let windows = Self.captureOnScreenWindows(pidToApp: pidToApp)

        if let detected = MeetingAppMatcher.detect(
            runningBundleIDs: runningBundleIDs,
            windows: windows,
            microphoneActive: effectiveMicActive,
            systemAudioActive: systemAudioActive,
            frontmostBundleID: frontmostBundleID
        ) {
            // Require 2 consecutive polls (~6s) for generic unknown two-way calls so brief
            // mic taps never spam; known calling apps and pre-join lobbies prompt immediately.
            if detected.app == .twoWayCall && activeCall == nil {
                consecutiveGenericTwoWayChecks += 1
                guard consecutiveGenericTwoWayChecks >= 2 else { return }
            } else {
                consecutiveGenericTwoWayChecks = 0
            }

            consecutiveIdleChecks = 0
            let key = callKey(for: detected)
            if activeCall == nil {
                activeCall = detected
                if !isRecordingConversation(), dismissedCallKey != key {
                    onMeetingDetected?(detected)
                }
            }
        } else if let previous = activeCall {
            consecutiveGenericTwoWayChecks = 0
            // Don't prematurely end an upcoming calendar pre-join prompt before 15 polls (~45s)
            let idleThreshold = previous.app == .upcomingMeeting ? 15 : 3
            consecutiveIdleChecks += 1
            if consecutiveIdleChecks >= idleThreshold {
                activeCall = nil
                dismissedCallKey = nil
                consecutiveIdleChecks = 0
                if previous.app != .upcomingMeeting {
                    onMeetingEnded?(previous)
                }
            }
        } else {
            consecutiveGenericTwoWayChecks = 0
        }
    }

    private func callKey(for event: DetectedMeetingEvent) -> String {
        "\(event.app.rawValue)|\(event.bundleIdentifier.lowercased())|\(event.windowTitle?.lowercased() ?? "")"
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

    private static func isDefaultAudioDeviceRunning(selector: AudioObjectPropertySelector) -> Bool {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
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
