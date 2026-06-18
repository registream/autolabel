# Dataset downloader: `rs_update_datasets()`.
#
# Port of `registream-autolabel/src/registream/autolabel/_datasets.py`
# `update_datasets()`. Downloads a single bundled ZIP containing the
# variables, value_labels, and registers CSVs for a `(domain, lang,
# version)` triple, extracts each, applies the same post-import
# processing Stata + Python do, validates the schema, and writes the
# cache files (DTA + CSV) plus a registry entry.
#
# Cross-client invariant: the on-disk cache files and the datasets.csv
# registry use the SAME format as Stata and Python so any client can
# read cache files produced by any other. See the `REGISTRY_COLUMNS`
# constant in registry.R for the registry column-order pin.
#
# CRAN note: this function HITS THE NETWORK. It is user-invoked (not
# called from package load, not from .onAttach), so it complies with
# the CRAN "no network during R CMD check" rule. The call site is
# documented as such. The function also writes to the cache directory,
# which on the CRAN default lives inside `R_user_dir("registream",
# "cache")`, allowed by CRAN as long as the user initiated the action.

DATASET_CHECK_CACHE_HOURS <- 24
DOWNLOAD_TIMEOUT_SECONDS  <- 60


#' @export
rs_update_datasets <- function(domain,
                               lang,
                               version   = "latest",
                               force     = FALSE,
                               directory = NULL) {
  log_and_heartbeat("rs_update_datasets")

  dir_ <- registream::autolabel_cache_dir(directory)
  dir.create(dir_, recursive = TRUE, showWarnings = FALSE)

  result <- new_download_result(domain = domain, lang = lang)

  # Fast path: required v3 cache files already exist and we're not forcing.
  var_dta <- registream::bundle_path(domain, "variables", lang,
                                     ext = "dta",
                                     directory = directory)
  val_dta <- registream::bundle_path(domain, "values", lang,
                                     ext = "dta",
                                     directory = directory)
  if (!isTRUE(force) && file.exists(var_dta) && file.exists(val_dta)) {
    result$skipped <- c(result$skipped,
                        registream::bundle_filename("variables",
                                                    lang, ext = "dta"))
    return(result)
  }

  # ---- States A/B: build from a pre-staged bundle on disk (offline) ----
  # Mirrors Stata `_al_ensure_bundle` (autolabel/stata/src/_al_utils.ado:93):
  # a pre-extracted folder (State A) or a pre-staged ZIP (State B) is used
  # ahead of the internet gate, so air-gapped users (e.g. SCB MONA) can build
  # the cache with no network. `force` skips them to allow a fresh re-pull.
  stage_dir      <- NULL
  actual_version <- NULL
  bundle_schema  <- NULL
  from_api       <- TRUE   # States A/B set this FALSE (see registry + cleanup)
  consume_path   <- NULL   # the staging input to erase after a local build
  if (!isTRUE(force)) {
    local_src <- find_local_bundle(domain, lang, version, dir_)
    if (!is.null(local_src)) {
      from_api     <- FALSE
      consume_path <- local_src$path
      if (identical(local_src$kind, "folder")) {
        stage_dir <- local_src$path            # the extracted folder itself
      } else {
        stage_dir <- tempfile("registream_stage_")
        dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
        on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)
        utils::unzip(local_src$path, exdir = stage_dir)
      }
      actual_version <- local_src$version
      bundle_schema  <- "2.0"
      message(sprintf("Building %s/%s metadata from %s (no download).",
                      domain, lang, local_src$path))
    }
  }

  if (is.null(stage_dir)) {
    # internet_access gate
    cfg <- registream::config_load(directory)
    if (!isTRUE(cfg$internet_access)) {
      if (file.exists(var_dta) && file.exists(val_dta)) {
        result$skipped <- c(result$skipped,
                            registream::bundle_filename("variables",
                                                        lang, ext = "dta"))
        return(result)
      }
      result$failed <- rbind(
        result$failed,
        data.frame(
          file = sprintf("%s_%s", domain, lang),
          error = sprintf(
            paste0("Cannot download: internet_access is disabled. ",
                   "To build offline, pre-stage the bundle ZIP at %s ",
                   "(or its extracted folder at %s/)."),
            file.path(dir_, sprintf("%s_%s_v<version>.zip", domain, lang)),
            file.path(dir_, sprintf("%s_%s", domain, lang))
          ),
          stringsAsFactors = FALSE)
      )
      return(result)
    }

    # Resolve version and schema from the /info endpoint.
    resolved <- tryCatch(
      resolve_bundle_version(domain, lang, version),
      error = function(e) NULL
    )
    if (is.null(resolved)) {
      result$failed <- rbind(
        result$failed,
        data.frame(file = sprintf("%s_%s", domain, lang),
                   error = "Failed to resolve version via /info endpoint.",
                   stringsAsFactors = FALSE)
      )
      return(result)
    }
    actual_version <- resolved$version
    bundle_schema  <- resolved$schema

    # Download the bundle ZIP to tempdir.
    api_url <- sprintf(
      "%s/api/v1/datasets/%s/variables/%s/%s?schema_max=2.0",
      registream::get_api_host(), domain, lang, actual_version
    )
    zip_path <- tempfile(pattern = sprintf("registream_%s_%s_", domain, lang),
                         fileext = ".zip")
    on.exit(unlink(zip_path, force = TRUE), add = TRUE)

    download_err <- tryCatch({
      registream::http_download_file(api_url, zip_path,
                                     timeout_seconds = DOWNLOAD_TIMEOUT_SECONDS)
      NULL
    }, error = function(e) conditionMessage(e))
    if (!is.null(download_err)) {
      result$failed <- rbind(
        result$failed,
        data.frame(file = sprintf("%s_%s", domain, lang),
                   error = download_err, stringsAsFactors = FALSE)
      )
      return(result)
    }

    # Stage: unzip to a temp directory.
    stage_dir <- tempfile("registream_stage_")
    dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)
    utils::unzip(zip_path, exdir = stage_dir)
  }

  # Manifest is a plain CSV (key/value), single chunk, no DTA conversion.
  # Without it on disk, `load_bundle()` falls back to `core_only` mode
  # and scope/release pinning is silently disabled. Stata's
  # `_al_download_bundle` (autolabel/stata/src/_al_utils.ado:280) puts
  # manifest in its file-type loop; we copy the same behavior here.
  manifest_chunks <- list.files(stage_dir, pattern = "\\.csv$",
                                recursive = TRUE, full.names = TRUE)
  manifest_chunks <- sort(manifest_chunks[
    grepl("/manifest/", manifest_chunks, fixed = TRUE)
  ])
  if (length(manifest_chunks) > 0L) {
    manifest_dst <- registream::bundle_path(domain, "manifest", lang,
                                            ext = "csv",
                                            directory = directory)
    dir.create(dirname(manifest_dst), recursive = TRUE, showWarnings = FALSE)
    tryCatch(
      file.copy(manifest_chunks[[1L]], manifest_dst, overwrite = TRUE),
      error = function(e) invisible(NULL)
    )
  }

  # Process each v3 file type. Optional manifest is plain CSV; scope /
  # release_sets are augmentation tables. Variables + value_labels are
  # strictly required.
  folder_map <- list(
    variables    = "variables",
    values       = "value_labels",
    scope        = "scope",
    release_sets = "release_sets"
  )
  for (ft in c("variables", "values", "scope", "release_sets")) {
    filename <- registream::bundle_filename(ft, lang, ext = "dta")
    ft_result <- tryCatch({
      df <- extract_and_concat(stage_dir, folder = folder_map[[ft]])
      if (is.null(df)) {
        # Folder not in ZIP (e.g., core-only bundles without scope/release_sets).
        NULL
      } else {
        df <- process_for_cache(df, ft)
        registream::validate_schema(df, ft)
        # Drop rows with empty variable_name (data quality issue)
        if ("variable_name" %in% colnames(df)) {
          keep <- !is.na(df$variable_name) &
            nzchar(trimws(as.character(df$variable_name)))
          df <- df[keep, , drop = FALSE]
        }
        # Fill NA in character columns (haven::write_dta can't write NA strings)
        for (col in colnames(df)) {
          if (is.character(df[[col]])) {
            df[[col]][is.na(df[[col]])] <- ""
          }
        }
        csv_path <- registream::bundle_path(domain, ft, lang,
                                            ext = "csv",
                                            directory = directory)
        dta_path <- registream::bundle_path(domain, ft, lang,
                                            ext = "dta",
                                            directory = directory)
        dir.create(dirname(csv_path), recursive = TRUE, showWarnings = FALSE)
        # quote = TRUE protects fields containing the `;` delimiter (real
        # value_labels_json / value_labels_stata do). qmethod = "double" is
        # required, not the default "escape": these fields also contain
        # literal `"`, and the readers (utils::read.csv, pandas) honour only
        # CSV-standard doubled quotes (""), not backslash escapes. Without it
        # the column count is right but the JSON value re-reads as garbage.
        # Matches Stata's `export delimited ... quote` and pandas to_csv.
        utils::write.table(
          df, file = csv_path, sep = ";", row.names = FALSE,
          col.names = TRUE, quote = TRUE, qmethod = "double",
          na = "", fileEncoding = "UTF-8"
        )
        haven::write_dta(df, dta_path)

        # Register the cache entry ONLY for fresh API downloads. Pre-staged
        # builds (States A/B) leave the cache index alone, mirroring Stata
        # (_al_utils.ado:396-403): the user told us where the files are, not
        # what release line they track, so registering would invite spurious
        # update prompts against an unknown provenance.
        if (from_api) {
          write_registry_entry(
            directory     = directory,
            domain        = domain,
            file_type     = ft,
            lang          = lang,
            version       = actual_version,
            schema        = bundle_schema,
            file_size_dta = file.info(dta_path)$size,
            file_size_csv = file.info(csv_path)$size
          )
        }
        filename
      }
    }, error = function(e) {
      structure(conditionMessage(e), class = "ft_error")
    })

    if (inherits(ft_result, "ft_error")) {
      result$failed <- rbind(
        result$failed,
        data.frame(file = filename, error = as.character(ft_result),
                   stringsAsFactors = FALSE)
      )
    } else if (!is.null(ft_result)) {
      result$files <- c(result$files, ft_result)
    }
  }

  # Consume the staging input after a successful local build, mirroring Stata
  # (_al_utils.ado:406-410): a State A extracted folder and a State B staged
  # ZIP are erased once the cache is built, leaving only the final cache in
  # `autolabel_dir`. Skipped on any failure so the user can retry. Best-effort.
  if (!from_api && success_of(result) && !is.null(consume_path) &&
      file.exists(consume_path)) {
    tryCatch(unlink(consume_path, recursive = TRUE, force = TRUE),
             error = function(e) invisible(NULL))
  }

  result
}


