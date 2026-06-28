import Foundation

public enum AgentStreamFormat: String, Codable, Equatable, Sendable {
    case plainText
}

public enum AgentInvocation: Equatable, Sendable {
    case args([String])    // "{prompt}" token replaced by the prompt argument
    case stdin([String])   // fixed args; prompt written to stdin
}

public struct AgentDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let keywords: [String]
    public let binaryName: String          // resolved on PATH unless binaryPath set
    public let binaryPath: String?
    public let invocation: AgentInvocation
    public let streamFormat: AgentStreamFormat

    public init(id: String, displayName: String, keywords: [String],
                binaryName: String, binaryPath: String? = nil,
                invocation: AgentInvocation, streamFormat: AgentStreamFormat) {
        self.id = id; self.displayName = displayName; self.keywords = keywords
        self.binaryName = binaryName; self.binaryPath = binaryPath
        self.invocation = invocation; self.streamFormat = streamFormat
    }

    public func render(prompt: String) -> (args: [String], stdin: String?) {
        switch invocation {
        case .args(let template):
            return (template.map { $0 == "{prompt}" ? prompt : $0 }, nil)
        case .stdin(let args):
            return (args, prompt)
        }
    }
}

public struct AgentConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var keyword: String
    public var binaryPath: String
    public var argsTemplate: [String]   // contains "{prompt}" unless usesStdin
    public var usesStdin: Bool
    public var streamFormat: AgentStreamFormat

    public init(id: String, displayName: String, keyword: String, binaryPath: String,
                argsTemplate: [String] = ["{prompt}"], usesStdin: Bool = false,
                streamFormat: AgentStreamFormat = .plainText) {
        self.id = id; self.displayName = displayName; self.keyword = keyword
        self.binaryPath = binaryPath; self.argsTemplate = argsTemplate
        self.usesStdin = usesStdin; self.streamFormat = streamFormat
    }

    public func descriptor() -> AgentDescriptor {
        AgentDescriptor(
            id: id, displayName: displayName, keywords: [keyword.lowercased()],
            binaryName: (binaryPath as NSString).lastPathComponent, binaryPath: binaryPath,
            invocation: usesStdin ? .stdin(argsTemplate) : .args(argsTemplate),
            streamFormat: streamFormat
        )
    }
}
