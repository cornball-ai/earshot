# earshot 0.0.3

Ported onto glinty's protocol v3 component vocabulary. The UI is a
component tree rather than HTML tags, so it travels the wire as
structure and a frontend that is not a browser renders the same app
with real widgets.

- `app_ui()` and every `render_ui()` in the server build components:
  `row`, `column`, `panel`, `txt`, `button`, `collapse`, `image`,
  `audio_output`. `glinty::div/span/p` and the old `tag()` signature
  are gone from glinty and gone from here.
- History rows are two buttons rather than a clickable card carrying
  a nested delete button. v3 has no clickable container, and a button
  inside a button was never valid markup. Each carries its entry id
  as the event's value, so one observer still serves every row.
- Button labels say the action. "x" beside a trash icon reads as "x"
  to a screen reader, and a bare timestamp does not say what pressing
  it does.
- The stylesheet dropped what the vocabulary now expresses and hooks
  what is left on ids and `[data-g-target]`. A test asserts no rule
  targets something the page never renders, because CSS fails
  silently by design.
- `record_btn` stays raw HTML on purpose: MediaRecorder is
  browser-only, and pretending otherwise would draw a button that
  does nothing everywhere else.

**Renumbered.** This was 0.2.0. earshot has never been released, has
no users, and is still changing with glinty underneath it, so the
version now says so: 0.0.1 was the Shiny app, 0.0.2 the move to
glinty, and this is 0.0.3.

# earshot 0.0.2

Migrated from Shiny to glinty (protocol 2), dropping the Shiny,
bslib and htmltools dependencies for `jsonlite` and `digest`.

# earshot 0.0.1

Initial Shiny app for speech-to-text: record or upload audio, get
transcriptions with timestamps.
