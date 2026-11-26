import Foundation

public struct AgentRegistry {
    public static let defaultBuiltIns: [AgentDescriptor] = [
        AgentDescriptor(id: "claude", displayName: "Claude", keywords: ["claude"],
            binaryName: "claude", invocation: .args(["-p", "{prompt}"]), streamFormat: .plainText),
        AgentDescriptor(id: "gemini", displayName: "Gemini", keywords: ["gemini"],
            binaryName: "gemini", invocation: .args(["{prompt}"]), streamFormat: .plainText,
            acpArgs: ["--acp"], acpFastModelPreference: ["flash-lite", "flash"]),
        AgentDescriptor(id: "codex", displayName: "Codex", keywords: ["codex"],
            binaryName: "codex", invocation: .args(["exec", "{prompt}"]), streamFormat: .plainText),
        AgentDescriptor(id: "antigravity", displayName: "Gemini Antigravity", keywords: ["antigravity", "agy", "gemini antigravity"],
            binaryName: "agy", invocation: .args(["-p", "{prompt}", "--disable-slash-commands", "--output-format", "text"]), streamFormat: .plainText,
            acpArgs: ["acp", "--include-default-customizations=false"],
            acpFastModelPreference: ["gemini-3.8-flash-low", "flash-low", "flash"]),
        AgentDescriptor(id: "copilot", displayName: "GitHub Copilot", keywords: ["copilot"],
            binaryName: "copilot", invocation: .args(["-p", "{prompt}"]), streamFormat: .plainText,
            acpArgs: ["--acp"], acpFastModelPreference: ["mini", "flash", "haiku"]),
        AgentDescriptor(id: "opencode", displayName: "OpenCode", keywords: ["opencode"],
            binaryName: "opencode", invocation: .args(["run", "{prompt}"]), streamFormat: .plainText,
            acpArgs: ["acp"], acpFastModelPreference: ["flash", "mini", "haiku"]),
        AgentDescriptor(id: "goose", displayName: "Goose", keywords: ["goose"],
            binaryName: "goose", invocation: .args(["run", "-t", "{prompt}"]), streamFormat: .plainText,
            acpArgs: ["acp"]),
        AgentDescriptor(id: "kimi", displayName: "Kimi", keywords: ["kimi"],
            binaryName: "kimi", invocation: .args(["--print", "-p", "{prompt}"]), streamFormat: .plainText,
            acpArgs: ["acp"]),
        AgentDescriptor(id: "aider", displayName: "Aider", keywords: ["aider"],
            binaryName: "aider", invocation: .args(["--message", "{prompt}", "--no-auto-commits"]), streamFormat: .plainText),
        AgentDescriptor(id: "amp", displayName: "Amp", keywords: ["amp"],
            binaryName: "amp", invocation: .args(["-x", "{prompt}"]), streamFormat: .plainText),
        AgentDescriptor(id: "qwen", displayName: "Qwen Code", keywords: ["qwen"],
            binaryName: "qwen", invocation: .args(["-p", "{prompt}"]), streamFormat: .plainText),
        AgentDescriptor(id: "glm", displayName: "GLM", keywords: ["glm"],
            binaryName: "glm", invocation: .args(["{prompt}"]), streamFormat: .plainText),
        AgentDescriptor(id: "cursor-agent", displayName: "Cursor Agent", keywords: ["cursor"],
            binaryName: "cursor-agent", invocation: .args(["-p", "{prompt}"]), streamFormat: .plainText),
    ]
    public static let defaultAgentID = "claude"

    /// Merges newly discovered system agents into an existing `askKeywordBindings` list
    /// without duplicating an already-bound agent target or clobbering an existing keyword.
    public static func mergedAskKeywordBindings(
        existing: [AskKeywordBinding],
        discovered: [DiscoveredAgent]
    ) -> [AskKeywordBinding] {
        var result = existing
        for agent in discovered {
            let target = AskTarget(kind: .agent, id: agent.id)
            let alreadyTargetsAgent = result.contains { $0.target == target }
            let primaryKeyword = agent.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let keywordTaken = result.contains {
                $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == primaryKeyword
            }
            if !alreadyTargetsAgent && !keywordTaken && !primaryKeyword.isEmpty {
                result.append(AskKeywordBinding(
                    id: "auto-agent-\(agent.id)",
                    keyword: primaryKeyword,
                    target: target
                ))
            }
        }
        return result
    }

    private let descriptors: [AgentDescriptor]
    public init(builtIns: [AgentDescriptor] = AgentRegistry.defaultBuiltIns,
                custom: [AgentConfiguration]) {
        let customDescriptors = custom.map { $0.descriptor() }
        let customIDs = Set(customDescriptors.map(\.id))
        // Custom agent configurations override built-ins with the same id or keyword.
        self.descriptors = customDescriptors + builtIns.filter { !customIDs.contains($0.id) }
    }

    public var all: [AgentDescriptor] { descriptors }

    public func resolve(keyword: String) -> AgentDescriptor? {
        let k = keyword.lowercased()
        return descriptors.first { $0.keywords.contains(k) }
    }
}
