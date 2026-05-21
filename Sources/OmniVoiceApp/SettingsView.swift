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
    let openEditor: () -> Void
    let openAskAI: () -> Void

    @State private var selectedTab: SettingsTab = .overview
    @State private var selectedCapability: CapabilityInfo?
    @State private var hotMenuAdvancedExpanded = false
    @State private var confirmClearConversations = false
    @State private var confirmClearAIThreads = false
    @Namespace private var settingsTabNamespace
    @Environment(\.colorScheme) private var colorScheme

    private let providerOrder = ASRProviderKind.userSelectableCases

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
        .alert("Clear conversation database?", isPresented: $confirmClearConversations) {
            Button("Clear Conversations", role: .destructive) {
                Task { await model.clearConversationDatabase() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved conversations from the local engine database. Archived transcript files stay on disk.")
        }
        .alert("Clear AI threads?", isPresented: $confirmClearAIThreads) {
            Button("Clear AI Threads", role: .destructive) {
                model.clearAskAIThreads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Ask AI chat threads and attachments. Editor documents and notes are not changed.")
        }
        .themeWindowBackground(model.activeTheme)
    }

    private var settingsTabStrip: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 7) {
                    settingsTabButtons
                }
            } else {
                settingsTabButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(.snappy(duration: 0.28), value: selectedTab)
    }

    private var settingsTabButtons: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: selectedTab == tab ? 24 : 22, weight: .semibold))
                            .frame(width: 50, height: 30)
                            .scaleEffect(selectedTab == tab ? 1.04 : 1.0)

                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 4)
                    .frame(minWidth: tab.minimumTabWidth, maxWidth: .infinity, minHeight: 58)
                    .background {
                        selectedTabBackground(for: tab)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? Color(themeColor: activePalette.accentText) : .secondary)
                .liquidGlassMotion(model.activeTheme, strong: selectedTab == tab)
                .help(tab.title)
            }
        }
    }

    private var activePalette: ResolvedThemePalette {
        model.activeTheme.resolvedPalette(for: colorScheme)
    }

    @ViewBuilder
    private func selectedTabBackground(for tab: SettingsTab) -> some View {
        if selectedTab == tab {
            if #available(macOS 26.0, *) {
                SettingsTabLiquidBlob(theme: model.activeTheme)
                    .frame(width: tab.minimumTabWidth + 16, height: 54)
                    .glassEffectID("settings-selected-tab", in: settingsTabNamespace)
                    .matchedGeometryEffect(id: "settings-selected-tab", in: settingsTabNamespace)
            } else {
                SettingsTabLiquidBlob(theme: model.activeTheme)
                    .frame(width: tab.minimumTabWidth + 16, height: 54)
                    .matchedGeometryEffect(id: "settings-selected-tab", in: settingsTabNamespace)
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .overview:
            tabPage {
                firstRunSetupSection
                statusSection
                startupPreflightSection
                storageSection
                testSection
            }
        case .dictation:
            tabPage {
                dictationSection
                dictionarySection
            }
        case .appearance:
            tabPage {
                appearanceSection
                hotkeySection
                waveformSection
                engineFrameSection
            }
        case .models:
            tabPage {
                modelSection
                diarizationModelSection
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
        case .help:
            tabPage {
                quickReferenceSection
            }
        }
    }

    private func tabPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var firstRunSetupSection: some View {
        if !model.preferences.firstRunSetupCompleted {
            Section("First Run Setup") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OmniVoice needs permissions and the local MLX speech model before dictation feels instant.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    setupChecklistRow(
                        title: "Microphone",
                        detail: model.microphoneAuthorized
                            ? "Allowed"
                            : "Allow microphone capture so OmniVoice can hear dictation.",
                        state: model.microphoneAuthorized ? .passed : .failed
                    )

                    setupChecklistRow(
                        title: "Accessibility",
                        detail: model.accessibilityTrusted
                            ? "Allowed"
                            : "Allow Accessibility so OmniVoice can insert text at the cursor.",
                        state: model.accessibilityTrusted ? .passed : .failed
                    )

                    setupChecklistRow(
                        title: "Speech Model",
                        detail: firstRunSpeechModelDetail,
                        state: firstRunSpeechModelState
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Refresh Checks") {
                                refreshPermissions()
                                Task {
                                    await model.refreshEngineStatus()
                                    await model.refreshStartupChecks()
                                }
                            }

                            if !model.microphoneAuthorized {
                                Button("Fix Microphone") {
                                    openMicrophoneSettings()
                                }
                            }

                            if !model.accessibilityTrusted {
                                Button("Fix Accessibility") {
                                    requestAccessibilityPermission()
                                }
                            }
                        }

                        HStack {
                            Button(modelDownloadButtonTitle) {
                                selectedTab = .models
                                Task {
                                    await model.downloadSelectedModel()
                                    await model.refreshStartupChecks()
                                }
                            }
                            .disabled(isModelActionRunning || selectedModelStatus == nil)

                            Button("Show Caption") {
                                showTestCaption()
                            }

                            Button("Finish Setup") {
                                model.completeFirstRunSetup()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
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

            VStack(alignment: .leading, spacing: 8) {
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

                    Button("Restart Engine") {
                        Task {
                            await model.restartEngine()
                        }
                    }
                }

                HStack {
                    Button {
                        openConversationMode()
                    } label: {
                        Label("Conversation Mode", systemImage: "bubble.left.and.text.bubble.right")
                    }

                    Button {
                        openEditor()
                    } label: {
                        Label("Editor & Notes", systemImage: "doc.richtext")
                    }

                    Button {
                        openAskAI()
                    } label: {
                        Label("Ask AI", systemImage: "sparkles")
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

                if startupChecksContainAction(.diarizationModel) {
                    Button("Download Diarization") {
                        selectedTab = .models
                        Task {
                            await model.downloadSelectedDiarizationModel()
                            await model.refreshStartupChecks()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section("Storage") {
            Toggle("Archive Conversations", isOn: automaticallyArchiveConversationsBinding)

            LabeledContent("Folder", value: model.conversationArchiveRootURL.path)

            HStack {
                Button("Choose Folder") {
                    chooseDirectory(title: "Choose OmniVoice Archive Folder", onSelect: model.setConversationArchiveFolderPath)
                }

                Button("Use Documents") {
                    model.setConversationArchiveFolderPath(ConversationArchive.defaultRootURL().path)
                }

                Button("Reveal") {
                    try? FileManager.default.createDirectory(
                        at: model.conversationArchiveRootURL,
                        withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.activateFileViewerSelecting([model.conversationArchiveRootURL])
                }

                Button("Sync Archive") {
                    Task { await model.syncConversationArchiveToDatabase() }
                }
                .help("Import archived conversation JSON files into the local engine database.")
            }

            HStack {
                Button("Clear Conversations", role: .destructive) {
                    confirmClearConversations = true
                }
                .disabled(model.isConversationRecording)
                .help("Remove saved conversations from the local engine database while leaving archive files on disk.")

                Button("Clear AI Threads", role: .destructive) {
                    confirmClearAIThreads = true
                }
                .disabled(model.askAIThreads.isEmpty)
                .help("Remove Ask AI chat threads without deleting editor documents or notes.")
            }

            Text("Conversation transcripts are mirrored here as Markdown and JSON. OmniVoice keeps its internal engine database in Application Support.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startupCheckRow(_ check: StartupCheckItem) -> some View {
        setupChecklistRow(title: check.title, detail: check.detail, state: check.state)
    }

    private func setupChecklistRow(
        title: String,
        detail: String,
        state: StartupCheckState
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: startupCheckIcon(for: state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(startupCheckColor(for: state))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 10)

            Text(state.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(startupCheckColor(for: state))
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
            Text("Streams draft text into plain native text fields while listening. Rich composers still commit the cleaned text on release.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .disabled(isModelActionRunning || selectedModelStatus == nil)
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

            HotkeyRecorderView(
                title: "Hot Menu",
                binding: model.preferences.hotMenuHotkey,
                theme: model.activeTheme,
                advancedTitle: "Advanced",
                advancedSystemImage: hotMenuAdvancedExpanded ? "chevron.up" : "slider.horizontal.3",
                onAdvanced: {
                    withAnimation(.snappy(duration: 0.18)) {
                        hotMenuAdvancedExpanded.toggle()
                    }
                },
                onChange: model.setHotMenuHotkey
            )

            if hotMenuAdvancedExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hot Menu Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        hotMenuActionRow(.up)
                        hotMenuActionRow(.left)
                        hotMenuActionRow(.right)
                        hotMenuActionRow(.down)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .themeSurface(model.activeTheme, cornerRadius: 8, strong: false)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func hotMenuActionRow(_ direction: HotMenuDirection) -> some View {
        GridRow {
            Label(direction.displayName, systemImage: direction.systemImage)
                .frame(minWidth: 72, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(0..<HotMenuAction.visibleSlotCount, id: \.self) { slot in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(slot + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)

                        Picker(
                            "\(direction.displayName) Slot \(slot + 1)",
                            selection: hotMenuActionBinding(for: direction, slot: slot)
                        ) {
                            ForEach(HotMenuAction.configurationCases, id: \.self) { action in
                                Text(action.displayName).tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 122)
                    }
                }
            }
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
        Section("Speech Model") {
            Picker("ASR Provider", selection: providerBinding) {
                ForEach(providerOrder, id: \.self) { provider in
                    Text(model.label(for: provider)).tag(provider)
                }
            }

            if let info = model.providerInfo(for: model.preferences.asrProvider) {
                LabeledContent("Runtime", value: info.available ? "Available" : (info.reason ?? "Unavailable"))
            }

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
    private var diarizationModelSection: some View {
        Section("Conversation Diarization") {
            Toggle("Speaker Diarization", isOn: conversationDiarizationEnabledBinding)

            Picker("Precision", selection: conversationDiarizationPrecisionBinding) {
                ForEach(DiarizationPrecision.allCases, id: \.self) { precision in
                    Text("\(precision.displayName) - \(precision.detail)").tag(precision)
                }
            }
            .disabled(!model.conversationDiarizationEnabled)

            LabeledContent("Session Provider", value: conversationDiarizationRuntimeText)

            if let info = selectedDiarizationProviderInfo {
                LabeledContent("Runtime", value: info.available ? "Available" : (info.reason ?? "Unavailable"))
            }

            if let modelStatus = selectedDiarizationModelStatus {
                LabeledContent("Hugging Face", value: modelStatus.repoID)
                LabeledContent("Local Path", value: modelStatus.localPath)
                LabeledContent("Installed", value: modelStatus.installed ? "Yes" : "No")
                LabeledContent("Revision", value: modelStatus.installedRevision?.prefix(12).description ?? "Not installed")
                LabeledContent("Update", value: selectedDiarizationModelUpdateText)

                HStack {
                    Button("Check Update") {
                        Task {
                            await model.checkSelectedDiarizationModelUpdate()
                        }
                    }
                    .disabled(isDiarizationModelActionRunning)

                    Button(diarizationModelDownloadButtonTitle) {
                        Task {
                            model.setConversationDiarizationEnabled(true)
                            await model.downloadSelectedDiarizationModel()
                        }
                    }
                    .disabled(isDiarizationModelActionRunning)
                }

                if let message = selectedDiarizationModelMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let issue = model.selectedDiarizationProviderIssue {
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.title)
                        .font(.callout.weight(.semibold))
                    Text(issue.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .themeSurface(model.activeTheme, cornerRadius: 8, strong: false)
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

            TextField("Custom Translation Model Folder", text: customTranslationModelPathBinding)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose Local Translation Folder") {
                    chooseDirectory(title: "Choose Translation Model Folder", onSelect: model.setCustomTranslationModelPath)
                }
                Button("Clear Translation Model") {
                    model.setCustomTranslationModelPath("")
                }
            }

            Text("Custom model paths override managed downloads when you want OmniVoice to use a manually installed model folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        Section("Live Translation") {
            Toggle("Translate dictated speech", isOn: liveTranslationEnabledBinding)

            Picker("Provider", selection: translationProviderBinding) {
                ForEach(TranslationProviderKind.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            if let info = selectedTranslationProviderInfo {
                LabeledContent("Runtime", value: info.available ? "Available" : (info.reason ?? "Unavailable"))
            }

            Picker("Model", selection: translationModelProviderIDBinding) {
                ForEach(TranslationModelRecommendation.allCases) { recommendation in
                    Text(model.modelStatus(forProviderID: recommendation.providerID)?.label ?? recommendation.displayName)
                        .tag(recommendation.providerID)
                }
            }

            if let translationModelStatus = selectedTranslationModelStatus {
                LabeledContent("Repository", value: translationModelStatus.repoID)
                if let recommendation = translationModelStatus.recommendation {
                    LabeledContent("Best For", value: recommendation)
                }
                if let size = translationModelStatus.size {
                    LabeledContent("Download", value: size)
                }
                if let precision = translationModelStatus.precision {
                    LabeledContent("Precision", value: precision)
                }
                LabeledContent("Installed", value: translationModelStatus.installed ? "Yes" : "No")
                LabeledContent("Local Path", value: translationModelStatus.localPath)
                LabeledContent("Update", value: selectedTranslationModelUpdateText)

                if let message = selectedTranslationModelMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Open Agreement") {
                        model.openSelectedTranslationModelAgreement()
                    }
                    Button("HF Tokens") {
                        model.openHuggingFaceTokenSettings()
                    }
                    Button("Check Update") {
                        Task {
                            await model.checkSelectedTranslationModelUpdate()
                        }
                    }
                    Button(translationModelDownloadButtonTitle) {
                        Task {
                            await model.downloadSelectedTranslationModel()
                        }
                    }
                    .disabled(isTranslationModelActionRunning)
                }

                Text("TranslateGemma MLX uses the Gemma license on Hugging Face. Before the first download, sign in, accept the model agreement, then paste a Hugging Face token here or authenticate with huggingface-cli login / HF_TOKEN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            SecureField("Hugging Face Token", text: $model.huggingFaceTokenDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Load Saved Token") {
                    model.loadHuggingFaceTokenFromKeychain()
                }
                Button("Save Token") {
                    model.saveHuggingFaceTokenToKeychain()
                }
                Button("Validate Access") {
                    Task {
                        await model.validateHuggingFaceAccess()
                    }
                }
                Button("Clear") {
                    model.clearHuggingFaceToken()
                }
            }

            if let status = model.huggingFaceAuthStatus {
                LabeledContent("Hugging Face", value: statusSummary(status))
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Picker("Spoken Language", selection: translationSourceLanguageBinding) {
                ForEach(model.translationSourceLanguageOptions) { language in
                    Text(model.translationLanguageLabel(for: language.code, in: model.translationSourceLanguageOptions))
                        .tag(language.code)
                }
            }
            .disabled(model.translationCapabilities?.sourceLanguageLocked ?? true)

            if let reason = model.translationCapabilities?.sourceLanguageReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Picker("Translate To", selection: translationTargetLanguageBinding) {
                ForEach(model.translationTargetLanguageOptions) { language in
                    Text(model.translationLanguageLabel(for: language.code, in: model.translationTargetLanguageOptions))
                        .tag(language.code)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Hot Menu Languages")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(0..<OmniVoicePreferences.translationQuickTargetLanguageSlotCount, id: \.self) { slot in
                        GridRow {
                            Text("\(slot + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .leading)

                            Picker("Hot Language \(slot + 1)", selection: translationQuickTargetLanguageBinding(slot: slot)) {
                                Text("Not used").tag("")
                                ForEach(model.translationTargetLanguageOptions) { language in
                                    Text(model.translationLanguageLabel(for: language.code, in: model.translationTargetLanguageOptions))
                                        .tag(language.code)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 260)
                        }
                    }
                }

                Text("Assign Translation Language in the hot menu, then tap that orb or arrow repeatedly to cycle targets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .themeSurface(model.activeTheme, cornerRadius: 8, strong: false)

            if let capabilities = model.translationCapabilities {
                LabeledContent("Language Source", value: capabilities.capabilitySource)
                if let message = capabilities.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            DisclosureGroup("Advanced local override") {
                LabeledContent("Override Folder", value: model.preferences.customTranslationModelPath.isEmpty ? "Using managed download" : model.preferences.customTranslationModelPath)
                HStack {
                    Button("Choose Local Folder") {
                        chooseDirectory(title: "Choose Translation Model Folder", onSelect: model.setCustomTranslationModelPath)
                    }
                    Button("Clear Override") {
                        model.setCustomTranslationModelPath("")
                    }
                }
                Text("Use this only for a manually installed MLX model. Managed downloads use the selected recommendation above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Test Translation") {
                    Task {
                        await model.runTranslationTest()
                    }
                }

                Button("Validate Languages") {
                    Task {
                        await model.runTranslationLanguageValidation()
                    }
                }

                Button("Refresh Providers") {
                    Task {
                        await model.refreshProviderAndModelStatus()
                    }
                }
            }

            Text(model.lastTestResult)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("Target languages come from the selected model's engine capability metadata. Current live speech translation uses English spoken input.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var integrationsSection: some View {
        Section("Text LLM Providers") {
            if visibleTextLLMProviders.isEmpty {
                Text("No AI providers added yet. Add the provider you want to configure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Default Ask AI Provider", selection: textLLMDefaultProviderBinding) {
                    ForEach(visibleTextLLMProviders) { provider in
                        Text(model.preferences.textLLMConfiguration(for: provider).displayName).tag(provider)
                    }
                }
            }

            HStack {
                Text("Named commands use their matching provider. Generic \"Ask AI\" uses the default above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !addableTextLLMProviders.isEmpty {
                    Menu {
                        ForEach(addableTextLLMProviders) { provider in
                            Button {
                                model.addTextLLMProvider(provider)
                            } label: {
                                Label(addProviderLabel(for: provider), systemImage: provider.systemImage)
                            }
                        }
                    } label: {
                        Label("Add Provider", systemImage: "plus.circle")
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(visibleTextLLMProviders) { provider in
                    textLLMProviderCard(provider)
                }
            }

            Text(model.lastTestResult)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        Section("Integration Files") {
            HStack {
                Button("Open Raycast Folder") {
                    openProjectResource("integrations/raycast")
                }

                Button("Open Integration Notes") {
                    openProjectResource("docs/INTEGRATIONS.md")
                }
            }
        }

        Section("MCP Servers") {
            Text("Add local MCP server launch settings here. These are stored in OmniVoice preferences so AI actions can use them when the MCP runtime adapter is connected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                model.addMCPServer()
            } label: {
                Label("Add MCP Server", systemImage: "plus.circle")
            }

            ForEach(model.preferences.mcpServers) { server in
                mcpServerCard(server)
            }
        }

        Section("Voice Patterns") {
            CapabilityMiniRow(title: "Ask Claude", detail: "Say \"Ask Claude\" or \"Hey Claude\" before a prompt, then insert the answer at the cursor.")
            CapabilityMiniRow(title: "Have AI take a look", detail: "Read selected or foreground text, then respond in the requested tone or language.")
            CapabilityMiniRow(title: "Custom API", detail: "Say \"Ask AI\" to use the default text LLM provider configured above.")
        }
    }

    private var visibleTextLLMProviders: [TextLLMProviderKind] {
        TextLLMProviderKind.allCases.filter { provider in
            model.preferences.textLLMConfiguration(for: provider).isVisibleInSettings
        }
    }

    private var addableTextLLMProviders: [TextLLMProviderKind] {
        TextLLMProviderKind.allCases.filter { provider in
            !visibleTextLLMProviders.contains(provider)
        }
    }

    private func addProviderLabel(for provider: TextLLMProviderKind) -> String {
        provider == TextLLMProviderKind.custom ? "Custom OpenAI-Compatible API" : provider.displayName
    }

    @ViewBuilder
    private func textLLMProviderCard(_ provider: TextLLMProviderKind) -> some View {
        let configuration = model.preferences.textLLMConfiguration(for: provider)
        let modelOptions = model.textLLMModelOptions[provider] ?? []
        let discoveryStatus = model.textLLMModelDiscoveryStatus[provider]
        let authStatus = model.textLLMOAuthStatus[provider]

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Label(configuration.displayName, systemImage: provider.systemImage)
                    .font(.headline)

                Spacer()

                Button(role: .destructive) {
                    model.removeTextLLMProvider(provider)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Remove provider")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Connection")
                        .foregroundStyle(.secondary)

                    Text(provider.defaultTransport.displayName)
                        .foregroundStyle(.primary)
                }

                if provider == .custom {
                    GridRow {
                        Text("Name")
                            .foregroundStyle(.secondary)

                        TextField("Custom provider name", text: textLLMCustomNameBinding(provider))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if provider != .githubCopilot {
                    GridRow {
                        Text("Base URL")
                            .foregroundStyle(.secondary)

                        TextField(provider.defaultBaseURL.isEmpty ? "https://host/v1" : provider.defaultBaseURL, text: textLLMBaseURLBinding(provider))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                GridRow {
                    Text("Model")
                        .foregroundStyle(.secondary)

                    if modelOptions.isEmpty {
                        TextField("Refresh models to populate", text: textLLMModelBinding(provider))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Model", selection: textLLMModelBinding(provider)) {
                            Text("Select Model").tag("")
                            ForEach(modelOptions, id: \.self) { modelID in
                                Text(modelID).tag(modelID)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }
                }

                if provider.requiresOAuth {
                    GridRow {
                        Text("Access Token")
                            .foregroundStyle(.secondary)

                        SecureField(provider == .codex ? "Codex user auth token" : "GitHub device auth token", text: textLLMOAuthAccessTokenBinding(provider))
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    GridRow {
                        Text("API Key")
                            .foregroundStyle(.secondary)

                        SecureField("Stored locally in OmniVoice preferences", text: textLLMAPIKeyBinding(provider))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .disabled(!configuration.enabled)

            if configuration.transport == .openAICompatible {
                textLLMHeadersEditor(provider)
                    .disabled(!configuration.enabled)
            }

            if provider == .githubCopilot {
                DisclosureGroup("Advanced OAuth App") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Sync uses OmniVoice's built-in GitHub Copilot device client. Override this only for development or a registered OmniVoice OAuth app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Optional OAuth client override", text: textLLMOAuthClientIDBinding(provider))
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 4)
                }
                .disabled(!configuration.enabled)
            }

            HStack {
                Spacer()

                if provider.requiresOAuth {
                    Button(provider == .githubCopilot ? "Device Sync" : "Authorize") {
                        Task {
                            await model.authorizeTextLLMProvider(provider)
                        }
                    }
                }

                Button("Refresh Models") {
                    Task {
                        await model.refreshTextLLMModels(provider)
                    }
                }

                Button("Test") {
                    Task {
                        await model.testTextLLMProvider(provider)
                    }
                }
                .disabled(!configuration.isConfigured)
            }

            if let discoveryStatus {
                Text(discoveryStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let authStatus {
                Text(authStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .themeSurface(model.activeTheme, cornerRadius: 8, strong: false, interactive: false)
    }

    @ViewBuilder
    private func textLLMHeadersEditor(_ provider: TextLLMProviderKind) -> some View {
        let headers = model.preferences.textLLMConfiguration(for: provider).headers

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Headers")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    addTextLLMHeader(provider)
                } label: {
                    Label("Add Header", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if headers.isEmpty {
                Text("Optional request headers for OpenAI-compatible providers such as Kimi, OpenRouter, or local gateways.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(headers) { header in
                    HStack(spacing: 8) {
                        Toggle("", isOn: textLLMHeaderEnabledBinding(provider, headerID: header.id))
                            .labelsHidden()
                            .frame(width: 22)

                        TextField("Header", text: textLLMHeaderNameBinding(provider, headerID: header.id))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120)

                        SecureField("Value", text: textLLMHeaderValueBinding(provider, headerID: header.id))
                            .textFieldStyle(.roundedBorder)

                        Button {
                            removeTextLLMHeader(provider, headerID: header.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mcpServerCard(_ server: MCPServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(server.displayName, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)

                Spacer()

                Toggle("Enabled", isOn: mcpServerEnabledBinding(server.id))
                    .toggleStyle(.switch)

                Button {
                    model.removeMCPServer(id: server.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                        .foregroundStyle(.secondary)

                    TextField("Obsidian Notes", text: mcpServerNameBinding(server.id))
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Command")
                        .foregroundStyle(.secondary)

                    TextField("npx", text: mcpServerCommandBinding(server.id))
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Arguments")
                        .foregroundStyle(.secondary)

                    TextField("-y @modelcontextprotocol/server-filesystem ~/Documents", text: mcpServerArgumentsBinding(server.id))
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Text("Environment")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    addMCPEnvironmentVariable(server.id)
                } label: {
                    Label("Add Env", systemImage: "plus")
                }
                .controlSize(.small)
            }

            ForEach(server.environment) { variable in
                HStack(spacing: 8) {
                    TextField("NAME", text: mcpEnvironmentNameBinding(server.id, variableID: variable.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 120)

                    SecureField("Value", text: mcpEnvironmentValueBinding(server.id, variableID: variable.id))
                        .textFieldStyle(.roundedBorder)

                    Button {
                        removeMCPEnvironmentVariable(server.id, variableID: variable.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .themeSurface(model.activeTheme, cornerRadius: 8, strong: false, interactive: false)
    }

    private func openProjectResource(_ relativePath: String) {
        if let url = projectResourceURL(relativePath) {
            NSWorkspace.shared.open(url)
        } else {
            NSSound.beep()
        }
    }

    private func projectResourceURL(_ relativePath: String) -> URL? {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            sourceRoot,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        ]

        for root in candidates {
            let candidate = root.appending(path: relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    @ViewBuilder
    private var dictionarySection: some View {
        Section("Personal Dictionary") {
            TextEditor(text: dictionaryTermsBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
            Text("Add names, products, acronyms, and terms OmniVoice should preserve. Use one term per line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var quickReferenceSection: some View {
        Section("Help") {
            OmniVoiceHelpGuide(theme: model.activeTheme) { capability in
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

                Button("Run Translation Test") {
                    Task {
                        await model.runTranslationTest()
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
            get: { model.preferences.asrProvider.normalizedForUserSelection },
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

    private func hotMenuActionBinding(for direction: HotMenuDirection, slot: Int) -> Binding<HotMenuAction> {
        Binding(
            get: {
                let actions = model.preferences.hotMenuActions(for: direction)
                guard actions.indices.contains(slot) else {
                    return .none
                }
                return actions[slot]
            },
            set: { model.setHotMenuAction($0, for: direction, slot: slot) }
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

    private var conversationDiarizationEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.conversationDiarizationEnabled },
            set: { model.setConversationDiarizationEnabled($0) }
        )
    }

    private var conversationDiarizationPrecisionBinding: Binding<DiarizationPrecision> {
        Binding(
            get: { model.conversationDiarizationPrecision },
            set: { model.setConversationDiarizationPrecision($0) }
        )
    }

    private var automaticallyArchiveConversationsBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.automaticallyArchiveConversations },
            set: { model.setAutomaticallyArchiveConversations($0) }
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

    private var translationProviderBinding: Binding<TranslationProviderKind> {
        Binding(
            get: { model.preferences.translationProvider },
            set: { model.setTranslationProvider($0) }
        )
    }

    private var translationModelProviderIDBinding: Binding<String> {
        Binding(
            get: { model.selectedTranslationModelProviderID() },
            set: { model.setTranslationModelProviderID($0) }
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

    private func translationQuickTargetLanguageBinding(slot: Int) -> Binding<String> {
        Binding(
            get: {
                let languages = model.preferences.translationQuickTargetLanguages
                if languages.indices.contains(slot) {
                    return languages[slot]
                }
                let defaults = OmniVoicePreferences.defaultTranslationQuickTargetLanguages
                if defaults.indices.contains(slot) {
                    return defaults[slot]
                }
                return ""
            },
            set: { model.setTranslationQuickTargetLanguage($0, slot: slot) }
        )
    }

    private var textLLMDefaultProviderBinding: Binding<TextLLMProviderKind> {
        Binding(
            get: {
                let current = model.preferences.textLLMDefaultProvider
                if visibleTextLLMProviders.contains(current) {
                    return current
                }
                return visibleTextLLMProviders.first ?? current
            },
            set: { model.setTextLLMDefaultProvider($0) }
        )
    }

    private func textLLMEnabledBinding(_ provider: TextLLMProviderKind) -> Binding<Bool> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).enabled },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.enabled = newValue }
            }
        )
    }

    private func textLLMCustomNameBinding(_ provider: TextLLMProviderKind) -> Binding<String> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).customName },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.customName = newValue }
            }
        )
    }

    private func textLLMTransportBinding(_ provider: TextLLMProviderKind) -> Binding<TextLLMTransport> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).transport },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.transport = newValue }
            }
        )
    }

    private func textLLMAuthModeBinding(_ provider: TextLLMProviderKind) -> Binding<TextLLMAuthMode> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).authMode },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.authMode = newValue }
            }
        )
    }

    private func textLLMBaseURLBinding(_ provider: TextLLMProviderKind) -> Binding<String> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).baseURL },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.baseURL = newValue }
            }
        )
    }

    private func textLLMModelBinding(_ provider: TextLLMProviderKind) -> Binding<String> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).model },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.model = newValue }
            }
        )
    }

    private func textLLMAPIKeyBinding(_ provider: TextLLMProviderKind) -> Binding<String> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).apiKey },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.apiKey = newValue }
            }
        )
    }

    private func textLLMOAuthClientIDBinding(_ provider: TextLLMProviderKind) -> Binding<String> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).oauthClientID },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.oauthClientID = newValue }
            }
        )
    }

    private func textLLMOAuthAccessTokenBinding(_ provider: TextLLMProviderKind) -> Binding<String> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).oauthAccessToken },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.oauthAccessToken = newValue }
            }
        )
    }

    private func textLLMOAuthRefreshTokenBinding(_ provider: TextLLMProviderKind) -> Binding<String> {
        Binding(
            get: { model.preferences.textLLMConfiguration(for: provider).oauthRefreshToken },
            set: { newValue in
                updateTextLLMConfiguration(provider) { $0.oauthRefreshToken = newValue }
            }
        )
    }

    private func textLLMHeaderEnabledBinding(_ provider: TextLLMProviderKind, headerID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                model.preferences.textLLMConfiguration(for: provider)
                    .headers
                    .first { $0.id == headerID }?
                    .enabled ?? true
            },
            set: { newValue in
                updateTextLLMHeader(provider, headerID: headerID) { $0.enabled = newValue }
            }
        )
    }

    private func textLLMHeaderNameBinding(_ provider: TextLLMProviderKind, headerID: UUID) -> Binding<String> {
        Binding(
            get: {
                model.preferences.textLLMConfiguration(for: provider)
                    .headers
                    .first { $0.id == headerID }?
                    .name ?? ""
            },
            set: { newValue in
                updateTextLLMHeader(provider, headerID: headerID) { $0.name = newValue }
            }
        )
    }

    private func textLLMHeaderValueBinding(_ provider: TextLLMProviderKind, headerID: UUID) -> Binding<String> {
        Binding(
            get: {
                model.preferences.textLLMConfiguration(for: provider)
                    .headers
                    .first { $0.id == headerID }?
                    .value ?? ""
            },
            set: { newValue in
                updateTextLLMHeader(provider, headerID: headerID) { $0.value = newValue }
            }
        )
    }

    private func addTextLLMHeader(_ provider: TextLLMProviderKind) {
        updateTextLLMConfiguration(provider) { $0.headers.append(TextLLMHeader()) }
    }

    private func removeTextLLMHeader(_ provider: TextLLMProviderKind, headerID: UUID) {
        updateTextLLMConfiguration(provider) { configuration in
            configuration.headers.removeAll { $0.id == headerID }
        }
    }

    private func updateTextLLMHeader(
        _ provider: TextLLMProviderKind,
        headerID: UUID,
        update: (inout TextLLMHeader) -> Void
    ) {
        updateTextLLMConfiguration(provider) { configuration in
            guard let index = configuration.headers.firstIndex(where: { $0.id == headerID }) else {
                return
            }
            update(&configuration.headers[index])
        }
    }

    private func updateTextLLMConfiguration(
        _ provider: TextLLMProviderKind,
        update: (inout TextLLMProviderConfiguration) -> Void
    ) {
        var configuration = model.preferences.textLLMConfiguration(for: provider)
        update(&configuration)
        model.setTextLLMConfiguration(configuration)
    }

    private func mcpServerEnabledBinding(_ serverID: UUID) -> Binding<Bool> {
        Binding(
            get: { mcpServer(serverID)?.enabled ?? true },
            set: { newValue in
                updateMCPServer(serverID) { $0.enabled = newValue }
            }
        )
    }

    private func mcpServerNameBinding(_ serverID: UUID) -> Binding<String> {
        Binding(
            get: { mcpServer(serverID)?.name ?? "" },
            set: { newValue in
                updateMCPServer(serverID) { $0.name = newValue }
            }
        )
    }

    private func mcpServerCommandBinding(_ serverID: UUID) -> Binding<String> {
        Binding(
            get: { mcpServer(serverID)?.command ?? "" },
            set: { newValue in
                updateMCPServer(serverID) { $0.command = newValue }
            }
        )
    }

    private func mcpServerArgumentsBinding(_ serverID: UUID) -> Binding<String> {
        Binding(
            get: { mcpServer(serverID)?.arguments ?? "" },
            set: { newValue in
                updateMCPServer(serverID) { $0.arguments = newValue }
            }
        )
    }

    private func mcpEnvironmentNameBinding(_ serverID: UUID, variableID: UUID) -> Binding<String> {
        Binding(
            get: {
                mcpServer(serverID)?
                    .environment
                    .first { $0.id == variableID }?
                    .name ?? ""
            },
            set: { newValue in
                updateMCPEnvironmentVariable(serverID, variableID: variableID) { $0.name = newValue }
            }
        )
    }

    private func mcpEnvironmentValueBinding(_ serverID: UUID, variableID: UUID) -> Binding<String> {
        Binding(
            get: {
                mcpServer(serverID)?
                    .environment
                    .first { $0.id == variableID }?
                    .value ?? ""
            },
            set: { newValue in
                updateMCPEnvironmentVariable(serverID, variableID: variableID) { $0.value = newValue }
            }
        )
    }

    private func addMCPEnvironmentVariable(_ serverID: UUID) {
        updateMCPServer(serverID) { $0.environment.append(MCPEnvironmentVariable()) }
    }

    private func removeMCPEnvironmentVariable(_ serverID: UUID, variableID: UUID) {
        updateMCPServer(serverID) { server in
            server.environment.removeAll { $0.id == variableID }
        }
    }

    private func updateMCPEnvironmentVariable(
        _ serverID: UUID,
        variableID: UUID,
        update: (inout MCPEnvironmentVariable) -> Void
    ) {
        updateMCPServer(serverID) { server in
            guard let index = server.environment.firstIndex(where: { $0.id == variableID }) else {
                return
            }
            update(&server.environment[index])
        }
    }

    private func updateMCPServer(_ serverID: UUID, update: (inout MCPServerConfiguration) -> Void) {
        guard var server = mcpServer(serverID) else {
            return
        }
        update(&server)
        model.setMCPServer(server)
    }

    private func mcpServer(_ serverID: UUID) -> MCPServerConfiguration? {
        model.preferences.mcpServers.first { $0.id == serverID }
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
        let label = model.label(for: model.preferences.asrProvider)
        guard let provider = model.providerInfo(for: model.preferences.asrProvider) else {
            return label
        }

        if provider.available {
            return label
        }

        return "\(label) unavailable"
    }

    private var firstRunSpeechModelState: StartupCheckState {
        if let provider = model.providerInfo(for: model.preferences.asrProvider), !provider.available {
            return .failed
        }

        guard let status = selectedModelStatus else {
            return .warning
        }

        return status.installed ? .passed : .failed
    }

    private var firstRunSpeechModelDetail: String {
        let label = model.label(for: model.preferences.asrProvider)

        if let provider = model.providerInfo(for: model.preferences.asrProvider), !provider.available {
            return provider.reason ?? "\(label) is unavailable."
        }

        guard let status = selectedModelStatus else {
            return "\(label) model status has not loaded yet."
        }

        if status.installed {
            return "\(status.label) is installed and ready."
        }

        return "\(status.label) needs to be downloaded before local dictation."
    }

    private var selectedModelStatus: EngineModelStatus? {
        model.modelStatus(for: model.preferences.asrProvider)
    }

    private var selectedDiarizationProviderInfo: EngineProviderInfo? {
        model.diarizationProviderInfo(for: model.preferences.conversationDiarizationProvider)
    }

    private var selectedTranslationProviderInfo: TranslationProviderInfo? {
        model.translationProviderInfo(for: model.preferences.translationProvider)
    }

    private var selectedTranslationModelStatus: EngineModelStatus? {
        return model.modelStatus(forProviderID: model.selectedTranslationModelProviderID())
    }

    private var selectedDiarizationModelStatus: EngineModelStatus? {
        model.modelStatus(forProviderID: model.conversationDiarizationPrecision.providerID)
    }

    private var conversationDiarizationRuntimeText: String {
        let preferred = model.preferences.conversationDiarizationProvider
        let effective = model.effectiveConversationDiarizationProviderID()
        if preferred == effective {
            return model.diarizationLabel(for: effective)
        }
        return "Falls back to \(model.diarizationLabel(for: effective))"
    }

    private var selectedModelUpdateText: String {
        guard let update = model.modelUpdateInfo,
              update.providerID == model.preferences.asrProvider.rawValue else {
            return "Not checked"
        }

        return update.updateAvailable ? "Available" : "Current"
    }

    private var selectedDiarizationModelUpdateText: String {
        guard let update = model.modelUpdateInfo,
              update.providerID == model.conversationDiarizationPrecision.providerID else {
            return "Not checked"
        }

        return update.updateAvailable ? "Available" : "Current"
    }

    private var selectedTranslationModelUpdateText: String {
        guard let update = model.modelUpdateInfo,
              update.providerID == model.selectedTranslationModelProviderID() else {
            return "Not checked"
        }

        return update.updateAvailable ? "Available" : "Current"
    }

    private func statusSummary(_ status: HuggingFaceAuthStatus) -> String {
        if status.connected, status.accessGranted == true {
            if let username = status.username, !username.isEmpty {
                return "Connected as \(username)"
            }
            return "Connected"
        }

        if status.connected {
            return "Connected, access needed"
        }

        return "Not connected"
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

    private var selectedDiarizationModelMessage: String? {
        if let download = model.modelDownloadStatus,
           download.providerID == model.conversationDiarizationPrecision.providerID {
            return download.message ?? download.state
        }

        guard let status = selectedDiarizationModelStatus, !status.missingFiles.isEmpty else {
            return nil
        }

        return "Missing: \(status.missingFiles.joined(separator: ", "))"
    }

    private var selectedTranslationModelMessage: String? {
        let providerID = model.selectedTranslationModelProviderID()

        if let download = model.modelDownloadStatus,
           download.providerID == providerID {
            return download.message ?? download.state
        }

        guard let status = selectedTranslationModelStatus, !status.missingFiles.isEmpty else {
            return nil
        }

        return "Missing: \(status.missingFiles.joined(separator: ", "))"
    }

    private var modelDownloadButtonTitle: String {
        guard let status = selectedModelStatus else { return "Download" }
        return status.installed ? "Update Model" : "Download Model"
    }

    private var translationModelDownloadButtonTitle: String {
        guard let status = selectedTranslationModelStatus else { return "Download" }
        return status.installed ? "Update Model" : "Download Model"
    }

    private var diarizationModelDownloadButtonTitle: String {
        guard let status = selectedDiarizationModelStatus else { return "Download" }
        return status.installed ? "Update Model" : "Download Model"
    }

    private var isModelActionRunning: Bool {
        guard let download = model.modelDownloadStatus,
              download.providerID == model.preferences.asrProvider.rawValue else {
            return false
        }
        return download.state == "queued" || download.state == "downloading"
    }

    private var isTranslationModelActionRunning: Bool {
        guard let download = model.modelDownloadStatus else {
            return false
        }
        return download.providerID == model.selectedTranslationModelProviderID()
            && (download.state == "queued" || download.state == "downloading")
    }

    private var isDiarizationModelActionRunning: Bool {
        guard let download = model.modelDownloadStatus,
              download.providerID == model.conversationDiarizationPrecision.providerID else {
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
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

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
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .dictation:
            "Dictation"
        case .appearance:
            "Personalize"
        case .models:
            "Models"
        case .translation:
            "Translate"
        case .integrations:
            "AI"
        case .help:
            "Help"
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
        case .help:
            "questionmark.circle"
        }
    }

    var minimumTabWidth: CGFloat {
        switch self {
        case .overview:
            68
        case .dictation:
            66
        case .appearance:
            70
        case .models:
            58
        case .translation:
            66
        case .integrations:
            52
        case .help:
            52
        }
    }
}

private struct SettingsTabLiquidBlob: View {
    let theme: OmniVoiceTheme

    var body: some View {
        let accent = Color(themeColor: theme.accentColor)
        let secondary = Color(themeColor: theme.secondaryAccentColor)
        let tint = Color(themeColor: theme.surfaceTint)

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.50)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.16))
                .blur(radius: 4)

            Circle()
                .fill(accent.opacity(0.26))
                .frame(width: 36, height: 36)
                .blur(radius: 11)
                .offset(x: -16, y: -7)

            Circle()
                .fill(secondary.opacity(0.20))
                .frame(width: 31, height: 31)
                .blur(radius: 10)
                .offset(x: 16, y: 7)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            accent.opacity(0.34),
                            secondary.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blur(radius: 0.25)
        }
        .compositingGroup()
        .shadow(color: accent.opacity(0.16), radius: 9, x: 0, y: 4)
    }
}

