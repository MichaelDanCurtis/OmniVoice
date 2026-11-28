import Foundation

/// Optional integration settings for delegating Ask AI requests to Ember (hosted on Fuego)
/// and invoking local Inferno agent sessions.
///
/// Command Mode / Computer Use remains native to OmniSpeak regardless of this setting.
public struct EmberDelegationConfiguration: Codable, Equatable, Sendable {
    public static let defaultServerURL = "https://fuego.curtishome.org"
    public static let defaultInfernoAgentID = "claude"

    /// When true (and configured), voice "ask ai …" and Ask AI Workspace delegate to Ember.
    public var enabled: Bool
    /// Base Fuego/Ember server URL (e.g. `https://fuego.curtishome.org`), or a full custom endpoint URL.
    public var serverURL: String
    /// Fuego company ID for `/api/companies/:companyId/ember/:agentId`.
    public var companyID: String
    /// Ember agent ID under the company.
    public var agentID: String
    /// Preferred agent ID when running prompts through local `inferno agent launch --agent <id>`.
    public var infernoAgentID: String

    public static let defaults = EmberDelegationConfiguration(
        enabled: false,
        serverURL: defaultServerURL,
        companyID: "",
        agentID: "",
        infernoAgentID: defaultInfernoAgentID
    )

    public init(
        enabled: Bool = false,
        serverURL: String = EmberDelegationConfiguration.defaultServerURL,
        companyID: String = "",
        agentID: String = "",
        infernoAgentID: String = EmberDelegationConfiguration.defaultInfernoAgentID
    ) {
        self.enabled = enabled
        var cleanedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleanedURL.hasSuffix("/") {
            cleanedURL.removeLast()
        }
        self.serverURL = cleanedURL
        self.companyID = companyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.agentID = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedInferno = infernoAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.infernoAgentID = cleanedInferno.isEmpty ? Self.defaultInfernoAgentID : cleanedInferno
    }

