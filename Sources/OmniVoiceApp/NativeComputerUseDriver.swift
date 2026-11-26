import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OmniVoiceCore

/// Native in-process macOS Computer-Use Driver built directly into OmniSpeak.
/// Uses macOS Accessibility (`AXUIElement`) for structured UI-element discovery &
/// `AXPress` invocation, `CGEvent` (`.privateState`) for mouse/keyboard/scroll input,
/// and `NSWorkspace` for app & URL launching — zero external MCP subprocesses, zero freezes.
@MainActor
final class NativeComputerUseDriver {
    struct AccessibleNode: Identifiable {
        let id: String              // e.g. "e1", "e2", ...
        let role: String            // e.g. "AXButton", "AXTextField", "AXLink"
        let label: String
        let center: CGPoint?
        let element: AXUIElement
    }

    struct ToolDescriptor {
        let name: String
        let description: String
        let schema: String
    }

    static let toolDescriptors: [ToolDescriptor] = [
        ToolDescriptor(name: "open_app", description: "Launch or focus a macOS app by name", schema: #"{"name": "Safari"}"#),
        ToolDescriptor(name: "open_url", description: "Open a URL in the default browser", schema: #"{"url": "https://example.com"}"#),
        ToolDescriptor(name: "click_element", description: "Click an interactive UI element by its element ID (e.g. e1) or visible label", schema: #"{"id": "e1", "label": "Send"}"#),
        ToolDescriptor(name: "click_at", description: "Click exact screen coordinates", schema: #"{"x": 500, "y": 300, "double": false, "right": false}"#),
        ToolDescriptor(name: "type_text", description: "Type text at the current cursor", schema: #"{"text": "hello", "press_enter": false}"#),
        ToolDescriptor(name: "press_key", description: "Press a key or keyboard shortcut", schema: #"{"key": "l", "modifiers": ["cmd"]}"#),
        ToolDescriptor(name: "scroll", description: "Scroll up, down, left, or right", schema: #"{"direction": "down", "amount": 6}"#),
        ToolDescriptor(name: "wait", description: "Pause briefly (seconds, max 3)", schema: #"{"seconds": 0.6}"#),
    ]

    static var toolsPromptSummary: String {
        toolDescriptors.map { "- \($0.name): \($0.description) | args: \($0.schema)" }.joined(separator: "\n")
    }

    private var lastNodes: [String: AccessibleNode] = [:]

    var isAccessibilityReady: Bool {
        AXIsProcessTrusted()
    }

    /// Captures a compact accessibility tree of the frontmost app's focused window
    /// (up to 65 interactive elements) plus the list of visible running apps.
    func captureDesktopState() -> (summary: String, nodes: [AccessibleNode]) {
        lastNodes.removeAll()
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontName = frontApp?.localizedName ?? "Unknown"
        let runningNames = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .prefix(16)
            .joined(separator: ", ")

        var lines: [String] = [
            "Frontmost app: \(frontName)",
            "Running apps: \(runningNames)",
        ]

        guard AXIsProcessTrusted(), let pid = frontApp?.processIdentifier else {
            lines.append("Accessibility elements: (grant Accessibility permission to inspect buttons/fields)")
            return (lines.joined(separator: "\n"), [])
        }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: CFTypeRef?
        let rootElement: AXUIElement
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let win = focusedWindowRef {
            rootElement = (win as! AXUIElement)
            if let winTitle = Self.stringAttribute(kAXTitleAttribute, of: rootElement), !winTitle.isEmpty {
                lines.append("Focused window: \(winTitle)")
            }
        } else {
            rootElement = appElement
        }

        var collected: [AccessibleNode] = []
        Self.collectInteractiveNodes(from: rootElement, depth: 0, maxDepth: 7, maxNodes: 65, into: &collected)
        for node in collected {
            lastNodes[node.id] = node
        }

        if !collected.isEmpty {
            lines.append("Interactive UI elements:")
            for node in collected {
                let coords: String
                if let pt = node.center {
                    coords = " @(\(Int(pt.x)),\(Int(pt.y)))"
                } else {
                    coords = ""
                }
                lines.append("  [\(node.id)] \(node.role) \"\(node.label)\"\(coords)")
            }
        }

        return (lines.joined(separator: "\n"), collected)
    }

    func execute(tool: String, arguments: [String: Any]) async throws -> String {
        switch tool.lowercased() {
        case "open_app", "switch_app", "launch_app":
            let name = (arguments["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return "Missing app name" }
            return try openApp(named: name)

        case "open_url":
            var raw = (arguments["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return "Missing URL" }
            if !raw.contains("://") {
                raw = "https://\(raw)"
            }
            guard let url = URL(string: raw) else { return "Invalid URL: \(raw)" }
            NSWorkspace.shared.open(url)
            return "Opened \(raw)"

        case "click_element":
            let elementID = (arguments["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (arguments["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return clickElement(id: elementID, label: label)

        case "click_at", "click":
            let x = Self.doubleValue(arguments["x"]) ?? 0
            let y = Self.doubleValue(arguments["y"]) ?? 0
            let isDouble = (arguments["double"] as? Bool) ?? false
            let isRight = (arguments["right"] as? Bool) ?? false
            postMouseClick(at: CGPoint(x: x, y: y), rightButton: isRight, clickCount: isDouble ? 2 : 1)
            return "Clicked (\(Int(x)), \(Int(y)))"

        case "type_text", "type":
            let text = (arguments["text"] as? String) ?? ""
            let pressEnter = (arguments["press_enter"] as? Bool) ?? false
            guard !text.isEmpty else { return "Nothing to type" }
            postUnicodeString(text)
            if pressEnter {
                try? await Task.sleep(for: .milliseconds(40))
                postKey(keyName: "enter", modifiers: [])
            }
            return "Typed “\(String(text.prefix(40)))”"

        case "press_key", "hotkey":
            let key = (arguments["key"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let modifiers = (arguments["modifiers"] as? [String]) ?? []
            guard !key.isEmpty else { return "Missing key" }
            postKey(keyName: key, modifiers: modifiers)
            let desc = modifiers.isEmpty ? key : "\(modifiers.joined(separator: "+"))+\(key)"
            return "Pressed \(desc)"

        case "scroll":
            let dir = (arguments["direction"] as? String ?? "down").lowercased()
            let amount = Int(Self.doubleValue(arguments["amount"]) ?? 6)
            postScroll(direction: dir, amount: max(1, min(amount, 30)))
            return "Scrolled \(dir)"

        case "wait":
            let seconds = min(max(Self.doubleValue(arguments["seconds"]) ?? 0.5, 0.1), 3.0)
            try? await Task.sleep(for: .seconds(seconds))
            return "Waited \(String(format: "%.1fs", seconds))"

        default:
            return "Unknown tool: \(tool)"
        }
    }

    // MARK: - Actions

    private func openApp(named name: String) throws -> String {
        // 1. Check already running apps first for instant focus
        let lower = name.lowercased()
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").lowercased() == lower
                || ($0.localizedName ?? "").lowercased().contains(lower)
        }) {
            running.activate(options: [.activateAllWindows])
            return "Switched to \(running.localizedName ?? name)"
        }

        // 2. Fall back to macOS `open -a`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", name]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            return "Opened \(name)"
        }
        return "Could not find app “\(name)”"
    }

    private func clickElement(id: String, label: String) -> String {
        var matched: AccessibleNode?
        if !id.isEmpty, let byID = lastNodes[id] {
            matched = byID
        }
        if matched == nil, !label.isEmpty {
            let lower = label.lowercased()
            matched = lastNodes.values.first(where: { $0.label.lowercased() == lower })
                ?? lastNodes.values.first(where: { $0.label.lowercased().contains(lower) })
        }
        guard let node = matched else {
            return "Could not find UI element “\(label.isEmpty ? id : label)”"
        }

        // Action Ladder: prefer AXPress first (works cleanly without moving cursor),
        // then fall back to exact center-point CGEvent click.
        if AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success {
            return "Clicked “\(node.label)”"
        }
        if let center = node.center {
            postMouseClick(at: center, rightButton: false, clickCount: 1)
            return "Clicked “\(node.label)” at (\(Int(center.x)), \(Int(center.y)))"
        }
        return "Element “\(node.label)” could not be clicked"
    }

    private func postMouseClick(at point: CGPoint, rightButton: Bool, clickCount: Int) {
        let source = CGEventSource(stateID: .privateState)
        let downType: CGEventType = rightButton ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightButton ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = rightButton ? .right : .left

        for clickNum in 1...max(1, clickCount) {
            if let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
               let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button) {
                down.setIntegerValueField(.mouseEventClickState, value: Int64(clickNum))
                up.setIntegerValueField(.mouseEventClickState, value: Int64(clickNum))
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func postUnicodeString(_ text: String) {
        let source = CGEventSource(stateID: .privateState)
        for unit in text.utf16 {
            var char = UniChar(unit)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func postKey(keyName: String, modifiers: [String]) {
        guard let keyCode = Self.virtualKeyCode(for: keyName) else { return }
        var flags: CGEventFlags = []
        for mod in modifiers.map({ $0.lowercased() }) {
            switch mod {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postScroll(direction: String, amount: Int) {
        let source = CGEventSource(stateID: .privateState)
        let vertical: Int32
        let horizontal: Int32
        switch direction {
        case "up": (vertical, horizontal) = (Int32(amount), 0)
        case "down": (vertical, horizontal) = (Int32(-amount), 0)
        case "left": (vertical, horizontal) = (0, Int32(amount))
        case "right": (vertical, horizontal) = (0, Int32(-amount))
        default: (vertical, horizontal) = (Int32(-amount), 0)
        }
        if let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Accessibility Tree Walking

    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXSearchField",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXComboBox",
        "AXMenuItem", "AXMenuButton", "AXTab", "AXRow",
    ]

    private static func collectInteractiveNodes(
        from element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        into results: inout [AccessibleNode]
    ) {
        guard depth <= maxDepth, results.count < maxNodes else { return }

        let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
        if interactiveRoles.contains(role) {
            let label = bestLabel(for: element)
            if !label.isEmpty {
                let id = "e\(results.count + 1)"
                results.append(
                    AccessibleNode(
                        id: id,
                        role: role.replacingOccurrences(of: "AX", with: ""),
                        label: String(label.prefix(64)),
                        center: centerPoint(of: element),
                        element: element
                    )
                )
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }
        for child in children.prefix(40) {
            if results.count >= maxNodes { break }
            collectInteractiveNodes(from: child, depth: depth + 1, maxDepth: maxDepth, maxNodes: maxNodes, into: &results)
        }
    }

    private static func bestLabel(for element: AXUIElement) -> String {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute, kAXHelpAttribute, kAXValueAttribute] {
            if let s = stringAttribute(attr, of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                return s
            }
        }
        return ""
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func centerPoint(of element: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef,
              let sizeVal = sizeRef else {
            return nil
        }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
              size.width > 1, size.height > 1 else {
            return nil
        }
        return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func virtualKeyCode(for name: String) -> CGKeyCode? {
        let map: [String: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06,
            "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E,
            "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
            "6": 0x16, "5": 0x17, "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F,
            "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D,
            "m": 0x2E, "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31,
            "delete": 0x33, "backspace": 0x33, "escape": 0x35, "esc": 0x35,
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        return map[name.lowercased()]
    }
}
