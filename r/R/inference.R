# Scope inference for v3 bundles.
#
# `infer_scope(bundle, datavars)` picks the scope tuple whose unique-
# variable coverage best matches the user's columns. Mirrors Python
# `registream.autolabel._inference.infer_scope`. Ranks by:
#   1. matches DESC           (unique variable hits in this scope)
#   2. coverage DESC          (total unique variables reachable in scope)
#   3. scope_level_1..N ASC   (deterministic tie-break)
# Returns NULL when the bundle is core-only, datavars is empty, or
# nothing matches.

.STRONG_PRIMARY_PCT <- 10L


rs_scope_inference <- function(levels,
                               level_aliases,
                               matches,
                               total_datavars,
                               match_pct,
                               has_strong_primary) {
  structure(
    list(
      levels             = as.character(levels),
      level_aliases      = as.character(level_aliases),
      matches            = as.integer(matches),
      total_datavars     = as.integer(total_datavars),
      match_pct          = as.integer(match_pct),
      has_strong_primary = isTRUE(has_strong_primary)
    ),
    class = "rs_scope_inference"
  )
}


#' @export
print.rs_scope_inference <- function(x, ...) {
  cat(sprintf("Inferred primary scope: %s\n",
              paste(x$levels, collapse = " / ")))
  cat(sprintf("  matches:            %d / %d (%d%%)\n",
              x$matches, x$total_datavars, x$match_pct))
  cat(sprintf("  has_strong_primary: %s\n",
              if (x$has_strong_primary) "TRUE" else "FALSE"))
  invisible(x)
}


#' @export
infer_scope <- function(bundle, datavars) {
  if (is.null(datavars) || length(datavars) == 0L) return(NULL)
  if (!inherits(bundle, "rs_bundle")) return(NULL)
  if (isTRUE(bundle$core_only) ||
      is.null(bundle$scope) ||
      is.null(bundle$release_sets)) {
    return(NULL)
  }

  depth <- bundle$manifest$scope_depth
  if (depth < 1L) return(NULL)

  level_cols <- sprintf("scope_level_%d", seq_len(depth))
  alias_cols <- sprintf("scope_level_%d_alias", seq_len(depth))

  datavars_lower <- unique(tolower(as.character(datavars)))
  datavars_lower <- datavars_lower[nzchar(datavars_lower)]
  if (length(datavars_lower) == 0L) return(NULL)

  var_names_lower <- tolower(as.character(bundle$variables$variable_name))
  matching_mask <- var_names_lower %in% datavars_lower
  if (!any(matching_mask)) return(NULL)

  scope_keep_cols <- c("scope_id", level_cols,
                       intersect(alias_cols, colnames(bundle$scope)))
  scope_min <- bundle$scope[, scope_keep_cols, drop = FALSE]
  rs_min <- bundle$release_sets[, c("release_set_id", "scope_id"), drop = FALSE]
  scope_per_rs <- merge(rs_min, scope_min, by = "scope_id", all.x = FALSE,
                        all.y = FALSE, sort = FALSE)
  scope_per_rs <- scope_per_rs[!duplicated(scope_per_rs$release_set_id), ,
                               drop = FALSE]

  matched_vars <- bundle$variables[matching_mask, c("variable_name",
                                                    "release_set_id"),
                                   drop = FALSE]
  matched_vars$variable_name <- tolower(as.character(matched_vars$variable_name))
  joined <- merge(matched_vars, scope_per_rs, by = "release_set_id",
                  all.x = FALSE, all.y = FALSE, sort = FALSE)
  if (nrow(joined) == 0L) return(NULL)

  key_match <- do.call(paste,
                       c(lapply(level_cols, function(c) as.character(joined[[c]])),
                         list(joined$variable_name, sep = "\001")))
  joined_uniq <- joined[!duplicated(key_match), , drop = FALSE]
  level_key <- do.call(paste,
                       c(lapply(level_cols,
                                function(c) as.character(joined_uniq[[c]])),
                         list(sep = "\001")))
  matches_tbl <- table(level_key)

  all_vars <- bundle$variables[, c("variable_name", "release_set_id"),
                               drop = FALSE]
  all_vars$variable_name <- tolower(as.character(all_vars$variable_name))
  all_joined <- merge(all_vars, scope_per_rs, by = "release_set_id",
                      all.x = FALSE, all.y = FALSE, sort = FALSE)
  cov_match_key <- do.call(paste,
                           c(lapply(level_cols,
                                    function(c) as.character(all_joined[[c]])),
                             list(all_joined$variable_name, sep = "\001")))
  all_joined_uniq <- all_joined[!duplicated(cov_match_key), , drop = FALSE]
  cov_level_key <- do.call(paste,
                           c(lapply(level_cols,
                                    function(c) as.character(all_joined_uniq[[c]])),
                             list(sep = "\001")))
  coverage_tbl <- table(cov_level_key)

  tuples_str <- names(matches_tbl)
  tuples_mat <- do.call(rbind,
                        strsplit(tuples_str, "\001", fixed = TRUE))
  if (ncol(tuples_mat) < depth) {
    pad <- matrix("", nrow = nrow(tuples_mat),
                  ncol = depth - ncol(tuples_mat))
    tuples_mat <- cbind(tuples_mat, pad)
  }
  colnames(tuples_mat) <- level_cols

  ranking <- as.data.frame(tuples_mat, stringsAsFactors = FALSE)
  ranking$matches  <- as.integer(unname(matches_tbl))
  ranking$coverage <- as.integer(unname(
    coverage_tbl[match(tuples_str, names(coverage_tbl))]
  ))
  ranking$coverage[is.na(ranking$coverage)] <- 0L
  ranking <- ranking[ranking$matches > 0L, , drop = FALSE]
  if (nrow(ranking) == 0L) return(NULL)

  order_args <- c(
    list(-ranking$matches, -ranking$coverage),
    lapply(level_cols, function(c) ranking[[c]])
  )
  ord <- do.call(order, c(order_args, list(method = "radix")))
  ranking <- ranking[ord, , drop = FALSE]
  top <- ranking[1L, , drop = FALSE]

  levels <- as.character(unlist(top[, level_cols, drop = FALSE]))

  alias_rows <- scope_per_rs
  for (i in seq_along(level_cols)) {
    col_vals <- as.character(alias_rows[[level_cols[[i]]]])
    col_vals[is.na(col_vals)] <- ""
    alias_rows <- alias_rows[col_vals == levels[[i]], , drop = FALSE]
  }
  level_aliases <- character(depth)
  for (i in seq_len(depth)) {
    alias_col <- alias_cols[[i]]
    if (alias_col %in% colnames(alias_rows) && nrow(alias_rows) > 0L) {
      vals <- trimws(as.character(alias_rows[[alias_col]]))
      vals <- vals[!is.na(vals) & nzchar(vals)]
      level_aliases[[i]] <- if (length(vals) > 0L) vals[[1L]] else ""
    } else {
      level_aliases[[i]] <- ""
    }
  }

  total <- length(datavars_lower)
  matches <- as.integer(top$matches)
  match_pct <- if (total == 0L) 0L else as.integer(round(matches / total * 100))

  rs_scope_inference(
    levels             = levels,
    level_aliases      = level_aliases,
    matches            = matches,
    total_datavars     = total,
    match_pct          = match_pct,
    has_strong_primary = match_pct >= .STRONG_PRIMARY_PCT
  )
}
