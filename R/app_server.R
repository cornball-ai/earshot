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
app_server <- function(input, output, session) {

  result <- shiny::reactiveVal(NULL)
  status_msg <- shiny::reactiveVal("Ready. Record or upload audio to transcribe.")
  recorded_file <- shiny::reactiveVal(NULL)

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

  # Save settings
  shiny::observeEvent(input$save_settings, {
    if (input$backend == "api") {
      if (nzchar(input$api_base)) {
        stt.api::set_stt_base(input$api_base)
        msg <- paste("API URL set to:", input$api_base)
      } else {
        status_msg("Please enter an API URL.")
        return()
      }

      if (nzchar(input$api_key)) {
        stt.api::set_stt_key(input$api_key)
        msg <- paste(msg, "(with API key)")
      }

      status_msg(msg)
    } else {
      # audio.whisper - clear API settings to force local backend
      options(stt.api_base = NULL, stt.api_key = NULL)
      status_msg("Using audio.whisper (local). Make sure it's installed.")
    }
  })

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
      model <- if (nzchar(input$model)) input$model else NULL
      language <- if (nzchar(input$language)) input$language else NULL
      prompt <- if (nzchar(input$prompt)) input$prompt else NULL

      res <- stt.api::transcribe(
        file = audio_path,
        model = model,
        language = language,
        prompt = prompt,
        response_format = "verbose_json"
      )

      result(res)
      recorded_file(NULL)  # Clear after successful transcription
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
}

# Null coalesce operator
`%||%` <- function(x, y) if (is.null(x)) y else x

# Base64 decode (using jsonlite, a dependency of stt.api)
base64_decode <- function(x) {
  jsonlite::base64_dec(x)
}

# Convert audio to 16-bit wav if needed (requires ffmpeg)
ensure_wav <- function(path, status_fn = message) {
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
