% tinyrox says don't edit this manually, but it can't stop you!
\name{whisper_local_works}
\alias{whisper_local_works}
\title{Can whisper actually run in this process?}
\usage{
whisper_local_works()
}
\value{
TRUE when whisper is installed and torch is ready
}
\description{
The package being installed says nothing about whether its torch
backend is: torch ships lantern separately, and without it every
call fails at transcription time. Checked here so a backend that
cannot work is never offered, rather than being offered, defaulted
to, and failing on the first press.
}
\keyword{internal}
