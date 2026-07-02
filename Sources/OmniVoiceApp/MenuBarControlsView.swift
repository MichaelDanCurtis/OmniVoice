import AppKit
import SwiftUI
import OmniVoiceCore

struct MenuBarControlsView: View {
    @Bindable var model: AppModel
    let showTestCaption: () -> Void
    let requestAccessibilityPermission: () -> Void
    let openConversationMode: () -> Void
    let openEditor: () -> Void
    let openAskAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.statusText)
                .font(.headline)
                .lineLimit(1)

            Text("Engine: \(model.engineState.label)")
                .foregroundStyle(model.engineState == .online ? .primary : .secondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color(themeColor: model.activeTheme.accentColor))
                    .frame(width: 9, height: 9)
                Text("Theme: \(model.activeTheme.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("ASR: \(model.label(for: model.preferences.asrProvider))")
                .lineLimit(1)
            Text("Style: \(model.preferences.style.displayName)")
                .lineLimit(1)
            Text("Accessibility: \(model.accessibilityTrusted ? "Allowed" : "Required")")
                .lineLimit(1)

            Divider()

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open OmniSpeak settings")

            Button("Refresh Status") {
                Task {
                    await model.refreshEngineStatus()
                }
            }
            .help("Check engine, models, microphone, accessibility, and provider status")

            Button("Run Cleanup Test") {
                Task {
                    await model.runCleanupTest()
                }
            }
            .help("Run a quick local cleanup pipeline test")

            Button("Show Test Caption") {
                showTestCaption()
            }
            .help("Preview the closed caption overlay")

            SettingsLink {
                Label("Quick Reference", systemImage: "questionmark.circle")
            }
            .help("Open the quick reference and capabilities guide")

            if !model.accessibilityTrusted {
                Button("Open Accessibility Settings") {
                    requestAccessibilityPermission()
                }
                .help("Open macOS Accessibility permissions for OmniSpeak")
            }

            Divider()

            Button("Cycle Style") {
                model.cycleStyle()
            }
            .help("Switch to the next dictation cleanup style")

            Button("Cycle ASR Provider") {
                model.cycleASRProvider()
            }
            .help("Switch to the next speech recognition provider")

            Divider()

            Button("Open Conversation Mode") {
                openConversationMode()
            }
            .help("Open live conversation recording and conversation history")

            Button("Open Editor") {
                openEditor()
            }
            .help("Open the document editor and subject notes")

            Button("Open Ask AI") {
                openAskAI()
            }
            .help("Open the full Ask AI chat window")

            Button("Open Engine Dashboard") {
                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/")!)
            }
            .help("Open the local engine dashboard in a browser")

            Button("Open Transcript History") {
                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/api/transcripts")!)
            }
            .help("Open raw transcript history from the local engine")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .help("Quit OmniSpeak")
        }
        .padding(8)
        .frame(width: 260, alignment: .leading)
    }
}
