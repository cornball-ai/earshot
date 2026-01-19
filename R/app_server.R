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

    status_msg("Transcribing...")
    result(NULL)

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
