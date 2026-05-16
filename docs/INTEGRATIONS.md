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

OmniVoice works in Codex through the same macOS Accessibility insertion path. It strips known Codex follow-up placeholder text and keeps the cursor after inserted text.

Useful defaults:

- Use `Raw Dictation` for code, shell commands, and exact file names.
- Use `Command, undo last dictation` if an inserted prompt needs to be removed.
- Use the Personal Dictionary for repo names, model names, and project-specific terms.

## Local API

The local engine API is available at `http://127.0.0.1:8765`.

Useful endpoints:

- `GET /health`
- `GET /api/status`
- `GET /api/transcripts`
- `GET /api/events`
- `POST /api/desktop-app/start`
- `POST /cleanup`
