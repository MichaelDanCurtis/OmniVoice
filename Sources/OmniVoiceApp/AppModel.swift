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
    var lastTestResult: String

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
        lastTestResult: String = "No test run yet"
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
        self.lastTestResult = lastTestResult
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

    func refreshEngineStatus() async {
        engineState = .checking
        do {
            _ = try await engineClient.health()
            providerStatuses = try await engineClient.providers()
            modelStatuses = try await engineClient.models()
            engineState = .online
            statusText = "Engine online"
        } catch {
            providerStatuses = []
            modelStatuses = []
            engineState = .offline(error.localizedDescription)
            statusText = "Engine offline"
        }
    }

    func refreshModelStatus() async {
        do {
            modelStatuses = try await engineClient.models()
        } catch {
            statusText = "Model status refresh failed"
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

    private func persistPreferences() {
        do {
            try preferencesStore.save(preferences)
        } catch {
            statusText = "Preferences save failed"
        }
    }
}
