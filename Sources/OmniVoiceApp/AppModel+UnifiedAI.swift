import Foundation
import OmniVoiceCore

enum UnifiedAIError: LocalizedError {
    case providerNotConfigured(String)
    case agentNotFound(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let name):
            "\(name) is not configured yet. Configure it in Settings → AI."
        case .agentNotFound(let id):
            "AI Agent \"\(id)\" was not found on PATH. Check Settings → AI → Agent configurations."
        case .emptyResponse:
            "The AI engine returned an empty response."
        }
    }
}

/// Single source of truth for AI routing and execution across OmniSpeak:
/// Dictation Cleanup, Ask AI (voice + workspace), Conversation Chat & Insights,
/// Meeting Co-Pilot, Editor AI, Translation, Voice Edit, Command Mode, and Service Mode.
extension AppModel {
    var defaultAIRoute: UnifiedAIRoute {
        preferences.defaultAIRoute
    }

    var activeUnifiedAILabel: String {
        unifiedAIRouteLabel(preferences.defaultAIRoute)
    }

    var resolvedUnifiedAILabel: String {
        concreteAIRouteLabel(resolvedUnifiedAIRoute())
    }

    func agentDisplayName(for agentID: String) -> String {
        let registry = AgentRegistry(custom: preferences.customAgents)
        return registry.all.first(where: { $0.id == agentID })?.displayName ?? agentID
    }

    func concreteAIRouteLabel(_ route: UnifiedAIRoute) -> String {
        switch route {
        case .auto:
            let resolved = resolvedUnifiedAIRoute(override: .auto)
            return resolved == .auto ? "Auto" : concreteAIRouteLabel(resolved)
        case .agent(let agentID):
            return "\(agentDisplayName(for: agentID)) (Agent)"
        case .textLLM(let provider):
            return preferences.textLLMConfiguration(for: provider).displayName
        case .localMLX:
            let modelName = CleanupModelRecommendation(providerID: preferences.llmCleanupLocalModelID).displayName
            return "Local MLX (\(modelName))"
        }
    }

    func unifiedAIRouteLabel(_ route: UnifiedAIRoute) -> String {
        switch route {
        case .auto:
            return "Auto (\(concreteAIRouteLabel(resolvedUnifiedAIRoute(override: .auto))))"
        case .agent, .textLLM, .localMLX:
            return concreteAIRouteLabel(route)
        }
    }

    /// Resolves `.auto` (or an optional override) into a concrete executable AI route.
    func resolvedUnifiedAIRoute(override: UnifiedAIRoute? = nil) -> UnifiedAIRoute {
        let chosen = override ?? preferences.defaultAIRoute
        if chosen != .auto {
            return chosen
        }
        if let configured = configuredTextLLMConfiguration() {
            return .textLLM(provider: configured.provider)
        }
        if let firstAgent = discoveredAgents.first {
            return .agent(agentID: firstAgent.id)
        }
        return .localMLX
    }

    func isUnifiedAIRouteReady(_ route: UnifiedAIRoute) -> Bool {
        switch resolvedUnifiedAIRoute(override: route) {
        case .textLLM(let provider):
            return preferences.textLLMConfiguration(for: provider).isConfigured
        case .agent(let agentID):
            let registry = AgentRegistry(custom: preferences.customAgents)
            return registry.all.contains(where: { $0.id == agentID }) || !discoveredAgents.isEmpty
        case .localMLX:
            return true
        case .auto:
            return true
        }
    }

    func setDefaultAIRoute(_ route: UnifiedAIRoute) {
        preferences.defaultAIRoute = route
        // Keep Dictation Cleanup and Service Mode aligned with the unified AI Configuration
        // so stale per-feature overrides don't silently hijack LLM routing.
        preferences.llmCleanupBackend = .aiConfiguration
        preferences.serviceMode.llmRoute = .auto

        switch route {
        case .textLLM(let provider):
            preferences.textLLMDefaultProvider = provider
            syncDefaultAskKeywordBinding(target: AskTarget(kind: .textLLM, id: provider.rawValue))
        case .agent(let agentID):
            preferences.llmCleanupAgentID = agentID
            syncDefaultAskKeywordBinding(target: AskTarget(kind: .agent, id: agentID))
        case .auto:
            let resolved = resolvedUnifiedAIRoute(override: .auto)
            switch resolved {
            case .textLLM(let provider):
                syncDefaultAskKeywordBinding(target: AskTarget(kind: .textLLM, id: provider.rawValue))
            case .agent(let agentID):
                syncDefaultAskKeywordBinding(target: AskTarget(kind: .agent, id: agentID))
            case .localMLX, .auto:
                break
            }
        case .localMLX:
            break
        }

        guard persistPreferences() else { return }
        onCustomAgentsChanged?(preferences.customAgents)
        statusText = "Default AI → \(unifiedAIRouteLabel(route))"
        warmUpConfiguredACPAgents()
    }

