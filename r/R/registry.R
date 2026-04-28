# datasets.csv registry read/write.
#
# Port of `read_registry` and `write_registry_entry` from
# registream-autolabel/src/registream/autolabel/_datasets.py. The
# registry lives inside the autolabel subdirectory of the registream
# cache (`<cache_dir>/autolabel/datasets.csv`). Column order is pinned
# to match Python + Stata exactly; both clients must be able to read
# each other's registry files.
#
# Timestamps are stored as Stata clock values (milliseconds since
# 1960-01-01 UTC), matching Stata's `clock("DMY hms")` format. Used by
# `check_for_dataset_updates()` for the 24-hour freshness cache.

DATASETS_REGISTRY_FILENAME <- "datasets.csv"

# Column order: must match Stata's _al_store_meta line 154 and Python's
# REGISTRY_COLUMNS tuple exactly. Cross-client cache compatibility
# depends on this.
REGISTRY_COLUMNS <- c(
  "dataset_key",
  "domain",
  "type",
  "lang",
  "version",
  "schema",
  "downloaded",
  "source",
  "file_size_dta",
  "file_size_csv",
  "last_checked"
)


# Map R's file_type ("values") to the on-disk filename infix
# ("value_labels"); matches Python's file_type_label branching.
.registry_file_type_label <- function(file_type) {
  if (identical(file_type, "values")) "value_labels" else file_type
}


registry_path <- function(directory = NULL) {
  file.path(registream::autolabel_cache_dir(directory),
            DATASETS_REGISTRY_FILENAME)
}


#' @export
read_registry <- function(directory = NULL) {
  path <- registry_path(directory)
  if (!file.exists(path)) {
    return(empty_registry())
  }
  df <- tryCatch(
    utils::read.csv(
      path, sep = ";", encoding = "UTF-8",
      stringsAsFactors = FALSE, check.names = FALSE,
      colClasses = "character"
    ),
    error = function(e) empty_registry()
  )
  # Ensure all canonical columns are present; missing ones get empty strings.
  for (col in REGISTRY_COLUMNS) {
    if (!col %in% colnames(df)) df[[col]] <- character(nrow(df))
  }
  df[, REGISTRY_COLUMNS, drop = FALSE]
}


#' @export
write_registry_entry <- function(directory,
                                 domain,
                                 file_type,
                                 lang,
                                 version,
                                 schema,
                                 file_size_dta,
                                 file_size_csv) {
  ft_label <- .registry_file_type_label(file_type)
  dataset_key <- sprintf("%s_%s_%s", domain, ft_label, lang)

  timestamp <- stata_clock_now()
  timestamp_str <- format(timestamp, scientific = FALSE)

  dir.create(dirname(registry_path(directory)), recursive = TRUE,
             showWarnings = FALSE)

  df <- read_registry(directory)

  new_row <- list(
    dataset_key   = dataset_key,
    domain        = domain,
    type          = ft_label,
    lang          = lang,
    version       = as.character(version),
    schema        = as.character(schema),
    downloaded    = timestamp_str,
    source        = "api",
    file_size_dta = as.character(file_size_dta),
    file_size_csv = as.character(file_size_csv),
    last_checked  = timestamp_str
  )

  idx <- which(df$dataset_key == dataset_key)
  if (length(idx) > 0L) {
    # Update existing: preserve last_checked from the previous entry.
    # Matches Stata's _al_store_meta behaviour line 708: "Don't reset
    # last_checked when re-downloading."
    new_row$last_checked <- df$last_checked[[idx[[1]]]]
    for (col in names(new_row)) {
      df[[col]][[idx[[1]]]] <- new_row[[col]]
    }
  } else {
    new_df <- as.data.frame(new_row, stringsAsFactors = FALSE)
    df <- rbind(df, new_df[, REGISTRY_COLUMNS, drop = FALSE])
  }

  df <- df[, REGISTRY_COLUMNS, drop = FALSE]
  utils::write.table(
    df, file = registry_path(directory),
    sep = ";", row.names = FALSE, col.names = TRUE,
    quote = FALSE, na = "", fileEncoding = "UTF-8"
  )
  invisible(df)
}


# ── Internal helpers ────────────────────────────────────────────────────────

empty_registry <- function() {
  df <- as.data.frame(
    lapply(REGISTRY_COLUMNS, function(.) character(0)),
    stringsAsFactors = FALSE
  )
  names(df) <- REGISTRY_COLUMNS
  df
}


# Stata clock value for "now". Cross-client timestamp format:
# milliseconds since 1960-01-01 UTC. Integer-like but stored as
# numeric to avoid 32-bit overflow on the ~2 trillion ms range.
stata_clock_now <- function() {
  registream::posix_to_stata_clock(Sys.time())
}