# Locate a pre-staged bundle on disk for an offline (State A/B) build,
# mirroring Stata `_al_ensure_bundle` (_al_utils.ado:93-147). Returns a source
# descriptor `list(kind, path, version)` or NULL.
#   State A -- a pre-extracted folder `<autolabel_dir>/<domain>_<lang>/` whose
#     `variables/0000.csv` chunk is present (the unzipped bundle layout).
#   State B -- a pre-staged ZIP `<autolabel_dir>/<domain>_<lang>_v*.zip`. When a
#     specific version is requested it is matched exactly; otherwise the
#     lexically last match wins (newest, given YYYYMMDD version stamps).
# `domain`/`lang` are lowercase alphanumeric ecosystem identifiers, so they
# need no regex escaping here.
find_local_bundle <- function(domain, lang, version, autolabel_dir) {
  extract_folder <- file.path(autolabel_dir, sprintf("%s_%s", domain, lang))
  if (file.exists(file.path(extract_folder, "variables", "0000.csv"))) {
    return(list(kind = "folder", path = extract_folder, version = ""))
  }
  pinned  <- !is.null(version) && !version %in% c("", "latest")
  ver_re  <- if (pinned) version else ".*"
  pattern <- sprintf("^%s_%s_v%s\\.zip$", domain, lang, ver_re)
  zips    <- sort(list.files(autolabel_dir, pattern = pattern,
                             full.names = TRUE))
  if (length(zips) > 0L) {
    zip_path <- zips[[length(zips)]]
    parsed   <- sub(sprintf("^%s_%s_v(.*)\\.zip$", domain, lang), "\\1",
                    basename(zip_path))
    return(list(kind = "zip", path = zip_path, version = parsed))
  }
  NULL
}


