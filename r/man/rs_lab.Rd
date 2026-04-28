\name{rs_lab}
\alias{rs_lab}
\alias{rs_lab_head}
\title{Display a Labelled Data Frame with Value Labels Applied}
\description{
\code{rs_lab()} returns a copy of \code{x} where every
\code{haven_labelled} column has been converted to a factor whose
levels are the value labels (via \code{\link[haven]{as_factor}}). The
underlying data is not modified -- this is a display helper, not a
mutator. The canonical pattern is:

\preformatted{  df |> autolabel() |> rs_lab() |> head()}

\code{rs_lab_head()} is a shortcut for
\code{head(haven::as_factor(x), n)}.

This function is the R equivalent of the Python client's
\code{LabeledView} / \code{df.rs.lab} accessor. Python needs a
wrapper class because pandas has no native concept of
"display with labels applied without mutating the frame"; R has
\code{haven::as_factor()} which does exactly that, so the entire
replacement is a one-line wrapper.
}
\usage{
rs_lab(x)

rs_lab_head(x, n = 5L)
}
\arguments{
\item{x}{A data frame, tibble, or vector. Typically a
  \code{haven_labelled} column or a data frame containing such
  columns (for example, the result of \code{autolabel()}).}
\item{n}{Number of rows to return from \code{rs_lab_head()}. Default
  5.}
}
\value{
A data frame (or vector, if \code{x} is a vector) with labelled
columns replaced by factors. Unlabelled columns are unchanged.
}
\seealso{
\code{\link{autolabel}}, \code{\link[haven]{as_factor}}
}
\keyword{manip}
