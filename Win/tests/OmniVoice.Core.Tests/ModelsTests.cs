using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class ModelsTests
{
    [Fact]
    public void AsrProvidersExposeCapabilityProfiles()
    {
        var parakeet = AsrProviderKind.ParakeetTdt.CapabilityProfile();
        Assert.Equal("Fast local dictation", parakeet.PrimaryUse);
        Assert.Contains("English", parakeet.LanguageCoverage);
        Assert.False(parakeet.SupportsSourceLanguagePicker);
        Assert.Contains("Fastest", parakeet.Pills);

        var senseVoice = AsrProviderKind.SenseVoiceSmallFunAsr.CapabilityProfile();
        Assert.Equal("Fast multilingual dictation", senseVoice.PrimaryUse);
        Assert.Contains("Mandarin", senseVoice.LanguageCoverage);
        Assert.True(senseVoice.SupportsSourceLanguagePicker);
        Assert.Contains("FunASR", senseVoice.Pills);

        var canary = AsrProviderKind.CanaryQwen25B.CapabilityProfile();
        Assert.Equal("Multilingual transcription", canary.PrimaryUse);
        Assert.Contains("multilingual", canary.LanguageCoverage, StringComparison.OrdinalIgnoreCase);
        Assert.True(canary.SupportsSourceLanguagePicker);
        Assert.Contains("Translation-ready", canary.Pills);
    }

    [Fact]
    public void FakeProviderIsClearlyTestOnly()
    {
        var fake = AsrProviderKind.Fake.CapabilityProfile();
        Assert.True(fake.IsTestOnly);
        Assert.Contains("testing", fake.Limitation, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void AsrProviderCycleSkipsTestOnlyProvider()
    {
        var preferences = new OmniVoicePreferences();

        preferences.CycleAsrProvider();
        Assert.Equal(AsrProviderKind.SenseVoiceSmallFunAsr, preferences.AsrProvider);

        preferences.CycleAsrProvider();
        Assert.Equal(AsrProviderKind.CanaryQwen25B, preferences.AsrProvider);

        preferences.CycleAsrProvider();
        Assert.Equal(AsrProviderKind.ParakeetTdt, preferences.AsrProvider);
    }

    [Fact]
    public void AsrProviderWireValuesMatchEngineContract()
    {
        Assert.Equal("parakeet-tdt", AsrProviderKind.ParakeetTdt.WireValue());
        Assert.Equal("sensevoice-small-funasr", AsrProviderKind.SenseVoiceSmallFunAsr.WireValue());
        Assert.Equal("canary-qwen-2.5b", AsrProviderKind.CanaryQwen25B.WireValue());
    }
}
