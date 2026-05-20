import Foundation

public enum TextInsertionStrategy: String, Codable, Equatable, Sendable {
    case directAccessibility
    case pasteboardOnly
}

public enum TextInsertionTargetPolicy {
    private static let richComposerTerms = [
        "arc",
        "chrome",
        "claude",
        "codex",
        "discord",
        "electron",
        "firefox",
        "microsoft teams",
        "openai",
        "safari",
        "slack",
        "teams",
    ]

    public static func strategy(
        bundleIdentifier: String?,
        applicationName: String?,
        currentValue: String,
        selectedRange: NSRange?
    ) -> TextInsertionStrategy {
        let haystack = [
            bundleIdentifier ?? "",
            applicationName ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        if richComposerTerms.contains(where: { haystack.contains($0) }) {
            return .pasteboardOnly
        }

        return .directAccessibility
    }
}
