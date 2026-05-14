from fastapi.testclient import TestClient
from omnivoice_engine.main import app


client = TestClient(app)


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_cleanup_endpoint():
    response = client.post(
        "/cleanup",
        json={
            "raw_transcript": "Schedule it for Monday, actually Tuesday.",
            "style": "neutral",
            "dictionary_terms": [],
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Schedule it for Tuesday.",
        "cleanup_applied": True,
    }


def test_providers_endpoint_includes_fake():
    response = client.get("/providers")

    assert response.status_code == 200
    assert {"id": "fake", "label": "Fake ASR", "available": True, "reason": None} in response.json()


def test_transcribe_endpoint_uses_fake_provider():
    response = client.post("/transcribe?provider=fake", content=b"audio-bytes")

    assert response.status_code == 200
    assert response.json() == {"text": "fake transcript", "provider": "fake"}


def test_stream_endpoint_emits_partial_and_final_caption():
    with client.websocket_connect("/stream?provider=fake&sample_rate=16000") as websocket:
        assert websocket.receive_json() == {"type": "partial", "text": "listening"}

        websocket.send_bytes(b"0" * 4096)
        assert websocket.receive_json() == {"type": "partial", "text": "fake transcript"}

        websocket.send_text("__finish__")
        assert websocket.receive_json() == {"type": "final", "text": "fake transcript"}
