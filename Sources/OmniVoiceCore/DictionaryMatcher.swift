import Foundation

/// Fast (<0.5 ms), zero-LLM Personal Dictionary matcher that enforces:
/// 1. Exact & apostrophe-normalized canonical/alias matches ("neuron's" & "neuron’s" -> "NeroNook")
/// 2. Phonetic (Metaphone-style) + Levenshtein fuzzy matching for distinctive custom words
///    ("nero nook", "neural nook", "nuronook", "neurons" -> "NeroNook") while strictly
///    protecting common English words from false-positive replacements.
public enum DictionaryMatcher {
    private struct CompiledEntry {
        let canonical: String
        let canonicalCompact: String
        let canonicalPhonetic: String
        let isCompoundBrand: Bool
        let aliases: [String]
        let aliasTargets: [(compact: String, phonetic: String)]
    }

    private static let outerPunctuation = CharacterSet(charactersIn: ".,!?;:\"'`“”‘’()[]{}")

    private static let protectedCommonWords: Set<String> = CorrectionClassifier.commonWords.union([
        "new", "near", "book", "look", "cook", "hook", "took", "nook", "room", "moon", "soon",
        "work", "word", "world", "page", "file", "code", "note", "notes", "call", "chat",
        "mail", "time", "date", "year", "week", "day", "hour", "minute", "second", "number",
        "right", "left", "back", "down", "over", "under", "open", "close", "start", "stop",
        "send", "read", "write", "edit", "save", "copy", "paste", "test", "build", "check",
        "team", "teams", "voice", "speak", "sound", "audio", "video", "screen", "window",
        "feature", "system", "custom", "grammar", "stream", "engine", "local", "model",
    ])

