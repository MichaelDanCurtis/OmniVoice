import Foundation

public struct AgentRegistry {
    public static let defaultBuiltIns: [AgentDescriptor] = [
        AgentDescriptor(id: "claude", displayName: "Claude", keywords: ["claude"],
            binaryName: "claude", invocation: .args(["-p", "{prompt}"]), streamFormat: .plainText),
        AgentDescriptor(id: "gemini", displayName: "Gemini", keywords: ["gemini"],
            binaryName: "gemini", invocation: .args(["{prompt}"]), streamFormat: .plainText),
    ]
    public static let defaultAgentID = "claude"

    private let descriptors: [AgentDescriptor]
    public init(builtIns: [AgentDescriptor] = AgentRegistry.defaultBuiltIns,
                custom: [AgentConfiguration]) {
        self.descriptors = builtIns + custom.map { $0.descriptor() }
    }

    public var all: [AgentDescriptor] { descriptors }

    public func resolve(keyword: String) -> AgentDescriptor? {
        let k = keyword.lowercased()
        return descriptors.first { $0.keywords.contains(k) }
    }
}
