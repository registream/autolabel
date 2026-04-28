# Variable lookup over a v3 bundle.
#
# Port of `registream-autolabel/src/registream/autolabel/_lookup.py`
# `lookup()`. Takes a character vector of variable names + optional
# scope/release, returns an `rs_lookup_result` S3 object with:
#   df            : matched metadata rows (one per variable default,
#                   all matching rows when detail = TRUE)
#   missing       : requested names that matched nothing
#   scope_counts  : map of variable_name (lowercase) to distinct scope
#                   tuples the variable appears in

#' @export
rs_lookup <- function(variables,
                      domain    = "scb",
                      lang      = "eng",
                      scope     = NULL,
                      release   = NULL,
                      detail    = FALSE,
                      directory = NULL) {
  if (missing(variables) || is.null(variables) || length(variables) == 0L) {
    stop("rs_lookup() requires a non-empty character vector in `variables`.",
         call. = FALSE)
  }
  variables <- as.character(variables)
  log_and_heartbeat("rs_lookup")

  bundle <- registream::load_bundle(domain, lang, directory = directory)
  filtered <- filter_bundle(bundle, scope = scope, release = release)

  metadata <- filtered$variables
  if (!"variable_name" %in% colnames(metadata) || nrow(metadata) == 0L) {
    return(.rs_lookup_result(
      df              = data.frame(),
      missing         = variables,
      scope_counts    = list()
    ))
  }

  requested_lower <- tolower(variables)
  var_lower <- tolower(as.character(metadata$variable_name))
  matched_mask <- var_lower %in% requested_lower
  matched <- metadata[matched_mask, , drop = FALSE]
  matched_var_lower <- var_lower[matched_mask]

  missing <- variables[!(requested_lower %in% unique(matched_var_lower))]

  scope_counts <- .v3_scope_counts(matched, matched_var_lower, bundle)

  result_df <- if (nrow(matched) == 0L) {
    matched
  } else if (isTRUE(detail)) {
    .v3_attach_scope_tuple(matched, bundle)
  } else {
    .v3_aggregate_default(matched)
  }

  result_df <- .enrich_with_value_labels(result_df, filtered$value_labels)
  rownames(result_df) <- NULL

  .rs_lookup_result(
    df           = result_df,
    missing      = missing,
    scope_counts = scope_counts
  )
}


#' @export
print.rs_lookup_result <- function(x, ...) {
  n <- nrow(x$df)

  if (n == 0L && length(x$missing) == 0L) {
    cat("<rs_lookup_result: empty>\n")
    return(invisible(x))
  }

  if (n > 0L) {
    cat(sprintf("<rs_lookup_result: %d variable%s>\n",
                n, if (n == 1L) "" else "s"))
    display_cols <- intersect(
      c("variable_name", "variable_label", "variable_unit", "variable_type",
        "scope_level_1", "scope_level_2", "release"),
      colnames(x$df)
    )
    if (length(display_cols) > 0L) {
      print(x$df[, display_cols, drop = FALSE], row.names = FALSE)
    }
  } else {
    cat("<rs_lookup_result: 0 variables matched>\n")
  }

  if (length(x$missing) > 0L) {
    cat(sprintf("\nNot found (%d): %s\n",
                length(x$missing),
                paste(x$missing, collapse = ", ")))
  }

  if (length(x$scope_counts) > 0L) {
    counts_vec <- unlist(x$scope_counts, use.names = TRUE)
    multi <- counts_vec[counts_vec > 1L]
    if (length(multi) > 0L) {
      cat(sprintf("\n%d variable%s appear%s in multiple scopes. ",
                  length(multi),
                  if (length(multi) == 1L) "" else "s",
                  if (length(multi) == 1L) "s" else ""))
      cat("Use `detail = TRUE` to see all scope rows.\n")
    }
  }

  invisible(x)
}


# ── Internal helpers ─────────────────────────────────────────────────────────

.rs_lookup_result <- function(df, missing, scope_counts) {
  structure(
    list(
      df           = df,
      missing      = missing,
      scope_counts = scope_counts
    ),
    class = "rs_lookup_result"
  )
}


.v3_aggregate_default <- function(matched) {
  if (nrow(matched) == 0L) return(matched)

  var_name  <- as.character(matched$variable_name)
  var_label <- as.character(matched$variable_label)
  label_key <- paste0(var_name, "\001", var_label)
  label_freq <- stats::ave(seq_len(nrow(matched)), label_key, FUN = length)

  if ("_is_primary" %in% colnames(matched)) {
    ord <- order(var_name,
                 -as.integer(matched$`_is_primary`),
                 -label_freq,
                 method = "radix")
  } else {
    ord <- order(var_name, -label_freq,
                 method = "radix")
  }
  sorted <- matched[ord, , drop = FALSE]
  sorted[!duplicated(sorted$variable_name), , drop = FALSE]
}


