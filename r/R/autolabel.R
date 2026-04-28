# The autolabel S3 generic and data.frame method.
#
# v3-only. Pipeline: load_bundle -> filter_bundle -> collapse -> apply_labels
# -> stamp_registream_attrs. There is no v1/v2 fallback path; the `register`
# / `variant` / `version` arguments from earlier iterations are gone; use
# `scope` and `release` against the v3 bundle's manifest + scope tables.

#' @export
autolabel <- function(x, ...) {
  UseMethod("autolabel")
}

#' @export
autolabel.data.frame <- function(x,
                                 domain       = "scb",
                                 lang         = "eng",
                                 scope        = NULL,
                                 release      = NULL,
                                 label_type   = c("both", "variables", "values"),
                                 variables    = NULL,
                                 exclude      = NULL,
                                 include_unit = TRUE,
                                 dryrun       = FALSE,
                                 directory    = NULL,
                                 ...) {
  label_type <- match.arg(label_type)
  if (!isTRUE(dryrun)) log_and_heartbeat("autolabel")

  bundle <- registream::load_bundle(domain, lang, directory = directory)

  datavars <- if (is.null(scope)) colnames(x) else NULL
  filtered <- filter_bundle(
    bundle,
    scope    = scope,
    release  = release,
    datavars = datavars
  )

  if (!isTRUE(dryrun) &&
      !is.null(filtered$inferred) &&
      isTRUE(filtered$inferred$has_strong_primary)) {
    message(sprintf(
      "Auto-detected scope: %s (%d%% variable match)",
      paste(filtered$inferred$levels, collapse = " / "),
      filtered$inferred$match_pct
    ))
  }

  collapsed <- collapse_to_one_per_variable(filtered, bundle)

  effective_vars <- .resolve_target_columns(x, variables, exclude)

  val_metadata_df <- if (label_type %in% c("values", "both")) {
    bundle$value_labels
  } else {
    NULL
  }

  resolved_scope_for_dryrun <- filtered$resolved_scope
  if (is.null(resolved_scope_for_dryrun) && !is.null(filtered$inferred)) {
    resolved_scope_for_dryrun <- filtered$inferred$levels
  }

  if (isTRUE(dryrun)) {
    return(.plan_label_stamps(
      x,
      var_metadata     = collapsed,
      val_metadata     = val_metadata_df,
      label_type       = label_type,
      variables        = effective_vars,
      include_unit     = include_unit,
      resolved_scope   = resolved_scope_for_dryrun,
      resolved_release = filtered$resolved_release %||%
                         filtered$auto_drilled_release
    ))
  }

  result <- apply_labels(
    x,
    var_metadata = collapsed,
    val_metadata = val_metadata_df,
    label_type   = label_type,
    variables    = effective_vars,
    include_unit = include_unit
  )

  stamp_registream_attrs(
    result$df,
    domain         = domain,
    lang           = lang,
    scope          = filtered$resolved_scope,
    release        = filtered$resolved_release %||%
                     filtered$auto_drilled_release,
    scope_depth    = bundle$manifest$scope_depth,
    schema_version = bundle$manifest$schema_version
  )
}


# Combine `variables` + `exclude` into a final column list. Returns NULL
# when no restriction is needed (caller labels every matching column).
# Unknown names are silently dropped (mirrors Stata dispatcher behavior).
.resolve_target_columns <- function(df, variables, exclude) {
  if (is.null(variables) && (is.null(exclude) || length(exclude) == 0L)) {
    return(NULL)
  }
  base <- if (is.null(variables)) {
    colnames(df)
  } else {
    intersect(variables, colnames(df))
  }
  if (!is.null(exclude) && length(exclude) > 0L) {
    base <- setdiff(base, exclude)
  }
  base
}


