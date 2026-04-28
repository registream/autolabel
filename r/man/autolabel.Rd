\name{autolabel}
\alias{autolabel}
\alias{autolabel.data.frame}
\title{Apply Variable and Value Labels to a Data Frame}
\description{
Apply curated variable and value labels from the RegiStream metadata
catalog to the columns of a data frame. Variable labels become the
\code{"label"} attribute on each column; value labels are attached via
\code{\link[haven]{labelled}} so the column gets a \code{"labels"}
attribute and the \code{"haven_labelled"} class. The underlying data is
not modified -- labels are metadata only.

\code{autolabel} runs the v3 pipeline against a 5-file metadata bundle
(\code{manifest_\{lang\}.csv}, \code{variables_\{lang\}.dta},
\code{value_labels_\{lang\}.dta}, \code{scope_\{lang\}.dta},
\code{release_sets_\{lang\}.dta}). Use \code{scope} to pin a particular
register / sub-population, \code{release} to pin a year, or omit both
to let the function auto-infer the best-matching scope from the user's
columns (the inferred scope is reported as a message).
}
\usage{
autolabel(x, ...)

\method{autolabel}{data.frame}(x,
                               domain = "scb",
                               lang = "eng",
                               scope = NULL,
                               release = NULL,
                               label_type = c("both", "variables", "values"),
                               variables = NULL,
                               exclude = NULL,
                               include_unit = TRUE,
                               dryrun = FALSE,
                               directory = NULL,
                               ...)
}
\arguments{
\item{x}{A \code{data.frame} (or tibble) of register data.}
\item{domain}{Dataset domain. Default \code{"scb"} (Statistics Sweden).}
\item{lang}{Language code. Default \code{"eng"}; \code{"swe"} also
  available for the SCB domain.}
\item{scope}{Optional character vector of scope-level tokens (case- and
  apostrophe-insensitive, alias-or-name match). The depth is driven by
  the manifest's \code{scope_depth}. As an overflow shorthand, passing
  \code{scope_depth + 1} tokens promotes the trailing token to
  \code{release}.}
\item{release}{Optional release identifier (typically a year). Filters
  the bundle's scope rows to that release before labelling.}
\item{label_type}{One of \code{"both"} (default), \code{"variables"},
  or \code{"values"}.}
\item{variables}{Optional character vector restricting which columns
  receive labels. Names not in \code{x} are silently skipped.}
\item{exclude}{Optional character vector of columns to skip when
  applying labels. Applied after \code{variables}. Mirrors the Stata
  \code{exclude()} option and the Python \code{exclude=} parameter.}
\item{include_unit}{If \code{TRUE} (default), append \code{" (unit)"}
  to variable labels when \code{variable_unit} is non-empty in the
  metadata. Matches the Stata client.}
\item{dryrun}{If \code{TRUE}, return an \code{autolabel_dryrun} S3
  object describing what would be stamped without mutating \code{x}.
  Mirrors the Stata \code{dryrun} flag and the Python
  \code{dryrun=TRUE} parameter. The returned object carries
  \code{variable_labels}, \code{value_labels}, \code{skipped_vars},
  \code{resolved_scope}, and \code{resolved_release} fields; a
  \code{print} method renders counts. Default \code{FALSE}.}
\item{directory}{Override for the RegiStream cache directory. Useful
  for testing with a synthetic fixture; otherwise inherits from
  \code{REGISTREAM_DIR} or \code{tools::R_user_dir("registream", "cache")}.}
\item{...}{Reserved for future use.}
}
\value{
When \code{dryrun = FALSE} (default): the input data frame with column
attributes set. Columns that have a matching \code{variable_name} in
the metadata gain a \code{"label"} attribute; columns with a non-empty
\code{value_label_id} additionally become \code{haven_labelled} with a
\code{"labels"} named vector. The returned object also carries a small
\code{"registream"} list attribute recording \code{domain},
\code{lang}, \code{scope}, \code{release}, and \code{scope_depth} for
downstream introspection (see \code{\link{info}}). Columns with no
metadata entry are unchanged.

When \code{dryrun = TRUE}: an \code{autolabel_dryrun} S3 object (a
list with five fields) describing the planned labeling without
touching \code{x}.
}
\seealso{
\code{\link[haven]{labelled}}, \code{\link[haven]{as_factor}},
\code{\link{scope}}, \code{\link{suggest}}
}
\keyword{manip}
