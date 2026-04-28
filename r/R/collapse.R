# Collapse a filtered bundle to one metadata row per variable_name.
#
# Line-for-line port of
# `registream-autolabel/src/registream/autolabel/_collapse.py`, which
# mirrors Stata `_al_collapse_rep1`. Sort key per variable:
#
#   1. `_is_primary` DESC -- prefer inferred / pinned primary scope rows
#   2. `_label_freq` DESC -- prefer the most-common label across scopes
#   3. `scope_level_1` ASC ... `scope_level_N` ASC -- deterministic
#      tie-break via the scope tuple (depth driven by manifest).
#
# The collapse is lossless relative to _filter_bundle_: every surviving
# variable_name keeps a row; duplicates are dropped only after the sort
# so the tie-break is reproducible.

collapse_to_one_per_variable <- function(filtered, bundle) {
  if (!inherits(filtered, "rs_filtered_bundle")) {
    stop("collapse_to_one_per_variable() requires an rs_filtered_bundle.",
         call. = FALSE)
  }
  variables <- filtered$variables
  if (nrow(variables) == 0L) return(variables)

  depth <- bundle$manifest$scope_depth
  level_cols <- if (depth > 0L) sprintf("scope_level_%d", seq_len(depth)) else character(0)

  joined <- variables

  if (depth > 0L &&
      !is.null(bundle$scope) &&
      !is.null(bundle$release_sets)) {
    scope_cols <- c("scope_id", level_cols)
    rs_to_scope <- merge(
      bundle$release_sets[, c("release_set_id", "scope_id"), drop = FALSE],
      bundle$scope[, scope_cols, drop = FALSE],
      by = "scope_id", sort = FALSE
    )
    rs_to_scope <- rs_to_scope[!duplicated(rs_to_scope$release_set_id), ,
                               drop = FALSE]
    rs_to_scope <- rs_to_scope[, c("release_set_id", level_cols),
                               drop = FALSE]

    joined <- merge(joined, rs_to_scope, by = "release_set_id",
                    all.x = TRUE, sort = FALSE)
  }

  joined$`_label_freq` <- .label_freq(joined)

  # Sort with explicit decreasing vector on order(..., method="radix"):
  # variable_name ASC, _is_primary DESC, _label_freq DESC, level_i ASC
  if (length(level_cols) > 0L && all(level_cols %in% colnames(joined))) {
    ord <- do.call(order, c(
      list(
        joined$variable_name,
        -joined$`_is_primary`,
        -joined$`_label_freq`
      ),
      lapply(level_cols, function(c) joined[[c]]),
      list(method = "radix")
    ))
  } else {
    ord <- order(
      joined$variable_name,
      -joined$`_is_primary`,
      -joined$`_label_freq`,
      method = "radix"
    )
  }
  joined <- joined[ord, , drop = FALSE]
  joined <- joined[!duplicated(joined$variable_name), , drop = FALSE]
  rownames(joined) <- NULL
  joined
}


# Count rows sharing (variable_name, variable_label). Returns 1 for
# every row if variable_label is absent (core-only variables tables).
.label_freq <- function(df) {
  if (!"variable_label" %in% colnames(df)) {
    return(rep(1L, nrow(df)))
  }
  key <- paste(as.character(df$variable_name), "\001",
               as.character(df$variable_label), sep = "")
  counts <- table(key)
  as.integer(counts[match(key, names(counts))])
}
