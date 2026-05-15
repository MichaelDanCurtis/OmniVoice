import AppKit
import SwiftUI
import OmniVoiceCore

struct HotkeyRecorderView: View {
    let title: String
    let binding: HotkeyBinding
    let onChange: (HotkeyBinding) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var validationMessage: String?
    @State private var pendingModifiers: UInt32 = 0
    @State private var lastModifierChord: UInt32 = 0

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(displayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(isRecording ? .secondary : .primary)
                        .frame(minWidth: 112, alignment: .trailing)

                    Button(isRecording ? "Cancel" : "Record") {
                        isRecording ? stopRecording() : startRecording()
                    }
                    .controlSize(.small)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var displayText: String {
        guard isRecording else { return binding.displayName }
        let visibleModifiers = pendingModifiers.modifierCount >= lastModifierChord.modifierCount
            ? pendingModifiers
            : lastModifierChord
        guard visibleModifiers != 0 else { return "Press keys..." }
        return "\(HotkeyBinding.displayName(forModifiers: visibleModifiers)) + key"
    }

    private func startRecording() {
        stopRecording()
        validationMessage = "Press modifiers, then a key"
        pendingModifiers = 0
        lastModifierChord = 0
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard isRecording else { return event }
            switch event.type {
            case .flagsChanged:
                handleModifierChange(event)
            case .keyDown:
                handleKeyDown(event)
            default:
                break
            }
            return nil
        }
    }

    private func handleModifierChange(_ event: NSEvent) {
        let modifiers = HotkeyBinding.carbonModifiers(from: event.modifierFlags)
        pendingModifiers = modifiers

        if modifiers != 0 {
            if modifiers.modifierCount >= lastModifierChord.modifierCount {
                lastModifierChord = modifiers
            }
            validationMessage = modifiers.modifierCount >= 2
                ? "Release to save, or press a key"
                : "Add another modifier, or press a key"
            return
        }

        guard lastModifierChord != 0 else { return }
        if lastModifierChord.modifierCount >= 2 {
            onChange(.modifierOnly(lastModifierChord))
            stopRecording()
        } else {
            lastModifierChord = 0
            validationMessage = "Use two modifiers, or one modifier plus a key"
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let modifiers = HotkeyBinding.carbonModifiers(from: event.modifierFlags)
        pendingModifiers = modifiers

        if event.keyCode == 53, modifiers == 0 {
            stopRecording()
            return
        }

        if let hotkey = HotkeyBinding(event: event), hotkey.hasModifier {
            onChange(hotkey)
            stopRecording()
        } else {
            validationMessage = "Press a key with ⌘, ⌥, ⌃, or ⇧"
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        validationMessage = nil
        pendingModifiers = 0
        lastModifierChord = 0
    }
}

private extension UInt32 {
    var modifierCount: Int {
        HotkeyBinding.modifierCount(in: self)
    }
}

private extension HotkeyBinding {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        carbonModifiers(
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
    }

    init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
}
