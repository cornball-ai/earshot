#' History Persistence Functions
#'
#' Functions for saving and loading transcription history.
#'
#' @keywords internal

#' Get the earshot data directory
#'
#' @return Path to ~/.earshot directory
#' @keywords internal
earshot_dir <- function() {
  path <- file.path(Sys.getenv("HOME"), ".earshot")
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }
  path
}

#' Get the audio storage directory
#'
#' @return Path to ~/.earshot/audio directory
#' @keywords internal
audio_dir <- function() {
  path <- file.path(earshot_dir(), "audio")
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }
  path
}

#' Get the history file path
#'
#' @return Path to ~/.earshot/history.rds
#' @keywords internal
history_file <- function() {
  file.path(earshot_dir(), "history.rds")
}

#' Load history from disk
#'
#' @return List of history entries (newest first), or empty list
#' @keywords internal
load_history <- function() {
  path <- history_file()
  if (file.exists(path)) {
    tryCatch(
      readRDS(path),
      error = function(e) list()
    )
  } else {
    list()
  }
}

#' Save history to disk
#'
#' @param history List of history entries
#' @keywords internal
save_history <- function(history) {
  saveRDS(history, history_file())
}

#' Generate a unique history entry ID
#'
#' @return Character string with timestamp + random suffix
#' @keywords internal
generate_id <- function() {
  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  suffix <- paste0(sample(letters, 6, replace = TRUE), collapse = "")
  paste0(timestamp, "_", suffix)
}

#' Create a new history entry
#'
#' @param text Transcribed text
#' @param segments Data frame of segments (or NULL)
#' @param source_type "record" or "upload"
#' @param model Model name used
#' @param language Language code
#' @param backend Backend used
#' @param raw Raw API response (optional)
#' @return A history entry list
#' @keywords internal
create_history_entry <- function(
  text,
  segments = NULL,
  source_type = "record",
  model = NULL,
  language = NULL,
  backend = NULL,
  raw = NULL
) {
  list(
    id = generate_id(),
    timestamp = Sys.time(),
    text = text,
    segments = segments,
    source_type = source_type,
    audio_file = NULL,
    model = model,
    language = language,
    backend = backend,
    raw = raw
  )
}

#' Add a history entry
#'
#' @param history Current history list
#' @param entry New entry to add
#' @return Updated history list (entry prepended)
#' @keywords internal
add_history_entry <- function(
  history,
  entry
) {
  c(list(entry), history)
}

#' Delete a history entry
#'
#' @param history Current history list
#' @param id ID of entry to delete
#' @return Updated history list with entry removed
#' @keywords internal
delete_history_entry <- function(
  history,
  id
) {
  # Find and remove entry
  idx <- which(vapply(history, function(e) e$id == id, logical(1)))
  if (length(idx) > 0) {
    # Delete audio file if exists
    entry <- history[[idx]]
    if (!is.null(entry$audio_file) && file.exists(entry$audio_file)) {
      unlink(entry$audio_file)
    }
    history <- history[- idx]
  }
  history
}

#' Save audio file for a history entry
#'
#' @param audio_path Path to source audio file
#' @param entry_id History entry ID
#' @return Path to saved audio file, or NULL on failure
#' @keywords internal
save_audio_file <- function(
  audio_path,
  entry_id
) {
  if (is.null(audio_path) || !file.exists(audio_path)) {
    return(NULL)
  }

  # Determine extension from source

  ext <- tolower(tools::file_ext(audio_path))
  if (ext == "") ext <- "webm"

  dest <- file.path(audio_dir(), paste0(entry_id, ".", ext))
  tryCatch({
      file.copy(audio_path, dest, overwrite = TRUE)
      dest
    }, error = function(e) {
      NULL
    })
}

#' Format timestamp for display
#'
#' @param timestamp POSIXct timestamp
#' @return Formatted string
#' @keywords internal
format_timestamp <- function(timestamp) {
  format(timestamp, "%b %d, %H:%M")
}

#' Truncate text for preview
#'
#' @param text Full text
#' @param max_chars Maximum characters
#' @return Truncated text with ellipsis if needed
#' @keywords internal
truncate_text <- function(
  text,
  max_chars = 60
) {
  if (nchar(text) <= max_chars) {
    text
  } else {
    paste0(substr(text, 1, max_chars - 3), "...")
  }
}

