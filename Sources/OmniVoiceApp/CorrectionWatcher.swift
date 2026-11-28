import ApplicationServices
import AppKit
import OmniVoiceCore

/// After OmniSpeak inserts dictated text, watches that field via Accessibility for the user
/// manually correcting a misheard word (e.g. "Neuron" -> "NeroNook") and automatically adds
/// it to the Personal Dictionary via `onLearn` (or refines an in-session learn via `onRefine`).
///
/// Key reliability guarantees (macOS native + Electron / Chromium / WebView composers):
/// 1. **Post-paste retry window (~1.2s):** waits for async `Cmd+V` paste flush in Electron/web apps.
/// 2. **Multi-strategy AX text reader:** reads `AXValue`, `AXStringForRange`, child `AXStaticText`
///    paragraphs (`contenteditable` composers like Claude, Antigravity, Slack, Notion), and parent
///    text containers when the focused node is a leaf.
/// 3. **Smart typing settle + fast active polling (100 ms):** waits **2.2s** while the user is still
///    actively typing inside a word (so pausing mid-word between "Nero" and "Nook" doesn't fire early),
///    commits faster (**0.55s**) once the user adds whitespace/moves away, and polls every 100 ms while
///    editing so hitting Enter immediately after the final keystroke still captures the full word.
/// 4. **In-session refinement:** if a user pauses >2.2s mid-word ("Nero") and then finishes typing
///    ("NeroNook") in the same text box, `onRefine` replaces the partial entry cleanly instead of
///    leaving a half-word behind.
@MainActor
final class CorrectionWatcher {
    /// Fired when a new correction is learned. Return the saved entry ID so in-session
    /// refinements can update that exact entry if the user keeps typing on the same word.
    var onLearn: ((LearnedCorrection) -> String?)?
    /// Fired if the user continues editing the same word after a learn was emitted,
    /// upgrading the previous partial entry (e.g. "Nero" -> "NeroNook").
    var onRefine: ((String, LearnedCorrection) -> String?)?

    private struct Receipt {
        let element: AXUIElement
        let originalBaseline: String
        let originalInsertedRange: Range<String.Index>
        var baseline: String
        var insertedRange: Range<String.Index>
        let deadline: Date
        var lastObservedText: String
        var lastNonEmptyEditedText: String?
        var lastLearnedEntryID: String?
        var lastLearnedCorrection: LearnedCorrection?
    }

    private var receipt: Receipt?
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var pollTimer: Timer?
    private var isFastPolling = false
    private var baselineCaptureTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    private let watchWindowSeconds: TimeInterval = 45
    private let midWordDebounceMilliseconds: Int = 2_200
    private let settledBoundaryDebounceMilliseconds: Int = 600

