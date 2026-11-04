using OmniVoice.Core;

namespace OmniVoice.Core.Tests;

public class DictationCommandParserTests
{
    [Fact]
    public void Parse_OpenCommand()
    {
        var command = DictationCommandParser.Parse("Command, open Notepad");
        Assert.NotNull(command);
        Assert.Equal(DictationCommandActionKind.OpenApplication, command!.Kind);
        Assert.Equal("Notepad", command.AppName);
    }

    [Fact]
    public void Parse_OpenApplicationWithLetsPrefix()
    {
        var command = DictationCommandParser.Parse("Command. Let's open Safari.");
        Assert.NotNull(command);
        Assert.Equal(DictationCommandActionKind.OpenApplication, command!.Kind);
        Assert.Equal("Safari", command.AppName);
    }

    [Fact]
    public void Parse_LaunchWithoutPunctuation()
    {
        var command = DictationCommandParser.Parse("command launch Google Chrome");
        Assert.NotNull(command);
        Assert.Equal("Google Chrome", command!.AppName);
    }

    [Fact]
    public void Parse_IgnoresNormalDictation()
    {
        Assert.Null(DictationCommandParser.Parse("Let's open Safari tomorrow."));
    }

    [Fact]
    public void Parse_CommandPalette()
    {
        var command = DictationCommandParser.Parse("Command, show commands");
        Assert.NotNull(command);
        Assert.Equal(DictationCommandActionKind.ShowCommandPalette, command!.Kind);
    }

    [Fact]
    public void Parse_UndoCommand()
    {
        var command = DictationCommandParser.Parse("Command, undo last dictation");
        Assert.NotNull(command);
        Assert.Equal(DictationCommandActionKind.UndoLastDictation, command!.Kind);
    }

    [Fact]
    public void Parse_AiHandoff()
    {
        var command = DictationCommandParser.Parse("Ask Claude, write a polite reply");
        Assert.NotNull(command);
        Assert.Equal(DictationCommandActionKind.AiHandoff, command!.Kind);
        Assert.Equal(AiHandoffTarget.Claude, command.AiTarget);
        Assert.Equal("write a polite reply", command.AiPrompt);
    }

    [Fact]
    public void Parse_HeyCodexHandoff()
    {
        var command = DictationCommandParser.Parse("Hey Codex I need a two sentence summary");
        Assert.NotNull(command);
        Assert.Equal(AiHandoffTarget.Codex, command!.AiTarget);
        Assert.Equal("I need a two sentence summary", command.AiPrompt);
    }

    [Fact]
    public void Parse_OpenRouterHandoff()
    {
        var command = DictationCommandParser.Parse("Have OpenRouter take a look at this and respond in Spanish");
        Assert.NotNull(command);
        Assert.Equal(AiHandoffTarget.OpenRouter, command!.AiTarget);
        Assert.Equal("at this and respond in Spanish", command.AiPrompt);
    }

    [Fact]
    public void Parse_OpenAiHandoff()
    {
        var command = DictationCommandParser.Parse("Ask OpenAI, make this sound more professional");
        Assert.NotNull(command);
        Assert.Equal(AiHandoffTarget.OpenAi, command!.AiTarget);
        Assert.Equal("make this sound more professional", command.AiPrompt);
    }

    [Fact]
    public void Parse_IgnoresOrdinaryMentions()
    {
        Assert.Null(DictationCommandParser.Parse("Claude is a useful app for drafting emails."));
    }
}