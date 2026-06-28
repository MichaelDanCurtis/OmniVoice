import AppKit
import OmniVoiceCore

/// Routes "ask <agent> …" voice commands (and follow-ups / actions while the bubble
/// is open) to a local agent CLI, streams the answer into the Ask bubble, and inserts
/// it at the captured cursor on request. Conversation context is OmniVoice-managed:
/// each turn re-sends the thread history as a one-shot prompt (no ACP).
@MainActor
final class AskController {
    private let bubble = AskBubbleWindow()
    private let runner: AgentRunning = AgentRunner()
    private let insertion: TextInsertionService
    private var registry = AgentRegistry(custom: [])
    private var history: [AskTurn] = []
    private var activeAgent: AgentDescriptor?
    private var capturedTarget: TextInsertionService.Target?
    private var lastAnswer = ""
    private var runToken = 0

    private(set) var bubbleOpen = false

    init(insertion: TextInsertionService) {
        self.insertion = insertion
        bubble.onInsert = { [weak self] in self?.insertAnswer() }
        bubble.onCopy = { [weak self] in self?.copyAnswer() }
        bubble.onDismiss = { [weak self] in self?.dismiss() }
    }

    func updateAgents(_ custom: [AgentConfiguration]) {
        registry = AgentRegistry(custom: custom)
    }

    /// Returns true if the transcript was consumed as an Ask command/follow-up/action
    /// (so the caller must NOT type it as dictation).
    func handle(transcript: String, captureTarget: TextInsertionService.Target?) -> Bool {
        let keywords = registry.all.flatMap(\.keywords)
        switch AskAICommandParser.parse(transcript, knownKeywords: keywords, bubbleOpen: bubbleOpen) {
        case .ask(let keyword, let question):
            guard let agent = registry.resolve(keyword: keyword) else { return false }
            history = []
            activeAgent = agent
            capturedTarget = captureTarget
            ask(agent: agent, question: question)
            return true
        case .followUp(let question):
            guard let agent = activeAgent else { return false }
            ask(agent: agent, question: question)
            return true
        case .action(.insert):
            insertAnswer(); return true
        case .action(.copy):
            copyAnswer(); return true
        case .action(.dismiss):
            dismiss(); return true
        case .none:
            return false
        }
    }

    private func ask(agent: AgentDescriptor, question: String) {
        bubbleOpen = true
        lastAnswer = ""
        bubble.show(question: question, agentName: agent.displayName)

        let prompt = AskPromptBuilder.build(history: history, question: question)
        history.append(AskTurn(role: .user, text: question))

        runToken += 1
        let token = runToken
        Task { @MainActor in
            do {
                let output = try await runner.run(agent, prompt: prompt) { [weak self] chunk in
                    Task { @MainActor in
                        guard let self, self.runToken == token else { return }
                        self.bubble.appendAnswer(chunk)
                    }
                }
                guard runToken == token else { return }
                bubble.setStreaming(false)
                lastAnswer = output.trimmingCharacters(in: .whitespacesAndNewlines)
                bubble.appendAnswer("")   // flush
                history.append(AskTurn(role: .assistant, text: lastAnswer))
            } catch AgentRunError.notFound {
                guard runToken == token else { return }
                bubble.showError("\(agent.displayName) CLI not found. Set its path in Settings → Ask AI agents.")
            } catch AgentRunError.failed(let message) {
                guard runToken == token else { return }
                bubble.showError("Couldn't reach \(agent.displayName). Run `\(agent.binaryName)` once in a terminal to sign in.\n\(message)")
            } catch {
                guard runToken == token else { return }
                bubble.showError("\(error)")
            }
        }
    }

    private func insertAnswer() {
        guard !lastAnswer.isEmpty else { return }
        copyAnswer()
        let text = lastAnswer
        let target = capturedTarget
        bubble.markInserted()
        Task { @MainActor in try? await insertion.insert(text, target: target) }
    }

    private func copyAnswer() {
        guard !lastAnswer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAnswer, forType: .string)
    }

    private func dismiss() {
        bubbleOpen = false
        runToken += 1   // cancel any in-flight streaming
        bubble.hide()
    }
}