    /// Start watching the currently-focused text element for manual corrections of `insertedText`.
    func observeFocusedElement(insertedText: String) {
        stop()
        let trimmedInserted = insertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInserted.isEmpty, AXIsProcessTrusted() else { return }

        baselineCaptureTask = Task { @MainActor [weak self] in
            for attempt in 0..<12 {
                guard !Task.isCancelled, let self else { return }
                if attempt > 0 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                }
                if let (element, value, range) = Self.captureBaseline(for: trimmedInserted) {
                    self.beginWatching(element: element, baseline: value, insertedRange: range)
                    return
                }
            }
        }
    }

    func stop() {
        baselineCaptureTask?.cancel()
        baselineCaptureTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        isFastPolling = false
        if let observer, let element = observedElement {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXSelectedTextChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedElement = nil
        receipt = nil
    }

    private func beginWatching(element: AXUIElement, baseline: String, insertedRange: Range<String.Index>) {
        receipt = Receipt(
            element: element,
            originalBaseline: baseline,
            originalInsertedRange: insertedRange,
            baseline: baseline,
            insertedRange: insertedRange,
            deadline: Date().addingTimeInterval(watchWindowSeconds),
            lastObservedText: baseline,
            lastNonEmptyEditedText: nil,
            lastLearnedEntryID: nil,
            lastLearnedCorrection: nil
        )
        installObserver(on: element)
        setPollInterval(0.30, fast: false)
    }

    private func setPollInterval(_ interval: TimeInterval, fast: Bool) {
        if isFastPolling == fast, pollTimer != nil { return }
        pollTimer?.invalidate()
        isFastPolling = fast
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handlePollOrChange() }
        }
    }

    private func handlePollOrChange() {
        guard var currentReceipt = receipt else { return }
        if Date() > currentReceipt.deadline {
            flushPendingEditAndStop()
            return
        }

        guard let currentText = Self.readElementText(currentReceipt.element) else {
            flushPendingEditAndStop()
            return
        }

        // User hit Enter/Send and the chat box cleared — immediately flush the last non-empty edit!
        if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           currentReceipt.lastNonEmptyEditedText != nil
        {
            flushPendingEditAndStop()
            return
        }

        guard currentText != currentReceipt.lastObservedText else { return }
        let previousText = currentReceipt.lastObservedText
        currentReceipt.lastObservedText = currentText
        if currentText != currentReceipt.baseline || currentText != currentReceipt.originalBaseline {
            currentReceipt.lastNonEmptyEditedText = currentText
        }
        receipt = currentReceipt

        // Once the user starts editing, switch to fast 100ms polling so rapid final keystrokes
        // right before Enter/Send are never missed.
        setPollInterval(0.10, fast: true)

        // If the user just typed a word-terminating character (space/punctuation) after editing,
        // settle quickly (0.6s); while mid-word typing, wait a full 2.2s so natural pauses
        // between syllables ("Nero" ... "Nook") never fire prematurely!
        let addedTrailingDelimiter = currentText.count == previousText.count + 1
            && currentText.last.map { $0.isWhitespace || ".!?,;:".contains($0) } == true
        let delayMs = addedTrailingDelimiter ? settledBoundaryDebounceMilliseconds : midWordDebounceMilliseconds
        scheduleDebouncedClassification(delayMilliseconds: delayMs)
    }

    private func scheduleDebouncedClassification(delayMilliseconds: Int) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.evaluateSettledEdit()
        }
    }

    private func evaluateSettledEdit() {
        guard var currentReceipt = receipt,
              let candidateAfter = currentReceipt.lastNonEmptyEditedText else {
            return
        }

        // 1. Check if the user kept typing on the EXACT same word we already learned in this session
        //    (e.g. paused at "Nero", then finished typing "NeroNook"). If so, refine that entry!
        if let prevID = currentReceipt.lastLearnedEntryID,
           let prevCorrection = currentReceipt.lastLearnedCorrection,
           let refined = CorrectionClassifier.classify(
               before: currentReceipt.originalBaseline,
               after: candidateAfter,
               insertedRange: currentReceipt.originalInsertedRange
           ),
           refined.from.lowercased() == prevCorrection.from.lowercased(),
           refined.to != prevCorrection.to
        {
            let updatedID = onRefine?(prevID, refined) ?? prevID
            currentReceipt.lastLearnedEntryID = updatedID
            currentReceipt.lastLearnedCorrection = refined
            advanceBaseline(of: &currentReceipt, to: candidateAfter)
            receipt = currentReceipt
            return
        }

        guard candidateAfter != currentReceipt.baseline else { return }

        guard let correction = CorrectionClassifier.classify(
            before: currentReceipt.baseline,
            after: candidateAfter,
            insertedRange: currentReceipt.insertedRange
        ) else {
            return
        }

        let createdID = onLearn?(correction)
        currentReceipt.lastLearnedEntryID = createdID
        currentReceipt.lastLearnedCorrection = correction
        advanceBaseline(of: &currentReceipt, to: candidateAfter)
        receipt = currentReceipt
    }

    private func advanceBaseline(of currentReceipt: inout Receipt, to settledText: String) {
        let oldInsertedLength = currentReceipt.baseline.distance(
            from: currentReceipt.insertedRange.lowerBound,
            to: currentReceipt.insertedRange.upperBound
        )
        let lengthDelta = settledText.count - currentReceipt.baseline.count
        let lowerOffset = min(
            settledText.count,
            currentReceipt.baseline.distance(from: currentReceipt.baseline.startIndex, to: currentReceipt.insertedRange.lowerBound)
        )
        let newSpanLength = max(1, min(settledText.count - lowerOffset, oldInsertedLength + lengthDelta))
        let newLower = settledText.index(settledText.startIndex, offsetBy: lowerOffset)
        let newUpper = settledText.index(newLower, offsetBy: newSpanLength)

        currentReceipt.baseline = settledText
        currentReceipt.insertedRange = newLower..<newUpper
        currentReceipt.lastNonEmptyEditedText = nil
    }

    private func flushPendingEditAndStop() {
        evaluateSettledEdit()
        stop()
    }

    private func installObserver(on element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<CorrectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handlePollOrChange() }
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, refcon)
        _ = AXObserverAddNotification(observer, element, kAXSelectedTextChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        self.observedElement = element
    }

    // MARK: - Robust Multi-Strategy AX Reading (AppKit + Electron / Chromium / WebView)

    private static func captureBaseline(for insertedText: String) -> (AXUIElement, String, Range<String.Index>)? {
        guard let focused = focusedElement(), !isSecure(focused) else { return nil }

        var candidate: AXUIElement? = focused
        for _ in 0..<3 {
            guard let el = candidate, !isSecure(el) else { break }
            if let text = readElementText(el), !text.isEmpty {
                if let range = text.range(of: insertedText, options: .backwards) {
                    return (el, text, range)
                }
                let normalizedText = text.replacingOccurrences(of: "\u{00A0}", with: " ")
                if let range = normalizedText.range(of: insertedText, options: .backwards) {
                    return (el, normalizedText, range)
                }
            }
            candidate = parentElement(of: el)
        }
        return nil
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        return (focused as! AXUIElement)
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
              let parent = ref else { return nil }
        return (parent as! AXUIElement)
    }

    private static func readElementText(_ element: AXUIElement) -> String? {
        // 1. Standard AXValue
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let str = valueRef as? String, !str.isEmpty {
            return str
        }

        // 2. AXNumberOfCharacters + AXStringForRange (Chromium / WebKit / rich editors)
        var countRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countRef) == .success,
           let count = (countRef as? NSNumber)?.intValue, count > 0, count <= 50_000
        {
            var cfRange = CFRange(location: 0, length: count)
            if let axRange = AXValueCreate(.cfRange, &cfRange) {
                var strRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    axRange,
                    &strRef
                ) == .success, let str = strRef as? String, !str.isEmpty {
                    return str
                }
            }
        }

        // 3. ContentEditable child AXStaticText aggregation (Claude, Antigravity, Slack, Notion, Teams)
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement], !children.isEmpty, children.count <= 40
        {
            var fragments: [String] = []
            for child in children {
                if let fragment = collectStaticText(from: child, depth: 0), !fragment.isEmpty {
                    fragments.append(fragment)
                }
            }
            if !fragments.isEmpty {
                return fragments.joined(separator: "\n")
            }
        }

        if let empty = valueRef as? String {
            return empty
        }
        return nil
    }

    private static func collectStaticText(from element: AXUIElement, depth: Int) -> String? {
        guard depth <= 2 else { return nil }
        var roleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        if role == "AXStaticText" {
            var valRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valRef) == .success,
               let text = valRef as? String {
                return text
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], !children.isEmpty, children.count <= 30 else {
            return nil
        }
        let nested = children.compactMap { collectStaticText(from: $0, depth: depth + 1) }.filter { !$0.isEmpty }
        return nested.isEmpty ? nil : nested.joined(separator: " ")
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success,
              let role = ref as? String else { return false }
        return role == "AXSecureTextField"
    }
}
