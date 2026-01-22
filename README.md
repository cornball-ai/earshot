# earshot

Shiny app for speech-to-text transcription using [stt.api](https://github.com/cornball-ai/stt.api).

## Installation

```r
remotes::install_github("cornball-ai/whisper")
remotes::install_github("cornball-ai/stt.api")
remotes::install_github("cornball-ai/earshot")
```

## Usage

**RStudio**: Open the project and click "Run App" (uses `app.R`)

**From R**:
```r
library(earshot)
run_app()
```

Opens at http://localhost:7802 by default.

## Features

- Record from microphone (requires browser - see note below)
- Upload audio files (.wav, .mp3, .m4a, .ogg, .flac, .webm)
- Model selection (tiny, base, small, medium, large, or whisper-1 for OpenAI)
- Optional language hint for improved accuracy
- Optional prompt for names, acronyms, or domain-specific terms
- View transcription text, segments with timestamps, or raw API response

### Microphone Recording

To use microphone recording, you must open the app in a web browser (not RStudio's viewer pane). Click "Open in Browser" in the Shiny viewer tab, or navigate directly to the URL (e.g., http://localhost:7802).

Microphone access requires:
- A secure context (HTTPS or localhost)
- Browser permission to access the microphone

## Backends

earshot uses [stt.api](https://github.com/cornball-ai/stt.api) which supports multiple transcription backends. In auto mode, backends are tried in this order:

1. **whisper** (native R torch) - Fastest, runs locally, no API key needed
2. **api** (OpenAI or compatible) - Requires API endpoint and key
3. **[audio.whisper](https://github.com/bnosac/audio.whisper)** - Fallback using the audio.whisper package

### Native whisper (recommended)

Install the whisper package for local transcription with no API dependencies:

```r
remotes::install_github("cornball-ai/whisper")
```

Models are downloaded automatically on first use.

### OpenAI API

To use OpenAI's API, set your API key in `~/.Renviron`:

```
OPENAI_API_KEY=sk-...
```

Then configure stt.api:

```r
stt.api::set_stt_base("https://api.openai.com")
stt.api::set_stt_key(Sys.getenv("OPENAI_API_KEY"))
```

### Local whisper server

For a local OpenAI-compatible server (e.g., whisper container):

```r
stt.api::set_stt_base("http://localhost:8200")
```

### audio.whisper

Install from the bnosac drat repository or GitHub:

```r
# From drat
install.packages("audio.whisper", repos = "https://bnosac.github.io/drat")

# From GitHub
remotes::install_github("bnosac/audio.whisper")
```

## License

MIT
