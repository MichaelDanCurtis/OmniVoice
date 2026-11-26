import AppKit
import OmniVoiceCore

/// Routes "ask <keyword> …" (and follow-ups / actions while the bubble is open) to the
/// keyword's bound provider — a local agent CLI or an engine text-LLM provider —
/// streaming/showing the answer in the Ask bubble. Conversation context is
/// OmniSpeak-managed: each turn re-sends thread history as a one-shot prompt (no ACP).
@MainActor
final class AskController {
    private let bubble = AskBubbleWindow()
    private let runner: AgentRunning = AgentRunner()
    private let insertion: TextInsertionService
    private let engineClient: EngineClient
    private var preferences = OmniVoicePreferences.defaults
    private var bindings: [AskKeywordBinding] = OmniVoicePreferences.defaultAskKeywordBindings
    private var registry = AgentRegistry(custom: [])
    private var history: [AskTurn] = []
    private var activeTarget: AskTarget?
    private var capturedTarget: TextInsertionService.Target?
    private var lastAnswer = ""
    private var runToken = 0

    /// Fires when the bubble opens (true) or closes (false). AppDelegate uses this to
    /// register/unregister the global Insert/Copy/Dismiss hotkeys only while it's up.
    var onBubbleVisibilityChanged: ((Bool) -> Void)?

    /// Entitlement gate for Ask AI. When set and returning false, a new ask/follow-up is
    /// blocked and `onAskAIPaywall` is invoked instead. Nil means "not wired yet" (allow).
    var isEntitledToAskAI: (() -> Bool)?
    var onAskAIPaywall: (() -> Void)?

    private(set) var bubbleOpen = false {
        didSet {
            if oldValue != bubbleOpen { onBubbleVisibilityChanged?(bubbleOpen) }
        }
    }

    init(insertion: TextInsertionService, engineClient: EngineClient) {
        self.insertion = insertion
        self.engineClient = engineClient
        bubble.onInsert = { [weak self] in self?.insertAnswer() }
        bubble.onCopy = { [weak self] in self?.copyAnswer() }
        bubble.onDismiss = { [weak self] in self?.dismiss() }
    }

    func updateConfiguration(_ prefs: OmniVoicePreferences) {
        preferences = prefs
        bindings = prefs.askKeywordBindings
        registry = AgentRegistry(custom: prefs.customAgents)
    }

