import Foundation
import Observation
import OmniVoiceCore

@MainActor
@Observable
final class AppModel {
    var preferences: OmniVoicePreferences
    var session: DictationSession
    var captionText: String
    var statusText: String

    private let preferencesStore: PreferencesStore

    init(
        preferences: OmniVoicePreferences? = nil,
        preferencesStore: PreferencesStore = PreferencesStore(),
        session: DictationSession = DictationSession(),
        captionText: String = "",
        statusText: String = "Ready"
    ) {
        self.preferencesStore = preferencesStore
        self.preferences = preferences ?? (try? preferencesStore.load()) ?? .defaults
        self.session = session
        self.captionText = captionText
        self.statusText = statusText
    }

    func cycleStyle() {
        preferences.cycleStyle()
        persistPreferences()
        statusText = "Style: \(preferences.style.displayName)"
    }

    func cycleASRProvider() {
        preferences.cycleASRProvider()
        persistPreferences()
        statusText = "ASR: \(preferences.asrProvider.rawValue)"
    }

    private func persistPreferences() {
        do {
            try preferencesStore.save(preferences)
        } catch {
            statusText = "Preferences save failed"
        }
    }
}
