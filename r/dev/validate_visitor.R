# RegiStream R port — visitor validation script
#
# Run in RStudio (interactive) to verify the local dev install end-to-end.
# Exercises every public surface: cold-start cascade, autolabel apply,
# dryrun preview, scope/release pinning, rs_lookup, scope() browse,
# suggest(), info().
#
# Expectations on a TRUE first-ever run (clean cache + config):
#   - rs_first_run() wizard prompts for setup mode + cache location
#   - ensure_bundle() prompts: "Download from RegiStream? (yes/no)"
#   - First download takes ~25s; subsequent calls warm-cache at ~5-7s
#
# If you want a no-prompt run (clean automated check), uncomment:
# Sys.setenv(REGISTREAM_AUTO_APPROVE = "yes")
#
# To force a true cold-start (re-download everything), uncomment:
# unlink(tools::R_user_dir("registream", "cache"),  recursive = TRUE)
# unlink(tools::R_user_dir("registream", "config"), recursive = TRUE)

suppressMessages({
  library(autolabel)
  library(haven)
})


# ── STEP 1: Build a tiny synthetic LISA-style frame ─────────────────────────
cat("\n=== STEP 1: Build synthetic LISA-style frame, round-trip via .dta ===\n\n")

df_raw <- data.frame(
  Kon             = c(1L, 2L, 1L, 2L, 1L),
  Alder           = c(25L, 47L, 33L, 61L, 19L),
  CIVIL           = c("OG", "G", "G", "S", "OG"),
  Sun2000Niva_Old = c(1L, 3L, 5L, 6L, 2L),
  inkomst         = c(180000, 420000, 350000, 510000, 95000)
)
dta_path <- tempfile(fileext = ".dta")
haven::write_dta(df_raw, dta_path)
df <- haven::read_dta(dta_path)
print(df)


# ── STEP 2: autolabel with auto-detected scope ──────────────────────────────
cat("\n=== STEP 2: autolabel with auto-detected scope ===\n\n")

t0 <- Sys.time()
df2 <- df |> autolabel(domain = "scb", lang = "eng")
cat(sprintf("\nautolabel() elapsed: %.2fs\n",
            as.numeric(Sys.time() - t0, units = "secs")))

cat("\nVariable labels:\n")
for (v in names(df2)) {
  lab <- attr(df2[[v]], "label", exact = TRUE)
  cat(sprintf("  %-18s %s\n", v, ifelse(is.null(lab), "<no label>", lab)))
}

cat("\nrs_lab() factor view (English):\n")
print(rs_lab(df2))


# ── STEP 3: dryrun preview (no mutation) ────────────────────────────────────
cat("\n=== STEP 3: dryrun preview (no df mutation) ===\n\n")

preview <- df |> autolabel(domain = "scb", lang = "eng", dryrun = TRUE)
print(preview)


# ── STEP 4: pinning — explicit scope + release ──────────────────────────────
# In the English bundle, level 1 has "LISA" as an alias for the long
# primary "Longitudinal Integration Database ..."; level 2 carries the
# long English name as the primary. Aliases resolve transparently.
cat("\n=== STEP 4: pinning — scope=c('LISA', 'Individuals aged 15 and older'), release='2021' ===\n\n")

df3 <- df |> autolabel(
  domain  = "scb",
  lang    = "eng",
  scope   = c("LISA", "Individuals aged 15 and older"),
  release = "2021"
)
for (v in names(df3)) {
  lab <- attr(df3[[v]], "label", exact = TRUE)
  cat(sprintf("  %-18s %s\n", v, ifelse(is.null(lab), "<no label>", lab)))
}


# ── STEP 5: rs_lookup — variable detail ─────────────────────────────────────
cat("\n=== STEP 5: rs_lookup() with detail = TRUE ===\n\n")

print(rs_lookup(c("Kon", "CIVIL", "Sun2000Niva_Old"), detail = TRUE))


# ── STEP 6: scope() browse — top level ──────────────────────────────────────
cat("\n=== STEP 6: scope() — top-level registers ===\n\n")

top <- scope(domain = "scb", lang = "eng")
print(top)


# ── STEP 7: scope() drill — into LISA ───────────────────────────────────────
cat("\n=== STEP 7: scope('LISA') — drill into LISA ===\n\n")

print(scope("LISA", domain = "scb", lang = "eng"))


# ── STEP 8: suggest() — recommend scope from a frame ────────────────────────
cat("\n=== STEP 8: suggest() — given the frame, recommend scope ===\n\n")

print(suggest(df, domain = "scb", lang = "eng"))


# ── STEP 9: info() — environment summary ────────────────────────────────────
cat("\n=== STEP 9: info() — environment + cache summary ===\n\n")

info()


# ── STEP 10: Assertions — quick pass/fail check ─────────────────────────────
cat("\n=== STEP 10: Assertions ===\n\n")

ok <- function(label, cond) {
  cat(sprintf("  %s  %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
  invisible(isTRUE(cond))
}

results <- c(
  ok("Kon has variable label = Gender",
     identical(attr(df2$Kon, "label", exact = TRUE), "Gender")),
  ok("CIVIL has variable label = Marital status",
     identical(attr(df2$CIVIL, "label", exact = TRUE), "Marital status")),
  ok("CIVIL is haven_labelled (value labels applied)",
     "haven_labelled" %in% class(df2$CIVIL)),
  ok("CIVIL 'OG' -> Single",
     as.character(haven::as_factor(df2$CIVIL))[[1]] == "Single"),
  ok("CIVIL 'G'  -> Married",
     as.character(haven::as_factor(df2$CIVIL))[[2]] == "Married"),
  ok("CIVIL 'S'  -> Divorced",
     as.character(haven::as_factor(df2$CIVIL))[[4]] == "Divorced"),
  ok("Kon 1 -> Male",
     as.character(haven::as_factor(df2$Kon))[[1]] == "Male"),
  ok("Kon 2 -> Female",
     as.character(haven::as_factor(df2$Kon))[[2]] == "Female"),
  ok("Pinned scope (LISA/Individer 2021) labels Kon",
     identical(attr(df3$Kon, "label", exact = TRUE), "Gender")),
  ok("dryrun returns autolabel_dryrun",
     inherits(preview, "autolabel_dryrun")),
  ok("rs_lookup returns rs_lookup_result",
     inherits(rs_lookup("Kon"), "rs_lookup_result")),
  ok("scope() returns non-NULL output",
     !is.null(top)),
  ok("suggest() returns rs_suggest_result",
     inherits(suggest(df, domain = "scb", lang = "eng"), "rs_suggest_result"))
)

cat(sprintf("\n=== RESULT: %d / %d assertions passed ===\n",
            sum(results), length(results)))
if (all(results)) {
  cat("All good. Patch is ready to ship as 1.0.1.\n")
} else {
  cat("Some assertions failed — investigate before shipping.\n")
}