# Dryrun planner. Mirrors Python `_plan_label_stamps` in _accessor.py.
# Builds an `autolabel_dryrun` S3 object describing what apply_labels
# *would* stamp, without mutating df. Parity contract with the Python
# `DryRunResult`: same field names, same semantics.
.plan_label_stamps <- function(df,
                               var_metadata,
                               val_metadata,
                               label_type,
                               variables,
                               include_unit,
                               resolved_scope,
                               resolved_release) {
  target <- .build_df_var_lookup(df, variables)

  planned_var <- list()
  skipped <- character()

  if (label_type %in% c("variables", "both") &&
      VARIABLE_NAME_COLUMN %in% colnames(var_metadata) &&
      VARIABLE_LABEL_COLUMN %in% colnames(var_metadata)) {
    has_unit <- include_unit && VARIABLE_UNIT_COLUMN %in% colnames(var_metadata)
    for (i in seq_len(nrow(var_metadata))) {
      raw_name <- var_metadata[[VARIABLE_NAME_COLUMN]][[i]]
      if (is.na(raw_name)) next
      key <- tolower(as.character(raw_name))
      if (!key %in% names(target)) next

      label <- var_metadata[[VARIABLE_LABEL_COLUMN]][[i]]
      if (is.na(label)) {
        skipped <- c(skipped, target[[key]])
        next
      }
      label_str <- trimws(as.character(label))
      if (!nzchar(label_str)) {
        skipped <- c(skipped, target[[key]])
        next
      }
      if (has_unit) {
        unit <- var_metadata[[VARIABLE_UNIT_COLUMN]][[i]]
        if (!is.na(unit)) {
          unit_str <- trimws(as.character(unit))
          if (nzchar(unit_str)) {
            label_str <- sprintf("%s (%s)", label_str, unit_str)
          }
        }
      }
      planned_var[[target[[key]]]] <- label_str
    }
  }

  planned_val <- list()
  if (label_type %in% c("values", "both") &&
      !is.null(val_metadata) &&
      VALUE_LABEL_ID_COLUMN %in% colnames(var_metadata) &&
      VALUE_LABEL_ID_COLUMN %in% colnames(val_metadata) &&
      VALUE_LABELS_COLUMN %in% colnames(val_metadata)) {
    raw_lookup <- .build_value_label_lookup(val_metadata)
    for (i in seq_len(nrow(var_metadata))) {
      raw_name <- var_metadata[[VARIABLE_NAME_COLUMN]][[i]]
      if (is.na(raw_name)) next
      key <- tolower(as.character(raw_name))
      if (!key %in% names(target)) next
      lid <- var_metadata[[VALUE_LABEL_ID_COLUMN]][[i]]
      if (is.na(lid)) next
      lid_str <- trimws(as.character(lid))
      if (!nzchar(lid_str)) next
      raw <- raw_lookup[[lid_str]]
      if (is.null(raw)) next
      col_name <- target[[key]]
      col_type <- typeof(df[[col_name]])
      parser_type <- if (col_type %in% c("integer", "double")) "integer" else "character"
      parsed <- registream::parse_value_labels_stata(raw, type = parser_type)
      if (length(parsed) == 0L) next
      planned_val[[col_name]] <- parsed
    }
  }

  structure(
    list(
      variable_labels  = planned_var,
      value_labels     = planned_val,
      skipped_vars     = sort(unique(skipped)),
      resolved_scope   = resolved_scope,
      resolved_release = resolved_release
    ),
    class = "autolabel_dryrun"
  )
}


#' @export
print.autolabel_dryrun <- function(x, ...) {
  cat("autolabel dryrun preview\n")
  cat(sprintf("  variable_labels: %d\n", length(x$variable_labels)))
  cat(sprintf("  value_labels:    %d\n", length(x$value_labels)))
  cat(sprintf("  skipped_vars:    %d\n", length(x$skipped_vars)))
  if (!is.null(x$resolved_scope) && length(x$resolved_scope) > 0L) {
    cat(sprintf("  resolved_scope:  %s\n",
                paste(x$resolved_scope, collapse = " / ")))
  }
  if (!is.null(x$resolved_release) && nzchar(as.character(x$resolved_release))) {
    cat(sprintf("  resolved_release: %s\n", x$resolved_release))
  }
  invisible(x)
}


# Local %||%: null-coalesce for legacy R (no rlang dep).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
