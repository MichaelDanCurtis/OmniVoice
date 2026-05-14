import AppKit
import SwiftUI
import OmniVoiceCore

@main
struct OmniVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("OmniVoice", systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.statusText)
                    .font(.headline)

                Divider()

                Text("ASR: \(model.preferences.asrProvider.rawValue)")
                Text("Style: \(model.preferences.style.displayName)")

                Button("Cycle Style") {
                    model.cycleStyle()
                }

                Button("Cycle ASR Provider") {
                    model.cycleASRProvider()
                }

                Divider()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
            .task {
                appDelegate.attach(model: model)
            }
        }
    }
}
