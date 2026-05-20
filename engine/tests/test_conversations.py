import json
from base64 import b64encode

import pytest
from fastapi.testclient import TestClient

from omnivoice_engine.diarization import DiarizationProvider, SpeakerAssignment
from omnivoice_engine.main import app
from omnivoice_engine.providers.base import ASRToken, ASRTranscript
from omnivoice_engine.runtime_store import RuntimeStore
from omnivoice_engine.schemas import ProviderInfo


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


def test_conversation_update_renames_speaker_everywhere_and_edits_text(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = create_session(monkeypatch, tmp_path)
    first = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 1000,
            "end_ms": 2200,
            "text": "Hello from speaker one.",
            "state": "settled",
        },
    ).json()
    second = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 2400,
            "end_ms": 3200,
            "text": "Second line.",
            "state": "settled",
        },
    ).json()

    response = client.patch(
        f"/api/conversations/{session['id']}",
        json={
            "title": "Edited roadmap call",
            "speaker_names": {"speaker-1": "Mike"},
            "segments": [
                {"id": first["id"], "text": "Hello from Mike."},
                {"id": second["id"], "text": "Second line."},
            ],
        },
    )

    assert response.status_code == 200
    detail = response.json()
    assert detail["session"]["title"] == "Edited roadmap call"
    assert [segment["speaker_display_name"] for segment in detail["segments"]] == ["Mike", "Mike"]
    assert detail["segments"][0]["text"] == "Hello from Mike."


def test_conversation_update_rejects_unknown_segment(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = create_session(monkeypatch, tmp_path)

    response = client.patch(
        f"/api/conversations/{session['id']}",
        json={"segments": [{"id": "missing-segment", "text": "Nope."}]},
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "conversation segment not found: missing-segment"


def test_conversation_delete_removes_session_segments_and_assists(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = create_session(monkeypatch, tmp_path)
    client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "speaker_id": "speaker-1",
            "speaker_display_name": "Speaker 1",
            "start_ms": 1000,
            "end_ms": 2200,
            "text": "Delete me.",
            "state": "settled",
        },
    )
    client.post(
        f"/api/conversations/{session['id']}/assist-cards",
        json={
            "kind": "answer",
            "title": "Delete answer",
            "body": "Delete body.",
            "source_references": [],
        },
    )

    response = client.delete(f"/api/conversations/{session['id']}")

    assert response.status_code == 200
    assert response.json() == {"status": "deleted", "session_id": session["id"]}
    assert client.get("/api/conversations").json() == []
    assert client.get(f"/api/conversations/{session['id']}").status_code == 404
    assert store.conversation_segments(session["id"]) == []
    assert store.conversation_assist_cards(session["id"]) == []


def test_conversation_import_rebuilds_session_segments_and_assists(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)

    detail = {
        "session": {
            "id": "archived-session",
            "title": "Archived call",
            "started_at": "2026-05-20T08:00:00+00:00",
            "ended_at": "2026-05-20T08:15:00+00:00",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt-mlx",
            "diarization_provider": "mlx-sortformer-streaming-fp32",
            "external_processing_enabled": False,
        },
        "segments": [
            {
                "id": "archived-segment",
                "session_id": "archived-session",
                "speaker_id": "speaker-1",
                "speaker_display_name": "Speaker 1",
                "start_ms": 1000,
                "end_ms": 2200,
                "text": "Imported from disk.",
                "state": "settled",
                "confidence": 0.9,
                "speaker_turns": [],
                "speaker_lines": [],
            }
        ],
        "assist_cards": [
            {
                "id": "archived-card",
                "session_id": "archived-session",
                "kind": "answer",
                "title": "Imported answer",
                "body": "This came from the archive.",
                "source_references": [],
                "confidence": 0.8,
                "status": "active",
                "created_at": "2026-05-20T08:16:00+00:00",
            }
        ],
    }

    response = client.post("/api/conversations/import", json=detail)

    assert response.status_code == 200
    assert response.json() == {
        "status": "created",
        "session_id": "archived-session",
        "segments": 1,
        "assist_cards": 1,
    }
    restored = client.get("/api/conversations/archived-session").json()
    assert restored["session"]["title"] == "Archived call"
    assert restored["segments"][0]["text"] == "Imported from disk."
    assert restored["assist_cards"][0]["title"] == "Imported answer"

    detail["session"]["title"] = "Updated archived call"
    detail["segments"][0]["text"] = "Updated from disk."
    update_response = client.post("/api/conversations/import", json=detail)

    assert update_response.status_code == 200
    assert update_response.json()["status"] == "updated"
    restored = client.get("/api/conversations/archived-session").json()
    assert restored["session"]["title"] == "Updated archived call"
    assert restored["segments"][0]["text"] == "Updated from disk."
    assert len(restored["segments"]) == 1


def test_conversation_segment_without_speaker_uses_local_diarization(monkeypatch, tmp_path):
    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "local-heuristic",
            "external_processing_enabled": False,
        },
    ).json()

    first_response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "start_ms": 1000,
            "end_ms": 3200,
            "text": "How many users did we have last year?",
            "state": "settled",
        },
    )
    second_response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "start_ms": 3400,
            "end_ms": 5100,
            "text": "We had eighteen thousand active users.",
            "state": "settled",
        },
    )

    assert first_response.status_code == 200
    assert first_response.json()["speaker_id"] == "speaker-1"
    assert first_response.json()["speaker_display_name"] == "Speaker 1"
    assert second_response.status_code == 200
    assert second_response.json()["speaker_id"] == "speaker-2"
    assert second_response.json()["speaker_display_name"] == "Speaker 2"
    assert any(event.kind == "diarization.assigned" for event in store.recent_events(10))


