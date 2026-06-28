# Ask AI via local agent CLIs — design

**Date:** 2026-06-28
**Status:** Approved design, pending spec review

## Summary

Add a voice-driven "Ask AI" path that answers questions by calling a **locally
installed, already-authenticated agent CLI** (Claude, Gemini, Codex, Grok, Kimi,
Copilot, opencode, or any user-added CLI) instead of requiring the user to
configure API keys or OAuth inside OmniVoice. The answer streams into a
liquid-glass **bubble** overlay; the user can insert it at the cursor, copy it,
or dismiss it — by voice or by single keypress. Follow-up questions continue the
same conversation.

## Goals

- "Ask &lt;agent&gt; &lt;question&gt;" by voice → streamed answer in a bubble → insert at cursor.
- Zero key management: reuse whatever the user's CLIs are already logged into.
- Multi-turn follow-ups without re-naming the agent.
- Support every installed agent through one uniform mechanism, and let the user
  **add their own** agents (keyword + CLI path + optional exact command).

## Non-goals (v1)

- **No ACP.** Conversation context is owned by OmniVoice and re-sent as a
  one-shot prompt each turn ("stateless multi-turn"). This is uniform across all
  CLIs and far simpler. ACP/warm-session may be revisited only if rapid-fire
  follow-ups or in-bubble agentic tool use become requirements.
- No agentic tool use in the bubble. Each agent is pinned to plain-chat mode.
- No new global hotkey — this rides the existing push-to-talk + command parser.

## Key decision: stateless multi-turn, not ACP

Every agent CLI accepts a prompt and returns text. To get multi-turn behavior we
build the prompt from the thread history ("Earlier: Q1 → A1. Now: Q2"). The
model can't tell it isn't a real session. Benefits: uniform across all agents
(Claude/Codex/Grok have no native ACP anyway), reuses existing thread state, no
session/permission/tool machinery. Trade-offs (both minor for short Q&A):
~1–3s cold-start per turn, and re-sending growing context (trimmed for long
threads; it's the user's CLI subscription, not metered API).

## Architecture

Runs **in the macOS app** (not the Python engine): spawning user CLIs, the
overlay, key handling, and cursor insertion are all desktop concerns, and it
avoids the bundled engine's minimal `PATH`.

Components (each one purpose, independently testable):

- **`AgentDescriptor`** (value type) — how to invoke one agent: `id`,
  `displayName`, `keywords` (voice triggers), `binaryPath`, `invocation`
  (argv template with a `{prompt}` slot, or "prompt on stdin"), `streamFormat`
  (`plainText` | `streamJSON` | `streamingJSON`), `extraArgs` (e.g. no-tools
  flags), optional `workingDirectory`/`env`. Pure data + prompt-rendering; no I/O.
- **`AgentRegistry`** — built-in descriptors + user `customAgents` from
  preferences, keyed by keyword. Resolves a spoken keyword to a descriptor.
- **`AgentRunner`** — given a descriptor + rendered prompt, spawns the CLI
  (`Process`), streams stdout, parses per `streamFormat`, emits text chunks and a
  final result; maps exit/stderr to errors. The spawn is behind a small protocol
  so it can be faked in tests.
- **`AskAICommandParser`** (extends `DictationCommandParser`) — pure function:
  recognizes a leading "ask &lt;keyword&gt; …" in a dictation and returns
  `(agentKeyword, question)`, else `nil`. Unit-testable.
- **`AskSession`** — state machine for one bubble: holds the `AskAIThread`,
  active agent, captured insertion target, and status (`asking` → `streaming` →
  `ready` → `inserted`/`dismissed`). Builds the next prompt from thread history.
- **`AskBubbleController`** — the overlay window + view (liquid-glass), renders
  streaming text and the action affordances; owns the key monitor.

Data flow: dictation transcript → `AskAICommandParser` → `AskSession`
(capture cursor target, append user turn) → `AgentRunner.run(descriptor, prompt)`
→ stream into `AskBubbleController` → on Insert, `TextInsertionService.insert`
into the captured target.

## Conversation handling

`AskSession` builds each prompt from the thread: a short system preamble
("Answer concisely. Plain text. Do not use tools or read files."), then prior
`user`/`assistant` turns, then the new question. Threads persist in the existing
`askAIThreads`. Long threads are trimmed (keep system + last N turns / token
budget).

## Voice grammar & follow-ups

- Triggered inside normal push-to-talk: a dictation starting with "ask
  &lt;keyword&gt;" is routed to Ask AI instead of being typed.
- Keywords: built-ins (`claude`, `gemini`, `codex`, `grok`, `kimi`, `copilot`,
  `opencode`) + a configurable **default** for "ask ai"/"ask assistant", + any
  custom agent's keyword.
