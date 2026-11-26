import Foundation
import OmniVoiceCore

/// Service Mode (Cloud / Outbound): streams voice through Deepgram and routes
/// LLM cleanup, translation, Voice Edit, Command Mode, and Meeting Co-Pilot
/// through the user's existing AI subscriptions.
extension AppModel {
    var isServiceModeEnabled: Bool {
        preferences.serviceMode.enabled
    }

    var effectiveDeepgramAPIKey: String {
        let direct = deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        return (ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isServiceModeReady: Bool {
        preferences.serviceMode.enabled && !effectiveDeepgramAPIKey.isEmpty
    }

    var serviceModeLLMLabel: String {
        switch preferences.serviceMode.llmRoute {
        case .auto:
            if let cfg = configuredConversationTextLLMConfiguration() {
                return "Auto (\(cfg.displayName))"
            }
            if let firstAgent = discoveredAgents.first {
                return "Auto (\(firstAgent.displayName) CLI)"
            }
            return "Auto"
        case .subscriptionAgent(let agentID):
            let registry = AgentRegistry(custom: preferences.customAgents)
            if let agent = registry.all.first(where: { $0.id == agentID }) {
                return "\(agent.displayName) CLI"
            }
            return "\(agentID) CLI"
        case .configuredTextLLM(let provider):
            return preferences.textLLMConfiguration(for: provider).displayName
        }
    }

    var serviceModeStatusSummary: String {
        "Deepgram \(preferences.serviceMode.deepgramModel.displayName) · \(serviceModeLLMLabel)"
    }

    func setServiceModeEnabled(_ enabled: Bool) {
        guard preferences.serviceMode.enabled != enabled else { return }
        preferences.serviceMode.enabled = enabled
        _ = persistPreferences()
        if enabled {
            if preferences.serviceMode.unloadLocalModelsWhenEnabled {
                Task {
                    await MLXLocalCleanupService.shared.unload()
                }
            }
            statusText = isServiceModeReady
                ? "Service Mode on (\(serviceModeStatusSummary))"
                : "Service Mode on — add Deepgram API key in Models"
        } else {
            statusText = "Local mode active (\(label(for: preferences.asrProvider)))"
        }
    }

    func setServiceModeDeepgramModel(_ model: DeepgramModel) {
        guard preferences.serviceMode.deepgramModel != model else { return }
        preferences.serviceMode.deepgramModel = model
        _ = persistPreferences()
    }

    func setServiceModeDeepgramLanguage(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "multi" : trimmed
        guard preferences.serviceMode.deepgramLanguage != resolved else { return }
        preferences.serviceMode.deepgramLanguage = resolved
        _ = persistPreferences()
    }

    func setServiceModeDeepgramSmartFormat(_ enabled: Bool) {
        guard preferences.serviceMode.deepgramSmartFormat != enabled else { return }
        preferences.serviceMode.deepgramSmartFormat = enabled
        _ = persistPreferences()
    }

    func setServiceModeLLMRoute(_ route: ServiceModeLLMRoute) {
        guard preferences.serviceMode.llmRoute != route else { return }
        preferences.serviceMode.llmRoute = route
        _ = persistPreferences()
        if preferences.serviceMode.enabled {
            statusText = "Service Mode LLM → \(serviceModeLLMLabel)"
        }
    }

    func setServiceModeUnloadLocalModels(_ enabled: Bool) {
        guard preferences.serviceMode.unloadLocalModelsWhenEnabled != enabled else { return }
        preferences.serviceMode.unloadLocalModelsWhenEnabled = enabled
        _ = persistPreferences()
        if enabled && preferences.serviceMode.enabled {
            Task {
                await MLXLocalCleanupService.shared.unload()
            }
        }
    }

    func setDeepgramAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard deepgramAPIKey != trimmed else { return }
        deepgramAPIKey = trimmed
        deepgramConnectionStatus = nil
        _ = llmSecretStore.setValue(trimmed, provider: Self.deepgramSecretProviderID, field: .apiKey)
    }

    func testDeepgramConnection() async {
        let key = effectiveDeepgramAPIKey
        guard !key.isEmpty else {
            deepgramConnectionStatus = "Enter a Deepgram API key first."
            return
        }
        isTestingDeepgramConnection = true
        deepgramConnectionStatus = "Testing Deepgram key…"
        defer { isTestingDeepgramConnection = false }

        do {
            deepgramConnectionStatus = try await DeepgramClient.testConnection(apiKey: key)
        } catch {
            deepgramConnectionStatus = error.localizedDescription
        }
    }

    /// Executes an LLM prompt through the user's configured Service Mode subscription
    /// (OAuth/API Text LLM provider OR installed subscription CLI such as Gemini Antigravity/Claude/Codex).
    func runServiceModeLLM(
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIChatAttachment] = []
    ) async -> String? {
        switch preferences.serviceMode.llmRoute {
        case .configuredTextLLM(let provider):
            let cfg = preferences.textLLMConfiguration(for: provider)
            if let text = await callTextLLMConfiguration(cfg, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments) {
                return text
            }
            if let fallbackCfg = configuredConversationTextLLMConfiguration(), fallbackCfg.provider != provider {
                return await callTextLLMConfiguration(fallbackCfg, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments)
            }
            return nil

        case .subscriptionAgent(let agentID):
            guard attachments.isEmpty else {
                if let cfg = configuredConversationTextLLMConfiguration() {
                    return await callTextLLMConfiguration(cfg, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments)
                }
                return nil
            }
            let registry = AgentRegistry(custom: preferences.customAgents)
            if let descriptor = registry.all.first(where: { $0.id == agentID }) ?? discoveredAgents.first?.descriptor {
                let combinedPrompt = "\(systemPrompt)\n\n\(userPrompt)"
                if let output = try? await meetingAgentRunner.run(descriptor, prompt: combinedPrompt, onChunk: { _ in }) {
                    let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                    if !sanitized.isEmpty { return sanitized }
                }
            }
            return nil

        case .auto:
            if let cfg = configuredConversationTextLLMConfiguration(),
               let text = await callTextLLMConfiguration(cfg, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments) {
                return text
            }
            if attachments.isEmpty, let localAgent = discoveredAgents.first?.descriptor {
                let combinedPrompt = "\(systemPrompt)\n\n\(userPrompt)"
                if let output = try? await meetingAgentRunner.run(localAgent, prompt: combinedPrompt, onChunk: { _ in }) {
                    let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                    if !sanitized.isEmpty { return sanitized }
                }
            }
            return nil
        }
    }

    private func callTextLLMConfiguration(
        _ configuration: TextLLMProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIChatAttachment]
    ) async -> String? {
        guard configuration.isConfigured else { return nil }
        do {
            let result = try await engineClient.aiChat(
                AIChatRequest(
                    provider: configuration.provider.rawValue,
                    baseURL: configuration.resolvedBaseURL,
                    model: configuration.trimmedModel,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders,
                    messages: [
                        AIChatMessage(role: .system, content: systemPrompt),
                        AIChatMessage(role: .user, content: userPrompt),
                    ],
                    attachments: attachments,
                    webSearchEnabled: false
                )
            )
            let cleaned = MLXLocalCleanupService.sanitizeOutput(result.text)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }
}
