import AppKit
import Foundation
import OmniVoiceCore

struct EmberInfernoEnvironmentStatus: Equatable, Sendable {
    var infernoBinaryPath: String?
    var infernoAppPath: String?
    var fuegoDesktopAppPath: String?
    var emberAppPath: String?
    var emberEngineTokenPath: String?
    var fuegoRuntimeDetected: Bool = false

    var isInfernoAvailable: Bool {
        infernoBinaryPath != nil || infernoAppPath != nil
    }

    var isLocalEmberEngineAvailable: Bool {
        emberAppPath != nil || emberEngineTokenPath != nil
    }

    var isEmberOrFuegoDetectedLocally: Bool {
        emberAppPath != nil || emberEngineTokenPath != nil || fuegoDesktopAppPath != nil || fuegoRuntimeDetected
    }
}

enum EmberSummonOutcome: Equatable, Sendable {
    case focusedStandaloneEmber
    case launchedStandaloneEmber
    case openedFuegoDesktop
    case openedRemoteURL(String)
    case notInstalled
}

enum EmberClientError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case httpError(Int, String)
    case turnFailed(String)
    case timedOut
    case infernoUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Configure Ember Server URL, Company ID, and Agent ID in Settings → AI → Ember & Inferno."
        case .invalidEndpoint:
            "Invalid Ember server URL. Check Settings → AI → Ember & Inferno."
        case .httpError(let code, let detail):
            code == 401 || code == 403
                ? "Ember authentication failed (HTTP \(code)). Add a valid Fuego API or session token in Settings → AI."
                : "Ember returned HTTP \(code): \(detail)"
        case .turnFailed(let detail):
            "Ember turn failed: \(detail)"
        case .timedOut:
            "Ember did not reply within 90 seconds. Check Fuego Desktop or your Ember server."
        case .infernoUnavailable:
            "Inferno CLI was not found on this Mac. Install Inferno or check ~/.local/bin/inferno."
        }
    }
}

/// Async client for delegating Ask AI requests to Ember (Fuego Conversation API)
/// and running agent sessions via the local Inferno (`orca`) CLI.
enum EmberClient {
    static let standaloneBundleIdentifier = "com.ember.standalone"
    static let localEngineBaseURL = "http://127.0.0.1:8780"

    static func detectLocalInstallations() -> EmberInfernoEnvironmentStatus {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        let infernoBinaryCandidates = [
            "\(home)/.local/bin/inferno",
            "/usr/local/bin/inferno",
            "/opt/homebrew/bin/inferno",
        ]
        let infernoBinary = infernoBinaryCandidates.first(where: { fm.isExecutableFile(atPath: $0) })
            ?? AgentRegistry.defaultBuiltIns
                .first(where: { $0.id == "inferno" })
                .flatMap { ExecutableResolver.resolve($0) }

        let infernoAppCandidates = [
            "\(home)/Applications/Inferno.app",
            "/Applications/Inferno.app",
        ]
        let infernoApp = infernoAppCandidates.first(where: { fm.fileExists(atPath: $0) })

        let fuegoAppCandidates = [
            "\(home)/Applications/Fuego Desktop.app",
            "/Applications/Fuego Desktop.app",
        ]
        let fuegoApp = fuegoAppCandidates.first(where: { fm.fileExists(atPath: $0) })

        let emberAppCandidates = [
            "\(home)/Applications/Ember.app",
            "/Applications/Ember.app",
        ]
        let emberApp = emberAppCandidates.first(where: { fm.fileExists(atPath: $0) })
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: standaloneBundleIdentifier)?.path

        let engineTokenCandidate = "\(home)/Library/Application Support/Ember/engine-token"
        let engineTokenPath = fm.fileExists(atPath: engineTokenCandidate) ? engineTokenCandidate : nil

        let fuegoSupportDir = "\(home)/Library/Application Support/Fuego"
        let fuegoRuntime = fm.fileExists(atPath: fuegoSupportDir)

