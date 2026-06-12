using OmniVoice.Core;

namespace OmniVoice.App.Services;

public sealed class DictationCoordinator : IDisposable
{
    private readonly HotkeyService _hotkeys = new();
    private readonly AudioCaptureService _audio = new();
    private readonly EngineClient _engine = new();
    private readonly EngineStreamingClient _streaming = new();
    private readonly TextInsertionService _insertion = new();
    private readonly DictationCommandExecutor _commandExecutor = new();
    private readonly ISecretStore _secretStore;
    private readonly PreferencesStore _preferencesStore;

    private OmniVoicePreferences _preferences = new();
    private string _apiKey = "";
    private DictationSession _session = new();
    private TextInsertionService.InsertionTarget? _target;
    private TextInsertionService.LiveDraft? _liveDraft;
    private PendingAiHandoffCommand? _pendingAiHandoff;

    public DictationCoordinator(ISecretStore? secretStore = null, PreferencesStore? preferencesStore = null)
    {
        _secretStore = secretStore ?? SecretStoreFactory.Create();
        _preferencesStore = preferencesStore ?? new PreferencesStore();
        LoadApiKey();
    }

    public DictationSession Session => _session;
    public string StatusText { get; private set; } = "Ready";
    public string CaptionText { get; private set; } = "";
    public float InputLevel { get; private set; }
    public EngineStreamingDiagnostics StreamingDiagnostics { get; private set; } = EngineStreamingDiagnostics.Idle;
    public PendingAiHandoffCommand? PendingAiHandoff => _pendingAiHandoff;

    public event Action? Changed;
    public event Action<string, float>? OverlayRequested;
    public event Action? OverlayHideRequested;

    public void Configure(OmniVoicePreferences preferences)
    {
        _preferences = preferences;
        _hotkeys.Register(preferences.DictationHotkey, preferences.StyleHotkey);
    }

    public void SetApiKey(string apiKey)
    {
        _apiKey = apiKey.Trim();
        if (string.IsNullOrEmpty(_apiKey))
            _secretStore.DeleteString(SecretAccounts.OpenAiCompatibleApiKey);
        else
            _secretStore.SetString(SecretAccounts.OpenAiCompatibleApiKey, _apiKey);
    }

    public void Start()
    {
        _hotkeys.OnEvent += HandleHotkey;
        _streaming.OnUpdate += update => WpfApplication.Current.Dispatcher.Invoke(() => HandleStreamUpdate(update));
        _streaming.OnDiagnostics += diagnostics =>
        {
            StreamingDiagnostics = diagnostics;
            Changed?.Invoke();
        };
        _audio.OnLevel += level =>
        {
            InputLevel = level;
            if (_session.State == DictationSessionState.Listening)
                OverlayRequested?.Invoke(CaptionText, level);
        };
        _audio.OnPcmChunk += chunk => _ = _streaming.SendPcmFloat32Async(chunk);
    }

    private void LoadApiKey()
    {
        var stored = _secretStore.GetString(SecretAccounts.OpenAiCompatibleApiKey);
        var legacy = stored is null ? _preferencesStore.LegacyOpenAiCompatibleApiKey() : null;
        _apiKey = stored ?? legacy ?? "";
        if (stored is null && !string.IsNullOrEmpty(legacy))
            _secretStore.SetString(SecretAccounts.OpenAiCompatibleApiKey, legacy);
    }

    private void HandleHotkey(HotkeyService.HotkeyEventKind kind)
    {
        WpfApplication.Current.Dispatcher.Invoke(() =>
        {
            switch (kind)
            {
                case HotkeyService.HotkeyEventKind.DictationPressed:
                    StartDictation();
                    break;
                case HotkeyService.HotkeyEventKind.DictationReleased:
                    _ = FinishDictationAsync();
                    break;
                case HotkeyService.HotkeyEventKind.StylePressed:
                    _preferences.CycleStyle();
                    StatusText = $"Style: {_preferences.Style.DisplayName()}";
                    OverlayRequested?.Invoke(StatusText, 0);
                    Changed?.Invoke();
                    break;
            }
        });
    }

