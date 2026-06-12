using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class TextInsertionEditTests
{
    [Fact]
    public void Make_ReplacesSelection()
    {
        var edit = TextInsertionEdit.Make("hello world", 6, 5, "universe", []);
        Assert.NotNull(edit);
        Assert.Equal("hello universe", edit!.Text);
        Assert.Equal(14, edit.CursorLocation);
    }
}