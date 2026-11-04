using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class DictationStyleResolverTests
{
    [Theory]
    [InlineData("Code", StyleProfile.Raw)]
    [InlineData("windowsterminal", StyleProfile.Raw)]
    [InlineData("OUTLOOK", StyleProfile.Professional)]
    [InlineData("Slack", StyleProfile.Concise)]
    public void CleanupStyle_UsesContextWhenNeutral(string processName, StyleProfile expected) =>
        Assert.Equal(expected, DictationStyleResolver.CleanupStyle(processName, StyleProfile.Neutral));

    [Fact]
    public void CleanupStyle_RespectsExplicitPreference() =>
        Assert.Equal(StyleProfile.Expanded, DictationStyleResolver.CleanupStyle("Code", StyleProfile.Expanded));
}