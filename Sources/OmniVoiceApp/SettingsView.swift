import AppKit
import SwiftUI
import OmniVoiceCore

struct SettingsView: View {
    static let preferredWidth: CGFloat = 620

    @Bindable var model: AppModel
    let showTestCaption: () -> Void
    let requestAccessibilityPermission: () -> Void
    let resetAccessibilityPermission: () -> Void
    let refreshPermissions: () -> Void
    let showConversationHistory: () -> Void
    let openConversationMode: () -> Void

    @State private var selectedTab: SettingsTab = .overview
    @State private var selectedCapability: CapabilityInfo?

    private let providerOrder: [ASRProviderKind] = [.parakeetTDT, .canaryQwen25B, .fake]

    var body: some View {
        VStack(spacing: 0) {
            settingsTabStrip
            Divider()
            selectedTabContent
        }
        .frame(width: Self.preferredWidth)
        .frame(minHeight: 620)
        .sheet(item: $selectedCapability) { capability in
            CapabilityDetailSheet(capability: capability, theme: model.activeTheme)
        }
    }

    private var settingsTabStrip: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 20)

                        Text(tab.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 6)
                    .frame(width: tab.tabWidth, height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? Color(themeColor: model.activeTheme.accentColor) : .secondary)
                .background {
                    tabBackground(for: tab)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func tabBackground(for tab: SettingsTab) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if selectedTab == tab {
            shape
                .fill(Color(themeColor: model.activeTheme.accentColor).opacity(0.13))
                .overlay {
                    shape.stroke(Color(themeColor: model.activeTheme.accentColor).opacity(0.35), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .overview:
            tabPage {
                statusSection
                startupPreflightSection
                capabilitiesSection
                testSection
            }
        case .dictation:
            tabPage {
                dictationSection
                hotkeySection
            }
        case .appearance:
            tabPage {
                appearanceSection
                waveformSection
                engineFrameSection
            }
        case .models:
            tabPage {
                modelSection
                customModelSection
            }
        case .translation:
            tabPage {
                translationSection
            }
        case .integrations:
            tabPage {
                integrationsSection
            }
        case .dictionary:
            tabPage {
                dictionarySection
                capabilityCatalogSection
            }
        }
    }

    private func tabPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Engine", value: model.engineState.label)
            LabeledContent("Endpoint", value: model.engineState.detail)
            LabeledContent("Selected Model", value: selectedProviderStatus)
            LabeledContent("Microphone", value: model.microphoneAuthorized ? "Allowed" : "Required")
            LabeledContent("Accessibility", value: model.accessibilityTrusted ? "Allowed" : "Required")
            LabeledContent("Streaming", value: model.streamingDiagnostics.state.displayName)
            LabeledContent("Stream Chunks", value: streamChunkText)
            LabeledContent("Stream Audio", value: byteCount(model.streamingDiagnostics.bytesSent))

            if let lastError = model.streamingDiagnostics.lastError {
                LabeledContent("Stream Error", value: lastError)
            }

            selectedProviderRecoveryCard

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
                    showConversationHistory()
                    Task {
                        await model.refreshTranscripts()
                    }
                }

                Button {
                    openConversationMode()
                } label: {
                    Label("Conversation Mode", systemImage: "bubble.left.and.text.bubble.right")
                }

                Button("Restart Engine") {
                    Task {
                        await model.restartEngine()
                    }
                }
            }

            if !model.accessibilityTrusted {
                Button("Open Accessibility Settings") {
                    requestAccessibilityPermission()
                }

                Button("Reset Accessibility") {
                    resetAccessibilityPermission()
                }
            }
        }
    }

    @ViewBuilder
    private var startupPreflightSection: some View {
        Section("Startup Preflight") {
            if model.startupChecks.isEmpty {
                Text("No startup check has run yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.startupChecks) { check in
                    startupCheckRow(check)
                }
            }

            HStack {
                Button("Refresh Checks") {
                    refreshPermissions()
                    Task {
                        await model.refreshStartupChecks()
                    }
                }

                if startupChecksContainAction(.accessibility) {
                    Button("Fix Accessibility") {
                        requestAccessibilityPermission()
                        Task {
                            await model.refreshStartupChecks()
                        }
                    }

                    Button("Reset Accessibility") {
                        resetAccessibilityPermission()
                        Task {
                            await model.refreshStartupChecks()
                        }
                    }
                }

                if startupChecksContainAction(.microphone) {
                    Button("Fix Microphone") {
                        openMicrophoneSettings()
                        Task {
                            await model.refreshStartupChecks()
                        }
                    }
                }

                if startupChecksContainAction(.engine) {
                    Button("Restart Engine") {
                        Task {
                            await model.restartEngine()
                        }
                    }
                }

                if startupChecksContainAction(.model) {
                    Button("Download Model") {
                        Task {
                            await model.downloadSelectedModel()
                            await model.refreshStartupChecks()
                        }
                    }
                }
            }
        }
    }

    private func startupCheckRow(_ check: StartupCheckItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: startupCheckIcon(for: check.state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(startupCheckColor(for: check.state))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(check.title)
                    .font(.callout.weight(.semibold))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 10)

            Text(check.state.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(startupCheckColor(for: check.state))
        }
        .padding(.vertical, 4)
    }

    private func startupChecksContainAction(_ action: StartupCheckAction) -> Bool {
        model.startupChecks.contains { $0.action == action }
    }

    private func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startupCheckIcon(for state: StartupCheckState) -> String {
        switch state {
        case .checking: "clock"
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func startupCheckColor(for state: StartupCheckState) -> Color {
        switch state {
        case .checking: .secondary
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }

    @ViewBuilder
    private var capabilitiesSection: some View {
        Section("Capabilities") {
            CapabilityOverviewView(theme: model.activeTheme) { capability in
                selectedCapability = capability
            }
        }
    }

    @ViewBuilder
    private var dictationSection: some View {
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

            Toggle("Live type draft into cursor", isOn: liveDraftInsertionEnabledBinding)
        }
    }

    @ViewBuilder
    private var selectedProviderRecoveryCard: some View {
        if let issue = model.selectedProviderIssue {
            VStack(alignment: .leading, spacing: 8) {
                Text(issue.title)
                    .font(.callout.weight(.semibold))
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                providerRecoveryActions
            }
            .padding(10)
            .themeSurface(model.activeTheme, cornerRadius: 8, strong: false)
        }
    }

    @ViewBuilder
    private var providerRecoveryActions: some View {
        HStack {
            Button("Open Models") {
                selectedTab = .models
            }

            Button("Download Model") {
                selectedTab = .models
                Task {
                    await model.downloadSelectedModel()
                }
            }
            .disabled(model.preferences.asrProvider == .fake || isModelActionRunning)

            Button("Use Fake For Testing") {
                model.setASRProvider(.fake)
            }
            .disabled(model.preferences.asrProvider == .fake)
        }
    }

    @ViewBuilder
    private var hotkeySection: some View {
        Section("Hotkeys") {
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
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Theme") {
            Picker("Mode", selection: appearanceModeBinding) {
                ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

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
    }

    @ViewBuilder
    private var waveformSection: some View {
        Section("Waveform") {
            Picker("Waveform", selection: waveformModeBinding) {
                ForEach(WaveformMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
    }

    @ViewBuilder
    private var engineFrameSection: some View {
        Section("Engine Panel") {
            Picker("Side", selection: engineFrameSideBinding) {
                ForEach(EngineFrameSide.allCases, id: \.self) { side in
                    Text(side.displayName).tag(side)
                }
            }
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        Section("Hugging Face Model") {
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

                if model.selectedProviderIssue != nil {
                    providerRecoveryActions
                }
            } else {
                Text("No downloadable model is required for this provider.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var customModelSection: some View {
        Section("External Local Models") {
            TextField("Custom Speech Model", text: customSpeechModelPathBinding)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose Speech Model") {
                    chooseDirectory(title: "Choose Speech Model Folder", onSelect: model.setCustomSpeechModelPath)
                }
                Button("Clear Speech Model") {
                    model.setCustomSpeechModelPath("")
                }
            }

            TextField("Custom Translation Model", text: customTranslationModelPathBinding)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose Translation Model") {
                    chooseDirectory(title: "Choose Translation Model Folder", onSelect: model.setCustomTranslationModelPath)
                }
                Button("Clear Translation Model") {
                    model.setCustomTranslationModelPath("")
                }
            }

            Text("Custom model paths are stored now so the runtime selector can use them when external model execution is wired.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        Section("Live Translation") {
            Toggle("Translate dictated speech", isOn: liveTranslationEnabledBinding)

            TextField("Source Language", text: translationSourceLanguageBinding)
                .textFieldStyle(.roundedBorder)
            TextField("Target Language", text: translationTargetLanguageBinding)
                .textFieldStyle(.roundedBorder)

            LabeledContent("Model", value: model.preferences.customTranslationModelPath.isEmpty ? "Not selected" : model.preferences.customTranslationModelPath)

            Button("Choose Translation Model") {
                chooseDirectory(title: "Choose Translation Model Folder", onSelect: model.setCustomTranslationModelPath)
            }

            Text("Use \"auto\" for source detection. Runtime translation will use the configured local model or AI provider once the translation engine route is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var integrationsSection: some View {
        Section("AI Handoff") {
            TextField("OpenAI-Compatible Base URL", text: openAICompatibleBaseURLBinding)
                .textFieldStyle(.roundedBorder)
            TextField("Model", text: openAICompatibleModelBinding)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: openAICompatibleAPIKeyBinding)
                .textFieldStyle(.roundedBorder)

            LabeledContent("Claude", value: "Ask Claude phrasing enabled")
            LabeledContent("Codex", value: "Hey Codex phrasing enabled")
            LabeledContent("OpenRouter", value: model.preferences.openAICompatibleBaseURL.isEmpty ? "Add endpoint" : "Endpoint configured")
            LabeledContent("Raycast", value: "Scripts available in integrations/raycast")

            HStack {
                Button("Open Raycast Files") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                            .appending(path: "integrations")
                            .appending(path: "raycast")
                    ])
                }

                Button("Open Integration Notes") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                            .appending(path: "docs")
                            .appending(path: "INTEGRATIONS.md")
                    ])
                }
            }
        }

        Section("Voice Patterns") {
            CapabilityMiniRow(title: "Ask Claude", detail: "Say \"Ask Claude\" or \"Hey Claude\" before a prompt, then insert the answer at the cursor.")
            CapabilityMiniRow(title: "Have AI take a look", detail: "Read selected or foreground text, then respond in the requested tone or language.")
            CapabilityMiniRow(title: "Custom API", detail: "Use the OpenAI-compatible endpoint and model configured above.")
        }
    }

    @ViewBuilder
    private var dictionarySection: some View {
        Section("Personal Dictionary") {
            TextEditor(text: dictionaryTermsBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
            Text("Add names, products, acronyms, and terms OmniVoice should preserve. Use one term per line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var capabilityCatalogSection: some View {
        Section("Capabilities And Quick Reference") {
            CapabilityCatalogView(theme: model.activeTheme) { capability in
                selectedCapability = capability
            }
        }
    }

    @ViewBuilder
    private var testSection: some View {
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

    private var appearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { model.preferences.appearanceMode },
            set: { model.setAppearanceMode($0) }
        )
    }

    private var waveformModeBinding: Binding<WaveformMode> {
        Binding(
            get: { model.preferences.waveformMode },
            set: { model.setWaveformMode($0) }
        )
    }

    private var engineFrameSideBinding: Binding<EngineFrameSide> {
        Binding(
            get: { model.preferences.engineFrameSide },
            set: { model.setEngineFrameSide($0) }
        )
    }

    private var customSpeechModelPathBinding: Binding<String> {
        Binding(
            get: { model.preferences.customSpeechModelPath },
            set: { model.setCustomSpeechModelPath($0) }
        )
    }

    private var customTranslationModelPathBinding: Binding<String> {
        Binding(
            get: { model.preferences.customTranslationModelPath },
            set: { model.setCustomTranslationModelPath($0) }
        )
    }

    private var liveTranslationEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.liveTranslationEnabled },
            set: { model.setLiveTranslationEnabled($0) }
        )
    }

    private var liveDraftInsertionEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.liveDraftInsertionEnabled },
            set: { model.setLiveDraftInsertionEnabled($0) }
        )
    }

    private var translationSourceLanguageBinding: Binding<String> {
        Binding(
            get: { model.preferences.translationSourceLanguage },
            set: { model.setTranslationSourceLanguage($0) }
        )
    }

    private var translationTargetLanguageBinding: Binding<String> {
        Binding(
            get: { model.preferences.translationTargetLanguage },
            set: { model.setTranslationTargetLanguage($0) }
        )
    }

    private var openAICompatibleBaseURLBinding: Binding<String> {
        Binding(
            get: { model.preferences.openAICompatibleBaseURL },
            set: { model.setOpenAICompatibleBaseURL($0) }
        )
    }

    private var openAICompatibleModelBinding: Binding<String> {
        Binding(
            get: { model.preferences.openAICompatibleModel },
            set: { model.setOpenAICompatibleModel($0) }
        )
    }

    private var openAICompatibleAPIKeyBinding: Binding<String> {
        Binding(
            get: { model.preferences.openAICompatibleAPIKey },
            set: { model.setOpenAICompatibleAPIKey($0) }
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

    private var streamChunkText: String {
        "\(model.streamingDiagnostics.chunksSent) sent, \(model.streamingDiagnostics.droppedChunks) dropped, \(model.streamingDiagnostics.partialsReceived) partials"
    }

    private func byteCount(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func chooseDirectory(title: String, onSelect: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url.path)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case overview
    case dictation
    case appearance
    case models
    case translation
    case integrations
    case dictionary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .dictation:
            "Dictation"
        case .appearance:
            "Look"
        case .models:
            "Models"
        case .translation:
            "Translate"
        case .integrations:
            "AI"
        case .dictionary:
            "Dictionary"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "gauge.with.dots.needle.bottom.50percent"
        case .dictation:
            "mic"
        case .appearance:
            "sparkles"
        case .models:
            "shippingbox"
        case .translation:
            "globe"
        case .integrations:
            "sparkle.magnifyingglass"
        case .dictionary:
            "text.book.closed"
        }
    }

    var tabWidth: CGFloat {
        switch self {
        case .overview:
            86
        case .dictation:
            84
        case .appearance:
            66
        case .models:
            78
        case .translation:
            86
        case .integrations:
            58
        case .dictionary:
            96
        }
    }
}