def test_conversation_segment_with_audio_payload_reaches_local_diarizer(monkeypatch, tmp_path):
    class AudioAwareDiarizer(DiarizationProvider):
        id = "audio-aware"
        label = "Audio Aware"

        def info(self):
            return ProviderInfo(id=self.id, label=self.label, available=True)

        def assign_speaker(
            self,
            *,
            session_id,
            text,
            start_ms,
            end_ms,
            existing_segments,
            audio,
        ):
            assert audio is not None
            assert audio.pcm_float32 == b"pcm-window!!"
            assert audio.sample_rate == 16000
            assert audio.start_ms == 250
            assert audio.end_ms == 3200
            return SpeakerAssignment("audio-speaker", "Audio Speaker", confidence=0.82)

    class AudioAwareRegistry:
        def get(self, provider_id):
            assert provider_id == "audio-aware"
            return AudioAwareDiarizer()

    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.diarization_registry", AudioAwareRegistry(), raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "audio-aware",
            "external_processing_enabled": False,
        },
    ).json()

    response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "start_ms": 1000,
            "end_ms": 3200,
            "text": "That was Bob speaking.",
            "state": "settled",
            "audio_start_ms": 250,
            "audio_pcm_float32_base64": b64encode(b"pcm-window!!").decode("ascii"),
            "audio_sample_rate": 16000,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["speaker_id"] == "audio-speaker"
    assert payload["speaker_display_name"] == "Audio Speaker"
    assert payload["confidence"] == 0.82