- **Follow-ups need no prefix:** while a bubble is open, the next dictation
  continues the same thread/agent. "ask &lt;other&gt;…" switches agent / new thread.
- Action commands while open: "copy that"/"insert that" → insert; "copy to
  clipboard" → clipboard only; "dismiss"/"never mind" → close.

## Bubble UX

Liquid-glass overlay matching the caption/switcher look. Shows the question and
the streaming answer. Actions, by voice or key:

- **I** — Insert at the original cursor (via `TextInsertionService`) + clipboard.
  (`Return` also inserts; it's the default.)
- **C** — Copy to clipboard only.
- **D** / **Esc** — Dismiss.

Action keys are labeled in the bubble. The cursor/focus target is captured **at
trigger time** (like dictation) so Insert lands where the user was. The bubble is
a **non-activating key panel** (`canBecomeKey` true, non-activating) so it
receives I/C/D without stealing the target app's focus or showing a Dock icon
(it's borderless/non-`.titled`, so the menu-bar-only Dock policy ignores it).

**Lifetime:** the bubble stays open after Insert/Copy (status shows "inserted")
so the user can keep asking follow-ups; only Dismiss (`D`/`Esc`), an explicit
"dismiss" voice command, or an idle timeout closes it. Closing ends the
follow-up window — a later "ask &lt;agent&gt;…" starts a fresh thread.

## Custom agents (Settings)

A "Ask AI agents" settings section, consistent with the existing
`textLLMProviders` / `mcpServers` config patterns:

- Lists built-in agents (each toggleable) + custom agents.
- **Add agent** form:
  - **Keyword / name** — voice trigger + display name (e.g. "GLM").
  - **CLI path** — browse to the binary (e.g. `~/.glm/bin/glm`).
  - **Advanced** (disclosure) — exact invocation: argv **template** with a
    `{prompt}` placeholder (default: prompt appended as the final argument) or
    "send prompt on stdin"; **stream format**; **extra flags** (no-tools);
    optional working dir / env.
- Persisted as `customAgents: [AgentConfiguration]` in `OmniVoicePreferences`.
  `AgentConfiguration` ⇄ `AgentDescriptor`.

## Discovery, PATH, and auth

- The CLIs live in `~/.local/bin`, nvm, `~/.kimi-code/bin`, `~/.opencode/bin` —
  not the GUI default `PATH`. Resolve each binary once at startup via the login
  shell (`$SHELL -lc 'command -v <bin>'`) and cache; custom agents use their
  explicit path.
- Auth is whatever the CLI already has. If a CLI returns an auth error, the
  bubble surfaces "Run `&lt;cli&gt;` once in a terminal to sign in."

## Security

- The spoken question is always passed as a **discrete argv element or via
  stdin** — never interpolated into a shell string. No `sh -c`. This prevents a
  dictated phrase from injecting a command.
- Plain-chat/no-tools flags keep agentic CLIs from reading files or running
  tools in response to a question.

## Error handling

CLI not found → "&lt;Agent&gt; CLI not found" + where it looked. Non-zero exit →
short stderr summary in the bubble. Timeout (configurable, e.g. 60s) → cancel +
message. Streaming parse error → fall back to raw text.

## Reuse map

`askAIThreads` (state) · overlay window pattern (bubble) · `TextInsertionService`
(insert) · `DictationCommandParser` (grammar) · cursor-target capture · Lucidity
glass theming.

## Built-in agent descriptors (initial)

| Agent | Binary | Invocation | Stream |
|---|---|---|---|
| Claude | `claude` | `-p {prompt} --output-format stream-json` | streamJSON |
| Gemini | `gemini` | `{prompt}` (positional, one-shot) | plain/json |
| Codex | `codex` | `exec {prompt} --json` | streamJSON |
| Grok | `grok` | `--single {prompt} --output-format streaming-json` | streamingJSON |
| Kimi | `kimi` | `-p {prompt}` | plain |
| Copilot | `copilot` | `-p {prompt}` | plain |
| opencode | `opencode` | `--prompt {prompt}` | plain |

Exact flags (incl. no-tools) confirmed per CLI during implementation. **v1 proven
end-to-end on Claude + Gemini first; others enabled as verified.**

## Testing

- `AgentDescriptor` prompt rendering + argv construction (incl. injection safety).
- `AskAICommandParser` grammar (keywords, follow-up vs new, action commands).
- `AskSession` prompt-building from thread history + trimming.
- `AgentRunner` with a faked process: chunking, stream parsing, error mapping.

## Future (explicitly deferred)

ACP warm sessions for the agents that support it (Gemini/Copilot/Kimi/opencode),
if rapid follow-ups or in-bubble tool use ever matter. The `AgentRunner`
interface is the seam where an `ACPRunner` could slot in later.
