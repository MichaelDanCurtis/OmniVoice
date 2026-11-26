import AppKit
import AVFoundation
import OmniVoiceCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionLogger = Logger(subsystem: "com.omnispeak.OmniVoiceApp", category: "Permissions")
    private weak var model: AppModel?
    private let overlay = CaptionOverlayWindow()
    private let hotMenuOverlay = HotMenuOverlayWindow()
    private let transcriptCacheOverlay = TranscriptCacheOverlayWindow()
    private let meetingDetector = MeetingDetectionService()
    private let meetingDetectedBanner = MeetingDetectedBannerWindow()
    private let meetingCopilotOverlay = MeetingCopilotOverlayWindow()
    private let meetingWrapUpWindow = MeetingWrapUpWindow()
    private let commandModeController = CommandModeController()
    private let hotkeys = HotkeyController()
    private let mouseShortcuts = MouseShortcutController()
    private let audioCapture = AudioCaptureService()
    private let engineClient = EngineClient()
    private let streamingClient = EngineStreamingClient()
    private let insertionService = TextInsertionService()
    private lazy var askController = AskController(insertion: insertionService, engineClient: engineClient)
    private let correctionWatcher = CorrectionWatcher()
    private let learnedWordToast = LearnedWordToast()
    private let teachCorrectionWindow = TeachCorrectionWindow()
    private let authLogin = AuthLoginController()
    private let paywallWindow = PaywallWindow()
    private var lastLearnableInsertion: String?
    private let recordingCuePlayer = RecordingCuePlayer.shared
    private let dockIconController = DynamicDockIconController()
    private let commandExecutor = DictationCommandExecutor()
    private var lastInputLevel: Float = 0
    private var lastLevelOverlayUpdate = Date.distantPast
    private var insertionTarget: TextInsertionService.Target?
    private var liveDraft: TextInsertionService.LiveDraft?
    // AppleSpeechTranscriber on macOS 26+; stored as Any because stored
    // properties cannot be availability-gated.
    private var appleSpeechSession: Any?
    private var activeDictationUsesAppleSpeech = false
    private let coreMLParakeet = CoreMLParakeetTranscriber()
    private var activeDictationUsesCoreMLParakeet = false
    private var coreMLPartialTask: Task<Void, Never>?
    private var deepgramStreamingSession: DeepgramStreamingSession?
    private var activeDictationUsesDeepgram = false
    private var pendingAudioCaptureStartTask: Task<Void, Never>?
    private var dictationCaptureGeneration: UInt64 = 0
    private var audioCaptureHasStartedForSession = false
    private var didPromptForAccessibility = false
    private var permissionRefreshTimer: Timer?
    private var overlayAutoHideTask: Task<Void, Never>?
    private var dictationPressedAt: TimeInterval = 0
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
        // Menu-bar-only by default: no Dock icon while OmniSpeak is just listening
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
                // Force: macOS reset the Dock icon to the static one when the icon reappeared.
                dockIconController.apply(theme: model.activeTheme, appearanceMode: model.preferences.appearanceMode, force: true)
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
        meetingDetector.stop()
        model?.stopPreMeetingBriefMonitor()
        meetingDetectedBanner.hide()
        meetingCopilotOverlay.endSession(keepPinnedModals: false)
        meetingWrapUpWindow.hide()
        commandModeController.shutdown()
        EngineSupervisor.shared.stopStartedProcess()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updatePermissionStatus()
        Task { [weak self] in await self?.model?.refreshEntitlement() }
    }

    func attach(model: AppModel) {
        self.model = model
        updatePermissionStatus()
        model.hydrateAndMigrateLLMSecrets()
        if model.preferencesLoadFailed {
            model.statusText = "Saved settings couldn't be read — using defaults"
        }
        askController.updateConfiguration(model.preferences)
        Task { [weak model] in
            await model?.discoverSystemAgents()
        }
        configureMeetingCopilot(model: model)
        commandModeController.attach(model: model)
        commandModeController.onTranscribeAudio = { [weak self, weak model] wavData in
            guard let self, let model else { return "" }
            if model.isServiceModeReady {
                return try await DeepgramClient.transcribe(
                    wavData: wavData,
                    config: model.preferences.serviceMode,
                    apiKey: model.effectiveDeepgramAPIKey
                )
            }
            if model.preferences.asrProvider == .parakeetCoreMLANE {
                return try await self.coreMLParakeet.transcribe(wavData: wavData)
            }
            let engineProvider: ASRProviderKind = model.preferences.asrProvider.isEngineBacked
                ? model.preferences.asrProvider
                : .parakeetTDTMLX
            let result = try await self.engineClient.transcribe(audio: wavData, provider: engineProvider)
            return result.text
        }
        hotMenuOverlay.onSelectTranslationLanguage = { [weak self, weak model] code in
            guard let self, let model else { return }
            self.hotMenuTriggerState.finish()
            model.selectQuickTranslationLanguage(code)
            let label = code.flatMap { InlineTranslationParser.languageInfo(forCode: $0)?.name } ?? "Off"
            self.showOverlay(text: code == nil ? "Translation Off" : "Translate → \(label)", styleName: "Translation", theme: model.activeTheme)
            self.scheduleOverlayAutoHide(after: 1.0, resetSession: false)
        }
        hotMenuOverlay.onExecuteAction = { [weak self, weak model] action in
            guard let self, let model else { return }
            self.hotMenuTriggerState.finish()
            self.executeHotMenu(action, model: model)
        }
        correctionWatcher.onLearn = { [weak self, weak model] correction in
            guard let self, let model, model.preferences.autoLearnCorrectionsEnabled else { return }
            self.commitLearnedCorrection(correction, model: model)
        }
        teachCorrectionWindow.onLearn = { [weak self, weak model] correction in
            guard let self, let model else { return }
            self.commitLearnedCorrection(correction, model: model)
        }
        learnedWordToast.onUndo = { [weak model] id in
            model?.removeDictionaryEntry(id: id)
        }
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
        model.onThemeChanged = { [weak self, weak model] theme, appearanceMode in
            self?.dockIconController.apply(theme: theme, appearanceMode: appearanceMode)
            if let model {
                self?.overlay.updateGlassOpacity(model.preferences.captionGlassOpacity)
                self?.meetingCopilotOverlay.updateTheme(
                    theme,
                    appearanceMode: appearanceMode,
                    corner: model.preferences.meetingCopilotCorner,
                    stealthMode: model.preferences.meetingStealthModeEnabled
                )
                self?.commandModeController.updateTheme(model: model)
            }
        }
        streamingClient.setOnDiagnostics { [weak self] diagnostics in
            Task { @MainActor [weak self] in
                self?.model?.streamingDiagnostics = diagnostics
            }
        }

        wireEntitlement(model: model)

        startPermissionRefreshTimer()
        applyHotkeys(preferences: model.preferences)
        applyMouseShortcuts(preferences: model.preferences)
        dockIconController.apply(theme: model.activeTheme, appearanceMode: model.preferences.appearanceMode)
    }

    private func configureMeetingCopilot(model: AppModel) {
        model.refreshCalendarAuthorizationStatus()

        meetingDetector.isEnabled = { [weak model] in
            model?.preferences.meetingAutoDetectEnabled ?? false
        }
        meetingDetector.isRecordingConversation = { [weak model] in
            model?.isConversationRecording ?? false
        }
        meetingDetector.onMeetingDetected = { [weak self, weak model] event in
            guard let self, let model else { return }
            guard !model.isConversationRecording else { return }
            if model.preferences.meetingAutoStartWithoutPrompt {
                Task { @MainActor in
                    await model.startDetectedMeeting(event)
                }
            } else {
                self.meetingDetectedBanner.show(
                    event: event,
                    corner: model.preferences.meetingCopilotCorner,
                    stealthMode: model.preferences.meetingStealthModeEnabled,
                    theme: model.activeTheme,
                    appearanceMode: model.preferences.appearanceMode
                )
            }
        }
        meetingDetector.onMeetingEnded = { [weak self, weak model] _ in
            self?.meetingDetectedBanner.hide()
            Task { @MainActor in
                await model?.handleDetectedCallEnded()
            }
        }

        meetingDetectedBanner.onStartMeeting = { [weak model] event in
            guard let model else { return }
            Task { @MainActor in
                await model.startDetectedMeeting(event)
            }
        }
        meetingDetectedBanner.onDismiss = { [weak self] in
            self?.meetingDetector.dismissCurrentPrompt()
        }

        meetingCopilotOverlay.onAnalyzeNow = { [weak model] in
            Task { @MainActor in
                await model?.runLiveMeetingInsightPass(force: true)
            }
        }
        meetingCopilotOverlay.onCatchUp = { [weak model] in
            Task { @MainActor in
                await model?.catchUpLastTwoMinutesInMeeting()
            }
        }
        meetingCopilotOverlay.onScreenContext = { [weak model] in
            Task { @MainActor in
                await model?.captureScreenAndAnswerInMeeting()
            }
        }
        meetingCopilotOverlay.onBookmarkMoment = { [weak model] in
            Task { @MainActor in
                await model?.bookmarkCurrentMeetingMoment()
            }
        }
        meetingCopilotOverlay.onToggleCorner = { [weak model] in
            model?.toggleMeetingCopilotCorner()
        }
        meetingCopilotOverlay.onStopMeeting = { [weak model] in
            Task { @MainActor in
                await model?.stopConversationRecording()
            }
        }
        meetingCopilotOverlay.onCopyText = { [weak self] text in
            self?.copyToPasteboard(text)
        }

        meetingWrapUpWindow.onCopyText = { [weak self] text in
            self?.copyToPasteboard(text)
        }
        meetingWrapUpWindow.onExportToNotes = { summary in
            switch MeetingExportService.exportToAppleNotes(summary) {
            case .success(let message):
                return message
            case .failure(let error):
                return error.localizedDescription
            }
        }
        meetingWrapUpWindow.onExportToReminders = { summary in
            switch await MeetingExportService.exportActionItemsToReminders(summary) {
            case .success(let count):
                return count == 1 ? "Added 1 Reminder" : "Added \(count) Reminders"
            case .failure(let error):
                return error.localizedDescription
            }
        }

        model.onMeetingCopilotSessionChanged = { [weak self, weak model] title, subtitle, keepPinned in
            guard let self, let model else { return }
            if let title {
                self.meetingCopilotOverlay.showSession(
                    title: title,
                    calendarSubtitle: subtitle,
                    corner: model.preferences.meetingCopilotCorner,
                    stealthMode: model.preferences.meetingStealthModeEnabled,
                    theme: model.activeTheme,
                    appearanceMode: model.preferences.appearanceMode
                )
            } else {
                self.meetingCopilotOverlay.endSession(keepPinnedModals: keepPinned)
            }
        }
        model.onMeetingCopilotAnalyzingChanged = { [weak self] analyzing in
            self?.meetingCopilotOverlay.setAnalyzing(analyzing)
        }
        model.onMeetingCopilotTalkTimeChanged = { [weak self] stats in
            self?.meetingCopilotOverlay.updateTalkTime(stats)
        }
        model.onMeetingCopilotModal = { [weak self, weak model] item in
            guard let self, let model else { return }
            self.meetingCopilotOverlay.updateTheme(
                model.activeTheme,
                appearanceMode: model.preferences.appearanceMode,
                corner: model.preferences.meetingCopilotCorner,
                stealthMode: model.preferences.meetingStealthModeEnabled
            )
            self.meetingCopilotOverlay.presentModal(item)
        }
        model.onMeetingWrapUpReady = { [weak self, weak model] summary in
            guard let self, let model else { return }
            self.meetingWrapUpWindow.show(
                summary: summary,
                corner: model.preferences.meetingCopilotCorner,
                stealthMode: model.preferences.meetingStealthModeEnabled,
                theme: model.activeTheme,
                appearanceMode: model.preferences.appearanceMode
            )
        }

        meetingDetector.start()
        model.startPreMeetingBriefMonitor()
    }

    private func wireEntitlement(model: AppModel) {
        model.onPresentPaywall = { [weak self] feature in
            self?.presentPaywall(for: feature)
        }
        model.onRequestSignIn = { [weak self] in self?.beginSignIn() }
        model.onRequestSignOut = { [weak self] in self?.authLogin.signOut() }
        model.onUpgrade = { [weak self] in self?.openBilling(path: "billing/checkout") }
        model.onManageBilling = { [weak self] in self?.openBilling(path: "billing/portal") }

        askController.isEntitledToAskAI = { [weak model] in
            model?.isEntitled(to: .askAI) ?? false
        }
        askController.onAskAIPaywall = { [weak self] in
            self?.presentPaywall(for: .askAI)
        }

        authLogin.onSignOut = { [weak model] in
            model?.accountEmail = nil
            Task { await model?.refreshEntitlement() }
        }

        model.accountEmail = authLogin.currentSession?.email
        Task { [weak model] in await model?.refreshEntitlement() }
    }

    private func presentPaywall(for feature: PremiumFeature) {
        paywallWindow.show(
            feature: feature,
            onStartTrial: { [weak self] in self?.beginSignIn() },
            onManageBilling: { [weak self] in self?.openBilling(path: "billing/portal") }
        )
    }

    private func beginSignIn() {
        guard let model else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await self.authLogin.signIn()
                model.accountEmail = session.email
                await model.refreshEntitlement()
                model.statusText = "Signed in as \(session.email)"
            } catch {
                model.statusText = (error as? AuthError)?.errorDescription ?? "Sign-in failed"
            }
        }
    }

    private func openBilling(path: String) {
        guard let base = WorkerConfig.baseURL else {
            model?.statusText = "Billing isn’t available yet."
            return
        }
        NSWorkspace.shared.open(base.appendingPathComponent(path))
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
            Bundle.main.bundleIdentifier ?? "com.omnispeak.OmniVoiceApp",
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
        overlayAutoHideTask?.cancel()
        overlayAutoHideTask = nil
        overlay.show(
            text: text,
            styleName: styleName,
            translationStatus: model?.preferences.captionTranslationStatus(
                targetLanguageOptions: model?.translationTargetLanguageOptions ?? []
            ),
            level: level,
            theme: theme ?? model?.activeTheme ?? .defaultTheme,
            appearanceMode: model?.preferences.appearanceMode ?? .system,
            glassOpacity: model?.preferences.captionGlassOpacity ?? 0.05,
            anchorFrame: anchorFrame
        )
    }

    func hideOverlay() {
        overlayAutoHideTask?.cancel()
        overlayAutoHideTask = nil
        overlay.hide()
    }

    private func scheduleOverlayAutoHide(after seconds: Double, resetSession: Bool = true) {
        overlayAutoHideTask?.cancel()
        overlayAutoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.2, seconds) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.overlay.hide()
            if resetSession, let model = self.model, model.session.state != .listening {
                model.session.reset()
            }
            self.overlayAutoHideTask = nil
        }
    }

    func commitOverlayAnimation() {
        overlay.commitAndHide(mode: model?.activeTheme.commitAnimationMode ?? .magicPoof)
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
        case .teachCorrectionPressed:
            if let last = lastLearnableInsertion {
                teachCorrectionWindow.show(originalText: last)
            }
        }
    }

    /// The bubble action hotkeys share the push-to-talk modifiers, so if PTT is
    /// modifier-only the chord also started a recording. Discard it (no transcript)
    /// when an action fires. No-op when nothing is recording (e.g. key-chord PTT).
    private func abortDictationForBubbleAction(model: AppModel) {
        guard model.session.state == .listening else { return }
        pendingDictationFinishTask?.cancel()
        pendingDictationFinishTask = nil
        pendingAudioCaptureStartTask?.cancel()
        pendingAudioCaptureStartTask = nil
        dictationCaptureGeneration &+= 1
        dictationTriggerState.cancel()
        if audioCaptureHasStartedForSession {
            _ = try? audioCapture.stopWAVData()   // stop capture, drop the audio
            audioCaptureHasStartedForSession = false
        }
        streamingClient.cancel()
        cancelAppleSpeechIfNeeded()
        cancelDeepgramStreamIfNeeded()
        cancelLiveDraftIfNeeded()
        model.session.reset()
        insertionTarget = nil
        hideOverlay()
        commandModeController.resumeOpenMicIfActive()
    }

    private func handleDictationPressed(model: AppModel) {
        let now = Date.timeIntervalSinceReferenceDate
        let decision = dictationTriggerState.press(at: now)
        switch decision {
        case .startMomentary:
            dictationPressedAt = now
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
        let now = Date.timeIntervalSinceReferenceDate
        guard dictationTriggerState.release(at: now) else {
            model.statusText = dictationTriggerState.mode == .latched ? "Dictation latched" : model.statusText
            return
        }

        // If the user held the hotkey to speak (>= 0.25s), this is push-to-talk rather
        // than the first tap of a double-tap latch — finish immediately with zero lag.
        let holdDuration = now - dictationPressedAt
        if holdDuration >= 0.25 {
            pendingDictationFinishTask?.cancel()
            pendingDictationFinishTask = nil
            finishDictationNow()
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
            liveTranslationEnabled: model.preferences.liveTranslationEnabled,
            activeLanguageCode: model.preferences.translationTargetLanguage,
            quickLanguages: model.preferences.translationQuickTargetLanguages,
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
            NSWorkspace.shared.open(EngineAuthTokenStore.shared.authenticatedURL(URL(string: "http://127.0.0.1:8765/")!))
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

    private func cancelAppleSpeechIfNeeded() {
        if #available(macOS 26.0, *), let session = appleSpeechSession as? AppleSpeechTranscriber {
            session.cancel()
        }
        appleSpeechSession = nil
        activeDictationUsesAppleSpeech = false
    }

    private func cancelDeepgramStreamIfNeeded() {
        deepgramStreamingSession?.cancel()
        deepgramStreamingSession = nil
        activeDictationUsesDeepgram = false
        audioCapture.onPCM16Chunk = nil
    }

    /// Starts a native SpeechAnalyzer session: partials drive the same caption
    /// path as engine streaming; audio chunks bypass the engine entirely.
    private func startAppleSpeechSession(model: AppModel, sampleRate: Double) throws {
        guard #available(macOS 26.0, *) else {
            struct AppleSpeechUnsupported: LocalizedError {
                var errorDescription: String? { "Apple Speech requires macOS 26 or later" }
            }
            throw AppleSpeechUnsupported()
        }

        let session = AppleSpeechTranscriber()
        appleSpeechSession = session
        session.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, let model = self.model else { return }
                guard model.session.state == .listening else { return }
                let displayText = TextInsertionEdit.sanitizedInsertionText(text)
                model.session.receivePartial(displayText)
                self.updateLiveDraft(with: displayText)
                model.captionText = displayText
                self.showOverlay(
                    text: displayText,
                    styleName: model.preferences.style.displayName,
                    level: self.lastInputLevel,
                    anchorFrame: self.activeOverlayAnchor
                )
            }
        }
        audioCapture.onPCMChunk = { data in
            session.append(pcm: data)
        }
        Task {
            do {
                try await session.start(locale: Locale.current, captureSampleRate: sampleRate)
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, let model = self.model else { return }
                    guard model.session.state == .listening else { return }
                    model.session.fail("Apple Speech failed: \(error.localizedDescription)")
                    model.statusText = "Apple Speech unavailable"
                    _ = try? self.audioCapture.stopWAVData()
                    self.dictationTriggerState.cancel()
                    self.cancelAppleSpeechIfNeeded()
                    self.cancelLiveDraftIfNeeded()
                    self.hideOverlay()
                }
            }
        }
    }

    /// Final transcript for the just-finished dictation: Deepgram (Service Mode),
    /// native Apple Speech, CoreML ANE Parakeet, or the local engine.
    private func transcribeFinishedDictation(audio: Data, model: AppModel) async throws -> TranscribeResult {
        if activeDictationUsesDeepgram {
            let session = deepgramStreamingSession
            deepgramStreamingSession = nil
            activeDictationUsesDeepgram = false
            audioCapture.onPCM16Chunk = nil

            let streamed = (await session?.finish() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !streamed.isEmpty {
                return TranscribeResult(text: streamed, provider: model.preferences.asrProvider)
            }
            let restText = try await DeepgramClient.transcribe(
                wavData: audio,
                config: model.preferences.serviceMode,
                apiKey: model.effectiveDeepgramAPIKey
            )
            return TranscribeResult(text: restText, provider: model.preferences.asrProvider)
        }
        if activeDictationUsesAppleSpeech, #available(macOS 26.0, *),
           let session = appleSpeechSession as? AppleSpeechTranscriber {
            defer {
                appleSpeechSession = nil
                activeDictationUsesAppleSpeech = false
            }
            let text = try await session.finish()
            return TranscribeResult(text: text, provider: .appleSpeech)
        }
        if activeDictationUsesCoreMLParakeet {
            defer {
                activeDictationUsesCoreMLParakeet = false
            }
            let text = try await coreMLParakeet.transcribe(wavData: audio)
            return TranscribeResult(text: text, provider: .parakeetCoreMLANE)
        }
        return try await engineClient.transcribe(audio: audio, provider: model.preferences.asrProvider)
    }

    private func startDictation(model: AppModel) {
        if commandModeController.isActive {
            commandModeController.pauseOpenMicForManualDictation()
        }
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
        let usesDeepgram = model.isServiceModeReady
        let usesAppleSpeech = !usesDeepgram && model.preferences.asrProvider == .appleSpeech
        let usesCoreMLParakeet = !usesDeepgram && model.preferences.asrProvider == .parakeetCoreMLANE
        activeDictationUsesDeepgram = usesDeepgram
        activeDictationUsesAppleSpeech = usesAppleSpeech
        activeDictationUsesCoreMLParakeet = usesCoreMLParakeet
        audioCapture.onPCM16Chunk = nil
        if !usesDeepgram && model.preferences.asrProvider.isEngineBacked {
            audioCapture.onPCMChunk = { [weak self] data in
                self?.streamingClient.sendPCMFloat32(data)
            }
        } else {
            audioCapture.onPCMChunk = nil
        }
        audioCapture.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.updateInputLevel(level)
            }
        }

        do {
            let sampleRate = audioCapture.inputSampleRate(deviceUID: model.preferences.microphoneID)
            if usesDeepgram {
                let dgSession = DeepgramStreamingSession()
                dgSession.onPartial = { [weak self] text in
                    Task { @MainActor [weak self] in
                        guard let self, let model = self.model else { return }
                        guard model.session.state == .listening else { return }
                        let displayText = TextInsertionEdit.sanitizedInsertionText(text)
                        guard !displayText.isEmpty else { return }
                        model.session.receivePartial(displayText)
                        self.updateLiveDraft(with: displayText)
                        model.captionText = displayText
                        self.showOverlay(
                            text: displayText,
                            styleName: "Deepgram · \(model.preferences.style.displayName)",
                            level: self.lastInputLevel,
                            anchorFrame: self.activeOverlayAnchor
                        )
                    }
                }
                try dgSession.start(
                    config: model.preferences.serviceMode,
                    sampleRate: Int(sampleRate.rounded()),
                    apiKey: model.effectiveDeepgramAPIKey
                )
                deepgramStreamingSession = dgSession
                audioCapture.onPCM16Chunk = { [weak dgSession] pcm16Data in
                    dgSession?.sendPCM16(pcm16Data)
                }
            } else if usesAppleSpeech {
                try startAppleSpeechSession(model: model, sampleRate: Double(sampleRate))
            } else if usesCoreMLParakeet {
                Task { [coreMLParakeet] in
                    try? await coreMLParakeet.prepareIfNeeded()
                }
            } else {
                streamingClient.connect(
                    provider: model.preferences.asrProvider,
                    sampleRate: sampleRate,
                    translation: streamingTranslationConfiguration(for: model)
                )
            }
            let cueDuration = recordingCuePlayer.playStartCue(preferences: model.preferences)
            pendingAudioCaptureStartTask?.cancel()
            pendingAudioCaptureStartTask = nil
            dictationCaptureGeneration &+= 1
            let generation = dictationCaptureGeneration
            audioCaptureHasStartedForSession = false

            let beginAudioCapture: @MainActor () -> Void = { [weak self, weak model] in
                guard let self, let model else { return }
                guard self.dictationCaptureGeneration == generation,
                      model.session.state == .listening else {
                    return
                }
                do {
                    _ = try self.audioCapture.start(deviceUID: model.preferences.microphoneID)
                    self.audioCaptureHasStartedForSession = true
                    if usesCoreMLParakeet {
                        self.startCoreMLParakeetLivePartials(model: model)
                    }
                } catch {
                    self.coreMLPartialTask?.cancel()
                    self.coreMLPartialTask = nil
                    model.session.fail("Microphone failed: \(error.localizedDescription)")
                    model.statusText = "Microphone failed"
                    self.dictationTriggerState.cancel()
                    self.pendingDictationFinishTask?.cancel()
                    self.pendingDictationFinishTask = nil
                    self.streamingClient.cancel()
                    self.cancelAppleSpeechIfNeeded()
                    self.cancelDeepgramStreamIfNeeded()
                    self.cancelLiveDraftIfNeeded()
                    self.hideOverlay()
                    self.commandModeController.resumeOpenMicIfActive()
                }
            }

            if cueDuration > 0.005 {
                // Wait asynchronously off the main thread so the HUD draw-in animation
                // and Deepgram/engine stream connect immediately with 0ms UI freeze.
                let delaySeconds = min(cueDuration + 0.03, 0.28)
                pendingAudioCaptureStartTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(delaySeconds))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, let self else { return }
                    self.pendingAudioCaptureStartTask = nil
                    beginAudioCapture()
                }
            } else {
                beginAudioCapture()
            }
        } catch {
            pendingAudioCaptureStartTask?.cancel()
            pendingAudioCaptureStartTask = nil
            dictationCaptureGeneration &+= 1
            audioCaptureHasStartedForSession = false
            coreMLPartialTask?.cancel()
            coreMLPartialTask = nil
            model.session.fail("Microphone failed: \(error.localizedDescription)")
            model.statusText = "Microphone failed"
            dictationTriggerState.cancel()
            pendingDictationFinishTask?.cancel()
            pendingDictationFinishTask = nil
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelDeepgramStreamIfNeeded()
            cancelLiveDraftIfNeeded()
            hideOverlay()
            commandModeController.resumeOpenMicIfActive()
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
            pendingAudioCaptureStartTask?.cancel()
            pendingAudioCaptureStartTask = nil
            dictationCaptureGeneration &+= 1
            audioCaptureHasStartedForSession = false
            coreMLPartialTask?.cancel()
            coreMLPartialTask = nil
            insertionTarget = nil
            pendingDictationFinishTask = nil
            commandModeController.resumeOpenMicIfActive()
        }

        coreMLPartialTask?.cancel()
        coreMLPartialTask = nil

        // User released push-to-talk before the brief start cue finished (ultra-short tap).
        if pendingAudioCaptureStartTask != nil || !audioCaptureHasStartedForSession {
            pendingAudioCaptureStartTask?.cancel()
            pendingAudioCaptureStartTask = nil
            dictationCaptureGeneration &+= 1
            recordingCuePlayer.playEmptyCue(preferences: model.preferences)
            model.session.reset()
            model.statusText = "No speech detected"
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelDeepgramStreamIfNeeded()
            cancelLiveDraftIfNeeded()
            hideOverlay()
            return
        }

        let audio: Data
        do {
            audio = try audioCapture.stopWAVData()
            audioCaptureHasStartedForSession = false
            recordingCuePlayer.playStopCue(preferences: model.preferences)
            model.statusText = "Transcribing"
            showOverlay(
                text: "Transcribing...",
                styleName: model.preferences.style.displayName,
                level: 0,
                anchorFrame: activeOverlayAnchor
            )
        } catch {
            recordingCuePlayer.playEmptyCue(preferences: model.preferences)
            model.session.fail("Audio capture failed: \(error.localizedDescription)")
            model.statusText = "Audio capture failed"
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelDeepgramStreamIfNeeded()
            cancelLiveDraftIfNeeded()
            hideOverlay()
            return
        }

        let transcript: TranscribeResult
        do {
            transcript = try await transcribeFinishedDictation(audio: audio, model: model)
        } catch {
            recordingCuePlayer.playEmptyCue(preferences: model.preferences)
            await model.refreshProviderAndModelStatus()
            let message = model.transcriptionFailureMessage(for: error)
            model.session.fail("Transcription failed: \(message)")
            model.statusText = message
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelLiveDraftIfNeeded()
            showOverlay(text: message, styleName: "Transcription failed", level: 0, anchorFrame: activeOverlayAnchor)
            scheduleOverlayAutoHide(after: 2.2)
            return
        }

        let rawTranscript = TextInsertionEdit.sanitizedInsertionText(transcript.text)
        guard !rawTranscript.isEmpty else {
            recordingCuePlayer.playEmptyCue(preferences: model.preferences)
            model.session.reset()
            model.statusText = "No speech detected"
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelLiveDraftIfNeeded()
            showOverlay(
                text: "No speech detected",
                styleName: model.preferences.style.displayName,
                level: 0,
                anchorFrame: activeOverlayAnchor
            )
            scheduleOverlayAutoHide(after: 1.2)
            return
        }

        // 1. Command Mode enter / exit / execution via cua-driver MCP
        if let directive = CommandModeVoiceParser.parse(rawTranscript) {
            model.session.reset()
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelLiveDraftIfNeeded()
            hideOverlay()
            switch directive {
            case .enter(let initialCommand):
                await commandModeController.enter(model: model, initialCommand: initialCommand)
            case .exit:
                commandModeController.exit(model: model)
            }
            return
        }

        if commandModeController.isActive {
            model.session.reset()
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelLiveDraftIfNeeded()
            overlay.commitAndHide(mode: model.activeTheme.commitAnimationMode)
            await commandModeController.execute(spokenCommand: rawTranscript, model: model)
            commandModeController.resumeOpenMicIfActive()
            return
        }

        // 2. Route "ask <agent> …" (and follow-ups / actions while the bubble is open)
        // to Ask AI instead of typing the transcript.
        if askController.handle(transcript: rawTranscript, captureTarget: insertionTarget) {
            model.session.reset()
            streamingClient.cancel()
            cancelAppleSpeechIfNeeded()
            cancelLiveDraftIfNeeded()
            hideOverlay()
            return
        }

        // 3. Voice Snippets & Dynamic Macros
        let clipboardString = NSPasteboard.general.string(forType: .string) ?? ""
        if let expandedSnippet = VoiceSnippetExpander.expand(
            rawTranscript,
            snippets: model.preferences.voiceSnippets,
            clipboardText: clipboardString
        ) {
            model.session.releaseHotkey(finalTranscript: rawTranscript)
            model.session.finishCleanup(expandedSnippet)
            await insertFinalText(expandedSnippet, model: model, successStatus: "Snippet inserted", learnable: false)
            return
        }

        // 4. Highlight & Transform ("Voice Edit Mode") when text is selected
        let selectedText = insertionTarget?.selectedText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if model.preferences.voiceEditSelectionEnabled,
           VoiceEditDetector.isEditInstruction(rawTranscript, hasSelectedText: !selectedText.isEmpty) {
            model.session.releaseHotkey(finalTranscript: rawTranscript)
            model.statusText = "Transforming selection…"
            showOverlay(text: "Transforming selection…", styleName: "Voice Edit", level: 0, anchorFrame: activeOverlayAnchor)
            if let transformed = await model.transformSelectedText(selectedText, instruction: rawTranscript) {
                model.session.finishCleanup(transformed)
                await insertFinalText(transformed, model: model, successStatus: "Selection updated", learnable: false)
                return
            }
        }

        // 5. Inline Voice Translation ("in Spanish, ..." / "translate to Japanese, ...")
        if let inlineTranslation = InlineTranslationParser.parse(rawTranscript) {
            model.session.releaseHotkey(finalTranscript: rawTranscript)
            model.statusText = "Translating to \(inlineTranslation.targetLanguageName)…"
            showOverlay(
                text: "Translating to \(inlineTranslation.targetLanguageName)…",
                styleName: "Translation",
                level: 0,
                anchorFrame: activeOverlayAnchor
            )
            if let translated = await model.translateTextZeroConfig(
                inlineTranslation.text,
                targetLanguageCode: inlineTranslation.targetLanguageCode,
                targetLanguageName: inlineTranslation.targetLanguageName
            ) {
                model.session.finishCleanup(translated)
                await insertFinalText(translated, model: model, successStatus: "Translated to \(inlineTranslation.targetLanguageName)", learnable: false)
                await model.refreshTranscripts(updateStatus: false)
                return
            }
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
            let baseAppName = insertionTarget?.application?.localizedName
                ?? insertionTarget?.application?.bundleIdentifier
                ?? ""
            let appContext: String
            if model.preferences.autoTonePerAppEnabled {
                appContext = AppToneContext.detect(
                    bundleIdentifier: insertionTarget?.application?.bundleIdentifier,
                    appName: baseAppName
                ).formattingHint
            } else {
                appContext = baseAppName
            }
            do {
                let cleanup = try await model.performCleanup(
                    rawTranscript: rawTranscript,
                    style: cleanupStyle,
                    appContext: appContext
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
        let speakingSeconds = max(1.0, Date.timeIntervalSinceReferenceDate - dictationPressedAt)
        let targetAppName = insertionTarget?.application?.localizedName
        await insertFinalText(insertionText, model: model, successStatus: model.preferences.liveTranslationEnabled ? "Translated text inserted" : "Inserted", learnable: true)
        model.recordDictationStats(text: insertionText, speakingSeconds: speakingSeconds, appName: targetAppName)
        await model.refreshTranscripts(updateStatus: false)
    }

    private func translatedTextIfNeeded(_ text: String, model: AppModel) async -> String {
        guard model.preferences.liveTranslationEnabled else {
            return text
        }

        let targetCode = model.preferences.translationTargetLanguage
        let targetName = InlineTranslationParser.languageInfo(forCode: targetCode)?.name ?? targetCode.uppercased()
        model.statusText = "Translating to \(targetName)…"
        showOverlay(text: "Translating to \(targetName)…", styleName: "Translation", level: 0, anchorFrame: activeOverlayAnchor)

        if let translated = await model.translateTextZeroConfig(
            text,
            targetLanguageCode: targetCode,
            targetLanguageName: targetName
        ) {
            model.captionText = translated
            showOverlay(text: translated, styleName: "Translation", anchorFrame: activeOverlayAnchor)
            model.statusText = "Translation ready"
            return translated
        }

        model.statusText = "Translation unavailable; inserting source"
        showOverlay(text: text, styleName: "Translation unavailable", anchorFrame: activeOverlayAnchor)
        return text
    }

    private func commitLearnedCorrection(_ correction: LearnedCorrection, model: AppModel) {
        guard let entry = model.upsertLearnedCorrection(correction) else { return }
        model.statusText = "Learned “\(correction.to)”"
        learnedWordToast.show(correction: correction, entryID: entry.id)
    }

    private func insertFinalText(_ finalText: String, model: AppModel, successStatus: String, learnable: Bool = false) async {
        if var draft = liveDraft {
            if insertionService.commitLiveDraft(finalText, draft: &draft) {
                liveDraft = nil
                model.statusText = successStatus
                overlay.commitAndHide(mode: model.activeTheme.commitAnimationMode)
                model.session.reset()
                if learnable {
                    lastLearnableInsertion = finalText
                    if model.preferences.autoLearnCorrectionsEnabled {
                        correctionWatcher.observeFocusedElement(insertedText: finalText)
                    }
                }
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
            if learnable {
                lastLearnableInsertion = finalText
                if model.preferences.autoLearnCorrectionsEnabled {
                    correctionWatcher.observeFocusedElement(insertedText: finalText)
                }
            }
        } catch TextInsertionService.InsertionError.accessibilityPermissionRequired {
            model.session.fail("Accessibility permission required")
            model.statusText = "Accessibility permission required"
            copyToPasteboard(finalText)
            if !didPromptForAccessibility {
                requestAccessibilityPermission()
            }
            showOverlay(text: finalText, styleName: "Accessibility required - copied", anchorFrame: activeOverlayAnchor)
            scheduleOverlayAutoHide(after: 2.4)
        } catch {
            model.session.fail("Insertion failed: \(error.localizedDescription)")
            model.statusText = "Insertion failed"
            copyToPasteboard(finalText)
            showOverlay(text: finalText, styleName: "Insertion failed - copied", anchorFrame: activeOverlayAnchor)
            scheduleOverlayAutoHide(after: 2.4)
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

    /// Streams fast on-device partial transcripts during Parakeet CoreML ANE dictation
    /// so both the live caption HUD and "Live type draft into cursor" update in real time.
    private func startCoreMLParakeetLivePartials(model: AppModel) {
        coreMLPartialTask?.cancel()
        coreMLPartialTask = Task { @MainActor [weak self, weak model] in
            var lastSampleCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled, let self, let model, model.session.state == .listening else {
                    break
                }
                let snapshot = self.audioCapture.snapshotFloat16kHz()
                guard snapshot.rawSampleCount > lastSampleCount, snapshot.samples.count >= 4_800 else {
                    continue
                }
                lastSampleCount = snapshot.rawSampleCount
                do {
                    let partial = try await self.coreMLParakeet.transcribe(samples16kHz: snapshot.samples)
                    guard !Task.isCancelled, model.session.state == .listening else { break }
                    let displayText = TextInsertionEdit.sanitizedInsertionText(partial)
                    guard !displayText.isEmpty, displayText != model.captionText else { continue }
                    model.session.receivePartial(displayText)
                    self.updateLiveDraft(with: displayText)
                    model.captionText = displayText
                    self.showOverlay(
                        text: displayText,
                        styleName: model.preferences.style.displayName,
                        level: self.lastInputLevel,
                        anchorFrame: self.activeOverlayAnchor
                    )
                } catch {
                    // Ignore transient partial decode misses; final stop pass will transcribe full WAV.
                }
            }
        }
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
