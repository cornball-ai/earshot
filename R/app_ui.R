#' App UI
#'
#' Create the Earshot app user interface.
#'
#' Assets are served from inst/app/www under /static/ by run_app().
#'
#' Built from glinty's component vocabulary rather than from tags, so
#' the same tree renders in the browser and in a Flutter client. The
#' one deliberate exception is the record button: recording needs
#' MediaRecorder, which recorder.js drives by DOM id, so that control
#' is browser-only in behaviour even though it draws everywhere.
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

                 # Header: the logo and wordmark, both inside one link.
                 glinty::panel(
                               id = "earshot-header",
                               glinty::link(
                    href = "https://cornball.ai", external = TRUE,
                    children = list(glinty::row(
                            gap = 12L, align = "center",
                            glinty::image("/static/logo.png",
                                          alt = "cornball.ai", height = 32L),
                            glinty::txt("earshot", variant = "heading")
                        ))
                )
        ),

                 glinty::row(
                             gap = 16L,
                             id = "main-layout",

                             # Left: history. Fixed width, so the centre gets the rest.
                             glinty::panel(
                    variant = "sidebar", width = 280L,
                    glinty::heading("History", level = 3L),
                    glinty::ui_output("config_display"),
                    glinty::checkbox_input("save_audio_files",
                                           "Save audio files", FALSE),
                    glinty::ui_output("history_list")
                ),

                             # Centre: input and results. Takes the spare space.
                             glinty::column(
                    grow = 1L, gap = 16L,

                    # 2:3 rather than a 40% basis. The vocabulary has
                    # proportions, not percentages, and the ratio is
                    # what the layout actually meant.
                    glinty::panel(
                                  variant = "card", grow = 2L, id = "input-card",

                                  # recorder.js finds this by id and drives
                                  # MediaRecorder from it. It is a real glinty
                                  # button so it renders in every frontend; only
                                  # the recording behind it is browser-only.
                                  glinty::button("record_btn", "Record"),

                                  glinty::divider("or"),

                                  glinty::file_input(
                            "audio_file", "",
                            accept = c(".wav", ".mp3", ".m4a", ".ogg", ".flac",
                                       ".webm")
                        ),

                                  glinty::checkbox_input("stream_mode",
                                                         "Live transcription", FALSE),

                                  glinty::audio_output("audio_preview"),

                                  glinty::text_input(
                            "prompt", "Prompt (optional)",
                            placeholder = "Names, acronyms, or terms"
                        ),

                                  glinty::button("transcribe", "Transcribe",
                                                 variant = "primary")
                    ),

                    glinty::column(
                                   grow = 3L, gap = 12L,

                                   glinty::conditional_panel(
                            condition = glinty::input_is("stream_mode", TRUE),
                            glinty::panel(
                                          variant = "card", title = "Live",
                                          glinty::text_output("live_text")
                            )
                        ),

                                   glinty::tabset(
                            glinty::tab_panel(
                                "Text",
                                glinty::verbatim_output("transcription")
                            ),
                            glinty::tab_panel("Segments",
                                              glinty::table_output("segments")),
                            glinty::tab_panel("Raw",
                                              glinty::verbatim_output("raw")),
                            id = "results_tabs"
                        )
                    )
                ),

                             # Right: settings. Fixed width, like the left.
                             glinty::panel(
                    variant = "sidebar", width = 280L,
                    glinty::heading("Settings", level = 3L),

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
                        # Deliberately NOT prefilled from OPENAI_API_KEY. A
                        # value= attribute is rendered into the page source
                        # in plaintext, where type="password" hides nothing,
                        # and glinty serves on all interfaces. The server
                        # already picks the environment key up in
                        # configure_backend(); this field is only for
                        # overriding it.
                        glinty::password_input(
                            "api_key", "API Key",
                            placeholder = key_placeholder()
                        )
                    ),

                    glinty::text_output("status", variant = "muted")
                )
        )
    )
}
