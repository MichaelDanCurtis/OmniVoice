import AppKit
import AVFoundation
import OmniVoiceCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionLogger = Logger(subsystem: "com.omnivoice.OmniVoiceApp", category: "Permissions")
    private weak var model: AppModel?
    private let overlay = CaptionOverlayWindow()
    private let hotkeys = HotkeyController()
    private let audioCapture = AudioCaptureService()
    private let engineClient = EngineClient()
    private let streamingClient = EngineStreamingClient()
    private let insertionService = TextInsertionService()
    private let commandExecutor = DictationCommandExecutor()
    private var lastInputLevel: Float = 0
    private var lastLevelOverlayUpdate = Date.distantPast
    private var insertionTarget: TextInsertionService.Target?
    private var liveDraft: TextInsertionService.LiveDraft?
    private var didPromptForAccessibility = false
    private var permissionRefreshTimer: Timer?
    private var lastLoggedMicStatus: AVAuthorizationStatus?
    private var lastLoggedAccessibilityEnabled: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRefreshTimer?.invalidate()
        hotkeys.unregister()
        EngineSupervisor.shared.stopStartedProcess()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updatePermissionStatus()
    }

    func attach(model: AppModel) {
        self.model = model
        updatePermissionStatus()

        hotkeys.onEvent = { [weak self] event in
            self?.handleHotkey(event)
        }
        model.onHotkeysChanged = { [weak self] preferences in
            self?.applyHotkeys(preferences: preferences)
        }
        streamingClient.setOnDiagnostics { [weak self] diagnostics in
            Task { @MainActor [weak self] in
                self?.model?.streamingDiagnostics = diagnostics
            }
        }

        startPermissionRefreshTimer()
        applyHotkeys(preferences: model.preferences)
    }

    func refreshPermissionStatus() {
        updatePermissionStatus()
    }

    func requestAccessibilityPermission() {
        didPromptForAccessibility = true
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updatePermissionStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.updatePermissionStatus()
        }
    }

    func showOverlay(
        text: String,
        styleName: String,
        level: Float = 0,
        theme: OmniVoiceTheme? = nil,
        anchorFrame: CGRect? = nil
    ) {
        overlay.show(
            text: text,
            styleName: styleName,
            level: level,
            theme: theme ?? model?.activeTheme ?? .defaultTheme,
            anchorFrame: anchorFrame
        )
    }

    func hideOverlay() {
        overlay.hide()
    }

    func commitOverlayAnimation() {
        overlay.commitAndHide(mode: model?.activeTheme.commitAnimationMode ?? .glyphStream)
    }

    func insertTextAtCurrentCursor(_ text: String) async {
        guard let model else { return }

        let target = insertionService.captureTarget()
        do {
            try await insertionService.insert(text, target: target)
            model.statusText = "Transcript inserted"
        } catch TextInsertionService.InsertionError.accessibilityPermissionRequired {
            copyToPasteboard(text)
            model.statusText = "Accessibility required - copied"
            if !didPromptForAccessibility {
                requestAccessibilityPermission()
            }
        } catch {
            copyToPasteboard(text)
            model.statusText = "Transcript copied"
        }
    }

    private func applyHotkeys(preferences: OmniVoicePreferences) {
        guard let model else { return }
        do {
            hotkeys.unregister()
            try hotkeys.register(
                dictation: preferences.dictationHotkey,
                style: preferences.styleHotkey
            )
        } catch {
            model.statusText = "Hotkey registration failed"
        }
    }

    private func startPermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePermissionStatus(updateStatusText: false)
            }
        }
    }

    private func updatePermissionStatus(updateStatusText: Bool = true) {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let accessibilityEnabled = AXIsProcessTrusted()
        logPermissionStatus(micStatus: micStatus, accessibilityEnabled: accessibilityEnabled)
        model?.microphoneAuthorized = micStatus == .authorized
        model?.accessibilityTrusted = accessibilityEnabled
        if accessibilityEnabled {
            didPromptForAccessibility = false
        }
        updatePermissionRefreshTimer(micStatus: micStatus, accessibilityEnabled: accessibilityEnabled)

        guard updateStatusText, model?.session.state == .idle else { return }

        switch (micStatus, accessibilityEnabled) {
        case (.authorized, true):
            model?.statusText = "Ready"
        case (.notDetermined, _):
            model?.statusText = "Microphone permission required"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in
                    self?.updatePermissionStatus()
                }
            }
        case (_, false):
            model?.statusText = "Accessibility permission required"
        default:
            model?.statusText = "Permissions required"
        }
    }

    private func logPermissionStatus(micStatus: AVAuthorizationStatus, accessibilityEnabled: Bool) {
        guard micStatus != lastLoggedMicStatus || accessibilityEnabled != lastLoggedAccessibilityEnabled else {
            return
        }

        lastLoggedMicStatus = micStatus
        lastLoggedAccessibilityEnabled = accessibilityEnabled
        permissionLogger.notice(
            "Permission status microphone=\(String(describing: micStatus), privacy: .public) accessibilityTrusted=\(accessibilityEnabled, privacy: .public) bundle=\(Bundle.main.bundleURL.path, privacy: .public)"
        )
    }

    private func updatePermissionRefreshTimer(micStatus: AVAuthorizationStatus, accessibilityEnabled: Bool) {
        if micStatus == .authorized && accessibilityEnabled {
            permissionRefreshTimer?.invalidate()
            permissionRefreshTimer = nil
        } else if permissionRefreshTimer == nil {
            startPermissionRefreshTimer()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleHotkey(_ event: HotkeyController.Event) {
        guard let model else { return }

        switch event {
        case .dictationPressed:
            startDictation(model: model)
        case .dictationReleased:
            streamingClient.finish()
            Task { [weak self] in
                await self?.finishDictation()
            }
        case .stylePressed:
            model.cycleStyle()
            showOverlay(text: model.statusText, styleName: model.preferences.style.displayName)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.hideOverlay()
            }
        }
    }

    private func startDictation(model: AppModel) {
        insertionTarget = insertionService.captureTarget()
        liveDraft = model.preferences.liveDraftInsertionEnabled
            ? insertionService.beginLiveDraft(target: insertionTarget)
            : nil
        model.session.pressHotkey()
        model.captionText = ""
        model.statusText = "Listening"
        lastInputLevel = 0
        lastLevelOverlayUpdate = .distantPast
        showOverlay(
            text: "",
            styleName: model.preferences.style.displayName,
            level: 0,
            anchorFrame: activeOverlayAnchor
        )

        streamingClient.setOnUpdate { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, let model = self.model else { return }
                guard model.session.state == .listening else { return }
                let displayText = TextInsertionEdit.sanitizedInsertionText(update.text)
                if !update.isFinal {
                    model.session.receivePartial(displayText)
                    self.updateLiveDraft(with: displayText)
                }
                model.captionText = displayText
                self.showOverlay(
                    text: displayText,
                    styleName: model.preferences.style.displayName,
                    level: self.lastInputLevel,
                    anchorFrame: self.activeOverlayAnchor
                )
            }
        }
        audioCapture.onPCMChunk = { [weak self] data in
            self?.streamingClient.sendPCMFloat32(data)
        }
        audioCapture.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.updateInputLevel(level)
            }
        }

        do {
            let sampleRate = audioCapture.inputSampleRate(deviceUID: model.preferences.microphoneID)
            streamingClient.connect(
                provider: model.preferences.asrProvider,
                sampleRate: sampleRate
            )
            _ = try audioCapture.start(deviceUID: model.preferences.microphoneID)
        } catch {
            model.session.fail("Microphone failed: \(error.localizedDescription)")
            model.statusText = "Microphone failed"
            streamingClient.cancel()
            cancelLiveDraftIfNeeded()
            hideOverlay()
        }
    }

    private func finishDictation() async {
        guard let model else {
            insertionTarget = nil
            return
        }
        defer {
            insertionTarget = nil
        }

        let audio: Data
        do {
            audio = try audioCapture.stopWAVData()
            model.statusText = "Transcribing"
            showOverlay(
                text: "Transcribing...",
                styleName: model.preferences.style.displayName,
                level: 0,
                anchorFrame: activeOverlayAnchor
            )
        } catch {
            model.session.fail("Audio capture failed: \(error.localizedDescription)")
            model.statusText = "Audio capture failed"
            streamingClient.cancel()
            cancelLiveDraftIfNeeded()
            hideOverlay()
            return
        }

        let transcript: TranscribeResult
        do {
            transcript = try await engineClient.transcribe(audio: audio, provider: model.preferences.asrProvider)
        } catch {
            await model.refreshProviderAndModelStatus()
            let message = model.transcriptionFailureMessage(for: error)
            model.session.fail("Transcription failed: \(message)")
            model.statusText = message
            streamingClient.cancel()
            cancelLiveDraftIfNeeded()
            showOverlay(text: message, styleName: "Transcription failed", level: 0, anchorFrame: activeOverlayAnchor)
            return
        }

        let rawTranscript = TextInsertionEdit.sanitizedInsertionText(transcript.text)
        guard !rawTranscript.isEmpty else {
            model.session.fail("No speech detected")
            model.statusText = "No speech detected"
            streamingClient.cancel()
            cancelLiveDraftIfNeeded()
            showOverlay(
                text: "No speech detected",
                styleName: model.preferences.style.displayName,
                level: 0,
                anchorFrame: activeOverlayAnchor
            )
            return
        }

        model.session.releaseHotkey(finalTranscript: rawTranscript)
        model.captionText = rawTranscript
        showOverlay(text: rawTranscript, styleName: model.preferences.style.displayName, anchorFrame: activeOverlayAnchor)

        let finalText: String
        if let literalText = literalPayload(from: rawTranscript) {
            finalText = TextInsertionEdit.sanitizedInsertionText(literalText)
            model.statusText = "Literal mode"
        } else {
            let cleanupStyle = cleanupStyle(for: insertionTarget, preferredStyle: model.preferences.style)
            do {
                let cleanup = try await engineClient.cleanup(
                    CleanupRequest(
                        rawTranscript: rawTranscript,
                        style: cleanupStyle,
                        dictionaryTerms: model.preferences.dictionaryTerms
                    )
                )
                finalText = TextInsertionEdit.sanitizedInsertionText(cleanup.text)
            } catch {
                finalText = TextInsertionEdit.sanitizedInsertionText(lightlyPunctuate(rawTranscript))
                model.statusText = "Cleanup skipped"
            }
        }

        model.session.finishCleanup(finalText)

        if let command = DictationCommandParser.parse(finalText) {
            cancelLiveDraftIfNeeded()
            await handle(command: command, model: model)
            return
        }

        if let selectedText = insertionTarget?.selectedText,
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let rewritten = SelectionRewrite.rewrite(selectedText: selectedText, instruction: finalText) {
            await insertFinalText(rewritten, model: model, successStatus: "Selection rewritten")
            return
        }

        await insertFinalText(finalText, model: model, successStatus: "Inserted")
    }

    private func insertFinalText(_ finalText: String, model: AppModel, successStatus: String) async {
        if var draft = liveDraft {
            if insertionService.commitLiveDraft(finalText, draft: &draft) {
                liveDraft = nil
                model.statusText = successStatus
                overlay.commitAndHide(mode: model.activeTheme.commitAnimationMode)
                model.session.reset()
                return
            }

            insertionService.cancelLiveDraft(draft)
            liveDraft = nil
        }

        do {
            try await insertionService.insert(finalText, target: insertionTarget)
            model.statusText = successStatus
            overlay.commitAndHide(mode: model.activeTheme.commitAnimationMode)
            model.session.reset()
        } catch TextInsertionService.InsertionError.accessibilityPermissionRequired {
            model.session.fail("Accessibility permission required")
            model.statusText = "Accessibility permission required"
            copyToPasteboard(finalText)
            if !didPromptForAccessibility {
                requestAccessibilityPermission()
            }
            showOverlay(text: finalText, styleName: "Accessibility required - copied", anchorFrame: activeOverlayAnchor)
        } catch {
            model.session.fail("Insertion failed: \(error.localizedDescription)")
            model.statusText = "Insertion failed"
            copyToPasteboard(finalText)
            showOverlay(text: finalText, styleName: "Insertion failed - copied", anchorFrame: activeOverlayAnchor)
        }
    }

    private func handle(command: DictationCommand, model: AppModel) async {
        do {
            switch command.action {
            case .openApplication:
                try commandExecutor.execute(command)
            case .showCommandPalette:
                showCommandPalette()
            case .undoLastDictation:
                try await insertionService.undoLastInsertion()
            case .aiHandoff(let target, let prompt):
                await handleAIHandoff(target: target, prompt: prompt, model: model)
                return
            }
            model.statusText = command.displayText
            showOverlay(text: command.displayText, styleName: "Command")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.hideOverlay()
            }
            model.session.reset()
        } catch {
            model.session.fail("Command failed: \(error.localizedDescription)")
            model.statusText = "Command failed"
            showOverlay(text: error.localizedDescription, styleName: "Command failed")
        }
    }

    private func handleAIHandoff(target: AIHandoffTarget, prompt: String, model: AppModel) async {
        let baseURL = model.preferences.openAICompatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let aiModel = model.preferences.openAICompatibleModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !aiModel.isEmpty else {
            model.session.fail("AI endpoint and model are required")
            model.statusText = "AI endpoint required"
            showOverlay(
                text: "Add an OpenAI-compatible endpoint and model in Integrations.",
                styleName: "AI handoff",
                anchorFrame: activeOverlayAnchor
            )
            return
        }

        let context = insertionTarget?.selectedText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        model.statusText = "Asking \(target.displayName)"
        showOverlay(text: "Asking \(target.displayName)...", styleName: "AI handoff", anchorFrame: activeOverlayAnchor)

        do {
            let result = try await engineClient.aiHandoff(
                AIHandoffRequest(
                    prompt: prompt,
                    provider: target.rawValue,
                    baseURL: baseURL,
                    model: aiModel,
                    apiKey: model.preferences.openAICompatibleAPIKey,
                    context: context
                )
            )
            let insertion = TextInsertionEdit.sanitizedInsertionText(result.text)
            guard !insertion.isEmpty else {
                model.session.fail("AI returned empty text")
                model.statusText = "AI returned empty text"
                showOverlay(text: "AI returned empty text", styleName: "AI handoff", anchorFrame: activeOverlayAnchor)
                return
            }

            await insertFinalText(insertion, model: model, successStatus: "AI response inserted")
        } catch {
            model.session.fail("AI handoff failed: \(error.localizedDescription)")
            model.statusText = "AI handoff failed"
            showOverlay(text: error.localizedDescription, styleName: "AI handoff failed", anchorFrame: activeOverlayAnchor)
        }
    }

    private func showCommandPalette() {
        showOverlay(
            text: "Command, open Safari\nCommand, undo last dictation\nAsk Claude, write a reply",
            styleName: "Commands"
        )
    }

    private func cleanupStyle(for target: TextInsertionService.Target?, preferredStyle: StyleProfile) -> StyleProfile {
        guard preferredStyle == .neutral else {
            return preferredStyle
        }
        guard let bundleID = target?.application?.bundleIdentifier?.lowercased() else {
            return preferredStyle
        }

        if bundleID.contains("terminal")
            || bundleID.contains("iterm")
            || bundleID.contains("xcode")
            || bundleID.contains("vscode") {
            return .raw
        }
        if bundleID.contains("mail") {
            return .professional
        }
        if bundleID.contains("slack")
            || bundleID.contains("messages")
            || bundleID.contains("mobilesms") {
            return .concise
        }
        return preferredStyle
    }

    private func literalPayload(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in ["literal mode", "raw dictation"] where lowered.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:;!?")))
        }
        return nil
    }

    private func lightlyPunctuate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if ".!?".contains(trimmed.last!) {
            return trimmed
        }
        return trimmed + "."
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func updateLiveDraft(with text: String) {
        guard !isTransientStreamingText(text), var draft = liveDraft else {
            return
        }

        if insertionService.updateLiveDraft(text, draft: &draft) {
            liveDraft = draft
        }
    }

    private func cancelLiveDraftIfNeeded() {
        guard let draft = liveDraft else {
            return
        }
        insertionService.cancelLiveDraft(draft)
        liveDraft = nil
    }

    private func isTransientStreamingText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("listening") == .orderedSame
    }

    private var activeOverlayAnchor: CGRect? {
        insertionTarget?.caretFrame
    }

    private func updateInputLevel(_ level: Float) {
        guard let model, model.session.state == .listening else { return }

        lastInputLevel = level
        let now = Date()
        guard now.timeIntervalSince(lastLevelOverlayUpdate) >= 0.08 else { return }

        lastLevelOverlayUpdate = now
        showOverlay(
            text: model.captionText,
            styleName: model.preferences.style.displayName,
            level: level,
            anchorFrame: activeOverlayAnchor
        )
    }
}