    private void StartDictation()
    {
        _target = _insertion.CaptureTarget();
        _liveDraft = null;
        if (_preferences.LiveDraftInsertionEnabled && _insertion.BeginLiveDraft(_target, out var draft))
            _liveDraft = draft;

        _session.PressHotkey();
        CaptionText = "";
        StatusText = "Listening";
        OverlayRequested?.Invoke("", 0);
        Changed?.Invoke();

        try
        {
            _audio.Start(_preferences.MicrophoneId);
            _ = _streaming.ConnectAsync(_preferences.AsrProvider, _audio.SampleRate);
        }
        catch (Exception ex)
        {
            _session.Fail($"Microphone failed: {ex.Message}");
            StatusText = "Microphone failed";
            _ = _streaming.CancelAsync();
            CancelLiveDraft();
            OverlayHideRequested?.Invoke();
            Changed?.Invoke();
        }
    }

    private void HandleStreamUpdate(TranscriptUpdate update)
    {
        if (_session.State != DictationSessionState.Listening) return;
        var display = TextInsertionEdit.SanitizedInsertionText(update.Text);
        if (!update.IsFinal)
        {
            _session.ReceivePartial(display);
            UpdateLiveDraft(display);
        }

        CaptionText = display;
        OverlayRequested?.Invoke(display, InputLevel);
        Changed?.Invoke();
    }

    private async Task FinishDictationAsync()
    {
        await _streaming.FinishAsync();
        byte[] audio;
        try
        {
            audio = _audio.StopWavData();
            StatusText = "Transcribing";
            OverlayRequested?.Invoke("Transcribing...", 0);
            Changed?.Invoke();
        }
        catch (Exception ex)
        {
            _session.Fail($"Audio capture failed: {ex.Message}");
            StatusText = "Audio capture failed";
            await _streaming.CancelAsync();
            CancelLiveDraft();
            OverlayHideRequested?.Invoke();
            Changed?.Invoke();
            return;
        }

        TranscribeResult transcript;
        try
        {
            transcript = await _engine.TranscribeAsync(audio, _preferences.AsrProvider);
        }
        catch (Exception ex)
        {
            _session.Fail($"Transcription failed: {ex.Message}");
            StatusText = ex.Message;
            await _streaming.CancelAsync();
            CancelLiveDraft();
            OverlayRequested?.Invoke(ex.Message, 0);
            Changed?.Invoke();
            return;
        }

        var raw = TextInsertionEdit.SanitizedInsertionText(transcript.Text);
        if (string.IsNullOrWhiteSpace(raw))
        {
            _session.Fail("No speech detected");
            StatusText = "No speech detected";
            await _streaming.CancelAsync();
            CancelLiveDraft();
            OverlayRequested?.Invoke("No speech detected", 0);
            Changed?.Invoke();
            return;
        }

        _session.ReleaseHotkey(raw);
        CaptionText = raw;
        OverlayRequested?.Invoke(raw, 0);
        Changed?.Invoke();

        var shouldTranslate = true;
        string finalText;
        if (TryLiteralPayload(raw, out var literal))
        {
            finalText = TextInsertionEdit.SanitizedInsertionText(literal);
            shouldTranslate = false;
            StatusText = "Literal mode";
        }
        else
        {
            var cleanupStyle = DictationStyleResolver.CleanupStyle(_target?.ProcessName, _preferences.Style);
            try
            {
                var cleanup = await _engine.CleanupAsync(new CleanupRequest(raw, cleanupStyle, _preferences.DictionaryTerms));
                finalText = TextInsertionEdit.SanitizedInsertionText(cleanup.Text);
            }
            catch
            {
                finalText = LightlyPunctuate(raw);
                StatusText = "Cleanup skipped";
            }
        }

        if (DictationCommandParser.Parse(finalText) is { } command)
        {
            CancelLiveDraft();
            await HandleCommandAsync(command, finalText);
            return;
        }

        if (!string.IsNullOrWhiteSpace(_target?.SelectedText) &&
            SelectionRewrite.Rewrite(_target.SelectedText, finalText) is { } rewritten)
        {
            _session.FinishCleanup(rewritten);
            await InsertFinalTextAsync(rewritten, "Selection rewritten");
            return;
        }

        var translated = shouldTranslate
            ? await TranslatedFinalTextIfNeededAsync(finalText)
            : (Text: finalText, SuccessStatus: "Inserted");
        _session.FinishCleanup(translated.Text);
        await InsertFinalTextAsync(translated.Text, translated.SuccessStatus);
    }

