using System.Text.Json;
using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class PreferencesStoreTests
{
    [Fact]
    public void Defaults_UseParakeetAndNeutralStyle()
    {
        var preferences = new OmniVoicePreferences();
        Assert.Equal(AsrProviderKind.ParakeetTdt, preferences.AsrProvider);
        Assert.Equal(StyleProfile.Neutral, preferences.Style);
        Assert.Equal(AiProviderPresetId.Custom, preferences.AiProviderPresetId);
    }

    [Fact]
    public void RoundTrip_PersistsPreferences()
    {
        var path = Path.Combine(Path.GetTempPath(), $"omnivoice-prefs-{Guid.NewGuid():N}.json");
        try
        {
            var store = new PreferencesStore(path);
            var preferences = new OmniVoicePreferences
            {
                AsrProvider = AsrProviderKind.Fake,
                Style = StyleProfile.Concise,
                DictionaryTerms = ["CUDA", "WPF"],
                TranslationSourceLanguage = "es",
                TranslationTargetLanguage = "en",
                OpenAiCompatibleBaseUrl = "http://127.0.0.1:1234/v1",
                OpenAiCompatibleModel = "test-model",
                AiProviderPresetId = AiProviderPresetId.LmStudio,
            };

            store.Save(preferences);
            var loaded = store.Load();

            Assert.Equal(AsrProviderKind.Fake, loaded.AsrProvider);
            Assert.Equal(StyleProfile.Concise, loaded.Style);
            Assert.Equal(["CUDA", "WPF"], loaded.DictionaryTerms);
            Assert.Equal("es", loaded.TranslationSourceLanguage);
            Assert.Equal(AiProviderPresetId.LmStudio, loaded.AiProviderPresetId);
        }
        finally
        {
            if (File.Exists(path))
                File.Delete(path);
        }
    }

    [Fact]
    public void LegacyOpenAiCompatibleApiKey_ReadsSnakeCaseField()
    {
        var path = Path.Combine(Path.GetTempPath(), $"omnivoice-prefs-{Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, """{"open_ai_compatible_api_key":"legacy-key"}""");
            var store = new PreferencesStore(path);
            Assert.Equal("legacy-key", store.LegacyOpenAiCompatibleApiKey());
        }
        finally
        {
            if (File.Exists(path))
                File.Delete(path);
        }
    }

    [Fact]
    public void Save_DoesNotPersistApiKeyField()
    {
        var path = Path.Combine(Path.GetTempPath(), $"omnivoice-prefs-{Guid.NewGuid():N}.json");
        try
        {
            var store = new PreferencesStore(path);
            store.Save(new OmniVoicePreferences());
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            Assert.False(document.RootElement.TryGetProperty("open_ai_compatible_api_key", out _));
        }
        finally
        {
            if (File.Exists(path))
                File.Delete(path);
        }
    }
}