import Foundation

/// Whether an Ask keyword routes to an engine text-LLM provider (API or OAuth) or
/// to a local agent CLI.
public enum AskTargetKind: String, Codable, Equatable, Hashable, Sendable {
    case textLLM
    case agent
}

/// A resolved Ask target: `id` is a `TextLLMProviderKind.rawValue` for `.textLLM`,
/// or a built-in agent id / `AgentConfiguration.id` for `.agent`.
public struct AskTarget: Codable, Equatable, Hashable, Sendable {
    public var kind: AskTargetKind
    public var id: String
    public init(kind: AskTargetKind, id: String) { self.kind = kind; self.id = id }
}

/// Binds a spoken keyword ("claude", "ai", …) to exactly one provider.
public struct AskKeywordBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var keyword: String
    public var target: AskTarget
    public init(id: String, keyword: String, target: AskTarget) {
        self.id = id; self.keyword = keyword; self.target = target
    }
}
