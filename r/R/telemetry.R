# Telemetry hook: the tiny bridge between autolabel's user-facing
# entry points and the registream usage/heartbeat functions.
#
# Each rs_* / autolabel() call fires this once at the top. All three
# steps are `tryCatch`-wrapped so telemetry can never break a user's
# analysis. If config/usage/heartbeat fails for any reason, we log
# nothing and proceed with the actual work.
#
# The three steps in order:
#
# 1. `rs_first_run()`: resolves a setup mode on first ever use. In
#    non-interactive sessions with no AUTO_APPROVE this silently picks
#    Offline Mode, which is the CRAN-safe default (no network, no
#    telemetry, but local usage logging is still on). Idempotent: no-ops
#    after first run.
# 2. `usage_log(command, module, module_version, core_version)`: appends
#    a row to usage_r.csv. Silently no-ops if usage_logging is FALSE. The
#    salt file and CSV header are auto-created on first call.
# 3. `send_heartbeat(version, command)`: best-effort network call,
#    respects internet_access + the 24-hour last_update_check cache.
#    Fails silently on any network error.
#
# Not exported. Internal to autolabel.

log_and_heartbeat <- function(command) {
  module_version <- tryCatch(
    as.character(utils::packageVersion("autolabel")),
    error = function(e) "unknown"
  )
  core_version <- tryCatch(
    as.character(utils::packageVersion("registream")),
    error = function(e) "unknown"
  )

  tryCatch(
    registream::rs_first_run(),
    error = function(e) invisible(NULL)
  )

  tryCatch(
    registream::usage_log(
      command        = command,
      module         = "autolabel",
      module_version = module_version,
      core_version   = core_version
    ),
    error = function(e) invisible(NULL)
  )

  hb <- tryCatch(
    registream::send_heartbeat(
      version            = core_version,
      command            = command,
      autolabel_version  = module_version
    ),
    error = function(e) NULL
  )

  # Render the scoped banner (core + autolabel only; never datamirror).
  # Users running autolabel care about autolabel + core; surfacing
  # unrelated-module updates here would be noise. `registream update` /
  # `rs_update()` is the explicit channel for a full-ecosystem check.
  if (!is.null(hb)) {
    banner <- tryCatch(
      registream::show_notification(
        current_version = core_version,
        result          = hb,
        modules         = c("registream", "autolabel")
      ),
      error = function(e) ""
    )
    if (nzchar(banner)) message(banner)
  }

  invisible(NULL)
}
