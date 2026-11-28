import AppKit
import Foundation
import NaturalLanguage
import OmniVoiceCore

struct LocalDictationCleanupOutcome: Equatable, Sendable {
    let text: String
    let cleanupApplied: Bool
    let selfCorrection: SelfCorrectionResolution
    let grammarFixesApplied: Int
    let needsLLMEscalation: Bool
}

/// Fast, 100% on-device, zero-LLM dictation cleanup & grammar corrector using:
/// 1. `SelfCorrectionResolver` (sentence resets, anchor-overlap splices, typed slot swaps)
/// 2. Deterministic filler, doubled-word, spoken-punctuation, capitalization, and dictionary polish
/// 3. Native macOS `NSSpellChecker` grammar & spelling pass protected by `NLTagger` proper nouns,
///    code/URL masks, and the user's Personal Dictionary.
@MainActor
enum LocalDictationCleanupService {
    private static let leadingFillersRegex = try! NSRegularExpression(
        pattern: #"^(?:um+|uh+|er+|ah+|hmm+|so\s+yeah|basically|i\s+just\s+wanted\s+to\s+say\s+that)[,.]?\s+"#,
        options: [.caseInsensitive]
    )
    private static let midHesitationRegex = try! NSRegularExpression(
        pattern: #"(?:,\s*|\s+)\b(?:um+|uh+|er+|ah+|hmm+)\b(?:,\s*|\s+)"#,
        options: [.caseInsensitive]
    )
    private static let doubledWordRegex = try! NSRegularExpression(
        pattern: #"\b([A-Za-z]+)\s+\1\b"#,
        options: [.caseInsensitive]
    )
    private static let standaloneIRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])i(?=(?:['’](?:m|ve|ll|d)\b|\b))"#,
        options: []
    )
    private static let sentenceStartRegex = try! NSRegularExpression(
        pattern: #"(^|[.!?]\s+|\n\s*)([a-z])"#,
        options: []
    )
    private static let protectedTokenRegex = try! NSRegularExpression(
        pattern: #"https?://\S+|\b\S+@\S+\.\S+\b|(?:/|~/)[^\s]+|\b[a-z]+[A-Z][A-Za-z0-9]*\b|\b[A-Za-z]+_[A-Za-z0-9_]+\b|\b[A-Z]{2,}[0-9]*\b"#,
        options: []
    )

    static func clean(
        rawTranscript: String,
        style: StyleProfile,
        dictionaryTerms: [String],
        dictionaryEntries: [DictionaryEntry],
        ephemeralVocabulary: [String] = [],
        polishConfig: LocalStreamPolishConfiguration = .defaults,
        engineClient: EngineClient? = nil
    ) async -> LocalDictationCleanupOutcome {
        let initial = rawTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        guard !initial.isEmpty else {
            return LocalDictationCleanupOutcome(
                text: "",
                cleanupApplied: false,
                selfCorrection: SelfCorrectionResolution(text: "", kind: .none),
                grammarFixesApplied: 0,
                needsLLMEscalation: false
            )
        }

        let effectiveDictionaryTerms = mergeVocabularyTerms(dictionaryTerms, ephemeralVocabulary)

        // 1. Spoken self-correction pass (zero-LLM, <1 ms)
        let correction = SelfCorrectionResolver.resolve(initial)
        var text = correction.text

        // 2. Spoken punctuation + filler removal + doubled-word cleanup
        text = applySpokenPunctuation(text)
        if style != .raw {
            text = stripHesitationFillers(text)
        }
        text = collapseDoubledWords(text)
        text = normalizeStandaloneI(text)

        // 3. Configurable local punctuation restoration (CoreML ANE ~10 ms or Fast Rules <1 ms)
        //    plus deterministic spoken numbered-list formatting (<1 ms).
        switch polishConfig.punctuationEngine {
        case .off:
            break
        case .fastRules:
            text = StreamPunctuator.punctuate(text, isFinal: true)
        case .coreMLAuto:
            if let neural = await CoreMLPunctuationService.shared.restorePunctuation(text, isFinal: true) {
                text = StreamPunctuator.formatNumberedLists(neural)
            } else {
                text = StreamPunctuator.punctuate(text, isFinal: true)
            }
        }
        if polishConfig.punctuationEngine != .off {
            text = StreamPunctuator.formatNumberedLists(text)
        }

        // 4. Configurable local grammar checking (Harper Rust <2 ms and/or macOS NSSpellChecker ~8 ms)
        let protectedTerms = buildProtectedTerms(
            dictionaryTerms: effectiveDictionaryTerms,
            dictionaryEntries: dictionaryEntries
        )
        var grammarFixCount = 0

        if polishConfig.grammarEngine == .harperRust || polishConfig.grammarEngine == .harperAndMacOS,
           let engineClient
        {
            if let harper = try? await engineClient.checkGrammar(
                text: text,
                protectedTerms: Array(protectedTerms)
            ), !harper.text.isEmpty {
                text = harper.text
                grammarFixCount += harper.appliedCount
            }
        }

        if polishConfig.grammarEngine == .macOSNative || polishConfig.grammarEngine == .harperAndMacOS {
            let (grammarPolished, macOSFixCount) = applyMacOSGrammarAndSpelling(
                to: text,
                protectedTerms: protectedTerms
            )
            text = grammarPolished
            grammarFixCount += macOSFixCount
        }

        // 5. Capitalization, dictionary canonicalization, and clean terminal punctuation
        text = capitalizeSentenceStarts(text)
        text = applyDictionaryCanonicalization(
            text,
            dictionaryTerms: effectiveDictionaryTerms,
            dictionaryEntries: dictionaryEntries
        )
        text = normalizeSpacingAndTerminalPunctuation(text, applyTerminalPeriod: polishConfig.punctuationEngine != .off)

        let changed = text != initial
        return LocalDictationCleanupOutcome(
            text: text,
            cleanupApplied: changed,
            selfCorrection: correction,
            grammarFixesApplied: grammarFixCount,
            needsLLMEscalation: correction.needsLLMEscalation
        )
    }

    /// Ultra-fast live-stream partial polish (runs while the user is speaking).
    /// Inserts natural commas, capitalization, and dictionary spellings without prematurely
    /// forcing a period on the still-in-progress tail of an utterance.
    static func polishLivePartial(
        _ rawPartial: String,
        polishConfig: LocalStreamPolishConfiguration,
        dictionaryTerms: [String],
        dictionaryEntries: [DictionaryEntry],
        ephemeralVocabulary: [String] = []
    ) async -> String {
        let sanitized = TextInsertionEdit.sanitizedInsertionText(rawPartial)
        guard !sanitized.isEmpty else { return "" }
        guard polishConfig.liveStreamPunctuationEnabled, polishConfig.punctuationEngine != .off else {
            return sanitized
        }

        let effectiveDictionaryTerms = mergeVocabularyTerms(dictionaryTerms, ephemeralVocabulary)
        var text = collapseDoubledWords(sanitized)
        switch polishConfig.punctuationEngine {
        case .off:
            break
        case .fastRules:
            text = StreamPunctuator.punctuate(text, isFinal: false)
        case .coreMLAuto:
            if let neural = await CoreMLPunctuationService.shared.restorePunctuation(text, isFinal: false) {
                text = neural
            } else {
                text = StreamPunctuator.punctuate(text, isFinal: false)
            }
        }
        text = applyDictionaryCanonicalization(
            text,
            dictionaryTerms: effectiveDictionaryTerms,
            dictionaryEntries: dictionaryEntries
        )
        return text
    }

    static func mergeVocabularyTerms(_ persistent: [String], _ ephemeral: [String]) -> [String] {
        guard !ephemeral.isEmpty else { return persistent }
        var seen = Set<String>()
        var merged: [String] = []
        merged.reserveCapacity(persistent.count + ephemeral.count)
        for term in persistent {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                merged.append(trimmed)
            }
        }
        for term in ephemeral {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                merged.append(trimmed)
            }
        }
        return merged
    }

    // MARK: - Native macOS NSSpellChecker Grammar & Spelling

    private static func applyMacOSGrammarAndSpelling(
        to text: String,
        protectedTerms: Set<String>
    ) -> (String, Int) {
        let ns = text as NSString
        guard ns.length >= 3, ns.length <= 4_000 else { return (text, 0) }

        let protectedRanges = collectProtectedRanges(in: text, protectedTerms: protectedTerms)
        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        let fullRange = NSRange(location: 0, length: ns.length)
        let types: NSTextCheckingTypes = NSTextCheckingResult.CheckingType.spelling.rawValue
            | NSTextCheckingResult.CheckingType.grammar.rawValue
            | NSTextCheckingResult.CheckingType.correction.rawValue

        let results = checker.check(
            text,
            range: fullRange,
            types: types,
            options: nil,
            inSpellDocumentWithTag: tag,
            orthography: nil,
            wordCount: nil
        )
        guard !results.isEmpty else { return (text, 0) }

        struct PendingEdit {
            let range: NSRange
            let replacement: String
        }

        var edits: [PendingEdit] = []

        for result in results {
            switch result.resultType {
            case .grammar:
                guard let details = result.grammarDetails else { continue }
                for detail in details {
                    guard let rangeValue = detail[NSGrammarRange] as? NSValue else { continue }
                    let subRange = rangeValue.rangeValue
                    let absoluteRange = NSRange(
                        location: result.range.location + subRange.location,
                        length: subRange.length
                    )
                    guard absoluteRange.location >= 0,
                          absoluteRange.location + absoluteRange.length <= ns.length,
                          !overlapsAny(absoluteRange, protectedRanges),
                          let corrections = detail[NSGrammarCorrections] as? [String],
                          let firstSuggestion = corrections.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !firstSuggestion.isEmpty else {
                        continue
                    }
                    let original = ns.substring(with: absoluteRange)
                    if original != firstSuggestion {
                        edits.append(PendingEdit(range: absoluteRange, replacement: firstSuggestion))
                    }
                }

            case .correction:
                let range = result.range
                guard range.location >= 0,
                      range.location + range.length <= ns.length,
                      !overlapsAny(range, protectedRanges),
                      let replacement = result.replacementString,
                      !replacement.isEmpty else {
                    continue
                }
                let original = ns.substring(with: range)
                if original != replacement {
                    edits.append(PendingEdit(range: range, replacement: replacement))
                }

            case .spelling:
                let range = result.range
                guard range.location >= 0,
                      range.location + range.length <= ns.length,
                      !overlapsAny(range, protectedRanges) else {
                    continue
                }
                let word = ns.substring(with: range)
                // Only auto-apply high-confidence single-word spelling fixes (e.g. "dont" -> "don't", "teh" -> "the")
                // and skip capitalized words that might be niche proper nouns.
                if let first = word.first, first.isUppercase, range.location > 0 {
                    continue
                }
                if let guess = checker.correction(forWordRange: range, in: text, language: "en_US", inSpellDocumentWithTag: tag),
                   !guess.isEmpty,
                   guess != word
                {
                    edits.append(PendingEdit(range: range, replacement: guess))
                }

            default:
                continue
            }
        }

        guard !edits.isEmpty else { return (text, 0) }

        // Sort descending by location and skip overlapping edits
        let sorted = edits.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location > rhs.range.location
            }
            return lhs.range.length > rhs.range.length
        }

        var mutable = text as NSString
        var lastAppliedStart = Int.max
        var applied = 0
        for edit in sorted {
            let end = edit.range.location + edit.range.length
            guard end <= lastAppliedStart else { continue }
            mutable = mutable.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
            lastAppliedStart = edit.range.location
            applied += 1
        }
        return (mutable as String, applied)
    }

    private static func collectProtectedRanges(in text: String, protectedTerms: Set<String>) -> [NSRange] {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []

        // 1. URLs, emails, paths, camelCase, snake_case, ALL-CAPS acronyms
        for match in protectedTokenRegex.matches(in: text, options: [], range: fullRange) {
            ranges.append(match.range)
        }

        // 2. NLTagger named entities (people, organizations, places) so macOS never mangles names
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName || tag == .organizationName || tag == .placeName {
                ranges.append(NSRange(tokenRange, in: text))
            }
            return true
        }

        // 3. Personal Dictionary terms & aliases
        let lowerText = text.lowercased()
        for term in protectedTerms where term.count >= 2 {
            var searchStart = lowerText.startIndex
            while let found = lowerText.range(of: term, range: searchStart..<lowerText.endIndex) {
                ranges.append(NSRange(found, in: text))
                searchStart = found.upperBound
            }
        }

        return ranges
    }

    private static func overlapsAny(_ candidate: NSRange, _ protectedRanges: [NSRange]) -> Bool {
        for range in protectedRanges {
            if NSIntersectionRange(candidate, range).length > 0 {
                return true
            }
        }
        return false
    }

    private static func buildProtectedTerms(
        dictionaryTerms: [String],
        dictionaryEntries: [DictionaryEntry]
    ) -> Set<String> {
        var terms = Set<String>()
        for term in dictionaryTerms {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !cleaned.isEmpty { terms.insert(cleaned) }
        }
        for entry in dictionaryEntries where entry.enabled {
            let canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !canonical.isEmpty { terms.insert(canonical) }
            for alias in entry.aliases {
                let cleaned = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !cleaned.isEmpty { terms.insert(cleaned) }
            }
        }
        return terms
    }

    // MARK: - Deterministic Polish Helpers

    private static func applySpokenPunctuation(_ text: String) -> String {
        let replacements: [(String, String)] = [
            (#"\s+\bcomma\b\s+"#, ", "),
            (#"\s+\bperiod\b\s*"#, ". "),
            (#"\s+\bfull stop\b\s*"#, ". "),
            (#"\s+\bquestion mark\b\s*"#, "? "),
            (#"\s+\bexclamation (?:mark|point)\b\s*"#, "! "),
            (#"\s+\bcolon\b\s+"#, ": "),
            (#"\s+\bsemicolon\b\s+"#, "; "),
            (#"\bnew paragraph\b"#, "\n\n"),
            (#"\bnew line\b"#, "\n"),
        ]
        var current = text
        for (pattern, replacement) in replacements {
            current = current.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return current
    }

    private static func stripHesitationFillers(_ text: String) -> String {
        var current = text
        while true {
            let ns = current as NSString
            let next = leadingFillersRegex.stringByReplacingMatches(
                in: current,
                options: [],
                range: NSRange(location: 0, length: ns.length),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if next == current { break }
            current = next
        }
        while true {
            let ns = current as NSString
            let next = midHesitationRegex.stringByReplacingMatches(
                in: current,
                options: [],
                range: NSRange(location: 0, length: ns.length),
                withTemplate: " "
            )
            if next == current { break }
            current = next
        }
        return current
    }

    private static func collapseDoubledWords(_ text: String) -> String {
        var current = text
        for _ in 0..<3 {
            let ns = current as NSString
            let next = doubledWordRegex.stringByReplacingMatches(
                in: current,
                options: [],
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "$1"
            )
            if next == current { break }
            current = next
        }
        return current
    }

    private static func normalizeStandaloneI(_ text: String) -> String {
        let ns = text as NSString
        return standaloneIRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "I"
        )
    }

    private static func capitalizeSentenceStarts(_ text: String) -> String {
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

    private static func applyDictionaryCanonicalization(
        _ text: String,
        dictionaryTerms: [String],
        dictionaryEntries: [DictionaryEntry]
    ) -> String {
        DictionaryMatcher.apply(
            to: text,
            dictionaryTerms: dictionaryTerms,
            dictionaryEntries: dictionaryEntries
        )
    }

    private static func normalizeSpacingAndTerminalPunctuation(_ text: String, applyTerminalPeriod: Bool = true) -> String {
        var cleaned = text
            .replacingOccurrences(of: #"[ \t]+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        // Don't force a period onto single-word/two-word snippets, already-punctuated text, or when punctuation is off
        let wordCount = cleaned.split(whereSeparator: { $0.isWhitespace }).count
        if applyTerminalPeriod, wordCount >= 3, let last = cleaned.last, !".!?:;\"'”’)]}".contains(last) {
            cleaned.append(".")
        }
        return cleaned
    }
}
