import Foundation
import OmniVoiceCore

/// Dictation productivity stats, Voice Snippets, Command Mode preferences/planning,
/// Zero-Config Translation, Highlight & Transform (Voice Edit), and debounced slider writes.
extension AppModel {
    private static let dictationStatsDefaultsKey = "OmniSpeak.dictationStats.v1"

    static func loadDictationStats() -> DictationStatsSnapshot {
        guard let data = UserDefaults.standard.data(forKey: dictationStatsDefaultsKey),
              let decoded = try? JSONDecoder().decode(DictationStatsSnapshot.self, from: data) else {
            return DictationStatsSnapshot()
        }
        return decoded
    }

    func recordDictationStats(text: String, speakingSeconds: Double, appName: String?) {
        dictationStats.record(text: text, speakingSeconds: speakingSeconds, appName: appName)
        if let data = try? JSONEncoder().encode(dictationStats) {
            UserDefaults.standard.set(data, forKey: Self.dictationStatsDefaultsKey)
        }
    }

    func setCommandModeCorner(_ corner: CommandModeCorner) {
        guard preferences.commandModeCorner != corner else { return }
        preferences.commandModeCorner = corner
        _ = persistPreferences()
        onThemeChanged?(activeTheme, preferences.appearanceMode)
    }

    func cycleCommandModeCorner() {
        setCommandModeCorner(preferences.commandModeCorner.next)
    }

