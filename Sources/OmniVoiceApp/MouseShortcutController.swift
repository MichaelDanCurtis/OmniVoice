import AppKit
import OmniVoiceCore

@MainActor
final class MouseShortcutController {
    var onPushToTalkPressed: (() -> Void)?
    var onPushToTalkReleased: (() -> Void)?
    var onTranscriptCachePressed: (() -> Void)?

    private var preferences = OmniVoicePreferences.defaults
    private var localMonitor: Any?
    private var globalDownMonitor: Any?
    private var globalUpMonitor: Any?
    private var pushedButtons = Set<Int>()

    func apply(preferences: OmniVoicePreferences) {
        self.preferences = preferences
        stop()

        guard preferences.mousePushToTalkEnabled || preferences.transcriptCacheMouseEnabled else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
            return event
        }
        globalDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalDownMonitor {
            NSEvent.removeMonitor(globalDownMonitor)
        }
        if let globalUpMonitor {
            NSEvent.removeMonitor(globalUpMonitor)
        }
        localMonitor = nil
        globalDownMonitor = nil
        globalUpMonitor = nil
        pushedButtons.removeAll()
    }

    private func handle(_ event: NSEvent) {
        guard event.buttonNumber >= MouseButtonBinding.minimumShortcutButtonNumber else {
            return
        }

        switch event.type {
        case .otherMouseDown:
            handleMouseDown(buttonNumber: event.buttonNumber)
        case .otherMouseUp:
            handleMouseUp(buttonNumber: event.buttonNumber)
        default:
            break
        }
    }

    private func handleMouseDown(buttonNumber: Int) {
        if preferences.mousePushToTalkEnabled,
           buttonNumber == preferences.mousePushToTalkButton.buttonNumber,
           pushedButtons.insert(buttonNumber).inserted {
            onPushToTalkPressed?()
            return
        }

        if preferences.transcriptCacheMouseEnabled,
           buttonNumber == preferences.transcriptCacheMouseButton.buttonNumber {
            onTranscriptCachePressed?()
        }
    }

    private func handleMouseUp(buttonNumber: Int) {
        guard preferences.mousePushToTalkEnabled,
              buttonNumber == preferences.mousePushToTalkButton.buttonNumber,
              pushedButtons.remove(buttonNumber) != nil else {
            return
        }

        onPushToTalkReleased?()
    }
}
