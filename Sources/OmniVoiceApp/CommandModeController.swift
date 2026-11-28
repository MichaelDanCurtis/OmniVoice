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
    private let targetHighlight = CommandTargetHighlightWindow()
    private let audioCapture = AudioCaptureService()
    private weak var attachedModel: AppModel?

    private(set) var isActive = false
    private var isMicMuted = false
    private var isMicCapturing = false
    private var isExecutingCommand = false

    // VAD state for hands-free open-mic utterance segmentation
    private var speechStartedAt: TimeInterval?
    private var lastVoiceAt: TimeInterval?
    private var ambientNoiseFloor: Float = 0.004
    private var vadMonitorTask: Task<Void, Never>?
    private var activeUtteranceTask: Task<Void, Never>?
    private var lastLevelUIUpdate: TimeInterval = 0

    /// Provided by AppDelegate to transcribe a finished open-mic WAV utterance using
    /// the user's active ASR provider (Deepgram, Parakeet CoreML ANE, or Engine ASR).
    var onTranscribeAudio: ((Data) async throws -> String)?
    /// Notifies AppModel/UI when Command Mode activates or exits.
    var onActiveStateChanged: ((Bool) -> Void)?

    func attach(model: AppModel) {
        attachedModel = model
        nativeDriver.onVisualTarget = { [weak self, weak model] rect, label in
            guard let self, let model else { return }
            self.targetHighlight.flash(axRect: rect, label: label, theme: model.activeTheme)
        }
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
        onActiveStateChanged?(true)
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
        activeUtteranceTask?.cancel()
        activeUtteranceTask = nil
        stopHandsFreeListening()
        isActive = false
        isMicMuted = false
        onActiveStateChanged?(false)
        overlay.hide()
        model.statusText = "Exited Command Mode"
    }

    func shutdown() {
        activeUtteranceTask?.cancel()
        activeUtteranceTask = nil
        stopHandsFreeListening()
        isActive = false
        onActiveStateChanged?(false)
        overlay.hide()
    }

    /// Temporarily pauses open-mic capture if the user presses the PTT hotkey manually.
    func pauseOpenMicForManualDictation() {
        guard isActive else { return }
        activeUtteranceTask?.cancel()
        activeUtteranceTask = nil
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
        ambientNoiseFloor = 0.004

        audioCapture.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.handleMicLevel(level)
            }
        }
        audioCapture.onPCMChunk = nil
        audioCapture.onPCM16Chunk = nil

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

        // Adaptive threshold: works for both quiet studio mics and rooms with light fan noise.
        let triggerThreshold = max(Float(0.0075), min(Float(0.035), ambientNoiseFloor * 2.6))
        let holdThreshold = max(Float(0.0055), triggerThreshold * 0.72)
        let activeThreshold = speechStartedAt == nil ? triggerThreshold : holdThreshold

        if level >= activeThreshold {
            if speechStartedAt == nil {
                speechStartedAt = now
            }
            lastVoiceAt = now
        } else if speechStartedAt == nil {
            // Smoothly track ambient noise floor while waiting for speech.
            ambientNoiseFloor = ambientNoiseFloor * 0.92 + level * 0.08
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
                    // Keep only a tight 0.55s pre-roll buffer while waiting for speech so
                    // ASR never receives 30+ seconds of dead leading silence!
                    self.audioCapture.trimToTrailingSeconds(0.55)
                    continue
                }

                let now = Date.timeIntervalSinceReferenceDate
                let silenceDuration = now - lastVoice
                let utteranceDuration = lastVoice - start

                // End of utterance: ~0.80s of trailing silence (or 10s max single command)
                let finishedBySilence = silenceDuration >= 0.80
                let finishedByMaxLength = (now - start) >= 10.0

                if finishedBySilence || finishedByMaxLength {
                    // Ignore tiny accidental bumps/clicks (< 0.22s)
                    if utteranceDuration < 0.22 {
                        self.speechStartedAt = nil
                        self.lastVoiceAt = nil
                        self.audioCapture.trimToTrailingSeconds(0.35)
                        continue
                    }

                    // Detach utterance finalization into its own uncancelled task so stopping the
                    // VAD monitor loop can NEVER cancel the transcription or tool execution!
                    self.vadMonitorTask = nil
                    self.activeUtteranceTask?.cancel()
                    self.activeUtteranceTask = Task { @MainActor [weak self, weak model] in
                        guard let self, let model else { return }
                        await self.finalizeHandsFreeUtterance(model: model)
                    }
                    return
                }
            }
        }
    }

    private func finalizeHandsFreeUtterance(model: AppModel) async {
        defer { activeUtteranceTask = nil }
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
            guard !Task.isCancelled, isActive else {
                overlay.setExecuting(false)
                return
            }
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
        } catch is CancellationError {
            overlay.setExecuting(false)
            return
        } catch {
            overlay.setExecuting(false)
            overlay.appendLog(CommandModeLogEntry(
                icon: "exclamationmark.triangle.fill",
                title: "Transcription failed",
                detail: error.localizedDescription,
                isError: true
            ))
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

        // 0. Instant voice summon for the Ember agent ("Ember", "Call Ember", "Talk to Ember")
        if let emberSummon = EmberVoiceCommandParser.parse(trimmed) {
            let summary = await model.summonEmber(initialMessage: emberSummon.initialMessage)
            overlay.appendLog(CommandModeLogEntry(
                icon: summary.contains("isn't installed") ? "exclamationmark.triangle.fill" : "flame.fill",
                title: "Ember",
                detail: summary,
                isError: summary.contains("isn't installed")
            ))
            return
        }

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
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if let fenceEnd = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<fenceEnd.lowerBound])
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try direct decode first, then scan balanced top-level JSON objects containing "calls".
        if let direct = decodeCalls(from: cleaned), !direct.isEmpty {
            return direct
        }
        var depth = 0
        var inString = false
        var escaped = false
        var startIdx: String.Index?
        for idx in cleaned.indices {
            let ch = cleaned[idx]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" {
                inString = true
            } else if ch == "{" {
                if depth == 0 { startIdx = idx }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let s = startIdx {
                    if let parsed = decodeCalls(from: String(cleaned[s...idx])), !parsed.isEmpty {
                        return parsed
                    }
                    startIdx = nil
                }
            }
        }
        return []
    }

    private static func decodeCalls(from jsonText: String) -> [PlannedCall]? {
        guard let data = jsonText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCalls = obj["calls"] as? [[String: Any]] else {
            return nil
        }
        return rawCalls.compactMap { item in
            guard let name = item["tool"] as? String, !name.isEmpty else { return nil }
            let args = (item["arguments"] as? [String: Any]) ?? [:]
            return PlannedCall(tool: name, arguments: args)
        }
    }
}
