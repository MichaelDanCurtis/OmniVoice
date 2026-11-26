import AppKit
import Foundation
import OmniVoiceCore

/// Coordinates Voice Command Mode using OmniSpeak's built-in in-process macOS
/// Computer-Use Driver (`NativeComputerUseDriver`: Accessibility tree + AXPress +
/// CGEvent mouse/keyboard/scroll + NSWorkspace) with **hands-free open-mic VAD
/// listening** so you never have to touch the keyboard while in Command Mode.
@MainActor
final class CommandModeController {
    private let nativeDriver = NativeComputerUseDriver()
    private let overlay = CommandModeOverlayWindow()
    private let audioCapture = AudioCaptureService()
    private weak var attachedModel: AppModel?

    private(set) var isActive = false
    private var isMicMuted = false
    private var isMicCapturing = false
    private var isExecutingCommand = false

    // VAD state for hands-free open-mic utterance segmentation
    private var speechStartedAt: TimeInterval?
    private var lastVoiceAt: TimeInterval?
    private var vadMonitorTask: Task<Void, Never>?
    private var lastLevelUIUpdate: TimeInterval = 0

    /// Provided by AppDelegate to transcribe a finished open-mic WAV utterance using
    /// the user's active ASR provider (Parakeet CoreML ANE or Engine ASR).
    var onTranscribeAudio: ((Data) async throws -> String)?

    func attach(model: AppModel) {
        attachedModel = model
        overlay.onReconnectMCP = { [weak self, weak model] in
            guard let self, let model else { return }
            self.refreshDriverStatus(model: model)
        }
        overlay.onToggleMute = { [weak self] in
            self?.toggleMute()
        }
        overlay.onCycleCorner = { [weak self, weak model] in
            guard let self, let model else { return }
            model.cycleCommandModeCorner()
            self.overlay.updateCorner(
                model.preferences.commandModeCorner,
                theme: model.activeTheme,
                appearanceMode: model.preferences.appearanceMode
            )
        }
        overlay.onExitCommandMode = { [weak self, weak model] in
            guard let self, let model else { return }
            self.exit(model: model)
        }
        overlay.onOpenCuaDocs = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func updateTheme(model: AppModel) {
        guard isActive else { return }
        overlay.updateCorner(
            model.preferences.commandModeCorner,
            theme: model.activeTheme,
            appearanceMode: model.preferences.appearanceMode
        )
    }

    func enter(model: AppModel, initialCommand: String? = nil) async {
        attachedModel = model
        isActive = true
        isMicMuted = false
        model.statusText = "Command Mode active (hands-free mic open)"
        overlay.show(
            corner: model.preferences.commandModeCorner,
            theme: model.activeTheme,
            appearanceMode: model.preferences.appearanceMode
        )
        refreshDriverStatus(model: model)
        if let initialCommand, !initialCommand.isEmpty {
            await execute(spokenCommand: initialCommand, model: model)
        }
        if isActive && !isMicMuted {
            startHandsFreeListening(model: model)
        }
    }

    func exit(model: AppModel) {
        stopHandsFreeListening()
        isActive = false
        isMicMuted = false
        overlay.hide()
        model.statusText = "Exited Command Mode"
    }

    func shutdown() {
        stopHandsFreeListening()
        isActive = false
        overlay.hide()
    }

    /// Temporarily pauses open-mic capture if the user presses the PTT hotkey manually.
    func pauseOpenMicForManualDictation() {
        guard isActive else { return }
        stopHandsFreeListening()
    }

    func resumeOpenMicIfActive() {
        guard isActive, !isMicMuted, !isExecutingCommand, !isMicCapturing, let model = attachedModel else { return }
        startHandsFreeListening(model: model)
    }

    private func toggleMute() {
        isMicMuted.toggle()
        if isMicMuted {
            stopHandsFreeListening()
            overlay.updateMicState(isOpen: false, isMuted: true, isHearingSpeech: false, level: 0)
        } else if isActive, let model = attachedModel {
            startHandsFreeListening(model: model)
        }
    }

    // MARK: - Hands-Free Open-Mic VAD

    private func startHandsFreeListening(model: AppModel) {
        stopHandsFreeListening()
        guard isActive, !isMicMuted, !isExecutingCommand else { return }

        speechStartedAt = nil
        lastVoiceAt = nil

        audioCapture.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.handleMicLevel(level)
            }
        }
        audioCapture.onPCMChunk = nil

