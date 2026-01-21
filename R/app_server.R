#' App Server
#'
#' Server logic for the Earshot Shiny app.
#'
#' @param input Shiny input object.
#' @param output Shiny output object.
#' @param session Shiny session object.
#'
#' @return NULL (side effects only).
#'
#' @importFrom utils capture.output str
#' @keywords internal
app_server <- function(
  input,
  output,
  session
) {

  result <- shiny::reactiveVal(NULL)
  status_msg <- shiny::reactiveVal("Ready. Record or upload audio to transcribe.")
  recorded_file <- shiny::reactiveVal(NULL)

  # Detect available backends (in priority order)
  available_backends <- detect_backends()
  default_backend <- unname(available_backends[1]) # Get value, not name

  # Update backend choices in UI
  shiny::updateSelectInput(session, "backend",
    choices = available_backends,
    selected = default_backend)

  # Configure default backend
  configure_backend(default_backend, session)
  status_msg(paste0("Ready. Using ", names(available_backends)[1], "."))

  # Dynamic model selection based on backend
  output$model_select <- shiny::renderUI({
      backend <- input$backend
      if (is.null(backend)) backend <- default_backend

      models <- get_models_for_backend(backend)
      shiny::selectInput("model", "Model",
        choices = models$choices,
        selected = models$default)
    })

  # Update backend configuration when changed
  shiny::observeEvent(input$backend, {
      configure_backend(input$backend, session)
      status_msg(paste0("Backend: ", input$backend))
    }, ignoreInit = TRUE)

  # Handle recorded audio from JavaScript
  shiny::observeEvent(input$recorded_audio, {
      audio_data <- input$recorded_audio

      # Decode base64 and save to temp file
      raw_audio <- base64_decode(audio_data$data)
      tmp_file <- tempfile(fileext = ".webm")
      writeBin(raw_audio, tmp_file)

      recorded_file(tmp_file)
      status_msg("Recording saved. Click Transcribe to process.")
    })

  # Handle recording errors
  shiny::observeEvent(input$recording_error, {
      status_msg(paste("Microphone error:", input$recording_error))
    })

  # Update status during recording
  shiny::observeEvent(input$recording_status, {
      if (input$recording_status == "recording") {
        status_msg("Recording... Click Stop when done.")
        recorded_file(NULL)
      }
    })

  # Apply API settings when changed
  shiny::observeEvent(list(input$api_base, input$api_key), {
      if (input$backend == "openai" && nzchar(input$api_base)) {
        stt.api::set_stt_base(input$api_base)
        if (nzchar(input$api_key)) {
          stt.api::set_stt_key(input$api_key)
        }
      }
    }, ignoreInit = TRUE)

  # Transcribe button
  shiny::observeEvent(input$transcribe, {
      # Get audio file path (recorded takes priority if available)
      audio_path <- recorded_file()
      if (is.null(audio_path) && !is.null(input$audio_file)) {
        audio_path <- input$audio_file$datapath
      }

      if (is.null(audio_path)) {
        status_msg("No audio to transcribe. Record or upload a file first.")
        return()
      }

      status_msg("Preparing audio...")
      result(NULL)

      # Convert to 16-bit wav if needed
      audio_path <- ensure_wav(audio_path, status_msg)
      if (is.null(audio_path)) return()

      status_msg("Transcribing...")

      tryCatch({
          if (nzchar(input$model)) {
            model <- input$model
          } else {
            model <- NULL
          }
          if (nzchar(input$language)) {
            language <- input$language
          } else {
            language <- NULL
          }
          if (nzchar(input$prompt)) {
            prompt <- input$prompt
          } else {
            prompt <- NULL
          }

          res <- stt.api::transcribe(
            file = audio_path,
            model = model,
            language = language,
            prompt = prompt,
            response_format = "verbose_json"
          )

          result(res)
          recorded_file(NULL) # Clear after successful transcription
          status_msg(sprintf("Done. Backend: %s, Language: %s",
              res$backend, res$language %||% "auto"))

        }, error = function(e) {
          status_msg(paste("Error:", conditionMessage(e)))
        })
    })

  output$status <- shiny::renderText({
      status_msg()
    })

  output$transcription <- shiny::renderText({
      res <- result()
      if (is.null(res)) return("")
      res$text
    })

  output$segments <- shiny::renderTable({
      res <- result()
      if (is.null(res) || is.null(res$segments)) return(NULL)
      res$segments
    })

  output$raw <- shiny::renderText({
      res <- result()
      if (is.null(res)) return("")
      paste(capture.output(str(res$raw)), collapse = "\n")
    })

  # Audio preview
  output$audio_preview <- shiny::renderUI({
      # Check for recorded file first, then uploaded
      audio_path <- recorded_file()
      audio_type <- "audio/webm"

      if (is.null(audio_path) && !is.null(input$audio_file)) {
        audio_path <- input$audio_file$datapath
        # Guess type from extension
        ext <- tolower(tools::file_ext(input$audio_file$name))
        audio_type <- switch(ext,
          mp3 = "audio/mpeg",
          wav = "audio/wav",
          m4a = "audio/mp4",
          ogg = "audio/ogg",
          flac = "audio/flac",
          webm = "audio/webm",
          "audio/mpeg"
        )
      }

      if (is.null(audio_path) || !file.exists(audio_path)) {
        return(NULL)
      }

      # Encode as base64 data URI
      audio_data <- base64_encode(readBin(audio_path, "raw", file.info(audio_path)$size))
      data_uri <- paste0("data:", audio_type, ";base64,", audio_data)

      shiny::div(
        class = "audio-preview",
        shiny::tags$label("Preview", class = "control-label"),
        shiny::tags$audio(
          src = data_uri,
          controls = "controls",
          style = "width: 100%;"
        )
      )
    })
}

