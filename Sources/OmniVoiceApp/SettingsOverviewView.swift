import AppKit
import SwiftUI
import OmniVoiceCore

struct SettingsOverviewView<RecoveryContent: View>: View {
    @Bindable var model: AppModel
    let selectedProviderStatus: String
    let streamChunkText: String
    let streamBytesText: String
    let showTestCaption: () -> Void
    let requestAccessibilityPermission: () -> Void
    let resetAccessibilityPermission: () -> Void
    let refreshPermissions: () -> Void
    let showConversationHistory: () -> Void
    let openConversationMode: () -> Void
    let openEditor: () -> Void
    let openAskAI: () -> Void
    @ViewBuilder let recoveryContent: () -> RecoveryContent

    private let healthColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        let theme = model.activeTheme

        VStack(alignment: .leading, spacing: 14) {
            heroEngineCard(theme: theme)

            LazyVGrid(columns: healthColumns, spacing: 10) {
                microphoneHealthTile(theme: theme)
                accessibilityHealthTile(theme: theme)
                streamHealthTile(theme: theme)
            }

            productivityStatsCard(theme: theme)

            recoveryContent()

            recentDictationsCard(theme: theme)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func productivityStatsCard(theme: OmniVoiceTheme) -> some View {
        let stats = model.dictationStats
        OmniGlassCard(theme: theme, cornerRadius: 14, strong: false, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Voice Productivity", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(stats.totalSessions) dictations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statPill(title: "Today", value: "\(stats.todayWords) words", theme: theme)
                    statPill(title: "Avg Speed", value: stats.averageWPM > 0 ? "\(stats.averageWPM) WPM" : "—", theme: theme)
                    statPill(title: "Time Saved", value: "\(stats.estimatedMinutesSaved) min", theme: theme)
                    statPill(title: "All Time", value: "\(stats.totalWords) words", theme: theme)
                }

                if !stats.topApps.isEmpty {
                    HStack(spacing: 6) {
                        Text("Top apps:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(stats.topApps, id: \.name) { app in
                            Text("\(app.name) (\(app.words))")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(themeColor: theme.accentColor).opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func statPill(title: String, value: String, theme: OmniVoiceTheme) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .themeSurface(theme, cornerRadius: 9, strong: false, interactive: false)
    }

    @ViewBuilder
    private func heroEngineCard(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 16, strong: true, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            OmniStatusPill(
                                title: "Engine \(model.engineState.label)",
                                tint: engineStatusColor,
                                pulsing: model.engineState == .online,
                                theme: theme
                            )

                            OmniStatusPill(
                                title: model.isServiceModeReady
                                    ? "Service Mode · Deepgram"
                                    : model.activeEngineBackendLabel,
                                tint: model.isServiceModeReady ? .cyan : Color(themeColor: theme.accentColor),
                                systemImage: model.isServiceModeReady ? "cloud.bolt.fill" : "bolt.horizontal.circle",
                                theme: theme
                            )
                        }

                        Text(model.isServiceModeReady
                             ? model.serviceModeStatusSummary
                             : model.label(for: model.preferences.asrProvider))
                            .font(.title3.weight(.semibold))
                            .fontDesign(theme.look.headerFontDesign)
                            .lineLimit(1)

                        Text(model.isServiceModeReady
                             ? "Cloud voice via Deepgram · LLM via \(model.serviceModeLLMLabel)"
                             : "\(selectedProviderStatus) · \(model.engineState.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Dictation Hotkey")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        OmniKeycapBadge(
                            shortcut: model.preferences.dictationHotkey.displayName,
                            theme: theme
                        )
                    }
                }

                Divider().opacity(0.45)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Service Mode (Cloud / Outbound)", systemImage: "cloud.bolt.fill")
                                .font(.caption.weight(.semibold))
                            Text(model.isServiceModeReady
                                 ? "Voice → Deepgram \(model.preferences.serviceMode.deepgramModel.displayName) · AI → \(model.serviceModeLLMLabel)"
                                 : (model.isServiceModeEnabled
                                    ? "Add your Deepgram API key in Models → Service Mode to activate."
                                    : "Offload voice input to Deepgram and LLM tasks to your existing subscriptions."))
                                .font(.caption2)
                                .foregroundStyle(model.isServiceModeEnabled && !model.isServiceModeReady ? .orange : .secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.preferences.serviceMode.enabled },
                            set: { model.setServiceModeEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                Divider().opacity(0.45)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Engine Runtime")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Picker("Engine Runtime", selection: Binding(
                            get: { model.preferences.engineBackendMode },
                            set: { model.setEngineBackendMode($0) }
                        )) {
                            ForEach(EngineBackendMode.allCases, id: \.self) { mode in
                                Text(mode.shortLabel).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }

                    Text(model.preferences.engineBackendMode.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.45)

                HStack(spacing: 8) {
                    Button {
                        refreshPermissions()
                        Task { await model.refreshEngineStatus() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task { await model.restartEngine(forceExternal: true) }
                    } label: {
                        Label("Restart Engine", systemImage: "power")
                    }

                    Button {
                        openConversationMode()
                    } label: {
                        Label("Conversation", systemImage: "bubble.left.and.text.bubble.right")
                    }

                    Button {
                        openEditor()
                    } label: {
                        Label("Editor", systemImage: "doc.richtext")
                    }

                    Button {
                        openAskAI()
                    } label: {
                        Label("Ask AI", systemImage: "sparkles")
                    }

                    Spacer()

                    Button {
                        NSWorkspace.shared.open(
                            EngineAuthTokenStore.shared.authenticatedURL(URL(string: "http://127.0.0.1:8765/")!)
                        )
                    } label: {
                        Label("Dashboard", systemImage: "safari")
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func microphoneHealthTile(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 13, strong: false, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Circle()
                        .fill(model.microphoneAuthorized ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                }

                Text(model.microphoneAuthorized ? "Allowed" : "Permission Required")
                    .font(.subheadline.weight(.semibold))

                Text(model.microphoneLabel(for: model.preferences.microphoneId))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func accessibilityHealthTile(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 13, strong: false, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Accessibility", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Circle()
                        .fill(model.accessibilityTrusted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                }

                Text(model.accessibilityTrusted ? "Allowed" : "Permission Required")
                    .font(.subheadline.weight(.semibold))

                if model.accessibilityTrusted {
                    Text("Cursor text insertion active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Drag from bar below or open Settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Button("Open Settings") { requestAccessibilityPermission() }
                            .controlSize(.mini)
                            .buttonStyle(.borderedProminent)
                        Button("Reset") { resetAccessibilityPermission() }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func streamHealthTile(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 13, strong: false, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Stream Pipeline", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Circle()
                        .fill(Color(themeColor: theme.accentColor))
                        .frame(width: 8, height: 8)
                }

                Text(model.streamingDiagnostics.state.displayName)
                    .font(.subheadline.weight(.semibold))

                Text("\(model.streamingDiagnostics.chunksSent) sent · \(model.streamingDiagnostics.partialsReceived) partials · \(streamBytesText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let lastError = model.streamingDiagnostics.lastError {
                    Text(lastError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func recentDictationsCard(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 14, strong: false, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Recent Dictations", systemImage: "text.bubble")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button("Show Caption") {
                        showTestCaption()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                    Button("Open History") {
                        showConversationHistory()
                        Task { await model.refreshTranscripts() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                if model.transcripts.isEmpty {
                    Text("No recent dictations recorded yet — hold \(model.preferences.dictationHotkey.displayName) to dictate or run a quick cleanup test.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(model.transcripts.prefix(3))) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.displayText)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .textSelection(.enabled)

                                HStack(spacing: 8) {
                                    if let style = record.style, !style.isEmpty {
                                        Text(style)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    if let provider = record.provider, !provider.isEmpty {
                                        Text(provider)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 4)
                            if record.id != model.transcripts.prefix(3).last?.id {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }
            }
        }
    }

    private var engineStatusColor: Color {
        switch model.engineState {
        case .online:
            .green
        case .checking, .unknown:
            .orange
        case .offline:
            .red
        }
    }
}
