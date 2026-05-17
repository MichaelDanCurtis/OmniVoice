# OmniVoice Integrations

## Raycast

Raycast Script Commands live in `integrations/raycast`.

They use the local engine API to show status, open the dashboard, open transcripts, and launch the desktop app.

## Claude Desktop

OmniVoice works well in Claude Desktop as a normal text insertion utility. The app now strips Claude's `Type / for commands` placeholder when that hint appears as field content or transcript suffix.

Useful defaults:

- Use `Neutral` or `Concise` style.
- Say `Command, open Claude` if Claude is installed as `Claude.app`.
- Use `Raw Dictation` for prompts that include code, file paths, or exact commands.

## Codex

OmniVoice treats Codex as a rich composer. Live dictation stays in the caret-attached caption overlay, and final text is inserted through pasteboard-style insertion so Codex plugin chips are not flattened into prompt text. It still strips known Codex follow-up placeholder text when that hint appears as field content or transcript suffix.

Useful defaults:

- Use `Raw Dictation` for code, shell commands, and exact file names.
- Use the app's normal undo if a pasteboard-style insertion needs to be removed.
- Use the Personal Dictionary for repo names, model names, and project-specific terms.

## AI Handoff

OmniVoice can route explicit AI commands through any OpenAI-compatible chat completions endpoint. Configure the endpoint in Settings -> Integrations:

- Base URL, for example `https://openrouter.ai/api/v1` or a local OpenAI-compatible server.
- Model, for example `anthropic/claude-sonnet` or a local model name.
- API Key, if the endpoint requires one.

Supported phrases:

- `Ask Claude, write a quick reply to Jane`
- `Hey Codex, summarize this in two sentences`
- `Have OpenRouter take a look at this and respond in Spanish`
- `Ask OpenAI, make this sound more professional`

If text is selected when dictation starts, OmniVoice sends the selected text as foreground context. OAuth-specific Codex, Claude, Copilot, and provider-native account integrations are still planned; the active implementation is OpenAI-compatible API access.

## Local API

The local engine API is available at `http://127.0.0.1:8765`.

Useful endpoints:

- `GET /health`
- `GET /api/status`
- `GET /api/transcripts`
- `GET /api/events`
- `POST /api/desktop-app/start`
- `POST /api/ai/handoff`
- `POST /cleanup`