private extension HotMenuDirection {
    var systemImage: String {
        switch self {
        case .up:
            "arrow.up"
        case .left:
            "arrow.left"
        case .right:
            "arrow.right"
        case .down:
            "arrow.down"
        }
    }
}

private struct CapabilityCatalogView: View {
    let theme: OmniVoiceTheme
    let onSelect: (CapabilityInfo) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
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

private struct OmniVoiceHelpGuide: View {
    let theme: OmniVoiceTheme
    let onSelect: (CapabilityInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HelpHeroCard(theme: theme)

            VStack(alignment: .leading, spacing: 8) {
                Text("Capability Reference")
                    .font(.headline)

                CapabilityCatalogView(theme: theme, onSelect: onSelect)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Things You Can Say")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                    HelpPhraseCard(
                        icon: "text.quote",
                        phrase: "No wait, I mean...",
                        detail: "Replaces the previous thought instead of appending the correction.",
                        theme: theme
                    )
                    HelpPhraseCard(
                        icon: "globe",
                        phrase: "Translation on. Translate to Spanish.",
                        detail: "Turns live translation on and shows the active target above captions.",
                        theme: theme
                    )
                    HelpPhraseCard(
                        icon: "sparkle.magnifyingglass",
                        phrase: "Ask Claude, write a quick reply...",
                        detail: "Sends the spoken request to the configured AI provider and inserts the answer.",
                        theme: theme
                    )
                    HelpPhraseCard(
                        icon: "person.2.wave.2",
                        phrase: "Start conversation mode.",
                        detail: "Records speaker turns, keeps a transcript, and lets Ask AI answer questions about it.",
                        theme: theme
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Use It Like This")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                    ForEach(HelpWorkflow.allCases) { workflow in
                        HelpWorkflowCard(workflow: workflow, theme: theme)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HelpHeroCard: View {
    let theme: OmniVoiceTheme
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color(themeColor: theme.accentColor).opacity(0.14), lineWidth: 1.4)
                        .frame(width: CGFloat(52 + index * 20), height: CGFloat(52 + index * 20))
                        .scaleEffect(animate && !reduceMotion ? 1.12 : 0.92)
                        .opacity(animate && !reduceMotion ? 0.18 : 0.58)
                        .animation(
                            .easeInOut(duration: 1.8 + Double(index) * 0.2)
                                .repeatForever(autoreverses: true),
                            value: animate
                        )
                }

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 30, weight: .semibold))
                    .themeAccentForeground(theme)
                    .frame(width: 70, height: 70)
                    .whisperBlobSurface(
                        accent: Color(themeColor: theme.accentColor),
                        secondary: Color(themeColor: theme.secondaryAccentColor),
                        tint: Color(themeColor: theme.surfaceTint),
                        fillOpacity: 0.10,
                        edgeOpacity: 0.20,
                        glowOpacity: 0.14,
                        edgeBlurRadius: 1.8,
                        edgeBleed: 4,
                        interactive: true
                    )
            }
            .frame(width: 112, height: 96)

            VStack(alignment: .leading, spacing: 7) {
                Text("Speak once. Use it anywhere.")
                    .font(.title3.weight(.bold))

                Text("OmniVoice listens locally, shows captions while you talk, cleans the result, and puts the final text where your cursor already is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HelpSignalStrip(theme: theme, animate: animate && !reduceMotion)
                    .frame(height: 28)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSurface(theme, cornerRadius: 14, strong: true, interactive: false)
        .onAppear {
            animate = true
        }
    }
}

