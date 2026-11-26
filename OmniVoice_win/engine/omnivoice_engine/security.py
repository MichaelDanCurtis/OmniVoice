from __future__ import annotations

import hmac
import os
from urllib.parse import urlparse

from fastapi import Request, WebSocket
from fastapi.responses import JSONResponse


ENGINE_AUTH_HEADER = "X-OmniSpeak-Engine-Token"
ENGINE_AUTH_COOKIE = "omnispeak_engine_token"
ALLOWED_LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1", "testserver"}


def configured_engine_token() -> str:
    return os.environ.get("OMNIVOICE_ENGINE_TOKEN", "").strip()


def extract_hostname(host_header: str | None) -> str:
    raw = (host_header or "").strip().lower()
    if not raw:
        return ""
    if raw.startswith("["):
        closing = raw.find("]")
        return raw[1:closing] if closing != -1 else raw
    if raw.count(":") == 1:
        return raw.split(":", 1)[0]
    return raw


def is_allowed_host(host_header: str | None) -> bool:
    hostname = extract_hostname(host_header)
    return not hostname or hostname in ALLOWED_LOCAL_HOSTS


def is_allowed_origin(origin_header: str | None) -> bool:
    raw = (origin_header or "").strip()
    if not raw:
        return True
    parsed = urlparse(raw)
    hostname = (parsed.hostname or "").lower()
    return hostname in ALLOWED_LOCAL_HOSTS


def token_matches(provided: str | None, expected: str) -> bool:
    candidate = (provided or "").strip()
    if not candidate or not expected:
        return False
    return hmac.compare_digest(candidate, expected)


def request_engine_token(request: Request) -> str | None:
    return (
        request.headers.get(ENGINE_AUTH_HEADER)
        or request.query_params.get("token")
        or request.cookies.get(ENGINE_AUTH_COOKIE)
    )


def websocket_engine_token(websocket: WebSocket) -> str | None:
    return (
        websocket.headers.get(ENGINE_AUTH_HEADER)
        or websocket.query_params.get("token")
        or websocket.cookies.get(ENGINE_AUTH_COOKIE)
    )


def check_http_security(request: Request) -> JSONResponse | None:
    if not is_allowed_host(request.headers.get("host")):
        return JSONResponse({"detail": "forbidden host"}, status_code=403)
    if not is_allowed_origin(request.headers.get("origin")):
        return JSONResponse({"detail": "forbidden origin"}, status_code=403)

    expected = configured_engine_token()
    path = request.url.path
    if expected and path != "/health" and not path.startswith("/assets/"):
        if not token_matches(request_engine_token(request), expected):
            return JSONResponse({"detail": "unauthorized"}, status_code=401)
    return None


def attach_dashboard_auth_cookie_if_needed(request: Request, response) -> None:
    expected = configured_engine_token()
    if expected and request.url.path == "/" and token_matches(request.query_params.get("token"), expected):
        response.set_cookie(
            key=ENGINE_AUTH_COOKIE,
            value=expected,
            httponly=True,
            samesite="strict",
        )


async def enforce_websocket_security(websocket: WebSocket) -> bool:
    if not is_allowed_host(websocket.headers.get("host")) or not is_allowed_origin(websocket.headers.get("origin")):
        await websocket.close(code=4403, reason="forbidden host or origin")
        return False
    expected = configured_engine_token()
    if expected and not token_matches(websocket_engine_token(websocket), expected):
        await websocket.close(code=4401, reason="unauthorized")
        return False
    return True
