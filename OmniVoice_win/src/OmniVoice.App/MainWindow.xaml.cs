using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using OmniVoice.App.Services;
using OmniVoice.Core;

namespace OmniVoice.App;

public partial class MainWindow : Window
{
    private readonly PreferencesStore _store = new();
    private readonly EngineClient _engine = new();
    private readonly ISecretStore _secretStore = SecretStoreFactory.Create();
    private OmniVoicePreferences _preferences = new();
    private DictationCoordinator? _coordinator;
    private bool _isLoading;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    public void BindCoordinator(DictationCoordinator coordinator)
    {
        _coordinator = coordinator;
        coordinator.Changed += () => Dispatcher.Invoke(UpdateFromCoordinator);
        UpdateFromCoordinator();
    }

    private void UpdateFromCoordinator()
    {
        if (_coordinator is null) return;
        StatusTextBlock.Text = _coordinator.StatusText;

        if (_coordinator.PendingAiHandoff is { } pending)
        {
            PendingHandoffPanel.Visibility = Visibility.Visible;
            PendingHandoffText.Text = $"AI handoff pending: {pending.Target.DisplayName()}";
        }
        else
        {
            PendingHandoffPanel.Visibility = Visibility.Collapsed;
        }
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        _isLoading = true;
        _preferences = _store.Load();
        PopulatePresetCombo();
        ApplyPreferencesToUi();
        LoadApiKeyIntoUi();
        _isLoading = false;
        await RefreshEngineStatusAsync();
    }

    private void PopulatePresetCombo()
    {
        PresetCombo.Items.Clear();
        foreach (var preset in AiProviderPreset.BuiltIn)
        {
            PresetCombo.Items.Add(new ComboBoxItem
            {
                Content = preset.Name,
                Tag = preset.Id.ToString(),
            });
        }
    }

    private void ApplyPreferencesToUi()
    {
        SelectComboByTag(ProviderCombo, _preferences.AsrProvider.WireValue());
        SelectComboByTag(StyleCombo, _preferences.Style.ToString());
        SelectComboByTag(PresetCombo, _preferences.AiProviderPresetId.ToString());
        BaseUrlBox.Text = _preferences.OpenAiCompatibleBaseUrl;
        ModelBox.Text = _preferences.OpenAiCompatibleModel;
        TranslationCheck.IsChecked = _preferences.LiveTranslationEnabled;
        LiveDraftCheck.IsChecked = _preferences.LiveDraftInsertionEnabled;
        SourceLanguageBox.Text = _preferences.TranslationSourceLanguage;
        TargetLanguageBox.Text = _preferences.TranslationTargetLanguage;
        DictionaryBox.Text = string.Join(Environment.NewLine, _preferences.DictionaryTerms);

        MicrophoneCombo.Items.Clear();
        foreach (var device in AudioCaptureService.ListDevices())
            MicrophoneCombo.Items.Add(new ComboBoxItem { Content = device.DisplayName, Tag = device.Id });

        if (_preferences.MicrophoneId is null)
            MicrophoneCombo.SelectedIndex = 0;
        else
            SelectComboByTag(MicrophoneCombo, _preferences.MicrophoneId);
    }

    private void LoadApiKeyIntoUi()
    {
        var stored = _secretStore.GetString(SecretAccounts.OpenAiCompatibleApiKey);
        var legacy = stored is null ? _store.LegacyOpenAiCompatibleApiKey() : null;
        ApiKeyBox.Password = stored ?? legacy ?? "";
    }

    private static void SelectComboByTag(System.Windows.Controls.ComboBox combo, string tag)
    {
        foreach (System.Windows.Controls.ComboBoxItem item in combo.Items)
        {
            if (string.Equals(item.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase))
            {
                combo.SelectedItem = item;
                return;
            }
        }
    }

    private void Persist()
    {
        if (_isLoading) return;
        _store.Save(_preferences);
        if (WpfApplication.Current is App app)
            app.ReloadHotkeys(_preferences);
    }

    private async Task RefreshEngineStatusAsync()
    {
        try
        {
            await _engine.HealthAsync();
            EngineTextBlock.Text = "Engine: online (127.0.0.1:8765)";
        }
        catch
        {
            EngineSupervisor.Shared.AsrDevice = _preferences.AsrDevice;
            var result = await EngineSupervisor.Shared.StartIfNeededAsync();
            EngineTextBlock.Text = $"Engine: {result.Detail}";
        }
    }

