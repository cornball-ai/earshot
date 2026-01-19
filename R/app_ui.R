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

  bslib::page_fillable(
    theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
    title = "earshot",

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
          target = "_blank",
          class = "header-link",
          shiny::tags$img(src = "www/logo.png", class = "header-logo"),
          shiny::span("earshot", class = "header-title")
        )
      )
    ),

    # Main layout with sidebar
    bslib::layout_sidebar(
      fillable = TRUE,
      sidebar = bslib::sidebar(
        width = 350,

        # Settings panel (collapsible)
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
                               value = getOption("stt.api_base", "https://api.openai.com")),
              shiny::passwordInput("api_key", "API Key",
                                   value = Sys.getenv("OPENAI_API_KEY", ""))
            ),

            shiny::actionButton("save_settings", "Save Settings",
                                class = "btn btn-outline-primary btn-sm")
          )
        ),

        shiny::hr(),

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

        # Audio preview
        shiny::uiOutput("audio_preview"),

        shiny::selectInput("model", "Model",
                           choices = c("whisper-1 (OpenAI)" = "whisper-1",
                                       "tiny" = "tiny",
                                       "base" = "base",
                                       "small" = "small",
                                       "medium" = "medium",
                                       "large" = "large"),
                           selected = "whisper-1"),

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

        shiny::actionButton("transcribe", "Transcribe", class = "btn-primary w-100"),

        shiny::hr(),
        shiny::verbatimTextOutput("status")
      ),

      # Main content
      bslib::navset_card_tab(
        bslib::nav_panel("Text", shiny::verbatimTextOutput("transcription")),
        bslib::nav_panel("Segments", shiny::tableOutput("segments")),
        bslib::nav_panel("Raw", shiny::verbatimTextOutput("raw"))
      )
    )
  )
}