def test_conversation_segment_preserves_diarization_speaker_turns(monkeypatch, tmp_path):
    class TurnAwareAssignment:
        speaker_id = "speaker-2"
        speaker_display_name = "Speaker 2"
        confidence = 0.74
        speaker_turns = [
            {
                "speaker_id": "speaker-1",
                "start_ms": 250,
                "end_ms": 1200,
                "confidence": 0.81,
                "overlap": False,
                "source_provider": "turn-aware",
            },
            {
                "speaker_id": "speaker-2",
                "start_ms": 1200,
                "end_ms": 3200,
                "confidence": 0.74,
                "overlap": False,
                "source_provider": "turn-aware",
            },
        ]

    class TurnAwareDiarizer(DiarizationProvider):
        id = "turn-aware"
        label = "Turn Aware"

        def info(self):
            return ProviderInfo(id=self.id, label=self.label, available=True)

        def assign_speaker(self, **_kwargs):
            return TurnAwareAssignment()

    class TurnAwareRegistry:
        def get(self, provider_id):
            assert provider_id == "turn-aware"
            return TurnAwareDiarizer()

    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.diarization_registry", TurnAwareRegistry(), raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "turn-aware",
            "external_processing_enabled": False,
        },
    ).json()

    response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "start_ms": 1000,
            "end_ms": 3200,
            "text": "Bob asked a question and Sarah answered it.",
            "state": "settled",
            "audio_start_ms": 250,
            "audio_pcm_float32_base64": b64encode(b"pcm-window!!").decode("ascii"),
            "audio_sample_rate": 16000,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["speaker_id"] == "speaker-2"
    assert [turn["speaker_id"] for turn in payload["speaker_turns"]] == ["speaker-1", "speaker-2"]

    detail = client.get(f"/api/conversations/{session['id']}").json()
    assert detail["segments"][0]["speaker_turns"] == payload["speaker_turns"]


def test_conversation_segment_stores_speaker_lines_from_aligned_asr(monkeypatch, tmp_path):
    class TurnAwareAssignment:
        speaker_id = "speaker-2"
        speaker_display_name = "Speaker 2"
        confidence = 0.74
        speaker_turns = [
            {"speaker_id": "speaker-1", "start_ms": 250, "end_ms": 1250, "confidence": 0.81},
            {"speaker_id": "speaker-2", "start_ms": 1250, "end_ms": 3250, "confidence": 0.74},
        ]

    class TurnAwareDiarizer(DiarizationProvider):
        id = "turn-aware"
        label = "Turn Aware"

        def info(self):
            return ProviderInfo(id=self.id, label=self.label, available=True)

        def assign_speaker(self, **_kwargs):
            return TurnAwareAssignment()

    class TurnAwareRegistry:
        def get(self, provider_id):
            assert provider_id == "turn-aware"
            return TurnAwareDiarizer()

    class AlignedASR:
        def transcribe_aligned_pcm_float32(self, pcm_bytes, sample_rate):
            assert pcm_bytes == b"pcm-window!!"
            assert sample_rate == 16000
            return ASRTranscript(
                text="Bob asked a question. Sarah answered it.",
                tokens=(
                    ASRToken(text="Bob", start_ms=0, end_ms=300, confidence=0.92),
                    ASRToken(text=" asked", start_ms=300, end_ms=600, confidence=0.91),
                    ASRToken(text=" a question.", start_ms=600, end_ms=1_000, confidence=0.9),
                    ASRToken(text=" Sarah", start_ms=1_000, end_ms=1_400, confidence=0.88),
                    ASRToken(text=" answered it.", start_ms=1_400, end_ms=2_500, confidence=0.86),
                ),
            )

    class ASRRegistry:
        def get(self, provider_id):
            assert provider_id == "aligned-asr"
            return AlignedASR()

    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.diarization_registry", TurnAwareRegistry(), raising=False)
    monkeypatch.setattr("omnivoice_engine.main.registry", ASRRegistry(), raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "aligned-asr",
            "diarization_provider": "turn-aware",
            "external_processing_enabled": False,
        },
    ).json()

    response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "start_ms": 1000,
            "end_ms": 3200,
            "text": "Bob asked a question and Sarah answered it.",
            "state": "settled",
            "audio_start_ms": 250,
            "audio_pcm_float32_base64": b64encode(b"pcm-window!!").decode("ascii"),
            "audio_sample_rate": 16000,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert [line["speaker_id"] for line in payload["speaker_lines"]] == ["speaker-1", "speaker-2"]
    assert [line["text"] for line in payload["speaker_lines"]] == [
        "Bob asked a question.",
        "Sarah answered it.",
    ]

    detail = client.get(f"/api/conversations/{session['id']}").json()
    assert detail["segments"][0]["speaker_lines"] == payload["speaker_lines"]


