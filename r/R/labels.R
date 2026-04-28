# Variable and value label application.
#
# Port of `registream-autolabel/src/registream/autolabel/_labels.py`'s
# `apply_variable_labels`, `apply_value_labels`, and `apply_labels`. The
# Python version writes into `df.attrs['registream']` because pandas
# lacks column-level metadata. R has column attributes natively, so we
# write directly to `attr(df[[col]], 'label')` and use
# `haven::labelled()` for value labels; no df-level blob, no
# vctrs/labelled package dependency. See `design/citation.md` and the
# r_runbook for the design rationale.
#
# Each apply_* function returns a list(df = <modified df>, n = <count>)
# so the caller can both pipe the labelled df forward and report how
# many labels were applied.

VARIABLE_NAME_COLUMN  <- "variable_name"
VARIABLE_LABEL_COLUMN <- "variable_label"
VARIABLE_UNIT_COLUMN  <- "variable_unit"
VALUE_LABEL_ID_COLUMN <- "value_label_id"
VALUE_LABELS_COLUMN   <- "value_labels_stata"

# df-level attr blob: holds bundle provenance so autolabel_suggest() /
# autolabel_info() can surface domain / scope / release after labelling.
# The column-level haven attrs remain the source of truth for labels;
# this blob is metadata *about* the label application itself.
ATTRS_KEY              <- "registream"
SCHEMA_VERSION_KEY     <- "registream_schema_version"


stamp_registream_attrs <- function(df,
                                   domain,
                                   lang,
                                   scope          = NULL,
                                   release        = NULL,
                                   scope_depth    = 0L,
                                   schema_version = "2.0") {
  attr(df, ATTRS_KEY) <- list(
    domain         = domain,
    lang           = lang,
    scope          = if (is.null(scope)) character(0) else as.character(scope),
    release        = release,
    scope_depth    = as.integer(scope_depth),
    schema_version = schema_version
  )
  attr(df, SCHEMA_VERSION_KEY) <- schema_version
  df
}


apply_variable_labels <- function(df,
                                  metadata,
                                  variables    = NULL,
                                  include_unit = TRUE) {
  if (!VARIABLE_NAME_COLUMN  %in% colnames(metadata)) return(list(df = df, n = 0L))
  if (!VARIABLE_LABEL_COLUMN %in% colnames(metadata)) return(list(df = df, n = 0L))

  df_vars <- .build_df_var_lookup(df, variables)
  if (length(df_vars) == 0L) return(list(df = df, n = 0L))

  has_unit_col <- include_unit && VARIABLE_UNIT_COLUMN %in% colnames(metadata)
  n <- 0L

  for (i in seq_len(nrow(metadata))) {
    var_name <- metadata[[VARIABLE_NAME_COLUMN]][[i]]
    if (is.na(var_name)) next
    var_lower <- tolower(as.character(var_name))
    if (!var_lower %in% names(df_vars)) next

    label <- metadata[[VARIABLE_LABEL_COLUMN]][[i]]
    if (is.na(label)) next
    label_str <- trimws(as.character(label))
    if (!nzchar(label_str)) next

    if (has_unit_col) {
      unit <- metadata[[VARIABLE_UNIT_COLUMN]][[i]]
      if (!is.na(unit)) {
        unit_str <- trimws(as.character(unit))
        if (nzchar(unit_str)) {
          label_str <- sprintf("%s (%s)", label_str, unit_str)
        }
      }
    }

    original_col <- df_vars[[var_lower]]
    attr(df[[original_col]], "label") <- label_str
    n <- n + 1L
  }

  list(df = df, n = n)
}


