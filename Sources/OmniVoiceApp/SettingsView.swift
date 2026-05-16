import AppKit
import SwiftUI
import OmniVoiceCore

struct SettingsView: View {
    @Bindable var model: AppModel
    let showTestCaption: () -> Void
    let requestAccessibilityPermission: () -> Void
    let refreshPermissions: () -> Void

    private let providerOrder: [ASRProviderKind] = [.parakeetTDT, .canaryQwen25B, .fake]

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Engine", value: model.engineState.label)
                LabeledContent("Endpoint", value: model.engineState.detail)
                LabeledContent("Selected Model", value: selectedProviderStatus)
                LabeledContent("Microphone", value: model.microphoneAuthorized ? "Allowed" : "Required")
                LabeledContent("Accessibility", value: model.accessibilityTrusted ? "Allowed" : "Required")

                HStack {
                    Button("Refresh") {
                        refreshPermissions()
                        Task {
                            await model.refreshEngineStatus()
                        }
                    }

                    Button("Open Dashboard") {
                        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/")!)
                    }

                    Button("Open History") {
                        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/api/transcripts")!)
                    }
                }

                if !model.accessibilityTrusted {
                    Button("Open Accessibility Settings") {
                        requestAccessibilityPermission()
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: themeIDBinding) {
                    ForEach(OmniVoiceTheme.builtIn, id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                    Text("Custom").tag(OmniVoiceThemeID.custom)
                }

                ColorPicker(
                    "Custom Accent",
                    selection: Binding(
                        get: { Color(themeColor: model.preferences.customAccentColor) },
                        set: { model.setCustomAccentColor(ThemeColor(color: $0)) }
                    )
                )

                ThemePreview(theme: model.activeTheme)
            }

            Section("Waveform And Motion") {
                Picker("Waveform", selection: waveformModeBinding) {
                    ForEach(WaveformMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Commit Animation", selection: commitAnimationModeBinding) {
                    ForEach(CommitAnimationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Engine Frame") {
                Picker("Side", selection: engineFrameSideBinding) {
                    ForEach(EngineFrameSide.allCases, id: \.self) { side in
                        Text(side.displayName).tag(side)
                    }
                }
            }

            Section("Dictation") {
                Picker("ASR Provider", selection: providerBinding) {
                    ForEach(providerOrder, id: \.self) { provider in
                        Text(model.label(for: provider)).tag(provider)
                    }
                }

                Picker("Microphone", selection: microphoneBinding) {
                    Text("System Default").tag(String?.none)
                    ForEach(model.microphoneDevices) { device in
                        Text(device.displayName).tag(Optional(device.id))
                    }
                    if let selected = model.preferences.microphoneID,
                       !model.microphoneDevices.contains(where: { $0.id == selected }) {
                        Text("Missing: \(selected)").tag(Optional(selected))
                    }
                }

                Button("Refresh Microphones") {
                    model.refreshMicrophones()
                }

                Picker("Cleanup Style", selection: styleBinding) {
                    ForEach(StyleProfile.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                HotkeyRecorderView(
                    title: "Dictation Hotkey",
                    binding: model.preferences.dictationHotkey,
                    theme: model.activeTheme,
                    onChange: model.setDictationHotkey
                )

                HotkeyRecorderView(
                    title: "Style Hotkey",
                    binding: model.preferences.styleHotkey,
                    theme: model.activeTheme,
                    onChange: model.setStyleHotkey
                )
            }

            Section("Model") {
                if let modelStatus = selectedModelStatus {
                    LabeledContent("Hugging Face", value: modelStatus.repoID)
                    LabeledContent("Local Path", value: modelStatus.localPath)
                    LabeledContent("Installed", value: modelStatus.installed ? "Yes" : "No")
                    LabeledContent("Revision", value: modelStatus.installedRevision?.prefix(12).description ?? "Not installed")
                    LabeledContent("Update", value: selectedModelUpdateText)

                    HStack {
                        Button("Check Update") {
                            Task {
                                await model.checkSelectedModelUpdate()
                            }
                        }
                        .disabled(isModelActionRunning)

                        Button(modelDownloadButtonTitle) {
                            Task {
                                await model.downloadSelectedModel()
                            }
                        }
                        .disabled(isModelActionRunning)
                    }

                    if let message = selectedModelMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("No downloadable model is required for this provider.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Personal Dictionary") {
                TextEditor(text: dictionaryTermsBinding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 92)
                Text("Add names, products, acronyms, and terms OmniVoice should preserve. Use one term per line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Quick Reference") {
                QuickReferenceView()
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

    private var microphoneBinding: Binding<String?> {
        Binding(
            get: { model.preferences.microphoneID },
            set: { model.setMicrophoneID($0) }
        )
    }

    private var dictionaryTermsBinding: Binding<String> {
        Binding(
            get: { model.preferences.dictionaryTerms.joined(separator: "\n") },
            set: { model.setDictionaryTermsText($0) }
        )
    }

    private var themeIDBinding: Binding<OmniVoiceThemeID> {
        Binding(
            get: { model.preferences.themeID },
            set: { model.setThemeID($0) }
        )
    }

    private var waveformModeBinding: Binding<WaveformMode> {
        Binding(
            get: { model.preferences.waveformMode },
            set: { model.setWaveformMode($0) }
        )
    }

    private var commitAnimationModeBinding: Binding<CommitAnimationMode> {
        Binding(
            get: { model.preferences.commitAnimationMode },
            set: { model.setCommitAnimationMode($0) }
        )
    }

    private var engineFrameSideBinding: Binding<EngineFrameSide> {
        Binding(
            get: { model.preferences.engineFrameSide },
            set: { model.setEngineFrameSide($0) }
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

    private var selectedModelStatus: EngineModelStatus? {
        model.modelStatus(for: model.preferences.asrProvider)
    }

    private var selectedModelUpdateText: String {
        guard let update = model.modelUpdateInfo,
              update.providerID == model.preferences.asrProvider.rawValue else {
            return "Not checked"
        }

        return update.updateAvailable ? "Available" : "Current"
    }

    private var selectedModelMessage: String? {
        if let download = model.modelDownloadStatus,
           download.providerID == model.preferences.asrProvider.rawValue {
            return download.message ?? download.state
        }

        guard let status = selectedModelStatus, !status.missingFiles.isEmpty else {
            return nil
        }

        return "Missing: \(status.missingFiles.joined(separator: ", "))"
    }

    private var modelDownloadButtonTitle: String {
        guard let status = selectedModelStatus else { return "Download" }
        return status.installed ? "Update Model" : "Download Model"
    }

    private var isModelActionRunning: Bool {
        guard let download = model.modelDownloadStatus,
              download.providerID == model.preferences.asrProvider.rawValue else {
            return false
        }
        return download.state == "queued" || download.state == "downloading"
    }
}

private struct ThemePreview: View {
    let theme: OmniVoiceTheme

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(themeColor: theme.accentColor))
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .stroke(Color(themeColor: theme.secondaryAccentColor).opacity(0.75), lineWidth: 2)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.name)
                    .font(.headline)
                Text("\(theme.waveformMode.displayName) / \(theme.commitAnimationMode.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .themeSurface(theme, cornerRadius: 8, strong: true)
    }
}
