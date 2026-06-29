# AI keyword bindings + AI-tab reorg — design

**Date:** 2026-06-28
**Status:** Approved design, pending spec review

## Summary

Unify how a spoken keyword ("ask Claude", "ask Codex", "ask AI") maps to an AI
provider. Today there are **two** parallel "ask" routers: the original
`DictationCommandParser.aiHandoff` path (engine API/OAuth providers → inserts the
answer at the cursor) and the new `AskController` path (local agent CLIs → answer
in a bubble). They collide on shared names like "claude". Replace both with one
**keyword → provider binding**: each keyword maps to exactly one configured
provider — **API, OAuth, or agent** — and every "ask &lt;keyword&gt;" flows through the
same Ask bubble. Reorganize the AI settings tab into API / OAuth / Agent sections
plus a keyword-binding editor, and remove the unused MCP section.

## Goals

- One keyword → one provider, where the provider is an API provider, an OAuth
  provider, or a local agent CLI. Free-form keyword text.
- Every keyword "ask" uses the bubble (Insert/Copy/Dismiss), regardless of target.
- AI tab sections in order: **API configurations → OAuth configurations → Agent
  configurations**, then **keyword bindings** (in Voice Patterns).
- Remove the MCP Servers settings (UI + model) — it is wired to nothing.

## Non-goals

- Token-level streaming for API/OAuth targets (the engine `aiHandoff` returns a
  full response; the bubble shows it when ready). Agent targets keep streaming.
- Keyword → fallback chains (one keyword → exactly one provider).
- Re-homing MCP into the agent layer (the CLIs own their own MCP config).

## Data model (`OmniVoiceCore`)

- **`AskTarget`** (enum, Codable, Equatable, Sendable):
  - `.textLLM(providerID: String)` — a `TextLLMProviderKind.rawValue`; routed via
    the engine `aiHandoff` (covers both API and OAuth, distinguished by the
    provider's own `authMode`/`transport`).
  - `.agent(agentID: String)` — a built-in agent id ("claude", "gemini") or a
    custom `AgentConfiguration.id`; routed via `AgentRunner` (CLI spawn).
- **`AskKeywordBinding`** (struct, Codable, Equatable, Identifiable, Sendable):
  `{ id: String, keyword: String, target: AskTarget }`.
- **`OmniVoicePreferences.askKeywordBindings: [AskKeywordBinding]`** with seeded
  defaults that preserve today's behavior:
  - `"ai"` → `.textLLM(defaultTextLLMProviderID)`
  - `"claude"` → `.agent("claude")`
  - `"gemini"` → `.agent("gemini")`
  - Keyword match is case-insensitive and trimmed.
- **`AskKeywordResolver`** (pure, Core): `resolve(_ keyword: String, in: [AskKeywordBinding]) -> AskTarget?` — case-insensitive, trimmed. Unit-testable; `AskController` calls it.
- Keep `customAgents`. **Remove** `mcpServers`, `MCPServerConfiguration`,
  `MCPEnvironmentVariable`, and the `setMCPServer`/`removeMCPServer` preference
  methods. Old persisted prefs containing `mcp_servers` decode fine — the key is
  simply ignored once the property is gone (no migration crash).

## Unified router (`OmniVoiceApp`)

`AskController` becomes the single keyword router:

- It owns the bindings (refreshed from preferences, like `customAgents` today) and
  exposes the bound keywords to `AskAICommandParser` as `knownKeywords`.
- `handle(transcript:captureTarget:)` resolves keyword → `AskKeywordBinding` →
  `AskTarget`:
  - `.agent(id)` → resolve to an `AgentDescriptor` (built-in or custom) → existing
    `AgentRunner` streaming path → bubble.
  - `.textLLM(id)` → build the `AIHandoffRequest` from the provider's
    `TextLLMProviderConfiguration` (reusing the logic currently in
    `handleAIHandoff`) → `engineClient.aiHandoff` → show the result in the bubble.
- Follow-ups, "copy that"/Insert/Dismiss, and cursor-target capture all work
  identically for both target kinds (the bubble + `TextInsertionService` are
  shared). For `.textLLM`, conversation context is carried by re-sending history
  in the handoff prompt (same stateless-multi-turn approach), bounded like the
  agent path.

The old `parseAIHandoff`/`handleAIHandoff` "ask &lt;name&gt; → insert at cursor" path is
removed; `AIHandoffTarget`'s ask-prefix parsing is superseded by the binding
keywords. (`engineClient.aiHandoff` and the request type stay — they are the
transport for `.textLLM`. The separate "have AI take a look" selection-rewrite
command is unaffected.)

## Settings reorg (`OmniVoiceApp`)

The AI tab body changes to these sections, in order:

1. **API configurations** — `TextLLMProviderKind` whose config `authMode == .apiKey`
   (Anthropic, OpenAI-compatible, OpenRouter, Custom). Existing provider cards.
2. **OAuth configurations** — config `authMode == .oauth` (Codex, Copilot).
3. **Agent configurations** — the current "Ask AI agents" section (built-ins note +
   custom agents + the Add form), moved here.
4. *(MCP Servers section removed.)*

Under **Voice Patterns**, replace the static "Ask Claude / Custom API" hints with a
**keyword-bindings editor**: a list of rows, each a `keyword` text field + a
provider **Picker** listing every configured provider across all three kinds
(API, OAuth, agent), with Add/Remove. Adding a row appends an `AskKeywordBinding`;
the picker writes the matching `AskTarget`.

## Defaults, errors, migration

- Provider list for the picker: all `TextLLMProviderKind` visible/configured +
  built-in agents + `customAgents`, each shown with a kind label (API / OAuth /
  Agent).
- Unbound keyword → not treated as an ask (normal dictation). Bound but
  unconfigured provider (e.g. API key missing) → bubble shows "Configure
  &lt;provider&gt; in AI settings." Agent binary not found → existing message.
- Removing `mcpServers`: delete the property, its CodingKeys, the two
  `decodeIfPresent` sites, the mutators, the `MCPServerConfiguration`/
  `MCPEnvironmentVariable` types, the SettingsView section + `mcpServerCard`, the
  `AppModel` mutators, and the related `PreferencesStoreTests`/`ModelsTests`.

## Testing

- `AskTarget` + `AskKeywordBinding` Codable round-trip.
- `OmniVoicePreferences.askKeywordBindings` defaults + back-compat decode of old
  JSON (with `mcp_servers`, without `ask_keyword_bindings`).
- A `AskKeywordResolver` (keyword → `AskTarget?`) — case-insensitive, trimmed.
- `AskAICommandParser` driven by bound keywords (already parameterized).
- Dual-dispatch in `AskController` and the settings reorg are integration: build +
  manual smoke (ask an API-bound keyword and an agent-bound keyword; confirm both
  land in the bubble; confirm the AI tab shows API/OAuth/Agent + bindings and no
  MCP).

## Reuse map

`AskController` / `AskBubbleWindow` / `AgentRunner` / `AgentRegistry` (agent path) ·
`engineClient.aiHandoff` + `TextLLMProviderConfiguration` (textLLM path) ·
`TextInsertionService` · existing provider cards in `SettingsView`.
