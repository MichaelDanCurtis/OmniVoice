using System.Drawing;
using System.Windows;
using System.Windows.Forms;
using OmniVoice.App.Services;
using OmniVoice.App.Windows;
using OmniVoice.Core;
using Application = System.Windows.Application;

namespace OmniVoice.App;

public partial class App : Application
{
    private NotifyIcon? _tray;
    private MainWindow? _settingsWindow;
    private CaptionOverlayWindow? _overlay;
    private DictationCoordinator? _coordinator;
    private readonly PreferencesStore _store = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var preferences = _store.Load();
        _overlay = new CaptionOverlayWindow();
        _settingsWindow = new MainWindow();

        _coordinator = new DictationCoordinator(preferencesStore: _store);
        _coordinator.Configure(preferences);
        _settingsWindow.BindCoordinator(_coordinator);
        _coordinator.Start();
        _coordinator.OverlayRequested += (text, level) =>
            _overlay?.ShowCaption(text, preferences.Style.DisplayName(), level);
        _coordinator.OverlayHideRequested += () => _overlay?.HideCaption();
        _tray = new NotifyIcon
        {
            Text = "OmniSpeak",
            Icon = SystemIcons.Application,
            Visible = true,
        };
        _tray.ContextMenuStrip = new ContextMenuStrip();
        _tray.ContextMenuStrip.Items.Add("Settings", null, (_, _) => ShowSettings());
        _tray.ContextMenuStrip.Items.Add("Engine Dashboard", null, (_, _) =>
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("http://127.0.0.1:8765") { UseShellExecute = true }));
        _tray.ContextMenuStrip.Items.Add("Exit", null, (_, _) => ShutdownApp());
        _tray.DoubleClick += (_, _) => ShowSettings();

        _ = EngineSupervisor.Shared.StartIfNeededAsync();
        ShowSettings();
    }

    public void ReloadHotkeys(OmniVoicePreferences preferences) => _coordinator?.Configure(preferences);

    private void ShowSettings()
    {
        if (_settingsWindow is null) return;
        _settingsWindow.Show();
        _settingsWindow.WindowState = WindowState.Normal;
        _settingsWindow.Activate();
    }

    private void ShutdownApp()
    {
        EngineSupervisor.Shared.StopStartedProcess();
        _coordinator?.Dispose();
        if (_tray is not null)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
        Shutdown();
    }
}