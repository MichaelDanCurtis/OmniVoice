import AppKit
import SwiftUI
import OmniVoiceCore

struct MenuBarControlsView: View {
    @Bindable var model: AppModel
    let showTestCaption: () -> Void
    let requestAccessibilityPermission: () -> Void

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

            Button("Refresh Status") {
                Task {
                    await model.refreshEngineStatus()
                }
            }

            Button("Run Cleanup Test") {
                Task {
                    await model.runCleanupTest()
                }
            }

            Button("Show Test Caption") {
                showTestCaption()
            }

            SettingsLink {
                Label("Quick Reference", systemImage: "questionmark.circle")
            }

            if !model.accessibilityTrusted {
                Button("Open Accessibility Settings") {
                    requestAccessibilityPermission()
                }
            }

            Divider()

            Button("Cycle Style") {
                model.cycleStyle()
            }

            Button("Cycle ASR Provider") {
                model.cycleASRProvider()
            }

            Divider()

            Button("Open Engine Dashboard") {
                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/")!)
            }

            Button("Open Transcript History") {
                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/api/transcripts")!)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 260, alignment: .leading)
    }
}
