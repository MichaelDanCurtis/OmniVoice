using System.Runtime.InteropServices;
using OmniVoice.Core;

namespace OmniVoice.App.Services;

public sealed class HotkeyService : IDisposable
{
    public enum HotkeyEventKind
    {
        DictationPressed,
        DictationReleased,
        StylePressed,
    }

    private HotkeyBinding _dictation = HotkeyBinding.DefaultDictation;
    private HotkeyBinding _style = HotkeyBinding.DefaultStyle;
    private NativeMethods.LowLevelKeyboardProc? _proc;
    private IntPtr _hook;
    private bool _dictationHeld;

    public event Action<HotkeyEventKind>? OnEvent;

    public void Register(HotkeyBinding dictation, HotkeyBinding style)
    {
        Unregister();
        _dictation = dictation;
        _style = style;
        _proc = HookCallback;
        _hook = NativeMethods.SetWindowsHookEx(
            NativeMethods.WhKeyboardLl,
            _proc,
            NativeMethods.GetModuleHandle(null),
            0);
    }

    public void Unregister()
    {
        if (_hook != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }

        _dictationHeld = false;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var data = Marshal.PtrToStructure<NativeMethods.KBDLLHOOKSTRUCT>(lParam);
            var keyDown = wParam == (IntPtr)NativeMethods.WmKeydown || wParam == (IntPtr)NativeMethods.WmSyskeydown;
            var keyUp = wParam == (IntPtr)NativeMethods.WmKeyup || wParam == (IntPtr)NativeMethods.WmSyskeyup;
            var vk = (int)data.VkCode;
            var mods = CurrentModifiers();

            if (_dictation.IsModifierOnly)
            {
                if (mods == _dictation.Modifiers && !_dictationHeld)
                {
                    _dictationHeld = true;
                    OnEvent?.Invoke(HotkeyEventKind.DictationPressed);
                }
                else if (_dictationHeld && mods != _dictation.Modifiers)
                {
                    _dictationHeld = false;
                    OnEvent?.Invoke(HotkeyEventKind.DictationReleased);
                }
            }
            else if (Matches(_dictation, vk, mods))
            {
                if (keyDown && !_dictationHeld)
                {
                    _dictationHeld = true;
                    OnEvent?.Invoke(HotkeyEventKind.DictationPressed);
                }
                else if (keyUp && _dictationHeld)
                {
                    _dictationHeld = false;
                    OnEvent?.Invoke(HotkeyEventKind.DictationReleased);
                }
            }

            if (_style.IsModifierOnly)
            {
                if (mods == _style.Modifiers && keyDown)
                    OnEvent?.Invoke(HotkeyEventKind.StylePressed);
            }
            else if (Matches(_style, vk, mods) && keyUp)
            {
                OnEvent?.Invoke(HotkeyEventKind.StylePressed);
            }
        }

        return NativeMethods.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private static bool Matches(HotkeyBinding binding, int vk, HotkeyModifiers mods) =>
        binding.VirtualKey == vk && binding.Modifiers == mods;

    private static HotkeyModifiers CurrentModifiers()
    {
        var mods = HotkeyModifiers.None;
        if (IsDown(NativeMethods.VkControl)) mods |= HotkeyModifiers.Control;
        if (IsDown(NativeMethods.VkMenu)) mods |= HotkeyModifiers.Alt;
        if (IsDown(NativeMethods.VkShift)) mods |= HotkeyModifiers.Shift;
        if (IsDown(NativeMethods.VkLwin)) mods |= HotkeyModifiers.Windows;
        return mods;
    }

    private static bool IsDown(int vk) => (NativeMethods.GetAsyncKeyState(vk) & 0x8000) != 0;

    public void Dispose() => Unregister();
}