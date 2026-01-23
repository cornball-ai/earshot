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
app_server <- function(
  input,
  output,
  session
) {

  result <- shiny::reactiveVal(NULL)
  status_msg <- shiny::reactiveVal("Ready. Record or upload audio to transcribe.")
  recorded_file <- shiny::reactiveVal(NULL)
  model_refresh <- shiny::reactiveVal(0) # Triggers model list refresh

  # Streaming transcription state
  streaming_chunks <- shiny::reactiveVal(list()) # Accumulates chunk results
  streaming_text <- shiny::reactiveVal("") # Combined live text

  # History state
  history <- shiny::reactiveVal(load_history())
  selected_entry <- shiny::reactiveVal(NULL)
  history_audio_file <- shiny::reactiveVal(NULL) # Audio from selected history entry

  # Track source type for history
  source_type <- shiny::reactiveVal("record")

  # Detect available backends (in priority order)
  available_backends <- detect_backends()
  default_backend <- unname(available_backends[1]) # Get value, not name

  # Update backend choices in UI
  shiny::updateSelectInput(session, "backend",
    choices = available_backends,
    selected = default_backend)

  # Configure default backend
  configure_backend(default_backend, session)
  status_msg(paste0("Ready. Using ", names(available_backends)[1], "."))

  # Dynamic model selection based on backend (refreshes after download)
  output$model_select <- shiny::renderUI({
      model_refresh() # Dependency to refresh after downloads
      backend <- input$backend
      if (is.null(backend)) backend <- default_backend

      models <- get_models_for_backend(backend)
      shiny::selectInput("model", "Model",
        choices = models$choices,
        selected = models$default)
    })

  # Config display at top of sidebar
  output$config_display <- shiny::renderUI({
      backend <- input$backend
      model <- input$model
      language <- input$language

      if (is.null(backend)) backend <- default_backend
      if (is.null(model)) model <- "..."
      if (is.null(language) || language == "") language <- "auto"

      shiny::tags$pre(
        id = "config_box",
        style = "font-family: 'JetBrains Mono', monospace; font-size: 0.8rem; color: #94a3b8; padding: 0.5rem; background: #f8fafc; border-radius: 6px; border: none;",
        paste0("Backend: ", backend, "\n",
          "Model: ", model, "\n",
          "Language: ", language)
      )
    })

  # Dynamic download model dropdown (only shows models NOT yet downloaded)
  output$download_model_ui <- shiny::renderUI({
      model_refresh() # Dependency to refresh after downloads

      all_models <- c("tiny", "base", "small", "medium", "large-v3")
      if (requireNamespace("whisper", quietly = TRUE)) {
        downloaded <- whisper::list_downloaded_models()
        available <- setdiff(all_models, downloaded)
      } else {
        available <- all_models
      }

      if (length(available) == 0) {
        shiny::div(
          class = "download-model-section text-muted",
          "All models downloaded"
        )
      } else {
        shiny::div(
          class = "download-model-section",
          shiny::selectInput("download_model", "Download Model",
            choices = available, selected = available[1]),
          shiny::actionButton("download_btn", "Download Weights",
            class = "btn-secondary btn-sm w-100")
        )
      }
    })

  # Update backend configuration when changed
  shiny::observeEvent(input$backend, {
      configure_backend(input$backend, session)
      status_msg(paste0("Backend: ", input$backend))
    }, ignoreInit = TRUE)

  # Model sizes in MB (approximate)
  model_sizes <- c(
    tiny = 151, base = 290, small = 967,
    medium = 3055, `large-v3` = 6174
  )

  # Handle whisper model download - show confirmation modal

  shiny::observeEvent(input$download_btn, {
      model <- input$download_model
      if (is.null(model) || model == "") return()

      if (!requireNamespace("whisper", quietly = TRUE)) {
        status_msg("whisper package not installed.")
        return()
      }

      # Check if already downloaded
      if (whisper::model_exists(model)) {
        status_msg(paste0("Model '", model, "' is already downloaded."))
        return()
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

      # Show confirmation modal
      shiny::showModal(shiny::modalDialog(
          title = "Download Model?",
          paste0("Download '", model, "' model (", size_str, ") from HuggingFace?"),
          footer = shiny::tagList(
            shiny::modalButton("Cancel"),
            shiny::actionButton("confirm_download", "Download", class = "btn-primary")
          )
        ))
    })

  # Handle confirmed download
  shiny::observeEvent(input$confirm_download, {
      shiny::removeModal()
      model <- input$download_model

      status_msg(paste0("Downloading '", model, "'... This may take a while."))

      # Download with consent option (modal = consent)
      tryCatch({
          old_opt <- getOption("whisper.consent")
          options(whisper.consent = TRUE)
          on.exit(options(whisper.consent = old_opt), add = TRUE)

          whisper::download_whisper_model(model)
          status_msg(paste0("Model '", model, "' downloaded successfully!"))

          # Trigger model list refresh
          model_refresh(model_refresh() + 1)
        }, error = function(e) {
          status_msg(paste0("Download failed: ", conditionMessage(e)))
        })
    })

  # Handle recorded audio from JavaScript
  shiny::observeEvent(input$recorded_audio, {
      audio_data <- input$recorded_audio

      # Decode base64 and save to temp file
      raw_audio <- base64_decode(audio_data$data)
      tmp_file <- tempfile(fileext = ".webm")
      writeBin(raw_audio, tmp_file)

      recorded_file(tmp_file)
      source_type("record")

      # If in stream mode, save history here (where we have the audio)
      if (isTRUE(input$stream_mode)) {
        text <- streaming_text()
        if (nzchar(text)) {
          tryCatch({
              message(">>> Creating history entry from streaming (in recorded_audio)")
              entry <- create_history_entry(
                text = text,
                segments = NULL,
                source_type = "record",
                model = input$model,
                language = input$language,
                backend = "openai"
              )
              message(">>> Entry ID: ", entry$id)

              # Save audio file if option enabled
              if (isTRUE(input$save_audio_files)) {
                saved_path <- save_audio_file(tmp_file, entry$id)
                entry$audio_file <- saved_path
                message(">>> Saved audio to: ", saved_path)
              }

              new_history <- add_history_entry(history(), entry)
              message(">>> History length: ", length(new_history))
              history(new_history)
              save_history(new_history)
              message(">>> Saved to: ", history_file())
            }, error = function(e) {
              message(">>> HISTORY ERROR: ", conditionMessage(e))
            })
        }
      } else {
        status_msg("Recording saved. Click Transcribe to process.")
      }
    })

  # Handle recording errors
  shiny::observeEvent(input$recording_error, {
      status_msg(paste("Microphone error:", input$recording_error))
    })

  # Update status during recording
  shiny::observeEvent(input$recording_status, {
      if (input$recording_status == "recording") {
        if (isTRUE(input$stream_mode)) {
          status_msg("Recording with live transcription...")
        } else {
          status_msg("Recording... Click Stop when done.")
        }
        recorded_file(NULL)
        history_audio_file(NULL) # Clear history audio when starting new recording
        selected_entry(NULL)
        source_type("record")
        # Reset streaming state
        streaming_chunks(list())
        streaming_text("")
      }
    })

  # Track upload source type
  shiny::observeEvent(input$audio_file, {
      if (!is.null(input$audio_file)) {
        source_type("upload")
        history_audio_file(NULL) # Clear history audio when uploading new file
        selected_entry(NULL)
      }
    })

  # Handle streaming chunks for live transcription
  shiny::observeEvent(input$streaming_chunk, {
      chunk_data <- input$streaming_chunk
      message(">>> Received chunk: ", chunk_data$index)
      if (is.null(chunk_data)) return()

      # Save chunk to temp file
      raw_audio <- base64_decode(chunk_data$data)
      tmp_file <- tempfile(fileext = ".webm")
      writeBin(raw_audio, tmp_file)
      message(">>> Saved chunk to: ", tmp_file, " size: ", file.size(tmp_file))

      # Convert to WAV
      wav_file <- ensure_wav(tmp_file, function(msg) NULL)
      if (is.null(wav_file)) {
        message(">>> WAV conversion failed")
        status_msg(paste0("Chunk ", chunk_data$index + 1, ": conversion failed"))
        return()
      }
      message(">>> Converted to WAV: ", wav_file)

      # Get current model settings
      if (nzchar(input$model)) {
        model <- input$model
      } else {
        model <- NULL
      }
      if (nzchar(input$language)) {
        language <- input$language
      } else {
        language <- NULL
      }

      # Transcribe chunk
      tryCatch({
          message(">>> Transcribing chunk ", chunk_data$index)
          res <- stt.api::transcribe(
            file = wav_file,
            model = model,
            language = language,
            response_format = "verbose_json"
          )
          message(">>> Transcription result: ", res$text)

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
          message(">>> Transcription error: ", conditionMessage(e))
          status_msg(paste0("Chunk ", chunk_data$index + 1, ": ", conditionMessage(e)))
        })

      # Clean up temp files
      unlink(c(tmp_file, wav_file))
    })

  # Handle streaming complete signal - just update display
  # History is saved in recorded_audio handler where we have the audio file
  shiny::observeEvent(input$streaming_complete, {
      text <- streaming_text()

      if (!nzchar(text)) {
        status_msg("Streaming complete. No text captured.")
        return()
      }

      # Set result for display
      result(list(
          text = text,
          segments = NULL,
          backend = "openai",
          language = input$language
        ))

      status_msg(sprintf("Done. %d chunks transcribed.", length(streaming_chunks())))
    })

  # Output for live transcription text
  output$live_text <- shiny::renderText({
      text <- streaming_text()
      if (nzchar(text)) text else "Waiting for audio..."
    })

  # Apply API settings when changed
  shiny::observeEvent(list(input$api_base, input$api_key), {
      if (input$backend == "openai" && nzchar(input$api_base)) {
        stt.api::set_stt_base(input$api_base)
        if (nzchar(input$api_key)) {
          stt.api::set_stt_key(input$api_key)
        }
      }
    }, ignoreInit = TRUE)

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

      # Store original path for audio saving
      original_audio_path <- audio_path

      status_msg("Preparing audio...")
      result(NULL)
      selected_entry(NULL)

      # Convert to 16-bit wav if needed
      audio_path <- ensure_wav(audio_path, status_msg)
      if (is.null(audio_path)) return()

      shiny::withProgress(message = "Transcribing...", value = 0, {

          shiny::incProgress(0.1, detail = "Preparing")

          if (nzchar(input$model)) {
            model <- input$model
          } else {
            model <- NULL
          }

          # Check if native whisper model is downloaded
          if (input$backend == "whisper" && !is.null(model)) {
            if (requireNamespace("whisper", quietly = TRUE) &&
              !whisper::model_exists(model)) {
              status_msg(paste0(
                  "Model '", model, "' not downloaded. ",
                  "Use the Download Weights button above."
                ))
              return()
            }
          }
          if (nzchar(input$language)) {
            language <- input$language
          } else {
            language <- NULL
          }
          if (nzchar(input$prompt)) {
            prompt <- input$prompt
          } else {
            prompt <- NULL
          }

          shiny::incProgress(0.2, detail = "Running transcription")

          tryCatch({
              res <- stt.api::transcribe(
                file = audio_path,
                model = model,
                language = language,
                prompt = prompt,
                response_format = "verbose_json"
              )

              shiny::incProgress(0.7, detail = "Done")

              result(res)
              recorded_file(NULL) # Clear after successful transcription
              status_msg(sprintf("Done. Backend: %s, Language: %s",
                  res$backend, res$language %||% "auto"))

              # Add to history
              tryCatch({
                  message(">>> Creating history entry")
                  entry <- create_history_entry(
                    text = res$text,
                    segments = res$segments,
                    source_type = source_type(),
                    model = model,
                    language = language,
                    backend = res$backend,
                    raw = res$raw
                  )
                  message(">>> Entry ID: ", entry$id)

                  # Save audio file if option enabled
                  if (isTRUE(input$save_audio_files)) {
                    saved_path <- save_audio_file(original_audio_path, entry$id)
                    entry$audio_file <- saved_path
                    message(">>> Saved audio to: ", saved_path)
                  }

                  # Add to history and save
                  new_history <- add_history_entry(history(), entry)
                  message(">>> History length: ", length(new_history))
                  history(new_history)
                  save_history(new_history)
                  message(">>> Saved to: ", history_file())
                }, error = function(e) {
                  message(">>> HISTORY ERROR: ", conditionMessage(e))
                })

            }, error = function(e) {
              status_msg(paste("Error:", conditionMessage(e)))
            })
        }) # end withProgress
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
      if (is.null(res)) return(NULL)
      if (is.null(res$segments) || nrow(res$segments) == 0) {
        return(data.frame(Note = "Segments not available for this backend"))
      }
      res$segments
    })

  output$raw <- shiny::renderText({
      res <- result()
      if (is.null(res)) return("")
      paste(capture.output(str(res$raw)), collapse = "\n")
    })

  # Audio preview
  output$audio_preview <- shiny::renderUI({
      # If viewing history entry, only show history audio (or nothing)
      if (!is.null(selected_entry())) {
        audio_path <- history_audio_file()
        if (is.null(audio_path) || !file.exists(audio_path)) {
          return(NULL)
        }
      } else {
        # Check for recorded file first, then uploaded
        audio_path <- recorded_file()

        if (is.null(audio_path) && !is.null(input$audio_file)) {
          audio_path <- input$audio_file$datapath
        }

        if (is.null(audio_path) || !file.exists(audio_path)) {
          return(NULL)
        }
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
      audio_data <- base64_encode(readBin(audio_path, "raw", file.info(audio_path)$size))
      data_uri <- paste0("data:", audio_type, ";base64,", audio_data)

      shiny::div(
        class = "audio-preview",
        shiny::tags$label("Preview", class = "control-label"),
        shiny::tags$audio(
          src = data_uri,
          controls = "controls",
          style = "width: 100%;"
        )
      )
    })

  # History list rendering
  output$history_list <- shiny::renderUI({
      hist <- history()
      sel <- selected_entry()

      if (length(hist) == 0) {
        return(shiny::div(
            class = "history-empty",
            "No transcriptions yet"
          ))
      }

      items <- lapply(hist, function(entry) {
          is_selected <- !is.null(sel) && sel == entry$id
          has_audio <- !is.null(entry$audio_file) && file.exists(entry$audio_file)

          # Only show icon if audio is saved
          icon_el <- if (has_audio) {
            if (entry$source_type == "upload") {
              icon <- "upload"
            } else {
              icon <- "mic"
            }
            shiny::span(class = paste("history-icon", icon))
          } else {
            NULL
          }

          shiny::div(
            class = paste("history-item", if (is_selected) "selected" else ""),
            `data-id` = entry$id,
            onclick = sprintf("Shiny.setInputValue('history_view', '%s', {priority: 'event'})", entry$id),
            shiny::div(
              class = "history-item-header",
              icon_el,
              shiny::span(class = "history-timestamp", format_timestamp(entry$timestamp)),
              shiny::tags$button(
                class = "history-delete-btn",
                onclick = sprintf("event.stopPropagation(); Shiny.setInputValue('history_delete', '%s', {priority: 'event'})", entry$id),
                "x"
              )
            ),
            shiny::div(
              class = "history-preview",
              truncate_text(entry$text, 80)
            )
          )
        })

      shiny::tagList(items)
    })

  # Handle history item view
  shiny::observeEvent(input$history_view, {
      id <- input$history_view
      hist <- history()

      # Find entry
      idx <- which(vapply(hist, function(e) e$id == id, logical(1)))
      if (length(idx) == 0) return()

      entry <- hist[[idx]]
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
  shiny::observeEvent(input$history_delete, {
      id <- input$history_delete

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
}

# Null coalesce operator
`%||%` <- function(
  x,
  y
) if (is.null(x)) y else x

# Base64 decode (using jsonlite, a dependency of stt.api)
base64_decode <- function(x) {
  jsonlite::base64_dec(x)
}

# Base64 encode
base64_encode <- function(x) {
  jsonlite::base64_enc(x)
}

# Convert audio to 16-bit wav if needed (requires ffmpeg)
ensure_wav <- function(
  path,
  status_fn = message
) {
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
configure_backend <- function(
  backend,
  session = NULL
) {
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
    list(
      choices = c("whisper-1" = "whisper-1"),
      default = "whisper-1"
    )
  } else if (backend == "audio.whisper") {
    list(
      choices = c("tiny" = "tiny",
        "base" = "base",
        "small" = "small",
        "medium" = "medium",
        "large" = "large"),
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
      list(
        choices = c("tiny" = "tiny"),
        default = "tiny"
      )
    }
  } else {
    list(choices = c("whisper-1" = "whisper-1"), default = "whisper-1")
  }
}

