% tinyrox says don't edit this manually, but it can't stop you!
\name{create_history_entry}
\alias{create_history_entry}
\title{Create a new history entry}
\usage{
create_history_entry(
  text,
  segments = NULL,
  source_type = "record",
  model = NULL,
  language = NULL,
  backend = NULL,
  raw = NULL
)
}
\arguments{
\item{text}{Transcribed text}

\item{segments}{Data frame of segments (or NULL)}

\item{source_type}{"record" or "upload"}

\item{model}{Model name used}

\item{language}{Language code}

\item{backend}{Backend used}

\item{raw}{Raw API response (optional)}
}
\value{
A history entry list
}
\description{
Create a new history entry
}
\keyword{internal}
