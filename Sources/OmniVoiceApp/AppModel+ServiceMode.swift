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
            return "AI Config (\(resolvedUnifiedAILabel))"
        case .subscriptionAgent(let agentID):
            return "\(agentDisplayName(for: agentID)) CLI"
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
        warmUpConfiguredACPAgents()
        Task { await refreshStartupChecks() }
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

    func setServiceModeDeepgramDiarize(_ enabled: Bool) {
        guard preferences.serviceMode.deepgramDiarize != enabled else { return }
        preferences.serviceMode.deepgramDiarize = enabled
        _ = persistPreferences()
        Task { await refreshStartupChecks() }
    }

    func setServiceModeLLMRoute(_ route: ServiceModeLLMRoute) {
        guard preferences.serviceMode.llmRoute != route else { return }
        preferences.serviceMode.llmRoute = route
        _ = persistPreferences()
        if preferences.serviceMode.enabled {
            statusText = "Service Mode LLM → \(serviceModeLLMLabel)"
        }
        warmUpConfiguredACPAgents()
        Task { await refreshStartupChecks() }
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
        attachments: [AIChatAttachment] = [],
        isCleanup: Bool = false,
        agentTimeoutSeconds: Double? = nil
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
                if descriptor.supportsACP {
                    if isCleanup {
                        // Zero-wait cold start for dictation cleanup: if ACP is warming, skip
                        // editing and return nil immediately so raw/Deepgram text pastes right away.
                        if let output = await ACPAgentPool.shared.promptIfReady(
                            descriptor,
                            prompt: combinedPrompt,
                            purpose: .cleanup,
                            timeoutSeconds: 8.5
                        ) {
                            let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                            if !sanitized.isEmpty { return sanitized }
                        }
                        return nil
                    }
                    if let output = try? await ACPAgentPool.shared.promptWaitingForWarmup(
                        descriptor,
                        prompt: combinedPrompt,
                        purpose: .interactive,
                        timeoutSeconds: agentTimeoutSeconds
                    ) {
                        let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                        if !sanitized.isEmpty { return sanitized }
                    }
                }
                if let output = try? await meetingAgentRunner.run(
                    descriptor,
                    prompt: combinedPrompt,
                    timeoutSeconds: agentTimeoutSeconds,
                    onChunk: { _ in }
                ) {
                    let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                    if !sanitized.isEmpty { return sanitized }
                }
            }
            return nil

        case .auto:
            let route = resolvedUnifiedAIRoute()
            if isCleanup, case .agent(let agentID) = route {
                let registry = AgentRegistry(custom: preferences.customAgents)
                if let descriptor = registry.all.first(where: { $0.id == agentID }) ?? discoveredAgents.first?.descriptor,
                   descriptor.supportsACP {
                    let combinedPrompt = "\(systemPrompt)\n\n\(userPrompt)"
                    if let output = await ACPAgentPool.shared.promptIfReady(
                        descriptor,
                        prompt: combinedPrompt,
                        purpose: .cleanup,
                        timeoutSeconds: 8.5
                    ) {
                        let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                        if !sanitized.isEmpty { return sanitized }
                    }
                    return nil
                }
            }
            if let text = await runUnifiedAIPrompt(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                attachments: attachments,
                routeOverride: route,
                agentTimeoutSeconds: agentTimeoutSeconds
            ) {
                return text
            }
            if route != .auto,
               let cfg = configuredConversationTextLLMConfiguration(),
               let text = await callTextLLMConfiguration(cfg, systemPrompt: systemPrompt, userPrompt: userPrompt, attachments: attachments) {
                return text
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
