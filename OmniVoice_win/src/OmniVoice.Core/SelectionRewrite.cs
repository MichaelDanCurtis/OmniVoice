namespace OmniVoice.Core;

public static class SelectionRewrite
{
    public static string? Rewrite(string selectedText, string instruction)
    {
        var trimmedSelection = selectedText.Trim();
        var normalized = instruction.Trim().TrimEnd('.', '!', '?').ToLowerInvariant();
        if (string.IsNullOrEmpty(trimmedSelection)) return null;

        if (normalized.Contains("bullet"))
            return Bulletize(trimmedSelection);

        if (normalized.Contains("shorter") || normalized.Contains("concise"))
            return SentenceParts(trimmedSelection).FirstOrDefault() ?? trimmedSelection;

        if (normalized.Contains("professional"))
            return Professionalize(trimmedSelection);

        if (normalized.Contains("warmer") || normalized.Contains("friendly"))
            return Warmer(trimmedSelection);

        foreach (var prefix in new[] { "reply politely that ", "reply that ", "respond politely that ", "respond that " })
        {
            if (!normalized.StartsWith(prefix)) continue;
            var content = normalized[prefix.Length..].Trim();
            if (string.IsNullOrEmpty(content)) return null;
            var capped = char.ToUpper(content[0]) + content[1..];
            return $"Thanks for the note. {capped}.";
        }

        return null;
    }

    private static string Bulletize(string text)
    {
        var parts = SentenceParts(text);
        return parts.Count == 0 ? $"- {text}" : string.Join("\n", parts.Select(p => $"- {p}"));
    }

    private static string Professionalize(string text)
    {
        var result = text
            .Replace("hey", "Hello", StringComparison.OrdinalIgnoreCase)
            .Replace("thanks", "Thank you", StringComparison.OrdinalIgnoreCase)
            .Trim();
        if (string.IsNullOrEmpty(result)) return result;
        return char.ToUpper(result[0]) + result[1..];
    }

    private static string Warmer(string text)
    {
        var result = text.Trim();
        if (string.IsNullOrEmpty(result)) return result;
        if (!result.Contains("thank", StringComparison.OrdinalIgnoreCase))
            result += result.EndsWith('.') ? " Thank you." : ". Thank you.";
        return result;
    }

    private static List<string> SentenceParts(string text) =>
        text.Split(['.', '!', '?'])
            .Select(s => s.Trim())
            .Where(s => !string.IsNullOrEmpty(s))
            .ToList();
}