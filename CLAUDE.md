# earshot

Shiny app for speech-to-text transcription using stt.api.

## Architecture

```
earshot/
├── app.R              # RStudio "Run App" entrypoint
├── R/
│   ├── run_app.R      # Exported app launcher
│   ├── app_ui.R       # Shiny UI
│   └── app_server.R   # Shiny server logic
└── inst/tinytest/     # Tests
```

## Usage

**RStudio**: Click "Run App" button (uses `app.R`, auto-loads package via pkgload)

**From R**:
```r
library(earshot)
run_app()  # port 7802
```

## Dependencies

- **shiny**: Web framework
- **stt.api**: Speech-to-text backend

## Development

```bash
# Build and test
r -e 'rhydrogen::document(); rhydrogen::install(); tinytest::test_package("earshot")'

# Run without installing
r -e 'rhydrogen::load_all(); run_app()'
```

## Backend Configuration

The app auto-configures stt.api on startup:
- Detects available backends (whisper, audio.whisper, OpenAI)
- Uses `OPENAI_API_KEY` env var if set
- Settings can be changed via the Settings sidebar in the UI
