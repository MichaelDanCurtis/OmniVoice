using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class DictationSessionTests
{
    [Fact]
    public void PressHotkey_StartsListening()
    {
        var session = new DictationSession();
        session.PressHotkey();
        Assert.Equal(DictationSessionState.Listening, session.State);
    }

    [Fact]
    public void ReleaseHotkey_MovesToCleaning()
    {
        var session = new DictationSession();
        session.PressHotkey();
        session.ReleaseHotkey("hello world");
        Assert.Equal(DictationSessionState.Cleaning, session.State);
        Assert.Equal("hello world", session.FinalTranscript);
    }
}