import Foundation

/// Resolves a spoken keyword to its bound `AskTarget` (case-insensitive, trimmed,
/// first match wins).
public enum AskKeywordResolver {
    public static func resolve(_ keyword: String, in bindings: [AskKeywordBinding]) -> AskTarget? {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bindings.first {
            $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }?.target
    }
}
