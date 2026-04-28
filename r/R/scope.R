# Depth-agnostic scope resolution for v3 bundles.
#
# Line-for-line port of
# `registream-autolabel/src/registream/autolabel/_filters.py`
# (normalize_token, resolve_scope, _tag_primary). The match ladder per
# level is:
#
#   1. exact match on scope_level_{N}_alias (if column present)
#   2. exact match on scope_level_{N}
#   3. substring match on scope_level_{N}
#
# Case- and apostrophe-insensitive throughout. First-level miss raises
# a classed `rs_error_scope` condition so callers can distinguish
# filter failures from generic errors.


# Lowercase + strip apostrophes. Python's `str.lower()` is Unicode-aware;
# in R we `enc2utf8` + `tolower` to get the equivalent on sv_SE.UTF-8 /
# C locales. Non-string input is coerced to "" (matches Python NaN
# handling in normalize_token).
normalize_token <- function(x) {
  if (is.null(x)) return("")
  if (length(x) == 0L) return("")
  if (length(x) > 1L) {
    return(unname(vapply(x, normalize_token, character(1L))))
  }
  if (is.na(x)) return("")
  s <- as.character(x)
  if (!nzchar(s)) return("")
  s <- tryCatch(enc2utf8(s), error = function(e) s)
  gsub("'", "", tolower(s), fixed = TRUE)
}


rs_error_scope <- function(message) {
  structure(
    class = c("rs_error_scope", "error", "condition"),
    list(message = message, call = sys.call(-1L))
  )
}


# Walk `tokens` against `bundle$scope` through the three-step ladder.
# Returns a list with:
#   scope_df: narrowed scope rows surviving every level match
#   resolved: character vector of the first-surviving-name per token
# Empty token ("" or NA) at a level means "all values at this level".
resolve_scope <- function(bundle, tokens) {
  if (is.null(bundle$scope)) {
    stop(rs_error_scope(
      "scope() requires the bundle's scope file (run rs_update_datasets to refresh)."
    ))
  }

  depth <- bundle$manifest$scope_depth
  scope_df <- bundle$scope
  resolved <- character(0)

  for (i in seq_along(tokens)) {
    raw <- tokens[[i]]
    if (i > depth) {
      stop(rs_error_scope(sprintf(
        "scope() level %d exceeds manifest scope_depth=%d.", i, depth
      )))
    }

    target <- normalize_token(raw)
    if (!nzchar(target)) {
      # Empty token = all values at this level; no narrowing.
      resolved <- c(resolved, "")
      next
    }

    name_col  <- sprintf("scope_level_%d", i)
    alias_col <- sprintf("scope_level_%d_alias", i)

    mask <- NULL

    # Step 1: exact match on alias column if present.
    if (alias_col %in% colnames(scope_df)) {
      alias_norm <- normalize_token(scope_df[[alias_col]])
      m <- alias_norm == target
      if (any(m, na.rm = TRUE)) {
        m[is.na(m)] <- FALSE
        mask <- m
      }
    }

    name_norm <- normalize_token(scope_df[[name_col]])

    # Step 2: exact match on the level name.
    if (is.null(mask)) {
      m <- name_norm == target
      if (any(m, na.rm = TRUE)) {
        m[is.na(m)] <- FALSE
        mask <- m
      }
    }

    # Step 3: substring match on the level name.
    if (is.null(mask)) {
      m <- grepl(target, name_norm, fixed = TRUE)
      if (any(m, na.rm = TRUE)) {
        m[is.na(m)] <- FALSE
        mask <- m
      }
    }

    if (is.null(mask)) {
      values <- unique(stats::na.omit(as.character(scope_df[[name_col]])))
      hint <- if (length(values) > 0L) {
        sprintf("\n  Available values: %s",
                paste(shQuote(utils::head(sort(values), 10L)), collapse = ", "))
      } else {
        ""
      }
      stop(rs_error_scope(sprintf(
        "No scope match at level %d for %s.%s",
        i, sQuote(raw), hint
      )))
    }

    scope_df <- scope_df[mask, , drop = FALSE]
    rownames(scope_df) <- NULL
    first_name <- as.character(scope_df[[name_col]])[[1L]]
    resolved <- c(resolved, first_name)
  }

  list(scope_df = scope_df, resolved = resolved)
}


# Return an integer 0/1 vector marking rows of `variables` whose
# release_set_id maps to the scope tuple `primary_levels`. Used by
# `filter_bundle` when scope was inferred (not explicit); only the
# winning-tuple rows get _is_primary=1 so the collapse sort prefers
# them without wiping non-primary labels.
tag_primary <- function(variables, bundle, primary_levels) {
  if (is.null(bundle$scope) || is.null(bundle$release_sets)) {
    return(rep(0L, nrow(variables)))
  }

  depth <- bundle$manifest$scope_depth
  if (depth < 1L || length(primary_levels) == 0L) {
    return(rep(0L, nrow(variables)))
  }

  matching <- bundle$scope
  for (i in seq_along(primary_levels)) {
    col <- sprintf("scope_level_%d", i)
    vals <- as.character(matching[[col]])
    vals[is.na(vals)] <- ""
    matching <- matching[vals == primary_levels[[i]], , drop = FALSE]
    if (nrow(matching) == 0L) break
  }

  if (nrow(matching) == 0L) return(rep(0L, nrow(variables)))

  primary_scope_ids <- unique(matching$scope_id)
  rs <- bundle$release_sets
  primary_rs_ids <- unique(
    rs$release_set_id[rs$scope_id %in% primary_scope_ids]
  )

  as.integer(variables$release_set_id %in% primary_rs_ids)
}