# Cold-start cascade: when a fresh-install user calls autolabel() and the
# metadata bundle isn't on disk, prompt them to download. Mirrors the
# Stata `_al_ensure_bundle` 3-state cascade in `_al_utils.ado:83`. Lives
# in the autolabel package (not registream core) because
# rs_update_datasets() is here -- registream provides the loader +
# downloader primitives, autolabel glues them into the cold-start UX.
#
# Behavior matrix:
#   cache already present              -> no-op
#   internet_access disabled           -> no-op (load_bundle throws cleanly)
#   non-interactive + no AUTO_APPROVE  -> no-op (CRAN / CI / script-safe)
#   interactive (or AUTO_APPROVE=yes)  -> prompt + download
#
# Returning silently on the no-op branches is intentional: the immediate
# next call (registream::load_bundle) raises `rs_error_missing_bundle`
# which already gives the user the explicit `rs_update_datasets(...)`
# escape hatch. We never want this helper to throw a different error
# than the one users have been documented against.
ensure_bundle <- function(domain, lang, directory = NULL) {
  var_dta <- registream::bundle_path(domain, "variables", lang,
                                     ext = "dta", directory = directory)
  val_dta <- registream::bundle_path(domain, "values", lang,
                                     ext = "dta", directory = directory)
  if (file.exists(var_dta) && file.exists(val_dta)) {
    return(invisible(NULL))
  }

  # Offline (States A/B): a bundle pre-staged on disk is built with no network
  # and no prompt, ahead of the internet gate -- mirrors Stata
  # `_al_ensure_bundle` ordering (_al_utils.ado:93). This is what lets an
  # air-gapped MONA user drop a bundle ZIP (or its extracted folder) next to
  # the cache and have autolabel() pick it up.
  if (!is.null(find_local_bundle(
    domain, lang, "latest", registream::autolabel_cache_dir(directory)
  ))) {
    message(sprintf(
      "Building %s/%s metadata from a local bundle (no download)...",
      domain, lang
    ))
    result <- rs_update_datasets(domain = domain, lang = lang,
                                 directory = directory)
    if (!success_of(result)) {
      err <- if (nrow(result$failed) > 0L) result$failed$error[[1]] else "unknown"
      message(sprintf("  Build failed: %s", err))
    }
    return(invisible(result))
  }

  cfg <- registream::config_load(directory)
  if (!isTRUE(cfg$internet_access)) {
    return(invisible(NULL))
  }

  auto_approve <- identical(
    tolower(Sys.getenv("REGISTREAM_AUTO_APPROVE", "")),
    "yes"
  )
  if (!interactive() && !auto_approve) {
    return(invisible(NULL))
  }

  if (auto_approve) {
    message(sprintf(
      "Metadata not cached for %s/%s. [AUTO-APPROVED]", domain, lang
    ))
  } else {
    response <- prompt_download_bundle(domain, lang)
    if (!identical(response, "yes")) {
      return(invisible(NULL))
    }
  }

  message(sprintf("Downloading metadata for %s/%s...", domain, lang))
  result <- rs_update_datasets(domain = domain, lang = lang,
                               directory = directory)
  if (!success_of(result)) {
    err <- if (nrow(result$failed) > 0L) result$failed$error[[1]] else "unknown"
    message(sprintf("  Download failed: %s", err))
  }
  invisible(result)
}