    /// Returns true if the transcript was consumed (caller must NOT type it).
    func handle(transcript: String, captureTarget: TextInsertionService.Target?) -> Bool {
        let keywords = bindings.map(\.keyword)
        switch AskAICommandParser.parse(transcript, knownKeywords: keywords, bubbleOpen: bubbleOpen) {
        case .ask(let keyword, let question):
            if let isEntitledToAskAI, !isEntitledToAskAI() {
                onAskAIPaywall?()
                return true // consumed: don't type the "ask …" transcript
            }
            if keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ai" {
                switch preferences.defaultAIRoute {
                case .localMLX:
                    history = []
                    activeTarget = nil
                    capturedTarget = captureTarget
                    askLocalMLX(question: question)
                    return true
                case .agent(let agentID):
                    let target = AskTarget(kind: .agent, id: agentID)
                    history = []
                    activeTarget = target
                    capturedTarget = captureTarget
                    ask(target: target, question: question)
                    return true
                case .textLLM(let provider):
                    let target = AskTarget(kind: .textLLM, id: provider.rawValue)
                    history = []
                    activeTarget = target
                    capturedTarget = captureTarget
                    ask(target: target, question: question)
                    return true
                case .auto:
                    break
                }
            }
            guard let target = AskKeywordResolver.resolve(keyword, in: bindings) else { return false }
            history = []
            activeTarget = target
            capturedTarget = captureTarget
            ask(target: target, question: question)
            return true
        case .followUp(let question):
            if let isEntitledToAskAI, !isEntitledToAskAI() {
                onAskAIPaywall?()
                return true
            }
            if let target = activeTarget {
                ask(target: target, question: question)
                return true
            }
            if preferences.defaultAIRoute == .localMLX {
                askLocalMLX(question: question)
                return true
            }
            return false
        case .action(.insert): insertAnswer(); return true
        case .action(.copy): copyAnswer(); return true
        case .action(.dismiss): dismiss(); return true
        case .none:
            return false
        }
    }

    // Entry points for the global Insert/Copy/Dismiss hotkeys (no-op unless the bubble is up).
    func bubbleInsert() { guard bubbleOpen else { return }; insertAnswer() }
    func bubbleCopy() { guard bubbleOpen else { return }; copyAnswer() }
    func bubbleDismiss() { guard bubbleOpen else { return }; dismiss() }

    private func ask(target: AskTarget, question: String) {
        switch target.kind {
        case .agent:
            guard let agent = registry.all.first(where: { $0.id == target.id }) else {
                bubbleOpen = true
                bubble.show(question: question, agentName: "Agent")
                bubble.showError("Agent \"\(target.id)\" is no longer configured.")
                return
            }
            askAgent(agent, question: question)
        case .textLLM:
            askTextLLM(providerID: target.id, question: question)
        }
    }

    private func askAgent(_ agent: AgentDescriptor, question: String) {
        bubbleOpen = true
        lastAnswer = ""
        bubble.show(question: question, agentName: agent.displayName)

        let enrichedQuestion = questionWithClipboardContextIfRelevant(question)
        let prompt = AskPromptBuilder.build(history: history, question: enrichedQuestion)
        history.append(AskTurn(role: .user, text: enrichedQuestion))

        runToken += 1
        let token = runToken
        Task { @MainActor [weak self] in
            guard let self else { return }
            let onChunk: @Sendable (String) -> Void = { [weak self] chunk in
                Task { @MainActor in
                    guard let self, self.runToken == token else { return }
                    self.bubble.appendAnswer(chunk)
                }
            }
            do {
                let output: String
                if agent.supportsACP {
                    do {
                        output = try await ACPAgentPool.shared.promptWaitingForWarmup(
                            agent,
                            prompt: prompt,
                            purpose: .interactive,
                            onChunk: onChunk
                        )
                    } catch {
                        guard self.runToken == token else { return }
                        output = try await self.runner.run(agent, prompt: prompt, onChunk: onChunk)
                    }
                } else {
                    output = try await self.runner.run(agent, prompt: prompt, onChunk: onChunk)
                }
                guard self.runToken == token else { return }
                self.bubble.setStreaming(false)
                self.lastAnswer = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.history.append(AskTurn(role: .assistant, text: self.lastAnswer))
            } catch AgentRunError.notFound {
                guard self.runToken == token else { return }
                self.bubble.showError("\(agent.displayName) CLI not found. Set its path in Settings → AI.")
            } catch AgentRunError.failed(let message) {
                guard self.runToken == token else { return }
                self.bubble.showError("Couldn't reach \(agent.displayName). Run `\(agent.binaryName)` once in a terminal to sign in.\n\(message)")
            } catch {
                guard self.runToken == token else { return }
                self.bubble.showError("\(error)")
            }
        }
    }

    private func askTextLLM(providerID: String, question: String) {
        guard let kind = TextLLMProviderKind(rawValue: providerID) else { return }
        let config = preferences.textLLMConfiguration(for: kind)
        bubbleOpen = true
        lastAnswer = ""
        bubble.show(question: question, agentName: kind.displayName)
        guard config.isConfigured else {
            bubble.showError("Configure \(kind.displayName) in Settings → AI.")
            return
        }
        let enrichedQuestion = questionWithClipboardContextIfRelevant(question)
        let prompt = AskPromptBuilder.build(history: history, question: enrichedQuestion)
        history.append(AskTurn(role: .user, text: enrichedQuestion))
        runToken += 1
        let token = runToken
        Task { @MainActor in
            do {
                let result = try await engineClient.aiHandoff(AIHandoffRequest(
                    prompt: prompt,
                    provider: config.provider.rawValue,
                    baseURL: config.resolvedBaseURL,
                    model: config.trimmedModel,
                    apiKey: config.trimmedAPIKey,
                    transport: config.transport,
                    oauthAccessToken: config.trimmedOAuthAccessToken,
                    headers: config.resolvedHeaders,
                    context: ""))
                guard runToken == token else { return }
                let text = TextInsertionEdit.sanitizedInsertionText(result.text)
                bubble.setStreaming(false)
                bubble.appendAnswer(text)
                lastAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                history.append(AskTurn(role: .assistant, text: lastAnswer))
            } catch {
                guard runToken == token else { return }
                bubble.showError("\(kind.displayName) failed: \(error.localizedDescription)")
            }
        }
    }

    private func askLocalMLX(question: String) {
        let modelName = CleanupModelRecommendation(providerID: preferences.llmCleanupLocalModelID).displayName
        bubbleOpen = true
        lastAnswer = ""
        bubble.show(question: question, agentName: "Local MLX (\(modelName))")

        let enrichedQuestion = questionWithClipboardContextIfRelevant(question)
        let prompt = AskPromptBuilder.build(history: history, question: enrichedQuestion)
        history.append(AskTurn(role: .user, text: enrichedQuestion))
        runToken += 1
        let token = runToken
        let providerID = preferences.llmCleanupLocalModelID
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await MLXLocalCleanupService.shared.generateRaw(
                    instructions: "You are a concise, helpful macOS assistant. Answer directly without preamble.",
                    prompt: prompt,
                    maxTokens: 768,
                    providerID: providerID
                )
                guard self.runToken == token else { return }
                let text = TextInsertionEdit.sanitizedInsertionText(output)
                self.bubble.setStreaming(false)
                self.bubble.appendAnswer(text)
                self.lastAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.history.append(AskTurn(role: .assistant, text: self.lastAnswer))
            } catch {
                guard self.runToken == token else { return }
                self.bubble.showError("Local MLX failed: \(error.localizedDescription)")
            }
        }
    }

    private func insertAnswer() {
        guard !lastAnswer.isEmpty else { return }
        copyAnswer()
        let text = lastAnswer
        let target = capturedTarget
        Task { @MainActor in
            do {
                try await insertion.insert(text, target: target)
                bubble.markInserted()
            } catch {
                // copyAnswer() already put it on the clipboard — tell the user to paste it
                // rather than claiming "Inserted" when the insert actually failed.
                bubble.markInsertFailed()
            }
        }
    }

    private func copyAnswer() {
        guard !lastAnswer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAnswer, forType: .string)
    }

    private func dismiss() {
        bubbleOpen = false
        runToken += 1   // cancel any in-flight run
        bubble.hide()
    }

    private func questionWithClipboardContextIfRelevant(_ question: String) -> String {
        guard preferences.clipboardAskContextEnabled else { return question }
        let lower = question.lowercased()
        let contextCues = [
            "this", "clipboard", "copied", "paste", "error", "crash", "stack trace",
            "log", "code", "above", "summarize", "explain", "fix", "review", "translate",
        ]
        guard contextCues.contains(where: { lower.contains($0) }) else {
            return question
        }
        guard let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboard.isEmpty else {
            return question
        }
        let clipped = clipboard.count > 4_000 ? String(clipboard.prefix(4_000)) + "\n…[truncated]" : clipboard
        return "\(question)\n\nClipboard context:\n\(clipped)"
    }
}