    static func acpStateKey(agentID: String, purpose: ACPSessionPurpose) -> String {
        "\(agentID):\(purpose.rawValue)"
    }

    func acpState(for agentID: String, purpose: ACPSessionPurpose = .cleanup) -> ACPWorkerState {
        acpWorkerStates[Self.acpStateKey(agentID: agentID, purpose: purpose)] ?? .idle
    }

    /// Returns the descriptor for whichever agent will currently handle Dictation Cleanup, if any.
    func activeCleanupAgentDescriptor() -> AgentDescriptor? {
        let registry = AgentRegistry(custom: preferences.customAgents)
        if preferences.serviceMode.enabled {
            switch preferences.serviceMode.llmRoute {
            case .subscriptionAgent(let agentID):
                return registry.all.first(where: { $0.id == agentID }) ?? discoveredAgents.first?.descriptor
            case .configuredTextLLM:
                return nil
            case .auto:
                break
            }
        }
        switch preferences.llmCleanupBackend {
        case .agent:
            return registry.all.first(where: { $0.id == preferences.llmCleanupAgentID }) ?? discoveredAgents.first?.descriptor
        case .aiConfiguration:
            if case .agent(let agentID) = resolvedUnifiedAIRoute() {
                return registry.all.first(where: { $0.id == agentID }) ?? discoveredAgents.first?.descriptor
            }
            return nil
        case .localMLX, .textLLM:
            return nil
        }
    }

    /// True when Dictation Cleanup targets an ACP agent whose warm-up is not yet ready
    /// (so the current dictation will skip editing and paste immediately).
    var isActiveCleanupAgentColdACP: Bool {
        guard preferences.llmCleanupEnabled,
              let descriptor = activeCleanupAgentDescriptor(),
              descriptor.supportsACP else {
            return false
        }
        return !acpState(for: descriptor.id, purpose: .cleanup).isReady
    }

    /// Proactively warms ACP workers in the background for whichever ACP-capable agent(s)
    /// are currently selected in AI Configuration, Cleanup, or Service Mode, and shuts down
    /// unused ACP workers so idle background processes don't linger.
    func warmUpConfiguredACPAgents() {
        let registry = AgentRegistry(custom: preferences.customAgents)
        var cleanupDescriptor: AgentDescriptor?
        var interactiveDescriptor: AgentDescriptor?

        if preferences.llmCleanupEnabled {
            if let desc = activeCleanupAgentDescriptor(), desc.supportsACP {
                cleanupDescriptor = desc
            }
        }
        if case .agent(let agentID) = resolvedUnifiedAIRoute(),
           let desc = registry.all.first(where: { $0.id == agentID }) ?? discoveredAgents.first?.descriptor,
           desc.supportsACP {
            interactiveDescriptor = desc
        }

        var activeIDs: Set<String> = []
        if let d = cleanupDescriptor { activeIDs.insert(d.id) }
        if let d = interactiveDescriptor { activeIDs.insert(d.id) }

        let cleanupToWarm = cleanupDescriptor
        let interactiveToWarm = interactiveDescriptor
        Task {
            await ACPAgentPool.shared.shutdownExcept(agentIDs: activeIDs)
            if let cleanupToWarm {
                await ACPAgentPool.shared.warmUpIfSupported(cleanupToWarm, purpose: .cleanup)
            }
            if let interactiveToWarm {
                await ACPAgentPool.shared.warmUpIfSupported(interactiveToWarm, purpose: .interactive)
            }
        }
    }

    func setDefaultAICategory(_ category: UnifiedAIRoute.Category) {
        switch category {
        case .auto:
            setDefaultAIRoute(.auto)
        case .agent:
            if case .agent = preferences.defaultAIRoute { return }
            let preferredID = discoveredAgents.first?.id
                ?? (preferences.llmCleanupAgentID.isEmpty ? "antigravity" : preferences.llmCleanupAgentID)
            setDefaultAIRoute(.agent(agentID: preferredID))
        case .textLLM:
            if case .textLLM = preferences.defaultAIRoute { return }
            let preferredProvider = configuredTextLLMConfiguration()?.provider
                ?? preferences.textLLMDefaultProvider
            setDefaultAIRoute(.textLLM(provider: preferredProvider))
        case .localMLX:
            setDefaultAIRoute(.localMLX)
        }
    }

    func syncDefaultAskKeywordBinding(target: AskTarget) {
        if let idx = preferences.askKeywordBindings.firstIndex(where: {
            $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ai"
        }) {
            preferences.askKeywordBindings[idx].target = target
        } else {
            preferences.askKeywordBindings.insert(
                AskKeywordBinding(id: "builtin-ai", keyword: "ai", target: target),
                at: 0
            )
        }
    }

