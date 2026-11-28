import Foundation

/// Selects how OmniSpeak restores commas, periods, and question marks locally (zero-LLM).
public enum LocalPunctuationEngine: String, CaseIterable, Codable, Equatable, Sendable {
    case off = "off"
    case fastRules = "fast_rules"
    case coreMLAuto = "coreml_auto"

    public var displayName: String {
        switch self {
        case .off:
            "Off"
        case .fastRules:
            "Fast Rules (<1 ms)"
        case .coreMLAuto:
            "CoreML ANE + Rules"
        }
    }

    public var shortLabel: String {
        switch self {
        case .off:
            "Off"
        case .fastRules:
            "Fast Rules"
        case .coreMLAuto:
            "CoreML ANE"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            "Keep punctuation exactly as emitted by the speech model."
        case .fastRules:
            "Instant <1 ms zero-download comma, clause, and question-mark rules."
        case .coreMLAuto:
            "Uses the on-device Apple Neural Engine CoreML punctuation model (~8–15 ms) when downloaded, falling back seamlessly to instant rules."
        }
    }
}

/// Selects the local, zero-LLM grammar engine run on dictated text.
public enum LocalGrammarEngine: String, CaseIterable, Codable, Equatable, Sendable {
    case off = "off"
    case harperRust = "harper_rust"
    case macOSNative = "macos_native"
    case harperAndMacOS = "harper_and_macos"

    public var displayName: String {
        switch self {
        case .off:
            "Off"
        case .harperRust:
            "Harper Rust (<2 ms)"
        case .macOSNative:
            "macOS Native"
        case .harperAndMacOS:
            "Harper + macOS"
        }
    }

    public var shortLabel: String {
        switch self {
        case .off:
            "Off"
        case .harperRust:
            "Harper"
        case .macOSNative:
            "macOS"
        case .harperAndMacOS:
            "Both"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            "Disable local zero-LLM grammar checking."
        case .harperRust:
            "Runs the built-in Harper Rust grammar engine inside omnivoice-engine (<2 ms, offline)."
        case .macOSNative:
            "Uses Apple's built-in NSSpellChecker grammar and spelling pass (~8 ms)."
        case .harperAndMacOS:
            "Runs Harper Rust (<2 ms) followed by macOS native grammar with Personal Dictionary guardrails."
        }
    }
}

/// User-configurable settings for local, zero-LLM voice-stream punctuation and grammar.
public struct LocalStreamPolishConfiguration: Codable, Equatable, Sendable {
    public var punctuationEngine: LocalPunctuationEngine
    public var grammarEngine: LocalGrammarEngine
    public var liveStreamPunctuationEnabled: Bool
    public var activeWindowVocabularyEnabled: Bool

    public static let defaults = LocalStreamPolishConfiguration(
        punctuationEngine: .coreMLAuto,
        grammarEngine: .harperAndMacOS,
        liveStreamPunctuationEnabled: true,
        activeWindowVocabularyEnabled: true
    )

    public init(
        punctuationEngine: LocalPunctuationEngine = .coreMLAuto,
        grammarEngine: LocalGrammarEngine = .harperAndMacOS,
        liveStreamPunctuationEnabled: Bool = true,
        activeWindowVocabularyEnabled: Bool = true
    ) {
        self.punctuationEngine = punctuationEngine
        self.grammarEngine = grammarEngine
        self.liveStreamPunctuationEnabled = liveStreamPunctuationEnabled
        self.activeWindowVocabularyEnabled = activeWindowVocabularyEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case punctuationEngine = "punctuation_engine"
        case grammarEngine = "grammar_engine"
        case liveStreamPunctuationEnabled = "live_stream_punctuation_enabled"
        case activeWindowVocabularyEnabled = "active_window_vocabulary_enabled"
    }

    private enum CamelCodingKeys: String, CodingKey {
        case punctuationEngine
        case grammarEngine
        case liveStreamPunctuationEnabled
        case activeWindowVocabularyEnabled
    }

