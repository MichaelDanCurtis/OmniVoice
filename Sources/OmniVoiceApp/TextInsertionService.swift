import AppKit
import OmniVoiceCore
import OSLog

@MainActor
final class TextInsertionService {
    private let logger = Logger(subsystem: "com.omnivoice.OmniVoiceApp", category: "Insertion")

    struct Target {
        let application: NSRunningApplication?
        let focusedElement: AXUIElement?
        let selectedText: String
        let currentValue: String
        let selectedRange: NSRange?
    }

    enum InsertionError: LocalizedError {
        case accessibilityPermissionRequired
        case noInsertionToUndo
        case pasteboardUnavailable
        case syntheticTypingUnavailable

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                "Accessibility permission is required to insert dictated text."
            case .noInsertionToUndo:
                "There is no recent OmniVoice insertion to undo."
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
        let previousCursorLocation: Int
    }

    private var lastDirectInsertion: DirectInsertionRecord?

    func captureTarget() -> Target {
        let focusedElement = Self.focusedElement()
        let application = focusedElement.flatMap(Self.application(for:))
            ?? NSWorkspace.shared.frontmostApplication
        let textState = focusedElement.flatMap(Self.textState(for:))
        logger.info(
            "Captured insertion target focused=\(focusedElement != nil, privacy: .public) app=\(application?.bundleIdentifier ?? "unknown", privacy: .public)"
        )

        return Target(
            application: application,
            focusedElement: focusedElement,
            selectedText: textState?.selectedText ?? "",
            currentValue: textState?.currentValue ?? "",
            selectedRange: textState?.selectedRange
        )
    }

    func insert(_ text: String, target: Target?) async throws {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility trust missing; copied fallback will be used")
            throw InsertionError.accessibilityPermissionRequired
        }
        let insertionText = TextInsertionEdit.sanitizedInsertionText(text)

        if let application = target?.application, application.bundleIdentifier != Bundle.main.bundleIdentifier {
            application.activate()
            try await Task.sleep(nanoseconds: 150_000_000)
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

        guard AXUIElementSetAttributeValue(record.element, kAXValueAttribute as CFString, record.previousText as CFString) == .success else {
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

        lastDirectInsertion = DirectInsertionRecord(
            application: Self.application(for: focused),
            element: focused,
            previousText: currentValue,
            previousCursorLocation: selectedRange.location
        )
        if !setCaretLocation(edit.cursorLocation, in: focused) {
            logger.warning("Accessibility insertion succeeded but caret confirmation failed")
        }
        return true
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
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restore(previousItems, to: pasteboard)
            throw InsertionError.pasteboardUnavailable
        }
        let ownChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        commandDown?.flags = .maskCommand
        commandUp?.flags = .maskCommand
        commandDown?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if pasteboard.changeCount == ownChangeCount {
                self.restore(previousItems, to: pasteboard)
            }
        }
    }

    private func typeWithSyntheticKeystrokes(_ text: String) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        for codeUnit in text.utf16 {
            var value = UniChar(codeUnit)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw InsertionError.syntheticTypingUnavailable
            }
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