    /// Executes an AI chat / generation request through the unified AI route
    /// (API / OAuth provider, installed AI Agent CLI, or built-in Local MLX).
    func runUnifiedAI(
        messages: [AIChatMessage],
        attachments: [AIChatAttachment] = [],
        webSearchEnabled: Bool = false,
        routeOverride: UnifiedAIRoute? = nil,
        modelOverride: String? = nil,
        agentTimeoutSeconds: Double? = nil
    ) async throws -> String {
        let resolved = resolvedUnifiedAIRoute(override: routeOverride)
        switch resolved {
        case .textLLM(let provider):
            var configuration = preferences.textLLMConfiguration(for: provider)
            if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                configuration.model = model
            }
            if !configuration.isConfigured {
                if routeOverride == nil, let fallback = configuredTextLLMConfiguration() {
                    configuration = fallback
                } else {
                    throw UnifiedAIError.providerNotConfigured(configuration.displayName)
                }
            }
            let normalized = configuration.normalized()
            let result = try await engineClient.aiChat(
                AIChatRequest(
                    provider: normalized.provider.rawValue,
                    baseURL: normalized.resolvedBaseURL,
                    model: normalized.trimmedModel,
                    apiKey: normalized.trimmedAPIKey,
                    transport: normalized.transport,
                    oauthAccessToken: normalized.trimmedOAuthAccessToken,
                    headers: normalized.resolvedHeaders,
                    messages: messages,
                    attachments: attachments,
                    webSearchEnabled: webSearchEnabled
                )
            )
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw UnifiedAIError.emptyResponse }
            return trimmed

        case .agent(let agentID):
            let registry = AgentRegistry(custom: preferences.customAgents)
            let descriptor = registry.all.first(where: { $0.id == agentID })
                ?? (routeOverride == nil ? discoveredAgents.first?.descriptor : nil)
            guard let descriptor else {
                throw UnifiedAIError.agentNotFound(agentID)
            }
            let prompt = Self.formatPromptForUnifiedCLI(messages: messages, attachments: attachments)
            let output: String
            if descriptor.supportsACP,
               let acpOutput = try? await ACPAgentPool.shared.promptWaitingForWarmup(
                   descriptor,
                   prompt: prompt,
                   purpose: .interactive,
                   timeoutSeconds: agentTimeoutSeconds
               ) {
                output = acpOutput
            } else {
                output = try await meetingAgentRunner.run(
                    descriptor,
                    prompt: prompt,
                    timeoutSeconds: agentTimeoutSeconds,
                    onChunk: { _ in }
                )
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw UnifiedAIError.emptyResponse }
            return trimmed

