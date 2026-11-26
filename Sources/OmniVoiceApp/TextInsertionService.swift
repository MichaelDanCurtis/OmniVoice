import AppKit
import OmniVoiceCore
import OSLog

@MainActor
final class TextInsertionService {
    private let logger = Logger(subsystem: "com.omnispeak.OmniVoiceApp", category: "Insertion")

    struct Target {
        let application: NSRunningApplication?
        let focusedElement: AXUIElement?
        let selectedText: String
        let currentValue: String
        let selectedRange: NSRange?
        let insertionStrategy: TextInsertionStrategy
        let caretFrame: CGRect?
    }

    enum LiveDraftMode {
        case accessibility(
            element: AXUIElement,
            originalText: String,
            selectedRange: NSRange,
            placeholderValues: [String]
        )
        case syntheticDiff
    }

    struct LiveDraft {
        let application: NSRunningApplication?
        let mode: LiveDraftMode
        var currentText: String
    }

    enum InsertionError: LocalizedError {
        case accessibilityPermissionRequired
        case noInsertionToUndo
        case insertionChanged
        case pasteboardUnavailable
        case syntheticTypingUnavailable

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                "Accessibility permission is required to insert dictated text."
            case .noInsertionToUndo:
                "There is no recent OmniSpeak insertion to undo."
            case .insertionChanged:
                "Text changed after dictation; nothing was undone."
            case .pasteboardUnavailable:
                "The pasteboard was unavailable."
            case .syntheticTypingUnavailable:
                "Synthetic typing was unavailable."
            }
        }
    }

    private struct DirectInsertionRecord {
        let application: NSRunningApplication?
        let element: AXUIElement
        let previousText: String
        let insertedValue: String
        let previousCursorLocation: Int
    }

    private struct PendingPasteboardRestore {
        let originalItems: [NSPasteboardItem]
        let expectedChangeCount: Int
        let workItem: DispatchWorkItem
    }

    private var lastDirectInsertion: DirectInsertionRecord?
    private var pendingPasteboardRestore: PendingPasteboardRestore?

    func captureTarget() -> Target {
        let focusedElement = Self.focusedElement()
        let application = focusedElement.flatMap(Self.application(for:))
            ?? NSWorkspace.shared.frontmostApplication
        let textState = focusedElement.flatMap(Self.textState(for:))
        let currentValue = textState?.currentValue ?? ""
        let selectedRange = textState?.selectedRange
        let insertionStrategy = TextInsertionTargetPolicy.strategy(
            bundleIdentifier: application?.bundleIdentifier,
            applicationName: application?.localizedName,
            currentValue: currentValue,
            selectedRange: selectedRange
        )
        let caretFrame = focusedElement.flatMap { element in
            Self.caretFrame(
                for: selectedRange,
                currentValue: currentValue,
                in: element
            ) ?? Self.elementFrame(for: element)
        }
        logger.info(
            "Captured insertion target focused=\(focusedElement != nil, privacy: .public) app=\(application?.bundleIdentifier ?? "unknown", privacy: .public) strategy=\(insertionStrategy.rawValue, privacy: .public)"
        )

        return Target(
            application: application,
            focusedElement: focusedElement,
            selectedText: textState?.selectedText ?? "",
            currentValue: currentValue,
            selectedRange: selectedRange,
            insertionStrategy: insertionStrategy,
            caretFrame: caretFrame
        )
    }

    func insert(_ text: String, target: Target?) async throws {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility trust missing; copied fallback will be used")
            throw InsertionError.accessibilityPermissionRequired
        }
        let insertionText = TextInsertionEdit.sanitizedInsertionText(text)

        if let application = target?.application,
           application.bundleIdentifier != Bundle.main.bundleIdentifier,
           application.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            application.activate()
            try await Task.sleep(nanoseconds: 60_000_000)
        }

        if target?.insertionStrategy == .pasteboardOnly {
            logger.info("Using pasteboard-only insertion for rich composer target")
            try insertWithPasteboard(insertionText)
            return
        }

        if let focusedElement = target?.focusedElement, insertWithAccessibility(insertionText, into: focusedElement) {
            logger.info("Inserted using captured accessibility element")
            return
        }

        if insertWithAccessibility(insertionText, into: Self.focusedElement()) {
            logger.info("Inserted using current accessibility element")
            return
        }

        do {
            logger.info("Accessibility direct insertion unavailable; posting pasteboard paste")
            try insertWithPasteboard(insertionText)
        } catch {
            logger.error("Pasteboard insertion failed; falling back to synthetic typing")
            try typeWithSyntheticKeystrokes(insertionText)
        }
    }

    func beginLiveDraft(target: Target?) -> LiveDraft? {
        guard AXIsProcessTrusted() else {
            logger.warning("Live draft skipped because accessibility trust is missing")
            return nil
        }
        // Do not overwrite highlighted text while live drafting (preserves Voice Edit selection).
        if let selectedText = target?.selectedText, !selectedText.isEmpty {
            logger.info("Live draft skipped because text is currently selected")
            return nil
        }
        if let target,
           let focusedElement = target.focusedElement,
           let selectedRange = target.selectedRange,
           target.insertionStrategy == .directAccessibility,
           selectedRange.length == 0 {
            return LiveDraft(
                application: target.application,
                mode: .accessibility(
                    element: focusedElement,
                    originalText: target.currentValue,
                    selectedRange: selectedRange,
                    placeholderValues: Self.placeholderValues(for: focusedElement)
                ),
                currentText: ""
            )
        }

        // For Electron/Chromium/rich composers (Antigravity, Chrome, Slack, VS Code, Terminal, etc.),
        // stream live drafts via modifier-isolated synthetic diff keystrokes right at the active cursor.
        logger.info("Starting synthetic-diff live draft for app=\(target?.application?.bundleIdentifier ?? "unknown", privacy: .public)")
        return LiveDraft(
            application: target?.application,
            mode: .syntheticDiff,
            currentText: ""
        )
    }

    @discardableResult
    func updateLiveDraft(_ text: String, draft: inout LiveDraft) -> Bool {
        applyLiveDraftText(text, draft: &draft, recordUndo: false)
    }

    @discardableResult
    func commitLiveDraft(_ text: String, draft: inout LiveDraft) -> Bool {
        applyLiveDraftText(text, draft: &draft, recordUndo: true)
    }

    func cancelLiveDraft(_ draft: LiveDraft) {
        guard AXIsProcessTrusted() else { return }
        switch draft.mode {
        case .accessibility(let element, let originalText, let selectedRange, _):
            guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, originalText as CFString) == .success else {
                logger.warning("Live draft restore failed")
                return
            }
            _ = setCaretLocation(selectedRange.location, in: element)
        case .syntheticDiff:
            guard !draft.currentText.isEmpty else { return }
            postBackspaces(count: draft.currentText.count)
        }
    }

    func undoLastInsertion() async throws {
        guard AXIsProcessTrusted() else {
            throw InsertionError.accessibilityPermissionRequired
        }
        guard let record = lastDirectInsertion else {
            throw InsertionError.noInsertionToUndo
        }

        if let application = record.application, application.bundleIdentifier != Bundle.main.bundleIdentifier {
            application.activate()
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        guard let currentValue = Self.textState(for: record.element)?.currentValue else {
            throw InsertionError.syntheticTypingUnavailable
        }
        guard let restoredValue = TextInsertionEdit.restoredPreviousValue(
            currentValue: currentValue,
            insertedValue: record.insertedValue,
            previousValue: record.previousText
        ) else {
            throw InsertionError.insertionChanged
        }

        guard AXUIElementSetAttributeValue(record.element, kAXValueAttribute as CFString, restoredValue as CFString) == .success else {
            throw InsertionError.syntheticTypingUnavailable
        }
        _ = setCaretLocation(record.previousCursorLocation, in: record.element)
        lastDirectInsertion = nil
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return nil
        }

        return (focused as! AXUIElement)
    }

    private static func application(for element: AXUIElement) -> NSRunningApplication? {
        var pid = pid_t(0)
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }

        return NSRunningApplication(processIdentifier: pid)
    }

    private static func textState(for element: AXUIElement) -> (currentValue: String, selectedText: String, selectedRange: NSRange?)? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let currentValue = valueRef as? String else {
            return nil
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else {
            return (currentValue, "", nil)
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange) else {
            return (currentValue, "", nil)
        }

        let nsValue = currentValue as NSString
        let range = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard range.location >= 0,
              range.length >= 0,
              range.location <= nsValue.length,
              range.location + range.length <= nsValue.length else {
            return (currentValue, "", nil)
        }

        return (currentValue, nsValue.substring(with: range), range)
    }

    private func insertWithAccessibility(_ text: String, into focused: AXUIElement?) -> Bool {
        guard let focused else {
            return false
        }

        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
              AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let currentValue = valueRef as? String,
              let rangeValue = rangeRef else {
            return false
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange) else {
            return false
        }

        guard let edit = TextInsertionEdit.make(
            currentValue: currentValue,
            selectedRange: NSRange(location: selectedRange.location, length: selectedRange.length),
            insertion: text,
            placeholderValues: Self.placeholderValues(for: focused)
        ) else {
            return false
        }
        if edit.ignoredPlaceholder {
            logger.info("Ignored accessibility placeholder while inserting dictated text")
        }

        guard AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, edit.text as CFString) == .success else {
            return false
        }

        // Verify the write actually took effect. Electron/Chromium webviews and custom
        // editors often return AXError.success as a no-op without mutating the field.
        if edit.text != currentValue {
            var verifiedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &verifiedRef) == .success,
               let verifiedValue = verifiedRef as? String,
               verifiedValue == currentValue {
                logger.warning("Accessibility value write was ignored by target element; falling back to pasteboard")
                return false
            }
        }

        lastDirectInsertion = DirectInsertionRecord(
            application: Self.application(for: focused),
            element: focused,
            previousText: currentValue,
            insertedValue: edit.text,
            previousCursorLocation: selectedRange.location
        )
        if !setCaretLocation(edit.cursorLocation, in: focused) {
            logger.warning("Accessibility insertion succeeded but caret confirmation failed")
        }
        return true
    }

    private func applyLiveDraftText(_ text: String, draft: inout LiveDraft, recordUndo: Bool) -> Bool {
        let insertionText = TextInsertionEdit.sanitizedInsertionText(text)
        guard !insertionText.isEmpty else {
            return false
        }

        switch draft.mode {
        case .accessibility(let element, let originalText, let selectedRange, let placeholderValues):
            guard let edit = TextInsertionEdit.make(
                currentValue: originalText,
                selectedRange: selectedRange,
                insertion: insertionText,
                placeholderValues: placeholderValues
            ) else {
                return false
            }

            guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, edit.text as CFString) == .success else {
                logger.warning("Live draft accessibility update failed")
                return false
            }
            if recordUndo {
                lastDirectInsertion = DirectInsertionRecord(
                    application: draft.application,
                    element: element,
                    previousText: originalText,
                    insertedValue: edit.text,
                    previousCursorLocation: selectedRange.location
                )
            }
            draft.currentText = insertionText
            _ = setCaretLocation(edit.cursorLocation, in: element)
            return true

        case .syntheticDiff:
            guard insertionText != draft.currentText else {
                return true
            }
            let oldChars = Array(draft.currentText)
            let newChars = Array(insertionText)
            var prefixCount = 0
            while prefixCount < oldChars.count,
                  prefixCount < newChars.count,
                  oldChars[prefixCount] == newChars[prefixCount] {
                prefixCount += 1
            }

            let deleteCount = oldChars.count - prefixCount
            if deleteCount > 0 {
                postBackspaces(count: deleteCount)
            }

            let suffix = String(newChars[prefixCount...])
            if !suffix.isEmpty {
                do {
                    try typeWithSyntheticKeystrokes(suffix)
                } catch {
                    logger.warning("Synthetic live draft typing failed: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }
            draft.currentText = insertionText
            return true
        }
    }

    private func postBackspaces(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) else {
                break
            }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func setCaretLocation(_ location: Int, in element: AXUIElement) -> Bool {
        guard location >= 0 else {
            return false
        }

        let immediateSuccess = Self.applyCaretLocation(location, to: element)
            && Self.caretLocation(in: element) == location

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = Self.applyCaretLocation(location, to: element)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            _ = Self.applyCaretLocation(location, to: element)
        }

        return immediateSuccess
    }

    private static func applyCaretLocation(_ location: Int, to element: AXUIElement) -> Bool {
        var newRange = CFRange(location: location, length: 0)
        guard let newRangeValue = AXValueCreate(.cfRange, &newRange) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRangeValue) == .success
    }

    private static func caretLocation(in element: AXUIElement) -> Int? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else {
            return nil
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange) else {
            return nil
        }
        return selectedRange.location
    }

    private static func caretFrame(for selectedRange: NSRange?, currentValue: String, in element: AXUIElement) -> CGRect? {
        guard let selectedRange else { return nil }

        if let frame = boundsForRange(
            NSRange(location: selectedRange.location, length: selectedRange.length),
            in: element
        ) {
            return frame
        }

        if selectedRange.length == 0, selectedRange.location < (currentValue as NSString).length,
           let nextCharacterFrame = boundsForRange(NSRange(location: selectedRange.location, length: 1), in: element) {
            return CGRect(
                x: nextCharacterFrame.minX,
                y: nextCharacterFrame.minY,
                width: 2,
                height: nextCharacterFrame.height
            )
        }

        if selectedRange.length == 0, selectedRange.location > 0,
           let previousCharacterFrame = boundsForRange(NSRange(location: selectedRange.location - 1, length: 1), in: element) {
            return CGRect(
                x: previousCharacterFrame.maxX,
                y: previousCharacterFrame.minY,
                width: 2,
                height: previousCharacterFrame.height
            )
        }

        return nil
    }

    private static func boundsForRange(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success, let boundsValue = boundsRef else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds), !bounds.isEmpty else {
            return nil
        }
        return appKitFrame(fromAccessibilityFrame: bounds)
    }

    private static func elementFrame(for element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              !size.equalTo(.zero) else {
            return nil
        }

        return appKitFrame(fromAccessibilityFrame: CGRect(origin: position, size: size))
    }

    private static func appKitFrame(fromAccessibilityFrame frame: CGRect) -> CGRect {
        let desktopFrame = NSScreen.screens.reduce(CGRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        guard !desktopFrame.isNull else {
            return frame
        }

        return CGRect(
            x: frame.minX,
            y: desktopFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private static func placeholderValues(for element: AXUIElement) -> [String] {
        [
            "AXPlaceholderValue",
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXTitleAttribute as String,
        ].compactMap { attribute in
            var valueRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success else {
                return nil
            }
            return valueRef as? String
        }
    }

    private func insertWithPasteboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousItems: [NSPasteboardItem]
        if let pending = pendingPasteboardRestore {
            pending.workItem.cancel()
            pendingPasteboardRestore = nil
            if pasteboard.changeCount == pending.expectedChangeCount {
                // Back-to-back dictation before the previous restore fired: preserve the
                // user's original pre-dictation clipboard rather than our prior dictation.
                previousItems = pending.originalItems
            } else {
                previousItems = snapshotPasteboardItems(from: pasteboard)
            }
        } else {
            previousItems = snapshotPasteboardItems(from: pasteboard)
        }

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restore(previousItems, to: pasteboard)
            throw InsertionError.pasteboardUnavailable
        }
        // This paste is transient (restored below); mark it so clipboard-history managers
        // (Paste, Maccy, …) don't persist the inserted text.
        _ = pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ownChangeCount = pasteboard.changeCount

        // Use .privateState so residual physical modifier keys from the dictation hotkey
        // (e.g. Option in ⌥Space) cannot leak into Cmd+V and turn it into Opt+Cmd+V.
        let source = CGEventSource(stateID: .privateState)
        guard let cmdKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            restore(previousItems, to: pasteboard)
            throw InsertionError.syntheticTypingUnavailable
        }
        cmdKeyDown.flags = .maskCommand
        vKeyDown.flags = .maskCommand
        vKeyUp.flags = .maskCommand
        cmdKeyUp.flags = []
        cmdKeyDown.post(tap: .cghidEventTap)
        vKeyDown.post(tap: .cghidEventTap)
        vKeyUp.post(tap: .cghidEventTap)
        cmdKeyUp.post(tap: .cghidEventTap)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPasteboardRestore = nil
            if pasteboard.changeCount == ownChangeCount {
                self.restore(previousItems, to: pasteboard)
            }
        }
        pendingPasteboardRestore = PendingPasteboardRestore(
            originalItems: previousItems,
            expectedChangeCount: ownChangeCount,
            workItem: workItem
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func snapshotPasteboardItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }

    private func typeWithSyntheticKeystrokes(_ text: String) throws {
        // Use .privateState with empty flags so held push-to-talk modifiers (Option/Control)
        // never leak into synthetic Unicode characters during live drafting.
        let source = CGEventSource(stateID: .privateState)
        for codeUnit in text.utf16 {
            var value = UniChar(codeUnit)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw InsertionError.syntheticTypingUnavailable
            }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
