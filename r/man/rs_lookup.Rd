\name{rs_lookup}
\alias{rs_lookup}
\alias{rs_lookup_result}
\alias{print.rs_lookup_result}
\title{Look Up Variable Metadata by Name}
\description{
Returns metadata (labels, units, value labels) for one or more
variables in the RegiStream catalog. Unlike \code{\link{autolabel}},
\code{rs_lookup} does not require a data frame -- it queries the
catalog directly by variable name and returns an
\code{rs_lookup_result} S3 object that prints as a compact summary.

Two aggregation modes:

\itemize{
  \item \strong{Default} (\code{detail = FALSE}): one row per
    \code{variable_name}, picking the most-common label across the
    scopes the variable appears in (with the
    \code{filter_bundle()}-tagged primary scope taking precedence on
    ties).
  \item \strong{Detail} (\code{detail = TRUE}): all matching rows
    enriched with \code{scope_level_1..N} and \code{release} columns
    so callers can see which scope each row came from.
}
}
\usage{
rs_lookup(variables,
          domain = "scb",
          lang = "eng",
          scope = NULL,
          release = NULL,
          detail = FALSE,
          directory = NULL)

\method{print}{rs_lookup_result}(x, ...)
}
\arguments{
\item{variables}{Character vector of variable names to look up.
  Matching is case-insensitive.}
\item{domain}{Dataset domain. Default \code{"scb"} (Statistics Sweden).}
\item{lang}{Language code. Default \code{"eng"}.}
\item{scope}{Optional character vector of scope-level tokens (same
  semantics as \code{\link{autolabel}}'s \code{scope} argument).
  Narrows the bundle to the matching atom before lookup.}
\item{release}{Optional release identifier. Filters scope rows to that
  release before lookup.}
\item{detail}{If \code{TRUE}, return all matching rows with the scope
  tuple attached instead of the one-per-variable default.}
\item{directory}{Override for the RegiStream cache directory.}
\item{x}{An \code{rs_lookup_result} object.}
\item{...}{Ignored for the print method.}
}
\value{
An \code{rs_lookup_result} S3 object -- a list with components:
\describe{
  \item{\code{df}}{A data frame of matched metadata rows. Includes a
    \code{value_labels} list-column where each cell holds a parsed
    named vector (names = labels, values = codes) or an empty vector
    if the variable has no value codes.}
  \item{\code{missing}}{Character vector of input variable names that
    were not found in the catalog, preserving the user's original
    casing.}
  \item{\code{scope_counts}}{Named list mapping lowered variable
    names to the number of distinct scope tuples each variable
    appears in.}
}
}
\seealso{
\code{\link{autolabel}}, \code{\link{scope}}, \code{\link{suggest}}
}
\keyword{manip}