        case .localMLX, .auto:
            let systemParts = messages.filter { $0.role == .system }.map(\.content)
            let instructions = systemParts.isEmpty
                ? "You are a helpful, concise assistant."
                : systemParts.joined(separator: "\n\n")
            let nonSystem = messages.filter { $0.role != .system }
            let prompt = Self.formatPromptForUnifiedCLI(messages: nonSystem, attachments: attachments)
            let output = try await MLXLocalCleanupService.shared.generateRaw(
                instructions: instructions,
                prompt: prompt,
                maxTokens: 768,
                providerID: preferences.llmCleanupLocalModelID
            )
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw UnifiedAIError.emptyResponse }
            return trimmed
        }
    }

    /// Convenience helper for single-shot system + user prompts (cleanup, meeting insights,
    /// translation, Voice Edit, Command Mode planning).
    func runUnifiedAIPrompt(
        systemPrompt: String,
        userPrompt: String,
        attachments: [AIChatAttachment] = [],
        webSearchEnabled: Bool = false,
        routeOverride: UnifiedAIRoute? = nil,
        agentTimeoutSeconds: Double? = nil,
        sanitize: Bool = true
    ) async -> String? {
        do {
            let output = try await runUnifiedAI(
                messages: [
                    AIChatMessage(role: .system, content: systemPrompt),
                    AIChatMessage(role: .user, content: userPrompt),
                ],
                attachments: attachments,
                webSearchEnabled: webSearchEnabled,
                routeOverride: routeOverride,
                agentTimeoutSeconds: agentTimeoutSeconds
            )
            let final = sanitize ? MLXLocalCleanupService.sanitizeOutput(output) : output
            return final.isEmpty ? nil : final
        } catch {
            return nil
        }
    }

    /// Runs Dictation Cleanup through a resolved concrete `UnifiedAIRoute`.
    func runDictationCleanup(
        via route: UnifiedAIRoute,
        rawTranscript: String,
        style: StyleProfile,
        appContext: String,
        dictionaryTerms: [String]? = nil
    ) async throws -> CleanupResult? {
        let effectiveDictionaryTerms = dictionaryTerms ?? preferences.dictionaryTerms
        let instructions = MLXLocalCleanupService.systemPrompt(
            style: style,
            dictionaryTerms: effectiveDictionaryTerms,
            appContext: appContext
        )

        switch route {
        case .agent(let agentID):
            let registry = AgentRegistry(custom: preferences.customAgents)
            guard let descriptor = registry.all.first(where: { $0.id == agentID })
                ?? discoveredAgents.first?.descriptor else {
                return nil
            }
            let prompt = "\(instructions)\n\nTranscript:\n\(rawTranscript)"
            if descriptor.supportsACP {
                // Zero-wait cold start: if ACP is still booting for the first time, kick off
                // background warm-up and return nil immediately so dictation pastes as-is
                // with zero cold-start delay.
                if let output = await ACPAgentPool.shared.promptIfReady(
                    descriptor,
                    prompt: prompt,
                    purpose: .cleanup,
                    timeoutSeconds: 8.5
                ) {
                    let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                    if !sanitized.isEmpty {
                        return CleanupResult(
                            text: sanitized,
                            cleanupApplied: true,
                            llmApplied: true,
                            llmFallbackReason: nil
                        )
                    }
                }
                return nil
            }
            if let output = try? await meetingAgentRunner.run(
                descriptor,
                prompt: prompt,
                timeoutSeconds: 5.0,
                onChunk: { _ in }
            ) {
                let sanitized = MLXLocalCleanupService.sanitizeOutput(output)
                if !sanitized.isEmpty {
                    return CleanupResult(
                        text: sanitized,
                        cleanupApplied: true,
                        llmApplied: true,
                        llmFallbackReason: nil
                    )
                }
            }
            return nil

        case .localMLX:
            do {
                let cleaned = try await MLXLocalCleanupService.shared.cleanup(
                    rawTranscript: rawTranscript,
                    style: style,
                    dictionaryTerms: effectiveDictionaryTerms,
                    appContext: appContext,
                    providerID: preferences.llmCleanupLocalModelID
                )
                return CleanupResult(
                    text: cleaned,
                    cleanupApplied: true,
                    llmApplied: true,
                    llmFallbackReason: nil
                )
            } catch {
                return nil
            }

        case .textLLM(let provider):
            let cfg = preferences.textLLMConfiguration(for: provider)
            guard cfg.isConfigured else { return nil }
            let llmConfig = CleanupLLMConfig(
                enabled: true,
                provider: provider.rawValue,
                baseURL: cfg.resolvedBaseURL,
                model: cfg.trimmedModel,
                apiKey: cfg.trimmedAPIKey,
                transport: cfg.transport,
                oauthAccessToken: cfg.trimmedOAuthAccessToken,
                headers: cfg.resolvedHeaders,
                timeoutSeconds: 8.0
            )
            let result = try await engineClient.cleanup(
                CleanupRequest(
                    rawTranscript: rawTranscript,
                    style: style,
                    dictionaryTerms: effectiveDictionaryTerms,
                    dictionaryEntries: CleanupRequest.entries(from: preferences.dictionaryEntries),
                    appContext: appContext,
                    llm: llmConfig
                )
            )
            return result.llmApplied ? result : nil

        case .auto:
            return try await runDictationCleanup(
                via: resolvedUnifiedAIRoute(override: .auto),
                rawTranscript: rawTranscript,
                style: style,
                appContext: appContext,
                dictionaryTerms: effectiveDictionaryTerms
            )
        }
    }

    static func formatPromptForUnifiedCLI(
        messages: [AIChatMessage],
        attachments: [AIChatAttachment]
    ) -> String {
        var sections: [String] = []

        if !attachments.isEmpty {
            var attachmentBlocks: [String] = []
            for attachment in attachments {
                let text = attachment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    attachmentBlocks.append("### \(attachment.title)\n\(text)")
                } else if attachment.mimeType.hasPrefix("image/") {
                    attachmentBlocks.append("### \(attachment.title)\n[Image attachment: \(attachment.mimeType)]")
                } else {
                    attachmentBlocks.append("### \(attachment.title)\n[\(attachment.kind) attachment]")
                }
            }
            if !attachmentBlocks.isEmpty {
                sections.append("Context Attachments:\n\n" + attachmentBlocks.joined(separator: "\n\n"))
            }
        }

        if messages.count == 1, let only = messages.first {
            sections.append(only.content)
        } else if messages.count == 2, messages[0].role == .system, messages[1].role == .user {
            sections.append(messages[0].content)
            sections.append(messages[1].content)
        } else {
            let formatted = messages.map { message -> String in
                switch message.role {
                case .system:
                    return "Instructions:\n\(message.content)"
                case .user:
                    return "User: \(message.content)"
                case .assistant:
                    return "Assistant: \(message.content)"
                }
            }.joined(separator: "\n\n")
            sections.append(formatted)
        }

        return sections.joined(separator: "\n\n")
    }
}
