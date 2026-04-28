\name{autolabel-internal}
\alias{read_registry}
\alias{write_registry_entry}
\alias{check_for_dataset_updates}
\alias{filter_bundle}
\alias{resolve_scope}
\alias{normalize_token}
\alias{tag_primary}
\alias{infer_scope}
\alias{collapse_to_one_per_variable}
\alias{stamp_registream_attrs}
\alias{rs_filtered_bundle}
\alias{rs_scope_inference}
\alias{print.rs_filtered_bundle}
\alias{print.rs_scope_inference}
\title{Internal Autolabel Helpers}
\description{
These functions form the internal API that \code{\link{autolabel}},
\code{\link{scope}}, \code{\link{suggest}}, and
\code{\link{rs_lookup}} are built on. They are exported so advanced
users and testing harnesses can reach them without \code{:::}, but
most callers should use the top-level wrappers instead.
}
\details{
\strong{Dataset registry:}
\itemize{
  \item \code{read_registry(directory)} reads the \code{datasets.csv}
    registry; canonical column order is pinned for cross-client
    compatibility with Python and Stata.
  \item \code{write_registry_entry(directory, domain, file_type, lang,
    version, schema, file_size_dta, file_size_csv)} inserts or
    updates a single row. Existing \code{last_checked} values are
    preserved on update.
  \item \code{check_for_dataset_updates(domain, lang, directory)}
    performs a 24-hour-cached version check against the server's
    \code{/info} endpoint.
}

\strong{Filter pipeline (scope / release):}
\itemize{
  \item \code{filter_bundle(bundle, scope, release, datavars)} narrows
    an \code{rs_bundle} to the requested scope atom + release and
    runs \code{infer_scope} when no tokens are given. Returns an
    \code{rs_filtered_bundle} S3 list with narrowed variables +
    value_labels + scope_rows + \code{resolved_scope} +
    \code{resolved_release} + \code{auto_drilled_release} +
    \code{inferred}.
  \item \code{resolve_scope(bundle, tokens)} walks the
    alias\eqn{\to}name\eqn{\to}substring match ladder per level.
    Raises \code{rs_error_scope} on first-level miss.
  \item \code{normalize_token(x)} lowercase + strip apostrophes via
    \code{tolower(enc2utf8(x))}. Used everywhere matching happens.
  \item \code{tag_primary(variables, bundle, primary_levels)} marks
    rows of \code{variables} whose release_set_id maps to the given
    scope tuple with \code{_is_primary = 1L}.
}

\strong{Inference and collapse:}
\itemize{
  \item \code{infer_scope(bundle, datavars)} returns the
    \code{rs_scope_inference} for the scope tuple whose unique
    variable-name coverage best matches \code{datavars}. Ranks by
    matches desc, coverage desc, then scope tuple asc. Returns
    \code{NULL} on core-only bundles or no matches. The 10\%
    threshold sets \code{has_strong_primary}.
  \item \code{collapse_to_one_per_variable(filtered, bundle)} sorts
    rows by \code{(variable_name asc, _is_primary desc, _label_freq
    desc, scope_level_1 asc, ..., scope_level_N asc)} and dedups on
    \code{variable_name}. One row per variable out.
}

\strong{Post-labelling provenance:}
\itemize{
  \item \code{stamp_registream_attrs(df, domain, lang, scope, release,
    scope_depth, schema_version)} attaches a small
    \code{attr(df, "registream")} list recording what was applied.
    Consumed by \code{\link{info}} and \code{\link{suggest}} for
    surfacing the active scope after labelling.
}
}
\keyword{internal}
