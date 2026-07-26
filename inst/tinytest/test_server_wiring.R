# Server-side wiring against a headless glinty session. No browser
# involved: build the session, feed it input messages the way the
# client would, and read what the server queued back.

new_session <- glinty:::new_session
session_end <- glinty:::session_end
with_session <- glinty:::with_session
dispatch <- glinty:::dispatch_client_message
tag_to_html <- glinty:::tag_to_html

app_ui <- earshot:::app_ui
app_server <- earshot:::app_server
opt_str <- earshot:::opt_str
detect_backends <- earshot:::detect_backends
get_models_for_backend <- earshot:::get_models_for_backend

json <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)

start <- function(id = "t1") {
  s <- new_session(id)
  with_session(s, app_server(s$input, s$output, s))
  glinty::flush_reactions()
  s
}

sent_of <- function(s, type) {
  Filter(function(m) identical(m$type, type), lapply(s$outgoing, json))
}

# --- the UI tree builds and renders ---
ui <- app_ui()
html <- tag_to_html(ui)
expect_true(nchar(html) > 1000)
expect_true(grepl('id="record_btn"', html, fixed = TRUE))
expect_true(grepl("g-tabset", html, fixed = TRUE))
expect_true(grepl("data-g-cond", html, fixed = TRUE))

# --- the API key never reaches the page ---
# type="password" only masks on screen; a value= attribute is plain
# text in the source, and glinty serves on all interfaces.
expect_true(grepl('id="api_key"', html, fixed = TRUE))
expect_false(grepl("sk-", html, fixed = TRUE))
key <- Sys.getenv("OPENAI_API_KEY", "")
if (nzchar(key)) {
  expect_false(grepl(key, html, fixed = TRUE))
}

# --- the server starts without error and seeds its outputs ---
s <- start()
expect_true(length(s$outgoing) > 0L)

# status reports readiness rather than staying blank
status <- sent_of(s, "update")
status_ids <- vapply(status, function(m) m$id, character(1L))
expect_true("status" %in% status_ids)

# --- opt_str: the guard every optional input read goes through ---
expect_null(opt_str(NULL))
expect_null(opt_str(""))
expect_null(opt_str(character(0)))
expect_null(opt_str(NA))
expect_null(opt_str(NA_character_))
expect_equal(opt_str("en"), "en")
expect_equal(opt_str(3L), "3")
# a two-element vector is not a scalar string
expect_null(opt_str(c("a", "b")))

# --- history rows carry their own id on a click bind ---
# This replaces the old inline onclick + Shiny.setInputValue strings.
s2 <- start("t2")
entry <- list(id = "abc123", text = "hello world", timestamp = Sys.time(),
              source_type = "record", backend = "openai")
with_session(s2, {
  s2$output$history_list <- glinty::render_ui(function() {
    glinty::tag("div",
      attrs = list(class = "history-item"),
      bind = list(event = "click", target = "history_view",
                  value = entry$id),
      children = list(glinty::div(class = "history-preview", entry$text)))
  })
})
glinty::flush_reactions()
ui_msgs <- Filter(function(m) identical(m$property, "ui"), sent_of(s2, "update"))
expect_true(length(ui_msgs) > 0L)
row <- ui_msgs[[length(ui_msgs)]]$value
expect_equal(row$bind$target, "history_view")
expect_equal(row$bind$value, "abc123")
session_end(s2)

# --- an object-valued input from app JS arrives with names intact ---
# recorder.js sends {data, type, size, index, timestamp}; if these
# collapsed to an unnamed vector, chunk_data$data would be NULL.
s3 <- new_session("t3")
dispatch(s3, paste0('{"type":"input","id":"streaming_chunk","value":',
                    '{"data":"QUJD","type":"audio/webm","size":3,',
                    '"index":0,"timestamp":123}}'))
chunk <- glinty::isolate(s3$input$streaming_chunk())
expect_true(is.list(chunk))
expect_equal(chunk$data, "QUJD")
expect_equal(chunk$index, 0L)
expect_equal(chunk$type, "audio/webm")
session_end(s3)

# --- backend helpers are unchanged pure R ---
backends <- detect_backends()
expect_true(length(backends) >= 1L)
expect_true(all(nzchar(names(backends))))

models <- get_models_for_backend("openai")
expect_equal(models$default, "whisper-1")
expect_true("whisper-1" %in% models$choices)
# an unknown backend still answers rather than erroring
expect_equal(get_models_for_backend("nonsense")$default, "whisper-1")

session_end(s)