    public init(from decoder: Decoder) throws {
        let snake = try? decoder.container(keyedBy: CodingKeys.self)
        let camel = try? decoder.container(keyedBy: CamelCodingKeys.self)
        let punct = (try? snake?.decodeIfPresent(LocalPunctuationEngine.self, forKey: .punctuationEngine))
            ?? (try? camel?.decodeIfPresent(LocalPunctuationEngine.self, forKey: .punctuationEngine))
            ?? Self.defaults.punctuationEngine
        let grammar = (try? snake?.decodeIfPresent(LocalGrammarEngine.self, forKey: .grammarEngine))
            ?? (try? camel?.decodeIfPresent(LocalGrammarEngine.self, forKey: .grammarEngine))
            ?? Self.defaults.grammarEngine
        let live = (try? snake?.decodeIfPresent(Bool.self, forKey: .liveStreamPunctuationEnabled))
            ?? (try? camel?.decodeIfPresent(Bool.self, forKey: .liveStreamPunctuationEnabled))
            ?? Self.defaults.liveStreamPunctuationEnabled
        let activeWindowVocab = (try? snake?.decodeIfPresent(Bool.self, forKey: .activeWindowVocabularyEnabled))
            ?? (try? camel?.decodeIfPresent(Bool.self, forKey: .activeWindowVocabularyEnabled))
            ?? Self.defaults.activeWindowVocabularyEnabled
        self.init(
            punctuationEngine: punct,
            grammarEngine: grammar,
            liveStreamPunctuationEnabled: live,
            activeWindowVocabularyEnabled: activeWindowVocab
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(punctuationEngine, forKey: .punctuationEngine)
        try container.encode(grammarEngine, forKey: .grammarEngine)
        try container.encode(liveStreamPunctuationEnabled, forKey: .liveStreamPunctuationEnabled)
        try container.encode(activeWindowVocabularyEnabled, forKey: .activeWindowVocabularyEnabled)
    }
}

/// Sub-millisecond, zero-download deterministic voice-stream punctuator.
///
/// Designed to run safely both on live streaming partials (`isFinal: false`)
/// and on finalized dictation (`isFinal: true`):
/// - Inserts commas after sentence-initial introductory markers ("Well,", "However,", "For example,", …)
/// - Inserts commas before independent-clause conjunctions ("... , but I ...", "... , so we ...", "... , and then ...")
/// - Detects natural English questions and applies `?` on finalized sentences
/// - Normalizes standalone `I` and sentence-start capitalization without altering any spoken words.
public enum StreamPunctuator {
    private static let introductoryMultiWord: [String] = [
        "on the other hand",
        "by the way",
        "for example",
        "for instance",
        "in addition",
        "in general",
        "in fact",
        "of course",
        "as a result",
        "at the same time",
        "after all",
        "to be honest",
        "first of all",
    ]

    private static let introductorySingleWord: [String] = [
        "however",
        "actually",
        "honestly",
        "basically",
        "meanwhile",
        "fortunately",
        "unfortunately",
        "finally",
        "overall",
        "instead",
        "otherwise",
        "therefore",
        "furthermore",
        "moreover",
        "anyway",
        "well",
        "first",
        "second",
        "third",
    ]

    private static let clauseSubjectPronouns: Set<String> = [
        "i", "i'm", "i've", "i'll", "i'd", "i’m", "i’ve", "i’ll", "i’d",
        "we", "we're", "we've", "we'll", "we'd",
        "you", "you're", "you've", "you'll", "you'd",
        "they", "they're", "they've", "they'll", "they'd",
        "he", "he's", "she", "she's", "it", "it's", "there", "that", "this",
    ]

    private static let questionStartersMulti: [String] = [
        "is there", "are there", "is it", "is this", "is that",
        "are we", "are you", "can we", "can you", "can i",
        "could we", "could you", "could i", "would you", "would it", "would we",
        "do you", "do we", "does it", "does this", "does that",
        "did you", "did we", "did it", "will it", "will you", "will we",
        "should we", "should i", "should it", "have you", "have we", "has it",
        "what's", "what is", "what are", "what do", "what does", "what did", "what would", "what should",
        "where's", "where is", "where are", "where do", "where did",
        "when's", "when is", "when are", "when do", "when did", "when will",
        "why is", "why are", "why do", "why does", "why did", "why would",
        "how do", "how does", "how did", "how is", "how are", "how can", "how would", "how much", "how many",
        "who is", "who are", "who did", "who can", "which one", "which is",
    ]

