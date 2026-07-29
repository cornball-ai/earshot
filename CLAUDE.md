# earshot

Speech-to-text transcription app using stt.api, built on
[glinty](https://github.com/cornball-ai/glinty).

## Architecture

```
earshot/
├── app.R              # RStudio "Run App" entrypoint
├── R/
│   ├── run_app.R      # Exported app launcher
│   ├── app_ui.R       # glinty UI tree
│   ├── app_server.R   # Reactive server logic
│   └── history.R      # History persistence
└── inst/
    ├── app/www/       # styles.css, recorder.js, logo.png (served at /static/)
    └── tinytest/      # Tests
```

## Usage

**RStudio**: Click "Run App" button (uses `app.R`, auto-loads via pkgload)

**From R**:
```r
library(earshot)
run_app()  # port 7802
```

glinty listens on all interfaces, so treat the port as reachable from
the local network. There is no `host` argument; scope it with a
firewall or a reverse proxy.

## Dependencies

- **glinty** (>= 0.4.0): web framework. Pulls only jsonlite + digest.
- **stt.api**: speech-to-text backend.

## Coming from the Shiny version

Migrated at 0.2.0. The differences that bite:

- Inputs are **called**: `input$backend()`, not `input$backend`.
- Inputs are `NULL` until set, and anything created inside
  `render_ui()` stays `NULL` until the user touches it. Optional
  string reads go through the `opt_str()` helper rather than bare
  `nzchar()`, which errors on `NULL`.
- `conditionalPanel("input.x == 'a'")` became
  `conditional_panel(condition = input_is("x", "a"))`. No JS
  expression, no eval.
- History rows use value-carrying click binds
  (`bind = list(event = "click", target = "history_view", value = id)`)
  instead of inline `onclick` strings calling `Shiny.setInputValue`.
  The nearest bind wins on click, so the delete button inside a row
  does not also trigger the row.
- `recorder.js` uses `Glinty.setInputValue` /
  `Glinty.addCustomMessageHandler` and listens for `glinty:connected`.
  No jQuery.

## Secrets

**The API key field is deliberately not prefilled.** A `value=`
attribute is rendered into the page source in plain text, where
`type="password"` hides nothing, and the port is LAN-reachable. The
server reads `OPENAI_API_KEY` itself in `configure_backend()`; the
field exists only to override it, and an empty field means "use the
environment".

Do not reintroduce `value = Sys.getenv(...)` on a password field.
`inst/tinytest/test_server_wiring.R` asserts the key never appears in
the rendered page.

## Development

```bash
# Build, document, install, test
r -e 'rformat::rformat_dir("R", control_braces = "multi", expand_if = TRUE); tinyrox::document(); tinypkgr::install(); tinytest::test_package("earshot")'

# Run without installing
r -e 'pkgload::load_all(); run_app()'
```

## Backend Configuration

The app auto-configures stt.api on startup:
- Detects available backends (whisper, audio.whisper, OpenAI)
- Uses `OPENAI_API_KEY` env var if set
- Settings can be changed via the Settings sidebar in the UI
