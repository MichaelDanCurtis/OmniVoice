import Foundation

/// A learned mapping: the text OmniVoice inserted (`from`) → the user's corrected form (`to`).
public struct LearnedCorrection: Equatable, Sendable {
    public let from: String
    public let to: String
    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Pure logic that decides whether an edit to OmniVoice's inserted text is a vocabulary
/// correction worth learning. Deterministic and side-effect-free so it's fully unit-tested;
/// the Accessibility plumbing that feeds it lives in `CorrectionWatcher` (app layer).
public enum CorrectionClassifier {
    /// - Parameters:
    ///   - before: the field value right after OmniVoice inserted.
    ///   - after: the field value now.
    ///   - insertedRange: the range OmniVoice wrote within `before`.
    /// - Returns: a `LearnedCorrection` when the edit is a single-word vocabulary fix that
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

        // Expand both boundaries out to whole words, so "there"→"their" is extracted as full
        // words (not "re"→"ir"). Prefix/suffix chars are identical in both strings, so the
        // expansion stays aligned.
        while beforeStart > 0 && !beforeChars[beforeStart - 1].isWhitespace { beforeStart -= 1 }
        while beforeEnd < beforeChars.count && !beforeChars[beforeEnd].isWhitespace {
            beforeEnd += 1
            afterEnd += 1
        }
        let afterStart = beforeStart

        let from = String(beforeChars[beforeStart..<beforeEnd]).trimmingCharacters(in: .whitespaces)
        let to = String(afterChars[afterStart..<afterEnd]).trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty, from != to else { return nil }

        // The edit must overlap the span OmniVoice inserted.
        let changeStartIdx = before.index(before.startIndex, offsetBy: beforeStart)
        let changeEndIdx = before.index(before.startIndex, offsetBy: beforeEnd)
        guard changeStartIdx < insertedRange.upperBound, insertedRange.lowerBound < changeEndIdx else { return nil }

        // `from` may be a 1–2 token mishearing; `to` (the canonical) must be a single word.
        guard tokenCount(from) <= 2, tokenCount(to) == 1, isLikelyVocabulary(to) else { return nil }

        return LearnedCorrection(from: from, to: to)
    }

    /// A correction is vocabulary-like (worth learning) when the corrected word carries an
    /// uppercase signal (proper noun / brand like "Figma", "SwiftUI", "macOS") OR is a single
    /// word that isn't a common English word. This rejects grammar/homophone edits
    /// (there→their, your→you're) from ever becoming global rules.
    public static func isLikelyVocabulary(_ word: String) -> Bool {
        guard tokenCount(word) == 1 else { return false }
        if word.dropFirst().contains(where: { $0.isUppercase }) { return true } // internal caps: SwiftUI, macOS
        if word.first?.isUppercase == true { return true }                      // leading cap: Figma
        return !commonWords.contains(word.lowercased())
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
        "before", "after", "while", "where", "when", "why", "how", "what", "which",
        "fast", "slow", "quick", "good", "bad", "new", "old", "great", "high", "low",
        "right", "left", "first", "last", "next", "many", "much", "long", "little",
        "go", "going", "went", "gone", "get", "got", "make", "made", "see", "saw",
        "know", "knew", "think", "thought", "take", "took", "come", "came", "want",
        "use", "used", "find", "found", "give", "gave", "tell", "told", "ask", "work",
        "to's", "lose", "loose", "affect", "effect", "accept", "except", "then's",
    ]
}
