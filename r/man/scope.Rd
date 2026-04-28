\name{scope}
\alias{scope}
\title{Browse the RegiStream Catalog (Depth-Agnostic)}
\description{
Depth-agnostic catalog browser. R port of the Stata
\code{autolabel scope} subcommand and Python
\code{registream.autolabel.scope()}. Returns a plain data frame at every
level; callers can chain base R, dplyr, gt, or anything else.

Scope-level tokens come in through \code{...}, matching Stata's
\code{autolabel scope LISA Individer} syntax. A bare vector also works:
\code{scope(c("LISA", "Individer"))} is equivalent to
\code{scope("LISA", "Individer")}.
}
\usage{
scope(...,
      domain    = "scb",
      lang      = "eng",
      search    = NULL,
      release   = NULL,
      directory = NULL)
}
\arguments{
\item{...}{Zero or more scope-level tokens. See Details for the four
  modes driven by token count vs the manifest's \code{scope_depth}.}
\item{domain}{Dataset domain. Default \code{"scb"} (Statistics Sweden).}
\item{lang}{Language code. Default \code{"eng"}.}
\item{search}{Optional substring filter applied to the active level's
  name column (case- and apostrophe-insensitive).}
\item{release}{Optional release identifier. Combined with full-depth
  tokens, switches the return to a per-variable table for that scope
  atom.}
\item{directory}{Override the RegiStream cache directory. Defaults to
  \code{REGISTREAM_DIR} env var, then the \code{cache_dir} config field,
  then \code{tools::R_user_dir("registream", "cache")}.}
}
\details{
Four modes, driven by the number of tokens vs the manifest's
\code{scope_depth}:
\enumerate{
  \item \strong{No tokens, no release} \eqn{\to} level-1 browse with a
    \code{variable_count} column.
  \item \strong{K < scope_depth tokens} \eqn{\to} level-(K+1) browse
    under the resolved prefix.
  \item \strong{K == scope_depth tokens} \eqn{\to} one row per release
    at that scope atom.
  \item \strong{Tokens + \code{release}} (or \code{scope_depth + 1}
    tokens via the overflow rule) \eqn{\to} one row per variable at
    that \code{(scope, release)} atom.
}
Matching per level uses a three-step ladder, case- and
apostrophe-insensitive: (1) exact alias match on
\code{scope_level_N_alias}, (2) exact name match on
\code{scope_level_N}, (3) name substring match.
}
\value{
A plain \code{data.frame}. Columns depend on the active mode -- see
Details.
}
\examples{
\dontrun{
# Level-1 browse
scope()

# Drill under LISA
scope("LISA")

# Releases at an atom
scope("LISA", "Individer 16 \u00e5r och \u00e4ldre")

# Variables at an atom (overflow-token shorthand)
scope("LISA", "Individer 16 \u00e5r och \u00e4ldre", "2021")

# Filtered level-1 browse
scope(search = "lisa")
}
}
\seealso{
\code{\link{autolabel}}, \code{\link{suggest}}, \code{\link{rs_lookup}}
}
\keyword{manip}
