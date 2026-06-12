namespace OmniVoice.Core;

public enum AiHandoffTarget
{
    Claude,
    Codex,
    OpenRouter,
    OpenAi,
    Custom,
}

public static class AiHandoffTargetExtensions
{
    public static string DisplayName(this AiHandoffTarget target) => target switch
    {
        AiHandoffTarget.Claude => "Claude",
        AiHandoffTarget.Codex => "Codex",
        AiHandoffTarget.OpenRouter => "OpenRouter",
        AiHandoffTarget.OpenAi => "OpenAI",
        _ => "AI",
    };
}

public enum DictationCommandActionKind
{
    OpenApplication,
    ShowCommandPalette,
    UndoLastDictation,
    AiHandoff,
}

public sealed record DictationCommand(DictationCommandActionKind Kind, string DisplayText, string? AppName = null, AiHandoffTarget? AiTarget = null, string? AiPrompt = null);

public static class DictationCommandParser
{
    internal static readonly char[] CommandBoundaries =
        [' ', '\t', '\r', '\n', ',', '.', ':', ';', '!', '?'];

    public static DictationCommand? Parse(string text)
    {
        var trimmed = text.Trim();
        if (TryParseAiHandoff(trimmed, out var aiCommand))
            return aiCommand;

        if (!trimmed.StartsWith("command", StringComparison.OrdinalIgnoreCase))
            return null;

        var afterCommand = trimmed["command".Length..].Trim(CommandBoundaries);

        if (string.IsNullOrEmpty(afterCommand))
            return null;

        var body = afterCommand;
        foreach (var prefix in new[] { "please ", "let's ", "lets " })
        {
            if (body.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                body = body[prefix.Length..].Trim();
                break;
            }
        }

        var normalized = body.ToLowerInvariant();
        if (normalized is "show commands" or "show command palette" or "help" or "what can i say")
            return new DictationCommand(DictationCommandActionKind.ShowCommandPalette, "Showing commands");

        if (normalized is "undo last dictation" or "undo last insertion" or "undo that")
            return new DictationCommand(DictationCommandActionKind.UndoLastDictation, "Undoing last dictation");

        foreach (var verb in new[] { "open ", "launch ", "start " })
        {
            if (!body.StartsWith(verb, StringComparison.OrdinalIgnoreCase)) continue;
            var name = body[verb.Length..].Trim(CommandBoundaries);
            if (string.IsNullOrEmpty(name)) return null;
            return new DictationCommand(DictationCommandActionKind.OpenApplication, $"Opening {name}", name);
        }

        return null;
    }

    private static bool TryParseAiHandoff(string text, out DictationCommand? command)
    {
        command = null;
        if (string.IsNullOrEmpty(text)) return false;

        foreach (var target in Enum.GetValues<AiHandoffTarget>())
        {
            if (target == AiHandoffTarget.Custom) continue;
            foreach (var prefix in AiPrefixes(target))
            {
                if (!TryPromptAfter(prefix, text, out var prompt)) continue;
                command = new DictationCommand(
                    DictationCommandActionKind.AiHandoff,
                    $"Asking {target.DisplayName()}",
                    AiTarget: target,
                    AiPrompt: prompt);
                return true;
            }
        }

        foreach (var prefix in new[] { "ask ai", "hey ai", "have ai take a look", "have the ai take a look" })
        {
            if (!TryPromptAfter(prefix, text, out var prompt)) continue;
            command = new DictationCommand(
                DictationCommandActionKind.AiHandoff,
                "Asking AI",
                AiTarget: AiHandoffTarget.Custom,
                AiPrompt: prompt);
            return true;
        }

        return false;
    }

    private static IEnumerable<string> AiPrefixes(AiHandoffTarget target) => target switch
    {
        AiHandoffTarget.Claude => ["ask claude", "hey claude", "have claude take a look"],
        AiHandoffTarget.Codex => ["ask codex", "hey codex", "have codex take a look"],
        AiHandoffTarget.OpenRouter => ["ask openrouter", "ask open router", "hey openrouter", "hey open router", "have openrouter take a look", "have open router take a look"],
        AiHandoffTarget.OpenAi => ["ask openai", "ask open ai", "hey openai", "hey open ai", "have openai take a look", "have open ai take a look"],
        _ => [],
    };

    private static bool TryPromptAfter(string prefix, string text, out string prompt)
    {
        prompt = "";
        if (!text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            return false;

        if (prefix.Length < text.Length)
        {
            var next = text[prefix.Length];
            if (!char.IsWhiteSpace(next) && !".,:;!?".Contains(next))
                return false;
        }

        prompt = text[prefix.Length..].Trim(CommandBoundaries);
        return !string.IsNullOrEmpty(prompt);
    }
}