import Foundation

/// Pure, zero-LLM vocabulary extractor that scans ephemeral active-window strings
/// (application name, focused window title, and bounded text around the cursor)
/// to surface distinctive brand, product, and code identifiers for a single utterance.
///
/// Never persists or logs extracted terms. Output is deduplicated case-insensitively
/// and capped at `maxExtractedTerms` so `DictionaryMatcher` remains sub-millisecond.
public enum WindowVocabularyExtractor {
    public static let maxInputCharacters = 4_000
    public static let maxExtractedTerms = 40

    private static let uiChromeAndGenericWords: Set<String> = [
        // Standard UI chrome & major apps/vendors
        "untitled", "document", "documents", "window", "windows", "settings", "preferences",
        "search", "inbox", "chrome", "safari", "finder", "apple", "google", "firefox",
        "brave", "edge", "arc", "slack", "zoom", "teams", "discord", "mail", "messages",
        "calendar", "notes", "reminders", "terminal", "console", "xcode", "cursor",
        "vscode", "visual", "studio", "preview", "textedit", "pages", "numbers", "keynote",
        "music", "photos", "podcasts", "facetime", "maps", "weather", "stocks", "books",
        "news", "store", "activity", "monitor", "spotlight", "siri", "icloud",
        "desktop", "applications", "downloads", "library", "system", "folder", "folders",
        // Common UI labels & chrome actions
        "edit", "file", "files", "view", "help", "format", "tools", "history", "bookmarks",
        "browser", "home", "back", "forward", "reload", "refresh", "share", "save",
        "cancel", "delete", "remove", "close", "open", "copy", "paste", "undo", "redo",
        "select", "none", "default", "defaults", "custom", "auto", "manual", "active",
        "recent", "general", "account", "accounts", "profile", "notifications", "privacy",
        "security", "network", "display", "sound", "audio", "video", "keyboard", "mouse",
        "status", "error", "errors", "warning", "warnings", "info", "output", "input",
        "result", "results", "summary", "overview", "details", "option", "options",
        "advanced", "basic", "standard", "quick", "local", "remote", "cloud", "server",
        "client", "public", "private", "admin", "user", "users", "team", "meeting",
        "meetings", "chat", "thread", "threads", "channel", "channels", "workspace",
        "project", "projects", "branch", "commit", "commits", "pull", "request", "requests",
        "issue", "issues", "review", "draft", "drafts", "final", "version", "release",
        "build", "debug", "test", "tests", "source", "sources", "code", "editor", "tab", "tabs",
        "menu", "panel", "sidebar", "toolbar", "header", "footer", "title", "content",
        "page", "screen", "button", "toggle", "check", "update", "updates", "upgrade",
        "install", "download", "upload", "export", "import", "print", "send", "reply",
        "forward", "archive", "trash", "spam", "starred", "pinned", "unread", "sent",
        // Calendar / time / conversational sentence starters
        "today", "tomorrow", "yesterday", "morning", "afternoon", "evening", "night",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "june", "july", "august", "september",
        "october", "november", "december",
        "hello", "thanks", "thank", "please", "sorry", "welcome", "cheers", "regards",
        "however", "actually", "honestly", "basically", "meanwhile", "fortunately",
        "unfortunately", "finally", "overall", "instead", "otherwise", "therefore",
        "furthermore", "moreover", "anyway", "second", "third", "fourth", "fifth",
        "building", "create", "creating", "running", "starting", "stopping", "checking",
        "reading", "writing", "editing", "adding", "fixing", "using", "making", "working",
        "looking", "trying", "getting", "having", "doing", "saying", "telling", "asking",
        "showing", "keeping", "moving", "waiting", "calling", "meeting", "talking",
        "note", "todo", "done", "true", "false", "null", "void", "return", "class",
        "struct", "enum", "func", "function", "const", "static", "import", "export",
        "async", "await", "guard", "switch", "case", "break", "continue", "while",
        "string", "bool", "double", "float", "array", "dictionary", "object", "number",
        "index", "count", "value", "values", "data", "item", "items", "list", "type",
        "name", "names", "path", "line", "text", "word", "words", "time", "date",
    ]