# Yes/no prompt for the cold-start cascade. Mirrors Stata's
# `_rs_utils prompt` UX: retries on invalid input, treats EOF / empty /
# `q` as a decline. The keystroke here is the CRAN-sanctioned
# "confirmation from the user" that authorises the subsequent network
# call + cache write.
prompt_download_bundle <- function(domain, lang) {
  cat("\n")
  cat(sprintf("Metadata not cached for %s/%s.\n", domain, lang))
  repeat {
    raw <- tryCatch(
      readline("Download from RegiStream? (yes/no): "),
      error = function(e) ""
    )
    ans <- tolower(trimws(as.character(raw)))
    if (ans %in% c("yes", "y")) return("yes")
    if (ans %in% c("no", "n", "")) return("no")
    if (ans %in% c("exit", "quit", "q")) return("no")
    cat(sprintf("Invalid response %s. Please type 'yes' or 'no'.\n",
                shQuote(ans)))
  }
}


#' @export
print.rs_download_result <- function(x, ...) {
  rule <- strrep("-", 60)
  cat(rule, "\n")
  cat(sprintf("rs_update_datasets(%s, %s): %s\n",
              shQuote(x$domain), shQuote(x$lang),
              if (success_of(x)) "success" else "failed"))
  cat(rule, "\n")
  if (length(x$files) > 0L) {
    cat(sprintf("  downloaded (%d): %s\n",
                length(x$files), paste(x$files, collapse = ", ")))
  }
  if (length(x$skipped) > 0L) {
    cat(sprintf("  skipped (%d):    %s\n",
                length(x$skipped), paste(x$skipped, collapse = ", ")))
  }
  if (nrow(x$failed) > 0L) {
    cat(sprintf("  failed (%d):\n", nrow(x$failed)))
    for (i in seq_len(nrow(x$failed))) {
      cat(sprintf("    %s: %s\n", x$failed$file[[i]], x$failed$error[[i]]))
    }
  }
  invisible(x)
}


