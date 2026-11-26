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
            raw_transcript="omnispeak works with qwen",
            style="neutral",
            dictionary_terms=["OmniSpeak", "Qwen"],
        )
    ).text == "OmniSpeak works with Qwen."


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


def test_preserves_normal_use_of_actually():
    assert clean("That's actually really helpful") == "That's actually really helpful."
    assert clean("Actually, I agree with you") == "Actually, I agree with you."


def test_actually_inline_replacement_handles_times_and_recipients():
    assert clean("Meet at 2pm, actually 3pm") == "Meet at 3pm."
    assert clean("Send it to Mark, actually Sara") == "Send it to Sara."


def test_concise_strips_mid_sentence_fillers_without_mangling_like():
    assert (
        clean("I was, um, thinking that, like, we should ship this, you know", "concise")
        == "I was thinking that we should ship this."
    )
    assert clean("I like coffee and I uh like tea", "concise") == "I like coffee and I like tea."


def test_professional_style_polishes_casual_speech():
    assert (
        clean("Hey so I'm gonna wanna send this kinda soon", "professional")
        == "I'm going to want to send this kind of soon."
    )


def test_capitalizes_multiple_sentences_and_pronoun_i_while_preserving_dictionary_and_filenames():
    result = clean_transcript(
        CleanupRequest(
            raw_transcript="macos runs great. i think i'm ready to ship main.py now",
            style="neutral",
            dictionary_terms=["macOS"],
        )
    )
    assert result.text == "macOS runs great. I think I'm ready to ship main.py now."


def test_build_llm_cleanup_messages_includes_context_and_vocabulary():
    from omnivoice_engine.cleanup import build_llm_cleanup_messages

    messages = build_llm_cleanup_messages(
        CleanupRequest(
            raw_transcript="test",
            style="professional",
            dictionary_terms=["OmniSpeak"],
            dictionary_entries=[{"canonical": "Figma", "aliases": ["fig ma"], "enabled": True}],
            app_context="Mail",
        ),
        "Test.",
    )
    assert messages[0]["role"] == "system"
    assert "Mail" in messages[0]["content"]
    assert "OmniSpeak" in messages[0]["content"]
    assert "Figma" in messages[0]["content"]
    assert messages[1] == {"role": "user", "content": "Test."}


def test_sanitize_llm_cleanup_output_strips_wrappers_and_enforces_dictionary():
    from omnivoice_engine.cleanup import sanitize_llm_cleanup_output

    assert (
        sanitize_llm_cleanup_output(
            '"Ship fig ma with omnispeak."',
            raw_transcript="ship fig ma with omnispeak",
            dictionary_terms=["OmniSpeak"],
            dictionary_entries=[{"canonical": "Figma", "aliases": ["fig ma"], "enabled": True}],
        )
        == "Ship Figma with OmniSpeak."
    )
    assert (
        sanitize_llm_cleanup_output(
            "```\nClean text.\n```",
            raw_transcript="clean text",
            dictionary_terms=[],
            dictionary_entries=[],
        )
        == "Clean text."
    )
