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
      shiny::tags$link(rel = "icon", type = "image/png", href = "www/logo.png"),
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

    # Main layout with collapsible sidebars
    bslib::layout_sidebar(
      fillable = TRUE,
      class = "main-layout",

      # Left sidebar: History
      sidebar = bslib::sidebar(
        id = "history_sidebar",
        title = "History",
        position = "left",
        open = "desktop",
        width = 280,
        # Config display
        shiny::uiOutput("config_display"),
        # Save audio checkbox
        shiny::checkboxInput("save_audio_files", "Save audio files", FALSE),
        # History list
        shiny::div(
          class = "history-list",
          shiny::uiOutput("history_list")
        )
      ),

      # Main content with right sidebar
      bslib::layout_sidebar(
        fillable = TRUE,

        # Right sidebar: Settings
        sidebar = bslib::sidebar(
          id = "settings_sidebar",
          title = "Settings",
          position = "right",
          open = "desktop",
          width = 280,
          shiny::selectInput("backend", "Backend",
            choices = c("OpenAI API" = "openai"),
            selected = "openai"),

          shiny::uiOutput("model_select"),

          shiny::conditionalPanel(
            condition = "input.backend == 'whisper'",
            shiny::uiOutput("download_model_ui")
          ),

          shiny::selectInput("language", "Language",
            choices = c("English" = "en",
              "Auto-detect" = "",
              "Spanish" = "es",
              "French" = "fr",
              "German" = "de",
              "Italian" = "it",
              "Portuguese" = "pt",
              "Japanese" = "ja",
              "Chinese" = "zh"),
            selected = "en"),

          shiny::conditionalPanel(
            condition = "input.backend == 'openai'",
            shiny::textInput("api_base", "API URL",
              value = "https://api.openai.com"),
            shiny::passwordInput("api_key", "API Key",
              value = Sys.getenv("OPENAI_API_KEY", ""))
          )
        ),

        # Center: Two panels side by side
        bslib::layout_columns(
          col_widths = c(5, 7),
          fill = TRUE,

          # Left center: Record/Upload/Transcribe
          bslib::card(
            class = "input-card",
            full_screen = FALSE,
            bslib::card_body(
              fillable = FALSE,
              # Record row
              shiny::div(
                class = "record-row",
                shiny::tags$button(
                  id = "record_btn",
                  class = "btn btn-record",
                  "Record"
                ),
                shiny::span(id = "record_timer", class = "record-timer")
              ),

              shiny::tags$hr(),
              shiny::tags$span("or", class = "divider-text"),

              # Upload section
              shiny::fileInput("audio_file", NULL,
                accept = c(".wav", ".mp3", ".m4a", ".ogg", ".flac", ".webm")),

              # Streaming toggle
              shiny::checkboxInput("stream_mode", "Live transcription", value = FALSE),

              # Audio preview
              shiny::uiOutput("audio_preview"),

              # Prompt
              shiny::textInput("prompt", "Prompt (optional)",
                placeholder = "Names, acronyms, or terms"),

              # Transcribe button
              shiny::actionButton("transcribe", "Transcribe", class = "btn-primary w-100")
            )
          ),

          # Right center: Results
          shiny::div(
            class = "results-column",

            # Live transcription (always visible when streaming)
            shiny::conditionalPanel(
              condition = "input.stream_mode",
              bslib::card(
                class = "live-card",
                bslib::card_header("Live"),
                bslib::card_body(
                  shiny::div(
                    class = "live-transcription",
                    shiny::textOutput("live_text")
                  )
                )
              )
            ),

            # Text/Segments/Raw tabs
            bslib::navset_card_tab(
              id = "results_tabs",
              full_screen = FALSE,
              bslib::nav_panel("Text",
                shiny::div(
                  class = "text-output",
                  shiny::verbatimTextOutput("transcription")
                )
              ),
              bslib::nav_panel("Segments", shiny::tableOutput("segments")),
              bslib::nav_panel("Raw", shiny::verbatimTextOutput("raw"))
            )
          )
        )
      )
    )
  )
}

