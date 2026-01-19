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

Configure stt.api before running:

```r
# Local whisper server
stt.api::set_stt_base("http://localhost:4123")

# OpenAI API
stt.api::set_stt_base("https://api.openai.com")
stt.api::set_stt_key(Sys.getenv("OPENAI_API_KEY"))
```