private struct HelpSignalStrip: View {
    let theme: OmniVoiceTheme
    let animate: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<18, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(themeColor: theme.accentColor).opacity(0.88),
                                Color(themeColor: theme.secondaryAccentColor).opacity(0.40)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: barHeight(index))
                    .opacity(index % 3 == 0 ? 0.74 : 0.96)
                    .animation(
                        .easeInOut(duration: 0.7 + Double(index % 5) * 0.08)
                            .repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let base: CGFloat = [9, 14, 20, 12, 24, 16, 11, 22, 15][index % 9]
        return animate ? base : max(8, base * 0.58)
    }
}

private struct HelpWorkflowCard: View {
    let workflow: HelpWorkflow
    let theme: OmniVoiceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: workflow.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .themeAccentForeground(theme)
                    .frame(width: 30, height: 30)
                    .themePillSurface(theme, interactive: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.title)
                        .font(.callout.weight(.semibold))
                    Text(workflow.kicker)
                        .font(.caption2.weight(.semibold))
                        .themeAccentForeground(theme)
                        .textCase(.uppercase)
                }

                Spacer(minLength: 0)
            }

            Text(workflow.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(workflow.example)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(themeColor: theme.surfaceTint).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .themeSurface(theme, cornerRadius: 10, strong: false)
    }
}

