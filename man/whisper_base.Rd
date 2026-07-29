% tinyrox says don't edit this manually, but it can't stop you!
\name{whisper_base}
\alias{whisper_base}
\title{The address of a remote whisper serve(), or ""}
\usage{
whisper_base()
}
\value{
character URL, or "" when none is configured
}
\description{
From the environment rather than a constant: the host is site
configuration, not something to bake into a package. `whisper::serve()`
listens on 7809 by default, so this is usually
`EARSHOT_WHISPER_BASE=http://somehost:7809`.
}
\keyword{internal}
