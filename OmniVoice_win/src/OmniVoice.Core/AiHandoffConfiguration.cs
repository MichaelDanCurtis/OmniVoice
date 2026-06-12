using System.Text.Json.Serialization;

namespace OmniVoice.Core;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum AiProviderPresetId
{
    [JsonPropertyName("custom")]
    Custom,

    [JsonPropertyName("openrouter")]
    OpenRouter,

    [JsonPropertyName("lm_studio")]
    LmStudio,

    [JsonPropertyName("ollama")]
    Ollama,
}

public sealed record AiProviderPreset(
    AiProviderPresetId Id,
    string Name,
    [property: JsonPropertyName("base_url")] string BaseUrl,
    [property: JsonPropertyName("default_model")] string DefaultModel = "",
    [property: JsonPropertyName("requires_api_key")] bool RequiresApiKey = false)
{
    public static IReadOnlyList<AiProviderPreset> BuiltIn { get; } =
    [
        new(AiProviderPresetId.OpenRouter, "OpenRouter", "https://openrouter.ai/api/v1", RequiresApiKey: true),
        new(AiProviderPresetId.LmStudio, "LM Studio", "http://127.0.0.1:1234/v1"),
        new(AiProviderPresetId.Ollama, "Ollama", "http://127.0.0.1:11434/v1"),
        new(AiProviderPresetId.Custom, "Custom", ""),
    ];

    public static AiProviderPreset? For(AiProviderPresetId id) =>
        BuiltIn.FirstOrDefault(p => p.Id == id);
}

public static class AiProviderPresetIdExtensions
{
    public static string WireValue(this AiProviderPresetId id) => id switch
    {
        AiProviderPresetId.OpenRouter => "openrouter",
        AiProviderPresetId.LmStudio => "lm_studio",
        AiProviderPresetId.Ollama => "ollama",
        _ => "custom",
    };
}

public sealed record PendingAiHandoffCommand(
    AiHandoffTarget Target,
    string Prompt,
    string Context,
    [property: JsonPropertyName("original_text")] string OriginalText)
{
    public string Provider => Target switch
    {
        AiHandoffTarget.Claude => "claude",
        AiHandoffTarget.Codex => "codex",
        AiHandoffTarget.OpenRouter => "openrouter",
        AiHandoffTarget.OpenAi => "openai",
        _ => "custom",
    };
}