private struct HelpPhraseCard: View {
    let icon: String
    let phrase: String
    let detail: String
    let theme: OmniVoiceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .themeAccentForeground(theme)
                    .frame(width: 30, height: 30)
                    .themePillSurface(theme, interactive: false)

                Text("Say This")
                    .font(.caption2.weight(.semibold))
                    .themeAccentForeground(theme)
                    .textCase(.uppercase)

                Spacer(minLength: 0)
            }

            Text(phrase)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(themeColor: theme.surfaceTint).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .themeSurface(theme, cornerRadius: 10, strong: false)
    }
}

private enum HelpWorkflow: String, CaseIterable, Identifiable {
    case dictate
    case translate
    case converse
    case write
    case askAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictate:
            "Dictate"
        case .translate:
            "Translate"
        case .converse:
            "Conversation"
        case .write:
            "Editor"
        case .askAI:
            "Ask AI"
        }
    }

    var kicker: String {
        switch self {
        case .dictate:
            "Cursor first"
        case .translate:
            "Local model"
        case .converse:
            "Speaker turns"
        case .write:
            "Notes to docs"
        case .askAI:
            "Context aware"
        }
    }

    var detail: String {
        switch self {
        case .dictate:
            "Hold the dictation hotkey, talk naturally, release to insert polished text at the cursor."
        case .translate:
            "Enable live translation, pick a target language, and OmniVoice captions the translated result."
        case .converse:
            "Record a meeting, split speaker turns when diarization is enabled, then ask questions about the transcript."
        case .write:
            "Capture rough notes by subject, then send the whole subject into the editor as writing context."
        case .askAI:
            "Add conversations, notes, files, images, or audio to a chat and choose the provider/model per session."
        }
    }

    var example: String {
        switch self {
        case .dictate:
            "No wait, make that..."
        case .translate:
            "Translate to French"
        case .converse:
            "What action items did Mike take?"
        case .write:
            "Write a letter using this subject"
        case .askAI:
            "Read this and draft a reply"
        }
    }

    var systemImage: String {
        switch self {
        case .dictate:
            "mic"
        case .translate:
            "globe"
        case .converse:
            "person.2.wave.2"
        case .write:
            "doc.richtext"
        case .askAI:
            "sparkle.magnifyingglass"
        }
    }
}

