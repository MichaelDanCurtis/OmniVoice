using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using OmniVoice.Core;

namespace OmniVoice.App.Services;

public sealed class TextInsertionService
{
    public sealed class InsertionTarget
    {
        public AutomationElement? FocusedElement { get; init; }
        public string? ProcessName { get; init; }
        public string SelectedText { get; init; } = "";
        public string CurrentValue { get; init; } = "";
        public int SelectionStart { get; init; }
        public int SelectionLength { get; init; }
    }

    public sealed class LiveDraft
    {
        public required AutomationElement Element { get; init; }
        public required string OriginalText { get; init; }
        public required int SelectionStart { get; init; }
        public required IReadOnlyList<string> PlaceholderValues { get; init; }
        public string CurrentText { get; set; } = "";
    }

    private (AutomationElement Element, string PreviousText, int PreviousCursor)? _lastInsertion;

    public InsertionTarget CaptureTarget()
    {
        var focused = AutomationElement.FocusedElement;
        if (focused is null)
            return new InsertionTarget();

        var currentValue = ReadValue(focused);
        return new InsertionTarget
        {
            FocusedElement = focused,
            ProcessName = TryProcessName(focused),
            CurrentValue = currentValue,
            SelectionStart = currentValue.Length,
            SelectionLength = 0,
        };
    }

    public bool BeginLiveDraft(InsertionTarget target, out LiveDraft? draft)
    {
        draft = null;
        if (target.FocusedElement is null)
            return false;

        draft = new LiveDraft
        {
            Element = target.FocusedElement,
            OriginalText = target.CurrentValue,
            SelectionStart = target.SelectionStart,
            PlaceholderValues = PlaceholderValues(target.FocusedElement),
        };
        return true;
    }

    public bool UpdateLiveDraft(string text, ref LiveDraft draft) =>
        ApplyLiveDraft(text, ref draft, recordUndo: false);

    public bool CommitLiveDraft(string text, ref LiveDraft draft) =>
        ApplyLiveDraft(text, ref draft, recordUndo: true);

    public void CancelLiveDraft(LiveDraft draft) => TrySetValue(draft.Element, draft.OriginalText);

    public async Task InsertAsync(string text, InsertionTarget? target)
    {
        var insertionText = TextInsertionEdit.SanitizedInsertionText(text);
        if (target?.FocusedElement is not null && TryInsertViaAutomation(insertionText, target.FocusedElement, target))
            return;

        var focused = AutomationElement.FocusedElement;
        if (focused is not null && TryInsertViaAutomation(insertionText, focused, target))
            return;

        await Task.Delay(50);
        PasteViaClipboard(insertionText);
    }

    public void UndoLastInsertion()
    {
        if (_lastInsertion is not { } record)
            throw new InvalidOperationException("There is no recent OmniSpeak insertion to undo.");

        if (!TrySetValue(record.Element, record.PreviousText))
            throw new InvalidOperationException("Could not restore the previous text.");

        _lastInsertion = null;
    }

    private bool ApplyLiveDraft(string text, ref LiveDraft draft, bool recordUndo)
    {
        var edit = TextInsertionEdit.Make(
            draft.OriginalText,
            draft.SelectionStart,
            0,
            text,
            draft.PlaceholderValues);
        if (edit is null) return false;
        if (!TrySetValue(draft.Element, edit.Text)) return false;

        if (recordUndo)
            _lastInsertion = (draft.Element, draft.OriginalText, draft.SelectionStart);

        draft.CurrentText = text;
        return true;
    }

    private bool TryInsertViaAutomation(string text, AutomationElement element, InsertionTarget? target)
    {
        var currentValue = target?.CurrentValue ?? ReadValue(element);
        var start = target?.SelectionStart ?? currentValue.Length;
        var length = target?.SelectionLength ?? 0;
        var placeholders = PlaceholderValues(element);

        var edit = TextInsertionEdit.Make(currentValue, start, length, text, placeholders);
        if (edit is null) return false;
        if (!TrySetValue(element, edit.Text)) return false;

        _lastInsertion = (element, currentValue, start);
        return true;
    }

    private static string ReadValue(AutomationElement element)
    {
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var patternObj) &&
            patternObj is ValuePattern valuePattern)
            return valuePattern.Current.Value ?? "";

        return "";
    }

    private static bool TrySetValue(AutomationElement element, string value)
    {
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var patternObj) &&
            patternObj is ValuePattern valuePattern)
        {
            valuePattern.SetValue(value);
            return true;
        }

        return false;
    }

    private static IReadOnlyList<string> PlaceholderValues(AutomationElement element)
    {
        var values = new List<string>();
        foreach (var id in new[] { AutomationElement.HelpTextProperty, AutomationElement.NameProperty })
        {
            var value = element.GetCurrentPropertyValue(id, true);
            if (value is string s && !string.IsNullOrWhiteSpace(s))
                values.Add(s);
        }

        return values;
    }

    private static void PasteViaClipboard(string text)
    {
        var previous = WpfClipboard.GetText();
        WpfClipboard.SetText(text);

        var inputs = new[]
        {
            new NativeMethods.INPUT
            {
                Type = NativeMethods.InputKeyboard,
                U = new NativeMethods.InputUnion { Ki = new NativeMethods.KEYBDINPUT { Vk = 0x11 } },
            },
            new NativeMethods.INPUT
            {
                Type = NativeMethods.InputKeyboard,
                U = new NativeMethods.InputUnion { Ki = new NativeMethods.KEYBDINPUT { Vk = 0x56 } },
            },
            new NativeMethods.INPUT
            {
                Type = NativeMethods.InputKeyboard,
                U = new NativeMethods.InputUnion { Ki = new NativeMethods.KEYBDINPUT { Vk = 0x56, Flags = NativeMethods.KeyeventfKeyup } },
            },
            new NativeMethods.INPUT
            {
                Type = NativeMethods.InputKeyboard,
                U = new NativeMethods.InputUnion { Ki = new NativeMethods.KEYBDINPUT { Vk = 0x11, Flags = NativeMethods.KeyeventfKeyup } },
            },
        };
        NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<NativeMethods.INPUT>());

        WpfApplication.Current.Dispatcher.BeginInvoke(() => WpfClipboard.SetText(previous));
    }

    private static string? TryProcessName(AutomationElement element)
    {
        try
        {
            var processId = element.Current.ProcessId;
            using var process = Process.GetProcessById(processId);
            return process.ProcessName;
        }
        catch
        {
            return null;
        }
    }
}