def test_conversation_segment_preview_returns_diarization_without_persisting(monkeypatch, tmp_path):
    class TurnAwareAssignment:
        speaker_id = "speaker-1"
        speaker_display_name = "Speaker 1"
        confidence = 0.81
        speaker_turns = [
            {"speaker_id": "speaker-1", "start_ms": 0, "end_ms": 900, "confidence": 0.81},
            {"speaker_id": "speaker-2", "start_ms": 900, "end_ms": 1800, "confidence": 0.76},
        ]

    class TurnAwareDiarizer(DiarizationProvider):
        id = "turn-aware"
        label = "Turn Aware"

        def info(self):
            return ProviderInfo(id=self.id, label=self.label, available=True)

        def assign_speaker(self, **kwargs):
            assert kwargs["audio"].pcm_float32 == b"pcm-window!!"
            return TurnAwareAssignment()

    class TurnAwareRegistry:
        def get(self, provider_id):
            assert provider_id == "turn-aware"
            return TurnAwareDiarizer()

    class AlignedASR:
        def transcribe_aligned_pcm_float32(self, pcm_bytes, sample_rate):
            assert pcm_bytes == b"pcm-window!!"
            assert sample_rate == 16000
            return ASRTranscript(
                text="Bob asked. Sarah answered.",
                tokens=(
                    ASRToken(text="Bob", start_ms=0, end_ms=250, confidence=0.92),
                    ASRToken(text=" asked.", start_ms=250, end_ms=800, confidence=0.91),
                    ASRToken(text=" Sarah", start_ms=900, end_ms=1_150, confidence=0.88),
                    ASRToken(text=" answered.", start_ms=1_150, end_ms=1_700, confidence=0.86),
                ),
            )

    class ASRRegistry:
        def get(self, provider_id):
            assert provider_id == "aligned-asr"
            return AlignedASR()

    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.diarization_registry", TurnAwareRegistry(), raising=False)
    monkeypatch.setattr("omnivoice_engine.main.registry", ASRRegistry(), raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "aligned-asr",
            "diarization_provider": "turn-aware",
            "external_processing_enabled": False,
        },
    ).json()

    response = client.post(
        f"/api/conversations/{session['id']}/segments/preview",
        json={
            "start_ms": 0,
            "end_ms": 1800,
            "text": "Bob asked and Sarah answered.",
            "state": "live",
            "audio_start_ms": 0,
            "audio_pcm_float32_base64": b64encode(b"pcm-window!!").decode("ascii"),
            "audio_sample_rate": 16000,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == f"live-{session['id']}"
    assert payload["state"] == "live"
    assert [turn["speaker_id"] for turn in payload["speaker_turns"]] == ["speaker-1", "speaker-2"]
    assert [line["speaker_id"] for line in payload["speaker_lines"]] == ["speaker-1", "speaker-2"]
    assert [line["text"] for line in payload["speaker_lines"]] == ["Bob asked.", "Sarah answered."]
    assert client.get(f"/api/conversations/{session['id']}").json()["segments"] == []


def test_conversation_segment_uses_preview_speakers_when_final_diarization_collapses(monkeypatch, tmp_path):
    class PreviewAwareDiarizer(DiarizationProvider):
        id = "preview-aware"
        label = "Preview Aware"

        def info(self):
            return ProviderInfo(id=self.id, label=self.label, available=True)

        def assign_speaker(self, **kwargs):
            if kwargs["text"].startswith("Preview"):
                return SpeakerAssignment(
                    speaker_id="speaker-2",
                    speaker_display_name="Speaker 2",
                    confidence=0.82,
                    speaker_turns=(
                        {"speaker_id": "speaker-1", "start_ms": 0, "end_ms": 900, "confidence": 0.81},
                        {"speaker_id": "speaker-2", "start_ms": 900, "end_ms": 1800, "confidence": 0.76},
                    ),
                )

            return SpeakerAssignment(
                speaker_id="speaker-1",
                speaker_display_name="Speaker 1",
                confidence=0.7,
                speaker_turns=(
                    {"speaker_id": "speaker-1", "start_ms": 0, "end_ms": 1800, "confidence": 0.7},
                ),
            )

    class PreviewAwareRegistry:
        def get(self, provider_id):
            assert provider_id == "preview-aware"
            return PreviewAwareDiarizer()

    class AlignedASR:
        def transcribe_aligned_pcm_float32(self, _pcm_bytes, sample_rate):
            assert sample_rate == 16000
            return ASRTranscript(
                text="Bob asked. Sarah answered.",
                tokens=(
                    ASRToken(text="Bob", start_ms=0, end_ms=300, confidence=0.92),
                    ASRToken(text=" asked.", start_ms=300, end_ms=800, confidence=0.91),
                    ASRToken(text=" Sarah", start_ms=900, end_ms=1_150, confidence=0.88),
                    ASRToken(text=" answered.", start_ms=1_150, end_ms=1_700, confidence=0.86),
                ),
            )

    class ASRRegistry:
        def get(self, provider_id):
            assert provider_id == "aligned-asr"
            return AlignedASR()

    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.diarization_registry", PreviewAwareRegistry(), raising=False)
    monkeypatch.setattr("omnivoice_engine.main.registry", ASRRegistry(), raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "aligned-asr",
            "diarization_provider": "preview-aware",
            "external_processing_enabled": False,
        },
    ).json()

    preview_response = client.post(
        f"/api/conversations/{session['id']}/segments/preview",
        json={
            "start_ms": 0,
            "end_ms": 1800,
            "text": "Preview Bob asked and Sarah answered.",
            "state": "live",
            "audio_start_ms": 0,
            "audio_pcm_float32_base64": b64encode(b"preview-pcm!").decode("ascii"),
            "audio_sample_rate": 16000,
        },
    )
    assert preview_response.status_code == 200

    final_response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "start_ms": 0,
            "end_ms": 1800,
            "text": "Final Bob asked and Sarah answered.",
            "state": "settled",
            "audio_start_ms": 0,
            "audio_pcm_float32_base64": b64encode(b"final-pcm!!!").decode("ascii"),
            "audio_sample_rate": 16000,
        },
    )

    assert final_response.status_code == 200
    payload = final_response.json()
    assert [turn["speaker_id"] for turn in payload["speaker_turns"]] == ["speaker-1", "speaker-2"]
    assert [line["speaker_id"] for line in payload["speaker_lines"]] == ["speaker-1", "speaker-2"]
    assert [line["text"] for line in payload["speaker_lines"]] == ["Bob asked.", "Sarah answered."]