private enum CapabilityDemoKind {
    case dictationFlow
    case captionStream
    case correctionRewrite
    case quoteTransform
    case punctuationLayout
    case commandBranch
    case literalFreeze
    case dictionaryPreserve
    case modelPipeline
    case translationFlow
    case aiRoute
    case conversationStack
}

private struct CapabilityDemoVisual: View {
    let capability: CapabilityInfo
    let theme: OmniVoiceTheme
    let compact: Bool
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool {
        animate && !reduceMotion
    }

    var body: some View {
        ZStack {
            demoBackdrop

            switch capability.demoKind {
            case .dictationFlow:
                dictationFlow
            case .captionStream:
                captionStream
            case .correctionRewrite:
                correctionRewrite
            case .quoteTransform:
                quoteTransform
            case .punctuationLayout:
                punctuationLayout
            case .commandBranch:
                commandBranch
            case .literalFreeze:
                literalFreeze
            case .dictionaryPreserve:
                dictionaryPreserve
            case .modelPipeline:
                modelPipeline
            case .translationFlow:
                translationFlow
            case .aiRoute:
                aiRoute
            case .conversationStack:
                conversationStack
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous))
        .onAppear {
            animate = true
        }
    }

    private var demoBackdrop: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                .fill(Color(themeColor: theme.surfaceTint).opacity(0.12))

