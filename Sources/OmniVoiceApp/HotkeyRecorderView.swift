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

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(isRecording ? "Press keys..." : binding.displayName)
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

    private func startRecording() {
        stopRecording()
        validationMessage = "Use at least one modifier"
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isRecording else { return event }
            if event.keyCode == 53, !hasPressedModifier(event) {
                stopRecording()
                return nil
            }
            if let hotkey = HotkeyBinding(event: event), hotkey.hasModifier {
                onChange(hotkey)
                stopRecording()
            } else {
                validationMessage = "Press a key with ⌘, ⌥, ⌃, or ⇧"
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }

    private func hasPressedModifier(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            || event.modifierFlags.contains(.option)
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.shift)
    }
}

private extension HotkeyBinding {
    init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(
            command: event.modifierFlags.contains(.command),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control),
            shift: event.modifierFlags.contains(.shift)
        )
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
}
