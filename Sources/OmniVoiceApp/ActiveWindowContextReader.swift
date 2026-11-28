import AppKit
import Foundation
import OmniVoiceCore

/// Ephemeral, privacy-first reader that extracts distinctive vocabulary hints from the
/// active application, focused window title, and visible text around the cursor for a
/// single dictation utterance.
///
/// Guarantees:
/// - Never persists or logs captured text or extracted terms
/// - Completely skipped for `AXSecureTextField` / password fields
/// - Bounded to ~2,500 visible characters and capped by `WindowVocabularyExtractor`
@MainActor
enum ActiveWindowContextReader {
    private static let maxVisibleTextCharacters = 2_500
    private static let maxStaticTextNodes = 40
    private static let maxStaticTextDepth = 3

    static func captureEphemeralVocabulary(for target: TextInsertionService.Target?) -> [String] {
        guard AXIsProcessTrusted() else { return [] }

        let focusedElement = target?.focusedElement ?? systemFocusedElement()
        if let focusedElement, isSecureElement(focusedElement) {
            return []
        }

        let application = target?.application ?? NSWorkspace.shared.frontmostApplication
        var rawSnippets: [String] = []

        if let appName = application?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appName.isEmpty
        {
            rawSnippets.append(appName)
        }

        if let windowTitle = focusedWindowTitle(for: application, focusedElement: focusedElement),
           !windowTitle.isEmpty
        {
            rawSnippets.append(windowTitle)
        }

        if let visibleText = boundedVisibleText(for: target, focusedElement: focusedElement),
           !visibleText.isEmpty
        {
            rawSnippets.append(visibleText)
        }

        return WindowVocabularyExtractor.extractTerms(from: rawSnippets)
    }

    // MARK: - Accessibility Helpers

    private static func systemFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef
        else {
            return nil
        }
        return (focused as! AXUIElement)
    }

    private static func stringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func isSecureElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as String, on: element)
        let subrole = stringAttribute(kAXSubroleAttribute as String, on: element)
        if role == "AXSecureTextField" || subrole == (kAXSecureTextFieldSubrole as String) || subrole == "AXSecureTextField" {
            return true
        }
        return false
    }

    private static func focusedWindowTitle(
        for application: NSRunningApplication?,
        focusedElement: AXUIElement?
    ) -> String? {
        if let pid = application?.processIdentifier, pid > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef
            {
                let windowElement = window as! AXUIElement
                if let title = stringAttribute(kAXTitleAttribute as String, on: windowElement)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty
                {
                    return title
                }
            }
        }

        if let focusedElement {
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(focusedElement, kAXWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef
            {
                let windowElement = window as! AXUIElement
                if let title = stringAttribute(kAXTitleAttribute as String, on: windowElement)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty
                {
                    return title
                }
            }
        }

        return nil
    }

    private static func boundedVisibleText(
        for target: TextInsertionService.Target?,
        focusedElement: AXUIElement?
    ) -> String? {
        // 1. Reuse already-captured target text when available (zero extra AX IPC).
        if let currentValue = target?.currentValue, !currentValue.isEmpty {
            return sliceAroundCaret(currentValue, selectedRange: target?.selectedRange, maxChars: maxVisibleTextCharacters)
        }

        guard let focusedElement else { return nil }

        // 2. Prefer visible character range via parameterized attribute (fast on huge editors).
        if let visibleSlice = visibleRangeString(from: focusedElement, maxChars: maxVisibleTextCharacters),
           !visibleSlice.isEmpty
        {
            return visibleSlice
        }

        // 3. Fall back to kAXValueAttribute bounded around cursor.
        if let value = stringAttribute(kAXValueAttribute as String, on: focusedElement), !value.isEmpty {
            return sliceAroundCaret(value, selectedRange: target?.selectedRange, maxChars: maxVisibleTextCharacters)
        }

        // 4. Fall back to shallow AXStaticText descendants inside the focused element.
        var collected: [String] = []
        var remainingChars = maxVisibleTextCharacters
        var visitedNodes = 0
        collectStaticText(
            from: focusedElement,
            depth: 0,
            visitedNodes: &visitedNodes,
            remainingChars: &remainingChars,
            into: &collected
        )
        return collected.isEmpty ? nil : collected.joined(separator: " ")
    }

    private static func visibleRangeString(from element: AXUIElement, maxChars: Int) -> String? {
        var visibleRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visibleRangeRef) == .success,
              let rangeValue = visibleRangeRef
        else {
            return nil
        }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange),
              cfRange.location >= 0,
              cfRange.length > 0
        else {
            return nil
        }

        var clamped = CFRange(location: cfRange.location, length: min(cfRange.length, maxChars))
        guard let param = AXValueCreate(.cfRange, &clamped) else { return nil }

        var stringRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            param,
            &stringRef
        ) == .success,
              let text = stringRef as? String
        else {
            return nil
        }

        return text.count > maxChars ? String(text.prefix(maxChars)) : text
    }

    private static func collectStaticText(
        from element: AXUIElement,
        depth: Int,
        visitedNodes: inout Int,
        remainingChars: inout Int,
        into out: inout [String]
    ) {
        guard depth <= maxStaticTextDepth, visitedNodes < maxStaticTextNodes, remainingChars > 0 else {
            return
        }
        visitedNodes += 1

        if isSecureElement(element) {
            return
        }

        let role = stringAttribute(kAXRoleAttribute as String, on: element)
        if role == (kAXStaticTextRole as String) {
            if let value = stringAttribute(kAXValueAttribute as String, on: element)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                let snippet = value.count > remainingChars ? String(value.prefix(remainingChars)) : value
                out.append(snippet)
                remainingChars -= snippet.count
            }
            return
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return
        }

        for child in children {
            guard visitedNodes < maxStaticTextNodes, remainingChars > 0 else { break }
            collectStaticText(
                from: child,
                depth: depth + 1,
                visitedNodes: &visitedNodes,
                remainingChars: &remainingChars,
                into: &out
            )
        }
    }

    private static func sliceAroundCaret(_ text: String, selectedRange: NSRange?, maxChars: Int) -> String {
        let ns = text as NSString
        guard ns.length > maxChars else { return text }

        if let range = selectedRange, range.location >= 0, range.location <= ns.length {
            let half = maxChars / 2
            let start = max(0, min(range.location - half, ns.length - maxChars))
            let length = min(maxChars, ns.length - start)
            return ns.substring(with: NSRange(location: start, length: length))
        }

        return ns.substring(with: NSRange(location: max(0, ns.length - maxChars), length: maxChars))
    }
}
