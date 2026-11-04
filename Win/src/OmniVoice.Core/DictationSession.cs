namespace OmniVoice.Core;

public enum DictationSessionState
{
    Idle,
    Listening,
    Cleaning,
    Inserting,
    Failed,
}

public sealed class DictationSession
{
    public DictationSessionState State { get; private set; } = DictationSessionState.Idle;
    public string PartialTranscript { get; private set; } = "";
    public string FinalTranscript { get; private set; } = "";
    public string FinalTextToInsert { get; private set; } = "";
    public string? FailureMessage { get; private set; }

    public void PressHotkey()
    {
        State = DictationSessionState.Listening;
        PartialTranscript = "";
        FinalTranscript = "";
        FinalTextToInsert = "";
        FailureMessage = null;
    }

    public void ReceivePartial(string text)
    {
        if (State != DictationSessionState.Listening) return;
        PartialTranscript = text;
    }

    public void ReleaseHotkey(string finalTranscript)
    {
        if (State != DictationSessionState.Listening) return;
        FinalTranscript = finalTranscript;
        State = DictationSessionState.Cleaning;
    }

    public void FinishCleanup(string text)
    {
        if (State != DictationSessionState.Cleaning) return;
        FinalTextToInsert = text;
        State = DictationSessionState.Inserting;
    }

    public void Fail(string message)
    {
        State = DictationSessionState.Failed;
        FailureMessage = message;
    }

    public void Reset()
    {
        State = DictationSessionState.Idle;
        PartialTranscript = "";
        FinalTranscript = "";
        FinalTextToInsert = "";
        FailureMessage = null;
    }
}