    private static let standaloneIRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])i(?=(?:['’](?:m|ve|ll|d)\b|\b))"#,
        options: []
    )

    private static let sentenceStartRegex = try! NSRegularExpression(
        pattern: #"(^|[.!?]\s+|\n\s*)([a-z])"#,
        options: []
    )

    private static let nonListIdiomNouns: Set<String> = [
        "time", "times", "place", "places", "floor", "floors", "half", "halves",
        "part", "parts", "day", "days", "week", "weeks", "month", "months",
        "year", "years", "hand", "hands", "step", "steps", "thing", "things",
        "person", "people", "one", "ones", "round", "rounds", "base", "class",
        "grade", "level", "stage", "phase", "draft", "version", "attempt", "try",
        "chance", "choice", "option", "thought", "thoughts", "impression",
        "glance", "sight", "shot", "pass", "run", "look", "word", "line",
        "page", "chapter", "section", "aid", "wind", "name", "language",
        "nature", "opinion", "guess", "rate", "degree", "order", "quarter",
        "gear", "amendment", "century", "street", "avenue",
    ]

    private static let ordinalDisallowedPrecedingWords: Set<String> = [
        "the", "a", "an", "my", "our", "your", "his", "her", "its", "their",
        "this", "that", "these", "those", "at", "in", "for", "of", "on", "to",
        "by", "from", "as", "into", "every", "each", "very", "per", "last",
        "next", "another", "one", "two", "three", "split", "half", "just",
        "only", "wait", "hold", "give", "take",
    ]

    private static let explicitDisallowedPrecedingWords: Set<String> = [
        "the", "a", "an", "this", "that", "my", "our", "your", "is", "was",
        "are", "were", "be", "been", "in", "on", "at", "of", "to", "for",
        "from", "by", "with", "after", "before", "during", "skip", "finish",
        "complete", "repeat",
    ]

    private static let ordinalValueMap: [String: Int] = [
        "first": 1, "firstly": 1,
        "second": 2, "secondly": 2,
        "third": 3, "thirdly": 3,
        "fourth": 4, "fourthly": 4,
        "fifth": 5, "fifthly": 5,
        "sixth": 6, "sixthly": 6,
        "seventh": 7, "seventhly": 7,
        "eighth": 8, "eighthly": 8,
        "ninth": 9, "ninthly": 9,
        "tenth": 10, "tenthly": 10,
    ]

    private static let spokenNumberValueMap: [String: Int] = [
        "one": 1, "1": 1,
        "two": 2, "2": 2,
        "three": 3, "3": 3,
        "four": 4, "4": 4,
        "five": 5, "5": 5,
        "six": 6, "6": 6,
        "seven": 7, "7": 7,
        "eight": 8, "8": 8,
        "nine": 9, "9": 9,
        "ten": 10, "10": 10,
    ]

    private static let listMarkerRegex = try! NSRegularExpression(
        pattern: #"(?:\b(and)[ \t]+)?(?:(?:\b(firstly|secondly|thirdly|fourthly|fifthly|sixthly|seventhly|eighthly|ninthly|tenthly|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\b)|(?:\b(number|step|item)[ \t]+(one|two|three|four|five|six|seven|eight|nine|ten|10|[1-9])\b))([,:\-—]|\.(?=[ \t]))?[ \t]+"#,
        options: [.caseInsensitive]
    )

    private static let introductoryRegexes: [NSRegularExpression] = {
        let ordinalGuard = nonListIdiomNouns.sorted().joined(separator: "|")
        let all = introductoryMultiWord + introductorySingleWord
        return all.map { phrase in
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
                .replacingOccurrences(of: "\\ ", with: "\\s+")
            // Match at start of string or after sentence break, only when NOT already followed by punctuation
            // and followed by at least two words (so "Well done" or bare "Okay" stays clean).
            // For "first" / "second" / "third", skip non-list idioms like "first time", "second floor".
            let guardLookahead: String
            if phrase == "first" || phrase == "second" || phrase == "third" {
                guardLookahead = "(?!(?:" + ordinalGuard + ")\\b)"
            } else {
                guardLookahead = ""
            }
            let pattern = #"(^|[.!?]\s+|\n\s*)("# + escaped + #")(\s+"# + guardLookahead + #"(?=[A-Za-z0-9'’"]+\s+[A-Za-z0-9'’"]+))"#
            return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }()

    public static func punctuate(_ raw: String, isFinal: Bool) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        guard !text.isEmpty else { return "" }

        // 1. Standalone "i" -> "I"
        text = standaloneIRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: "I"
        )

        // 2. Sentence-initial introductory commas ("However we..." -> "However, we...")
        for regex in introductoryRegexes {
            let ns = text as NSString
            text = regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "$1$2,$3"
            )
        }

        // 3. Independent-clause coordinating commas ("... but I ...", "... so we ...", "... and then ...")
        text = insertCoordinatingClauseCommas(in: text)

        // 4. Sentence-start capitalization
        text = capitalizeSentenceStarts(in: text)

        // 5. Final punctuation (`.`, `?`) and spoken numbered list formatting only when finalized
        if isFinal {
            text = applyFinalSentencePunctuation(in: text)
            text = formatNumberedLists(text)
        }

        // Clean spacing around punctuation (preserving intentional newlines from numbered lists)
        text = text
            .replacingOccurrences(of: #"[ \t]+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #",{2,}"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    private enum ListMarkerFamily: Equatable {
        case ordinal
        case number
        case step
        case item
    }

    private struct ListMarkerCandidate {
        let family: ListMarkerFamily
        let ordinalValue: Int
        let markerStart: String.Index
        let bodyStart: String.Index
    }

    /// Converts spoken sequential lists ("First ... Second ... Third ...",
    /// "Number one ... Number two ...", "Step one ... Step two ...", "Item one ... Item two ...")
    /// into clean newline-separated `1. ...`, `2. ...`, `3. ...` items in <1 ms (zero-LLM).
    ///
    /// Strict guardrails:
    /// - Requires at least 2 sequential items starting at 1 (`1, 2, [3, ...]`) in the same family
    /// - Never triggers on a single marker ("First, let's check the logs.")
    /// - Never triggers on out-of-order markers ("Second ... First ...")
    /// - Never triggers on non-list idioms ("first time ... second time", "a second", "the first ...")
    public static func formatNumberedLists(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let ns = trimmed as NSString
        let matches = listMarkerRegex.matches(
            in: trimmed,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        guard matches.count >= 2 else { return text }

        var candidates: [ListMarkerCandidate] = []
        candidates.reserveCapacity(matches.count)

        for match in matches {
            guard let fullRange = Range(match.range, in: trimmed) else { continue }

            let hasAndPrefix = match.range(at: 1).location != NSNotFound
            let ordinalRange = match.range(at: 2)
            let explicitPrefixRange = match.range(at: 3)
            let explicitNumberRange = match.range(at: 4)
            let delimiterRange = match.range(at: 5)
            let hasExplicitDelimiter = delimiterRange.location != NSNotFound

            let family: ListMarkerFamily
            let ordinalValue: Int
            let keywordRange: NSRange
            var isLyOrdinal = false

            if ordinalRange.location != NSNotFound {
                let word = ns.substring(with: ordinalRange).lowercased()
                guard let value = ordinalValueMap[word] else { continue }
                family = .ordinal
                ordinalValue = value
                keywordRange = ordinalRange
                isLyOrdinal = word.hasSuffix("ly")
            } else if explicitPrefixRange.location != NSNotFound,
                      explicitNumberRange.location != NSNotFound
            {
                let prefix = ns.substring(with: explicitPrefixRange).lowercased()
                let numWord = ns.substring(with: explicitNumberRange).lowercased()
                guard let value = spokenNumberValueMap[numWord] else { continue }
                switch prefix {
                case "number": family = .number
                case "step": family = .step
                case "item": family = .item
                default: continue
                }
                ordinalValue = value
                keywordRange = explicitPrefixRange
            } else {
                continue
            }

            // Only absorb a leading "and " for items 2..10 (e.g., "And third, ...").
            let markerStart: String.Index
            if hasAndPrefix && ordinalValue == 1 {
                guard let kwStart = Range(keywordRange, in: trimmed)?.lowerBound else { continue }
                markerStart = kwStart
            } else {
                markerStart = fullRange.lowerBound
            }
            let bodyStart = fullRange.upperBound
            guard bodyStart < trimmed.endIndex else { continue }

            // Guardrail 1: Check preceding word (reject "the first", "a second", "in step one", etc.)
            if let prevWord = precedingWordBefore(markerStart, in: trimmed) {
                switch family {
                case .ordinal:
                    if ordinalDisallowedPrecedingWords.contains(prevWord) { continue }
                case .number, .step, .item:
                    if explicitDisallowedPrecedingWords.contains(prevWord) { continue }
                }
            }

            // Guardrail 2: For bare ordinals (without comma/colon/dash and not -ly),
            // reject common non-list idioms ("first time", "second floor", "first step", etc.)
            if family == .ordinal && !hasExplicitDelimiter && !isLyOrdinal {
                if let nextWord = firstWordStartingAt(bodyStart, in: trimmed),
                   nonListIdiomNouns.contains(nextWord)
                {
                    continue
                }
            }

            candidates.append(ListMarkerCandidate(
                family: family,
                ordinalValue: ordinalValue,
                markerStart: markerStart,
                bodyStart: bodyStart
            ))
        }

        guard candidates.count >= 2 else { return text }

        // Find the first valid sequential run 1, 2, [3, ...] of the same family with non-empty item bodies.
        for startIndex in candidates.indices {
            let first = candidates[startIndex]
            guard first.ordinalValue == 1 else { continue }

            // Guardrail 3: Reject if an out-of-order marker of the same family (>= 2) appeared before item 1.
            let hasEarlierHigherMarker = candidates[..<startIndex].contains {
                $0.family == first.family && $0.ordinalValue >= 2
            }
            if hasEarlierHigherMarker {
                continue
            }

            var chain: [ListMarkerCandidate] = [first]
            var expected = 2

            for idx in (startIndex + 1)..<candidates.count {
                let candidate = candidates[idx]
                guard candidate.family == first.family else { continue }
                if candidate.ordinalValue == expected {
                    let prev = chain[chain.count - 1]
                    let segment = cleanedItemBody(
                        String(trimmed[prev.bodyStart..<candidate.markerStart]),
                        isLastItem: false
                    )
                    if !segment.isEmpty {
                        chain.append(candidate)
                        expected += 1
                    }
                }
            }

            guard chain.count >= 2 else { continue }
            let finalBody = cleanedItemBody(
                String(trimmed[chain[chain.count - 1].bodyStart..<trimmed.endIndex]),
                isLastItem: true
            )
            guard !finalBody.isEmpty else { continue }

            // Build formatted output: preserve lead-in on its own line, then `1. ...`, `2. ...`, ...
            var lines: [String] = []
            var leadIn = String(trimmed[..<chain[0].markerStart])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !leadIn.isEmpty {
                if leadIn.hasSuffix(",") || leadIn.hasSuffix(";") {
                    leadIn = String(leadIn.dropLast()).trimmingCharacters(in: .whitespaces) + ":"
                }
                lines.append(leadIn)
            }

            for (idx, marker) in chain.enumerated() {
                let isLast = (idx == chain.count - 1)
                let endIndex = isLast ? trimmed.endIndex : chain[idx + 1].markerStart
                let body = cleanedItemBody(String(trimmed[marker.bodyStart..<endIndex]), isLastItem: isLast)
                let capitalized = capitalizeListItemStart(body)
                lines.append("\(idx + 1). \(capitalized)")
            }

            return lines.joined(separator: "\n")
        }

        return text
    }

    private static func precedingWordBefore(_ index: String.Index, in text: String) -> String? {
        var cursor = index
        while cursor > text.startIndex {
            let prev = text.index(before: cursor)
            if text[prev] == " " || text[prev] == "\t" {
                cursor = prev
            } else {
                break
            }
        }
        guard cursor > text.startIndex else { return nil }
        let lastChar = text[text.index(before: cursor)]
        // Sentence or clause boundary immediately before the marker
        if "\n.!?:;,—-".contains(lastChar) {
            return nil
        }
        var wordStart = cursor
        while wordStart > text.startIndex {
            let prev = text.index(before: wordStart)
            if text[prev].isWhitespace {
                break
            }
            wordStart = prev
        }
        let word = String(text[wordStart..<cursor])
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        return word.isEmpty ? nil : word
    }

    private static func firstWordStartingAt(_ index: String.Index, in text: String) -> String? {
        var cursor = index
        while cursor < text.endIndex && text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex else { return nil }
        var wordEnd = cursor
        while wordEnd < text.endIndex && !text[wordEnd].isWhitespace {
            wordEnd = text.index(after: wordEnd)
        }
        let word = String(text[cursor..<wordEnd])
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        return word.isEmpty ? nil : word
    }

    private static func cleanedItemBody(_ raw: String, isLastItem: Bool) -> String {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = body.first, ",:-—;".contains(first) {
            body = String(body.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !isLastItem {
            while let last = body.last, ",;".contains(last) {
                body = String(body.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return body
    }

    private static func capitalizeListItemStart(_ body: String) -> String {
        guard let firstChar = body.first, firstChar.isLowercase else { return body }
        // Preserve intentional lowercase-start brand words like "iPhone" / "macOS" / "iOS"
        let firstWord = body.prefix(while: { !$0.isWhitespace })
        if firstWord.dropFirst().contains(where: \.isUppercase) {
            return body
        }
        return firstChar.uppercased() + body.dropFirst()
    }

    private static func insertCoordinatingClauseCommas(in text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 6 else { return text }

        var out = words
        var wordsSinceBreak = 0

        for idx in 0..<out.count {
            let token = out[idx]
            let lower = token.lowercased().trimmingCharacters(in: .punctuationCharacters)

            if idx >= 4, wordsSinceBreak >= 4, idx + 1 < out.count {
                let prev = out[idx - 1]
                let prevHasPunct = prev.last.map { ",.;:!?-—".contains($0) } ?? false
                let nextLower = out[idx + 1].lowercased().trimmingCharacters(in: .punctuationCharacters)

                let shouldInsertComma: Bool
                if !prevHasPunct {
                    if (lower == "but" || lower == "so") && clauseSubjectPronouns.contains(nextLower) {
                        shouldInsertComma = true
                    } else if lower == "and" && nextLower == "then" {
                        shouldInsertComma = true
                    } else if lower == "however" || lower == "although" || lower == "whereas" {
                        shouldInsertComma = true
                    } else {
                        shouldInsertComma = false
                    }
                } else {
                    shouldInsertComma = false
                }

                if shouldInsertComma {
                    out[idx - 1] = prev + ","
                    wordsSinceBreak = 0
                }
            }

            if let last = out[idx].last, ",.;:!?".contains(last) {
                wordsSinceBreak = 0
            } else {
                wordsSinceBreak += 1
            }
        }

        return out.joined(separator: " ")
    }

    private static func capitalizeSentenceStarts(in text: String) -> String {
        let ns = text as NSString
        let matches = sentenceStartRegex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var mutable = ns
        for match in matches.reversed() {
            let letterRange = match.range(at: 2)
            let upper = mutable.substring(with: letterRange).uppercased()
            mutable = mutable.replacingCharacters(in: letterRange, with: upper) as NSString
        }
        return mutable as String
    }

    private static func applyFinalSentencePunctuation(in text: String) -> String {
        guard !text.isEmpty else { return text }
        // Inspect only the final sentence after the last `. ! ? \n`
        let lastSentence: String
        if let range = text.range(of: #"[.!?]\s+|\n"#, options: [.regularExpression, .backwards]) {
            lastSentence = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            lastSentence = text
        }
        guard !lastSentence.isEmpty else { return text }

        let wordCount = lastSentence.split(whereSeparator: { $0.isWhitespace }).count
        let looksLikeQuestion = isLikelyQuestion(lastSentence)

        if let last = text.last {
            if last == "." && looksLikeQuestion {
                return String(text.dropLast()) + "?"
            }
            if ".!?:;\"'”’)]}".contains(last) {
                return text
            }
        }

        if looksLikeQuestion && wordCount >= 2 {
            return text + "?"
        }
        if wordCount >= 3 {
            return text + "."
        }
        return text
    }

    private static func isLikelyQuestion(_ sentence: String) -> Bool {
        var cleaned = sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;:"))
        // Strip leading conversational fillers/markers before checking question opener
        for lead in ["well,", "so,", "okay,", "ok,", "hey,", "actually,", "also,", "and ", "so ", "well "] {
            if cleaned.hasPrefix(lead) {
                cleaned = String(cleaned.dropFirst(lead.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for starter in questionStartersMulti {
            if cleaned == starter || cleaned.hasPrefix(starter + " ") {
                return true
            }
        }
        return false
    }
}
