import ApplicationServices
import AppKit
import OmniVoiceCore

/// After OmniSpeak inserts dictated text, briefly watches that field (Accessibility) for the
/// user correcting the inserted word, and reports a learnable correction. All reads are bounded
/// to one element for a short window; nothing is stored or transmitted. The decision logic is
/// the pure `CorrectionClassifier` — this class is just the plumbing (manual-tested).
@MainActor
final class CorrectionWatcher {
    var onLearn: ((LearnedCorrection) -> Void)?

    private struct Receipt {
        let element: AXUIElement
        let baseline: String
        let insertedRange: Range<String.Index>
        let deadline: Date
    }

    private var receipt: Receipt?
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var pollTimer: Timer?

    /// Start watching the currently-focused text element for a correction of `insertedText`.
    func observeFocusedElement(insertedText: String) {
        stop()
        guard AXIsProcessTrusted(), let element = Self.focusedElement() else { return }
        guard !Self.isSecure(element) else { return }
        guard let value = Self.value(of: element),
              let range = value.range(of: insertedText, options: .backwards) else { return }

        receipt = Receipt(element: element, baseline: value, insertedRange: range,
                          deadline: Date().addingTimeInterval(20))
        installObserver(on: element)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleValueChange() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let observer, let element = observedElement {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedElement = nil
        receipt = nil
    }

    private func handleValueChange() {
        guard let receipt else { return }
        if Date() > receipt.deadline { stop(); return }
        guard let current = Self.value(of: receipt.element), current != receipt.baseline else { return }
        if let correction = CorrectionClassifier.classify(
            before: receipt.baseline, after: current, insertedRange: receipt.insertedRange
        ) {
            let handler = onLearn
            stop()
            handler?(correction)
        }
    }

    private func installObserver(on element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<CorrectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handleValueChange() }
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, refcon) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        self.observedElement = element
    }

    // MARK: - AX reads

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        return (focused as! AXUIElement)
    }

    private static func value(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success,
              let value = ref as? String else { return nil }
        return value
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success,
              let role = ref as? String else { return false }
        return role == "AXSecureTextField"
    }
}
