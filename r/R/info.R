# info(): configuration + cache snapshot.
#
# Port of Stata `autolabel info` and Python `registream.autolabel._commands.info`.
# Reads the registream config + resolves cache directories + prints a
# compact summary. Returns the underlying list invisibly so callers can
# inspect programmatically.
#
# Version and citation commands intentionally omitted. Users type
# `utils::packageVersion("autolabel")` for the version (canonical R
# idiom) and `cite()` from citation.R for the citation string.

#' @export
info <- function(directory = NULL) {
  rule <- strrep("-", 60)
  cat(rule, "\n")
  cat("autolabel configuration\n")
  cat(rule, "\n")

  core_v <- tryCatch(
    as.character(utils::packageVersion("registream")),
    error = function(e) "unknown"
  )
  al_v <- tryCatch(
    as.character(utils::packageVersion("autolabel")),
    error = function(e) "unknown"
  )
  cat(sprintf("  autolabel_version:   %s\n", al_v))
  cat(sprintf("  registream_version:  %s\n", core_v))

  dir_ <- tryCatch(
    if (is.null(directory)) registream::cache_dir() else path.expand(directory),
    error = function(e) NA_character_
  )
  bundle_dir_ <- tryCatch(
    registream::autolabel_cache_dir(directory),
    error = function(e) NA_character_
  )
  if (!is.na(dir_))        cat(sprintf("  registream_dir:      %s\n", dir_))
  if (!is.na(bundle_dir_)) cat(sprintf("  autolabel_cache:     %s\n", bundle_dir_))

  cfg <- tryCatch(registream::config_load(directory), error = function(e) NULL)
  if (!is.null(cfg)) {
    cat(sprintf("  internet_access:     %s\n", isTRUE(cfg$internet_access)))
    cat(sprintf("  usage_logging:       %s\n", isTRUE(cfg$usage_logging)))
    cat(sprintf("  telemetry_enabled:   %s\n", isTRUE(cfg$telemetry_enabled)))
    cat(sprintf("  auto_update_check:   %s\n", isTRUE(cfg$auto_update_check)))
  }

  cat(rule, "\n")
  invisible(list(
    autolabel_version  = al_v,
    registream_version = core_v,
    registream_dir     = dir_,
    autolabel_cache    = bundle_dir_,
    config             = cfg
  ))
}
