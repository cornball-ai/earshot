# Test history persistence functions

# Test generate_id format
id <- earshot:::generate_id()
expect_true(is.character(id))
expect_true(nchar(id) > 20)
expect_true(grepl("^\\d{14}_[a-z]{6}$", id))

# Test create_history_entry
entry <- earshot:::create_history_entry(
  text = "Test transcription",
  source_type = "record",
  model = "whisper-1",
  language = "en",
  backend = "openai"
)
expect_true(is.list(entry))
expect_equal(entry$text, "Test transcription")
expect_equal(entry$source_type, "record")
expect_equal(entry$model, "whisper-1")
expect_equal(entry$backend, "openai")
expect_true(inherits(entry$timestamp, "POSIXct"))
expect_true(!is.null(entry$id))

# Test add_history_entry
history <- list()
history <- earshot:::add_history_entry(history, entry)
expect_equal(length(history), 1)
expect_equal(history[[1]]$text, "Test transcription")

# Add another entry
entry2 <- earshot:::create_history_entry(
  text = "Second transcription",
  source_type = "upload"
)
history <- earshot:::add_history_entry(history, entry2)
expect_equal(length(history), 2)
# New entry should be first (prepended)
expect_equal(history[[1]]$text, "Second transcription")
expect_equal(history[[2]]$text, "Test transcription")

# Test delete_history_entry
history <- earshot:::delete_history_entry(history, entry$id)
expect_equal(length(history), 1)
expect_equal(history[[1]]$text, "Second transcription")

# Test truncate_text
expect_equal(earshot:::truncate_text("Short", 60), "Short")
expect_equal(
  earshot:::truncate_text("This is a very long text that exceeds the maximum character limit", 30),
  "This is a very long text th..."
)

# Test format_timestamp
ts <- as.POSIXct("2026-01-22 14:30:00")
formatted <- earshot:::format_timestamp(ts)
expect_true(grepl("Jan 22", formatted))
expect_true(grepl("14:30", formatted))