    private static let excludedWords: Set<String> = CorrectionClassifier.commonWords.union(uiChromeAndGenericWords)

    private static let fileExtensionSuffixes: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rs", "go", "rb",
        "java", "kt", "cpp", "cc", "hpp", "md", "markdown", "txt", "json", "yaml",
        "yml", "toml", "xml", "html", "css", "scss", "sql", "sh", "zsh", "bash",
        "pdf", "png", "jpg", "jpeg", "svg", "webp", "docx", "xlsx", "pptx", "csv",
    ]

    private static let tokenSeparators = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "/\\—–|•·()[]{}<>,;:\"'`“”‘’!?@#$%^&*+=~")
    )

    private struct RankedCandidate {
        let term: String
        let lower: String
        let priority: Int // lower number = higher priority
        let firstSeenIndex: Int
    }

    /// Extracts up to `maxExtractedTerms` distinctive custom/brand/code terms from ephemeral
    /// context strings (active app name, focused window title, bounded visible editor text).
    public static func extractTerms(from texts: [String]) -> [String] {
        guard !texts.isEmpty else { return [] }

        var remainingBudget = maxInputCharacters
        var bestByLower: [String: RankedCandidate] = [:]
        var seenCounter = 0

        for rawText in texts {
            guard remainingBudget > 0 else { break }
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let bounded: String
            if trimmed.count > remainingBudget {
                bounded = String(trimmed.prefix(remainingBudget))
            } else {
                bounded = trimmed
            }
            remainingBudget -= bounded.count

            // First strip URLs and email addresses so domain fragments / query params don't leak in.
            let scrubbed = stripURLsAndEmails(bounded)
            let tokens = scrubbed.components(separatedBy: tokenSeparators)

            for rawToken in tokens {
                let candidate = normalizeToken(rawToken)
                guard !candidate.isEmpty else { continue }

                if let priority = classificationPriority(for: candidate) {
                    let lower = candidate.lowercased()
                    if let existing = bestByLower[lower] {
                        let candidateHasRicherCasing = casingScore(candidate) > casingScore(existing.term)
                        if priority < existing.priority || (priority == existing.priority && candidateHasRicherCasing) {
                            bestByLower[lower] = RankedCandidate(
                                term: candidate,
                                lower: lower,
                                priority: priority,
                                firstSeenIndex: existing.firstSeenIndex
                            )
                        }
                    } else {
                        bestByLower[lower] = RankedCandidate(
                            term: candidate,
                            lower: lower,
                            priority: priority,
                            firstSeenIndex: seenCounter
                        )
                        seenCounter += 1
                    }
                }
            }
        }

        let sorted = bestByLower.values.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.firstSeenIndex < rhs.firstSeenIndex
        }

        return Array(sorted.prefix(maxExtractedTerms).map(\.term))
    }

    private static let urlOrEmailRegex = try! NSRegularExpression(
        pattern: #"https?://\S+|\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
        options: [.caseInsensitive]
    )

    private static func stripURLsAndEmails(_ text: String) -> String {
        let ns = text as NSString
        return urlOrEmailRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: ns.length),
            withTemplate: " "
        )
    }

    private static func normalizeToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        guard token.count >= 3, token.count <= 64 else { return "" }

        // Strip trailing possessive "'s" / "’s"
        if token.lowercased().hasSuffix("'s") || token.lowercased().hasSuffix("’s") {
            token = String(token.dropLast(2))
        }

        // Strip common code/document file extension ("AppModel.swift" -> "AppModel")
        if let dotIdx = token.lastIndex(of: ".") {
            let ext = String(token[token.index(after: dotIdx)...]).lowercased()
            if fileExtensionSuffixes.contains(ext) {
                token = String(token[..<dotIdx])
            } else {
                // Skip dotted expressions like "model.preferences" or version numbers "3.14"
                return ""
            }
        }

        token = token.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        guard token.count >= 3, token.count <= 64 else { return "" }
        guard token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return "" }
        guard token.contains(where: \.isLetter) else { return "" }

        // Reject pure hex hashes / UUID-like noise (e.g. "0a485eb1", "deadbeef")
        if isLikelyHexNoise(token) { return "" }

        return token
    }

    /// Returns priority tier (0 = highest) if `token` is a distinctive vocabulary hint, else nil.
    private static func classificationPriority(for token: String) -> Int? {
        let lower = token.lowercased()

        // Tier 0: CamelCase / PascalCase words (NeroNook, OmniSpeak, FuegoDev, CoreMLPunctuationService, SwiftUI, macOS, iPhone)
        if isCamelOrPascalCase(token) {
            return 0
        }

        // Tier 1: Underscored or distinctive hyphenated identifiers
        if token.contains("_") {
            let parts = token.split(separator: "_").map(String.init)
            guard parts.count >= 2,
                  parts.allSatisfy({ !$0.isEmpty && $0.contains(where: \.isLetter) }),
                  token.count >= 4, token.count <= 48 else {
                return nil
            }
            return 1
        }

        if token.contains("-") {
            let parts = token.split(separator: "-").map(String.init)
            guard parts.count >= 2, parts.count <= 4,
                  parts.allSatisfy({ $0.count >= 2 && $0.contains(where: \.isLetter) }) else {
                return nil
            }
            // Keep hyphenated identifiers when at least one segment is a distinctive / proper / internal-caps term
            let hasDistinctiveSegment = parts.contains { part in
                isCamelOrPascalCase(part)
                    || (part.first?.isUppercase == true && !excludedWords.contains(part.lowercased()))
                    || (!excludedWords.contains(part.lowercased()) && part.count >= 4)
            }
            let allExcluded = parts.allSatisfy { excludedWords.contains($0.lowercased()) }
            if hasDistinctiveSegment && !allExcluded {
                return 1
            }
            return nil
        }

        // Never extract excluded common English / UI chrome words as plain capitalized terms
        if excludedWords.contains(lower) {
            return nil
        }

        // Tier 2: Distinctive capitalized proper nouns (Parakeet, Sortformer, Supabase, Anthropic)
        if let first = token.first, first.isUppercase,
           token.count >= 4,
           token.allSatisfy({ $0.isLetter || $0.isNumber })
        {
            let rest = token.dropFirst()
            // Reject ALL-CAPS generic words unless distinctive acronym >= 3? Keep Title-Case proper nouns cleanly.
            if rest.allSatisfy({ $0.isLowercase || $0.isNumber }) {
                return 2
            }
        }

        return nil
    }

    private static func isCamelOrPascalCase(_ token: String) -> Bool {
        guard !token.contains("_"), !token.contains("-"),
              token.count >= 3,
              token.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return false
        }
        let hasLower = token.contains(where: \.isLowercase)
        let hasInternalUpper = token.dropFirst().contains(where: \.isUppercase)
        return hasLower && hasInternalUpper
    }

    private static func isLikelyHexNoise(_ token: String) -> Bool {
        let stripped = token.replacingOccurrences(of: "-", with: "")
        guard stripped.count >= 8 else { return false }
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let allHex = stripped.unicodeScalars.allSatisfy { hexChars.contains($0) }
        let hasDigit = stripped.contains(where: \.isNumber)
        return allHex && hasDigit
    }

    private static func casingScore(_ term: String) -> Int {
        let internalUpper = term.dropFirst().filter(\.isUppercase).count
        let leadingUpper = term.first?.isUppercase == true ? 1 : 0
        return internalUpper * 2 + leadingUpper
    }
}
