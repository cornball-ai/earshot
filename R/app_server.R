#' App Server
#'
#' Server logic for the Earshot app.
#'
#' @param input glinty input proxy.
#' @param output glinty output proxy.
#' @param session glinty session.
#'
#' @return NULL (side effects only).
#'
#' @importFrom utils capture.output str
#' @keywords internal
app_server <- function(input, output, session) {
    result <- glinty::reactive_val(NULL)
    status_msg <- glinty::reactive_val("Ready. Record or upload audio to transcribe.")
    recorded_file <- glinty::reactive_val(NULL)
    model_refresh <- glinty::reactive_val(0) # Triggers model list refresh

    # Streaming transcription state
    streaming_chunks <- glinty::reactive_val(list()) # Accumulates chunk results
    streaming_text <- glinty::reactive_val("") # Combined live text

    # History state
    history <- glinty::reactive_val(load_history())
    selected_entry <- glinty::reactive_val(NULL)
    history_audio_file <- glinty::reactive_val(NULL) # Audio from selected entry

    # Track source type for history
    source_type <- glinty::reactive_val("record")

    # Detect available backends (in priority order)
    available_backends <- detect_backends()
    default_backend <- unname(available_backends[1]) # Get value, not name

    # Update backend choices in UI
    glinty::update_select_input(session, "backend",
                                choices = available_backends,
                                selected = default_backend)

    # Configure default backend
    configure_backend(default_backend, session)
    status_msg(paste0("Ready. Using ", names(available_backends)[1], "."))

    # The backend select is seeded from the DOM, so it always reads; the
    # model select is built by render_ui, and inputs that first appear
    # in dynamic UI stay NULL server-side until the user touches them.
    current_backend <- function() {
        opt_str(input$backend()) %||% default_backend
    }
    current_model <- function() {
        opt_str(input$model()) %||%
        get_models_for_backend(current_backend())$default
    }

    # Dynamic model selection based on backend (refreshes after download)
    output$model_select <- glinty::render_ui(function() {
        model_refresh() # Dependency to refresh after downloads
        models <- get_models_for_backend(current_backend())
        glinty::select_input("model", "Model",
                             choices = models$choices,
                             selected = models$default)
    })

    # Config display at top of sidebar
    output$config_display <- glinty::render_ui(function() {
        language <- opt_str(input$language()) %||% "auto"

        glinty::txt(paste0("Backend: ", current_backend(), " / ",
                           "Model: ", current_model() %||% "...", " / ",
                           "Language: ", language),
                    variant = "muted")
    })

    # Dynamic download model dropdown (only shows models NOT yet downloaded)
    output$download_model_ui <- glinty::render_ui(function() {
        model_refresh() # Dependency to refresh after downloads

        all_models <- c("tiny", "base", "small", "medium", "large-v3")
        if (requireNamespace("whisper", quietly = TRUE)) {
            downloaded <- whisper::list_downloaded_models()
            available <- setdiff(all_models, downloaded)
        } else {
            available <- all_models
        }

        if (length(available) == 0) {
            glinty::txt("All models downloaded", variant = "muted")
        } else {
            glinty::column(
                           gap = 8L,
                           glinty::select_input("download_model", "Download Model",
                    choices = available, selected = available[1]),
                           glinty::button("download_btn", "Download Weights",
                                          icon = "download")
            )
        }
    })

    # Update backend configuration when changed
    glinty::observe_event(input$backend, function() {
        configure_backend(input$backend(), session)
        status_msg(paste0("Backend: ", input$backend()))
    })

    # Keep the recorder's copy of the streaming flag in step
    glinty::observe_event(input$stream_mode, function() {
        glinty::send_custom_message(session, "set_stream_mode",
                                    isTRUE(input$stream_mode()))
    }, ignore_null = FALSE)

    # Model sizes in MB (approximate)
    model_sizes <- c(
                     tiny = 151, base = 290, small = 967,
                     medium = 3055, `large-v3` = 6174
    )

    # Handle whisper model download - show confirmation modal
    glinty::observe_event(input$download_btn, function() {
        model <- opt_str(input$download_model())
        if (is.null(model)) {
            return(invisible(NULL))
        }

        if (!requireNamespace("whisper", quietly = TRUE)) {
            status_msg("whisper package not installed.")
            return(invisible(NULL))
        }

        # Check if already downloaded
        if (whisper::model_exists(model)) {
            status_msg(paste0("Model '", model, "' is already downloaded."))
            return(invisible(NULL))
        }

        # Get size for display
        size_mb <- model_sizes[[model]]
        if (!is.null(size_mb)) {
            if (size_mb >= 1000) {
                size_str <- sprintf("%.1f GB", size_mb / 1000)
            } else {
                size_str <- paste0(size_mb, " MB")
            }
        } else {
            size_str <- "unknown size"
        }

        glinty::show_modal(
                           session,
                           glinty::txt(paste0("Download '", model, "' model (",
                    size_str, ") from HuggingFace?")),
                           title = "Download Model?",
                           footer = glinty::row(
                glinty::modal_button("Cancel"),
                glinty::button("confirm_download", "Download")
            )
        )
    })

    # Handle confirmed download
    glinty::observe_event(input$confirm_download, function() {
        glinty::remove_modal(session)
        model <- opt_str(input$download_model())
        if (is.null(model)) {
            return(invisible(NULL))
        }

        status_msg(paste0("Downloading '", model, "'... This may take a while."))

        # Download with consent option (modal = consent)
        tryCatch({
            old_opt <- getOption("whisper.consent")
            options(whisper.consent = TRUE)
            on.exit(options(whisper.consent = old_opt), add = TRUE)

            whisper::download_whisper_model(model)
            status_msg(paste0("Model '", model, "' downloaded successfully."))

            # Trigger model list refresh
            model_refresh(model_refresh() + 1)
        }, error = function(e) {
            status_msg(paste0("Download failed: ", conditionMessage(e)))
        })
    })

    # Handle recorded audio from JavaScript
    glinty::observe_event(input$recorded_audio, function() {
        audio_data <- input$recorded_audio()

        # Decode base64 and save to temp file
        raw_audio <- base64_decode(audio_data$data)
        tmp_file <- tempfile(fileext = ".webm")
        writeBin(raw_audio, tmp_file)

        recorded_file(tmp_file)
        source_type("record")

        # If in stream mode, save history here (where we have the audio)
        if (isTRUE(input$stream_mode())) {
            text <- streaming_text()
            if (nzchar(text)) {
                tryCatch({
                    entry <- create_history_entry(
                        text = text,
                        segments = NULL,
                        source_type = "record",
                        model = current_model(),
                        language = opt_str(input$language()),
                        backend = "openai"
                    )

                    # Save audio file if option enabled
                    if (isTRUE(input$save_audio_files())) {
                        entry$audio_file <- save_audio_file(tmp_file, entry$id)
                    }

                    new_history <- add_history_entry(history(), entry)
                    history(new_history)
                    save_history(new_history)
                }, error = function(e) {
                    message(">>> HISTORY ERROR: ", conditionMessage(e))
                })
            }
        } else {
            status_msg("Recording saved. Click Transcribe to process.")
        }
    })

    # Handle recording errors
    glinty::observe_event(input$recording_error, function() {
        status_msg(paste("Microphone error:", input$recording_error()))
    })

    # Update status during recording
    glinty::observe_event(input$recording_status, function() {
        if (identical(input$recording_status(), "recording")) {
            if (isTRUE(input$stream_mode())) {
                status_msg("Recording with live transcription...")
            } else {
                status_msg("Recording... Click Stop when done.")
            }
            recorded_file(NULL)
            history_audio_file(NULL) # Clear history audio on a new recording
            selected_entry(NULL)
            source_type("record")
            # Reset streaming state
            streaming_chunks(list())
            streaming_text("")
        }
    })

    # Track upload source type
    glinty::observe_event(input$audio_file, function() {
        source_type("upload")
        history_audio_file(NULL) # Clear history audio when uploading
        selected_entry(NULL)
    })

    # Handle streaming chunks for live transcription
    glinty::observe_event(input$streaming_chunk, function() {
        chunk_data <- input$streaming_chunk()
        if (is.null(chunk_data)) {
            return(invisible(NULL))
        }

        # Save chunk to temp file
        raw_audio <- base64_decode(chunk_data$data)
        tmp_file <- tempfile(fileext = ".webm")
        writeBin(raw_audio, tmp_file)

        # Convert to WAV
        wav_file <- ensure_wav(tmp_file, function(msg) NULL)
        if (is.null(wav_file)) {
            status_msg(paste0("Chunk ", chunk_data$index + 1, ": conversion failed"))
            unlink(tmp_file)
            return(invisible(NULL))
        }

        # Transcribe chunk
        tryCatch({
            res <- stt.api::stt(
                                file = wav_file,
                                model = current_model(),
                                language = opt_str(input$language()),
                                response_format = "verbose_json"
            )

            # Add to accumulated chunks
            chunks <- streaming_chunks()
            chunks[[length(chunks) + 1]] <- list(
                index = chunk_data$index,
                text = res$text
            )
            streaming_chunks(chunks)

            # Update combined text
            texts <- vapply(chunks, function(x) x$text, character(1))
            streaming_text(paste(texts, collapse = " "))

            status_msg(sprintf("Live: %d chunks transcribed", length(chunks)))

        }, error = function(e) {
            status_msg(paste0("Chunk ", chunk_data$index + 1, ": ",
                              conditionMessage(e)))
        })

        # Clean up temp files
        unlink(c(tmp_file, wav_file))
    })

    # Handle streaming complete signal - just update display
    # History is saved in recorded_audio handler where we have the audio file
    glinty::observe_event(input$streaming_complete, function() {
        text <- streaming_text()

        if (!nzchar(text)) {
            status_msg("Streaming complete. No text captured.")
            return(invisible(NULL))
        }

        # Set result for display
        result(list(
                    text = text,
                    segments = NULL,
                    backend = "openai",
                    language = opt_str(input$language())
            ))

        status_msg(sprintf("Done. %d chunks transcribed.",
                           length(streaming_chunks())))
    })

    # Output for live transcription text
    output$live_text <- glinty::render_text(function() {
        text <- streaming_text()
        if (nzchar(text)) text else "Waiting for audio..."
    })

    # Apply API settings when changed.
    #
    # The key field starts empty on purpose (see app_ui): an empty field
    # means "use OPENAI_API_KEY", which configure_backend() already
    # applied, so only a typed value overrides it. Nothing here ever
    # sends the key back to the browser.
    glinty::observe_event(function() {
        list(input$api_base(), input$api_key())
    }, function() {
        if (!identical(current_backend(), "openai")) {
            return(invisible(NULL))
        }
        api_base <- opt_str(input$api_base())
        if (!is.null(api_base)) {
            stt.api::set_stt_base(api_base)
        }
        api_key <- opt_str(input$api_key())
        if (!is.null(api_key)) {
            stt.api::set_stt_key(api_key)
        }
    })

    # Transcribe button
    glinty::observe_event(input$transcribe, function() {
        # Get audio file path (recorded takes priority if available)
        audio_path <- recorded_file()
        upload <- input$audio_file()
        if (is.null(audio_path) && !is.null(upload)) {
            audio_path <- upload$datapath[[1]]
        }

        if (is.null(audio_path)) {
            status_msg("No audio to transcribe. Record or upload a file first.")
            return(invisible(NULL))
        }

        # Store original path for audio saving
        original_audio_path <- audio_path

        status_msg("Preparing audio...")
        result(NULL)
        selected_entry(NULL)

        # Convert to 16-bit wav if needed
        audio_path <- ensure_wav(audio_path, status_msg)
        if (is.null(audio_path)) {
            return(invisible(NULL))
        }

        model <- current_model()
        backend <- current_backend()

        # Check if native whisper model is downloaded
        if (identical(backend, "whisper") && !is.null(model) &&
                          requireNamespace("whisper", quietly = TRUE) &&
                          !whisper::model_exists(model)) {
            status_msg(paste0(
                              "Model '", model, "' not downloaded. ",
                              "Use the Download Weights button above."
                ))
            return(invisible(NULL))
        }

        glinty::with_progress(session, message = "Transcribing...", {
            glinty::inc_progress(0.1, detail = "Preparing")

            language <- opt_str(input$language())
            prompt <- opt_str(input$prompt())

            glinty::inc_progress(0.2, detail = "Running transcription")

            tryCatch({
                res <- stt.api::stt(
                                    file = audio_path,
                                    model = model,
                                    language = language,
                                    prompt = prompt,
                                    response_format = "verbose_json"
                )

                glinty::inc_progress(0.6, detail = "Done")

                result(res)
                recorded_file(NULL) # Clear after successful transcription
                status_msg(sprintf("Done. Backend: %s, Language: %s",
                                   res$backend, res$language %||% "auto"))

                # Add to history
                tryCatch({
                    entry <- create_history_entry(
                        text = res$text,
                        segments = res$segments,
                        source_type = source_type(),
                        model = model,
                        language = language,
                        backend = res$backend,
                        raw = res$raw
                    )

                    # Save audio file if option enabled
                    if (isTRUE(input$save_audio_files())) {
                        entry$audio_file <- save_audio_file(original_audio_path,
                            entry$id)
                    }

                    # Add to history and save
                    new_history <- add_history_entry(history(), entry)
                    history(new_history)
                    save_history(new_history)
                }, error = function(e) {
                    message(">>> HISTORY ERROR: ", conditionMessage(e))
                })

            }, error = function(e) {
                status_msg(paste("Error:", conditionMessage(e)))
            })
        })
    })

    output$status <- glinty::render_text(function() {
        status_msg()
    })

    output$transcription <- glinty::render_text(function() {
        res <- result()
        if (is.null(res)) return("")
        res$text
    })

    output$segments <- glinty::render_table(function() {
        res <- result()
        if (is.null(res) || is.null(res$segments) || nrow(res$segments) == 0) {
            return(data.frame(Note = "Segments not available for this backend"))
        }
        res$segments
    })

    output$raw <- glinty::render_text(function() {
        res <- result()
        if (is.null(res)) return("")
        paste(capture.output(str(res$raw)), collapse = "\n")
    })

    # Audio preview
    #
    # render_audio() rather than a hand-built <audio> element: the
    # value is a source, and which element plays it is the frontend's
    # problem. NULL leaves the slot empty.
    output$audio_preview <- glinty::render_audio(function() {
        # If viewing history entry, only show history audio (or nothing)
        if (!is.null(selected_entry())) {
            audio_path <- history_audio_file()
        } else {
            # Check for recorded file first, then uploaded
            audio_path <- recorded_file()
            upload <- input$audio_file()
            if (is.null(audio_path) && !is.null(upload)) {
                audio_path <- upload$datapath[[1]]
            }
        }

        if (is.null(audio_path) || !file.exists(audio_path)) {
            return(NULL)
        }

        # Guess type from extension
        ext <- tolower(tools::file_ext(audio_path))
        audio_type <- switch(ext,
                             mp3 = "audio/mpeg",
                             wav = "audio/wav",
                             m4a = "audio/mp4",
                             ogg = "audio/ogg",
                             flac = "audio/flac",
                             webm = "audio/webm",
                             "audio/webm"
        )

        # Encode as base64 data URI
        audio_data <- base64_encode(
                                    readBin(audio_path, "raw", file.info(audio_path)$size))
        paste0("data:", audio_type, ";base64,", audio_data)
    })

    # History list rendering
    output$history_list <- glinty::render_ui(function() {
        hist <- history()
        sel <- selected_entry()

        if (length(hist) == 0) {
            return(glinty::txt("No transcriptions yet", variant = "muted"))
        }

        items <- lapply(hist, function(entry) {
            is_selected <- !is.null(sel) && sel == entry$id
            has_audio <- !is.null(entry$audio_file) &&
            file.exists(entry$audio_file)

            # Only when the audio was kept: the icon says where the
            # recording came from, and there is nothing to say when
            # there is no file.
            icon_el <- if (has_audio) {
                glinty::icon(if (identical(entry$source_type, "upload")) {
                                 "upload"
                             } else {
                                 "microphone"
                             })
            } else {
                NULL
            }

            # The timestamp is the button, and it carries the entry id
            # as its value -- one observer below serves every row and
            # reads which. Under protocol 2 this was a click bind on
            # the whole card; v3 has no clickable container, and a
            # button is the honest component for "press this".
            glinty::panel(
                          variant = if (is_selected) "card" else "plain",
                          glinty::row(
                                      gap = 8L, align = "center",
                                      icon_el,
                                      glinty::button(
                            "history_view",
                            paste("View", format_timestamp(entry$timestamp)),
                            variant = "ghost", value = entry$id
                        ),
                                      glinty::button("history_delete", "Delete",
                                                     variant = "ghost", icon = "trash",
                                                     value = entry$id)
                    ),
                          glinty::txt(truncate_text(entry$text, 80),
                                      variant = "muted")
            )
        })

        do.call(glinty::column, c(items, list(gap = 8L)))
    })

    # Handle history item view
    glinty::observe_event(input$history_view, function() {
        id <- input$history_view()
        hist <- history()

        # Find entry
        idx <- which(vapply(hist, function(e) identical(e$id, id), logical(1)))
        if (length(idx) == 0) {
            return(invisible(NULL))
        }

        entry <- hist[[idx[[1]]]]
        selected_entry(id)

        # Clear current recording and set history audio
        recorded_file(NULL)
        if (!is.null(entry$audio_file) && file.exists(entry$audio_file)) {
            history_audio_file(entry$audio_file)
        } else {
            history_audio_file(NULL)
        }

        # Load entry into result view
        result(list(
                    text = entry$text,
                    segments = entry$segments,
                    backend = entry$backend,
                    language = entry$language,
                    raw = entry$raw
            ))

        status_msg(sprintf("Loaded: %s (%s)",
                           format_timestamp(entry$timestamp),
                           entry$backend %||% "unknown"))
    })

    # Handle history item delete
    glinty::observe_event(input$history_delete, function() {
        id <- input$history_delete()

        # Delete entry
        updated <- delete_history_entry(history(), id)
        history(updated)
        save_history(updated)

        # Clear selection if deleted entry was selected
        if (!is.null(selected_entry()) && selected_entry() == id) {
            selected_entry(NULL)
            result(NULL)
        }

        status_msg("Entry deleted")
    })

    invisible(NULL)
}

