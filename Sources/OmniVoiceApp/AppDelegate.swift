import AppKit
import AVFoundation
import OmniVoiceCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionLogger = Logger(subsystem: "com.omnivoice.OmniVoiceApp", category: "Permissions")
    private weak var model: AppModel?
    private let overlay = CaptionOverlayWindow()
    private let hotMenuOverlay = HotMenuOverlayWindow()
    private let transcriptCacheOverlay = TranscriptCacheOverlayWindow()
    private let hotkeys = HotkeyController()
    private let mouseShortcuts = MouseShortcutController()
    private let audioCapture = AudioCaptureService()
    private let engineClient = EngineClient()
    private let streamingClient = EngineStreamingClient()
    private let insertionService = TextInsertionService()
    private lazy var askController = AskController(insertion: insertionService, engineClient: engineClient)
    private let recordingCuePlayer = RecordingCuePlayer.shared
    private let dockIconController = DynamicDockIconController()
    private let commandExecutor = DictationCommandExecutor()
    private var lastInputLevel: Float = 0
    private var lastLevelOverlayUpdate = Date.distantPast
    private var insertionTarget: TextInsertionService.Target?
    private var liveDraft: TextInsertionService.LiveDraft?
    private var didPromptForAccessibility = false
    private var permissionRefreshTimer: Timer?
    private var lastLoggedMicStatus: AVAuthorizationStatus?
    private var lastLoggedAccessibilityEnabled: Bool?
    private var hotMenuTriggerState = HotMenuTriggerState()
    private var dictationTriggerState = DictationTriggerState()
    private var pendingDictationFinishTask: Task<Void, Never>?
    private var mousePushToTalkActive = false
    var onOpenConversationMode: (() -> Void)?
    var onOpenEditor: (() -> Void)?
    var onOpenEditorNotes: (() -> Void)?
    var onOpenAskAI: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only by default: no Dock icon while OmniVoice is just listening
        // in the status bar. A Dock icon (and Cmd-Tab entry) appears only while a
        // real window is open, and disappears when every window is closed or
        // minimized. The caption / hot-menu / transcript overlays are borderless
        // floating panels (not `.titled`) so they never count as an open window.
        NSApplication.shared.setActivationPolicy(.accessory)
        observeWindowPresence()
        syncActivationPolicy()
    }

    private func observeWindowPresence() {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // willClose fires before the window leaves the list; recompute next tick.
                DispatchQueue.main.async { self?.syncActivationPolicy() }
            }
        }
    }

    private func syncActivationPolicy() {
        let hasVisibleWindow = NSApplication.shared.windows.contains { window in
            window.styleMask.contains(.titled) && window.isVisible && !window.isMiniaturized
        }
        let desired: NSApplication.ActivationPolicy = hasVisibleWindow ? .regular : .accessory
        guard NSApplication.shared.activationPolicy() != desired else { return }
        NSApplication.shared.setActivationPolicy(desired)
        if desired == .regular {
            if let model {
                dockIconController.apply(theme: model.activeTheme, appearanceMode: model.preferences.appearanceMode)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRefreshTimer?.invalidate()
        hotkeys.unregister()
        mouseShortcuts.stop()
        transcriptCacheOverlay.cancel()
        EngineSupervisor.shared.stopStartedProcess()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updatePermissionStatus()
    }

    func attach(model: AppModel) {
        self.model = model
        updatePermissionStatus()
        askController.updateConfiguration(model.preferences)
        model.onCustomAgentsChanged = { [weak self, weak model] _ in
            guard let model else { return }
            self?.askController.updateConfiguration(model.preferences)
        }
        askController.onBubbleVisibilityChanged = { [weak self, weak model] isOpen in
            guard let self, let model else { return }
            if isOpen {
                let base = model.preferences.dictationHotkey.modifiers & HotkeyBinding.modifierMask
                let modifiers = base != 0 ? base : HotkeyBinding.carbonModifiers(command: true, option: true)
                self.hotkeys.registerBubbleActions(modifiers: modifiers)
            } else {
                self.hotkeys.unregisterBubbleActions()
            }
        }

        hotkeys.onEvent = { [weak self] event in
            self?.handleHotkey(event)
        }
        model.onHotkeysChanged = { [weak self] preferences in
            self?.applyHotkeys(preferences: preferences)
        }
        mouseShortcuts.onPushToTalkPressed = { [weak self, weak model] in
            guard let self, let model else { return }
            self.handleMousePushToTalkPressed(model: model)
        }
        mouseShortcuts.onPushToTalkReleased = { [weak self, weak model] in
            guard let self, let model else { return }
            self.handleMousePushToTalkReleased(model: model)
        }
        mouseShortcuts.onTranscriptCachePressed = { [weak self, weak model] in
            guard let self, let model else { return }
            self.showTranscriptCache(model: model)
        }
        model.onMouseShortcutsChanged = { [weak self] preferences in
            self?.applyMouseShortcuts(preferences: preferences)
        }
        model.onThemeChanged = { [weak self] theme, appearanceMode in
            self?.dockIconController.apply(theme: theme, appearanceMode: appearanceMode)
        }
        streamingClient.setOnDiagnostics { [weak self] diagnostics in
            Task { @MainActor [weak self] in
                self?.model?.streamingDiagnostics = diagnostics
            }
        }

        startPermissionRefreshTimer()
        applyHotkeys(preferences: model.preferences)
        applyMouseShortcuts(preferences: model.preferences)
        dockIconController.apply(theme: model.activeTheme, appearanceMode: model.preferences.appearanceMode)
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

    func resetAccessibilityPermission() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = [
            "reset",
            "Accessibility",
            Bundle.main.bundleIdentifier ?? "com.omnivoice.OmniVoiceApp",
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            permissionLogger.error("Failed to reset Accessibility with tccutil: \(error.localizedDescription, privacy: .public)")
        }

        didPromptForAccessibility = false
        updatePermissionStatus()
        requestAccessibilityPermission()
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
            translationStatus: model?.preferences.captionTranslationStatus(
                targetLanguageOptions: model?.translationTargetLanguageOptions ?? []
            ),
            level: level,
            theme: theme ?? model?.activeTheme ?? .defaultTheme,
            appearanceMode: model?.preferences.appearanceMode ?? .system,
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
        await insertCachedTranscript(text, target: target, model: model)
    }

    private func insertCachedTranscript(
        _ text: String,
        target: TextInsertionService.Target?,
        model: AppModel
    ) async {
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
                additionalDictation: preferences.additionalDictationHotkeys,
                style: preferences.styleHotkey,
                hotMenu: preferences.hotMenuHotkey,
                transcriptCache: preferences.transcriptCacheHotkey
            )
        } catch {
            model.statusText = "Hotkey registration failed"
        }
    }

    private func applyMouseShortcuts(preferences: OmniVoicePreferences) {
        mouseShortcuts.apply(preferences: preferences)
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
            handleDictationPressed(model: model)
        case .dictationReleased:
            handleDictationReleased(model: model)
        case .stylePressed:
            model.cycleStyle()
            showOverlay(text: model.statusText, styleName: model.preferences.style.displayName)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.hideOverlay()
            }
        case .hotMenuPressed:
            showHotMenu(model: model)
        case .hotMenuReleased:
            releaseHotMenu(model: model)
        case .transcriptCachePressed:
            showTranscriptCache(model: model)
        case .bubbleInsert:
            abortDictationForBubbleAction(model: model)
            askController.bubbleInsert()
        case .bubbleCopy:
            abortDictationForBubbleAction(model: model)
            askController.bubbleCopy()
        case .bubbleDismiss:
            abortDictationForBubbleAction(model: model)
            askController.bubbleDismiss()
        }
    }

    /// The bubble action hotkeys share the push-to-talk modifiers, so if PTT is
    /// modifier-only the chord also started a recording. Discard it (no transcript)
    /// when an action fires. No-op when nothing is recording (e.g. key-chord PTT).
    private func abortDictationForBubbleAction(model: AppModel) {
        guard model.session.state == .listening else { return }
        pendingDictationFinishTask?.cancel()
        pendingDictationFinishTask = nil
        dictationTriggerState.cancel()
        _ = try? audioCapture.stopWAVData()   // stop capture, drop the audio
        streamingClient.cancel()
        cancelLiveDraftIfNeeded()
        model.session.reset()
        insertionTarget = nil
        hideOverlay()
    }

    private func handleDictationPressed(model: AppModel) {
        let decision = dictationTriggerState.press(at: Date.timeIntervalSinceReferenceDate)
        switch decision {
        case .startMomentary:
            pendingDictationFinishTask?.cancel()
            pendingDictationFinishTask = nil
            startDictation(model: model)
        case .startLatched:
            pendingDictationFinishTask?.cancel()
            pendingDictationFinishTask = nil
            if model.session.state != .listening {
                startDictation(model: model)
            }
            model.statusText = "Dictation latched"
            showOverlay(
                text: model.captionText,
                styleName: "Dictation latched",
                level: lastInputLevel,
                theme: model.activeTheme,
                anchorFrame: activeOverlayAnchor
            )
        case .finishLatched:
            pendingDictationFinishTask?.cancel()
            pendingDictationFinishTask = nil
            finishDictationNow()
        case .ignore:
            break
        }
    }

    private func handleDictationReleased(model: AppModel) {
        guard dictationTriggerState.release(at: Date.timeIntervalSinceReferenceDate) else {
            model.statusText = dictationTriggerState.mode == .latched ? "Dictation latched" : model.statusText
            return
        }

        pendingDictationFinishTask?.cancel()
        pendingDictationFinishTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(DictationTriggerState.doubleTapInterval * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.finishDictationNow()
            }
        }
    }

    private func finishDictationNow() {
        streamingClient.finish()
        Task { [weak self] in
            await self?.finishDictation()
        }
    }

    private func handleMousePushToTalkPressed(model: AppModel) {
        guard model.session.state == .idle else { return }

        pendingDictationFinishTask?.cancel()
        pendingDictationFinishTask = nil
        dictationTriggerState.cancel()
        mousePushToTalkActive = true
        startDictation(model: model)
    }

    private func handleMousePushToTalkReleased(model: AppModel) {
        guard mousePushToTalkActive else { return }

        mousePushToTalkActive = false
        guard model.session.state == .listening else { return }
        finishDictationNow()
    }

    private func showTranscriptCache(model: AppModel) {
        guard model.session.state == .idle else { return }

        if transcriptCacheOverlay.isPresented {
            transcriptCacheOverlay.cancel()
            return
        }

        let target = insertionService.captureTarget()
        let anchor = NSEvent.mouseLocation
        let showPicker: ([EngineTranscriptRecord]) -> Void = { [weak self, weak model] transcripts in
            guard let self, let model else { return }
            let usableTranscripts = transcripts
                .filter { !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(16)

            guard !usableTranscripts.isEmpty else {
                model.statusText = "No recent transcripts"
                self.showOverlay(text: "No recent transcripts", styleName: "Transcript Cache", theme: model.activeTheme)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.hideOverlay()
                }
                return
            }

            model.statusText = "Transcript cache"
            self.transcriptCacheOverlay.show(
                anchor: anchor,
                transcripts: Array(usableTranscripts),
                theme: model.activeTheme,
                appearanceMode: model.preferences.appearanceMode,
                onInsert: { [weak self, weak model] transcript in
                    guard let self, let model else { return }
                    Task {
                        await self.insertCachedTranscript(
                            transcript.displayText,
                            target: target,
                            model: model
                        )
                    }
                },
                onCancel: {
                    model.statusText = "Transcript cache cancelled"
                }
            )
        }

        if model.transcripts.isEmpty {
            Task { @MainActor [weak model] in
                guard let model else { return }
                await model.refreshTranscripts(updateStatus: false)
                showPicker(model.transcripts)
            }
        } else {
            showPicker(model.transcripts)
        }
    }

    private func showHotMenu(model: AppModel) {
        guard model.session.state == .idle else { return }
        guard hotMenuTriggerState.mode != .latched else { return }

        let mode = hotMenuTriggerState.press(at: Date.timeIntervalSinceReferenceDate)
        let actions = Dictionary(
            uniqueKeysWithValues: HotMenuDirection.allCases.map { direction in
                (direction, model.preferences.effectiveHotMenuActions(for: direction))
            }
        )
        let actionLabels = actions.values.flatMap { $0 }.reduce(into: [HotMenuAction: String]()) { labels, action in
            labels[action] = model.hotMenuActionLabel(action)
        }
        hotMenuOverlay.show(
            center: overlay.preferredHotMenuCenter(),
            theme: model.activeTheme,
            actions: actions,
            actionLabels: actionLabels,
            mode: mode,
            onConfirm: { [weak self, weak model] in
                guard let self, let model else { return }
                self.finishHotMenu(model: model, clearTriggerState: true)
            },
            onCancel: { [weak self, weak model] in
                guard let self, let model else { return }
                self.cancelHotMenu(model: model, clearTriggerState: true)
            }
        )
        model.statusText = mode == .latched ? "Hot menu latched" : "Hot menu"
    }

    private func releaseHotMenu(model: AppModel) {
        guard hotMenuTriggerState.release(at: Date.timeIntervalSinceReferenceDate) else {
            if hotMenuTriggerState.mode == .latched {
                model.statusText = "Hot menu latched"
            }
            return
        }

        finishHotMenu(model: model, clearTriggerState: false)
    }

    private func finishHotMenu(model: AppModel, clearTriggerState: Bool) {
        guard let action = hotMenuOverlay.finish(), action != .none else {
            model.statusText = "Hot menu cancelled"
            if clearTriggerState {
                hotMenuTriggerState.finish()
            }
            return
        }

        if clearTriggerState {
            hotMenuTriggerState.finish()
        }
        executeHotMenu(action, model: model)
    }

    private func cancelHotMenu(model: AppModel, clearTriggerState: Bool) {
        hotMenuOverlay.cancel()
        if clearTriggerState {
            hotMenuTriggerState.finish()
        }
        model.statusText = "Hot menu cancelled"
    }

    private func executeHotMenu(_ action: HotMenuAction, model: AppModel) {
        switch action {
        case .none, .selectionRewrite:
            model.statusText = "Hot menu cancelled"
        case .openConversation:
            onOpenConversationMode?()
            model.statusText = "Conversation mode"
        case .transcriptionMode:
            model.editorWorkspaceMode = .notes
            onOpenEditorNotes?()
            model.statusText = "Editor notes"
            showOverlay(
                text: "Editor Notes opened. Capture notes and draft documents from subject context.",
                styleName: "Notes",
                theme: model.activeTheme
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.hideOverlay()
            }
        case .askAI:
            onOpenAskAI?()
            model.statusText = "Ask AI mode"
            showOverlay(
                text: "Ask AI opened. Add files, subjects, or conversations as context.",
                styleName: "Ask AI",
                theme: model.activeTheme
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.hideOverlay()
            }
        case .dictation:
            model.statusText = "Dictation mode"
            showOverlay(
                text: "Hold \(model.preferences.dictationHotkey.displayName) to dictate.",
                styleName: "Dictation",
                theme: model.activeTheme
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.hideOverlay()
            }
        case .toggleTranslation:
            model.setLiveTranslationEnabled(!model.preferences.liveTranslationEnabled)
            showTranslationStateOverlay(model: model)
        case .translationOff:
            model.setLiveTranslationEnabled(false)
            showTranslationStateOverlay(model: model)
        case .translationOn:
            model.setLiveTranslationEnabled(true)
            showTranslationStateOverlay(model: model)
        case .cycleTranslationLanguage:
            model.cycleQuickTranslationTargetLanguage()
            showOverlay(text: model.statusText, styleName: "Language", theme: model.activeTheme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.hideOverlay()
            }
        case .translationQuickTarget1, .translationQuickTarget2, .translationQuickTarget3, .translationQuickTarget4:
            if let slot = action.quickTranslationTargetSlot {
                model.selectQuickTranslationTargetLanguage(slot: slot)
            }
            showOverlay(text: model.statusText, styleName: "Language", theme: model.activeTheme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.hideOverlay()
            }
        case .cycleStyle:
            model.cycleStyle()
            showOverlay(text: model.statusText, styleName: model.preferences.style.displayName, theme: model.activeTheme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.hideOverlay()
            }
        case .styleNeutral, .styleProfessional, .styleConcise, .styleExpanded, .styleRaw:
            if let style = action.styleProfile {
                model.setStyle(style)
            }
            showOverlay(text: model.statusText, styleName: model.preferences.style.displayName, theme: model.activeTheme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.hideOverlay()
            }
        case .cycleASRProvider:
            model.cycleASRProvider()
            showOverlay(text: model.statusText, styleName: "Model", theme: model.activeTheme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.hideOverlay()
            }
        case .openDashboard:
            NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765/")!)
            model.statusText = "Dashboard opened"
        }
    }

    private func showTranslationStateOverlay(model: AppModel) {
        let target = model.translationLanguageLabel(
            for: model.preferences.translationTargetLanguage,
            in: model.translationTargetLanguageOptions
        )
        showOverlay(
            text: model.preferences.liveTranslationEnabled ? "Translating to \(target)" : "Translation off",
            styleName: "Translation",
            theme: model.activeTheme
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.hideOverlay()
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
                sampleRate: sampleRate,
                translation: streamingTranslationConfiguration(for: model)
            )
            let cueDuration = recordingCuePlayer.playStartCue(preferences: model.preferences)
            if cueDuration > 0 {
                Thread.sleep(forTimeInterval: min(cueDuration + 0.03, 0.30))
            }
            _ = try audioCapture.start(deviceUID: model.preferences.microphoneID)
        } catch {
            model.session.fail("Microphone failed: \(error.localizedDescription)")
            model.statusText = "Microphone failed"
            dictationTriggerState.cancel()
            pendingDictationFinishTask?.cancel()
            pendingDictationFinishTask = nil
            streamingClient.cancel()
            cancelLiveDraftIfNeeded()
            hideOverlay()
        }
    }

    private func streamingTranslationConfiguration(for model: AppModel) -> TranslationStreamConfiguration? {
        guard model.preferences.liveTranslationEnabled else {
            return nil
        }
        return TranslationStreamConfiguration(
            provider: model.preferences.translationProvider,
            sourceLanguage: model.preferences.translationSourceLanguage,
            targetLanguage: model.preferences.translationTargetLanguage,
            modelPath: model.effectiveTranslationModelPath()
        )
    }

    private func finishDictation() async {
        guard let model else {
            insertionTarget = nil
            return
        }
        defer {
            insertionTarget = nil
            pendingDictationFinishTask = nil
        }

        let audio: Data
        do {
            audio = try audioCapture.stopWAVData()
            recordingCuePlayer.playStopCue(preferences: model.preferences)
            model.statusText = "Transcribing"
            showOverlay(
                text: "Transcribing...",
                styleName: model.preferences.style.displayName,
                level: 0,
                anchorFrame: activeOverlayAnchor
            )
        } catch {
            recordingCuePlayer.playStopCue(preferences: model.preferences)
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

        // Route "ask <agent> …" (and follow-ups / actions while the bubble is open)
        // to Ask AI instead of typing the transcript.
        if askController.handle(transcript: rawTranscript, captureTarget: insertionTarget) {
            model.session.reset()
            streamingClient.cancel()
            cancelLiveDraftIfNeeded()
            hideOverlay()
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

        if let command = DictationCommandParser.parse(finalText) {
            cancelLiveDraftIfNeeded()
            await handle(command: command, model: model)
            return
        }

        let insertionText = await translatedTextIfNeeded(finalText, model: model)
        model.session.finishCleanup(insertionText)
        await insertFinalText(insertionText, model: model, successStatus: model.preferences.liveTranslationEnabled ? "Translated text inserted" : "Inserted")
        await model.refreshTranscripts(updateStatus: false)
    }

    private func translatedTextIfNeeded(_ text: String, model: AppModel) async -> String {
        guard model.preferences.liveTranslationEnabled else {
            return text
        }

        model.statusText = "Translating"
        showOverlay(text: "Translating...", styleName: "Translation", level: 0, anchorFrame: activeOverlayAnchor)

        do {
            let result = try await engineClient.translate(
                TranslationRequest(
                    text: text,
                    provider: model.preferences.translationProvider,
                    sourceLanguage: model.preferences.translationSourceLanguage,
                    targetLanguage: model.preferences.translationTargetLanguage,
                    context: [text],
                    modelPath: model.effectiveTranslationModelPath()
                )
            )
            let translated = TextInsertionEdit.sanitizedInsertionText(result.text)
            guard !translated.isEmpty else {
                model.statusText = "Translation returned empty text"
                return text
            }

            model.captionText = translated
            showOverlay(text: translated, styleName: "Translation", anchorFrame: activeOverlayAnchor)
            model.statusText = "Translation ready"
            return translated
        } catch {
            model.statusText = "Translation unavailable; inserting source"
            showOverlay(text: text, styleName: "Translation unavailable", anchorFrame: activeOverlayAnchor)
            return text
        }
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
        let configuration = model.preferences.textLLMConfiguration(for: target)
        guard configuration.isConfigured else {
            let providerName = configuration.provider.displayName
            model.session.fail("\(providerName) is not configured")
            model.statusText = "\(providerName) not configured"
            showOverlay(
                text: "Configure \(providerName) in AI settings.",
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
                    provider: configuration.provider.rawValue,
                    baseURL: configuration.resolvedBaseURL,
                    model: configuration.trimmedModel,
                    apiKey: configuration.trimmedAPIKey,
                    transport: configuration.transport,
                    oauthAccessToken: configuration.trimmedOAuthAccessToken,
                    headers: configuration.resolvedHeaders,
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
        // Keep the live caption and VU meter in the stable draggable overlay.
        // AX caret bounds vary too much across rich composers to move this
        // whole window without also dragging the meter away from the user.
        nil
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
