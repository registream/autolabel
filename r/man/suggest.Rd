\name{suggest}
\alias{suggest}
\alias{rs_suggest_result}
\alias{print.rs_suggest_result}
\title{Preview Labeling Coverage Without Mutating Data}
\description{
Analyzes the columns of a data frame against the RegiStream catalog
and reports which scopes would contribute labels under automatic mode
-- without applying anything. Recommended first step for mixed-panel
labeling workflows.

R port of Python \code{registream.autolabel.suggest()} and the Stata
\code{autolabel suggest} subcommand.
}
\usage{
suggest(x, ...,
        domain    = "scb",
        lang      = "eng",
        release   = NULL,
        directory = NULL)

\method{print}{rs_suggest_result}(x, ...)
}
\arguments{
\item{x}{For \code{suggest()}: a data frame (or tibble) whose columns
  drive the coverage analysis. For \code{print.rs_suggest_result()}:
  an \code{rs_suggest_result} object.}
\item{...}{For \code{suggest()}: optional scope-level tokens (same
  semantics as \code{\link{scope}}'s \code{...}). When given, the
  coverage calc is narrowed to that scope atom. For the print method:
  ignored.}
\item{domain}{Dataset domain. Default \code{"scb"}.}
\item{lang}{Language code. Default \code{"eng"}.}
\item{release}{Optional release identifier. Narrows the coverage calc
  to that release.}
\item{directory}{Override the RegiStream cache directory.}
}
\value{
An \code{rs_suggest_result} S3 list with components:
\describe{
  \item{\code{coverage}}{A data frame: one row per candidate scope
    tuple, columns \code{scope_level_1..N}, \code{matches} (distinct
    variable hits), \code{coverage_pct}, and \code{is_primary}
    (\code{TRUE} when the scope is the inferred primary with
    \code{>= 10\%} match).}
  \item{\code{primary}}{An \code{rs_scope_inference} object for the
    winning tuple, or \code{NULL} when no scope cleared the 10\%
    threshold (mixed-panel data).}
  \item{\code{pin_command}}{A copy-pasteable
    \code{autolabel(df, domain = ..., scope = c(...))} call that
    would reproduce the inferred pin.}
}
}
\examples{
\dontrun{
df <- haven::read_dta("lisa_2020.dta")

# Full coverage preview
result <- suggest(df)
print(result)

# Scope-specific preview
suggest(df, "LISA")
suggest(df, "LISA", "Individer 16 \u00e5r och \u00e4ldre")
}
}
\seealso{
\code{\link{autolabel}}, \code{\link{scope}}
}
\keyword{manip}