    private async Task<(string Text, string SuccessStatus)> TranslatedFinalTextIfNeededAsync(string finalText)
    {
        if (!_preferences.LiveTranslationEnabled)
            return (finalText, "Inserted");

        var sourceLanguage = string.IsNullOrWhiteSpace(_preferences.TranslationSourceLanguage)
            ? "auto"
            : _preferences.TranslationSourceLanguage.Trim();
        var targetLanguage = string.IsNullOrWhiteSpace(_preferences.TranslationTargetLanguage)
            ? "en"
            : _preferences.TranslationTargetLanguage.Trim();

        if (string.Equals(sourceLanguage, targetLanguage, StringComparison.OrdinalIgnoreCase))
            return (finalText, "Inserted");

        var baseUrl = _preferences.OpenAiCompatibleBaseUrl.Trim();
        var model = _preferences.OpenAiCompatibleModel.Trim();
        if (string.IsNullOrEmpty(baseUrl) || string.IsNullOrEmpty(model))
        {
            StatusText = "Translation endpoint required";
            OverlayRequested?.Invoke("Add an OpenAI-compatible endpoint and model in Settings.", 0);
            return (finalText, "Inserted - translation skipped");
        }

        StatusText = "Translating";
        OverlayRequested?.Invoke($"Translating to {targetLanguage}...", 0);
        Changed?.Invoke();

        try
        {
            var result = await _engine.TranslateAsync(new TranslationRequest(
                finalText,
                sourceLanguage,
                targetLanguage,
                _preferences.AiProviderPresetId.WireValue(),
                baseUrl,
                model,
                _apiKey));
            var translatedText = TextInsertionEdit.SanitizedInsertionText(result.Text);
            if (string.IsNullOrWhiteSpace(translatedText))
            {
                StatusText = "Translation returned empty text";
                OverlayRequested?.Invoke("Translation returned empty text", 0);
                return (finalText, "Inserted - translation skipped");
            }

            CaptionText = translatedText;
            OverlayRequested?.Invoke(translatedText, 0);
            return (translatedText, "Translated");
        }
        catch (Exception ex)
        {
            StatusText = "Translation skipped";
            OverlayRequested?.Invoke(ex.Message, 0);
            return (finalText, "Inserted - translation skipped");
        }
    }

    private async Task InsertFinalTextAsync(string finalText, string successStatus)
    {
        if (_liveDraft is { } draft)
        {
            if (_insertion.CommitLiveDraft(finalText, ref draft))
            {
                _liveDraft = null;
                StatusText = successStatus;
                _session.Reset();
                OverlayHideRequested?.Invoke();
                Changed?.Invoke();
                return;
            }

            _insertion.CancelLiveDraft(draft);
            _liveDraft = null;
        }

        try
        {
            await _insertion.InsertAsync(finalText, _target);
            StatusText = successStatus;
            _session.Reset();
            OverlayHideRequested?.Invoke();
        }
        catch (Exception ex)
        {
            _session.Fail($"Insertion failed: {ex.Message}");
            StatusText = "Insertion failed - copied";
            WpfClipboard.SetText(finalText);
            OverlayRequested?.Invoke(finalText, 0);
        }

        Changed?.Invoke();
    }

    private async Task HandleCommandAsync(DictationCommand command, string originalText)
    {
        try
        {
            switch (command.Kind)
            {
                case DictationCommandActionKind.OpenApplication:
                    _commandExecutor.Execute(command);
                    break;
                case DictationCommandActionKind.ShowCommandPalette:
                    OverlayRequested?.Invoke("Command, open Notepad\nCommand, undo last dictation\nAsk Claude, write a reply", 0);
                    break;
                case DictationCommandActionKind.UndoLastDictation:
                    _insertion.UndoLastInsertion();
                    break;
                case DictationCommandActionKind.AiHandoff when command.AiPrompt is not null:
                    await RunAiHandoffAsync(new PendingAiHandoffCommand(
                        command.AiTarget ?? AiHandoffTarget.Custom,
                        command.AiPrompt,
                        _target?.SelectedText?.Trim() ?? "",
                        originalText));
                    return;
            }

            StatusText = command.DisplayText;
            OverlayRequested?.Invoke(command.DisplayText, 0);
            _session.Reset();
        }
        catch (Exception ex)
        {
            _session.Fail($"Command failed: {ex.Message}");
            StatusText = "Command failed";
            OverlayRequested?.Invoke(ex.Message, 0);
        }

        Changed?.Invoke();
    }

    public async Task RetryPendingAiHandoffAsync()
    {
        if (_pendingAiHandoff is not { } pending)
            return;

        _target = _insertion.CaptureTarget();
        await RunAiHandoffAsync(pending);
    }

