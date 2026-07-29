% tinyrox says don't edit this manually, but it can't stop you!
\name{app_ui}
\alias{app_ui}
\title{App UI}
\usage{
app_ui()
}
\value{
A glinty UI tree.
}
\description{
Create the Earshot app user interface.
}
\details{
Assets are served from inst/app/www under /static/ by run_app().

Built from glinty's component vocabulary rather than from tags, so
the same tree renders in the browser and in a Flutter client. The
one deliberate exception is the record button: recording needs
MediaRecorder, which recorder.js drives by DOM id, so that control
is browser-only in behaviour even though it draws everywhere.

}
\keyword{internal}
