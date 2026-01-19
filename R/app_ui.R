#' App UI
#'
#' Create the Earshot Shiny app user interface.
#'
#' @return A Shiny UI object.
#'
#' @keywords internal
app_ui <- function() {
  # Resource path for assets
  www_path <- system.file("app/www", package = "earshot")
  if (www_path == "") {
    # Dev mode - use local path
    www_path <- "inst/app/www"
  }
  shiny::addResourcePath("www", www_path)

  shiny::fluidPage(
    shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "www/styles.css"),
      shiny::tags$script(src = "www/recorder.js")
    ),

    # Header
    shiny::div(
      class = "earshot-header",
      shiny::div(
        class = "header-content",
        shiny::tags$a(
          href = "https://cornball.ai",
          class = "header-link",
          shiny::tags$img(src = "www/logo.png", class = "header-logo", alt = "Cornball AI"),
          shiny::span("earshot", class = "header-title")
        )
      )
    ),

    shiny::sidebarLayout(
      shiny::sidebarPanel(
        # Record from microphone
        shiny::div(
          class = "record-section",
          shiny::tags$label("Record from Microphone", class = "control-label"),
          shiny::div(
            class = "record-controls",
            shiny::tags$button(
              id = "record_btn",
              class = "btn btn-record",
              "Record"
            ),
            shiny::span(id = "record_timer", class = "record-timer")
          )
        ),

        shiny::tags$div(class = "input-divider",
          shiny::span("or", class = "divider-text")
        ),

        # Upload file
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
        shiny::verbatimTextOutput("status"),

        # Settings panel (collapsible)
        shiny::hr(),
        shiny::tags$details(
          class = "settings-panel",
          shiny::tags$summary("Settings"),
          shiny::div(
            class = "settings-content",
            shiny::selectInput("backend", "Backend",
                               choices = c("API Server" = "api",
                                           "audio.whisper (local)" = "audio.whisper"),
                               selected = "api"),

            shiny::conditionalPanel(
              condition = "input.backend == 'api'",
              shiny::textInput("api_base", "API URL",
                               value = getOption("stt.api_base", ""),
                               placeholder = "http://localhost:4123"),
              shiny::passwordInput("api_key", "API Key (optional)",
                                   placeholder = "For OpenAI API")
            ),

            shiny::actionButton("save_settings", "Save Settings",
                                class = "btn btn-outline-primary btn-sm")
          )
        )
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
