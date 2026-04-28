# dev/exercise-real.R: end-to-end proof that the R client works
# against the REAL `~/.registream/` cache, writes its own config +
# usage log + hits the heartbeat, and co-locates cleanly with the
# existing Python/Stata files.
#
# Not shipped in the package (`^dev$` is in `.Rbuildignore`). Run
# manually during development:
#
#   Rscript dev/exercise-real.R
#
# The script is NOT read-only; it writes `config_r.toml`, may append
# to `.salt` if missing, and appends rows to `usage_r.csv`. These are
# the exact files the R client is supposed to write on a user's
# machine; running the script produces a proof-of-life for the full
# telemetry + usage + heartbeat pipeline against a populated cache.
#
# Heartbeat: the call will currently return `reason = "network_error"`
# because commit `79500fe` on registream.org ("Fixed heartbeat
# endpoint") is committed locally but not deployed to the live server.
# Probe: `curl https://registream.org/api/v1/heartbeat` returns 404,
# while the legacy `/api/v1/stata/heartbeat` alias returns 200. Deploy
# the server fix to flip heartbeat from network_error to success.

suppressPackageStartupMessages({
  library(autolabel)
  library(haven)
})

real_cache <- path.expand("~/.registream")
if (!dir.exists(file.path(real_cache, "autolabel"))) {
  stop(sprintf(
    "Real cache not found at %s/autolabel/. Populate via the Stata or Python client first.",
    real_cache
  ))
}

Sys.setenv(REGISTREAM_DIR = real_cache)
# Auto-approve picks Full Mode; enables telemetry + update-check.
Sys.setenv(REGISTREAM_AUTO_APPROVE = "yes")

cat("== BEFORE ============================================================\n")
cat(sprintf("Cache dir: %s\n\n", real_cache))
cat("Files in REGISTREAM_DIR:\n")
before_files <- list.files(real_cache, all.files = TRUE, no.. = TRUE)
for (f in before_files) {
  info <- file.info(file.path(real_cache, f))
  kind <- if (info$isdir) "DIR " else "FILE"
  cat(sprintf("  %s  %s\n", kind, f))
}


# ── Step 1: first-run wizard (auto-approve → Full Mode) ────────────────────
cat("\n== STEP 1: rs_first_run() ============================================\n")
cfg_before <- registream::config_load()
cat(sprintf("config_r.toml exists before: %s\n",
            file.exists(registream::config_path())))
cfg <- registream::rs_first_run()
cat(sprintf("config_r.toml exists after:  %s\n",
            file.exists(registream::config_path())))
cat(sprintf("first_run_completed: %s\n", cfg$first_run_completed))
cat(sprintf("usage_logging:       %s\n", cfg$usage_logging))
cat(sprintf("telemetry_enabled:   %s\n", cfg$telemetry_enabled))
cat(sprintf("internet_access:     %s\n", cfg$internet_access))


# ── Step 2: autolabel() on lisa.dta against the real cache ────────────────
cat("\n== STEP 2: autolabel() ==============================================\n")
fixture <- system.file("extdata", "lisa.dta", package = "autolabel")
if (!nzchar(fixture)) fixture <- "r/inst/extdata/lisa.dta"
lisa <- as.data.frame(haven::read_dta(fixture))
cat(sprintf("Read lisa.dta: %d rows x %d cols\n", nrow(lisa), ncol(lisa)))

t_label <- system.time({
  labelled <- autolabel(lisa, domain = "scb", lang = "eng")
})
has_var <- vapply(labelled, function(c) !is.null(attr(c, "label", exact = TRUE)),
                  logical(1))
cat(sprintf("autolabel done: %d/%d columns labelled (%.2fs)\n",
            sum(has_var), ncol(labelled), t_label[["elapsed"]]))


# ── Step 3: rs_lookup ─────────────────────────────────────────────────────
cat("\n== STEP 3: rs_lookup('age') =========================================\n")
lk <- tryCatch(rs_lookup("age"), error = function(e) {
  cat(sprintf("rs_lookup error: %s\n", conditionMessage(e))); NULL
})
if (!is.null(lk)) {
  cat(sprintf("rs_lookup returned %d row(s)\n", nrow(lk$df)))
}


# ── Step 4: scope (v3 catalog browser) ─────────────────────────
cat("\n== STEP 4: scope(search='lisa') ===========================\n")
rg <- tryCatch(scope(search = "lisa"),

               error = function(e) {
                 cat(sprintf("scope error: %s\n", conditionMessage(e)))
                 NULL
               })
if (!is.null(rg) && nrow(rg) > 0L) {
  print(utils::head(rg, 5L))
}


# ── Step 5: rs_lab on a small slice ───────────────────────────────────────
cat("\n== STEP 5: rs_lab(labelled[, 1:5]) ==================================\n")
slice <- tryCatch(rs_lab(labelled[, 1:5, drop = FALSE]),
                  error = function(e) {
                    cat(sprintf("rs_lab error: %s\n", conditionMessage(e)))
                    NULL
                  })
if (!is.null(slice)) cat(sprintf("rs_lab returned %d rows x %d cols\n",
                                   nrow(slice), ncol(slice)))


# ── Step 6: inspect what R wrote ──────────────────────────────────────────
cat("\n== AFTER =============================================================\n")
cat("Files in REGISTREAM_DIR:\n")
after_files <- list.files(real_cache, all.files = TRUE, no.. = TRUE)
for (f in after_files) {
  info <- file.info(file.path(real_cache, f))
  kind <- if (info$isdir) "DIR " else "FILE"
  marker <- if (f %in% before_files) "   " else "NEW"
  cat(sprintf("  %s %s  %s\n", marker, kind, f))
}

cat("\n--- config_r.toml ---\n")
if (file.exists(file.path(real_cache, "config_r.toml"))) {
  cat(readLines(file.path(real_cache, "config_r.toml")), sep = "\n")
  cat("\n")
}

cat("\n--- usage_r.csv ---\n")
if (file.exists(file.path(real_cache, "usage_r.csv"))) {
  lines <- readLines(file.path(real_cache, "usage_r.csv"))
  cat(lines, sep = "\n")
  cat(sprintf("\n(total rows incl. header: %d)\n", length(lines)))
}

cat("\n--- rs_stats() ---\n")
print(registream::rs_stats())

cat("\n== DONE ==============================================================\n")
