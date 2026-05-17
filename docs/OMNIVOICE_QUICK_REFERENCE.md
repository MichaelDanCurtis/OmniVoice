# OmniVoice Quick Reference

## Dictation

Hold the dictation hotkey, speak, then release the hotkey. OmniVoice shows live captions while listening and inserts the cleaned text where your cursor was when dictation started.

If the local engine is not already running, the Mac app tries to start the bundled engine automatically. The first launch may take longer while Python dependencies are installed.

## Corrections

- `no wait, ...`
- `scratch that, ...`
- `oops, correction. ...`

Example:

`I am here to see what you guys need. Oops, correction. I am here to see what you guys want.`

Becomes:

`I am here to see what you guys want.`

## Quotes

- `open quote hello there close quote` becomes `"hello there"`
- `quote hello there quote` becomes `"hello there"`
- `double quote` inserts `"`
- `single quote` inserts `'`

## Punctuation

- `comma` becomes `,`
- `period` or `full stop` becomes `.`
- `question mark` becomes `?`
- `exclamation mark` or `exclamation point` becomes `!`
- `colon` becomes `:`
- `semicolon` becomes `;`
- `new line` inserts a line break
- `new paragraph` inserts a paragraph break

## Command Mode

Start with `command`, then say an app-opening or OmniVoice command.

Examples:

- `Command, open Safari`
- `Command, launch Google Chrome`
- `Command, start Notes`
- `Command, undo last dictation`
- `Command, show commands`

Command mode opens supported applications and runs safe OmniVoice actions. It does not run shell commands, delete files, send messages, or take destructive actions.

## AI Handoff

Open Settings -> Integrations and configure an OpenAI-compatible Base URL, Model, and API Key. Then hold the dictation hotkey and use an explicit AI phrase.

Examples:

- `Ask Claude, write a quick reply to Jane`
- `Hey Codex, summarize this in two sentences`
- `Have OpenRouter take a look at this and respond in Spanish`
- `Ask OpenAI, make this sound more professional`

If text is selected when dictation starts, OmniVoice sends that selected text as context. Only the AI response is inserted at the cursor.

## Selection Rewrite

Select text, hold the dictation hotkey, then say a rewrite instruction.

Examples:

- `make this shorter`
- `turn this into bullets`
- `make this more professional`
- `make this warmer`
- `reply politely that Tuesday works`

## Literal Mode

Start a dictation with `literal mode` to insert the rest with cleanup skipped.

Example:

`literal mode npm run build`

Becomes:

`npm run build`

## Per-App Profiles

When the selected cleanup style is `Neutral`, OmniVoice applies a few automatic app profiles:

- Terminal, Xcode, and VS Code use raw dictation.
- Mail uses professional cleanup.
- Slack and Messages use concise cleanup.

Pick an explicit cleanup style to override these automatic profiles.

## Personal Dictionary

Add names, products, acronyms, and project terms in Settings. OmniVoice uses those entries to preserve configured casing during cleanup.

## Cleanup Styles

- `Neutral` keeps a natural cleaned-up version.
- `Professional` is more formal.
- `Concise` removes more filler.
- `Expanded` is more explanatory.
- `Raw Dictation` keeps the transcript closest to what was heard.
