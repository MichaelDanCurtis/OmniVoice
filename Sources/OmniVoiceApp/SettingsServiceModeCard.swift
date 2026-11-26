import OmniVoiceCore
import SwiftUI

/// Independent SwiftUI view for the **Service Mode (Cloud / Outbound)** configuration card,
/// keeping `@Observable` invalidations isolated from the rest of `SettingsView`.
struct SettingsServiceModeCard: View {
    @Bindable var model: AppModel

    var body: some View {
        let cfg = model.preferences.serviceMode
        let hasKey = !model.effectiveDeepgramAPIKey.isEmpty
        let registry = AgentRegistry(custom: model.preferences.customAgents)
        let discoveredIDs = Set(model.discoveredAgents.map(\.id))

        OmniGlassCard(theme: model.activeTheme, cornerRadius: 14, strong: cfg.enabled, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Label("Service Mode (Cloud / Outbound)", systemImage: "cloud.bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .fontDesign(model.activeTheme.look.headerFontDesign)

                            OmniStatusPill(
                                title: cfg.enabled ? (hasKey ? "Active" : "API Key Needed") : "Local",
                                tint: cfg.enabled ? (hasKey ? .cyan : .orange) : .secondary,
                                systemImage: cfg.enabled ? "antenna.radiowaves.left.and.right" : "desktopcomputer",
                                theme: model.activeTheme
                            )
                        }

                        Text("Flip everything to cloud/outbound services — Deepgram handles dictation, conversations, and speaker diarization while your AI subscriptions handle cleanup, Ask AI, and Meeting Co-Pilot. Zero local models loaded in RAM.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { model.preferences.serviceMode.enabled },
                        set: { model.setServiceModeEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Deepgram API Key")
                            .font(.callout)
                            .frame(width: 136, alignment: .leading)

                        SecureField("dg_... (stored in macOS Keychain)", text: Binding(
                            get: { model.deepgramAPIKey },
                            set: { model.setDeepgramAPIKey($0) }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await model.testDeepgramConnection() }
                        } label: {
                            Text(model.isTestingDeepgramConnection ? "Testing…" : "Test Key")
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(model.isTestingDeepgramConnection || !hasKey)
                    }

                    if let status = model.deepgramConnectionStatus, !status.isEmpty {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(status.lowercased().hasPrefix("connected") ? .green : .orange)
                    } else if model.deepgramAPIKey.isEmpty, hasKey {
                        Text("Using DEEPGRAM_API_KEY from your shell environment.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deepgram Model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Deepgram Model", selection: Binding(
                            get: { model.preferences.serviceMode.deepgramModel },
                            set: { model.setServiceModeDeepgramModel($0) }
                        )) {
                            ForEach(DeepgramModel.allCases) { option in
                                Text("\(option.displayName) — \(option.badge)").tag(option)
                            }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice Language")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Voice Language", selection: Binding(
                            get: { model.preferences.serviceMode.deepgramLanguage },
                            set: { model.setServiceModeDeepgramLanguage($0) }
                        )) {
                            ForEach(ServiceModeConfiguration.languageOptions, id: \.code) { item in
                                Text(item.label).tag(item.code)
                            }
                        }
                        .labelsHidden()
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subscription LLM")
                            .font(.callout)
                        Text("Use your existing Gemini Antigravity, Claude, Codex, Gemini, or Copilot subscription — no extra API key required.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Subscription LLM", selection: Binding<String>(
                        get: { model.preferences.serviceMode.llmRoute.pickerID },
                        set: { model.setServiceModeLLMRoute(ServiceModeLLMRoute(pickerID: $0)) }
                    )) {
                        Text("Follow AI Configuration (\(model.resolvedUnifiedAILabel))").tag(ServiceModeLLMRoute.auto.pickerID)
                        Section("Installed Subscription CLIs") {
                            ForEach(registry.all, id: \.id) { agent in
                                let badge = discoveredIDs.contains(agent.id) ? " ✓" : ""
                                Text("\(agent.displayName) CLI\(badge)")
                                    .tag(ServiceModeLLMRoute.subscriptionAgent(agentID: agent.id).pickerID)
                            }
                        }
                        Section("Configured AI Providers (OAuth / API)") {
                            ForEach(TextLLMProviderKind.allCases, id: \.self) { provider in
                                let cfgProvider = model.preferences.textLLMConfiguration(for: provider)
                                let badge = cfgProvider.isConfigured ? " ✓" : ""
                                Text("\(cfgProvider.displayName)\(badge)")
                                    .tag(ServiceModeLLMRoute.configuredTextLLM(provider: provider).pickerID)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }

                HStack(spacing: 16) {
                    Toggle("Smart Format & Punctuation", isOn: Binding(
                        get: { model.preferences.serviceMode.deepgramSmartFormat },
                        set: { model.setServiceModeDeepgramSmartFormat($0) }
                    ))
                    .font(.caption)

                    Toggle("Cloud Speaker Diarization", isOn: Binding(
                        get: { model.preferences.serviceMode.deepgramDiarize },
                        set: { model.setServiceModeDeepgramDiarize($0) }
                    ))
                    .font(.caption)

                    Toggle("Unload local MLX RAM", isOn: Binding(
                        get: { model.preferences.serviceMode.unloadLocalModelsWhenEnabled },
                        set: { model.setServiceModeUnloadLocalModels($0) }
                    ))
                    .font(.caption)
                }
            }
        }
    }
}
