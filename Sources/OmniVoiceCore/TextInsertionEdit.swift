import Foundation

public struct TextInsertionEdit: Equatable, Sendable {
    private static let knownPlaceholderValues = [
        "Ask for follow-up changes",
        "Type / for commands",
        "Type slash for commands",
    ]

    public let text: String
    public let cursorLocation: Int
    public let ignoredPlaceholder: Bool

    public static func make(
        currentValue: String,
        selectedRange: NSRange,
        insertion: String,
        placeholderValues: [String]
    ) -> TextInsertionEdit? {
        let isPlaceholderOnlyValue = Self.isPlaceholderOnlyValue(
            currentValue,
            placeholderValues: placeholderValues
        )
        let sourceValue = isPlaceholderOnlyValue ? "" : currentValue
        let replacementRange = isPlaceholderOnlyValue ? NSRange(location: 0, length: 0) : selectedRange
        let sanitizedInsertion = Self.sanitizedInsertionText(insertion, placeholderValues: placeholderValues)
        let nsValue = sourceValue as NSString

        guard replacementRange.location >= 0,
              replacementRange.length >= 0,
              replacementRange.location <= nsValue.length,
              replacementRange.location + replacementRange.length <= nsValue.length else {
            return nil
        }

        let updated = nsValue.replacingCharacters(in: replacementRange, with: sanitizedInsertion)
        return TextInsertionEdit(
            text: updated,
            cursorLocation: replacementRange.location + (sanitizedInsertion as NSString).length,
            ignoredPlaceholder: isPlaceholderOnlyValue
        )
    }

    public static func restoredPreviousValue(
        currentValue: String,
        insertedValue: String,
        previousValue: String
    ) -> String? {
        guard currentValue == insertedValue else { return nil }
        return previousValue
    }

    public static func sanitizedInsertionText(_ text: String) -> String {
        sanitizedInsertionText(text, placeholderValues: [])
    }

    private static func sanitizedInsertionText(_ text: String, placeholderValues: [String]) -> String {
        (placeholderValues + knownPlaceholderValues).reduce(text.trimmingCharacters(in: .whitespacesAndNewlines)) { result, placeholder in
            removingTrailingPlaceholder(placeholder, from: result)
        }
    }

    private static func isPlaceholderOnlyValue(_ value: String, placeholderValues: [String]) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = placeholderValues + knownPlaceholderValues
        return candidates.contains { placeholderValue in
            let normalizedPlaceholder = placeholderValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedPlaceholder.isEmpty && normalizedValue.caseInsensitiveCompare(normalizedPlaceholder) == .orderedSame
        }
    }

    private static func removingTrailingPlaceholder(_ placeholder: String, from text: String) -> String {
        let suffixCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?\"'”’"))
        let trimmed = text.trimmingCharacters(in: suffixCharacters)

        guard let range = trimmed.range(of: placeholder, options: [.caseInsensitive, .anchored, .backwards]) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
