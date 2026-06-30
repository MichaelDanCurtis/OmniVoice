from omnivoice_engine.cleanup import clean_transcript
from omnivoice_engine.schemas import CleanupRequest


def clean(raw: str, style: str = "neutral") -> str:
    return clean_transcript(CleanupRequest(raw_transcript=raw, style=style)).text


def test_dictionary_entries_alias_replacement_and_casing():
    from omnivoice_engine.cleanup import _apply_dictionary_entries

    entries = [{"canonical": "Figma", "aliases": ["fig ma"], "enabled": True}]
    assert _apply_dictionary_entries("open fig ma and figma", entries) == "open Figma and Figma"


def test_dictionary_entries_disabled_skipped():
    from omnivoice_engine.cleanup import _apply_dictionary_entries

    entries = [{"canonical": "Figma", "aliases": [], "enabled": False}]
    assert _apply_dictionary_entries("figma", entries) == "figma"


def test_no_wait_replaces_abandoned_clause():
    assert (
        clean("I'm going to go to the store. No wait, I'm going to go to the house.")
        == "I'm going to go to the house."
    )


def test_actually_replaces_date():
    assert clean("Schedule it for Monday, actually Tuesday.") == "Schedule it for Tuesday."


def test_scratch_that_keeps_following_sentence():
    assert clean("Send the invoice to Mark. Scratch that, send it to Sara.") == "Send it to Sara."


def test_oops_correction_keeps_following_sentence():
    assert (
        clean("Hi, I am here to see what you guys need. Oops, correction. I am here to see what you guys want.")
        == "I am here to see what you guys want."
    )


def test_spoken_quote_commands_become_punctuation():
    assert clean("open quote hello there close quote") == '"hello there".'


def test_spoken_basic_punctuation_commands_become_punctuation():
    assert clean("hello comma Michael question mark") == "Hello, Michael?"


def test_dictionary_terms_preserve_configured_casing():
    assert clean_transcript(
        CleanupRequest(
            raw_transcript="omnivoice works with qwen",
            style="neutral",
            dictionary_terms=["OmniVoice", "Qwen"],
        )
    ).text == "OmniVoice works with Qwen."


def test_concise_removes_leading_filler():
    assert (
        clean("um I just wanted to say that we should ship this today", "concise")
        == "We should ship this today."
    )


def test_raw_style_only_trims_spacing():
    assert clean("  um I mean keep these words  ", "raw") == "um I mean keep these words"


def test_strips_codex_follow_up_placeholder_suffix():
    assert clean("Fix this permanently. Ask for follow-up changes") == "Fix this permanently."


def test_strips_claude_command_placeholder_suffix():
    assert clean("Open the release notes. Type / for commands") == "Open the release notes."


def test_strips_spoken_claude_command_placeholder_suffix():
    assert clean("Open the release notes. Type slash for commands") == "Open the release notes."
