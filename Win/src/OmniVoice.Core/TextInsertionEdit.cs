namespace OmniVoice.Core;

public sealed record TextInsertionEdit(string Text, int CursorLocation, bool IgnoredPlaceholder)
{
    private static readonly string[] KnownPlaceholderValues =
    [
        "Ask for follow-up changes",
        "Type / for commands",
        "Type slash for commands",
    ];

    public static TextInsertionEdit? Make(
        string currentValue,
        int selectionStart,
        int selectionLength,
        string insertion,
        IReadOnlyList<string> placeholderValues)
    {
        var isPlaceholderOnly = IsPlaceholderOnlyValue(currentValue, placeholderValues);
        var sourceValue = isPlaceholderOnly ? "" : currentValue;
        var start = isPlaceholderOnly ? 0 : selectionStart;
        var length = isPlaceholderOnly ? 0 : selectionLength;
        var sanitized = SanitizedInsertionText(insertion, placeholderValues);

        if (start < 0 || length < 0 || start > sourceValue.Length || start + length > sourceValue.Length)
            return null;

        var updated = sourceValue[..start] + sanitized + sourceValue[(start + length)..];
        return new TextInsertionEdit(updated, start + sanitized.Length, isPlaceholderOnly);
    }

    public static string SanitizedInsertionText(string text) =>
        SanitizedInsertionText(text, []);

    private static string SanitizedInsertionText(string text, IReadOnlyList<string> placeholderValues)
    {
        var result = text.Trim();
        foreach (var placeholder in placeholderValues.Concat(KnownPlaceholderValues))
            result = RemovingTrailingPlaceholder(placeholder, result);
        return result;
    }

    private static bool IsPlaceholderOnlyValue(string value, IReadOnlyList<string> placeholderValues)
    {
        var normalized = value.Trim();
        return placeholderValues.Concat(KnownPlaceholderValues).Any(p =>
        {
            var ph = p.Trim();
            return !string.IsNullOrEmpty(ph) &&
                   string.Equals(normalized, ph, StringComparison.OrdinalIgnoreCase);
        });
    }

    private static string RemovingTrailingPlaceholder(string placeholder, string text)
    {
        var trimmed = text.Trim().TrimEnd('.', '!', '?', '"', '\'', '”', '’', ' ');
        if (!trimmed.EndsWith(placeholder, StringComparison.OrdinalIgnoreCase))
            return text.Trim();

        var index = trimmed.LastIndexOf(placeholder, StringComparison.OrdinalIgnoreCase);
        if (index < 0) return text.Trim();
        return trimmed[..index].Trim();
    }
}