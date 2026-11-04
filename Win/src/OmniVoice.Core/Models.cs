using System.Text.Json.Serialization;

namespace OmniVoice.Core;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum StyleProfile
{
    Neutral,
    Professional,
    Concise,
    Expanded,
    Raw,
}

public static class StyleProfileExtensions
{
    public static string DisplayName(this StyleProfile style) => style switch
    {
        StyleProfile.Neutral => "Neutral",
        StyleProfile.Professional => "Professional",
        StyleProfile.Concise => "Concise",
        StyleProfile.Expanded => "Expanded",
        StyleProfile.Raw => "Raw Dictation",
        _ => style.ToString(),
    };

    public static StyleProfile Next(this StyleProfile style)
    {
        var values = Enum.GetValues<StyleProfile>();
        var index = Array.IndexOf(values, style);
        return values[(index + 1) % values.Length];
    }
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum AsrProviderKind
{
    [JsonPropertyName("fake")]
    Fake,

    [JsonPropertyName("parakeet-tdt")]
    ParakeetTdt,

    [JsonPropertyName("sensevoice-small-funasr")]
    SenseVoiceSmallFunAsr,

    [JsonPropertyName("canary-qwen-2.5b")]
    CanaryQwen25B,
}

public sealed record ModelCapabilityProfile(
    string PrimaryUse,
    string LanguageCoverage,
    string AutoDetectBehavior,
    string LanguagePickerBehavior,
    string DataPath,
    string Setup,
    string Limitation,
    IReadOnlyList<string> Pills,
    bool SupportsSourceLanguagePicker,
    bool IsTestOnly = false);

public static class AsrProviderKindExtensions
{
    public static string DisplayName(this AsrProviderKind provider) => provider switch
    {
        AsrProviderKind.Fake => "Fake",
        AsrProviderKind.ParakeetTdt => "Parakeet TDT",
        AsrProviderKind.SenseVoiceSmallFunAsr => "SenseVoice Small FunASR",
        AsrProviderKind.CanaryQwen25B => "Canary Qwen 2.5B",
        _ => provider.ToString(),
    };

    public static string WireValue(this AsrProviderKind provider) => provider switch
    {
        AsrProviderKind.Fake => "fake",
        AsrProviderKind.ParakeetTdt => "parakeet-tdt",
        AsrProviderKind.SenseVoiceSmallFunAsr => "sensevoice-small-funasr",
        AsrProviderKind.CanaryQwen25B => "canary-qwen-2.5b",
        _ => provider.ToString().ToLowerInvariant(),
    };

    public static ModelCapabilityProfile CapabilityProfile(this AsrProviderKind provider) => provider switch
    {
        AsrProviderKind.ParakeetTdt => new(
            PrimaryUse: "Fast local dictation",
            LanguageCoverage: "English speech input",
            AutoDetectBehavior: "No language detection; optimized for English.",
            LanguagePickerBehavior: "Source language is fixed to English. Translation target can still be changed.",
            DataPath: "Microphone -> local ASR -> cleanup/translation -> text insertion.",
            Setup: "Best default for day-to-day push-to-talk dictation.",
            Limitation: "Use a multilingual ASR model when the spoken input is not English.",
            Pills: ["Fastest", "Local", "Best default"],
            SupportsSourceLanguagePicker: false),

        AsrProviderKind.SenseVoiceSmallFunAsr => new(
            PrimaryUse: "Fast multilingual dictation",
            LanguageCoverage: "Mandarin, Cantonese, English, Japanese, and Korean-focused speech input",
            AutoDetectBehavior: "FunASR/SenseVoice language identification can infer supported source languages.",
            LanguagePickerBehavior: "Source language can be automatic or manually selected for supported languages.",
            DataPath: "Microphone -> local FunASR/SenseVoice -> cleanup/translation -> text insertion.",
            Setup: "Download SenseVoiceSmall from Hugging Face and install the optional FunASR runtime.",
            Limitation: "Not MLX-native; Windows performance depends on local CPU/GPU Torch runtime.",
            Pills: ["Fast", "FunASR", "CJK-ready"],
            SupportsSourceLanguagePicker: true),

        AsrProviderKind.CanaryQwen25B => new(
            PrimaryUse: "Multilingual transcription",
            LanguageCoverage: "Multilingual speech input with automatic language support from the model runtime.",
            AutoDetectBehavior: "Model runtime can infer supported source languages.",
            LanguagePickerBehavior: "Source language may be automatic or manually selected when the runtime exposes supported languages.",
            DataPath: "Microphone -> local ASR -> cleanup/translation -> text insertion.",
            Setup: "Good fallback when the speaker may not be using English.",
            Limitation: "Higher latency and heavier resource use than Parakeet.",
            Pills: ["Multilingual", "Translation-ready", "Heavier"],
            SupportsSourceLanguagePicker: true),

        _ => new(
            PrimaryUse: "Testing only",
            LanguageCoverage: "Synthetic English output",
            AutoDetectBehavior: "No real speech recognition.",
            LanguagePickerBehavior: "Not available.",
            DataPath: "Local test stub -> text insertion.",
            Setup: "Used by development tests and diagnostics.",
            Limitation: "This provider is for testing and should not appear as a normal user-facing model.",
            Pills: ["Test only"],
            SupportsSourceLanguagePicker: false,
            IsTestOnly: true),
    };
}

[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Windows = 8,
}

public sealed record HotkeyBinding(int VirtualKey, HotkeyModifiers Modifiers)
{
    public const int ModifierOnlyVirtualKey = -1;

