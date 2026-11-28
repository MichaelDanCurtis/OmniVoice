import Foundation

public enum SelfCorrectionKind: String, Equatable, Sendable {
    case none
    case sentenceReset
    case anchorSplice
    case typedSlotSwap
    case ambiguousNeedsLLM
}

public struct SelfCorrectionResolution: Equatable, Sendable {
    public let text: String
    public let kind: SelfCorrectionKind
    public let appliedCount: Int
    public let needsLLMEscalation: Bool

    public init(
        text: String,
        kind: SelfCorrectionKind,
        appliedCount: Int = 0,
        needsLLMEscalation: Bool = false
    ) {
        self.text = text
        self.kind = kind
        self.appliedCount = appliedCount
        self.needsLLMEscalation = needsLLMEscalation
    }
}

/// Pure-Swift, zero-LLM spoken self-correction resolver.
///
/// Handles three deterministic tiers in sub-millisecond time:
/// 1. **Sentence-scoped resets:** "let me rephrase", "scratch that", "start over", "oops, sorry, let me rephrase", "never mind, …"
///    — replaces only the current sentence/clause while keeping earlier completed sentences intact.
/// 2. **Anchor-overlap phrase splice:** "Let's look at this page to the right. Oops, I mean the page to the left."
///    — matches shared words/determiners/prepositions between the tail before the cue and the replacement phrase.
/// 3. **Typed slot swap:** numbers, currency, times, weekdays, months, ordinals, and opposite/direction pairs
///    — e.g. "Change timeout to 30 seconds, oops sorry, 45" -> "Change timeout to 45 seconds."
///
/// When a clear spoken repair cue is detected but none of the deterministic strategies match with high
/// confidence (e.g. a freeform semantic rewrite with zero lexical or slot overlap), `needsLLMEscalation`
/// is returned as `true` so Standard (Smart Hybrid) mode can escalate only that utterance to an LLM.
public enum SelfCorrectionResolver {
    private enum CueCategory {
        case sentenceReset
        case inlineRepair
    }

    private struct CueSpec {
        let regex: NSRegularExpression
        let category: CueCategory
    }

    private struct CueMatch {
        let range: NSRange
        let category: CueCategory
    }

    private enum SlotType: Equatable {
        case currency
        case time
        case number
        case weekday
        case month
        case ordinal
        case direction(Int) // group ID of opposite/direction family
    }

    private struct WordToken {
        let text: String
        let lower: String
        let cleanedLower: String
        let range: NSRange
    }

