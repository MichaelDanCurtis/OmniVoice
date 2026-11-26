import Foundation

public enum TextInsertionStrategy: String, Codable, Equatable, Sendable {
    case directAccessibility
    case pasteboardOnly
}

public enum TextInsertionTargetPolicy {
    private static let richComposerBundleIDs: Set<String> = [
        "company.thebrowser.browser", // Arc
        "com.apple.safari",
        "com.apple.terminal",
        "com.google.chrome",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.tinyspeck.slackmacgap",
        "com.hnc.discord",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.anthropic.claudefordesktop",
        "com.openai.codex",
        "com.openai.chat",
        "com.google.antigravity",
        "com.microsoft.vscode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
        "notion.id",
        "md.obsidian",
        "com.linear",
        "dev.zed.zed",
        "dev.warp.warp-stable",
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
    ]

    private static let richComposerTokens: Set<String> = [
        "antigravity",
        "arc",
        "brave",
        "chrome",
        "chromium",
        "claude",
        "codex",
        "cursor",
        "discord",
        "electron",
        "firefox",
        "ghostty",
        "iterm2",
        "linear",
        "notion",
        "obsidian",
        "openai",
        "safari",
        "slack",
        "teams",
        "terminal",
        "vscode",
        "warp",
        "windsurf",
        "zed",
    ]

    public static func strategy(
        bundleIdentifier: String?,
        applicationName: String?,
        currentValue: String,
        selectedRange: NSRange?
    ) -> TextInsertionStrategy {
        let normalizedBundleID = (bundleIdentifier ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if richComposerBundleIDs.contains(normalizedBundleID) {
            return .pasteboardOnly
        }

        let normalizedAppName = (applicationName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedAppName.contains("microsoft teams") {
            return .pasteboardOnly
        }

        let tokens = identifierTokens(in: normalizedBundleID).union(identifierTokens(in: normalizedAppName))
        if !tokens.isDisjoint(with: richComposerTokens) {
            return .pasteboardOnly
        }

        return .directAccessibility
    }

    private static func identifierTokens(in value: String) -> Set<String> {
        Set(
            value.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }
}
