# suggest(): preview the labeling plan without mutating df.
#
# Port of `registream-autolabel/src/registream/autolabel/_commands.py`
# `suggest()`. Returns an `rs_suggest_result` S3 carrying:
#   coverage   : one row per candidate scope tuple with matches +
#                coverage_pct + is_primary
#   primary    : the rs_scope_inference for the winning tuple or NULL
#   pin_command: copy-pasteable R code that reproduces the pin

#' @export
suggest <- function(x,
                    ...,
                    domain    = "scb",
                    lang      = "eng",
                    release   = NULL,
                    directory = NULL) {
  log_and_heartbeat("suggest")

  tokens <- unlist(list(...), use.names = FALSE)
  tokens <- tokens[!is.na(tokens) & nzchar(tokens)]
  scope_arg <- if (length(tokens) == 0L) NULL else tokens

  bundle <- registream::load_bundle(domain, lang, directory = directory)

  datavars <- if (is.data.frame(x)) colnames(x) else as.character(x)
  datavars <- datavars[!is.na(datavars) & nzchar(datavars)]

  filtered <- filter_bundle(
    bundle,
    scope    = scope_arg,
    release  = release,
    datavars = if (is.null(scope_arg)) datavars else NULL
  )

  coverage <- .coverage_table(bundle, filtered, datavars)
  primary  <- filtered$inferred
  pin_command <- .build_pin_command(domain, lang, primary, scope_arg, release)

  .rs_suggest_result(
    coverage    = coverage,
    primary     = primary,
    pin_command = pin_command
  )
}


#' @export
print.rs_suggest_result <- function(x, ...) {
  rule <- strrep("-", 60)
  cat(rule, "\n")
  if (is.null(x$primary)) {
    cat("No strong primary scope (mixed-panel dataset).\n")
  } else {
    cat(sprintf("Primary scope: %s  (%d%% of dataset variables)\n",
                paste(x$primary$levels, collapse = " / "),
                x$primary$match_pct))
  }
  cat(rule, "\n")
  if (nrow(x$coverage) > 0L) {
    print(utils::head(x$coverage, 10L), row.names = FALSE)
    if (nrow(x$coverage) > 10L) {
      cat(sprintf("\n...(%d more scopes)\n", nrow(x$coverage) - 10L))
    }
  } else {
    cat("(no candidate scopes)\n")
  }
  cat("\n")
  cat(sprintf("Pin command:\n  %s\n", x$pin_command))
  invisible(x)
}


# ── Internal helpers ────────────────────────────────────────────────────────

.rs_suggest_result <- function(coverage, primary, pin_command) {
  structure(
    list(
      coverage    = coverage,
      primary     = primary,
      pin_command = pin_command
    ),
    class = "rs_suggest_result"
  )
}


.coverage_table <- function(bundle, filtered, datavars) {
  if (isTRUE(bundle$core_only) ||
      is.null(bundle$scope) ||
      is.null(bundle$release_sets)) {
    return(data.frame(
      scope_level_1 = character(0),
      matches       = integer(0),
      coverage_pct  = integer(0),
      is_primary    = logical(0),
      stringsAsFactors = FALSE
    ))
  }

  depth <- bundle$manifest$scope_depth
  level_cols <- sprintf("scope_level_%d", seq_len(depth))

  variables <- filtered$variables
  if (nrow(variables) == 0L) {
    empty <- stats::setNames(
      replicate(depth, character(0), simplify = FALSE),
      level_cols
    )
    empty$matches <- integer(0)
    empty$coverage_pct <- integer(0)
    empty$is_primary <- logical(0)
    return(as.data.frame(empty, stringsAsFactors = FALSE))
  }

  datavars_lower <- unique(tolower(as.character(datavars)))
  datavars_lower <- datavars_lower[nzchar(datavars_lower)]

  scope_min <- bundle$scope[, c("scope_id", level_cols), drop = FALSE]
  rs_min <- bundle$release_sets[, c("release_set_id", "scope_id"), drop = FALSE]
  scope_per_rs <- merge(rs_min, scope_min, by = "scope_id", sort = FALSE)
  scope_per_rs <- scope_per_rs[!duplicated(scope_per_rs$release_set_id), ,
                               drop = FALSE]

  joined <- merge(variables, scope_per_rs, by = "release_set_id", sort = FALSE)
  var_lower <- tolower(as.character(joined$variable_name))
  joined$.in_data <- var_lower %in% datavars_lower
  hits <- joined[joined$.in_data, , drop = FALSE]

  if (nrow(hits) == 0L) {
    empty <- stats::setNames(
      replicate(depth, character(0), simplify = FALSE),
      level_cols
    )
    empty$matches <- integer(0)
    empty$coverage_pct <- integer(0)
    empty$is_primary <- logical(0)
    return(as.data.frame(empty, stringsAsFactors = FALSE))
  }

  dedup_key <- do.call(paste,
                       c(lapply(level_cols, function(c) as.character(hits[[c]])),
                         list(as.character(hits$variable_name), sep = "\001")))
  hits_uniq <- hits[!duplicated(dedup_key), , drop = FALSE]
  group_key <- do.call(paste,
                       c(lapply(level_cols,
                                function(c) as.character(hits_uniq[[c]])),
                         list(sep = "\001")))
  counts_tbl <- table(group_key)

  tuples_str <- names(counts_tbl)
  tuples_mat <- do.call(rbind,
                        strsplit(tuples_str, "\001", fixed = TRUE))
  if (ncol(tuples_mat) < depth) {
    pad <- matrix("", nrow = nrow(tuples_mat),
                  ncol = depth - ncol(tuples_mat))
    tuples_mat <- cbind(tuples_mat, pad)
  }
  colnames(tuples_mat) <- level_cols

  coverage <- as.data.frame(tuples_mat, stringsAsFactors = FALSE)
  coverage$matches <- as.integer(unname(counts_tbl))
  n <- max(length(datavars_lower), 1L)
  coverage$coverage_pct <- as.integer(round(coverage$matches / n * 100))

  # Order by matches DESC, then level tuple ASC.
  order_args <- c(
    list(-coverage$matches),
    lapply(level_cols, function(c) coverage[[c]])
  )
  ord <- do.call(order, c(order_args, list(method = "radix")))
  coverage <- coverage[ord, , drop = FALSE]

  coverage$is_primary <- FALSE
  if (!is.null(filtered$inferred) &&
      isTRUE(filtered$inferred$has_strong_primary)) {
    primary <- filtered$inferred$levels
    primary_match <- rep(TRUE, nrow(coverage))
    for (i in seq_along(level_cols)) {
      vals <- as.character(coverage[[level_cols[[i]]]])
      vals[is.na(vals)] <- ""
      primary_match <- primary_match & (vals == primary[[i]])
    }
    coverage$is_primary <- primary_match
  }

  rownames(coverage) <- NULL
  coverage
}


.build_pin_command <- function(domain, lang, primary, scope, release) {
  scope_repr <- NULL
  if (!is.null(scope) && length(scope) > 0L) {
    scope_repr <- as.character(scope)
  } else if (!is.null(primary)) {
    scope_repr <- primary$levels
  }

  parts <- c(sprintf("domain = %s", shQuote(domain)),
             sprintf("lang = %s",   shQuote(lang)))
  if (!is.null(scope_repr)) {
    inner <- paste(shQuote(scope_repr), collapse = ", ")
    parts <- c(parts, sprintf("scope = c(%s)", inner))
  }
  if (!is.null(release)) {
    parts <- c(parts, sprintf("release = %s", shQuote(release)))
  }
  sprintf("autolabel(df, %s)", paste(parts, collapse = ", "))
}