apply_value_labels <- function(df,
                               var_metadata,
                               val_metadata,
                               variables = NULL) {
  if (!VARIABLE_NAME_COLUMN  %in% colnames(var_metadata)) return(list(df = df, n = 0L))
  if (!VALUE_LABEL_ID_COLUMN %in% colnames(var_metadata)) return(list(df = df, n = 0L))
  if (!VALUE_LABEL_ID_COLUMN %in% colnames(val_metadata)) return(list(df = df, n = 0L))
  if (!VALUE_LABELS_COLUMN   %in% colnames(val_metadata)) return(list(df = df, n = 0L))

  raw_lookup <- .build_value_label_lookup(val_metadata)
  if (length(raw_lookup) == 0L) return(list(df = df, n = 0L))

  df_vars <- .build_df_var_lookup(df, variables)
  if (length(df_vars) == 0L) return(list(df = df, n = 0L))

  n <- 0L

  for (i in seq_len(nrow(var_metadata))) {
    var_name <- var_metadata[[VARIABLE_NAME_COLUMN]][[i]]
    if (is.na(var_name)) next
    var_lower <- tolower(as.character(var_name))
    if (!var_lower %in% names(df_vars)) next

    lid <- var_metadata[[VALUE_LABEL_ID_COLUMN]][[i]]
    if (is.na(lid)) next
    lid_str <- trimws(as.character(lid))
    if (!nzchar(lid_str)) next

    raw <- raw_lookup[[lid_str]]
    if (is.null(raw)) next

    original_col <- df_vars[[var_lower]]
    col <- df[[original_col]]
    col_type <- typeof(col)

    parser_type <- if (col_type %in% c("integer", "double")) "integer" else "character"
    parsed <- registream::parse_value_labels_stata(raw, type = parser_type)
    if (length(parsed) == 0L) next

    # Coerce labels to match column type (haven::labelled is strict).
    if (col_type == "double" && typeof(parsed) == "integer") {
      parsed <- stats::setNames(as.numeric(parsed), names(parsed))
    }

    existing_label <- attr(col, "label")
    df[[original_col]] <- haven::labelled(col, labels = parsed, label = existing_label)
    n <- n + 1L
  }

  list(df = df, n = n)
}


apply_labels <- function(df,
                         var_metadata,
                         val_metadata = NULL,
                         label_type   = c("both", "variables", "values"),
                         variables    = NULL,
                         include_unit = TRUE) {
  label_type <- match.arg(label_type)
  n_var <- 0L
  n_val <- 0L

  if (label_type %in% c("variables", "both")) {
    res <- apply_variable_labels(df, var_metadata,
                                 variables    = variables,
                                 include_unit = include_unit)
    df    <- res$df
    n_var <- res$n
  }

  if (label_type %in% c("values", "both") && !is.null(val_metadata)) {
    res <- apply_value_labels(df, var_metadata, val_metadata,
                              variables = variables)
    df    <- res$df
    n_val <- res$n
  }

  list(df = df, n_variables = n_var, n_values = n_val)
}


# ── Internal helpers ─────────────────────────────────────────────────────────

# Build a `lowercase -> original` lookup of df column names. If `variables`
# is given, restrict to that subset (silently drop names not in df). The
# Python equivalent is the `df_vars = {col.lower(): col for col in ...}`
# pattern in `_labels.py:212-216, 313-316`.
.build_df_var_lookup <- function(df, variables = NULL) {
  cols <- if (is.null(variables)) {
    colnames(df)
  } else {
    intersect(variables, colnames(df))
  }
  stats::setNames(cols, tolower(cols))
}

# Build a value_label_id -> raw_string lookup. First-wins on duplicates,
# matching Python's `if label_id_str in label_lookup: continue` skip.
.build_value_label_lookup <- function(val_metadata) {
  out <- list()
  for (i in seq_len(nrow(val_metadata))) {
    lid <- val_metadata[[VALUE_LABEL_ID_COLUMN]][[i]]
    if (is.na(lid)) next
    lid_str <- trimws(as.character(lid))
    if (!nzchar(lid_str)) next
    if (!is.null(out[[lid_str]])) next
    raw <- val_metadata[[VALUE_LABELS_COLUMN]][[i]]
    if (is.na(raw)) next
    raw_str <- as.character(raw)
    if (!nzchar(trimws(raw_str))) next
    out[[lid_str]] <- raw_str
  }
  out
}
