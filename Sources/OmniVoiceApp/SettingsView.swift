import AppKit
import SwiftUI
import OmniVoiceCore

struct SettingsView: View {
    @Bindable var model: AppModel
    let showTestCaption: () -> Void

    private let providerOrder: [ASRProviderKind] = [.parakeetTDT, .canaryQwen25B, .fake]

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Engine", value: model.engineState.label)
                LabeledContent("Endpoint", value: model.engineState.detail)
                LabeledContent("Selected Model", value: selectedProviderStatus)

                HStack {
                    Button("Refresh") {
                        Task {
                            await model.refreshEngineStatus()
                        }
                    }

                    Button("Open Providers") {
                        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/providers")!)
                    }
                }
            }

            Section("Dictation") {
                Picker("ASR Provider", selection: providerBinding) {
                    ForEach(providerOrder, id: \.self) { provider in
                        Text(model.label(for: provider)).tag(provider)
                    }
                }

                Picker("Cleanup Style", selection: styleBinding) {
                    ForEach(StyleProfile.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                LabeledContent("Dictation Hotkey", value: model.preferences.dictationHotkey.displayName)
                LabeledContent("Style Hotkey", value: model.preferences.styleHotkey.displayName)
            }

            Section("Test") {
                HStack {
                    Button("Run Cleanup Test") {
                        Task {
                            await model.runCleanupTest()
                        }
                    }

                    Button("Show Caption") {
                        showTestCaption()
                    }
                }

                Text(model.lastTestResult)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }

    private var providerBinding: Binding<ASRProviderKind> {
        Binding(
            get: { model.preferences.asrProvider },
            set: { model.setASRProvider($0) }
        )
    }

    private var styleBinding: Binding<StyleProfile> {
        Binding(
            get: { model.preferences.style },
            set: { model.setStyle($0) }
        )
    }

    private var selectedProviderStatus: String {
        guard let provider = model.providerInfo(for: model.preferences.asrProvider) else {
            return "Not checked"
        }

        if provider.available {
            return "Available"
        }

        return provider.reason ?? "Unavailable"
    }
}
