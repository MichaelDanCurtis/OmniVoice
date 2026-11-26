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
    var checkForUpdates: (() -> Void)? = nil
    var canCheckForUpdates: Bool = false

    private let workspaceColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        let theme = model.activeTheme
        let accent = Color(themeColor: theme.accentColor)

        VStack(alignment: .leading, spacing: 11) {
            headerSection(theme: theme, accent: accent)

            modelAndPipelineCard(theme: theme)

            LazyVGrid(columns: workspaceColumns, spacing: 8) {
                OmniWorkspaceTile(
                    title: "Conversation",
                    subtitle: "Live & archive",
                    systemImage: "bubble.left.and.text.bubble.right",
                    theme: theme,
                    action: openConversationMode
                )

                OmniWorkspaceTile(
                    title: "Editor",
                    subtitle: "Notes & docs",
                    systemImage: "doc.richtext",
                    theme: theme,
                    action: openEditor
                )

                OmniWorkspaceTile(
                    title: "Ask AI",
                    subtitle: "Prompt chat",
                    systemImage: "sparkles",
                    theme: theme,
                    action: openAskAI
                )
            }

            if !model.accessibilityTrusted {
                accessibilityAlertBanner(theme: theme)
            }

            footerActions
        }
        .padding(12)
        .frame(width: 324, alignment: .leading)
        .themeWindowBackground(theme)
    }

    @ViewBuilder
    private func headerSection(theme: OmniVoiceTheme, accent: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("OmniSpeak")
                        .font(.headline)
                        .fontDesign(theme.look.headerFontDesign)
                }

                Text(model.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                OmniStatusPill(
                    title: model.engineState.label,
                    tint: engineStatusColor,
                    pulsing: model.engineState == .online,
                    theme: theme
                )

                OmniKeycapBadge(
                    shortcut: model.preferences.dictationHotkey.displayName,
                    theme: theme
                )
            }
        }
    }

    @ViewBuilder
    private func modelAndPipelineCard(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 12, strong: false, padding: 11) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Speech Model")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(model.label(for: model.preferences.asrProvider))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Cycle ASR") {
                        model.cycleASRProvider()
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }

                Divider().opacity(0.4)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cleanup Style")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(model.preferences.style.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Cycle Style") {
                        model.cycleStyle()
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }

                Divider().opacity(0.4)

                HStack(spacing: 10) {
                    Toggle("Smart AI", isOn: Binding(
                        get: { model.preferences.llmCleanupEnabled },
                        set: { model.setLLMCleanupEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Spacer(minLength: 4)

                    Toggle("Translate", isOn: Binding(
                        get: { model.preferences.liveTranslationEnabled },
                        set: { model.setLiveTranslationEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .font(.caption)

                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Runtime: \(model.activeEngineBackendLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(theme.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func accessibilityAlertBanner(theme: OmniVoiceTheme) -> some View {
        OmniGlassCard(theme: theme, cornerRadius: 10, strong: true, padding: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility Required")
                        .font(.caption.weight(.semibold))
                    Text("Allow Accessibility so OmniSpeak can insert text.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button("Grant") {
                    requestAccessibilityPermission()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button {
                    Task { await model.refreshEngineStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button {
                    showTestCaption()
                } label: {
                    Label("Caption", systemImage: "captions.bubble")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Cleanup Test") {
                    Task { await model.runCleanupTest() }
                }
                .buttonStyle(.link)
                .font(.caption2)

                Button("Dashboard") {
                    NSWorkspace.shared.open(
                        EngineAuthTokenStore.shared.authenticatedURL(URL(string: "http://127.0.0.1:8765/")!)
                    )
                }
                .buttonStyle(.link)
                .font(.caption2)

                Button("History") {
                    NSWorkspace.shared.open(
                        EngineAuthTokenStore.shared.authenticatedURL(URL(string: "http://127.0.0.1:8765/api/transcripts")!)
                    )
                }
                .buttonStyle(.link)
                .font(.caption2)

                if let checkForUpdates {
                    Button("Updates") {
                        checkForUpdates()
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                    .disabled(!canCheckForUpdates)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