    public void CopyPendingAiHandoffPrompt()
    {
        if (_pendingAiHandoff is not { } pending)
            return;

        WpfClipboard.SetText(pending.Prompt);
        StatusText = "AI prompt copied";
        Changed?.Invoke();
    }

    public async Task InsertPendingAiHandoffOriginalAsync()
    {
        if (_pendingAiHandoff is not { } pending)
            return;

        _target = _insertion.CaptureTarget();
        await InsertFinalTextAsync(pending.OriginalText, "Original AI command inserted");
        ClearPendingAiHandoff();
    }

    public void ClearPendingAiHandoff()
    {
        _pendingAiHandoff = null;
        Changed?.Invoke();
    }

    public async Task<string> TestAiHandoffAsync(string prompt)
    {
        var baseUrl = _preferences.OpenAiCompatibleBaseUrl.Trim();
        var model = _preferences.OpenAiCompatibleModel.Trim();
        if (string.IsNullOrEmpty(baseUrl) || string.IsNullOrEmpty(model))
            throw new InvalidOperationException("Add an OpenAI-compatible endpoint and model in Settings.");

        var result = await _engine.AiHandoffAsync(new AiHandoffRequest(
            prompt,
            _preferences.AiProviderPresetId.WireValue(),
            baseUrl,
            model,
            _apiKey,
            ""));
        return TextInsertionEdit.SanitizedInsertionText(result.Text);
    }

    private async Task RunAiHandoffAsync(PendingAiHandoffCommand pending)
    {
        _pendingAiHandoff = pending;
        Changed?.Invoke();

        var baseUrl = _preferences.OpenAiCompatibleBaseUrl.Trim();
        var model = _preferences.OpenAiCompatibleModel.Trim();
        if (string.IsNullOrEmpty(baseUrl) || string.IsNullOrEmpty(model))
        {
            _session.Fail("AI endpoint and model are required");
            StatusText = "AI endpoint required";
            OverlayRequested?.Invoke("Add an OpenAI-compatible endpoint and model in Settings.", 0);
            Changed?.Invoke();
            return;
        }

        StatusText = $"Asking {pending.Target.DisplayName()}";
        OverlayRequested?.Invoke($"Asking {pending.Target.DisplayName()}...", 0);
        Changed?.Invoke();

        try
        {
            var result = await _engine.AiHandoffAsync(new AiHandoffRequest(
                pending.Prompt,
                pending.Provider,
                baseUrl,
                model,
                _apiKey,
                pending.Context));
            var insertion = TextInsertionEdit.SanitizedInsertionText(result.Text);
            if (string.IsNullOrWhiteSpace(insertion))
            {
                _session.Fail("AI returned empty text");
                StatusText = "AI returned empty text";
                OverlayRequested?.Invoke("AI returned empty text", 0);
                Changed?.Invoke();
                return;
            }

            ClearPendingAiHandoff();
            _session.FinishCleanup(insertion);
            await InsertFinalTextAsync(insertion, "AI response inserted");
        }
        catch (Exception ex)
        {
            _session.Fail($"AI handoff failed: {ex.Message}");
            StatusText = "AI handoff failed";
            OverlayRequested?.Invoke(ex.Message, 0);
            Changed?.Invoke();
        }
    }

    private void UpdateLiveDraft(string text)
    {
        if (string.Equals(text.Trim(), "listening", StringComparison.OrdinalIgnoreCase)) return;
        if (_liveDraft is { } draft)
            _insertion.UpdateLiveDraft(text, ref draft);
    }

    private void CancelLiveDraft()
    {
        if (_liveDraft is { } draft)
            _insertion.CancelLiveDraft(draft);
        _liveDraft = null;
    }

    private static bool TryLiteralPayload(string text, out string payload)
    {
        payload = "";
        var trimmed = text.Trim();
        foreach (var prefix in new[] { "literal mode", "raw dictation" })
        {
            if (!trimmed.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) continue;
            payload = trimmed[prefix.Length..].Trim(' ', '\t', '\r', '\n', ',', '.', ':', ';', '!', '?');
            return true;
        }

        return false;
    }

    private static string LightlyPunctuate(string text)
    {
        var trimmed = text.Trim();
        if (string.IsNullOrEmpty(trimmed)) return trimmed;
        return trimmed.EndsWith('.') || trimmed.EndsWith('!') || trimmed.EndsWith('?') ? trimmed : trimmed + ".";
    }

    public void Dispose()
    {
        _hotkeys.Dispose();
        _audio.Dispose();
        _engine.Dispose();
        _ = _streaming.DisposeAsync();
    }
}