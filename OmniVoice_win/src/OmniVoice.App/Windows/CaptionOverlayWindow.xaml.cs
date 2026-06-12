using System.Windows;

namespace OmniVoice.App.Windows;

public partial class CaptionOverlayWindow : Window
{
    public CaptionOverlayWindow()
    {
        InitializeComponent();
        Left = SystemParameters.WorkArea.Width / 2 - Width / 2;
        Top = SystemParameters.WorkArea.Height - Height - 48;
    }

    public void ShowCaption(string text, string styleName, float level)
    {
        StyleLabel.Text = styleName;
        CaptionLabel.Text = text;
        LevelBar.Value = Math.Clamp(level * 8, 0, 1);
        if (!IsVisible)
            Show();
    }

    public void HideCaption()
    {
        Hide();
    }
}