            Circle()
                .fill(Color(themeColor: theme.accentColor).opacity(active ? 0.14 : 0.07))
                .frame(width: compact ? 80 : 170, height: compact ? 80 : 170)
                .blur(radius: compact ? 16 : 28)
                .offset(x: active ? 46 : -26, y: active ? -16 : 14)
                .animation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true), value: animate)

            Circle()
                .fill(Color(themeColor: theme.secondaryAccentColor).opacity(active ? 0.10 : 0.05))
                .frame(width: compact ? 70 : 140, height: compact ? 70 : 140)
                .blur(radius: compact ? 18 : 32)
                .offset(x: active ? -40 : 38, y: active ? 20 : -20)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: animate)
        }
    }

    private var dictationFlow: some View {
        HStack(spacing: compact ? 8 : 18) {
            demoIcon("mic.fill")
            flowLine
            demoTextPill(active ? "clean text" : "raw speech")
                .offset(x: active ? 0 : -8)
                .opacity(active ? 1 : 0.72)
            flowLine
            demoIcon("cursorarrow.click.2")
        }
        .padding(.horizontal, compact ? 8 : 18)
    }

    private var captionStream: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(Color(themeColor: theme.accentColor).opacity(index < (active ? 7 : 4) ? 0.82 : 0.24))
                        .frame(width: compact ? CGFloat(14 + index % 3 * 5) : CGFloat(24 + index % 3 * 8), height: compact ? 5 : 7)
                        .animation(.easeInOut(duration: 0.9 + Double(index) * 0.05).repeatForever(autoreverses: true), value: animate)
                }
            }
            demoTextPill(active ? "captioning live..." : "listening...")
                .frame(maxWidth: compact ? 150 : 260, alignment: .leading)
        }
        .padding(compact ? 8 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var correctionRewrite: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 12) {
            ZStack(alignment: .leading) {
                Text("store")
                    .font(.system(size: compact ? 13 : 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.red.opacity(0.70))
                    .frame(width: active ? (compact ? 42 : 74) : 4, height: 2)
                    .offset(y: 1)
                    .animation(.easeOut(duration: 0.48), value: animate)
            }
            HStack(spacing: 7) {
                Image(systemName: "arrow.turn.down.right")
                    .themeAccentForeground(theme)
                Text("house")
                    .font(.system(size: compact ? 15 : 28, weight: .bold, design: .rounded))
                    .themeAccentForeground(theme)
                    .scaleEffect(active ? 1 : 0.92)
                    .animation(.spring(response: 0.42, dampingFraction: 0.72), value: animate)
            }
        }
        .padding(compact ? 8 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quoteTransform: some View {
        HStack(spacing: compact ? 7 : 14) {
            Text(active ? "“" : "quote")
                .font(.system(size: compact ? 18 : 40, weight: .bold, design: .serif))
                .themeAccentForeground(theme)
            demoTextPill("hello Jane")
            Text(active ? "”" : "close")
                .font(.system(size: compact ? 18 : 40, weight: .bold, design: .serif))
                .themeSecondaryAccentForeground(theme)
        }
        .padding(.horizontal, compact ? 8 : 18)
        .animation(.snappy(duration: 0.42), value: animate)
    }

    private var punctuationLayout: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            demoLine(width: compact ? 120 : 250)
            demoLine(width: active ? (compact ? 70 : 140) : (compact ? 115 : 230))
            if !compact {
                Spacer(minLength: 3)
            }
            demoLine(width: active ? (compact ? 128 : 260) : (compact ? 46 : 94))
                .offset(y: active ? (compact ? 6 : 12) : 0)
        }
        .padding(compact ? 8 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.62), value: animate)
    }

    private var commandBranch: some View {
        HStack(spacing: compact ? 8 : 18) {
            demoTextPill("Command")
            flowLine
            VStack(spacing: compact ? 5 : 9) {
                demoIcon("safari")
                if !compact {
                    Text("open app")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .offset(y: active ? -6 : 6)
            .animation(.spring(response: 0.52, dampingFraction: 0.76), value: animate)
        }
        .padding(.horizontal, compact ? 8 : 18)
    }

    private var literalFreeze: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(spacing: 7) {
                Image(systemName: "lock.fill")
                    .themeAccentForeground(theme)
                Text("literal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            demoTextPill(compact ? "/Users/michael/..." : "/Users/michael/project && npm run build")
                .font(.caption.monospaced())
                .overlay(alignment: .trailing) {
                    Image(systemName: "checkmark.seal.fill")
                        .themeAccentForeground(theme)
                        .offset(x: compact ? 8 : 10)
                        .opacity(active ? 1 : 0.35)
                }
        }
        .padding(compact ? 8 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dictionaryPreserve: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            demoTextPill("parakeet tdt")
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed.fill")
                    .themeAccentForeground(theme)
                Text("Parakeet TDT")
                    .font(.system(size: compact ? 13 : 22, weight: .bold, design: .rounded))
                    .themeAccentForeground(theme)
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.vertical, compact ? 4 : 7)
                    .background(Color(themeColor: theme.accentColor).opacity(0.15), in: Capsule())
            }
        }
        .padding(compact ? 8 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelPipeline: some View {
        HStack(spacing: compact ? 5 : 12) {
            pipelineNode("HF", icon: "arrow.down.circle")
            flowLine
            pipelineNode("MLX", icon: "cpu")
            flowLine
            pipelineNode("Ready", icon: "checkmark.circle.fill")
        }
        .padding(.horizontal, compact ? 7 : 16)
    }

    private var translationFlow: some View {
        HStack(spacing: compact ? 6 : 14) {
            demoTextPill("Hello")
            Image(systemName: "globe")
                .font(.system(size: compact ? 17 : 34, weight: .semibold))
                .themeAccentForeground(theme)
                .rotationEffect(.degrees(active ? 8 : -8))
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: animate)
            demoTextPill(active ? "Hola" : "...")
                .themeAccentForeground(theme)
        }
        .padding(.horizontal, compact ? 8 : 18)
    }

    private var aiRoute: some View {
        HStack(spacing: compact ? 7 : 14) {
            demoIcon("text.bubble")
            flowLine
            demoIcon("sparkles")
                .scaleEffect(active ? 1.08 : 0.94)
                .animation(.spring(response: 0.50, dampingFraction: 0.68).repeatForever(autoreverses: true), value: animate)
            flowLine
            demoTextPill("answer")
        }
        .padding(.horizontal, compact ? 8 : 18)
    }

    private var conversationStack: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            speakerRow("S1", width: compact ? 118 : 250, color: Color(themeColor: theme.accentColor))
            speakerRow("S2", width: compact ? 92 : 200, color: Color(themeColor: theme.secondaryAccentColor))
                .padding(.leading, compact ? 18 : 38)
            speakerRow("S1", width: compact ? 104 : 230, color: Color(themeColor: theme.accentColor))
        }
        .padding(compact ? 8 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: active ? 0 : 5)
        .animation(.easeOut(duration: 0.55), value: animate)
    }

    private var flowLine: some View {
        Capsule()
            .fill(Color(themeColor: theme.accentColor).opacity(0.42))
            .frame(width: compact ? 18 : 46, height: 2)
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(Color(themeColor: theme.accentColor))
                    .frame(width: compact ? 4 : 6, height: compact ? 4 : 6)
                    .offset(x: active ? 4 : -14)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: animate)
            }
    }

    private func demoIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: compact ? 17 : 30, weight: .semibold))
            .themeAccentForeground(theme)
            .frame(width: compact ? 34 : 58, height: compact ? 34 : 58)
            .background(Color(themeColor: theme.surfaceTint).opacity(0.16), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color(themeColor: theme.accentColor).opacity(0.22), lineWidth: 1)
            }
    }

    private func demoTextPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: compact ? 11 : 18, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.70)
            .padding(.horizontal, compact ? 8 : 13)
            .padding(.vertical, compact ? 5 : 8)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color(themeColor: theme.accentColor).opacity(0.20), lineWidth: 1)
            }
    }

    private func demoLine(width: CGFloat) -> some View {
        Capsule()
            .fill(Color(themeColor: theme.accentColor).opacity(0.45))
            .frame(width: width, height: compact ? 6 : 9)
    }

    private func pipelineNode(_ label: String, icon: String) -> some View {
        VStack(spacing: compact ? 3 : 7) {
            Image(systemName: icon)
                .font(.system(size: compact ? 14 : 23, weight: .semibold))
            Text(label)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(1)
        }
        .themeAccentForeground(theme)
        .frame(width: compact ? 48 : 78, height: compact ? 48 : 78)
        .background(Color(themeColor: theme.surfaceTint).opacity(0.14), in: RoundedRectangle(cornerRadius: compact ? 8 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 8 : 14, style: .continuous)
                .stroke(Color(themeColor: theme.accentColor).opacity(active ? 0.38 : 0.18), lineWidth: 1)
        }
    }

    private func speakerRow(_ speaker: String, width: CGFloat, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(speaker)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: compact ? 24 : 34)
            Capsule()
                .fill(color.opacity(0.62))
                .frame(width: active ? width : width * 0.68, height: compact ? 8 : 12)
        }
    }
}

