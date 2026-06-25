import AppKit
import OmniVoiceCore
import SwiftUI

struct MouseButtonRecorderView: View {
    let title: String
    let binding: MouseButtonBinding
    let theme: OmniVoiceTheme
    let onChange: (MouseButtonBinding) -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?
    @State private var validationMessage: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(displayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(isRecording ? .secondary : .primary)
                        .frame(minWidth: 118, alignment: .trailing)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .themeSurface(theme, cornerRadius: 8)
        .onDisappear {
            stopRecording()
        }
    }

    private var displayText: String {
        isRecording ? "Click side button..." : binding.displayName
    }

    private func startRecording() {
        stopRecording()
        validationMessage = "Click an extra mouse button"
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { event in
            handle(event)
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { event in
            Task { @MainActor in
                handle(event)
            }
        }
    }

    private func handle(_ event: NSEvent) {
        guard isRecording else { return }

        let candidate = MouseButtonBinding(buttonNumber: event.buttonNumber)
        guard candidate.isUsableShortcut else {
            validationMessage = "Use a side or extra mouse button"
            return
        }

        onChange(candidate)
        stopRecording()
    }

    private func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        isRecording = false
        validationMessage = nil
    }
}
