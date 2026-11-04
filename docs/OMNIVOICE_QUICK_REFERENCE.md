# OmniSpeak Quick Reference

## Dictation

Hold the dictation hotkey, speak, then release the hotkey. OmniSpeak shows live captions while listening and inserts the cleaned text where your cursor was when dictation started.

If the local engine is not already running, the Mac app tries to start the bundled engine automatically. The first launch may take longer while the bundled runtime is copied into OmniSpeak's Application Support folder.

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

Start with `command`, then say an app-opening or OmniSpeak command.

Examples:

- `Command, open Safari`
- `Command, launch Google Chrome`
- `Command, start Notes`
- `Command, undo last dictation`
- `Command, show commands`

Command mode opens supported applications and runs safe OmniSpeak actions. It does not run shell commands, delete files, send messages, or take destructive actions.

## AI Handoff

Open Settings -> AI and add the provider you want to use. Pick the provider/model for the current Ask AI or conversation session before sending.

Examples:

- `Ask Claude, write a quick reply to Jane`
- `Hey Codex, summarize this in two sentences`
- `Have OpenRouter take a look at this and respond in Spanish`
- `Ask OpenAI, make this sound more professional`

If selected text, conversations, notes, files, images, or audio are attached to the session, OmniSpeak sends that context with the request. Only the AI response is inserted or displayed in the AI flow.

## Conversation Mode

Open Conversation Mode from the menu bar, Settings, or the hot menu. Press Start to begin a live meeting capture.

The live view shows streaming speaker blocks with timestamps. When local diarization is enabled and the Sortformer model is available, OmniSpeak separates detected speaker turns locally. When diarization is off or unavailable, recording still works with generic transcript text.

The conversation AI panel runs only when you ask. It sends the current transcript as context and can answer questions, summarize, or extract action items without continuously monitoring the conversation.

Saved conversations can be copied, deleted in bulk, archived to disk, opened in the Editor, or attached to Ask AI.

## Translation

Enable live translation in Settings -> Translate or through the hot menu. Pick a local translation model, choose a target language, and the caption overlay shows the active target above translated captions.

TranslateGemma-style Hugging Face models may require accepting the model agreement before download. Add a Hugging Face token in Settings -> Models when a model is gated.

## Hot Menu

Hold the hot-menu hotkey to open the radial action menu. Use the mouse or arrow keys to choose actions. Tap the hot-menu hotkey twice quickly to latch it open.

Typical hot-menu actions:

- Up cycles Conversation, Transcription, and Ask AI modes.
- Right turns translation on or off.
- Left cycles quick target languages.
- Down cycles dictation style.

## Literal Mode

Start a dictation with `literal mode` to insert the rest with cleanup skipped.

Example:

`literal mode npm run build`

Becomes:

`npm run build`

## Per-App Profiles

When the selected cleanup style is `Neutral`, OmniSpeak applies a few automatic app profiles:

- Terminal, Xcode, and VS Code use raw dictation.
- Mail uses professional cleanup.
- Slack and Messages use concise cleanup.

Pick an explicit cleanup style to override these automatic profiles.

## Personal Dictionary

Add names, products, acronyms, and project terms in Settings. OmniSpeak uses those entries to preserve configured casing during cleanup.

## Cleanup Styles

- `Neutral` keeps a natural cleaned-up version.
- `Professional` is more formal.
- `Concise` removes more filler.
- `Expanded` is more explanatory.
- `Raw Dictation` keeps the transcript closest to what was heard.