        return EmberInfernoEnvironmentStatus(
            infernoBinaryPath: infernoBinary,
            infernoAppPath: infernoApp,
            fuegoDesktopAppPath: fuegoApp,
            emberAppPath: emberApp,
            emberEngineTokenPath: engineTokenPath,
            fuegoRuntimeDetected: fuegoRuntime
        )
    }

    static func readLocalEngineToken() -> String? {
        let tokenURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ember/engine-token")
        guard let raw = try? String(contentsOf: tokenURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isLocalEngineHealthy() async -> Bool {
        guard let url = URL(string: "\(localEngineBaseURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.8
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return (200...299).contains(http.statusCode)
    }

    static func waitForLocalEngine(timeoutSeconds: Double = 6.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await isLocalEngineHealthy() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return await isLocalEngineHealthy()
    }

    /// Brings up or launches standalone `Ember.app` (`com.ember.standalone`),
    /// falling back to `Fuego Desktop.app` or a configured remote Ember URL.
    @MainActor
    static func summonEmberApp(config: EmberDelegationConfiguration) async -> EmberSummonOutcome {
        let env = detectLocalInstallations()
        let openConfig = NSWorkspace.OpenConfiguration()
        openConfig.activates = true

        // 1. Focus already-running standalone Ember.app (bringing it forward across Spaces)
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == standaloneBundleIdentifier
                || ($0.activationPolicy == .regular && ($0.localizedName ?? "").lowercased() == "ember")
        }) {
            running.activate(options: [.activateAllWindows])
            if let bundleURL = running.bundleURL ?? env.emberAppPath.map({ URL(fileURLWithPath: $0) }) {
                _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: openConfig)
            }
            return .focusedStandaloneEmber
        }

        // 2. Launch standalone Ember.app (which also auto-starts local ember-engine :8780)
        if let appPath = env.emberAppPath {
            let url = URL(fileURLWithPath: appPath)
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: openConfig)
            return .launchedStandaloneEmber
        }

        // 3. Fallback: Fuego Desktop.app
        if let fuegoPath = env.fuegoDesktopAppPath {
            let url = URL(fileURLWithPath: fuegoPath)
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: openConfig)
            return .openedFuegoDesktop
        }

        // 4. Fallback: configured remote Ember server URL
        if config.isConfigured, let remoteURL = URL(string: config.trimmedServerURL) {
            NSWorkspace.shared.open(remoteURL)
            return .openedRemoteURL(config.trimmedServerURL)
        }

        return .notInstalled
    }

    static func testConnection(
        config: EmberDelegationConfiguration,
        apiToken: String
    ) async throws -> String {
        if await isLocalEngineHealthy(), let localToken = readLocalEngineToken() {
            if let statusURL = URL(string: "\(localEngineBaseURL)/api/ember/status") {
                let (data, http) = try await performLocalEngineRequest(
                    url: statusURL,
                    method: "GET",
                    body: nil,
                    engineToken: localToken
                )
                if (200...299).contains(http.statusCode),
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let cloudLinked = (root["cloudConnected"] as? Bool) == true
                    return cloudLinked
                        ? "Connected to Local Ember Engine (127.0.0.1:8780 · Cloud linked)"
                        : "Connected to Local Ember Engine (127.0.0.1:8780 · Local mode)"
                }
            }
            return "Connected to Local Ember Engine (127.0.0.1:8780)"
        }

        guard let url = config.conversationEndpointURL else {
            let env = detectLocalInstallations()
            if env.emberAppPath != nil {
                return "Ember.app installed — say “call ember” or click Open Ember to start its local engine"
            }
            throw EmberClientError.notConfigured
        }
        let (data, http) = try await performRequest(url: url, method: "GET", body: nil, apiToken: apiToken)
        guard (200...299).contains(http.statusCode) else {
            let preview = String(data: data.prefix(220), encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw EmberClientError.httpError(http.statusCode, preview)
        }
        if let snapshot = EmberResponseParser.parseSnapshot(from: data) {
            return "Connected to Ember · \(snapshot.messages.count) messages in conversation"
        }
        return "Connected to Ember (\(url.host ?? "server"))"
    }

    /// Sends a prompt to local `ember-engine :8780` (`POST /api/ember/chat`) if running
    /// (or launches standalone `Ember.app` when no remote server is configured),
    /// otherwise sends to Fuego Cloud Ember (`POST /api/companies/:companyId/ember/:agentId/messages`).
    static func sendMessage(
        prompt: String,
        config: EmberDelegationConfiguration,
        apiToken: String,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        // 1. Prefer running local ember-engine :8780 for instant zero-config integration
        if await isLocalEngineHealthy(), let localToken = readLocalEngineToken() {
            return try await sendToLocalEngine(prompt: prompt, engineToken: localToken, onStatus: onStatus)
        }

        // 2. If remote Fuego isn't configured but standalone Ember.app is installed, launch it and use local engine
        if !config.isConfigured {
            let env = detectLocalInstallations()
            if env.emberAppPath != nil {
                onStatus?("Starting Ember…")
                _ = await summonEmberApp(config: config)
                if await waitForLocalEngine(timeoutSeconds: 6.0), let localToken = readLocalEngineToken() {
                    return try await sendToLocalEngine(prompt: prompt, engineToken: localToken, onStatus: onStatus)
                }
            }
        }

        guard let messagesURL = config.messagesEndpointURL else {
            throw EmberClientError.notConfigured
        }

        // Capture existing message IDs before posting so we only match the newly generated reply.
        var baselineIDs = Set<String>()
        if let conversationURL = config.conversationEndpointURL,
           let (baselineData, baselineHTTP) = try? await performRequest(url: conversationURL, method: "GET", body: nil, apiToken: apiToken),
           (200...299).contains(baselineHTTP.statusCode),
           let baseline = EmberResponseParser.parseSnapshot(from: baselineData) {
            baselineIDs = Set(baseline.messages.map(\.id))
        }

        let clampedBody = EmberDelegationConfiguration.clampedMessageBody(prompt)
        let requestPayload: [String: Any] = [
            "body": clampedBody,
            "clientRequestId": UUID().uuidString.lowercased(),
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: requestPayload)

        onStatus?("Sending to Ember…")
        let (postData, postHTTP) = try await performRequest(
            url: messagesURL,
            method: "POST",
            body: jsonData,
            apiToken: apiToken
        )
        guard (200...299).contains(postHTTP.statusCode) else {
            let preview = String(data: postData.prefix(220), encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: postHTTP.statusCode)
            throw EmberClientError.httpError(postHTTP.statusCode, preview)
        }

        // If the endpoint returned a synchronous reply directly, use it immediately.
        if let immediate = EmberResponseParser.parseImmediateReply(from: postData) {
            return immediate
        }
        if let snapshot = EmberResponseParser.parseSnapshot(from: postData),
           let reply = snapshot.newestAssistantReply(excludingIDs: baselineIDs) {
            return reply.body
        }

        guard let pollURL = config.conversationEndpointURL else {
            throw EmberClientError.timedOut
        }

        onStatus?("Ember is thinking…")
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(1_200))
            try Task.checkCancellation()

            let (pollData, pollHTTP) = try await performRequest(
                url: pollURL,
                method: "GET",
                body: nil,
                apiToken: apiToken
            )
            guard (200...299).contains(pollHTTP.statusCode) else {
                let preview = String(data: pollData.prefix(220), encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: pollHTTP.statusCode)
                throw EmberClientError.httpError(pollHTTP.statusCode, preview)
            }
            guard let snapshot = EmberResponseParser.parseSnapshot(from: pollData) else { continue }
            if let reply = snapshot.newestAssistantReply(excludingIDs: baselineIDs) {
                return reply.body
            }
            if let turnError = snapshot.activeTurnError, !snapshot.hasActiveTurn {
                throw EmberClientError.turnFailed(turnError)
            }
        }

        throw EmberClientError.timedOut
    }

    // MARK: - Local Inferno CLI Integration

    static func fetchInfernoInstalledAgents(binaryPath: String) async -> [InfernoInstalledAgent] {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { return [] }
        do {
            let data = try await runCLI(binaryPath: binaryPath, arguments: ["agent", "installed", "--json"], timeoutSeconds: 8)
            return InfernoCLIParser.parseInstalledAgents(from: data)
        } catch {
            return []
        }
    }

    /// Launches a prompt via local `inferno agent launch --agent <agentID> --prompt <prompt> --json`
    /// and polls `inferno agent read <sessionId> --json` until the agent responds (or returns launch receipt).
    static func runInfernoPrompt(
        binaryPath: String,
        agentID: String,
        prompt: String,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw EmberClientError.infernoUnavailable
        }
        onStatus?("Launching Inferno (\(agentID))…")
        let launchData = try await runCLI(
            binaryPath: binaryPath,
            arguments: ["agent", "launch", "--agent", agentID, "--prompt", prompt, "--json"],
            timeoutSeconds: 20
        )
        let receipt = InfernoCLIParser.parseLaunchReceipt(from: launchData)
        guard let sessionID = receipt?.sessionID, !sessionID.isEmpty else {
            if let immediate = InfernoCLIParser.parseReadOutput(from: launchData) {
                return immediate
            }
            let detail = receipt?.detail ?? String(data: launchData, encoding: .utf8) ?? "Session launched in Inferno."
            return detail.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        onStatus?("Waiting for Inferno (\(agentID))…")
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(1_200))
            try Task.checkCancellation()

            if let readData = try? await runCLI(
                binaryPath: binaryPath,
                arguments: ["agent", "read", sessionID, "--json"],
                timeoutSeconds: 10
            ), let reply = InfernoCLIParser.parseReadOutput(from: readData) {
                return reply
            }
        }

        return "Inferno session \(sessionID) is running in Inferno. Switch to Inferno to continue."
    }

    // MARK: - Local Ember Engine (:8780)

    static func sendToLocalEngine(
        prompt: String,
        engineToken: String,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let chatURL = URL(string: "\(localEngineBaseURL)/api/ember/chat") else {
            throw EmberClientError.invalidEndpoint
        }
        let clamped = EmberDelegationConfiguration.clampedMessageBody(prompt)
        let payload: [String: Any] = [
            "text": clamped,
            "source": "omnivoice",
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        onStatus?("Sending to Ember…")
        let (data, http) = try await performLocalEngineRequest(
            url: chatURL,
            method: "POST",
            body: body,
            engineToken: engineToken,
            timeoutSeconds: 60
        )
        guard (200...299).contains(http.statusCode) else {
            let preview = String(data: data.prefix(220), encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw EmberClientError.httpError(http.statusCode, preview)
        }
        if let err = EmberResponseParser.parseError(from: data) {
            throw EmberClientError.turnFailed(err)
        }
        if let reply = EmberResponseParser.parseImmediateReply(from: data) {
            return reply
        }
        if let snapshot = EmberResponseParser.parseSnapshot(from: data),
           let latest = snapshot.messages.last(where: { $0.isAssistant }) {
            return latest.body
        }
        return "Message delivered to Ember."
    }

    private static func performLocalEngineRequest(
        url: URL,
        method: String,
        body: Data?,
        engineToken: String,
        timeoutSeconds: TimeInterval = 15
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(engineToken, forHTTPHeaderField: "X-Ember-Engine-Token")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EmberClientError.invalidEndpoint
        }
        return (data, http)
    }

    // MARK: - Networking & Subprocess Helpers

    private static func performRequest(
        url: URL,
        method: String,
        body: Data?,
        apiToken: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let cleanedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedToken.isEmpty {
            if cleanedToken.contains("=") && !cleanedToken.lowercased().hasPrefix("bearer ") {
                request.setValue(cleanedToken, forHTTPHeaderField: "Cookie")
            } else {
                let value = cleanedToken.lowercased().hasPrefix("bearer ") ? cleanedToken : "Bearer \(cleanedToken)"
                request.setValue(value, forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EmberClientError.invalidEndpoint
        }
        return (data, http)
    }

    private static func runCLI(binaryPath: String, arguments: [String], timeoutSeconds: Double) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            let home = NSHomeDirectory()
            let extra = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = env["PATH"].map { "\($0):\(extra)" } ?? extra
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.terminate()
                throw EmberClientError.timedOut
            }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 && outData.isEmpty {
                let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "exit \(process.terminationStatus)"
                throw EmberClientError.turnFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return outData
        }.value
    }
}
