import AppKit
import Foundation
import OmniVoiceCore

/// Ember (Fuego) & Inferno integration on AppModel:
/// auto-detects local Inferno CLI + Fuego Desktop, manages Keychain token storage,
/// toggles optional Ask AI delegation to Ember, and keeps Command Mode native to OmniSpeak.
extension AppModel {
    var effectiveEmberAPIToken: String {
        let direct = emberAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        for envKey in ["EMBER_API_TOKEN", "FUEGO_API_TOKEN"] {
            if let value = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return ""
    }

    /// True when the user turned on Ember delegation for Ask AI AND either standalone Ember.app
    /// (local `ember-engine :8780`) or a remote Fuego Ember endpoint is available.
    var isEmberDelegationActive: Bool {
        preferences.emberDelegation.enabled && isEmberBackendReady
    }

    var isEmberBackendReady: Bool {
        preferences.emberDelegation.isConfigured || emberInfernoEnvironment.isLocalEmberEngineAvailable
    }

    var emberStatusSummary: String {
        if preferences.emberDelegation.enabled {
            if emberInfernoEnvironment.isLocalEmberEngineAvailable && !preferences.emberDelegation.isConfigured {
                return "Delegating Ask AI → Ember (Local)"
            }
            return isEmberBackendReady
                ? "Delegating Ask AI → Ember"
                : "Ember on — install Ember.app or set Server IDs"
        }
        if emberInfernoEnvironment.emberAppPath != nil {
            return "Ember.app Ready · Off"
        }
        if emberInfernoEnvironment.isEmberOrFuegoDetectedLocally {
            return "Fuego / Ember detected · Off"
        }
        return "Off (OmniSpeak handles Ask AI)"
    }

    func refreshEmberInfernoEnvironment() async {
        let envStatus = await Task.detached(priority: .utility) {
            EmberClient.detectLocalInstallations()
        }.value
        emberInfernoEnvironment = envStatus

        if let binary = envStatus.infernoBinaryPath {
            let agents = await EmberClient.fetchInfernoInstalledAgents(binaryPath: binary)
            if !agents.isEmpty {
                infernoInstalledAgents = agents
            }
        }
    }

    func setEmberDelegationEnabled(_ enabled: Bool) {
        guard preferences.emberDelegation.enabled != enabled else { return }
        preferences.emberDelegation.enabled = enabled
        _ = persistPreferences()
        onCustomAgentsChanged?(preferences.customAgents)
        statusText = enabled
            ? (isEmberBackendReady
                ? "Ask AI delegated to Ember (Command Mode stays OmniSpeak)"
                : "Ember delegation enabled — install Ember.app or finish setup in Settings → AI")
            : "Ask AI handled by OmniSpeak (\(resolvedUnifiedAILabel))"
    }

    func setEmberServerURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.emberDelegation.serverURL != trimmed else { return }
        preferences.emberDelegation.serverURL = trimmed
        emberConnectionStatus = nil
        _ = persistPreferences()
        onCustomAgentsChanged?(preferences.customAgents)
    }

    func setEmberCompanyID(_ companyID: String) {
        let trimmed = companyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.emberDelegation.companyID != trimmed else { return }
        preferences.emberDelegation.companyID = trimmed
        emberConnectionStatus = nil
        _ = persistPreferences()
        onCustomAgentsChanged?(preferences.customAgents)
    }

    func setEmberAgentID(_ agentID: String) {
        let trimmed = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.emberDelegation.agentID != trimmed else { return }
        preferences.emberDelegation.agentID = trimmed
        emberConnectionStatus = nil
        _ = persistPreferences()
        onCustomAgentsChanged?(preferences.customAgents)
    }

    func setEmberAPIToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard emberAPIToken != trimmed else { return }
        emberAPIToken = trimmed
        emberConnectionStatus = nil
        _ = llmSecretStore.setValue(trimmed, provider: Self.emberSecretProviderID, field: .apiKey)
    }

    func setInfernoDefaultAgentID(_ agentID: String) {
        let trimmed = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? EmberDelegationConfiguration.defaultInfernoAgentID : trimmed
        guard preferences.emberDelegation.infernoAgentID != resolved else { return }
        preferences.emberDelegation.infernoAgentID = resolved
        _ = persistPreferences()
        onCustomAgentsChanged?(preferences.customAgents)
        statusText = "Inferno default agent → \(resolved)"
    }

    func testEmberConnection() async {
        guard isEmberBackendReady else {
            emberConnectionStatus = "Install Ember.app or enter Ember Server URL, Company ID, and Agent ID first."
            return
        }
        isTestingEmberConnection = true
        emberConnectionStatus = "Connecting to Ember…"
        defer { isTestingEmberConnection = false }

        do {
            let summary = try await EmberClient.testConnection(
                config: preferences.emberDelegation,
                apiToken: effectiveEmberAPIToken
            )
            emberConnectionStatus = summary
        } catch {
            emberConnectionStatus = error.localizedDescription
        }
    }

    /// Summons (focuses or launches) the standalone Ember agent (`Ember.app`),
    /// optionally forwarding an immediate spoken message to `ember-engine :8780` or remote Ember.
    @discardableResult
    func summonEmber(initialMessage: String? = nil) async -> String {
        let outcome = await EmberClient.summonEmberApp(config: preferences.emberDelegation)
        await refreshEmberInfernoEnvironment()

        let baseSummary: String
        switch outcome {
        case .focusedStandaloneEmber:
            baseSummary = "Ember is ready"
        case .launchedStandaloneEmber:
            baseSummary = "Opened Ember"
        case .openedFuegoDesktop:
            baseSummary = "Opened Fuego Desktop"
        case .openedRemoteURL:
            baseSummary = "Opened Ember in browser"
        case .notInstalled:
            statusText = "Ember isn't installed on this Mac"
            return "Ember isn't installed — install Ember.app or set Ember Server URL in Settings → AI"
        }

        let cleanedMessage = initialMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanedMessage.isEmpty else {
            statusText = baseSummary
            return baseSummary
        }

        // Wait briefly for local ember-engine (:8780) if Ember.app just cold-started, then send the spoken prompt.
        let config = preferences.emberDelegation
        let token = effectiveEmberAPIToken
        Task.detached(priority: .userInitiated) {
            if outcome == .launchedStandaloneEmber {
                _ = await EmberClient.waitForLocalEngine(timeoutSeconds: 6.0)
            }
            _ = try? await EmberClient.sendMessage(
                prompt: cleanedMessage,
                config: config,
                apiToken: token
            )
        }
        let sentSummary = "Sent to Ember: “\(String(cleanedMessage.prefix(64)))”"
        statusText = sentSummary
        return sentSummary
    }

    func openEmberOrFuegoDesktop() {
        Task { @MainActor in
            _ = await summonEmber(initialMessage: nil)
        }
    }

    func openInfernoApp() {
        if let appPath = emberInfernoEnvironment.infernoAppPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
            statusText = "Opened Inferno"
        } else if let url = URL(string: "inferno://") {
            NSWorkspace.shared.open(url)
        }
    }
}
