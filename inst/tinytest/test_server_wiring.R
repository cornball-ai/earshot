# Server-side wiring against a headless glinty session. No browser
# involved: build the session, feed it input messages the way the
# client would, and read what the server queued back.

new_session <- glinty:::new_session
session_end <- glinty:::session_end
with_session <- glinty:::with_session
dispatch <- glinty:::dispatch_client_message
component_to_html <- glinty:::component_to_html

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
html <- component_to_html(ui)
expect_true(nchar(html) > 1000)
expect_true(grepl('id="record_btn"', html, fixed = TRUE))
expect_true(grepl("g-tabset", html, fixed = TRUE))
expect_true(grepl("data-g-cond", html, fixed = TRUE))

# --- the API key never reaches the page ---
# type="password" only masks on screen; a value= attribute is plain
# text in the source, and glinty serves on all interfaces.
expect_true(grepl('id="api_key"', html, fixed = TRUE))
# Key-shaped, not just the prefix. The placeholder is literally
# "sk-..." when no key is in the environment, so grepling for "sk-"
# passed on a machine that had one set and failed on CI, which does
# not -- reporting a leak that was the hint text all along.
expect_false(grepl("sk-[A-Za-z0-9_-]{20,}", html))
key <- Sys.getenv("OPENAI_API_KEY", "")
if (nzchar(key)) {
  expect_false(grepl(key, html, fixed = TRUE))
}

# --- the server starts without error and seeds its outputs ---
s <- start()
expect_true(length(s$outgoing) > 0L)

# status reports readiness rather than staying blank
status <- sent_of(s, "output")
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

# --- history rows carry their own id on a valued button ---
#
# Protocol 2 put a click bind on the row div, carrying the entry id.
# v3 has no clickable container: the timestamp is a button and the id
# rides on the event as its value. One observer still serves every
# row -- the press says which.
s2 <- start("t2")
entry <- list(id = "abc123", text = "hello world", timestamp = Sys.time(),
              source_type = "record", backend = "openai")
with_session(s2, {
  s2$output$history_list <- glinty::render_ui(function() {
    glinty::column(
      glinty::button("history_view", "12:04", value = entry$id),
      glinty::txt(entry$text, variant = "muted"))
  })
})
glinty::flush_reactions()
ui_msgs <- Filter(function(m) identical(m$kind, "ui"), sent_of(s2, "output"))
expect_true(length(ui_msgs) > 0L)
row <- ui_msgs[[length(ui_msgs)]]$value
btn <- row$children[[1]]
expect_equal(btn$component, "button")
expect_equal(btn$id, "history_view")
expect_equal(btn$value, "abc123")

# and a list of them lowers without a duplicate DOM id: the component
# id names the handler, not the element, which is what lets rows share
# one
rows_html <- component_to_html(glinty::column(
  glinty::button("history_view", "a", value = "a"),
  glinty::button("history_view", "b", value = "b")))
expect_false(grepl(' id="history_view"', rows_html, fixed = TRUE))
expect_equal(length(gregexpr('data-g-value="', rows_html)[[1]]), 2L)
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

# --- no stylesheet rule targets something the page never renders ---
#
# The port moved elements from classes to ids and glinty later stopped
# giving event buttons a DOM id at all, so a selector could quietly
# stop matching and nothing would notice: CSS fails silently by
# design. #transcribe was dead for exactly that reason.
css <- readLines(system.file("app/www/styles.css", package = "earshot"),
                 warn = FALSE)
served <- component_to_html(app_ui())
ids_in_page <- unique(gsub('.*id="([^"]*)".*', "\\1",
                           regmatches(served,
                                      gregexpr('id="[^"]*"', served))[[1]]))

# every #id selector at the start of a line, ignoring media-query
# indentation
sel <- regmatches(css, regexpr("^\\s*#[A-Za-z0-9_-]+", css))
sel <- unique(sub("^\\s*#", "", sel))
expect_true(length(sel) > 0L)
dead <- setdiff(sel, ids_in_page)
expect_equal(dead, character(0))

# and the routing hooks the stylesheet uses are really emitted
targets <- regmatches(css, gregexpr('\\[data-g-target="[^"]*"\\]', css))[[1]]
for (t in unique(targets)) {
    expect_true(grepl(t, served, fixed = TRUE))
}

# --- which engine, and where it runs, said outright ---
#
# stt.api asks those separately and defaults both to "auto", and its
# auto rule is `if (.has_whisper()) route <- "package"`: local whisper
# wins whenever the package is installed, and set_stt_base() is never
# consulted. earshot passed neither argument, so every transcription
# went in process no matter which backend was selected -- which on a
# machine whose torch is half-installed means every press failed on
# "Lantern is not loaded", including the OpenAI one.
stt_route <- earshot:::stt_route
expect_equal(stt_route("openai"), list(backend = "openai", source = "api"))
expect_equal(stt_route("whisper-api"), list(backend = "whisper", source = "api"))
expect_equal(stt_route("whisper"),
             list(backend = "whisper", source = "package"))