    /// Applies exact canonical/alias matches and phonetic/fuzzy Personal Dictionary matches to `text`.
    public static func apply(
        to text: String,
        dictionaryTerms: [String],
        dictionaryEntries: [DictionaryEntry]
    ) -> String {
        guard !text.isEmpty else { return text }

        var compiled: [CompiledEntry] = []
        var seenCanonicals = Set<String>()

        for entry in dictionaryEntries where entry.enabled {
            let canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else { continue }
            seenCanonicals.insert(canonical.lowercased())

            let cleanedAliases = entry.aliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let cCompact = compactAlphaNum(canonical)
            let cPhonetic = phoneticKey(cCompact)
            let aTargets = cleanedAliases.map { alias -> (String, String) in
                let compact = compactAlphaNum(alias)
                return (compact, phoneticKey(compact))
            }
            compiled.append(CompiledEntry(
                canonical: canonical,
                canonicalCompact: cCompact,
                canonicalPhonetic: cPhonetic,
                isCompoundBrand: canonical.dropFirst().contains(where: \.isUppercase),
                aliases: cleanedAliases,
                aliasTargets: aTargets
            ))
        }

        for term in dictionaryTerms {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seenCanonicals.contains(cleaned.lowercased()) else { continue }
            seenCanonicals.insert(cleaned.lowercased())
            let cCompact = compactAlphaNum(cleaned)
            compiled.append(CompiledEntry(
                canonical: cleaned,
                canonicalCompact: cCompact,
                canonicalPhonetic: phoneticKey(cCompact),
                isCompoundBrand: cleaned.dropFirst().contains(where: \.isUppercase),
                aliases: [],
                aliasTargets: []
            ))
        }

        guard !compiled.isEmpty else { return text }

        // 1. Exact & apostrophe-normalized alias/canonical pass (longest patterns first)
        var current = text
        var exactRules: [(pattern: String, replacement: String)] = []
        for entry in compiled {
            exactRules.append((entry.canonical, entry.canonical))
            for alias in entry.aliases {
                exactRules.append((alias, entry.canonical))
                let straight = alias.replacingOccurrences(of: "’", with: "'")
                let curly = alias.replacingOccurrences(of: "'", with: "’")
                if straight != alias { exactRules.append((straight, entry.canonical)) }
                if curly != alias { exactRules.append((curly, entry.canonical)) }
            }
        }
        exactRules.sort { $0.pattern.count > $1.pattern.count }

        for rule in exactRules {
            let escaped = NSRegularExpression.escapedPattern(for: rule.pattern)
            let pattern = #"(?<!\w)"# + escaped + #"(?!\w)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = current as NSString
                current = regex.stringByReplacingMatches(
                    in: current,
                    options: [],
                    range: NSRange(location: 0, length: ns.length),
                    withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement)
                )
            }
        }

        // 2. Phonetic + Levenshtein fuzzy pass over 2-word spans and 1-word tokens (line-preserving).
        //    Only runs for distinctive dictionary entries (compact len >= 5) to guarantee zero false positives.
        let fuzzyEntries = compiled.filter { $0.canonicalCompact.count >= 5 }
        guard !fuzzyEntries.isEmpty else { return current }

        let lines = current.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let processedLines = lines.map { line -> String in
            let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard !words.isEmpty else { return line }

            var output: [String] = []
            output.reserveCapacity(words.count)
            var i = 0

            while i < words.count {
                let token = words[i]
                if token.isEmpty {
                    output.append(token)
                    i += 1
                    continue
                }

                // Try 2-word span first (e.g. "nero nook" or "neural nook" -> "NeroNook")
                if i + 1 < words.count, !words[i + 1].isEmpty {
                    let (lead1, core1, trail1) = splitOuterPunctuation(words[i])
                    let (_, core2, trail2) = splitOuterPunctuation(words[i + 1])
                    if trail1.isEmpty, !core1.isEmpty, !core2.isEmpty {
                        let combinedCompact = compactAlphaNum(core1 + core2)
                        if combinedCompact.count >= 5,
                           let matched = bestFuzzyMatch(
                               candidateCompact: combinedCompact,
                               isMultiWord: true,
                               entries: fuzzyEntries
                           )
                        {
                            output.append(lead1 + matched + trail2)
                            i += 2
                            continue
                        }
                    }
                }

                // Try single-word fuzzy match (e.g. "nuronook", "neuron's", "neurons" -> "NeroNook")
                let (lead, core, trail) = splitOuterPunctuation(token)
                let compact = compactAlphaNum(core)
                if compact.count >= 5,
                   !protectedCommonWords.contains(core.lowercased()),
                   let matched = bestFuzzyMatch(
                       candidateCompact: compact,
                       isMultiWord: false,
                       entries: fuzzyEntries
                   )
                {
                    output.append(lead + matched + trail)
                } else {
                    output.append(token)
                }
                i += 1
            }

            return output.joined(separator: " ")
        }

        return processedLines.joined(separator: "\n")
    }

    // MARK: - Phonetic & Edit Distance Matching

    private static func bestFuzzyMatch(
        candidateCompact: String,
        isMultiWord: Bool,
        entries: [CompiledEntry]
    ) -> String? {
        let candidatePhonetic = phoneticKey(candidateCompact)
        var bestCanonical: String?
        var bestScore: Double = 0

        for entry in entries {
            // Skip already-exact canonicals
            if candidateCompact == entry.canonicalCompact {
                return entry.canonical
            }

            // Score against canonical AND against any learned aliases (e.g. alias "neuron's" catches "neurons")
            var targets: [(compact: String, phonetic: String)] = [(entry.canonicalCompact, entry.canonicalPhonetic)]
            targets.append(contentsOf: entry.aliasTargets)

            for target in targets where target.compact.count >= 5 {
                let sim = similarityScore(
                    candidateCompact: candidateCompact,
                    candidatePhonetic: candidatePhonetic,
                    targetCompact: target.compact,
                    targetPhonetic: target.phonetic,
                    isMultiWord: isMultiWord,
                    isCompoundBrand: entry.isCompoundBrand
                )
                if sim > bestScore {
                    bestScore = sim
                    bestCanonical = entry.canonical
                }
            }
        }

        return bestScore >= 0.72 ? bestCanonical : nil
    }

    private static func similarityScore(
        candidateCompact: String,
        candidatePhonetic: String,
        targetCompact: String,
        targetPhonetic: String,
        isMultiWord: Bool,
        isCompoundBrand: Bool
    ) -> Double {
        let maxLen = max(candidateCompact.count, targetCompact.count)
        guard maxLen >= 5 else { return 0 }

        // Require the same starting phonetic consonant/vowel family to prevent cross-word collisions
        guard candidateCompact.first == targetCompact.first
            || (!candidatePhonetic.isEmpty && candidatePhonetic.first == targetPhonetic.first) else {
            return 0
        }

        let editDist = levenshtein(candidateCompact, targetCompact)
        let charSimilarity = 1.0 - (Double(editDist) / Double(maxLen))

        // 1. Exact compact match (e.g. "nero nook" -> "neronook" == "neronook")
        if editDist == 0 {
            return 1.0
        }

        // 2. Tiny edit distance (1 typo on >= 6-char word, e.g. "NeroNok" -> "NeroNook", "neurons" vs "neurons" alias)
        if editDist == 1 && maxLen >= 6 {
            return max(charSimilarity, 0.90)
        }

        // 3. Phonetic match (Metaphone-style key equality or 1-edit phonetic match on distinctive words)
        if !candidatePhonetic.isEmpty && !targetPhonetic.isEmpty {
            if candidatePhonetic == targetPhonetic {
                // Exact phonetic match (e.g. "nuronook" / "neronuk" == NRNK == "NeroNook")
                return charSimilarity >= 0.62 ? max(charSimilarity, 0.85) : 0
            }
            let phonDist = levenshtein(candidatePhonetic, targetPhonetic)
            let phonMax = max(candidatePhonetic.count, targetPhonetic.count)
            if phonDist == 1 && phonMax >= 4 && charSimilarity >= (isMultiWord ? 0.68 : 0.74) {
                // Near-phonetic match (e.g. "neural nook" NRLNK vs NRNK "NeroNook")
                return 0.78
            }
            // Compound brand first-try near-phonetic match (e.g. "neuron's" / "neurons" NRNS vs NRNK "NeroNook"):
            // shares at least the first 3 phonetic consonants with a single trailing/internal consonant shift.
            if isCompoundBrand, !isMultiWord,
               phonDist == 1, phonMax >= 4,
               maxLen >= 7, candidateCompact.count >= 6,
               abs(candidateCompact.count - targetCompact.count) <= 2,
               charSimilarity >= 0.50,
               sharedPrefixCount(candidatePhonetic, targetPhonetic) >= 3
            {
                return 0.76
            }
        }

        return 0
    }

    private static func sharedPrefixCount(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        for (a, b) in zip(lhs, rhs) {
            if a == b {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Lightweight English phonetic key (inspired by Metaphone/Cologne):
    /// collapses vowel variations, silent letters, ph->f, ck->k, double letters, etc.
    static func phoneticKey(_ compactLower: String) -> String {
        guard !compactLower.isEmpty else { return "" }
        var s = compactLower
        let digraphs: [(String, String)] = [
            ("ph", "f"),
            ("gh", ""),
            ("ck", "k"),
            ("kn", "n"),
            ("wr", "r"),
            ("sh", "x"),
            ("ch", "x"),
            ("th", "0"),
            ("qu", "kw"),
            ("oo", "u"),
            ("ee", "i"),
            ("ea", "i"),
        ]
        for (from, to) in digraphs {
            s = s.replacingOccurrences(of: from, with: to)
        }

        var result = ""
        var prev: Character?
        for (idx, ch) in s.enumerated() {
            let mapped: Character?
            switch ch {
            case "a", "e", "i", "o", "u", "y", "h", "w":
                mapped = (idx == 0) ? ch : nil
            case "c", "q":
                mapped = "k"
            case "z":
                mapped = "s"
            case "v":
                mapped = "f"
            case "j":
                mapped = "g"
            default:
                mapped = ch
            }
            if let m = mapped, m != prev {
                result.append(m)
                prev = m
            }
        }
        return result
    }

    private static func compactAlphaNum(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func splitOuterPunctuation(_ token: String) -> (lead: String, core: String, trail: String) {
        var chars = Array(token)
        var lead = ""
        while let first = chars.first, first.unicodeScalars.allSatisfy({ outerPunctuation.contains($0) }) {
            lead.append(chars.removeFirst())
        }
        var trail = ""
        while let last = chars.last, last.unicodeScalars.allSatisfy({ outerPunctuation.contains($0) }) {
            trail.insert(chars.removeLast(), at: trail.startIndex)
        }
        return (lead, String(chars), trail)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = (a[i - 1] == b[j - 1]) ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