#' @export
check_for_dataset_updates <- function(domain, lang, directory = NULL) {
  cfg <- registream::config_load(directory)
  if (!isTRUE(cfg$internet_access)) return("")

  registry <- read_registry(directory)
  if (nrow(registry) == 0L) return("")

  sentinel_key <- sprintf("%s_variables_%s", domain, lang)
  rows <- which(registry$dataset_key == sentinel_key)
  if (length(rows) == 0L) return("")
  row <- rows[[1]]

  cached_version <- registry$version[[row]]
  last_checked   <- suppressWarnings(as.numeric(registry$last_checked[[row]]))
  if (is.na(last_checked)) last_checked <- 0

  now_stata <- registream::posix_to_stata_clock(Sys.time())
  ms_per_hour <- 1000 * 60 * 60
  if ((now_stata - last_checked) < (DATASET_CHECK_CACHE_HOURS * ms_per_hour)) {
    return("")
  }

  resolved <- tryCatch(
    resolve_bundle_version(domain, lang, "latest"),
    error = function(e) NULL
  )

  # Update last_checked regardless of the outcome so we don't spam the
  # server on a failing call.
  registry$last_checked[[row]] <- format(now_stata, scientific = FALSE)
  tryCatch(
    utils::write.table(
      registry, file = registry_path(directory),
      sep = ";", row.names = FALSE, col.names = TRUE,
      quote = FALSE, na = "", fileEncoding = "UTF-8"
    ),
    error = function(e) invisible(NULL)
  )

  if (is.null(resolved)) return("")
  latest_version <- resolved$version

  if (nzchar(latest_version) && latest_version != "latest" &&
      latest_version != cached_version) {
    return(sprintf(
      "Newer metadata available for %s/%s (cached: %s, latest: %s). Run: rs_update_datasets(\"%s\", \"%s\", force = TRUE)",
      domain, lang, cached_version, latest_version, domain, lang
    ))
  }

  ""
}


