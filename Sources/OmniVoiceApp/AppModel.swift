import Foundation
import Observation
import OmniVoiceCore

enum EngineConnectionState: Equatable {
    case unknown
    case checking
    case online
    case offline(String)

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .checking: "Checking"
        case .online: "Online"
        case .offline: "Offline"
        }
    }

    var detail: String {
        switch self {
        case .unknown: "Not checked yet"
        case .checking: "Checking local engine"
        case .online: "127.0.0.1:8765"
        case .offline(let message): message
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var preferences: OmniVoicePreferences
    var session: DictationSession
    var captionText: String
    var statusText: String
    var engineState: EngineConnectionState
    var providerStatuses: [EngineProviderInfo]
    var modelStatuses: [EngineModelStatus]
    var modelUpdateInfo: EngineModelUpdateInfo?
    var modelDownloadStatus: EngineModelDownloadStatus?
    var transcripts: [EngineTranscriptRecord]
    var microphoneDevices: [MicrophoneDevice]
    var lastTestResult: String
    var microphoneAuthorized: Bool
    var accessibilityTrusted: Bool
    var streamingDiagnostics: EngineStreamingDiagnostics

    private let preferencesStore: PreferencesStore
    private let engineClient: EngineClient
    @ObservationIgnored var onHotkeysChanged: ((OmniVoicePreferences) -> Void)?

    init(
        preferences: OmniVoicePreferences? = nil,
        preferencesStore: PreferencesStore = PreferencesStore(),
        engineClient: EngineClient = EngineClient(),
        session: DictationSession = DictationSession(),
        captionText: String = "",
        statusText: String = "Ready",
        engineState: EngineConnectionState = .unknown,
        providerStatuses: [EngineProviderInfo] = [],
        modelStatuses: [EngineModelStatus] = [],
        modelUpdateInfo: EngineModelUpdateInfo? = nil,
        modelDownloadStatus: EngineModelDownloadStatus? = nil,
        transcripts: [EngineTranscriptRecord] = [],
        microphoneDevices: [MicrophoneDevice] = MicrophoneDeviceService.inputDevices(),
        lastTestResult: String = "No test run yet",
        microphoneAuthorized: Bool = false,
        accessibilityTrusted: Bool = false,
        streamingDiagnostics: EngineStreamingDiagnostics = .idle
    ) {
        self.preferencesStore = preferencesStore
        self.engineClient = engineClient
        self.preferences = preferences ?? (try? preferencesStore.load()) ?? .defaults
        self.session = session
        self.captionText = captionText
        self.statusText = statusText
        self.engineState = engineState
        self.providerStatuses = providerStatuses
        self.modelStatuses = modelStatuses
        self.modelUpdateInfo = modelUpdateInfo
        self.modelDownloadStatus = modelDownloadStatus
        self.transcripts = transcripts
        self.microphoneDevices = microphoneDevices
        self.lastTestResult = lastTestResult
        self.microphoneAuthorized = microphoneAuthorized
        self.accessibilityTrusted = accessibilityTrusted
        self.streamingDiagnostics = streamingDiagnostics
    }

    var activeTheme: OmniVoiceTheme {
        let baseTheme: OmniVoiceTheme = if preferences.themeID == .custom {
            .custom(accent: preferences.customAccentColor)
        } else {
            OmniVoiceTheme.builtInTheme(id: preferences.themeID) ?? .defaultTheme
        }

        return baseTheme.withModes(
            waveformMode: preferences.waveformMode,
            commitAnimationMode: preferences.commitAnimationMode,
            engineFrameSide: preferences.engineFrameSide
        )
    }

    func cycleStyle() {
        setStyle(preferences.style.next())
    }

    func cycleASRProvider() {
        preferences.cycleASRProvider()
        persistPreferences()
        statusText = "ASR: \(preferences.asrProvider.rawValue)"
    }

    func setStyle(_ style: StyleProfile) {
        preferences.style = style
        persistPreferences()
        statusText = "Style: \(style.displayName)"
    }

    func setASRProvider(_ provider: ASRProviderKind) {
        preferences.asrProvider = provider
        persistPreferences()
        modelUpdateInfo = nil
        modelDownloadStatus = nil
        statusText = "ASR: \(provider.rawValue)"
    }

    func setMicrophoneID(_ microphoneID: String?) {
        preferences.microphoneID = microphoneID
        persistPreferences()
        statusText = "Microphone: \(microphoneLabel(for: microphoneID))"
    }

    func setThemeID(_ themeID: OmniVoiceThemeID) {
        let presetTheme = themeID == .custom ? nil : OmniVoiceTheme.builtInTheme(id: themeID)
        let waveformMode = presetTheme?.waveformMode ?? preferences.waveformMode
        let commitAnimationMode = presetTheme?.commitAnimationMode ?? preferences.commitAnimationMode
        let engineFrameSide = presetTheme?.engineFrameSide ?? preferences.engineFrameSide

        guard preferences.themeID != themeID ||
            preferences.waveformMode != waveformMode ||
            preferences.commitAnimationMode != commitAnimationMode ||
            preferences.engineFrameSide != engineFrameSide else {
            return
        }

        preferences.themeID = themeID
        preferences.waveformMode = waveformMode
        preferences.commitAnimationMode = commitAnimationMode
        preferences.engineFrameSide = engineFrameSide
        guard persistPreferences() else {
            return
        }

        statusText = "Theme: \(activeTheme.name)"
    }

    func setCustomAccentColor(_ color: ThemeColor) {
        guard preferences.customAccentColor != color || preferences.themeID != .custom else {
            return
        }

        preferences.customAccentColor = color
        preferences.themeID = .custom
        guard persistPreferences() else {
            return
        }

        statusText = "Custom accent: \(color.hex)"
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        guard preferences.appearanceMode != mode else {
            return
        }

        preferences.appearanceMode = mode
        guard persistPreferences() else {
            return
        }

        statusText = "Appearance: \(mode.displayName)"
    }

    func setWaveformMode(_ mode: WaveformMode) {
        guard preferences.waveformMode != mode else {
            return
        }

        preferences.waveformMode = mode
        guard persistPreferences() else {
            return
        }

        statusText = "Waveform: \(mode.displayName)"
    }

    func setEngineFrameSide(_ side: EngineFrameSide) {
        guard preferences.engineFrameSide != side else {
            return
        }

        preferences.engineFrameSide = side
        guard persistPreferences() else {
            return
        }

        statusText = "Engine frame: \(side.displayName)"
    }

    func setEngineFrameHandlePosition(_ position: Double) {
        let clamped = OmniVoicePreferences.clampedHandlePosition(position)
        guard abs(preferences.engineFrameHandlePosition - clamped) > 0.005 else {
            return
        }

        preferences.engineFrameHandlePosition = clamped
        guard persistPreferences() else {
            return
        }

        statusText = "History handle moved"
    }

    func setCustomSpeechModelPath(_ path: String) {
        guard preferences.customSpeechModelPath != path else {
            return
        }

        preferences.customSpeechModelPath = path
        guard persistPreferences() else {
            return
        }

        statusText = path.isEmpty ? "Custom speech model cleared" : "Custom speech model selected"
    }

    func setCustomTranslationModelPath(_ path: String) {
        guard preferences.customTranslationModelPath != path else {
            return
        }

        preferences.customTranslationModelPath = path
        guard persistPreferences() else {
            return
        }

        statusText = path.isEmpty ? "Translation model cleared" : "Translation model selected"
    }

    func setLiveTranslationEnabled(_ enabled: Bool) {
        guard preferences.liveTranslationEnabled != enabled else {
            return
        }

        preferences.liveTranslationEnabled = enabled
        guard persistPreferences() else {
            return
        }

        statusText = enabled ? "Live translation enabled" : "Live translation disabled"
    }

    func setLiveDraftInsertionEnabled(_ enabled: Bool) {
        guard preferences.liveDraftInsertionEnabled != enabled else {
            return
        }

        preferences.liveDraftInsertionEnabled = enabled
        guard persistPreferences() else {
            return
        }

        statusText = enabled ? "Live draft typing enabled" : "Live draft typing disabled"
    }

    func setTranslationSourceLanguage(_ language: String) {
        let normalized = normalizedLanguageCode(language, fallback: "auto")
        guard preferences.translationSourceLanguage != normalized else {
            return
        }

        preferences.translationSourceLanguage = normalized
        guard persistPreferences() else {
            return
        }

        statusText = "Translation source: \(normalized)"
    }

    func setTranslationTargetLanguage(_ language: String) {
        let normalized = normalizedLanguageCode(language, fallback: "en")
        guard preferences.translationTargetLanguage != normalized else {
            return
        }

        preferences.translationTargetLanguage = normalized
        guard persistPreferences() else {
            return
        }

        statusText = "Translation target: \(normalized)"
    }

    func setOpenAICompatibleBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.openAICompatibleBaseURL != trimmed else {
            return
        }

        preferences.openAICompatibleBaseURL = trimmed
        guard persistPreferences() else {
            return
        }

        statusText = trimmed.isEmpty ? "AI endpoint cleared" : "AI endpoint updated"
    }

    func setOpenAICompatibleModel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.openAICompatibleModel != trimmed else {
            return
        }

        preferences.openAICompatibleModel = trimmed
        guard persistPreferences() else {
            return
        }

        statusText = trimmed.isEmpty ? "AI model cleared" : "AI model updated"
    }

    func setDictationHotkey(_ binding: HotkeyBinding) {
        guard binding != preferences.styleHotkey else {
            statusText = "Hotkeys must be different"
            return
        }
        preferences.dictationHotkey = binding
        persistPreferences()
        onHotkeysChanged?(preferences)
        statusText = "Dictation hotkey: \(binding.displayName)"
    }

    func setStyleHotkey(_ binding: HotkeyBinding) {
        guard binding != preferences.dictationHotkey else {
            statusText = "Hotkeys must be different"
            return
        }
        preferences.styleHotkey = binding
        persistPreferences()
        onHotkeysChanged?(preferences)
        statusText = "Style hotkey: \(binding.displayName)"
    }

    func setDictionaryTermsText(_ text: String) {
        preferences.dictionaryTerms = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        persistPreferences()
        statusText = "Dictionary updated"
    }

    func refreshEngineStatus() async {
        engineState = .checking
        await loadEngineStatus(startEngineIfOffline: true)
    }

    func restartEngine() async {
        engineState = .checking
        statusText = "Restarting engine"

        let startResult = await EngineSupervisor.shared.restart()
        switch startResult {
        case .alreadyOnline, .started:
            await loadEngineStatus(startEngineIfOffline: false)
        case .stillStarting, .unavailable, .failed:
            providerStatuses = []
            modelStatuses = []
            transcripts = []
            engineState = .offline(startResult.detail)
            statusText = startResult.detail
        }
    }

    private func loadEngineStatus(startEngineIfOffline: Bool) async {
        do {
            _ = try await engineClient.health()
            providerStatuses = try await engineClient.providers()
            modelStatuses = try await engineClient.models()
            transcripts = (try? await engineClient.transcripts(limit: 100)) ?? transcripts
            engineState = .online
            statusText = "Engine online"
        } catch {
            if startEngineIfOffline {
                let startResult = await EngineSupervisor.shared.startIfNeeded()
                switch startResult {
                case .alreadyOnline, .started:
                    await loadEngineStatus(startEngineIfOffline: false)
                    return
                case .stillStarting, .unavailable, .failed:
                    providerStatuses = []
                    modelStatuses = []
                    transcripts = []
                    engineState = .offline(startResult.detail)
                    statusText = startResult.detail
                    return
                }
            }
            providerStatuses = []
            modelStatuses = []
            transcripts = []
            engineState = .offline(error.localizedDescription)
            statusText = "Engine offline"
        }
    }

    func refreshTranscripts() async {
        do {
            transcripts = try await engineClient.transcripts(limit: 100)
            statusText = "Conversation history refreshed"
        } catch {
            statusText = "Conversation history unavailable"
        }
    }

    func refreshModelStatus() async {
        do {
            modelStatuses = try await engineClient.models()
        } catch {
            statusText = "Model status refresh failed"
        }
    }

    func refreshMicrophones() {
        microphoneDevices = MicrophoneDeviceService.inputDevices()
        if let microphoneID = preferences.microphoneID,
           !microphoneDevices.contains(where: { $0.id == microphoneID }) {
            statusText = "Selected microphone is not connected"
        } else {
            statusText = "Microphones refreshed"
        }
    }

    func checkSelectedModelUpdate() async {
        guard preferences.asrProvider != .fake else {
            statusText = "Fake ASR has no model download"
            return
        }

        do {
            let update = try await engineClient.checkModelUpdate(provider: preferences.asrProvider)
            modelUpdateInfo = update
            statusText = update.updateAvailable ? "Model update available" : "Model is current"
        } catch {
            statusText = "Model update check failed"
        }
    }

    func downloadSelectedModel() async {
        guard preferences.asrProvider != .fake else {
            statusText = "Fake ASR has no model download"
            return
        }

        do {
            let download = try await engineClient.downloadModel(provider: preferences.asrProvider)
            modelDownloadStatus = download
            statusText = download.message ?? "Model download queued"
            await pollModelDownload(provider: preferences.asrProvider)
        } catch {
            statusText = "Model download failed"
        }
    }

    func runCleanupTest() async {
        lastTestResult = "Running..."
        do {
            let result = try await engineClient.cleanup(
                CleanupRequest(
                    rawTranscript: "I am going to the store. No wait, I am going to the house.",
                    style: preferences.style,
                    dictionaryTerms: preferences.dictionaryTerms
                )
            )
            lastTestResult = result.text
            statusText = "Cleanup test passed"
        } catch {
            lastTestResult = error.localizedDescription
            statusText = "Cleanup test failed"
        }
    }

    func providerInfo(for provider: ASRProviderKind) -> EngineProviderInfo? {
        providerStatuses.first { $0.id == provider.rawValue }
    }

    func modelStatus(for provider: ASRProviderKind) -> EngineModelStatus? {
        modelStatuses.first { $0.providerID == provider.rawValue }
    }

    func label(for provider: ASRProviderKind) -> String {
        providerInfo(for: provider)?.label ?? provider.rawValue
    }

    func microphoneLabel(for microphoneID: String?) -> String {
        guard let microphoneID else {
            return "System Default"
        }

        return microphoneDevices.first { $0.id == microphoneID }?.displayName ?? "Missing: \(microphoneID)"
    }

    private func pollModelDownload(provider: ASRProviderKind) async {
        for _ in 0..<300 {
            do {
                let current = try await engineClient.modelDownloadStatus(provider: provider)
                modelDownloadStatus = current
                statusText = current.message ?? "Model \(current.state)"
                if current.state == "completed" || current.state == "failed" {
                    modelStatuses = try await engineClient.models()
                    return
                }
            } catch {
                statusText = "Model download status failed"
                return
            }

            try? await Task.sleep(for: .seconds(2))
        }
    }

    @discardableResult
    private func persistPreferences() -> Bool {
        do {
            try preferencesStore.save(preferences)
            return true
        } catch {
            statusText = "Preferences save failed"
            return false
        }
    }

    private func normalizedLanguageCode(_ language: String, fallback: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? fallback : trimmed
    }
}
