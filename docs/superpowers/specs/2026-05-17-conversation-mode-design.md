# OmniVoice Conversation Mode Design

## Goal

Conversation Mode turns OmniVoice from a push-to-talk dictation tool into a live meeting recorder. It captures a live conversation, shows paragraph-style captions in real time, separates speakers when possible, and provides an assist rail that can surface useful answers without posting anything into the meeting.

The first version is a live experience, not an audio-file import workflow. File import can reuse the same transcript, diarization, and assist services later.

## Product Shape

Conversation Mode opens a dedicated window. It should feel like a meeting recorder, not like the small dictation overlay.

The main window has two primary regions:

1. A live transcript feed.
2. A right-side assist rail.

The live transcript feed uses the visual direction from mockup B: paragraph-style closed captions with a colored vertical speaker bar at the left of each paragraph. It should read like a live transcript rather than like one subtitle line at a time.

Each paragraph shows:

- timestamp
- speaker label
- colored speaker bar
- transcript text
- live or settled state when the text is still provisional

The assist rail uses the visual direction from mockup C, but it is active rather than just informational. It can detect questions, show found answers, provide time zone conversions, suggest follow-up questions, and expose source links.

## Capture Modes

Conversation Mode should support four capture configurations.

### Microphone Only

Use this for in-person conversations. Audio comes from the selected microphone. Diarization tries to separate people in the room into `Speaker 1`, `Speaker 2`, and so on.

### System/App Audio Only

Use this for meetings where the user is mostly listening. Audio comes from the computer, meeting app, browser tab, or system output capture path when available.

### Microphone Plus System/App Audio

This is the preferred meeting mode.

The user's microphone track is known as `You`. Remote audio is diarized separately. This avoids wasting diarization work on the local speaker and makes the transcript cleaner:

```text
You: Let's walk through the proposal.
Speaker 1: I had a question about pricing.
Speaker 2: The timeline looks good to me.
```

### Mixed Fallback

If source-separated capture is unavailable, OmniVoice records a mixed track and diarizes the full audio. This mode is less accurate but keeps Conversation Mode usable.

The UI must make the active capture mode visible because speaker confidence depends heavily on whether audio is source-separated.

## Transcription And Diarization Pipeline

Conversation Mode uses separate services for transcription and speaker labeling.

### ASR Layer

The ASR provider produces live text, timestamps, and final transcript segments. Parakeet remains the fast default ASR path. Canary or another provider can be used when accuracy or translation is more important than latency.

### Diarization Layer

The diarization provider estimates who spoke when. It emits time ranges, speaker IDs, confidence, and overlap information.

Base Parakeet TDT should not be treated as the diarization engine by itself. It can provide timestamps and text. A diarization provider such as Sortformer, Streaming Sortformer, or another compatible local model provides speaker turns.

### Alignment Layer

The alignment layer combines ASR output with diarization ranges. It assigns words or transcript segments to speaker turns and updates the live transcript when a speaker label changes.

This layer must support rolling correction. Real-time diarization will sometimes revise the last few seconds of speaker labels. The UI should allow recent speaker labels to settle rather than pretending they are final immediately.

### Identity Layer

Diarization labels are not real identities. `Speaker 1` means the model thinks a consistent voice spoke in that region. `Bob` means the user confirmed or the system inferred a name.

Rules:

- Default labels are `You`, `Speaker 1`, `Speaker 2`, etc.
- Inferred names are suggestions, not facts.
- User-confirmed speaker names override inferred names.
- Renaming a speaker updates every matching turn without rewriting transcript words.
- The user can clear inferred names and return to generic speaker labels.

## Live Transcript Behavior

The transcript feed has three text states.

### Live Draft

Words are still changing. Text appears slightly muted or with a live marker.

### Settled Text

The ASR provider has finalized the segment. Text becomes normal weight/color.

### Corrected Speaker Label

When diarization revises a recent turn, the speaker label and bar can update. The words should not visibly jump unless the ASR text itself changes.

The transcript should preserve readability over maximal raw event fidelity. Users should see coherent paragraphs by speaker, not a noisy stream of tiny fragments.

## Assist Rail

The assist rail is a meeting companion, not an auto-posting agent.

It can create cards for:

- detected questions
- answer lookups
- time zone conversions
- definitions
- follow-up question suggestions
- action item candidates
- source-backed notes
- uncertainty warnings

Each card can expose only safe user-controlled actions:

- `Copy`
- `Speak`
- `Sources`
- `Dismiss`
- `Pin`

There is no `Post` action in the first design. OmniVoice does not send messages to Teams, Zoom, Slack, or meeting chat from Conversation Mode.

### Copy

Copy places the card's useful text on the clipboard. The user decides where to paste it.

### Speak

Speak reads the card text using text-to-speech. The first implementation should be local device playback only. A future explicit "speak into meeting audio" mode can be considered later, but it is not part of this spec.

### Sources

Sources opens or previews the files, notes, or records used to produce the answer. For Obsidian/MCP-style retrieval, cards should show enough source context that the user can trust or reject the answer quickly.

## Knowledge And Retrieval

The assist rail may use connected local or user-approved sources. Examples:

