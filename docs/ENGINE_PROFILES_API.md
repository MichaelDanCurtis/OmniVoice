# OmniVoice Engine — Multi-App Layered Settings Profiles API

`omnivoice-engine` (Rust, `http://127.0.0.1:8765`) provides an **additive, profile-layered voice configuration API** stored inside `omnivoice.db` (`voice_settings_profiles` table) so multiple desktop/CLI apps (**OmniSpeak**, **Inferno**, **Spark**, **OmniDraw**, etc.) can share one local voice daemon while optionally maintaining independent per-app settings.

> **Compatibility guarantee for OmniSpeak.app:** This API is 100% additive. Existing `OmniSpeak.app` preferences (`com.omnispeak.OmniVoiceApp`), routes, tables, and `EngineSupervisor` launch flow are completely unchanged.

## Authentication
On startup, when `OMNIVOICE_ENGINE_TOKEN` is set, `omnivoice-engine` writes the active session token to:
```
~/Library/Application Support/OmniSpeak/engine-data/engine-token   (mode 0600)
```
Local sibling apps owned by the user pass it in header `X-OmniSpeak-Engine-Token`.

## Profile Inheritance Model
- **`default`**: Shared global baseline inherited by every app in `"shared"` mode.
- **`<app_id>`** (e.g. `inferno`, `omnispeak`, `spark`, `omnidraw`, matching `^[a-z0-9_-]{1,48}$`): Optional per-app sparse override merged on top of `default` (including nested `service_mode` merge; `null` removes an overridden key).

## Endpoints

| Method | Path | Behavior |
|---|---|---|
| `GET` | `/api/settings?profile=<id>` | Returns `{ profileId, mode: "shared" \| "custom", effective, defaults, override, profiles, updatedAt }`. |
| `PATCH` | `/api/settings?profile=<id>` | Merges JSON object into `default` (shared) or `<id>` (custom override) and returns the resolved envelope. |
| `DELETE` | `/api/settings?profile=<id>` | Deletes `<id>`'s override so the app reverts to `"shared"` mode (`default` cannot be deleted). |
| `GET` | `/api/settings/profiles` | Lists all stored profile IDs and `updatedAt` timestamps. |

## Example
```bash
TOKEN=$(cat "$HOME/Library/Application Support/OmniSpeak/engine-data/engine-token")

# Read effective settings for Inferno
curl -H "X-OmniSpeak-Engine-Token: $TOKEN" \
  "http://127.0.0.1:8765/api/settings?profile=inferno"

# Give Inferno its own independent style + Deepgram Service Mode without touching OmniSpeak
curl -X PATCH -H "X-OmniSpeak-Engine-Token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"style":"concise","service_mode":{"enabled":true,"deepgram_model":"flux-general-en"}}' \
  "http://127.0.0.1:8765/api/settings?profile=inferno"

# Revert Inferno back to following the shared default profile
curl -X DELETE -H "X-OmniSpeak-Engine-Token: $TOKEN" \
  "http://127.0.0.1:8765/api/settings?profile=inferno"
```
