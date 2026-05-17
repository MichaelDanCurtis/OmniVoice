import json

import pytest
from fastapi.testclient import TestClient

from omnivoice_engine.main import app
from omnivoice_engine.runtime_store import RuntimeStore


client = TestClient(app)


def create_session(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    return client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()


def test_conversation_session_round_trip(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)

    response = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    )

    assert response.status_code == 200
    session = response.json()
    assert session["title"] == "Roadmap call"
    assert session["capture_mode"] == "microphone_only"
    assert session["ended_at"] is None

    history = client.get("/api/conversations").json()
    assert history[0]["id"] == session["id"]


def test_conversation_segments_and_assist_cards(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()

    segment_response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
    )
    card_response = client.post(
        f"/api/conversations/{session['id']}/assist-cards",
        json={
            "kind": "answer",
            "title": "Answer Found",
            "body": "Last year we had 18,420 active users.",
            "source_references": ["Obsidian/adoption-2025.md"],
            "confidence": 0.78,
        },
    )

    assert segment_response.status_code == 200
    assert card_response.status_code == 200

    detail = client.get(f"/api/conversations/{session['id']}").json()
    assert detail["session"]["id"] == session["id"]
    assert detail["segments"][0]["text"] == "How many users did we have last year?"
    assert detail["assist_cards"][0]["body"] == "Last year we had 18,420 active users."


def test_conversation_stop_sets_ended_at(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()

    response = client.post(f"/api/conversations/{session['id']}/stop")

    assert response.status_code == 200
    assert response.json()["ended_at"] is not None


@pytest.mark.parametrize(
    "payload",
    [
        {
            "title": "Roadmap call",
            "capture_mode": " ",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
        {
            "title": "Roadmap call",
            "capture_mode": "unsupported",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
        {
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": " ",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
        {
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "",
            "external_processing_enabled": False,
        },
    ],
)
def test_invalid_conversation_session_payloads_return_422(monkeypatch, tmp_path, payload):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)

    response = client.post("/api/conversations", json=payload)

    assert response.status_code == 422


@pytest.mark.parametrize(
    "payload",
    [
        {
            "speaker_id": "",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": " ",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": " ",
            "state": "settled",
            "confidence": 0.91,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": -1,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": -1,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 18129,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "unknown",
            "confidence": 0.91,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 1.1,
        },
        {
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": -0.1,
        },
    ],
)
def test_invalid_conversation_segment_payloads_return_422(monkeypatch, tmp_path, payload):
    session = create_session(monkeypatch, tmp_path)

    response = client.post(f"/api/conversations/{session['id']}/segments", json=payload)

    assert response.status_code == 422


@pytest.mark.parametrize(
    "payload",
    [
        {
            "kind": "unsupported",
            "title": "Answer Found",
            "body": "Last year we had 18,420 active users.",
            "source_references": ["Obsidian/adoption-2025.md"],
            "confidence": 0.78,
        },
        {
            "kind": "answer",
            "title": "Answer Found",
            "body": "Last year we had 18,420 active users.",
            "source_references": ["Obsidian/adoption-2025.md"],
            "confidence": 1.1,
        },
        {
            "kind": "answer",
            "title": "Answer Found",
            "body": "Last year we had 18,420 active users.",
            "source_references": ["Obsidian/adoption-2025.md"],
            "confidence": -0.1,
        },
    ],
)
def test_invalid_conversation_assist_card_payloads_return_422(monkeypatch, tmp_path, payload):
    session = create_session(monkeypatch, tmp_path)

    response = client.post(f"/api/conversations/{session['id']}/assist-cards", json=payload)

    assert response.status_code == 422


def test_recent_conversation_sessions_ignores_malformed_trailing_lines(tmp_path):
    store = RuntimeStore(tmp_path)
    sessions = [
        store.create_conversation_session(
            title=f"Conversation {index}",
            capture_mode="microphone_only",
            asr_provider="parakeet-tdt",
            diarization_provider="mock",
            external_processing_enabled=False,
        )
        for index in range(4)
    ]
    with store.conversation_sessions_path.open("a", encoding="utf-8") as handle:
        handle.write("{not-valid-json}\n")
        handle.write(json.dumps({"not": "a conversation"}) + "\n")

    recent = store.recent_conversation_sessions(limit=3)

    assert [session.id for session in recent] == [session.id for session in reversed(sessions[-3:])]


def test_conversation_detail_ignores_invalid_segment_and_assist_card_rows(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()
    client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
    )
    client.post(
        f"/api/conversations/{session['id']}/assist-cards",
        json={
            "kind": "answer",
            "title": "Answer Found",
            "body": "Last year we had 18,420 active users.",
            "source_references": ["Obsidian/adoption-2025.md"],
            "confidence": 0.78,
        },
    )
    with store.conversation_segments_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"session_id": session["id"], "text": "missing required fields"}) + "\n")
    with store.conversation_assist_cards_path.open("a", encoding="utf-8") as handle:
        handle.write(
            json.dumps(
                {
                    "id": "bad-card",
                    "session_id": session["id"],
                    "kind": "answer",
                    "title": "Bad Card",
                    "body": "Bad card",
                    "status": "unsupported",
                    "created_at": "2026-05-17T08:00:00Z",
                }
            )
            + "\n"
        )

    response = client.get(f"/api/conversations/{session['id']}")

    assert response.status_code == 200
    detail = response.json()
    assert len(detail["segments"]) == 1
    assert len(detail["assist_cards"]) == 1


def test_conversation_export_returns_text(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "mock",
            "external_processing_enabled": False,
        },
    ).json()
    client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "confidence": 0.91,
        },
    )

    response = client.get(f"/api/conversations/{session['id']}/export")

    assert response.status_code == 200
    assert "Speaker 1 [00:18]" in response.text
    assert "How many users did we have last year?" in response.text