# A backend this has not been taught is stt.api's call, not a guess
expect_equal(stt_route("something-new"),
             list(backend = "auto", source = "auto"))

# every backend the app offers has a route
whisper_base <- earshot:::whisper_base

# Set it, check, restore. A helper for this was more machinery than
# two blocks of test need.
Sys.setenv(EARSHOT_WHISPER_BASE = "http://example.test:7809")
expect_equal(whisper_base(), "http://example.test:7809")
offered <- detect_backends()
expect_true("whisper-api" %in% offered)
# first, so it is the default: a remote GPU beats in-process CPU
expect_equal(unname(offered[1]), "whisper-api")
for (b in offered) {
  expect_false(identical(stt_route(b)$backend, "auto"))
}

Sys.unsetenv("EARSHOT_WHISPER_BASE")
expect_equal(whisper_base(), "")
expect_false("whisper-api" %in% detect_backends())

# --- a backend that cannot run is not offered ---
# requireNamespace() says the package is installed; it says nothing
# about whether torch is ready. Offering it anyway made a broken
# backend the default.
expect_true(is.logical(earshot:::whisper_local_works()))
expect_equal(length(earshot:::whisper_local_works()), 1L)

# The invariant that matters: a backend in the list can be run. Held
# only as "does it have a route" this passed while the list offered an
# in-process whisper whose torch could not start -- and offered it
# first, so it was the default, so the first press of Transcribe died.
if ("whisper" %in% detect_backends()) {
  expect_true(earshot:::whisper_local_works())
}
if ("whisper-api" %in% detect_backends()) {
  expect_true(nzchar(earshot:::whisper_base()))
}
if ("openai" %in% detect_backends()) {
  # either an environment key, or the fallback that lets one be typed
  expect_true(nzchar(Sys.getenv("OPENAI_API_KEY", "")) ||
              identical(unname(detect_backends()), "openai"))
}

configure_backend <- earshot:::configure_backend
old_base <- getOption("stt.api_base")

# What the user typed wins. The field defaults to OpenAI's host, so
# honouring it costs nothing in the common case and is the only way to
# reach an OpenAI-compatible endpoint elsewhere -- which the field
# exists to allow and which this used to hardcode past.
configure_backend("openai", base = "http://compatible.test:1234")
expect_equal(getOption("stt.api_base"), "http://compatible.test:1234")

Sys.setenv(EARSHOT_WHISPER_BASE = "http://example.test:7809")
configure_backend("whisper-api")
expect_equal(getOption("stt.api_base"), "http://example.test:7809")
Sys.unsetenv("EARSHOT_WHISPER_BASE")

# Transcription is not a quick API call. stt.api caps the total at 60s
# by default, which cuts a long recording off and looks to the user
# like the server failed.
old_timeout <- getOption("stt.timeout")
Sys.setenv(EARSHOT_WHISPER_BASE = "http://example.test:7809")
configure_backend("whisper-api")
expect_true(getOption("stt.timeout") > 60)
# and it stays overridable, for whoever knows their own tape better
options(earshot.stt_timeout = 123)
configure_backend("whisper-api")
expect_equal(getOption("stt.timeout"), 123)
options(earshot.stt_timeout = NULL, stt.timeout = old_timeout)
Sys.unsetenv("EARSHOT_WHISPER_BASE")

configure_backend("whisper")
expect_null(getOption("stt.api_base"))
options(stt.api_base = old_base)

# --- a model belonging to the previous backend is not used ---
# render_ui() rebuilds the model select when the backend changes, and
# v3 deliberately does not echo the new tree's values back, so the
# server goes on holding "tiny" after a switch to a backend whose only
# model is "whisper-1".
s4 <- new_session("t4")
with_session(s4, app_server(s4$input, s4$output, s4))
glinty::flush_reactions()
dispatch(s4, '{"type":"input","id":"backend","value":"whisper"}')
dispatch(s4, '{"type":"input","id":"model","value":"tiny"}')
glinty::flush_reactions()
dispatch(s4, '{"type":"input","id":"backend","value":"openai"}')
glinty::flush_reactions()
expect_equal(glinty::isolate(s4$input$model()), "tiny",
             info = "the stale value really is still there")
# and the app does not use it
models <- get_models_for_backend("openai")
expect_false("tiny" %in% models$choices)
session_end(s4)