def test_conversation_segment_preserves_transcript_when_diarization_fails(monkeypatch, tmp_path):
    class ExplodingDiarizer(DiarizationProvider):
        id = "exploding"
        label = "Exploding"

        def info(self):
            return ProviderInfo(id=self.id, label=self.label, available=True)

        def assign_speaker(self, **_kwargs):
            raise RuntimeError("model exploded")

    class ExplodingRegistry:
        def get(self, provider_id):
            assert provider_id == "exploding"
            return ExplodingDiarizer()

    store = RuntimeStore(tmp_path)
    monkeypatch.setattr("omnivoice_engine.main.runtime_store", store, raising=False)
    monkeypatch.setattr("omnivoice_engine.main.diarization_registry", ExplodingRegistry(), raising=False)
    session = client.post(
        "/api/conversations",
        json={
            "title": "Roadmap call",
            "capture_mode": "microphone_only",
            "asr_provider": "parakeet-tdt",
            "diarization_provider": "exploding",
            "external_processing_enabled": False,
        },
    ).json()

    response = client.post(
        f"/api/conversations/{session['id']}/segments",
        json={
            "start_ms": 1000,
            "end_ms": 3200,
            "text": "This line still needs to be saved.",
            "state": "settled",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["speaker_id"] == "speaker"
    assert payload["speaker_display_name"] == "Speaker"
    assert payload["text"] == "This line still needs to be saved."
    assert any(event.kind == "diarization.failed" for event in store.recent_events(10))


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
        {
            "start_ms": 18130,
            "end_ms": 21900,
            "text": "How many users did we have last year?",
            "state": "settled",
            "audio_pcm_float32_base64": "cGNt",
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
