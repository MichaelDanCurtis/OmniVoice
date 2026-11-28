import Foundation

/// A learned mapping: the text OmniSpeak inserted (`from`) → the user's corrected form (`to`).
public struct LearnedCorrection: Equatable, Sendable {
    public let from: String
    public let to: String
    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Pure logic that decides whether an edit to OmniSpeak's inserted text is a vocabulary
/// correction worth learning. Deterministic and side-effect-free so it's fully unit-tested;
/// the Accessibility plumbing that feeds it lives in `CorrectionWatcher` (app layer).
public enum CorrectionClassifier {
    private static let outerPunctuation = CharacterSet(charactersIn: ".,!?;:\"'`“”‘’()[]{}")

    /// - Parameters:
    ///   - before: the field value right after OmniSpeak inserted.
    ///   - after: the field value now.
    ///   - insertedRange: the range OmniSpeak wrote within `before`.
    /// - Returns: a `LearnedCorrection` when the edit is a vocabulary fix that
    ///   overlaps the inserted span; otherwise nil.
    public static func classify(before: String, after: String, insertedRange: Range<String.Index>) -> LearnedCorrection? {
        let beforeChars = Array(before)
        let afterChars = Array(after)

        // Minimal changed region: trim the common prefix and (non-overlapping) common suffix.
        var prefix = 0
        let maxPrefix = min(beforeChars.count, afterChars.count)
        while prefix < maxPrefix && beforeChars[prefix] == afterChars[prefix] { prefix += 1 }

        var suffix = 0
        while suffix < (maxPrefix - prefix)
            && beforeChars[beforeChars.count - 1 - suffix] == afterChars[afterChars.count - 1 - suffix] {
            suffix += 1
        }

        var beforeStart = prefix
        var beforeEnd = beforeChars.count - suffix   // exclusive
        var afterEnd = afterChars.count - suffix      // exclusive (afterStart == prefix too)
        guard beforeStart <= beforeEnd, prefix <= afterEnd else { return nil }
        guard beforeStart != beforeEnd || prefix != afterEnd else { return nil } // no change

        // Expand both boundaries out to whole words, so "there"→"their" or "neuron's"→"NeroNook"
        // is extracted as full tokens (not partial character diffs).
        while beforeStart > 0 && !beforeChars[beforeStart - 1].isWhitespace { beforeStart -= 1 }
        while beforeEnd < beforeChars.count && !beforeChars[beforeEnd].isWhitespace {
            beforeEnd += 1
            afterEnd += 1
        }
        let afterStart = beforeStart

        let rawFrom = String(beforeChars[beforeStart..<beforeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTo = String(afterChars[afterStart..<afterEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip trailing/leading outer punctuation while preserving internal apostrophes/hyphens
        // (e.g. "neuron's." -> "neuron's", "NeroNook." -> "NeroNook").
        var from = stripOuterPunctuation(rawFrom)
        var to = stripOuterPunctuation(rawTo)
        guard !from.isEmpty, !to.isEmpty, from != to else { return nil }

        // If both `from` and `to` end with the exact same possessive "'s" / "’s",
        // learn the base word ("neuron's" -> "NeroNook's" learns "neuron" -> "NeroNook").
        if let strippedFrom = stripPossessiveSuffix(from),
           let strippedTo = stripPossessiveSuffix(to),
           !strippedFrom.isEmpty, !strippedTo.isEmpty
        {
            from = strippedFrom
            to = strippedTo
        }

        // Guard against mid-typing partial artifacts (single letter like "N" or dangling "neuron'")
        guard to.count >= 2 else { return nil }
        guard let lastTo = to.last, lastTo.isLetter || lastTo.isNumber else { return nil }
        guard to.contains(where: { $0.isLetter }) else { return nil }

        // Reject raw prefix truncations caused by mid-backspace ("neuron's" -> "neuron" without brand casing)
        let fromLower = from.lowercased()
        let toLower = to.lowercased()
        if fromLower.hasPrefix(toLower) && toLower.count < fromLower.count {
            let hasBrandCasing = to.first?.isUppercase == true || to.dropFirst().contains(where: { $0.isUppercase })
            if !hasBrandCasing {
                return nil
            }
        }

        // The edit must overlap the span OmniSpeak inserted.
        let changeStartIdx = before.index(before.startIndex, offsetBy: beforeStart)
        let changeEndIdx = before.index(before.startIndex, offsetBy: beforeEnd)
        guard changeStartIdx < insertedRange.upperBound, insertedRange.lowerBound < changeEndIdx else { return nil }

        // `from` may be a 1–3 token mishearing ("nero nook", "fig ma", "neuron's");
        // `to` (the canonical) may be a single custom word ("NeroNook", "Figma") OR a 2-word
        // proper-noun phrase ("Fuego Desktop", "Omni Plan") where every token is capitalized.
        let fromTokens = tokenCount(from)
        let toTokens = tokenCount(to)
        guard fromTokens >= 1, fromTokens <= 3 else { return nil }
        guard (toTokens == 1 && isLikelyVocabulary(to)) || (toTokens == 2 && isLikelyProperNounPhrase(to)) else {
            return nil
        }

        return LearnedCorrection(from: from, to: to)
    }

    /// A correction is vocabulary-like (worth learning) when the corrected word carries an
    /// uppercase signal (proper noun / brand like "Figma", "SwiftUI", "NeroNook", "macOS")
    /// OR is a single word that isn't a common English word.
    public static func isLikelyVocabulary(_ word: String) -> Bool {
        guard tokenCount(word) == 1, word.count >= 2 else { return false }
        if word.dropFirst().contains(where: { $0.isUppercase }) { return true } // internal caps: SwiftUI, NeroNook, macOS
        if word.first?.isUppercase == true {
            // Capitalized common word at sentence start (e.g. "There" -> "Their") shouldn't be learned.
            if commonWords.contains(word.lowercased()) { return false }
            return true
        }
        return !commonWords.contains(word.lowercased())
    }

    private static func isLikelyProperNounPhrase(_ phrase: String) -> Bool {
        let parts = phrase.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            part.count >= 2
                && part.first?.isUppercase == true
                && !commonWords.contains(part.lowercased())
        }
    }

    private static func stripOuterPunctuation(_ value: String) -> String {
        value.trimmingCharacters(in: outerPunctuation)
    }

    private static func stripPossessiveSuffix(_ value: String) -> String? {
        if value.lowercased().hasSuffix("'s") || value.lowercased().hasSuffix("’s") {
            return String(value.dropLast(2))
        }
        return nil
    }

    private static func tokenCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Common English words (incl. frequent homophones) where a "correction" is almost always
    /// a grammar fix, not new vocabulary. Curated rather than exhaustive — bad learns are
    /// undoable and visible in Settings.
    static let commonWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "then", "than", "so", "because", "as",
        "to", "too", "two", "of", "in", "on", "at", "by", "for", "with", "about", "from",
        "into", "over", "under", "again", "further", "here", "there", "their", "theyre",
        "they're", "your", "youre", "you're", "its", "it's", "whos", "who's", "whose",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
        "my", "mine", "our", "ours", "his", "hers", "this", "that", "these", "those",
        "is", "am", "are", "was", "were", "be", "been", "being", "have", "has", "had",
        "do", "does", "did", "will", "would", "should", "could", "can", "may", "might",
        "must", "shall", "not", "no", "yes", "all", "any", "some", "few", "more", "most",
        "other", "such", "only", "own", "same", "very", "just", "now", "well", "also",
        "up", "down", "out", "off", "above", "below", "between", "through", "during",
        "before", "after", "while", "where", "when", "why", "how", "what", "which", "who",
        "fast", "slow", "quick", "good", "bad", "new", "old", "great", "high", "low",
        "right", "left", "first", "last", "next", "many", "much", "long", "little",
        "go", "going", "went", "gone", "get", "got", "make", "made", "see", "saw",
        "know", "knew", "think", "thought", "take", "took", "come", "came", "want",
        "use", "used", "find", "found", "give", "gave", "tell", "told", "ask", "work",
        "to's", "lose", "loose", "affect", "effect", "accept", "except", "then's",
    ]
}