        do {
            _ = try audioCapture.start(deviceUID: model.preferences.microphoneID)
            isMicCapturing = true
            overlay.updateMicState(isOpen: true, isMuted: false, isHearingSpeech: false, level: 0)
            startVADMonitorLoop(model: model)
        } catch {
            isMicCapturing = false
            overlay.updateMicState(isOpen: false, isMuted: false, isHearingSpeech: false, level: 0)
            overlay.appendLog(CommandModeLogEntry(
                icon: "mic.slash.fill",
                title: "Open mic unavailable",
                detail: error.localizedDescription,
                isError: true
            ))
        }
    }

    private func stopHandsFreeListening() {
        vadMonitorTask?.cancel()
        vadMonitorTask = nil
        speechStartedAt = nil
        lastVoiceAt = nil
        if isMicCapturing {
            audioCapture.onLevel = nil
            audioCapture.stop()
            isMicCapturing = false
        }
        overlay.updateMicState(isOpen: false, isMuted: isMicMuted, isHearingSpeech: false, level: 0)
    }

    private func handleMicLevel(_ level: Float) {
        guard isActive, isMicCapturing, !isExecutingCommand else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let speechThreshold: Float = 0.015

        if level >= speechThreshold {
            if speechStartedAt == nil {
                speechStartedAt = now
            }
            lastVoiceAt = now
        }

        if now - lastLevelUIUpdate >= 0.07 {
            lastLevelUIUpdate = now
            overlay.updateMicState(
                isOpen: true,
                isMuted: false,
                isHearingSpeech: speechStartedAt != nil,
                level: level
            )
        }
    }

    private func startVADMonitorLoop(model: AppModel) {
        vadMonitorTask?.cancel()
        vadMonitorTask = Task { @MainActor [weak self, weak model] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled, let self, let model,
                      self.isActive, self.isMicCapturing, !self.isExecutingCommand else {
                    break
                }

                guard let start = self.speechStartedAt, let lastVoice = self.lastVoiceAt else {
                    continue
                }

                let now = Date.timeIntervalSinceReferenceDate
                let silenceDuration = now - lastVoice
                let utteranceDuration = lastVoice - start

                // End of utterance: ~0.90s of trailing silence (or 10s max single command)
                let finishedBySilence = silenceDuration >= 0.90
                let finishedByMaxLength = (now - start) >= 10.0

                if finishedBySilence || finishedByMaxLength {
                    // Ignore tiny accidental bumps/clicks (< 0.25s)
                    if utteranceDuration < 0.25 {
                        self.speechStartedAt = nil
                        self.lastVoiceAt = nil
                        self.audioCapture.stop()
                        self.isMicCapturing = false
                        self.startHandsFreeListening(model: model)
                        return
                    }

                    await self.finalizeHandsFreeUtterance(model: model)
                    return
                }
            }
        }
    }

    private func finalizeHandsFreeUtterance(model: AppModel) async {
        vadMonitorTask?.cancel()
        vadMonitorTask = nil
        speechStartedAt = nil
        lastVoiceAt = nil

        guard isMicCapturing else { return }
        audioCapture.onLevel = nil
        let wavData = (try? audioCapture.stopWAVData()) ?? Data()
        isMicCapturing = false
        overlay.updateMicState(isOpen: false, isMuted: false, isHearingSpeech: false, level: 0)

        guard !wavData.isEmpty, let transcribe = onTranscribeAudio else {
            resumeOpenMicIfActive()
            return
        }

        overlay.setExecuting(true)
        do {
            let rawText = try await transcribe(wavData)
            let cleaned = TextInsertionEdit.sanitizedInsertionText(rawText)
            overlay.setExecuting(false)

            guard !cleaned.isEmpty else {
                resumeOpenMicIfActive()
                return
            }

            if let directive = CommandModeVoiceParser.parse(cleaned), case .exit = directive {
                RecordingCuePlayer.shared.playStopCue(preferences: model.preferences)
                exit(model: model)
                return
            }

            await execute(spokenCommand: cleaned, model: model)
        } catch {
            overlay.setExecuting(false)
        }

        resumeOpenMicIfActive()
    }

    // MARK: - Driver Status & Execution

    func refreshDriverStatus(model: AppModel) {
        let count = NativeComputerUseDriver.toolDescriptors.count
        if nativeDriver.isAccessibilityReady {
            overlay.updateNativeDriverState(ready: true, toolCount: count)
            overlay.appendLog(CommandModeLogEntry(
                icon: "bolt.horizontal.circle.fill",
                title: "Native Computer-Use Driver ready",
                detail: "Hands-free mic open · \(count) built-in macOS tools"
            ))
        } else {
            overlay.updateNativeDriverState(ready: false, toolCount: count)
            overlay.appendLog(CommandModeLogEntry(
                icon: "exclamationmark.triangle.fill",
                title: "Accessibility permission needed",
                detail: "Grant Accessibility access so OmniSpeak can inspect & click UI elements.",
                isError: true
            ))
        }
    }

    func execute(spokenCommand: String, model: AppModel) async {
        let trimmed = spokenCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isExecutingCommand = true
        overlay.setExecuting(true)
        defer {
            isExecutingCommand = false
            overlay.setExecuting(false)
        }

        overlay.appendLog(CommandModeLogEntry(
            icon: "waveform",
            title: "“\(trimmed)”",
            detail: "Inspecting active window…"
        ))

        let desktopState = nativeDriver.captureDesktopState()

        // 1. Instant zero-latency fast path for simple single-step voice commands
        if let fast = NativeDesktopFastPath.match(trimmed) {
            var args: [String: Any] = [:]
            for (k, v) in fast.stringArgs { args[k] = v }
            for (k, v) in fast.boolArgs { args[k] = v }
            for (k, v) in fast.intArgs { args[k] = v }
            for (k, v) in fast.arrayArgs { args[k] = v }

            do {
                let result = try await nativeDriver.execute(tool: fast.tool, arguments: args)
                overlay.appendLog(CommandModeLogEntry(
                    icon: "checkmark.circle.fill",
                    title: fast.tool,
                    detail: result
                ))
            } catch {
                overlay.appendLog(CommandModeLogEntry(
                    icon: "xmark.circle.fill",
                    title: "\(fast.tool) failed",
                    detail: error.localizedDescription,
                    isError: true
                ))
            }
            return
        }

        // 2. Multi-step AI tool planner using the live native Accessibility tree
        let plannerSystem = """
        You control macOS natively via OmniSpeak's built-in Computer-Use Driver.
        Translate the user's spoken request into a short JSON sequence of native tool calls.

        Available tools:
        \(NativeComputerUseDriver.toolsPromptSummary)

        Return ONLY valid JSON with this exact shape:
        {
          "summary": "Short description",
          "calls": [
            { "tool": "open_app", "arguments": { "name": "Safari" } }
          ]
        }
        Use at most 5 tool calls. When clicking a visible element from the Accessibility list, prefer `click_element` with its `id` (e.g. "e3") or `label`. Add a short `wait` (0.6s) after `open_app` before typing or clicking inside the newly focused app.
        """
        let plannerPrompt = """
        User request: "\(trimmed)"

        Live desktop state:
        \(desktopState.summary)
        """

        guard let planText = await model.planCommandModeTools(systemPrompt: plannerSystem, userPrompt: plannerPrompt) else {
            overlay.appendLog(CommandModeLogEntry(
                icon: "exclamationmark.triangle.fill",
                title: "Planner unavailable",
                detail: "Configure an AI provider or local MLX model to plan multi-step actions.",
                isError: true
            ))
            return
        }

        let calls = Self.parseToolCalls(from: planText)
        guard !calls.isEmpty else {
            overlay.appendLog(CommandModeLogEntry(
                icon: "text.bubble",
                title: "Could not map to desktop actions",
                detail: String(planText.prefix(140))
            ))
            return
        }

        for call in calls.prefix(5) {
            do {
                if call.tool == "click_element" {
                    _ = nativeDriver.captureDesktopState()
                }
                let result = try await nativeDriver.execute(tool: call.tool, arguments: call.arguments)
                overlay.appendLog(CommandModeLogEntry(
                    icon: "checkmark.circle.fill",
                    title: call.tool,
                    detail: String(result.prefix(140))
                ))
                try? await Task.sleep(for: .milliseconds(90))
            } catch {
                overlay.appendLog(CommandModeLogEntry(
                    icon: "xmark.circle.fill",
                    title: "\(call.tool) failed",
                    detail: error.localizedDescription,
                    isError: true
                ))
                break
            }
        }
    }

    private struct PlannedCall {
        let tool: String
        let arguments: [String: Any]
    }

    private static func parseToolCalls(from response: String) -> [PlannedCall] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end,
              let data = String(trimmed[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCalls = obj["calls"] as? [[String: Any]] else {
            return []
        }
        return rawCalls.compactMap { item in
            guard let name = item["tool"] as? String, !name.isEmpty else { return nil }
            let args = (item["arguments"] as? [String: Any]) ?? [:]
            return PlannedCall(tool: name, arguments: args)
        }
    }
}
