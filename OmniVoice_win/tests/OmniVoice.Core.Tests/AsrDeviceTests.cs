using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class AsrDeviceTests
{
    [Fact]
    public void MoonshineProvider_HasWireValue()
    {
        Assert.Equal("moonshine-base-en", AsrProviderKind.MoonshineBaseEn.WireValue());
    }

    [Fact]
    public void ExistingProviders_KeepTheirWireValues()
    {
        Assert.Equal("parakeet-tdt", AsrProviderKind.ParakeetTdt.WireValue());
        Assert.Equal("canary-qwen-2.5b", AsrProviderKind.CanaryQwen25B.WireValue());
        Assert.Equal("fake", AsrProviderKind.Fake.WireValue());
    }

    [Fact]
    public void CycleAsrProvider_VisitsMoonshineAndReturnsToParakeet()
    {
        var preferences = new OmniVoicePreferences { AsrProvider = AsrProviderKind.ParakeetTdt };

        var seen = new List<AsrProviderKind>();
        for (var i = 0; i < 4; i++)
        {
            preferences.CycleAsrProvider();
            seen.Add(preferences.AsrProvider);
        }

        Assert.Contains(AsrProviderKind.MoonshineBaseEn, seen);
        Assert.Equal(AsrProviderKind.ParakeetTdt, preferences.AsrProvider);
    }

    [Fact]
    public void AsrDevice_DefaultsToAuto()
    {
        Assert.Equal(AsrDeviceKind.Auto, new OmniVoicePreferences().AsrDevice);
    }

    [Theory]
    [InlineData(AsrDeviceKind.Auto, "auto")]
    [InlineData(AsrDeviceKind.Cpu, "cpu")]
    [InlineData(AsrDeviceKind.Cuda, "cuda")]
    public void AsrDevice_WireValues(AsrDeviceKind device, string expected)
    {
        Assert.Equal(expected, device.WireValue());
    }

    [Fact]
    public void AsrDevice_RoundTripsThroughThePreferencesStore()
    {
        var path = Path.Combine(Path.GetTempPath(), $"omnispeak-prefs-{Guid.NewGuid():N}.json");
        try
        {
            var store = new PreferencesStore(path);
            store.Save(new OmniVoicePreferences
            {
                AsrProvider = AsrProviderKind.MoonshineBaseEn,
                AsrDevice = AsrDeviceKind.Cuda,
            });

            var loaded = store.Load();

            Assert.Equal(AsrProviderKind.MoonshineBaseEn, loaded.AsrProvider);
            Assert.Equal(AsrDeviceKind.Cuda, loaded.AsrDevice);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [Fact]
    public void EngineProviderInfo_CarriesTheExecutionDevice()
    {
        var info = new EngineProviderInfo("parakeet-tdt", "Parakeet TDT", true, null, "cuda");
        Assert.Equal("cuda", info.Device);
    }
}