private struct CapabilityCard: View {
    let capability: CapabilityInfo
    let theme: OmniVoiceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: capability.systemImage)
                    .themeAccentForeground(theme)
                    .frame(width: 18)
                Text(capability.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            CapabilityDemoVisual(capability: capability, theme: theme, compact: true)
                .frame(height: 70)

            Text(capability.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .padding(10)
        .themeSurface(theme, cornerRadius: 8, strong: false)
    }
}

private struct CapabilityDetailSheet: View {
    let capability: CapabilityInfo
    let theme: OmniVoiceTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: capability.systemImage)
                            .font(.title2)
                            .themeAccentForeground(theme)
                            .frame(width: 34, height: 34)
                            .themePillSurface(theme, interactive: false)

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

                    CapabilityDemoVisual(capability: capability, theme: theme, compact: false)
                        .frame(height: 170)
                        .padding(12)
                        .themeSurface(theme, cornerRadius: 14, strong: true, interactive: false)

                    CapabilityDetailBlock(
                        title: "What It Does",
                        text: capability.whatItDoes,
                        systemImage: "sparkles",
                        theme: theme
                    )

                    CapabilityDetailBlock(
                        title: "Say This",
                        lines: capability.sayThis,
                        systemImage: "quote.bubble",
                        theme: theme
                    )

                    CapabilityDetailBlock(
                        title: "What Happens",
                        text: capability.whatHappens,
                        systemImage: "arrow.down.forward.and.arrow.up.backward",
                        theme: theme
                    )
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 620, height: 640)
        .themeWindowBackground(theme)
    }
}