    public var trimmedServerURL: String {
        var trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    public var trimmedCompanyID: String {
        companyID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedAgentID: String {
        agentID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedInfernoAgentID: String {
        let trimmed = infernoAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultInfernoAgentID : trimmed
    }

    /// True if either the full Fuego Ember path (server + company + agent) is configured,
    /// OR the user supplied a direct custom Ember endpoint URL containing `/ember/`.
    public var isConfigured: Bool {
        messagesEndpointURL != nil
    }

    /// `GET /api/companies/:companyId/ember/:agentId`
    public var conversationEndpointURL: URL? {
        let base = trimmedServerURL
        guard !base.isEmpty else { return nil }
        if base.lowercased().contains("/api/companies/") && base.lowercased().contains("/ember/") {
            let cleaned = base.hasSuffix("/messages") ? String(base.dropLast("/messages".count)) : base
            return URL(string: cleaned)
        }
        guard !trimmedCompanyID.isEmpty, !trimmedAgentID.isEmpty else { return nil }
        let encodedCompany = trimmedCompanyID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmedCompanyID
        let encodedAgent = trimmedAgentID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmedAgentID
        return URL(string: "\(base)/api/companies/\(encodedCompany)/ember/\(encodedAgent)")
    }

    /// `POST /api/companies/:companyId/ember/:agentId/messages`
    public var messagesEndpointURL: URL? {
        let base = trimmedServerURL
        guard !base.isEmpty else { return nil }
        if base.lowercased().hasSuffix("/messages") {
            return URL(string: base)
        }
        guard let convo = conversationEndpointURL else { return nil }
        return convo.appendingPathComponent("messages")
    }

    /// `POST /api/companies/:companyId/ember/:agentId/cancel`
    public var cancelEndpointURL: URL? {
        conversationEndpointURL?.appendingPathComponent("cancel")
    }

    /// Clips a message to Fuego Ember's 4,096 UTF-8 byte body contract.
    public static func clampedMessageBody(_ text: String, maxUTF8Bytes: Int = 4_096) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count > maxUTF8Bytes else { return trimmed }
        var result = ""
        var byteCount = 0
        for scalar in trimmed.unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            if byteCount + scalarBytes > maxUTF8Bytes - 3 {
                break
            }
            result.unicodeScalars.append(scalar)
            byteCount += scalarBytes
        }
        return result + "…"
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case serverURL = "server_url"
        case companyID = "company_id"
        case agentID = "agent_id"
        case infernoAgentID = "inferno_agent_id"
    }

    private enum ConvertedCodingKeys: String, CodingKey {
        case enabled
        case serverURL = "serverUrl"
        case companyID = "companyId"
        case agentID = "agentId"
        case infernoAgentID = "infernoAgentId"
    }

    public init(from decoder: Decoder) throws {
        let snake = try? decoder.container(keyedBy: CodingKeys.self)
        let camel = try? decoder.container(keyedBy: ConvertedCodingKeys.self)
        let enabled = (try? snake?.decodeIfPresent(Bool.self, forKey: .enabled))
            ?? (try? camel?.decodeIfPresent(Bool.self, forKey: .enabled))
            ?? false
        let serverURL = (try? snake?.decodeIfPresent(String.self, forKey: .serverURL))
            ?? (try? camel?.decodeIfPresent(String.self, forKey: .serverURL))
            ?? Self.defaultServerURL
        let companyID = (try? snake?.decodeIfPresent(String.self, forKey: .companyID))
            ?? (try? camel?.decodeIfPresent(String.self, forKey: .companyID))
            ?? ""
        let agentID = (try? snake?.decodeIfPresent(String.self, forKey: .agentID))
            ?? (try? camel?.decodeIfPresent(String.self, forKey: .agentID))
            ?? ""
        let infernoAgentID = (try? snake?.decodeIfPresent(String.self, forKey: .infernoAgentID))
            ?? (try? camel?.decodeIfPresent(String.self, forKey: .infernoAgentID))
            ?? Self.defaultInfernoAgentID
        self.init(
            enabled: enabled,
            serverURL: serverURL,
            companyID: companyID,
            agentID: agentID,
            infernoAgentID: infernoAgentID
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(trimmedServerURL.isEmpty ? Self.defaultServerURL : trimmedServerURL, forKey: .serverURL)
        try container.encode(trimmedCompanyID, forKey: .companyID)
        try container.encode(trimmedAgentID, forKey: .agentID)
        try container.encode(trimmedInfernoAgentID, forKey: .infernoAgentID)
    }
}

public struct EmberMessage: Equatable, Sendable {
    public let id: String
    public let isAssistant: Bool
    public let body: String
    public let clientRequestID: String?

    public init(id: String, isAssistant: Bool, body: String, clientRequestID: String? = nil) {
        self.id = id
        self.isAssistant = isAssistant
        self.body = body
        self.clientRequestID = clientRequestID
    }
}

public struct EmberConversationSnapshot: Equatable, Sendable {
    public let messages: [EmberMessage]
    public let hasActiveTurn: Bool
    public let activeTurnError: String?

    public init(messages: [EmberMessage], hasActiveTurn: Bool = false, activeTurnError: String? = nil) {
        self.messages = messages
        self.hasActiveTurn = hasActiveTurn
        self.activeTurnError = activeTurnError
    }

    /// Finds a newly arrived assistant reply that was not present in `knownMessageIDs`.
    public func newestAssistantReply(excludingIDs knownMessageIDs: Set<String>) -> EmberMessage? {
        messages.last { msg in
            msg.isAssistant
                && !knownMessageIDs.contains(msg.id)
                && !msg.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// Parses Fuego Ember REST API JSON payloads cleanly across schema variations.
public enum EmberResponseParser {
    public static func parseSnapshot(from data: Data) -> EmberConversationSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let container = (root["conversation"] as? [String: Any])
            ?? (root["data"] as? [String: Any])
            ?? root

        let rawItems = (container["messages"] as? [[String: Any]])
            ?? (container["comments"] as? [[String: Any]])
            ?? (root["messages"] as? [[String: Any]])
            ?? []

        let parsed: [EmberMessage] = rawItems.enumerated().compactMap { index, item in
            let body = (item["body"] as? String)
                ?? (item["text"] as? String)
                ?? (item["content"] as? String)
                ?? ""
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let id = (item["id"] as? String)
                ?? (item["messageId"] as? String)
                ?? (item["commentId"] as? String)
                ?? "msg-\(index)"
            let role = ((item["role"] as? String)
                ?? (item["authorType"] as? String)
                ?? (item["senderRole"] as? String)
                ?? (item["sender"] as? String)
                ?? "").lowercased()
            let isAssistant = role == "assistant"
                || role == "agent"
                || role == "ember"
                || role == "bot"
                || (item["authorAgentId"] as? String)?.isEmpty == false
            let clientReqID = (item["clientRequestId"] as? String) ?? (item["client_request_id"] as? String)
            return EmberMessage(id: id, isAssistant: isAssistant, body: trimmed, clientRequestID: clientReqID)
        }

        let activeTurn = (container["activeTurn"] as? [String: Any])
            ?? (container["active_turn"] as? [String: Any])
            ?? (root["activeTurn"] as? [String: Any])
        let activeStatus = (activeTurn?["status"] as? String ?? "").lowercased()
        let hasActiveTurn: Bool
        if let activeTurn {
            hasActiveTurn = activeStatus != "completed" && activeStatus != "failed" && activeStatus != "cancelled" && !activeTurn.isEmpty
        } else {
            hasActiveTurn = (container["pendingRunId"] as? String)?.isEmpty == false
        }
        let turnError = (activeTurn?["error"] as? String)
            ?? (activeTurn?["errorMessage"] as? String)
            ?? (root["error"] as? String)

        return EmberConversationSnapshot(
            messages: parsed,
            hasActiveTurn: hasActiveTurn,
            activeTurnError: turnError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? turnError : nil
        )
    }

    /// Extracts an immediate assistant reply if a `POST .../messages` or local
    /// `ember-engine :8780` `POST /api/ember/chat` response returns one synchronously.
    public static func parseImmediateReply(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["reply", "assistantReply", "text", "answer"] {
            if let value = root[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        for objectKey in ["assistantMessage", "assistant_message", "message"] {
            if let messageObj = root[objectKey] as? [String: Any] {
                let text = (messageObj["body"] as? String)
                    ?? (messageObj["text"] as? String)
                    ?? (messageObj["content"] as? String)
                    ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// Extracts an explicit error message from an Ember or local `ember-engine` payload
    /// when `ok == false` or `error` is populated.
    public static func parseError(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let ok = root["ok"] as? Bool, ok {
            return nil
        }
        if let err = (root["error"] as? String) ?? (root["message"] as? String) {
            let trimmed = err.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

/// Parsed voice command to summon/open the Ember agent (with an optional immediate message).
public struct EmberSummonCommand: Equatable, Sendable {
    public let initialMessage: String?

    public init(initialMessage: String? = nil) {
        self.initialMessage = initialMessage
    }
}

/// Parses spoken summon triggers for bringing up the Ember agent:
/// - Exact: "Ember", "Hey Ember", "Call Ember", "Talk to Ember", "Open Ember",
///   "Bring up Ember", "Summon Ember", "Wake Ember", "Launch Ember"
/// - With prompt: "Call Ember, check my servers", "Talk to Ember about deployments",
///   "Hey Ember, what's on my calendar?", "Ember, summarize my briefing"
///
/// Intentionally ignores:
/// - "Ask Ember …" (handled by AskController's inline Ask AI bubble)
/// - Normal prose mentioning Ember without a summon verb or address pause
///   (e.g. "Ember is looking great today" or "An ember fell from the fire").
public enum EmberVoiceCommandParser {
    private static let politeLeadIns: [String] = [
        "please", "can you", "could you", "would you", "go ahead and", "go ahead", "okay", "ok", "hey",
    ]

    private static let exactSummonPhrases: Set<String> = [
        "ember",
        "ember agent",
        "call ember",
        "call ember agent",
        "call the ember agent",
        "talk to ember",
        "talk to ember agent",
        "talk to the ember agent",
        "speak to ember",
        "speak with ember",
        "chat with ember",
        "open ember",
        "open ember agent",
        "open the ember agent",
        "show ember",
        "show ember agent",
        "show the ember agent",
        "bring up ember",
        "bring up ember agent",
        "bring up the ember agent",
        "pull up ember",
        "launch ember",
        "start ember",
        "wake ember",
        "wake up ember",
        "summon ember",
    ]

    private static let messagePrefixes: [String] = [
        "call the ember agent",
        "talk to the ember agent",
        "bring up the ember agent",
        "open the ember agent",
        "call ember agent",
        "talk to ember agent",
        "bring up ember agent",
        "open ember agent",
        "talk to ember",
        "speak to ember",
        "speak with ember",
        "chat with ember",
        "call ember",
        "tell ember",
        "message ember",
        "send to ember",
        "summon ember",
        "wake up ember",
        "wake ember",
        "bring up ember",
        "pull up ember",
        "open ember and",
    ]

    public static func parse(_ raw: String) -> EmberSummonCommand? {
        let trimmedOriginal = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else { return nil }

        // Keep "ask ember …" routed to AskController's inline Ask AI bubble.
        let rawLower = trimmedOriginal.lowercased()
        if rawLower == "ask ember" || rawLower.hasPrefix("ask ember ") || rawLower.hasPrefix("ask ember,") {
            return nil
        }

        // Track whether the speaker explicitly addressed Ember with "hey" (e.g. "Hey Ember check my servers")
        var hadHeyLeadIn = false
        var workingOriginal = trimmedOriginal
        var strippedAny = true
        while strippedAny {
            strippedAny = false
            let lower = workingOriginal.lowercased()
            for prefix in politeLeadIns {
                if lower.hasPrefix(prefix) {
                    let afterIdx = workingOriginal.index(workingOriginal.startIndex, offsetBy: prefix.count)
                    if afterIdx < workingOriginal.endIndex {
                        let nextChar = workingOriginal[afterIdx]
                        guard nextChar.isWhitespace || nextChar.isPunctuation else { continue }
                    }
                    if prefix == "hey" {
                        hadHeyLeadIn = true
                    }
                    workingOriginal = String(workingOriginal[afterIdx...])
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ",.:;!?-—")))
                    strippedAny = true
                    break
                }
            }
        }

        let normalizedExact = normalizeForExactMatch(workingOriginal)
        if exactSummonPhrases.contains(normalizedExact) {
            return EmberSummonCommand(initialMessage: nil)
        }

        let workingLower = workingOriginal.lowercased()

        // Multi-word unambiguous summon + trailing prompt (e.g. "Call Ember, check my servers")
        for prefix in messagePrefixes {
            guard workingLower.hasPrefix(prefix) else { continue }
            let afterIdx = workingOriginal.index(workingOriginal.startIndex, offsetBy: prefix.count)
            guard afterIdx < workingOriginal.endIndex else {
                return EmberSummonCommand(initialMessage: nil)
            }
            let nextChar = workingOriginal[afterIdx]
            guard nextChar.isWhitespace || nextChar.isPunctuation else { continue }

            let remainder = cleanTrailingMessage(String(workingOriginal[afterIdx...]))
            return EmberSummonCommand(initialMessage: remainder.isEmpty ? nil : remainder)
        }

        // Single-word "Ember, <message>" (requires explicit address pause punctuation OR "hey" lead-in)
        if workingLower.hasPrefix("ember") {
            let afterIdx = workingOriginal.index(workingOriginal.startIndex, offsetBy: 5)
            guard afterIdx < workingOriginal.endIndex else {
                return EmberSummonCommand(initialMessage: nil)
            }
            let nextChar = workingOriginal[afterIdx]
            let hasAddressPunctuation = nextChar == "," || nextChar == ":" || nextChar == "-" || nextChar == "—" || nextChar == "!"
            let hasHeyAddress = hadHeyLeadIn && (nextChar.isWhitespace || nextChar.isPunctuation)
            if hasAddressPunctuation || hasHeyAddress {
                let remainder = cleanTrailingMessage(String(workingOriginal[afterIdx...]))
                if !remainder.isEmpty {
                    return EmberSummonCommand(initialMessage: remainder)
                }
            }
        }

        return nil
    }

    private static func normalizeForExactMatch(_ text: String) -> String {
        let lower = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'`()[]"))
        return lower
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func cleanTrailingMessage(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ",.:;!?-—"))
        )
        let lower = cleaned.lowercased()
        if lower.hasPrefix("and ") {
            cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}

public struct InfernoInstalledAgent: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public struct InfernoLaunchReceipt: Equatable, Sendable {
    public let sessionID: String?
    public let outcomeKind: String?
    public let detail: String?

    public init(sessionID: String?, outcomeKind: String?, detail: String?) {
        self.sessionID = sessionID
        self.outcomeKind = outcomeKind
        self.detail = detail
    }
}

/// Parses JSON responses emitted by the local `inferno` (Orca) CLI.
public enum InfernoCLIParser {
    public static func parseInstalledAgents(from data: Data) -> [InfernoInstalledAgent] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let result = (root["result"] as? [String: Any]) ?? root
        let rawAgents = (result["agents"] as? [[String: Any]]) ?? []
        return rawAgents.compactMap { item in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            let name = (item["name"] as? String) ?? id
            let isDefault = (item["default"] as? Bool) ?? false
            return InfernoInstalledAgent(id: id, name: name, isDefault: isDefault)
        }
    }

    public static func parseLaunchReceipt(from data: Data) -> InfernoLaunchReceipt? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let result = (root["result"] as? [String: Any]) ?? root
        let sessionID = (result["sessionId"] as? String)
            ?? (result["agentSessionId"] as? String)
            ?? ((result["session"] as? [String: Any])?["id"] as? String)
            ?? ((result["terminal"] as? [String: Any])?["id"] as? String)
        let outcomeKind = (result["outcome"] as? [String: Any])?["kind"] as? String
        let detail = ((result["receipt"] as? [String: Any])?["detail"] as? String)
            ?? (result["detail"] as? String)
            ?? (root["error"] as? String)
        return InfernoLaunchReceipt(sessionID: sessionID, outcomeKind: outcomeKind, detail: detail)
    }

    public static func parseReadOutput(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let plain = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return plain.isEmpty ? nil : plain
        }
        let result = (root["result"] as? [String: Any]) ?? root
        for key in ["lastAssistantMessage", "latestMessage", "text", "output", "content", "body"] {
            if let value = result[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        if let messages = result["messages"] as? [[String: Any]],
           let lastAssistant = messages.last(where: { (($0["role"] as? String) ?? "").lowercased() == "assistant" }) {
            let text = (lastAssistant["text"] as? String)
                ?? (lastAssistant["content"] as? String)
                ?? (lastAssistant["body"] as? String)
                ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
