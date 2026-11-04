from omnivoice_engine.runtime_store import RuntimeStore


def test_recent_transcripts_uses_tail_read_without_full_file_decode(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    store.record_transcript(source="stream", raw_text="first")
    store.record_transcript(source="stream", raw_text="second")
    store.record_transcript(source="stream", raw_text="third")

    def reject_full_file_read(_path):
        raise AssertionError("recent reads should not decode the whole JSONL file")

    monkeypatch.setattr(store, "_read_lines", reject_full_file_read)

    recent = store.recent_transcripts(2)

    assert [transcript.raw_text for transcript in recent] == ["third", "second"]


def test_line_counts_do_not_decode_full_jsonl_files(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    store.record_event("one", "First")
    store.record_event("two", "Second")

    def reject_full_file_read(_path):
        raise AssertionError("line counts should not decode the whole JSONL file")

    monkeypatch.setattr(store, "_read_lines", reject_full_file_read)

    assert store.event_count() == 2


def test_recent_transcripts_skips_malformed_tail_lines(tmp_path):
    store = RuntimeStore(tmp_path)
    store.record_transcript(source="stream", raw_text="first")
    store.record_transcript(source="stream", raw_text="second")
    store.transcripts_path.open("a", encoding="utf-8").write("{not-json}\n")

    recent = store.recent_transcripts(2)

    assert [transcript.raw_text for transcript in recent] == ["second", "first"]
