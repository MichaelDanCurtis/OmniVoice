using System.Text.Json;

namespace OmniVoice.Core;

public sealed class PreferencesStore
{
    private readonly string _path;

    public PreferencesStore(string? path = null)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var dir = Path.Combine(appData, "OmniSpeak");
        Directory.CreateDirectory(dir);
        _path = path ?? Path.Combine(dir, "preferences.json");
    }

    public OmniVoicePreferences Load()
    {
        if (!File.Exists(_path))
            return new OmniVoicePreferences();

        try
        {
            var json = File.ReadAllText(_path);
            return JsonSerializer.Deserialize<OmniVoicePreferences>(json, JsonOptions.Engine)
                   ?? new OmniVoicePreferences();
        }
        catch
        {
            return new OmniVoicePreferences();
        }
    }

    public void Save(OmniVoicePreferences preferences)
    {
        var json = JsonSerializer.Serialize(preferences, JsonOptions.Engine);
        File.WriteAllText(_path, json);
    }

    public string? LegacyOpenAiCompatibleApiKey()
    {
        if (!File.Exists(_path))
            return null;

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(_path));
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                return null;

            foreach (var property in new[] { "open_ai_compatible_api_key", "openAiCompatibleApiKey", "openAICompatibleAPIKey" })
            {
                if (!document.RootElement.TryGetProperty(property, out var value) ||
                    value.ValueKind != JsonValueKind.String)
                    continue;

                var trimmed = value.GetString()?.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                    return trimmed;
            }
        }
        catch
        {
            return null;
        }

        return null;
    }
}