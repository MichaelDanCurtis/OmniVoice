import Foundation

/// Single source of truth for which AI engine powers OmniSpeak across Dictation Cleanup,
/// Ask AI (voice + workspace), Conversation Chat & Insights, Meeting Co-Pilot,
/// Editor AI, Translation, Voice Edit, Command Mode, and Service Mode.
public enum UnifiedAIRoute: Codable, Equatable, Hashable, Sendable {
    /// Automatically picks the best available engine:
    /// 1) Configured API / OAuth Text LLM provider
    /// 2) First installed local AI Agent CLI (Gemini Antigravity, Claude, Codex, Gemini, etc.)
    /// 3) Built-in on-device Apple Silicon MLX model
    case auto

    /// Routes through an installed or custom CLI agent (`antigravity`, `claude`, `codex`, `gemini`, etc.).
    case agent(agentID: String)

    /// Routes through a configured API-key or OAuth Text LLM provider.
    case textLLM(provider: TextLLMProviderKind)

    /// Routes through the built-in Apple Silicon MLX local model (on-device, private, offline).
    case localMLX

    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case auto
        case agent
        case textLLM
        case localMLX

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .auto:
                "Auto"
            case .agent:
                "AI Agent"
            case .textLLM:
                "API / OAuth"
            case .localMLX:
                "Local MLX"
            }
        }
    }

    public var category: Category {
        switch self {
        case .auto:
            .auto
        case .agent:
            .agent
        case .textLLM:
            .textLLM
        case .localMLX:
            .localMLX
        }
    }

    public var pickerID: String {
        switch self {
        case .auto:
            "auto"
        case .agent(let agentID):
            "agent:\(agentID)"
        case .textLLM(let provider):
            "llm:\(provider.rawValue)"
        case .localMLX:
            "local_mlx"
        }
    }

    public init(pickerID: String) {
        if pickerID == "local_mlx" {
            self = .localMLX
        } else if pickerID.hasPrefix("agent:") {
            let id = String(pickerID.dropFirst("agent:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            self = id.isEmpty ? .auto : .agent(agentID: id)
        } else if pickerID.hasPrefix("llm:") {
            let raw = String(pickerID.dropFirst("llm:".count))
            self = .textLLM(provider: TextLLMProviderKind(providerID: raw))
        } else {
            self = .auto
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "agent":
            let id = (try? container.decode(String.self, forKey: .value))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self = id.isEmpty ? .auto : .agent(agentID: id)
        case "text_llm":
            let raw = try container.decode(String.self, forKey: .value)
            self = .textLLM(provider: TextLLMProviderKind(providerID: raw))
        case "local_mlx":
            self = .localMLX
        default:
            self = .auto
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode("auto", forKey: .kind)
        case .agent(let agentID):
            try container.encode("agent", forKey: .kind)
            try container.encode(agentID, forKey: .value)
        case .textLLM(let provider):
            try container.encode("text_llm", forKey: .kind)
            try container.encode(provider.rawValue, forKey: .value)
        case .localMLX:
            try container.encode("local_mlx", forKey: .kind)
        }
    }
}
