# earshot

Shiny app for speech-to-text transcription using [stt.api](https://github.com/cornball-ai/stt.api).

## Installation

```r
remotes::install_github("cornball-ai/earshot")
```

## Usage

```r
library(earshot)
run_app()
```

Opens at http://localhost:7802 by default.

## Features

- Upload audio files (.wav, .mp3, .m4a, .ogg, .flac, .webm)
- Model selection (tiny, base, small, medium, large, or whisper-1 for OpenAI)
- Optional language hint for improved accuracy
- Optional prompt for names, acronyms, or domain-specific terms
- View transcription text, segments with timestamps, or raw API response

## Backend Configuration

Configure stt.api before running:

```r
# Local whisper server
stt.api::set_stt_base("http://localhost:4123")

# OpenAI API
stt.api::set_stt_base("https://api.openai.com")
stt.api::set_stt_key(Sys.getenv("OPENAI_API_KEY"))
```

## License

MIT
