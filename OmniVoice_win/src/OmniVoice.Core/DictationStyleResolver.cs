namespace OmniVoice.Core;

public static class DictationStyleResolver
{
    public static StyleProfile CleanupStyle(string? processName, StyleProfile preferredStyle)
    {
        if (preferredStyle != StyleProfile.Neutral)
            return preferredStyle;

        if (string.IsNullOrWhiteSpace(processName))
            return preferredStyle;

        var normalized = processName.Trim().ToLowerInvariant();

        if (normalized is "cmd" or "powershell" or "pwsh" or "windowsterminal" or "wt"
            or "devenv" or "code" or "cursor")
            return StyleProfile.Raw;

        if (normalized is "outlook")
            return StyleProfile.Professional;

        if (normalized is "slack" or "teams")
            return StyleProfile.Concise;

        return preferredStyle;
    }
}