# ── Internal helpers ────────────────────────────────────────────────────────

new_download_result <- function(domain, lang) {
  structure(
    list(
      domain  = domain,
      lang    = lang,
      files   = character(0),
      skipped = character(0),
      failed  = data.frame(file = character(0), error = character(0),
                           stringsAsFactors = FALSE)
    ),
    class = "rs_download_result"
  )
}


success_of <- function(result) {
  nrow(result$failed) == 0L
}


# Port of Python `_resolve_version`. Calls the /info endpoint to turn
# "latest" into a concrete YYYYMMDD version + schema version.
resolve_bundle_version <- function(domain, lang, version) {
  if (version != "latest") {
    return(list(version = version, schema = "2.0"))
  }

  info_url <- sprintf(
    "%s/api/v1/datasets/%s/variables/%s/latest/info?format=stata&schema_max=2.0",
    registream::get_api_host(), domain, lang
  )

  text <- tryCatch(
    registream::http_get_text(info_url,
                              timeout_seconds = DOWNLOAD_TIMEOUT_SECONDS),
    error = function(e) NULL
  )
  if (is.null(text)) {
    # Network error: fall back to "latest" as the URL segment.
    return(list(version = "latest", schema = "2.0"))
  }

  actual_version <- "latest"
  schema_version <- "2.0"
  for (raw in strsplit(text, "\n", fixed = TRUE)[[1]]) {
    line <- trimws(raw)
    if (startsWith(line, "version=")) {
      v <- trimws(substr(line, nchar("version=") + 1L, nchar(line)))
      if (nzchar(v)) actual_version <- v
    } else if (startsWith(line, "schema=")) {
      s <- trimws(substr(line, nchar("schema=") + 1L, nchar(line)))
      if (nzchar(s)) schema_version <- s
    }
  }

  list(version = actual_version, schema = schema_version)
}


# Extract CSVs from a staging directory (the unzipped bundle root) and
# concatenate into one data.frame. The ZIP layout places CSVs under
# `<bundle_root>/<folder>/*.csv`, e.g.
# `scb_eng/variables/0000.csv`, `scb_eng/value_labels/0000.csv`, etc.
# Returns NULL if the folder has no matching CSVs.
#
# Performance: SCB's value_labels folder is ~78 chunks / ~516 MB
# uncompressed (each row carries a JSON blob in `value_labels_json`).
# base R's `read.csv` lexer takes minutes on this and was the dominant
# cost in `rs_update_datasets()`. We use `data.table::fread` when
# available (10-100x faster, single-pass C lexer) and fall back to
# `read.csv` when the user hasn't installed it. data.table is in
# Suggests, not Imports, to keep the dep tree lean.
extract_and_concat <- function(stage_dir, folder) {
  all_csv <- list.files(stage_dir, pattern = "\\.csv$", recursive = TRUE,
                        full.names = TRUE)
  if (length(all_csv) == 0L) {
    stop("Staged bundle contains no .csv files", call. = FALSE)
  }
  match_pattern <- sprintf("/%s/", folder)
  matched <- all_csv[grepl(match_pattern, all_csv, fixed = TRUE)]
  if (length(matched) == 0L) {
    return(NULL)
  }
  matched <- sort(matched)

  dfs <- lapply(matched, read_csv_with_delimiter_fallback)
  if (requireNamespace("data.table", quietly = TRUE)) {
    as.data.frame(data.table::rbindlist(dfs, use.names = TRUE, fill = TRUE),
                  stringsAsFactors = FALSE)
  } else {
    do.call(rbind, dfs)
  }
}