private struct CapabilityOverviewView: View {
    let theme: OmniVoiceTheme
    let onSelect: (CapabilityInfo) -> Void

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                capability(.dictation)
                capability(.liveCaptions)
            }
            GridRow {
                capability(.corrections)
                capability(.commandMode)
            }
            GridRow {
                capability(.selectionRewrite)
                capability(.modelControl)
            }
        }
    }

    private func capability(_ capability: CapabilityInfo) -> some View {
        Button {
            onSelect(capability)
        } label: {
            CapabilityCard(capability: capability, theme: theme)
        }
        .buttonStyle(.plain)
    }
}

private struct CapabilityCatalogView: View {
    let theme: OmniVoiceTheme
    let onSelect: (CapabilityInfo) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
            ForEach(CapabilityInfo.allCases) { capability in
                Button {
                    onSelect(capability)
                } label: {
                    CapabilityCard(capability: capability, theme: theme)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CapabilityCard: View {
    let capability: CapabilityInfo
    let theme: OmniVoiceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: capability.systemImage)
                    .foregroundStyle(Color(themeColor: theme.accentColor))
                    .frame(width: 18)
                Text(capability.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(capability.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(10)
        .themeSurface(theme, cornerRadius: 8, strong: false)
    }
}

private struct CapabilityDetailSheet: View {
    let capability: CapabilityInfo
    let theme: OmniVoiceTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: capability.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color(themeColor: theme.accentColor))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(capability.title)
                        .font(.title3.weight(.bold))
                    Text(capability.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(capability.examples, id: \.self) { example in
                    Text(example)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .themeSurface(theme, cornerRadius: 7, strong: false)
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

private struct CapabilityMiniRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}

private enum CapabilityInfo: String, CaseIterable, Identifiable {
    case dictation
    case liveCaptions
    case corrections
    case quotes
    case punctuation
    case commandMode
    case selectionRewrite
    case literalMode
    case personalDictionary
    case modelControl
    case translation
    case aiHandoff
    case conversationHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:
            "Dictation"
        case .liveCaptions:
            "Live Captions"
        case .corrections:
            "Corrections"
        case .quotes:
            "Quotes"
        case .punctuation:
            "Punctuation"
        case .commandMode:
            "Command Mode"
        case .selectionRewrite:
            "Selection Rewrite"
        case .literalMode:
            "Literal Mode"
        case .personalDictionary:
            "Personal Dictionary"
        case .modelControl:
            "Model Control"
        case .translation:
            "Translation"
        case .aiHandoff:
            "AI Handoff"
        case .conversationHistory:
            "Conversation History"
        }
    }

    var summary: String {
        switch self {
        case .dictation:
            "Hold the hotkey, speak, release to insert cleaned text."
        case .liveCaptions:
            "See streaming text while OmniVoice listens."
        case .corrections:
            "Replace mistakes with no-wait, scratch-that, and correction phrasing."
        case .quotes:
            "Speak quote markers and get real quotation marks."
        case .punctuation:
            "Speak punctuation and paragraph controls naturally."
        case .commandMode:
            "Open apps and run safe OmniVoice actions by voice."
        case .selectionRewrite:
            "Select text first, then say how it should be rewritten."
        case .literalMode:
            "Preserve exact words, paths, names, and code-like text."
        case .personalDictionary:
            "Preserve product names, acronyms, and casing."
        case .modelControl:
            "Install, update, and choose local speech models."
        case .translation:
            "Configure source/target language and a local translation model."
        case .aiHandoff:
            "Route spoken prompts to Claude, Codex, OpenRouter, or OpenAI-compatible APIs."
        case .conversationHistory:
            "Review, copy, or insert recent transcripts."
        }
    }

    var systemImage: String {
        switch self {
        case .dictation:
            "mic"
        case .liveCaptions:
            "captions.bubble"
        case .corrections:
            "text.badge.checkmark"
        case .quotes:
            "quote.bubble"
        case .punctuation:
            "textformat"
        case .commandMode:
            "command"
        case .selectionRewrite:
            "selection.pin.in.out"
        case .literalMode:
            "curlybraces"
        case .personalDictionary:
            "text.book.closed"
        case .modelControl:
            "shippingbox"
        case .translation:
            "globe"
        case .aiHandoff:
            "sparkle.magnifyingglass"
        case .conversationHistory:
            "bubble.left.and.text.bubble.right"
        }
    }

    var examples: [String] {
        switch self {
        case .dictation:
            [
                "Hold the dictation hotkey, speak, then release.",
                "The cleaned text lands wherever the cursor was when dictation started.",
            ]
        case .liveCaptions:
            [
                "Watch the caption overlay while speaking to confirm the engine is hearing you.",
                "Drag the caption overlay to choose its normal position.",
            ]
        case .corrections:
            [
                "I'm going to the store. No wait, I'm going to the house.",
                "Scratch that. We should move the meeting to Thursday.",
            ]
        case .quotes:
            [
                "Open quote hello Jane close quote.",
                "Say quote, then the phrase, then close quote.",
            ]
        case .punctuation:
            [
                "New paragraph",
                "Comma, period, question mark, exclamation mark, new line.",
            ]
        case .commandMode:
            [
                "Command, open Safari.",
                "Command, undo last dictation.",
                "Command, show commands.",
            ]
        case .selectionRewrite:
            [
                "Select text, then say: make this shorter.",
                "Select text, then say: rewrite this in Spanish and sound warmer.",
            ]
        case .literalMode:
            [
                "Raw dictation slash users slash michael slash desktop.",
                "Literal mode npm run build colon watch.",
            ]
        case .personalDictionary:
            [
                "Add OmniVoice, MLX, Parakeet TDT, or client names one per line.",
                "Dictionary terms are sent into cleanup so casing and names are preserved.",
            ]
        case .modelControl:
            [
                "Use Models to download Parakeet TDT from Hugging Face.",
                "Set a custom speech model folder when testing an external runtime.",
            ]
        case .translation:
            [
                "Source language: auto. Target language: es.",
                "Choose a local translation model folder before enabling runtime translation.",
            ]
        case .aiHandoff:
            [
                "Ask Claude, write a quick reply to Jane.",
                "Select text, then say: Have OpenRouter take a look at this and respond in Spanish.",
            ]
        case .conversationHistory:
            [
                "Open History, then copy a transcript.",
                "Open History, then Insert a transcript at the current cursor.",
            ]
        }
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
                Text(theme.waveformMode.displayName)
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