    private static let determiners: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "your", "our", "his", "her", "their", "its",
    ]

    private static let prepositions: Set<String> = [
        "to", "for", "at", "on", "in", "by", "with", "from", "around", "about", "into", "onto", "of", "over", "under", "near",
    ]

    private static let stopwords: Set<String> = determiners.union(prepositions).union([
        "and", "or", "but", "is", "are", "was", "were", "be", "it", "of",
    ])

    private static let weekdays: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "today", "tomorrow", "yesterday",
    ]

    private static let months: Set<String> = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    ]

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "half", "quarter", "dozen",
    ]

    private static let ordinalWords: Set<String> = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "eleventh", "twelfth", "last",
    ]

    private static let directionGroups: [Set<String>] = [
        ["left", "right", "center", "middle"],
        ["up", "down"],
        ["top", "bottom"],
        ["north", "south", "east", "west"],
        ["front", "back"],
        ["before", "after"],
        ["next", "previous", "prior", "last"],
        ["in", "out", "inside", "outside"],
        ["on", "off"],
        ["yes", "no"],
        ["true", "false"],
        ["more", "less", "fewer"],
        ["earlier", "later"],
        ["higher", "lower"],
        ["bigger", "smaller", "larger"],
        ["faster", "slower"],
        ["am", "pm"],
    ]

    /// Ordered longest/most-specific first so compound cues like
    /// "Oops, I'm sorry. No, let me rephrase." match as a single repair marker.
    private static let cueSpecs: [CueSpec] = {
        func compile(_ pattern: String, _ category: CueCategory) -> CueSpec {
            CueSpec(
                regex: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                category: category
            )
        }

        let apologeticPrefix = #"(?:(?:oops|whoops|sorry|i['’]m\s+sorry|my\s+bad|wait|no|actually)[,.;:!?\-—\s]+)*"#
        return [
            // Tier 1: Explicit sentence/clause reset cues
            compile(
                #"(?<=[\s,.;:!?\-—])"# + apologeticPrefix + #"(?:let\s+me\s+rephrase(?:\s+that)?|rephrase\s+that|let\s+me\s+start\s+over|start\s+over|scratch\s+that|forget\s+that|disregard\s+that)(?:[,.;:!?\-—]+\s*|\s+|$)"#,
                .sentenceReset
            ),
            compile(
                #"(?<=[\s,.;:!?\-—])(?:(?:oops|whoops|sorry|i['’]m\s+sorry)[,.;:!?\-—\s]+|(?:wait|no)[,.;:!?\-—]+\s*)correction(?:[,.;:!?\-—]+\s*|\s+)"#,
                .sentenceReset
            ),
            compile(
                #"(?<=[\s,.;:!?\-—])(?:never\s*mind)[,.;:!?\-—]+\s+"#,
                .sentenceReset
            ),

            // Tier 2/3: Compound apologetic inline repair cues (e.g. "Oops, I mean", "Oops, I'm sorry, actually")
            compile(
                #"(?<=[\s,.;:!?\-—])(?:oops|whoops)[,.;:!?\-—\s]+(?:(?:i['’]m\s+sorry|sorry|my\s+bad|no|wait|actually)[,.;:!?\-—\s]+)*(?:i\s+mean(?:t(?:\s+to\s+say)?)?|make\s+(?:it|that)|change\s+(?:it|that)\s+to|actually|no|wait)?[,.;:!?\-—\s]*"#,
                .inlineRepair
            ),
            compile(
                #"(?<=[\s,.;:!?\-—])(?:i['’]m\s+sorry|sorry|my\s+bad)[,.;:!?\-—\s]+(?:(?:no|wait|actually)[,.;:!?\-—\s]+)*(?:i\s+mean(?:t(?:\s+to\s+say)?)?|make\s+(?:it|that)|change\s+(?:it|that)\s+to|actually)[,.;:!?\-—\s]*"#,
                .inlineRepair
            ),
            compile(
                #"(?<=[\s,.;:!?\-—])(?:no|wait)[,.;:!?\-—\s]+(?:(?:no|wait|sorry|actually)[,.;:!?\-—\s]+)*(?:i\s+mean(?:t(?:\s+to\s+say)?)?|make\s+(?:it|that)|change\s+(?:it|that)\s+to)[,.;:!?\-—\s]*"#,
                .inlineRepair
            ),
            compile(
                #"(?<=[\s,.;:!?\-—])(?:no[,\s]+wait|wait[,\s]+no|no[,\s]+actually|actually[,\s]+no|actually[,\s]+wait|actually[,\s]+make\s+(?:it|that)|make\s+that|i\s+meant\s+to\s+say|i\s+meant|or\s+rather)(?:[,.;:!?\-—]+\s*|\s+)"#,
                .inlineRepair
            ),
            compile(
                #"(?<=[,.;:!?\-—]\s)(?:sorry|i\s+mean|actually)(?:[,.;:!?\-—]+\s+)"#,
                .inlineRepair
            ),
        ]
    }()

    public static func resolve(_ raw: String) -> SelfCorrectionResolution {
        var current = collapseWhitespace(raw)
        guard !current.isEmpty else {
            return SelfCorrectionResolution(text: "", kind: .none, appliedCount: 0, needsLLMEscalation: false)
        }

        var appliedCount = 0
        var lastKind: SelfCorrectionKind = .none
        var needsLLM = false

        for _ in 0..<4 {
            guard let match = findFirstCue(in: current) else { break }

            let ns = current as NSString
            let beforeRaw = ns.substring(to: match.range.location)
            let afterRaw = ns.substring(from: match.range.location + match.range.length)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ",;:—-")))

            // Must have real preceding content to be a mid-utterance self-correction.
            let beforeTrimmed = beforeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !beforeTrimmed.isEmpty else { break }

            let (earlierSentences, currentSentence, beforeTrailingPunct) = splitCurrentSentence(from: beforeRaw)
            guard !currentSentence.isEmpty else { break }

            switch match.category {
            case .sentenceReset:
                let replacement = afterRaw.isEmpty ? "" : capitalizeFirstIfNeeded(afterRaw)
                let rebuilt = joinSentences(earlier: earlierSentences, current: replacement)
                current = collapseWhitespace(rebuilt)
                appliedCount += 1
                lastKind = .sentenceReset

            case .inlineRepair:
                guard !afterRaw.isEmpty else {
                    // Bare trailing "oops" / "sorry" with nothing after — don't mutate aggressively.
                    needsLLM = true
                    return SelfCorrectionResolution(
                        text: current,
                        kind: appliedCount > 0 ? lastKind : .ambiguousNeedsLLM,
                        appliedCount: appliedCount,
                        needsLLMEscalation: true
                    )
                }

                let (leadingClause, trailingRemainder) = splitLeadingClause(from: afterRaw)

                // 1. Try Typed Slot Swap first for short typed values (numbers, currency, times, weekdays, months, ordinals, directions)
                if let swapped = tryTypedSlotSwap(
                    currentSentence: currentSentence,
                    replacementClause: leadingClause,
                    preservePunctuation: beforeTrailingPunct
                ) {
                    let combinedCurrent = appendRemainder(swapped, trailingRemainder)
                    current = collapseWhitespace(joinSentences(earlier: earlierSentences, current: combinedCurrent))
                    appliedCount += 1
                    lastKind = .typedSlotSwap
                    continue
                }

                // 2. Try Anchor-Overlap Phrase Splice (e.g. "this page to the right. Oops, I mean the page to the left.")
                if let spliced = tryAnchorSplice(
                    currentSentence: currentSentence,
                    replacementClause: leadingClause,
                    preservePunctuation: beforeTrailingPunct
                ) {
                    let combinedCurrent = appendRemainder(spliced, trailingRemainder)
                    current = collapseWhitespace(joinSentences(earlier: earlierSentences, current: combinedCurrent))
                    appliedCount += 1
                    lastKind = .anchorSplice
                    continue
                }

                // 3. Ambiguous semantic rewrite (no lexical anchor or typed slot match)
                // Flag for Smart Hybrid LLM escalation, while providing a clean best-effort zero-LLM text.
                let fallbackReplacement = capitalizeFirstIfNeeded(afterRaw)
                let bestEffort: String
                if isStandaloneClause(leadingClause) {
                    bestEffort = collapseWhitespace(joinSentences(earlier: earlierSentences, current: fallbackReplacement))
                } else {
                    // Keep original without mutating unpredictably, just flag for LLM.
                    bestEffort = current
                }
                return SelfCorrectionResolution(
                    text: bestEffort,
                    kind: .ambiguousNeedsLLM,
                    appliedCount: appliedCount,
                    needsLLMEscalation: true
                )
            }
        }

        return SelfCorrectionResolution(
            text: current,
            kind: lastKind,
            appliedCount: appliedCount,
            needsLLMEscalation: needsLLM
        )
    }

    // MARK: - Cue Discovery

    private static func findFirstCue(in text: String) -> CueMatch? {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        var best: CueMatch?
        for spec in cueSpecs {
            guard let match = spec.regex.firstMatch(in: text, options: [], range: fullRange) else {
                continue
            }
            guard match.range.location > 0 else { continue }
            if let existing = best {
                if match.range.location < existing.range.location
                    || (match.range.location == existing.range.location && match.range.length > existing.range.length)
                {
                    best = CueMatch(range: match.range, category: spec.category)
                }
            } else {
                best = CueMatch(range: match.range, category: spec.category)
            }
        }
        return best
    }

    // MARK: - Sentence & Clause Splitting

    /// Splits `before` into `(earlierSentences, currentSentence, trailingPunctuation)`.
    /// Crucially strips a single trailing `.` / `!` / `?` right before the cue so
    /// `"Let's look at this page to the right. Oops, I mean ..."` targets `"Let's look at this page to the right"`.
    private static func splitCurrentSentence(from before: String) -> (String, String, String) {
        var trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        var trailingPunct = ""
        if let last = trimmed.last, ".!?".contains(last) {
            trailingPunct = String(last)
            trimmed.removeLast()
        } else {
            while let last = trimmed.last, ",;:-—".contains(last) {
                trimmed.removeLast()
            }
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "", trailingPunct) }

        // Find the last sentence break inside `trimmed`
        let ns = trimmed as NSString
        var boundaryEnd: Int?
        if let regex = try? NSRegularExpression(pattern: #"[.!?]\s+"#, options: []) {
            let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
            if let last = matches.last {
                boundaryEnd = last.range.location + last.range.length
            }
        }
        if let boundaryEnd {
            let earlier = ns.substring(to: boundaryEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            let current = ns.substring(from: boundaryEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            return (earlier, current, trailingPunct)
        }
        return ("", trimmed, trailingPunct)
    }

    private static func splitLeadingClause(from after: String) -> (String, String) {
        let trimmed = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = trimmed as NSString
        if let regex = try? NSRegularExpression(pattern: #"[.!?](?:\s+|$)"#, options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
        {
            let clauseEnd = match.range.location + 1
            let leading = ns.substring(to: clauseEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = ns.substring(from: match.range.location + match.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
            return (leading, rest)
        }
        return (trimmed, "")
    }

    // MARK: - Tier 2: Anchor-Overlap Phrase Splice

    private static func tryAnchorSplice(
        currentSentence: String,
        replacementClause: String,
        preservePunctuation: String
    ) -> String? {
        let baseTokens = tokenize(currentSentence)
        let repTokens = tokenize(replacementClause)
        guard !baseTokens.isEmpty, !repTokens.isEmpty else { return nil }
        guard repTokens.count <= baseTokens.count + 2 else { return nil }

        let repTrailingPunct = trailingSentencePunctuation(of: replacementClause)
        let finalPunct = repTrailingPunct.isEmpty ? preservePunctuation : repTrailingPunct

        var bestIndex: Int?
        var bestScore: Double = 0

        // Search candidate suffix start indices in `baseTokens`
        let minStart = max(0, baseTokens.count - (repTokens.count + 3))
        for startIdx in minStart..<baseTokens.count {
            let suffix = Array(baseTokens[startIdx...])
            let score = alignmentScore(suffix: suffix, replacement: repTokens)
            if score > bestScore {
                bestScore = score
                bestIndex = startIdx
            }
        }

        guard let spliceIndex = bestIndex, bestScore >= 1.6 else { return nil }

        let ns = currentSentence as NSString
        let prefix: String
        if spliceIndex == 0 {
            prefix = ""
        } else {
            let cutOffset = baseTokens[spliceIndex].range.location
            prefix = ns.substring(to: cutOffset).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let cleanedRep = stripTrailingSentencePunctuation(replacementClause)
        let adjustedRep: String
        if prefix.isEmpty {
            adjustedRep = capitalizeFirstIfNeeded(cleanedRep)
        } else {
            // Lowercase leading word of replacement if ASR capitalized it after a period (e.g. "Oops, I mean The page...")
            // unless it is "I" or an acronym/proper noun that was also capitalized inside the sentence.
            adjustedRep = adjustCasingForMidSentence(cleanedRep, originalLead: baseTokens[spliceIndex].text)
        }

        let joined = prefix.isEmpty ? adjustedRep : "\(prefix) \(adjustedRep)"
        return finalPunct.isEmpty ? joined : "\(joined)\(finalPunct)"
    }

    private static func alignmentScore(suffix: [WordToken], replacement: [WordToken]) -> Double {
        let m = suffix.count
        let n = replacement.count
        guard m > 0, n > 0 else { return 0 }

        // Require reasonable length similarity between replaced span and replacement span
        let lengthDiff = abs(m - n)
        if lengthDiff > 2 { return 0 }
        if max(m, n) >= 3 && Double(min(m, n)) / Double(max(m, n)) < 0.55 {
            return 0
        }

        // Single-word replacement belongs to Tier 3 (Typed Slot Swap)
        if n == 1 {
            return 0
        }

        var score: Double = 0
        var matchedPositions = 0
        var matchedContentWords = 0

        // 1. Lead-in structural match (exact word, determiner equivalence, or preposition equivalence)
        let s0 = suffix[0].cleanedLower
        let r0 = replacement[0].cleanedLower
        if s0 == r0 {
            score += 1.4
            matchedPositions += 1
            if !stopwords.contains(s0) { matchedContentWords += 1 }
        } else if determiners.contains(s0) && determiners.contains(r0) {
            score += 1.2
            matchedPositions += 1
        } else if prepositions.contains(s0) && prepositions.contains(r0) {
            score += 1.0
            matchedPositions += 1
        }

        // 2. Shared vocabulary across the two spans (excluding already-counted index 0)
        let suffixBag = Set(suffix.dropFirst().map(\.cleanedLower))
        let repTail = replacement.dropFirst()
        for token in repTail {
            if suffixBag.contains(token.cleanedLower) {
                matchedPositions += 1
                if stopwords.contains(token.cleanedLower) {
                    score += 0.45
                } else {
                    score += 1.0
                    matchedContentWords += 1
                }
            }
        }

        // 3. Bonus if the tail tokens belong to the same semantic slot type (e.g. "right" vs "left", "30" vs "45")
        if let sLast = suffix.last, let rLast = replacement.last,
           let sType = classifyToken(sLast), let rType = classifyToken(rLast), sType == rType
        {
            score += 0.9
        }

        // 4. Penalty for length mismatch
        score -= Double(lengthDiff) * 0.35

        // Safety gate:
        // - For 2-word spans ("the store" -> "the house", "to Bob" -> "to Alice", "red folder" -> "blue folder"),
        //   require exact/determiner lead match OR shared content word, AND exact length match.
        if n == 2 {
            guard m == 2 else { return 0 }
            let leadMatched = (s0 == r0) || (determiners.contains(s0) && determiners.contains(r0))
            let tailSameWord = suffix[1].cleanedLower == replacement[1].cleanedLower && !stopwords.contains(replacement[1].cleanedLower)
            if leadMatched || tailSameWord {
                return max(score, 1.7)
            }
            return 0
        }

        // For 3+ word spans, require at least one shared content word OR strong structural overlap
        let overlapRatio = Double(matchedPositions) / Double(max(m, n))
        guard matchedContentWords >= 1 || overlapRatio >= 0.6 else { return 0 }
        return score
    }

    // MARK: - Tier 3: Typed Slot Swap

    private static func tryTypedSlotSwap(
        currentSentence: String,
        replacementClause: String,
        preservePunctuation: String
    ) -> String? {
        let repCleaned = stripTrailingSentencePunctuation(replacementClause)
        let repTokens = tokenize(repCleaned)
        guard !repTokens.isEmpty, repTokens.count <= 2 else { return nil }

        guard let repSlot = classifySpan(repTokens) else { return nil }

        let baseTokens = tokenize(currentSentence)
        guard !baseTokens.isEmpty else { return nil }

        let repTrailingPunct = trailingSentencePunctuation(of: replacementClause)
        let finalPunct = repTrailingPunct.isEmpty ? preservePunctuation : repTrailingPunct

        // Scan backward in `currentSentence` for the most recent 2-token or 1-token span of the same slot type.
        var targetRange: NSRange?
        var idx = baseTokens.count - 1
        while idx >= 0 {
            if idx >= 1 {
                let pair = [baseTokens[idx - 1], baseTokens[idx]]
                if let pairSlot = classifySpan(pair), pairSlot == repSlot {
                    let start = pair[0].range.location
                    let end = pair[1].range.location + pair[1].range.length
                    targetRange = NSRange(location: start, length: end - start)
                    break
                }
            }
            if let singleSlot = classifyToken(baseTokens[idx]), singleSlot == repSlot {
                targetRange = baseTokens[idx].range
                break
            }
            idx -= 1
        }

        guard let replaceRange = targetRange else { return nil }

        let ns = currentSentence as NSString
        let originalSpan = ns.substring(with: replaceRange)
        let originalTrailingPunct = trailingPunctuationOnly(of: originalSpan)
        let effectiveReplacement: String
        if replaceRange.location == 0 {
            effectiveReplacement = capitalizeFirstIfNeeded(repCleaned)
        } else {
            effectiveReplacement = adjustCasingForMidSentence(repCleaned, originalLead: originalSpan)
        }

        let updated = ns.replacingCharacters(in: replaceRange, with: effectiveReplacement + originalTrailingPunct)
        let trimmedUpdated = stripTrailingSentencePunctuation(updated)
        return finalPunct.isEmpty ? trimmedUpdated : "\(trimmedUpdated)\(finalPunct)"
    }

    private static func classifySpan(_ tokens: [WordToken]) -> SlotType? {
        if tokens.count == 1 {
            return classifyToken(tokens[0])
        }
        if tokens.count == 2 {
            let first = tokens[0].cleanedLower
            let second = tokens[1].cleanedLower
            // e.g. "4 pm", "3:30 am"
            if (isNumericString(first) || isClockTime(first)) && (second == "am" || second == "pm" || second == "a.m" || second == "p.m") {
                return .time
            }
            // e.g. "50 dollars", "20 bucks"
            if isNumericString(first) && ["dollar", "dollars", "buck", "bucks", "euro", "euros", "pound", "pounds", "cent", "cents"].contains(second) {
                return .currency
            }
            // e.g. "45 seconds", "10 minutes" — if second word is a unit, only classify as number if we shouldn't drop units;
            // actually handled better by anchor splice when both have units, or number-only replacement when rep has 1 token!
        }
        return nil
    }

    private static func classifyToken(_ token: WordToken) -> SlotType? {
        let raw = token.lower.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]"))
        guard !raw.isEmpty else { return nil }

        if raw.hasPrefix("$") || raw.hasPrefix("€") || raw.hasPrefix("£") {
            let remainder = String(raw.dropFirst())
            if isNumericString(remainder) { return .currency }
        }
        if isClockTime(raw) || raw == "noon" || raw == "midnight" {
            return .time
        }
        if isOrdinalString(raw) || ordinalWords.contains(raw) {
            return .ordinal
        }
        if isNumericString(raw) || numberWords.contains(raw) {
            return .number
        }
        if weekdays.contains(raw) {
            return .weekday
        }
        if months.contains(raw) {
            return .month
        }
        for (groupIndex, group) in directionGroups.enumerated() {
            if group.contains(raw) {
                return .direction(groupIndex)
            }
        }
        return nil
    }

    private static func isNumericString(_ s: String) -> Bool {
        let stripped = s.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard !stripped.isEmpty else { return false }
        return Double(stripped) != nil
    }

    private static func isClockTime(_ s: String) -> Bool {
        let pattern = #"^\d{1,2}(?::\d{2})?(?:am|pm)$|^\d{1,2}:\d{2}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isOrdinalString(_ s: String) -> Bool {
        let pattern = #"^\d+(?:st|nd|rd|th)$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Helpers

    private static func tokenize(_ text: String) -> [WordToken] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#, options: []) else { return [] }
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { match in
            let raw = ns.substring(with: match.range)
            let lower = raw.lowercased()
            let cleaned = lower.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            return WordToken(text: raw, lower: lower, cleanedLower: cleaned, range: match.range)
        }
    }

    private static func isStandaloneClause(_ clause: String) -> Bool {
        let words = tokenize(clause)
        return words.count >= 4
    }

    private static func joinSentences(earlier: String, current: String) -> String {
        let e = earlier.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty { return c }
        if c.isEmpty { return e }
        return "\(e) \(c)"
    }

    private static func appendRemainder(_ base: String, _ remainder: String) -> String {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return b }
        if b.isEmpty { return r }
        return "\(b) \(r)"
    }

    private static func trailingSentencePunctuation(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, ".!?".contains(last) else { return "" }
        return String(last)
    }

    private static func trailingPunctuationOnly(of text: String) -> String {
        var result = ""
        for ch in text.reversed() {
            if ",.;:!?".contains(ch) {
                result.insert(ch, at: result.startIndex)
            } else {
                break
            }
        }
        return result
    }

    private static func stripTrailingSentencePunctuation(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last, ".!?".contains(last) {
            trimmed.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeFirstIfNeeded(_ text: String) -> String {
        guard let first = text.first else { return text }
        if first.isLowercase {
            return first.uppercased() + text.dropFirst()
        }
        return text
    }

    private static func adjustCasingForMidSentence(_ replacement: String, originalLead: String) -> String {
        guard let firstChar = replacement.first, firstChar.isUppercase else { return replacement }
        // Preserve capitalization if the original replaced token was capitalized (proper noun / sentence start)
        if let origFirst = originalLead.first, origFirst.isUppercase {
            return replacement
        }
        // Preserve "I", "I'm", acronyms (all caps >= 2), weekdays/months
        let firstWord = replacement.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? replacement
        let cleaned = firstWord.trimmingCharacters(in: .punctuationCharacters)
        if cleaned == "I" || cleaned.hasPrefix("I'") || cleaned.hasPrefix("I’") {
            return replacement
        }
        if cleaned.count >= 2 && cleaned == cleaned.uppercased() && cleaned.rangeOfCharacter(from: .letters) != nil {
            return replacement
        }
        let lowerFirst = cleaned.lowercased()
        if weekdays.contains(lowerFirst) || months.contains(lowerFirst) {
            return replacement
        }
        return firstChar.lowercased() + replacement.dropFirst()
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+([,.;:!?])"#, with: "$1", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
