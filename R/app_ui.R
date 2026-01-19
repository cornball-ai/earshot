#' App UI
#'
#' Create the Earshot Shiny app user interface.
#'
#' @return A Shiny UI object.
#'
#' @keywords internal
app_ui <- function() {
  shiny::fluidPage(
    shiny::titlePanel("Earshot - Speech to Text"),

    shiny::sidebarLayout(
      shiny::sidebarPanel(
        shiny::fileInput("audio_file", "Upload Audio File",
                         accept = c(".wav", ".mp3", ".m4a", ".ogg", ".flac", ".webm")),

        shiny::selectInput("model", "Model",
                           choices = c("Default" = "",
                                       "tiny" = "tiny",
                                       "base" = "base",
                                       "small" = "small",
                                       "medium" = "medium",
                                       "large" = "large",
                                       "whisper-1" = "whisper-1"),
                           selected = ""),

        shiny::selectInput("language", "Language (optional)",
                           choices = c("Auto-detect" = "",
                                       "English" = "en",
                                       "Spanish" = "es",
                                       "French" = "fr",
                                       "German" = "de",
                                       "Italian" = "it",
                                       "Portuguese" = "pt",
                                       "Japanese" = "ja",
                                       "Chinese" = "zh"),
                           selected = ""),

        shiny::textInput("prompt", "Prompt (optional)",
                         placeholder = "Names, acronyms, or terms to guide transcription"),

        shiny::actionButton("transcribe", "Transcribe", class = "btn-primary"),

        shiny::hr(),
        shiny::verbatimTextOutput("status")
      ),

      shiny::mainPanel(
        shiny::tabsetPanel(
          shiny::tabPanel("Text",
                          shiny::br(),
                          shiny::verbatimTextOutput("transcription")),
          shiny::tabPanel("Segments",
                          shiny::br(),
                          shiny::tableOutput("segments")),
          shiny::tabPanel("Raw",
                          shiny::br(),
                          shiny::verbatimTextOutput("raw"))
        )
      )
    )
  )
}
