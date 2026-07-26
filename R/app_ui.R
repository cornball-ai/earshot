#' App UI
#'
#' Create the Earshot app user interface.
#'
#' Assets are served from inst/app/www under /static/ by run_app().
#'
#' @return A glinty UI tree.
#'
#' @keywords internal
app_ui <- function() {
    # Placeholder text for the API key field
    #
    # Reports whether an environment key is in play without putting the
    # key itself anywhere near the page.
    key_placeholder <- function() {
        if (nzchar(Sys.getenv("OPENAI_API_KEY", ""))) {
            "using OPENAI_API_KEY (type to override)"
        } else {
            "sk-..."
        }
    }

    glinty::page(
                 title = "earshot",
                 css = "/static/styles.css",
                 js = "/static/recorder.js",
                 favicon = "/static/logo.png",

                 # Header
                 glinty::div(
                             class = "earshot-header",
                             glinty::div(
                class = "header-content",
                glinty::tag(
                            "a",
                            attrs = list(href = "https://cornball.ai",
                        target = "_blank", class = "header-link"),
                            children = list(
                        glinty::tag("img", attrs = list(
                                src = "/static/logo.png",
                                class = "header-logo",
                                alt = "cornball.ai"
                            )),
                        glinty::span("earshot", class = "header-title")
                    )
                )
            )
        ),

                 glinty::div(
                             class = "main-layout",

                             # Left: history
                             glinty::div(
                class = "left-sidebar",
                glinty::div(class = "sidebar-title", "History"),
                glinty::ui_output("config_display"),
                glinty::checkbox_input("save_audio_files", "Save audio files", FALSE),
                glinty::div(
                            class = "history-list",
                            glinty::ui_output("history_list")
                )
            ),

                             # Centre: input and results
                             glinty::div(
                class = "center-content",

                glinty::div(
                            class = "input-card",

                            glinty::div(
                                        class = "record-row",
                                        # recorder.js binds this by id; no glinty binding wanted
                                        glinty::tag("button", text = "Record", attrs = list(
                                id = "record_btn",
                                class = "g-btn btn-record",
                                type = "button"
                            )),
                                        glinty::span("", id = "record_timer", class = "record-timer")
                    ),

                            glinty::div(
                                        class = "input-divider",
                                        glinty::span("or", class = "divider-text")
                    ),

                            glinty::file_input(
                        "audio_file", "",
                        accept = c(".wav", ".mp3", ".m4a", ".ogg", ".flac", ".webm")
                    ),

                            glinty::checkbox_input("stream_mode", "Live transcription", FALSE),

                            glinty::ui_output("audio_preview"),

                            glinty::text_input(
                        "prompt", "Prompt (optional)",
                        placeholder = "Names, acronyms, or terms"
                    ),

                            glinty::button("transcribe", "Transcribe")
                ),

                glinty::div(
                            class = "results-column",

                            glinty::conditional_panel(
                        condition = glinty::input_is("stream_mode", TRUE),
                        glinty::div(
                                    class = "live-card",
                                    glinty::div(class = "panel-header", "Live"),
                                    glinty::div(
                                class = "live-transcription",
                                glinty::text_output("live_text")
                            )
                        )
                    ),

                            glinty::tabset(
                        glinty::tab_panel(
                            "Text",
                            glinty::div(
                                        class = "text-output",
                                        glinty::verbatim_output("transcription")
                            )
                        ),
                        glinty::tab_panel("Segments", glinty::table_output("segments")),
                        glinty::tab_panel("Raw", glinty::verbatim_output("raw")),
                        id = "results_tabs"
                    )
                )
            ),

                             # Right: settings
                             glinty::div(
                class = "right-sidebar",
                glinty::div(class = "sidebar-title", "Settings"),

                glinty::select_input(
                                     "backend", "Backend",
                                     choices = c("OpenAI API" = "openai"),
                                     selected = "openai"
                ),

                glinty::ui_output("model_select"),

                glinty::conditional_panel(
                    condition = glinty::input_is("backend", "whisper"),
                    glinty::ui_output("download_model_ui")
                ),

                glinty::select_input(
                                     "language", "Language",
                                     choices = c(
                        "English" = "en",
                        "Auto-detect" = "",
                        "Spanish" = "es",
                        "French" = "fr",
                        "German" = "de",
                        "Italian" = "it",
                        "Portuguese" = "pt",
                        "Japanese" = "ja",
                        "Chinese" = "zh"
                    ),
                                     selected = "en"
                ),

                glinty::conditional_panel(
                    condition = glinty::input_is("backend", "openai"),
                    glinty::text_input(
                                       "api_base", "API URL",
                                       value = "https://api.openai.com"
                    ),
                    # Deliberately NOT prefilled from OPENAI_API_KEY. A value=
                    # attribute is rendered into the page source in plaintext,
                    # where type="password" hides nothing, and glinty serves on
                    # all interfaces. The server already picks the environment
                    # key up in configure_backend(); this field is only for
                    # overriding it.
                    glinty::password_input(
                        "api_key", "API Key",
                        placeholder = key_placeholder()
                    )
                ),

                glinty::div(class = "status-line", glinty::text_output("status"))
            )
        )
    )
}