- Obsidian notes through MCP
- local markdown folders
- transcript history
- current meeting transcript
- user-provided docs
- OpenAI-compatible AI handoff providers, when enabled

Retrieval is opt-in per connector/source. Conversation audio and transcript content must not be sent to external providers unless the user has explicitly enabled external processing for that session or provider.

Question detection should be conservative. If someone asks, "How many users did we have last year?", the rail can create a `Question Detected` card and run retrieval if the relevant source is enabled.

The answer card should separate:

- answer text
- source names
- confidence or uncertainty
- whether any external provider was used

## Post-Call View

After recording stops, Conversation Mode becomes a review surface.

Post-call features:

- full transcript
- speaker rename
- speaker merge/split correction
- summary
- action items
- questions asked
- answer cards generated during the meeting
- source list
- export transcript
- copy transcript

Post-call summary and action item generation can use local rules or an enabled AI provider.

## Data Model

Conversation Mode needs durable records distinct from single dictation transcripts.

Core records:

- `ConversationSession`
- `ConversationAudioSource`
- `ConversationSegment`
- `SpeakerTurn`
- `SpeakerIdentity`
- `AssistCard`

### ConversationSession

Stores session metadata:

- id
- title
- started timestamp
- ended timestamp
- capture mode
- source list
- ASR provider
- diarization provider
- local-only or external-processing flags

### ConversationSegment

Stores transcript text:

- id
- session id
- start time
- end time
- text
- settled state
- ASR confidence when available
- speaker id

### SpeakerTurn

Stores diarization output:

- id
- session id
- speaker id
- start time
- end time
- confidence
- overlap flag
- source provider

### SpeakerIdentity

Stores display identity:

- speaker id
- display name
- origin: generic, inferred, user-confirmed
- color token

### AssistCard

Stores rail cards:

- id
- session id
- kind
- title
- body
- source references
- confidence
- created timestamp
- status: active, copied, spoken, pinned, dismissed

## Permissions And Privacy

Conversation Mode needs explicit permission UX because it may capture meeting audio and local knowledge sources.

Required controls:

- show active capture sources before recording starts
- show whether external AI processing is enabled
- allow local-only sessions
- allow transcript history to be disabled or cleared
- allow source connectors to be enabled/disabled
- clearly mark answer cards that used external processing

The default posture should be local-first and approval-first.

## Error Handling

Conversation Mode should degrade gracefully.

Expected failures:

- microphone unavailable
- system audio capture unavailable
- meeting app audio cannot be isolated
- ASR provider missing
- diarization provider missing
- diarization confidence too low
- overlapping speech cannot be separated
- source connector unavailable
- retrieval returns no useful answer
- TTS unavailable

Degradation rules:

- If diarization is unavailable, keep live transcript running without speaker labels.
- If system audio capture is unavailable, offer microphone-only or mixed fallback.
- If a source connector fails, keep the assist rail running and show the connector error on the card.
- If TTS fails, leave Copy available.
- If speaker confidence is low, show `Unknown Speaker` or mark the label uncertain.

## UI States

Conversation Mode should include these states:

- setup: choose capture mode and sources
- recording: live transcript and assist rail
- paused: recording paused without closing the session
- stopped/review: post-call transcript review
- error/recovery: permission or provider failures with clear next actions

## MVP Scope

The first implementation slice should not try to solve every provider problem at once.

MVP should include:

- Conversation Mode window
- microphone-only recording
- paragraph-style live transcript feed
- generic speaker labels from a mock or pluggable diarization provider
- assist rail data model and static/live generated cards
- Copy action
- Speak action using local TTS if available
- post-call transcript review

Next slice should add:

- system/app audio capture
- microphone plus system/app source separation
- real local diarization provider integration
- speaker rename and merge/split correction
- Obsidian/MCP retrieval-backed answer cards

Out of scope for the MVP:

- posting into Teams, Zoom, Slack, or chat fields
- automatic meeting participation
- external AI processing by default
- speaking into meeting audio
- perfect real-time speaker labels

## Testing Strategy

Tests should cover:

- conversation record serialization
- speaker turn alignment with transcript segments
- speaker rename propagation
- low-confidence speaker labeling
- assist card state transitions
- Copy action text generation
- TTS failure fallback
- local-only privacy flags
- missing diarization provider fallback
- transcript export shape

Live capture should be tested with deterministic audio fixtures after the initial UI/data model foundation lands.

## Design Decision

The chosen direction is:

**Live Conversation Mode with paragraph-style captions, speaker bars, timestamps, and a right-side assist rail limited to Copy, Speak, Sources, Pin, and Dismiss.**

OmniVoice should help the user during the meeting, but it should not speak or post on their behalf without a future explicit mode. The first version should earn trust by being fast, useful, visible, and easy to ignore.

## Implementation Status

The first implementation slice covers microphone-only live recording, paragraph-style captions, local persistence, mock/pluggable speaker labeling, plain-text transcript export, and Copy/Speak/Sources assist cards. System/app audio capture, real local diarization, Obsidian/MCP retrieval, speaker rename/merge, and source-backed answer cards remain follow-up slices.