    public static HotkeyBinding DefaultDictation => new(0x20, HotkeyModifiers.Control | HotkeyModifiers.Alt);
    public static HotkeyBinding DefaultStyle => new(0x53, HotkeyModifiers.Control | HotkeyModifiers.Alt);

    public bool IsModifierOnly => VirtualKey == ModifierOnlyVirtualKey;

    public string DisplayName =>
        IsModifierOnly
            ? ModifierDisplayName(Modifiers)
            : $"{ModifierDisplayName(Modifiers)}{KeyDisplayName(VirtualKey)}";

    public static string ModifierDisplayName(HotkeyModifiers modifiers)
    {
        var parts = new List<string>();
        if (modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
        if (modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
        if (modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
        if (modifiers.HasFlag(HotkeyModifiers.Windows)) parts.Add("Win");
        return string.Join("+", parts);
    }

    private static string KeyDisplayName(int virtualKey) => virtualKey switch
    {
        0x20 => "Space",
        0x0D => "Enter",
        0x09 => "Tab",
        0x08 => "Backspace",
        0x1B => "Esc",
        >= 0x30 and <= 0x39 => ((char)virtualKey).ToString(),
        >= 0x41 and <= 0x5A => ((char)virtualKey).ToString(),
        _ => $"VK{virtualKey:X}",
    };
}

public sealed record TranscriptUpdate(string Text, bool IsFinal);

public sealed record CleanupRequest(
    [property: JsonPropertyName("raw_transcript")] string RawTranscript,
    StyleProfile Style,
    [property: JsonPropertyName("dictionary_terms")] IReadOnlyList<string> DictionaryTerms);

public sealed record CleanupResult(string Text, [property: JsonPropertyName("cleanup_applied")] bool CleanupApplied);

public sealed record TranscribeResult(string Text, [property: JsonPropertyName("provider")] string Provider);

public sealed record EngineHealth(string Status);

public sealed record EngineProviderInfo(string Id, string Label, bool Available, string? Reason);

public sealed record EngineModelStatus(
    [property: JsonPropertyName("provider_id")] string ProviderId,
    string Label,
    [property: JsonPropertyName("repo_id")] string RepoId,
    [property: JsonPropertyName("local_path")] string LocalPath,
    bool Installed,
    [property: JsonPropertyName("installed_revision")] string? InstalledRevision,
    [property: JsonPropertyName("remote_revision")] string? RemoteRevision,
    [property: JsonPropertyName("update_available")] bool? UpdateAvailable,
    [property: JsonPropertyName("missing_files")] IReadOnlyList<string> MissingFiles,
    [property: JsonPropertyName("download_state")] string DownloadState,
    [property: JsonPropertyName("download_message")] string? DownloadMessage);

public sealed record EngineModelUpdateInfo(
    [property: JsonPropertyName("provider_id")] string ProviderId,
    [property: JsonPropertyName("repo_id")] string RepoId,
    [property: JsonPropertyName("installed_revision")] string? InstalledRevision,
    [property: JsonPropertyName("remote_revision")] string RemoteRevision,
    [property: JsonPropertyName("update_available")] bool UpdateAvailable);

public sealed record EngineModelDownloadStatus(
    [property: JsonPropertyName("provider_id")] string ProviderId,
    string State,
    string? Message,
    [property: JsonPropertyName("local_path")] string LocalPath,
    string? Revision);

public sealed record EngineTranscriptRecord(
    string Id,
    [property: JsonPropertyName("created_at")] string CreatedAt,
    string Source,
    [property: JsonPropertyName("raw_text")] string RawText,
    [property: JsonPropertyName("cleaned_text")] string? CleanedText,
    string? Provider,
    string? Style,
    [property: JsonPropertyName("audio_bytes")] int? AudioBytes,
    [property: JsonPropertyName("sample_rate")] int? SampleRate,
    [property: JsonPropertyName("duration_ms")] int? DurationMs)
{
    public string DisplayText
    {
        get
        {
            var cleaned = CleanedText?.Trim() ?? "";
            return string.IsNullOrEmpty(cleaned) ? RawText : cleaned;
        }
    }
}

public sealed class OmniVoicePreferences
{
    [JsonPropertyName("asr_provider")]
    public AsrProviderKind AsrProvider { get; set; } = AsrProviderKind.ParakeetTdt;

    public StyleProfile Style { get; set; } = StyleProfile.Neutral;

    [JsonPropertyName("dictionary_terms")]
    public List<string> DictionaryTerms { get; set; } = [];

    [JsonPropertyName("microphone_id")]
    public string? MicrophoneId { get; set; }

    [JsonPropertyName("dictation_hotkey")]
    public HotkeyBinding DictationHotkey { get; set; } = HotkeyBinding.DefaultDictation;

    [JsonPropertyName("style_hotkey")]
    public HotkeyBinding StyleHotkey { get; set; } = HotkeyBinding.DefaultStyle;

    [JsonPropertyName("live_translation_enabled")]
    public bool LiveTranslationEnabled { get; set; }

    [JsonPropertyName("translation_source_language")]
    public string TranslationSourceLanguage { get; set; } = "auto";

    [JsonPropertyName("translation_target_language")]
    public string TranslationTargetLanguage { get; set; } = "en";

    [JsonPropertyName("ai_provider_preset_id")]
    public AiProviderPresetId AiProviderPresetId { get; set; } = AiProviderPresetId.Custom;

    [JsonPropertyName("open_ai_compatible_base_url")]
    public string OpenAiCompatibleBaseUrl { get; set; } = "";

    [JsonPropertyName("open_ai_compatible_model")]
    public string OpenAiCompatibleModel { get; set; } = "";

    [JsonPropertyName("live_draft_insertion_enabled")]
    public bool LiveDraftInsertionEnabled { get; set; }

    public void CycleStyle() => Style = Style.Next();

    public void CycleAsrProvider() => AsrProvider = AsrProvider switch
    {
        AsrProviderKind.ParakeetTdt => AsrProviderKind.SenseVoiceSmallFunAsr,
        AsrProviderKind.SenseVoiceSmallFunAsr => AsrProviderKind.CanaryQwen25B,
        AsrProviderKind.CanaryQwen25B => AsrProviderKind.ParakeetTdt,
        _ => AsrProviderKind.ParakeetTdt,
    };
}

public sealed record AiHandoffRequest(
    string Prompt,
    string Provider,
    [property: JsonPropertyName("base_url")] string BaseUrl,
    string Model,
    [property: JsonPropertyName("api_key")] string ApiKey,
    string Context = "");

public sealed record AiHandoffResult(string Text, string Provider, string Model);

public sealed record TranslationRequest(
    string Text,
    [property: JsonPropertyName("source_language")] string SourceLanguage,
    [property: JsonPropertyName("target_language")] string TargetLanguage,
    string Provider,
    [property: JsonPropertyName("base_url")] string BaseUrl,
    string Model,
    [property: JsonPropertyName("api_key")] string ApiKey);

public sealed record TranslationResult(
    string Text,
    string Provider,
    string Model,
    [property: JsonPropertyName("source_language")] string SourceLanguage,
    [property: JsonPropertyName("target_language")] string TargetLanguage);

public sealed record MicrophoneDevice(string Id, string DisplayName);

public enum EngineStreamingConnectionState
{
    Idle,
    Connecting,
    Open,
    Closing,
    Closed,
    Failed,
    Cancelled,
}

public sealed record EngineStreamingDiagnostics(
    EngineStreamingConnectionState State,
    string? ProviderId,
    double SampleRate,
    int ChunksSent,
    int BytesSent,
    int UpdatesReceived,
    int PartialsReceived,
    int FinalsReceived,
    int DroppedChunks,
    int DroppedBytes,
    string LastText,
    string? LastError)
{
    public static EngineStreamingDiagnostics Idle { get; } = new(
        EngineStreamingConnectionState.Idle, null, 0, 0, 0, 0, 0, 0, 0, 0, "", null);
}