    private void ProviderCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoading || ProviderCombo.SelectedItem is not ComboBoxItem item) return;
        _preferences.AsrProvider = item.Tag?.ToString() switch
        {
            "canary-qwen-2.5b" => AsrProviderKind.CanaryQwen25B,
            "fake" => AsrProviderKind.Fake,
            _ => AsrProviderKind.ParakeetTdt,
        };
        Persist();
    }

    private void StyleCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoading || StyleCombo.SelectedItem is not ComboBoxItem item) return;
        if (Enum.TryParse<StyleProfile>(item.Tag?.ToString(), out var style))
        {
            _preferences.Style = style;
            Persist();
        }
    }

    private void PresetCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoading || PresetCombo.SelectedItem is not ComboBoxItem item) return;
        if (!Enum.TryParse<AiProviderPresetId>(item.Tag?.ToString(), out var presetId))
            return;

        _preferences.AiProviderPresetId = presetId;
        if (AiProviderPreset.For(presetId) is { } preset && presetId != AiProviderPresetId.Custom)
        {
            if (string.IsNullOrWhiteSpace(BaseUrlBox.Text))
                BaseUrlBox.Text = preset.BaseUrl;
            if (!string.IsNullOrWhiteSpace(preset.DefaultModel) && string.IsNullOrWhiteSpace(ModelBox.Text))
                ModelBox.Text = preset.DefaultModel;
        }

        Persist();
    }

    private void MicrophoneCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoading || MicrophoneCombo.SelectedItem is not ComboBoxItem item) return;
        _preferences.MicrophoneId = item.Tag?.ToString() == "default" ? null : item.Tag?.ToString();
        Persist();
    }

    private void DictionaryBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_isLoading) return;
        _preferences.DictionaryTerms = DictionaryBox.Text
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(s => s.Trim())
            .Where(s => !string.IsNullOrEmpty(s))
            .ToList();
        Persist();
    }

    private void Integration_TextChanged(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        _preferences.OpenAiCompatibleBaseUrl = BaseUrlBox.Text.Trim();
        _preferences.OpenAiCompatibleModel = ModelBox.Text.Trim();
        _preferences.LiveTranslationEnabled = TranslationCheck.IsChecked == true;
        _preferences.LiveDraftInsertionEnabled = LiveDraftCheck.IsChecked == true;
        _preferences.TranslationSourceLanguage = SourceLanguageBox.Text.Trim();
        _preferences.TranslationTargetLanguage = TargetLanguageBox.Text.Trim();
        Persist();
    }

    private void ApiKeyBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (_isLoading) return;
        _coordinator?.SetApiKey(ApiKeyBox.Password);
    }

    private void OpenDashboard_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("http://127.0.0.1:8765") { UseShellExecute = true });

    private async void RestartEngine_Click(object sender, RoutedEventArgs e)
    {
        var result = await EngineSupervisor.Shared.RestartAsync();
        EngineTextBlock.Text = $"Engine: {result.Detail}";
    }

    private async void CleanupTest_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var result = await _engine.CleanupAsync(new CleanupRequest(
                "I am going to the store. No wait, I am going to the house.",
                _preferences.Style,
                _preferences.DictionaryTerms));
            WpfMessageBox.Show(result.Text, "Cleanup test", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            WpfMessageBox.Show(ex.Message, "Cleanup test failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void TestAiHandoff_Click(object sender, RoutedEventArgs e)
    {
        if (_coordinator is null) return;
        _coordinator.SetApiKey(ApiKeyBox.Password);
        try
        {
            var response = await _coordinator.TestAiHandoffAsync("Reply with the single word: connected");
            WpfMessageBox.Show(response, "AI handoff test", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            WpfMessageBox.Show(ex.Message, "AI handoff test failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void RetryHandoff_Click(object sender, RoutedEventArgs e)
    {
        if (_coordinator is null) return;
        await _coordinator.RetryPendingAiHandoffAsync();
    }

    private void CopyPrompt_Click(object sender, RoutedEventArgs e) =>
        _coordinator?.CopyPendingAiHandoffPrompt();

    private async void InsertOriginal_Click(object sender, RoutedEventArgs e)
    {
        if (_coordinator is null) return;
        await _coordinator.InsertPendingAiHandoffOriginalAsync();
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }
}