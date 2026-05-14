from omnivoice_engine.cleanup import clean_transcript
from omnivoice_engine.schemas import CleanupRequest


def clean(raw: str, style: str = "neutral") -> str:
    return clean_transcript(CleanupRequest(raw_transcript=raw, style=style)).text


def test_no_wait_replaces_abandoned_clause():
    assert (
        clean("I'm going to go to the store. No wait, I'm going to go to the house.")
        == "I'm going to go to the house."
    )


def test_actually_replaces_date():
    assert clean("Schedule it for Monday, actually Tuesday.") == "Schedule it for Tuesday."


def test_scratch_that_keeps_following_sentence():
    assert clean("Send the invoice to Mark. Scratch that, send it to Sara.") == "Send it to Sara."


def test_concise_removes_leading_filler():
    assert (
        clean("um I just wanted to say that we should ship this today", "concise")
        == "We should ship this today."
    )


def test_raw_style_only_trims_spacing():
    assert clean("  um I mean keep these words  ", "raw") == "um I mean keep these words"
