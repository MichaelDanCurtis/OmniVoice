# Mic-vs-System Two-Track Diarization — Design

**Date:** 2026-07-29
**Status:** Approved direction; implementation not started
**Origin:** Method adopted from [digimata/quill](https://github.com/digimata/quill):
"mic-vs-system is free two-party diarization — `me` vs `them` with no
speaker-identification model."

## Goal

Give conversation mode reliable "who said what" for calls and meetings without
running a diarization model at all, by exploiting capture topology: the
microphone track is *the user*; the system-audio track is *everyone else*.

## Method (quill's approach, mapped onto OmniSpeak)

1. **Capture two tracks.** Extend `ConversationCaptureMode` (already carries
   `.microphoneOnly`) with `.microphoneAndSystem`. Mic capture stays
   `AudioCaptureService`. System audio uses a Core Audio **process tap**
   (`CATapDescription`, macOS 14.2+) mixing down all system output — this is
   how quill records the remote side of any call app without per-app support.
2. **Transcribe each track independently** with the selected ASR provider
   (engine MLX providers or Apple Speech). Tracks are independent streams, so
   the existing per-session streaming path is reused per track.
3. **Merge chronologically.** Both tracks share the session start clock;
   segments carry start offsets. The merge interleaves finished segments by
   timestamp and stamps `speaker_id`: mic → `speaker-me` ("Me"), system →
   `speaker-them` ("Them"). Existing conversation UI/rename already handles
   speaker ids.
4. **Compose with model diarization, don't replace it.** The MLX sortformer
   providers still matter for splitting multiple remote voices; when enabled,
   run them on the *system track only* — the mic track never needs a model.
   Two-party labeling is exact by construction; model diarization refines
   "Them" into "Them 1 / Them 2".

## Why this over model-only diarization

- Me/them separation is *exact* (it is capture topology, not inference).
- Zero model download, zero added latency for the two-party case (most calls).
- Cleanly degrades: no system-audio permission → `.microphoneOnly`, exactly
  today's behavior.

## Permissions & gotchas

- System-audio taps require the **Audio Capture** TCC permission
  (`NSAudioCaptureUsageDescription`); prompt on first use of
  `.microphoneAndSystem`, mirroring the Accessibility permission UX.
- Echo double-capture: the mic may pick up speaker output when not using
  headphones. v1 accepts this (quill does); the merge can later drop
  near-duplicate overlapping text between tracks.
- The process tap captures *all* system audio (music etc.), not just the call.
  v1 accepts this; per-process taps are a refinement.

## v1 scope

- `.microphoneAndSystem` capture mode + toggle in conversation UI.
- Second streaming transcription lane + timestamp merge with fixed
  `speaker-me`/`speaker-them` labels.
- Engine diarization applied to the system track when the user enables it.

Out of scope: per-app tap selection, echo dedup, Windows (WASAPI loopback is
the analogous method there — note for the port).