.v3_attach_scope_tuple <- function(matched, bundle) {
  depth <- bundle$manifest$scope_depth
  if (depth == 0L ||
      is.null(bundle$scope) ||
      is.null(bundle$release_sets)) {
    return(matched)
  }
  level_cols <- sprintf("scope_level_%d", seq_len(depth))
  scope_cols <- c("scope_id", level_cols,
                  if ("release" %in% colnames(bundle$scope)) "release"
                  else character(0))
  rs <- bundle$release_sets[, c("release_set_id", "scope_id"), drop = FALSE]
  sc <- bundle$scope[, scope_cols, drop = FALSE]
  joined <- merge(matched, rs, by = "release_set_id",
                  all.x = TRUE, sort = FALSE)
  joined <- merge(joined, sc, by = "scope_id",
                  all.x = TRUE, sort = FALSE)
  joined
}


.v3_scope_counts <- function(matched, matched_var_lower, bundle) {
  if (nrow(matched) == 0L ||
      is.null(bundle$scope) ||
      is.null(bundle$release_sets)) {
    return(list())
  }
  depth <- bundle$manifest$scope_depth
  if (depth == 0L) return(list())
  level_cols <- sprintf("scope_level_%d", seq_len(depth))
  rs <- bundle$release_sets[, c("release_set_id", "scope_id"), drop = FALSE]
  sc <- bundle$scope[, c("scope_id", level_cols), drop = FALSE]
  joined <- merge(matched, rs, by = "release_set_id",
                  all.x = TRUE, sort = FALSE)
  joined <- merge(joined, sc, by = "scope_id",
                  all.x = TRUE, sort = FALSE)
  joined$.var_lower <- tolower(as.character(joined$variable_name))

  dedup_key <- do.call(paste,
                       c(list(joined$.var_lower),
                         lapply(level_cols, function(c) as.character(joined[[c]])),
                         list(sep = "\001")))
  uniq <- joined[!duplicated(dedup_key), , drop = FALSE]
  counts <- table(uniq$.var_lower)
  as.list(stats::setNames(as.integer(unname(counts)), names(counts)))
}


.enrich_with_value_labels <- function(df, val_meta) {
  empty <- stats::setNames(integer(0), character(0))

  if (nrow(df) == 0L) {
    df[["value_labels"]] <- list()
    return(df)
  }

  # Parse only the value-label rows actually referenced by `df`. The full
  # SCB-English `value_labels` table is ~12k rows and parsing every row
  # takes ~60s; a single-variable lookup typically references one lid.
  cache <- new.env(parent = emptyenv())
  needed_lids <- if ("value_label_id" %in% colnames(df)) {
    raw_lids <- df[["value_label_id"]]
    raw_lids <- raw_lids[!is.na(raw_lids)]
    unique(trimws(as.character(raw_lids)))
  } else character(0)
  needed_lids <- needed_lids[nzchar(needed_lids)]

  if (length(needed_lids) > 0L &&
      !is.null(val_meta) &&
      "value_label_id" %in% colnames(val_meta) &&
      "value_labels_stata" %in% colnames(val_meta)) {
    val_lid <- trimws(as.character(val_meta[["value_label_id"]]))
    keep <- val_lid %in% needed_lids
    val_meta_sub <- val_meta[keep, , drop = FALSE]
    for (i in seq_len(nrow(val_meta_sub))) {
      lid <- val_meta_sub[["value_label_id"]][[i]]
      if (is.na(lid)) next
      lid_str <- trimws(as.character(lid))
      if (!nzchar(lid_str)) next
      if (exists(lid_str, envir = cache, inherits = FALSE)) next
      raw <- val_meta_sub[["value_labels_stata"]][[i]]
      parsed <- registream::parse_value_labels_stata(raw)
      if (length(parsed) > 0L) {
        assign(lid_str, parsed, envir = cache)
      }
    }
  }

  lookup_one <- function(lid) {
    if (is.na(lid)) return(empty)
    lid_str <- trimws(as.character(lid))
    if (!nzchar(lid_str)) return(empty)
    if (!exists(lid_str, envir = cache, inherits = FALSE)) return(empty)
    get(lid_str, envir = cache, inherits = FALSE)
  }

  if ("value_label_id" %in% colnames(df)) {
    df[["value_labels"]] <- lapply(df[["value_label_id"]], lookup_one)
  } else {
    df[["value_labels"]] <- replicate(nrow(df), empty, simplify = FALSE)
  }

  df
}
