import AppKit
import AVFoundation
import OmniVoiceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private let overlay = CaptionOverlayWindow()
    private let hotkeys = HotkeyController()
    private let audioCapture = AudioCaptureService()
    private let engineClient = EngineClient()
    private let streamingClient = EngineStreamingClient()
    private let insertionService = TextInsertionService()
    private var lastInputLevel: Float = 0
    private var lastLevelOverlayUpdate = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregister()
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

        applyHotkeys(preferences: model.preferences)
    }

    func showOverlay(text: String, styleName: String, level: Float = 0) {
        overlay.show(text: text, styleName: styleName, level: level)
    }

    func hideOverlay() {
        overlay.hide()
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

    private func updatePermissionStatus() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let accessibilityEnabled = AXIsProcessTrusted()

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
        model.session.pressHotkey()
        model.captionText = ""
        model.statusText = "Listening"
        lastInputLevel = 0
        lastLevelOverlayUpdate = .distantPast
        showOverlay(text: "", styleName: model.preferences.style.displayName, level: 0)

        streamingClient.setOnUpdate { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, let model = self.model else { return }
                model.captionText = update.text
                model.session.receivePartial(update.text)
                self.showOverlay(text: update.text, styleName: model.preferences.style.displayName, level: self.lastInputLevel)
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
            let sampleRate = try audioCapture.start(deviceUID: model.preferences.microphoneID)
            streamingClient.connect(
                provider: model.preferences.asrProvider,
                sampleRate: sampleRate
            )
        } catch {
            model.session.fail("Microphone failed: \(error.localizedDescription)")
            model.statusText = "Microphone failed"
            streamingClient.cancel()
            hideOverlay()
        }
    }

    private func finishDictation() async {
        guard let model else { return }

        let audio: Data
        do {
            audio = try audioCapture.stopWAVData()
            model.statusText = "Transcribing"
            showOverlay(text: "Transcribing...", styleName: model.preferences.style.displayName, level: 0)
        } catch {
            model.session.fail("Audio capture failed: \(error.localizedDescription)")
            model.statusText = "Audio capture failed"
            streamingClient.cancel()
            hideOverlay()
            return
        }

        let transcript: TranscribeResult
        do {
            transcript = try await engineClient.transcribe(audio: audio, provider: model.preferences.asrProvider)
        } catch {
            model.session.fail("Transcription failed: \(error.localizedDescription)")
            model.statusText = "Transcription failed"
            streamingClient.cancel()
            showOverlay(text: error.localizedDescription, styleName: "Transcription failed", level: 0)
            return
        }

        let rawTranscript = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTranscript.isEmpty else {
            model.session.fail("No speech detected")
            model.statusText = "No speech detected"
            streamingClient.cancel()
            showOverlay(text: "No speech detected", styleName: model.preferences.style.displayName, level: 0)
            return
        }

        model.session.releaseHotkey(finalTranscript: rawTranscript)
        model.captionText = rawTranscript
        showOverlay(text: rawTranscript, styleName: model.preferences.style.displayName)

        let finalText: String
        do {
            let cleanup = try await engineClient.cleanup(
                CleanupRequest(
                    rawTranscript: rawTranscript,
                    style: model.preferences.style,
                    dictionaryTerms: model.preferences.dictionaryTerms
                )
            )
            finalText = cleanup.text
        } catch {
            finalText = lightlyPunctuate(rawTranscript)
            model.statusText = "Cleanup skipped"
        }

        model.session.finishCleanup(finalText)

        do {
            try insertionService.insert(finalText)
            model.statusText = "Inserted"
            hideOverlay()
            model.session.reset()
        } catch {
            model.session.fail("Insertion failed: \(error.localizedDescription)")
            model.statusText = "Insertion failed"
            copyToPasteboard(finalText)
            showOverlay(text: finalText, styleName: "Insertion failed - copied")
        }
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

    private func updateInputLevel(_ level: Float) {
        guard let model, model.session.state == .listening else { return }

        lastInputLevel = level
        let now = Date()
        guard now.timeIntervalSince(lastLevelOverlayUpdate) >= 0.08 else { return }

        lastLevelOverlayUpdate = now
        showOverlay(
            text: model.captionText,
            styleName: model.preferences.style.displayName,
            level: level
        )
    }
}