private struct CapabilityDetailBlock: View {
    let title: String
    let text: String?
    let lines: [String]
    let systemImage: String
    let theme: OmniVoiceTheme

    init(title: String, text: String, systemImage: String, theme: OmniVoiceTheme) {
        self.title = title
        self.text = text
        self.lines = []
        self.systemImage = systemImage
        self.theme = theme
    }

    init(title: String, lines: [String], systemImage: String, theme: OmniVoiceTheme) {
        self.title = title
        self.text = nil
        self.lines = lines
        self.systemImage = systemImage
        self.theme = theme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .themeAccentForeground(theme)

            if let text {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(Color(themeColor: theme.surfaceTint).opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSurface(theme, cornerRadius: 10, strong: false, interactive: false)
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
                "Say: Have OpenRouter take a look at the current window and respond in Spanish.",
            ]
        case .conversationHistory:
            [
                "Open History, then copy a transcript.",
                "Open History, then Insert a transcript at the current cursor.",
            ]
        }
    }

    var sayThis: [String] {
        examples
    }

    var demoKind: CapabilityDemoKind {
        switch self {
        case .dictation:
            .dictationFlow
        case .liveCaptions:
            .captionStream
        case .corrections:
            .correctionRewrite
        case .quotes:
            .quoteTransform
        case .punctuation:
            .punctuationLayout
        case .commandMode:
            .commandBranch
        case .literalMode:
            .literalFreeze
        case .personalDictionary:
            .dictionaryPreserve
        case .modelControl:
            .modelPipeline
        case .translation:
            .translationFlow
        case .aiHandoff:
            .aiRoute
        case .conversationHistory:
            .conversationStack
        }
    }

    var whatItDoes: String {
        switch self {
        case .dictation:
            "Turns a held hotkey into a local speech-to-text session, cleans the result, and inserts the final text into the foreground app."
        case .liveCaptions:
            "Shows a lightweight caption overlay while audio is being processed, so you can see that OmniVoice is hearing you before final insertion."
        case .corrections:
            "Detects self-correction phrases and rewrites the previous clause instead of blindly appending every word you spoke."
        case .quotes:
            "Converts spoken quote markers into punctuation so dictated messages, prompts, and snippets read naturally."
        case .punctuation:
            "Maps spoken punctuation and layout commands into commas, periods, line breaks, and paragraph breaks."
        case .commandMode:
            "Routes command phrases into app actions rather than text insertion, keeping dictation and control separate."
        case .literalMode:
            "Keeps exact wording, file paths, commands, and code-like fragments from being over-polished by cleanup."
        case .personalDictionary:
            "Injects names, products, acronyms, and preferred casing into cleanup so recurring terms survive dictation."
        case .modelControl:
            "Keeps the local model stack visible: what is selected, what is installed, and what can be downloaded or updated."
        case .translation:
            "Runs dictated English through the local translation model and shows the active target language in the caption flow."
        case .aiHandoff:
            "Hands a spoken prompt to the selected AI provider/model, then inserts or displays the answer where the workflow needs it."
        case .conversationHistory:
            "Stores conversation transcripts so they can be copied, opened in the editor, or attached to Ask AI as context."
        }
    }

    var whatHappens: String {
        switch self {
        case .dictation:
            "The raw transcript stays local, cleanup runs, and the cursor ends at the end of the inserted text."
        case .liveCaptions:
            "The overlay appears during capture, updates while you speak, then fades back after the final text is handled."
        case .corrections:
            "The mistaken phrase is removed from the final text and the replacement phrase becomes the sentence."
        case .quotes:
            "The spoken markers disappear and the final text contains typographic quote characters around the intended phrase."
        case .punctuation:
            "The words that name punctuation are transformed into formatting, giving you readable prose without manual cleanup."
        case .commandMode:
            "OmniVoice performs the action, reports status, and avoids dumping the command words into the active text field."
        case .literalMode:
            "Cleanup backs off and preserves spacing, symbols, casing, and command-shaped text as closely as possible."
        case .personalDictionary:
            "Matched terms are favored during cleanup, which reduces recurring fixes for client names, model names, and product names."
        case .modelControl:
            "The app checks local availability, downloads or updates models when requested, and reports model health in Settings."
        case .translation:
            "Captions and final output use the selected target language while the app keeps the source/target state visible."
        case .aiHandoff:
            "The request is sent with any configured context, files, conversations, or transcripts, then the response lands in the AI flow."
        case .conversationHistory:
            "Speaker turns and transcripts remain available after recording so later writing and AI work can reuse the context."
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
