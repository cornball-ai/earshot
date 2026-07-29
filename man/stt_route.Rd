% tinyrox says don't edit this manually, but it can't stop you!
\name{stt_route}
\alias{stt_route}
\title{How an earshot backend maps onto stt.api's two axes}
\usage{
stt_route(backend)
}
\arguments{
\item{backend}{character earshot backend value}
}
\value{
list(backend, source) for [stt.api::stt]
}
\description{
stt.api asks *which engine* and *where it runs* separately, and
defaults both to "auto". Its auto rule is
`if (.has_whisper()) route <- "package"` -- local whisper wins
whenever the package is installed, and set_stt_base() is never
consulted. earshot passed neither argument, so every transcription
went in process no matter which backend was selected.
}
\keyword{internal}