    func setCommandModeMCPCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "cua-driver" : trimmed
        guard preferences.commandModeMCPCommand != resolved else { return }
        preferences.commandModeMCPCommand = resolved
        _ = persistPreferences()
    }

    func addVoiceSnippet(trigger: String, expansion: String) {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTrigger.isEmpty, !cleanExpansion.isEmpty else { return }
        preferences.voiceSnippets.append(VoiceSnippet(trigger: cleanTrigger, expansion: cleanExpansion))
        _ = persistPreferences()
        statusText = "Snippet “\(cleanTrigger)” added"
    }

    func removeVoiceSnippet(id: String) {
        preferences.voiceSnippets.removeAll { $0.id == id }
        _ = persistPreferences()
    }

    func setAutoTonePerAppEnabled(_ enabled: Bool) {
        guard preferences.autoTonePerAppEnabled != enabled else { return }
        preferences.autoTonePerAppEnabled = enabled
        _ = persistPreferences()
    }

    func setVoiceEditSelectionEnabled(_ enabled: Bool) {
        guard preferences.voiceEditSelectionEnabled != enabled else { return }
        preferences.voiceEditSelectionEnabled = enabled
        _ = persistPreferences()
    }

    func setClipboardAskContextEnabled(_ enabled: Bool) {
        guard preferences.clipboardAskContextEnabled != enabled else { return }
        preferences.clipboardAskContextEnabled = enabled
        _ = persistPreferences()
    }

    func setCaptionGlassOpacity(_ opacity: Double) {
        let clamped = min(max(opacity, 0), 1)
        guard abs(preferences.captionGlassOpacity - clamped) > 0.001 else { return }
        preferences.captionGlassOpacity = clamped
        persistPreferencesDebounced()
        onThemeChanged?(activeTheme, preferences.appearanceMode)
        onCaptionGlassOpacityChanged?(clamped)
    }

    func persistPreferencesDebounced(delayMs: Int = 220) {
        debouncedPersistTask?.cancel()
        debouncedPersistTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMs))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            _ = self?.persistPreferences()
        }
    }

    func selectQuickTranslationLanguage(_ code: String?) {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            preferences.liveTranslationEnabled = false
            _ = persistPreferences()
            statusText = "Live translation off"
            return
        }
        preferences.translationTargetLanguage = code.lowercased()
        preferences.liveTranslationEnabled = true
        _ = persistPreferences()
        let label = InlineTranslationParser.languageInfo(forCode: code)?.name ?? code.uppercased()
        statusText = "Translating to \(label)"
    }

    /// Zero-config translation: honors Service Mode when enabled, then engine translator,
    /// seamlessly falling back to on-device MLX-Swift Qwen3 or configured Text LLM.
    func translateTextZeroConfig(
        _ text: String,
        targetLanguageCode: String,
        targetLanguageName: String? = nil
    ) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let languageName = targetLanguageName
            ?? InlineTranslationParser.languageInfo(forCode: targetLanguageCode)?.name
            ?? targetLanguageCode.uppercased()

        if preferences.serviceMode.enabled {
            if let result = await runServiceModeLLM(
                systemPrompt: "Translate the user's text into \(languageName). Output ONLY the translation with no commentary or quotes.",
                userPrompt: trimmed
            ) {
                let cleaned = TextInsertionEdit.sanitizedInsertionText(result)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        if selectedTranslationModelInstalled {
            if let result = try? await engineClient.translate(
                TranslationRequest(
                    text: trimmed,
                    provider: preferences.translationProvider,
                    sourceLanguage: preferences.translationSourceLanguage,
                    targetLanguage: targetLanguageCode,
                    context: [trimmed],
                    modelPath: effectiveTranslationModelPath()
                )
            ) {
                let cleaned = TextInsertionEdit.sanitizedInsertionText(result.text)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        if preferences.defaultAIRoute != .auto, preferences.defaultAIRoute != .localMLX {
            if let result = await runUnifiedAIPrompt(
                systemPrompt: "Translate the user's text into \(languageName). Output ONLY the translation with no commentary or quotes.",
                userPrompt: trimmed
            ) {
                let cleaned = TextInsertionEdit.sanitizedInsertionText(result)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        if let local = try? await MLXLocalCleanupService.shared.translate(
            text: trimmed,
            targetLanguage: languageName,
            providerID: preferences.llmCleanupLocalModelID
        ) {
            let cleaned = TextInsertionEdit.sanitizedInsertionText(local)
            if !cleaned.isEmpty { return cleaned }
        }

        if let result = await runUnifiedAIPrompt(
            systemPrompt: "Translate the user's text into \(languageName). Output ONLY the translation with no commentary or quotes.",
            userPrompt: trimmed
        ) {
            let cleaned = TextInsertionEdit.sanitizedInsertionText(result)
            if !cleaned.isEmpty { return cleaned }
        }

        return nil
    }

    private var selectedTranslationModelInstalled: Bool {
        modelStatus(forProviderID: selectedTranslationModelProviderID())?.installed == true
    }

    /// Rewrites currently highlighted text according to a spoken instruction ("make this shorter", etc.).
    func transformSelectedText(_ selectedText: String, instruction: String) async -> String? {
        let systemPrompt = "You are a crisp inline text editor. Apply the user's instruction to the selected text and return ONLY the transformed text with no quotes or preamble."
        let userPrompt = "Instruction: \(instruction)\n\nSelected text:\n\(selectedText)"

        if preferences.serviceMode.enabled {
            if let cloud = await runServiceModeLLM(systemPrompt: systemPrompt, userPrompt: userPrompt) {
                let cleaned = TextInsertionEdit.sanitizedInsertionText(cloud)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        if preferences.defaultAIRoute != .localMLX {
            if let unified = await runUnifiedAIPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt) {
                let cleaned = TextInsertionEdit.sanitizedInsertionText(unified)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        if let local = try? await MLXLocalCleanupService.shared.transformSelection(
            selectedText: selectedText,
            instruction: instruction,
            providerID: preferences.llmCleanupLocalModelID
        ) {
            let cleaned = TextInsertionEdit.sanitizedInsertionText(local)
            if !cleaned.isEmpty { return cleaned }
        }

        if let fallback = await runUnifiedAIPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt) {
            let cleaned = TextInsertionEdit.sanitizedInsertionText(fallback)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    func planCommandModeTools(systemPrompt: String, userPrompt: String) async -> String? {
        if preferences.serviceMode.enabled,
           let servicePlan = await runServiceModeLLM(systemPrompt: systemPrompt, userPrompt: userPrompt) {
            return servicePlan
        }
        if let unified = await runUnifiedAIPrompt(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            sanitize: false
        ) {
            return unified
        }
        return try? await MLXLocalCleanupService.shared.generateRaw(
            instructions: systemPrompt,
            prompt: userPrompt,
            maxTokens: 512,
            providerID: preferences.llmCleanupLocalModelID
        )
    }
}
