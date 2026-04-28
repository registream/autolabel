# Scope / release filter for v3 bundles.
#
# `filter_bundle(bundle, scope, release, datavars)` narrows an rs_bundle
# to the requested scope atom + release, runs scope inference when no
# explicit tokens are given, and returns an rs_filtered_bundle for
# `collapse_to_one_per_variable()` downstream. Mirrors Python
# `registream.autolabel._filters.filter_bundle`.
#
# Semantics:
#   - scope = c(lvl1, ..., lvlK)   with K == scope_depth → narrow to atom
#   - scope = c(lvl1, ..., lvlK)   with K <  scope_depth → narrow to prefix
#   - scope = c(..., depth+1-th)   overflow rule: last token becomes release
#   - scope = NULL, datavars given → infer primary scope, tag _is_primary
#   - release = ... alone          → filter scope_rows by release
#   - auto-drill                  → single-release scope surfaces the release


rs_filter_error <- function(message) {
  structure(
    class = c("rs_error_filter", "error", "condition"),
    list(message = message, call = sys.call(-1L))
  )
}


rs_filtered_bundle <- function(variables,
                               value_labels,
                               scope_rows,
                               inferred             = NULL,
                               resolved_scope       = NULL,
                               resolved_release     = NULL,
                               auto_drilled_release = NULL,
                               contributing_scopes  = list()) {
  structure(
    list(
      variables            = variables,
      value_labels         = value_labels,
      scope_rows           = scope_rows,
      inferred             = inferred,
      resolved_scope       = resolved_scope,
      resolved_release     = resolved_release,
      auto_drilled_release = auto_drilled_release,
      contributing_scopes  = contributing_scopes
    ),
    class = "rs_filtered_bundle"
  )
}


#' @export
filter_bundle <- function(bundle,
                          scope    = NULL,
                          release  = NULL,
                          datavars = NULL) {
  if (!inherits(bundle, "rs_bundle")) {
    stop(rs_filter_error(
      "filter_bundle() requires an rs_bundle (use registream::load_bundle)."
    ))
  }

  tokens <- if (length(scope) == 0L) character(0) else as.character(scope)
  depth  <- bundle$manifest$scope_depth

  if (isTRUE(bundle$core_only) ||
      is.null(bundle$scope) ||
      is.null(bundle$release_sets)) {
    if (length(tokens) > 0L) {
      stop(rs_filter_error(paste0(
        "scope() requires a full bundle (manifest + scope + release_sets); ",
        "the loaded bundle is core-only. Re-download via rs_update_datasets()."
      )))
    }
    if (!is.null(release)) {
      stop(rs_filter_error(paste0(
        "release() requires a full bundle (manifest + scope + release_sets); ",
        "the loaded bundle is core-only. Re-download via rs_update_datasets()."
      )))
    }
    vars_out <- bundle$variables
    vars_out$`_is_primary` <- 0L
    return(rs_filtered_bundle(
      variables    = vars_out,
      value_labels = bundle$value_labels,
      scope_rows   = NULL
    ))
  }

  # Overflow-token → release (autolabel.ado:1499-1502).
  if (length(tokens) == depth + 1L && is.null(release)) {
    release <- tokens[[length(tokens)]]
    tokens  <- tokens[-length(tokens)]
  } else if (length(tokens) > depth) {
    stop(rs_filter_error(sprintf(
      paste0(
        "scope() has %d tokens but manifest declares scope_depth=%d ",
        "(overflow allows %d tokens where the last becomes release)."
      ),
      length(tokens), depth, depth + 1L
    )))
  }

  inferred <- NULL
  scope_rows <- bundle$scope
  resolved_levels <- NULL

  if (length(tokens) > 0L) {
    res <- resolve_scope(bundle, tokens)
    scope_rows       <- res$scope_df
    resolved_levels  <- res$resolved
  } else if (length(datavars) > 0L) {
    inferred <- infer_scope(bundle, datavars)
  }

  if (!is.null(release)) {
    rel_mask <- as.character(scope_rows$release) == as.character(release)
    rel_mask[is.na(rel_mask)] <- FALSE
    scope_rows <- scope_rows[rel_mask, , drop = FALSE]
    if (nrow(scope_rows) == 0L) {
      stop(rs_filter_error(sprintf(
        "No metadata found for release=%s at the requested scope.",
        sQuote(release)
      )))
    }
  }

  auto_drilled_release <- NULL
  if (length(tokens) > 0L && is.null(release)) {
    rels <- unique(as.character(scope_rows$release))
    if (length(rels) == 1L) auto_drilled_release <- rels
  }

  scope_ids <- unique(scope_rows$scope_id)
  rs <- bundle$release_sets
  release_set_ids <- unique(rs$release_set_id[rs$scope_id %in% scope_ids])

  variables <- bundle$variables
  if (length(tokens) > 0L || !is.null(release)) {
    keep <- variables$release_set_id %in% release_set_ids
    variables <- variables[keep, , drop = FALSE]
    rownames(variables) <- NULL
  }

  if (length(tokens) > 0L) {
    variables$`_is_primary` <- 1L
  } else if (!is.null(inferred)) {
    variables$`_is_primary` <- tag_primary(variables, bundle, inferred$levels)
  } else {
    variables$`_is_primary` <- 0L
  }

  rownames(scope_rows) <- NULL

  rs_filtered_bundle(
    variables            = variables,
    value_labels         = bundle$value_labels,
    scope_rows           = scope_rows,
    inferred             = inferred,
    resolved_scope       = if (length(resolved_levels) > 0L) resolved_levels else NULL,
    resolved_release     = release,
    auto_drilled_release = auto_drilled_release,
    contributing_scopes  = list()
  )
}


#' @export
print.rs_filtered_bundle <- function(x, ...) {
  rule <- strrep("-", 60)
  cat(rule, "\n")
  cat("RegiStream FilteredBundle\n")
  cat(rule, "\n")
  cat(sprintf("  variables:    %d rows\n", nrow(x$variables)))
  cat(sprintf("  value_labels: %d rows\n", nrow(x$value_labels)))
  if (!is.null(x$scope_rows)) {
    cat(sprintf("  scope_rows:   %d rows\n", nrow(x$scope_rows)))
  }
  if (!is.null(x$resolved_scope)) {
    cat(sprintf("  resolved_scope:   %s\n",
                paste(x$resolved_scope, collapse = " / ")))
  }
  if (!is.null(x$resolved_release)) {
    cat(sprintf("  resolved_release: %s\n", x$resolved_release))
  }
  if (!is.null(x$auto_drilled_release)) {
    cat(sprintf("  auto_drilled:     %s\n", x$auto_drilled_release))
  }
  if (!is.null(x$inferred)) {
    cat(sprintf("  inferred_primary: %s (%d / %d = %d%%)\n",
                paste(x$inferred$levels, collapse = " / "),
                x$inferred$matches,
                x$inferred$total_datavars,
                x$inferred$match_pct))
  }
  cat(rule, "\n")
  invisible(x)
}
