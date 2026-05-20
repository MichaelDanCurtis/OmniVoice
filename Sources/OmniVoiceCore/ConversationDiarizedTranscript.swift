import Foundation

public struct ConversationDiarizedTranscriptLine: Equatable, Identifiable, Sendable {
    public let id: String
    public let sourceSegmentID: String
    public let speakerID: String
    public let speakerDisplayName: String
    public let startMs: Int
    public let endMs: Int?
    public let text: String

    public var timestampLabel: String {
        let totalSeconds = max(0, startMs / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

public extension ConversationSegment {
    var diarizedTranscriptLines: [ConversationDiarizedTranscriptLine] {
        ConversationDiarizedTranscriptBuilder.lines(for: self)
    }
}

public enum ConversationSpeakerTurnMerge {
    public static func merge(
        existing: [SpeakerTurn],
        preview: [SpeakerTurn],
        replacingStartMs: Int?,
        replacingEndMs: Int?
    ) -> [SpeakerTurn] {
        guard !preview.isEmpty else {
            return existing.sorted(by: turnSort)
        }

        let previewStart = preview.map(\.startMs).min() ?? 0
        let previewEnd = preview.map { $0.endMs ?? $0.startMs }.max() ?? previewStart
        let replacementStart = replacingStartMs ?? previewStart
        let replacementEnd = replacingEndMs ?? previewEnd

        let kept = existing.filter { turn in
            let turnEnd = turn.endMs ?? turn.startMs
            return turnEnd <= replacementStart || turn.startMs >= replacementEnd
        }

        return (kept + preview).sorted(by: turnSort)
    }

    private static func turnSort(_ lhs: SpeakerTurn, _ rhs: SpeakerTurn) -> Bool {
        if lhs.startMs != rhs.startMs {
            return lhs.startMs < rhs.startMs
        }
        return (lhs.endMs ?? lhs.startMs) < (rhs.endMs ?? rhs.startMs)
    }
}

public enum ConversationSpeakerLineMerge {
    public static func merge(
        existing: [ConversationSpeakerLine],
        preview: [ConversationSpeakerLine],
        replacingStartMs: Int?,
        replacingEndMs: Int?
    ) -> [ConversationSpeakerLine] {
        guard !preview.isEmpty else {
            return existing.sorted(by: lineSort)
        }

        let previewStart = preview.map(\.startMs).min() ?? 0
        let previewEnd = preview.map { $0.endMs ?? $0.startMs }.max() ?? previewStart
        let replacementStart = replacingStartMs ?? previewStart
        let replacementEnd = replacingEndMs ?? previewEnd

        let kept = existing.filter { line in
            let lineEnd = line.endMs ?? line.startMs
            return lineEnd <= replacementStart || line.startMs >= replacementEnd
        }

        return (kept + preview).sorted(by: lineSort)
    }

    private static func lineSort(_ lhs: ConversationSpeakerLine, _ rhs: ConversationSpeakerLine) -> Bool {
        if lhs.startMs != rhs.startMs {
            return lhs.startMs < rhs.startMs
        }
        return (lhs.endMs ?? lhs.startMs) < (rhs.endMs ?? rhs.startMs)
    }
}

public enum ConversationLiveSegmentWindow {
    public static func merge(
        existingStartMs: Int?,
        existingEndMs: Int?,
        incomingStartMs: Int,
        incomingEndMs: Int?,
        speakerTurns: [SpeakerTurn]
    ) -> (startMs: Int, endMs: Int?) {
        let turnStartMs = speakerTurns.map(\.startMs).min()
        let turnEndMs = speakerTurns.map { $0.endMs ?? $0.startMs }.max()
        let startMs = [existingStartMs, incomingStartMs, turnStartMs]
            .compactMap { $0 }
            .min() ?? incomingStartMs
        let endMs = [existingEndMs, incomingEndMs, turnEndMs]
            .compactMap { $0 }
            .max()

        return (startMs: startMs, endMs: endMs)
    }
}

private enum ConversationDiarizedTranscriptBuilder {
    private static let minimumTurnDurationMs = 250
    private static let mergeGapMs = 400
    private static let snapWindowWords = 4

    struct SpeakerInterval {
        var speakerID: String
        var startMs: Int
        var endMs: Int

        var durationMs: Int {
            max(0, endMs - startMs)
        }
    }

    static func lines(for segment: ConversationSegment) -> [ConversationDiarizedTranscriptLine] {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let backendLines = backendSpeakerLines(for: segment)
        let intervals = normalizedIntervals(for: segment)

        guard !text.isEmpty else {
            return backendLines.isEmpty ? [singleLine(for: segment, text: text)] : backendLines
        }

        if shouldUseBackendSpeakerLines(backendLines, intervals: intervals) {
            return backendLines
        }

        guard !intervals.isEmpty else {
            return [singleLine(for: segment, text: text)]
        }

        let uniqueSpeakers = Set(intervals.map(\.speakerID))
        if uniqueSpeakers.count <= 1 {
            return [
                line(
                    for: segment,
                    index: 0,
                    speakerID: intervals[0].speakerID,
                    startMs: intervals[0].startMs,
                    endMs: intervals.last?.endMs,
                    text: text
                )
            ]
        }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= intervals.count else {
            return proportionalLinesWithoutEmptyTurns(for: segment, intervals: intervals, words: words)
        }

        return proportionalLinesWithoutEmptyTurns(for: segment, intervals: intervals, words: words)
    }

    private static func backendSpeakerLines(for segment: ConversationSegment) -> [ConversationDiarizedTranscriptLine] {
        segment.speakerLines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.startMs != $1.startMs {
                    return $0.startMs < $1.startMs
                }
                return ($0.endMs ?? $0.startMs) < ($1.endMs ?? $1.startMs)
            }
            .enumerated()
            .map { index, speakerLine in
                line(
                    for: segment,
                    index: index,
                    speakerID: speakerLine.speakerID,
                    startMs: speakerLine.startMs,
                    endMs: speakerLine.endMs,
                    text: speakerLine.text
                )
            }
    }

    private static func shouldUseBackendSpeakerLines(
        _ backendLines: [ConversationDiarizedTranscriptLine],
        intervals: [SpeakerInterval]
    ) -> Bool {
        guard !backendLines.isEmpty else {
            return false
        }

        let expectedSpeakers = Set(intervals.map(\.speakerID))
        guard expectedSpeakers.count > 1 else {
            return true
        }

        let backendSpeakers = Set(backendLines.map(\.speakerID))
        return expectedSpeakers.isSubset(of: backendSpeakers)
    }

    private static func normalizedIntervals(for segment: ConversationSegment) -> [SpeakerInterval] {
        let segmentStart = segment.startMs
        let segmentEnd = segment.endMs ?? max(segment.startMs, segment.speakerTurns.map { $0.endMs ?? $0.startMs }.max() ?? segment.startMs)
        guard segmentEnd > segmentStart else { return [] }

        let sortedTurns = segment.speakerTurns
            .compactMap { turn -> SpeakerInterval? in
                let rawEnd = turn.endMs ?? turn.startMs
                let start = max(segmentStart, turn.startMs)
                let end = min(segmentEnd, rawEnd)
                guard end > start else { return nil }
                return SpeakerInterval(speakerID: turn.speakerID, startMs: start, endMs: end)
            }
            .filter { $0.durationMs >= minimumTurnDurationMs }
            .sorted {
                if $0.startMs != $1.startMs {
                    return $0.startMs < $1.startMs
                }
                return $0.durationMs > $1.durationMs
            }

        var nonOverlapping: [SpeakerInterval] = []
        var cursor = segmentStart
        for turn in sortedTurns {
            let start = max(turn.startMs, cursor)
            let end = turn.endMs
            guard end - start >= minimumTurnDurationMs else { continue }
            nonOverlapping.append(SpeakerInterval(speakerID: turn.speakerID, startMs: start, endMs: end))
            cursor = end
        }

        return mergeAdjacentIntervals(nonOverlapping)
    }

    private static func mergeAdjacentIntervals(_ intervals: [SpeakerInterval]) -> [SpeakerInterval] {
        var merged: [SpeakerInterval] = []
        for interval in intervals {
            if let last = merged.last,
               last.speakerID == interval.speakerID,
               interval.startMs - last.endMs <= mergeGapMs {
                merged[merged.count - 1] = SpeakerInterval(
                    speakerID: last.speakerID,
                    startMs: last.startMs,
                    endMs: max(last.endMs, interval.endMs)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func proportionalLinesWithoutEmptyTurns(
        for segment: ConversationSegment,
        intervals: [SpeakerInterval],
        words: [String]
    ) -> [ConversationDiarizedTranscriptLine] {
        guard !words.isEmpty else {
            return [singleLine(for: segment, text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        let totalDuration = max(1, intervals.reduce(0) { $0 + $1.durationMs })
        var cumulativeDuration = 0
        var wordStart = 0
        var rawLines: [ConversationDiarizedTranscriptLine] = []

        for (index, interval) in intervals.enumerated() {
            let remainingIntervals = intervals.count - index
            let wordEnd: Int
            if index == intervals.count - 1 {
                wordEnd = words.count
            } else {
                cumulativeDuration += interval.durationMs
                let target = Int((Double(cumulativeDuration) / Double(totalDuration) * Double(words.count)).rounded())
                let minimumEnd = min(words.count, wordStart + 1)
                let maximumEnd = max(minimumEnd, words.count - (remainingIntervals - 1))
                wordEnd = snappedWordEnd(
                    target: target,
                    lowerBound: wordStart,
                    minimumEnd: minimumEnd,
                    maximumEnd: maximumEnd,
                    words: words
                )
            }

            guard wordEnd > wordStart else { continue }
            let text = words[wordStart..<wordEnd].joined(separator: " ")
            rawLines.append(
                line(
                    for: segment,
                    index: rawLines.count,
                    speakerID: interval.speakerID,
                    startMs: interval.startMs,
                    endMs: interval.endMs,
                    text: text
                )
            )
            wordStart = wordEnd
        }

        return mergeAdjacentLines(rawLines)
    }

    private static func snappedWordEnd(
        target: Int,
        lowerBound: Int,
        minimumEnd: Int,
        maximumEnd: Int,
        words: [String]
    ) -> Int {
        let clamped = min(max(target, minimumEnd), maximumEnd)
        let forwardLimit = min(maximumEnd, clamped + snapWindowWords)
        if clamped <= forwardLimit {
            for candidate in clamped...forwardLimit where isSentenceBoundary(words[candidate - 1]) {
                return candidate
            }
        }

        let backwardLimit = max(minimumEnd, clamped - snapWindowWords, lowerBound + 1)
        if backwardLimit <= clamped {
            for candidate in stride(from: clamped, through: backwardLimit, by: -1) where isSentenceBoundary(words[candidate - 1]) {
                return candidate
            }
        }

        return clamped
    }

    private static func isSentenceBoundary(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".?!".contains(last)
    }

    private static func mergeAdjacentLines(_ lines: [ConversationDiarizedTranscriptLine]) -> [ConversationDiarizedTranscriptLine] {
        var merged: [ConversationDiarizedTranscriptLine] = []
        for line in lines where !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let last = merged.last, last.speakerID == line.speakerID {
                merged[merged.count - 1] = ConversationDiarizedTranscriptLine(
                    id: last.id,
                    sourceSegmentID: last.sourceSegmentID,
                    speakerID: last.speakerID,
                    speakerDisplayName: last.speakerDisplayName,
                    startMs: last.startMs,
                    endMs: line.endMs,
                    text: "\(last.text) \(line.text)"
                )
            } else {
                merged.append(line)
            }
        }
        return merged.isEmpty ? lines : merged
    }

    private static func singleLine(for segment: ConversationSegment, text: String) -> ConversationDiarizedTranscriptLine {
        ConversationDiarizedTranscriptLine(
            id: "\(segment.id)-line-0",
            sourceSegmentID: segment.id,
            speakerID: segment.speakerID,
            speakerDisplayName: segment.speakerDisplayName,
            startMs: segment.startMs,
            endMs: segment.endMs,
            text: text
        )
    }

    private static func line(
        for segment: ConversationSegment,
        index: Int,
        speakerID: String,
        startMs: Int,
        endMs: Int?,
        text: String
    ) -> ConversationDiarizedTranscriptLine {
        ConversationDiarizedTranscriptLine(
            id: "\(segment.id)-line-\(index)",
            sourceSegmentID: segment.id,
            speakerID: speakerID,
            speakerDisplayName: displayName(for: speakerID, segment: segment),
            startMs: startMs,
            endMs: endMs,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func displayName(for speakerID: String, segment: ConversationSegment) -> String {
        if speakerID == segment.speakerID {
            return segment.speakerDisplayName
        }
        let suffix = speakerID.replacingOccurrences(of: "speaker-", with: "")
        if Int(suffix) != nil {
            return "Speaker \(suffix)"
        }
        return speakerID.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
