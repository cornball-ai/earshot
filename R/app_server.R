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
  status_msg <- shiny::reactiveVal("Ready. Upload an audio file to transcribe.")

  shiny::observeEvent(input$transcribe, {
    shiny::req(input$audio_file)

    status_msg("Transcribing...")
    result(NULL)

    tryCatch({
      model <- if (nzchar(input$model)) input$model else NULL
      language <- if (nzchar(input$language)) input$language else NULL
      prompt <- if (nzchar(input$prompt)) input$prompt else NULL

      res <- stt.api::transcribe(
        file = input$audio_file$datapath,
        model = model,
        language = language,
        prompt = prompt,
        response_format = "verbose_json"
      )

      result(res)
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
