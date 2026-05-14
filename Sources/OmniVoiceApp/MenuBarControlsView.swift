import AppKit
import SwiftUI
import OmniVoiceCore

struct MenuBarControlsView: View {
    @Bindable var model: AppModel
    let showTestCaption: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.statusText)
                .font(.headline)
                .lineLimit(1)

            Text("Engine: \(model.engineState.label)")
                .foregroundStyle(model.engineState == .online ? .primary : .secondary)

            Text("ASR: \(model.label(for: model.preferences.asrProvider))")
                .lineLimit(1)
            Text("Style: \(model.preferences.style.displayName)")
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

            Divider()

            Button("Cycle Style") {
                model.cycleStyle()
            }

            Button("Cycle ASR Provider") {
                model.cycleASRProvider()
            }

            Divider()

            Button("Open Engine Health") {
                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/health")!)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 260, alignment: .leading)
    }
}