# Null coalesce operator
`%||%` <- function(
  x,
  y
) if (is.null(x)) y else x

# Base64 decode (using jsonlite, a dependency of stt.api)
base64_decode <- function(x) {
  jsonlite::base64_dec(x)
}

# Base64 encode
base64_encode <- function(x) {
  jsonlite::base64_enc(x)
}

# Convert audio to 16-bit wav if needed (requires ffmpeg)
ensure_wav <- function(
  path,
  status_fn = message
) {
  # Check if already a wav file with correct format
  ext <- tolower(tools::file_ext(path))

  if (ext == "wav") {
    # Could still be wrong format, but try it first
    return(path)
  }

  # Convert to 16-bit mono wav at 16kHz
  wav_path <- tempfile(fileext = ".wav")

  status_fn("Converting to WAV format...")

  result <- system2("ffmpeg",
    args = c("-y", "-i", shQuote(path),
      "-ar", "16000", "-ac", "1", "-sample_fmt", "s16",
      shQuote(wav_path)),
    stdout = FALSE, stderr = FALSE)

  if (result != 0 || !file.exists(wav_path)) {
    status_fn("Error: Audio conversion failed. Is ffmpeg installed?")
    return(NULL)
  }

  wav_path
}

# Detect available backends in priority order
# Returns named vector: c("Display Name" = "value")
detect_backends <- function() {

  backends <- c()

  # Check for native whisper (not yet available)
  # if (requireNamespace("whisper", quietly = TRUE)) {
  #   backends <- c(backends, "whisper (native)" = "whisper")
  # }

  # Check for audio.whisper
  if (requireNamespace("audio.whisper", quietly = TRUE)) {
    backends <- c(backends, "audio.whisper (local)" = "audio.whisper")
  }

  # Check for OpenAI API key
  if (nzchar(Sys.getenv("OPENAI_API_KEY", ""))) {
    backends <- c(backends, "OpenAI API" = "openai")
  }

  # Fallback to OpenAI (user can enter key)
  if (length(backends) == 0) {
    backends <- c("OpenAI API" = "openai")
  }

  backends
}

# Configure backend settings
configure_backend <- function(
  backend,
  session = NULL
) {
  if (backend == "openai") {
    stt.api::set_stt_base("https://api.openai.com")
    key <- Sys.getenv("OPENAI_API_KEY", "")
    if (nzchar(key)) {
      stt.api::set_stt_key(key)
    }
  } else if (backend == "audio.whisper") {
    # Clear API settings to force local backend
    options(stt.api_base = NULL, stt.api_key = NULL)
  }
}

# Get models for a backend
get_models_for_backend <- function(backend) {
  if (backend == "openai") {
    list(
      choices = c("whisper-1" = "whisper-1"),
      default = "whisper-1"
    )
  } else if (backend == "audio.whisper") {
    list(
      choices = c("tiny" = "tiny",
        "base" = "base",
        "small" = "small",
        "medium" = "medium",
        "large" = "large"),
      default = "small"
    )
  } else if (backend == "whisper") {
    # Native whisper (future)
    list(
      choices = c("tiny" = "tiny",
        "base" = "base",
        "small" = "small",
        "medium" = "medium",
        "large" = "large"),
      default = "small"
    )
  } else {
    list(choices = c("whisper-1" = "whisper-1"), default = "whisper-1")
  }
}