# Try semicolon delimiter first; fall back to comma if only one column
# results. Mirrors Python's `_read_csv_with_delimiter_fallback`. Uses
# `data.table::fread` (Suggests) when available -- SCB's value_labels
# CSV is ~516 MB across 78 chunks and base `read.csv` is impractical
# at that size. Falls back to base R for users without data.table.
#
# fread quirk: as of data.table 1.16.x, fread strips outer quotes but
# does NOT unescape doubled quotes (`""` -> `"`) inside fields. The SCB
# bundle's `value_labels_json` and `value_labels_stata` columns contain
# embedded quotes that are CSV-escaped on disk; without post-processing,
# the Stata-format parser sees `""0""` instead of `"0"` and produces
# garbage labels (which then duplicate and trip `haven::labelled`'s
# uniqueness check). `unescape_doubled_quotes()` undoes the CSV
# double-quote escaping in every character column, which is a no-op
# for fields without embedded quotes (the common case).
read_csv_with_delimiter_fallback <- function(path) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    df <- tryCatch(
      data.table::fread(path, sep = ";", encoding = "UTF-8",
                        colClasses = "character", na.strings = "",
                        data.table = FALSE, showProgress = FALSE),
      error = function(e) NULL
    )
    if (is.null(df) || ncol(df) <= 1L) {
      df <- data.table::fread(path, sep = ",", encoding = "UTF-8",
                              colClasses = "character", na.strings = "",
                              data.table = FALSE, showProgress = FALSE)
    }
    return(unescape_doubled_quotes(df))
  }
  df <- tryCatch(
    utils::read.csv(path, sep = ";", encoding = "UTF-8",
                    stringsAsFactors = FALSE, check.names = FALSE,
                    na.strings = "", colClasses = "character"),
    error = function(e) NULL
  )
  if (!is.null(df) && ncol(df) > 1L) return(df)
  utils::read.csv(path, sep = ",", encoding = "UTF-8",
                  stringsAsFactors = FALSE, check.names = FALSE,
                  na.strings = "", colClasses = "character")
}


# Undo CSV `""` -> `"` escaping on every character column in `df`.
# Cheap (vectorized gsub, fixed-string match) and a no-op for fields
# without embedded quotes. Compensates for the fread quirk noted in
# `read_csv_with_delimiter_fallback`.
unescape_doubled_quotes <- function(df) {
  for (col in colnames(df)) {
    if (is.character(df[[col]])) {
      df[[col]] <- gsub('""', '"', df[[col]], fixed = TRUE)
    }
  }
  df
}


# Post-import processing. Mirrors Python `_process_for_cache` and
# Stata's `_al_download` lines 364-398. Lowercases `variable_name`,
# sorts, deduplicates on v1, and drops the `value_labels_json` column
# and `{}` rows on "values" type.
process_for_cache <- function(df, file_type) {
  if ("variable_name" %in% colnames(df)) {
    df$variable_name <- tolower(as.character(df$variable_name))
    df <- df[order(df$variable_name), , drop = FALSE]
    rownames(df) <- NULL
  }

  # v3 value_labels keep both `value_labels_json` and `value_labels_stata`;
  # only drop rows that are empty placeholders.
  if (identical(file_type, "values") &&
      "value_labels_json" %in% colnames(df)) {
    json_col <- as.character(df$value_labels_json)
    json_col[is.na(json_col)] <- ""
    keep <- json_col != "{}"
    df <- df[keep, , drop = FALSE]
    rownames(df) <- NULL
  }

  df
}