# Null coalesce operator; also treats zero-length as absent
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) {
    y
} else {
    x
}

# Normalize an input value to a non-empty string, or NULL
#
# glinty inputs are NULL until set, and inputs created inside
# render_ui() stay NULL until the user touches them, so every optional
# string read goes through here rather than bare nzchar().
opt_str <- function(x) {
    if (is.null(x) || length(x) != 1L) {
        return(NULL)
    }
    if (is.na(x) || !nzchar(as.character(x))) {
        return(NULL)
    }
    as.character(x)
}

# Base64 decode (using jsonlite, a dependency of stt.api)
base64_decode <- function(x) {
    jsonlite::base64_dec(x)
}

# Base64 encode
base64_encode <- function(x) {
    jsonlite::base64_enc(x)
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
                      args = c("-y", "-i", shQuote(path), "-ar", "16000", "-ac", "1",
                               "-sample_fmt", "s16", shQuote(wav_path)),
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

    # Check for native whisper
    if (requireNamespace("whisper", quietly = TRUE)) {
        backends <- c(backends, "whisper (native)" = "whisper")
    }

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
configure_backend <- function(backend, session = NULL) {
    if (backend == "openai") {
        stt.api::set_stt_base("https://api.openai.com")
        key <- Sys.getenv("OPENAI_API_KEY", "")
        if (nzchar(key)) {
            stt.api::set_stt_key(key)
        }
    } else if (backend == "audio.whisper") {
        # Clear API settings to force local backend
        options(stt.api_base = NULL, stt.api_key = NULL)
    } else if (backend == "whisper") {
        # Native whisper - no API settings needed
        options(stt.api_base = NULL, stt.api_key = NULL)
    }
}

# Get models for a backend
get_models_for_backend <- function(backend) {
    if (backend == "openai") {
        list(choices = c("whisper-1" = "whisper-1"), default = "whisper-1")
    } else if (backend == "audio.whisper") {
        list(
             choices = c("tiny" = "tiny", "base" = "base", "small" = "small",
                         "medium" = "medium", "large" = "large"),
             default = "small"
        )
    } else if (backend == "whisper") {
        # Native whisper - only show downloaded models
        if (requireNamespace("whisper", quietly = TRUE)) {
            downloaded <- whisper::list_downloaded_models()
            if (length(downloaded) == 0) {
                # No models downloaded - show all with tiny as default
                list(
                     choices = c("tiny" = "tiny",
                                 "base" = "base",
                                 "small" = "small",
                                 "medium" = "medium",
                                 "large-v3" = "large-v3"),
                     default = "tiny"
                )
            } else {
                # Only show downloaded models
                choices <- stats::setNames(downloaded, downloaded)
                list(choices = choices, default = downloaded[1])
            }
        } else {
            # whisper not installed
            list(choices = c("tiny" = "tiny"), default = "tiny")
        }
    } else {
        list(choices = c("whisper-1" = "whisper-1"), default = "whisper-1")
    }
}
