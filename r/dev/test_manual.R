# dev/test_manual.R: R analog of autolabel/stata/dev/test_manual.do
# and autolabel/python/registream-autolabel/dev/test_manual.py.
#
# Walks the same lookup -> scope-browse -> waterfall -> autolabel
# -> pin-scope -> pin-release sequence as the Stata and Python files,
# so all three clients exercise the same flows against the same
# autolabel/examples/lisa.dta fixture.
#
# Not shipped in the package (`^dev$` is in `.Rbuildignore`).
#
# Pre-flight (run once in a shell before sourcing this file):
#
#   cd ~/Github/registream-org/autolabel/r
#   Rscript -e 'devtools::load_all()'   # editable, no install needed
#
# The dev API server at localhost:5000 must be running for the
# rs_update_datasets() call in section 1 to succeed; without it the
# bundle load will fail unless the cache at ~/.registream/autolabel/
# is already populated.
#
# Capture a log:
#
#   Rscript dev/test_manual.R 2>&1 | tee dev/test_manual.log

suppressPackageStartupMessages({
  # Load source trees (works whether or not the package is installed; the
  # installed copy may be stale relative to the working source).
  pkgload::load_all("../../registream/r", quiet = TRUE)
  pkgload::load_all(".", quiet = TRUE)
  library(haven)
})

# 0. Host override: point at the local dev API
Sys.setenv(REGISTREAM_API_HOST = "http://localhost:5000")
Sys.setenv(REGISTREAM_AUTO_APPROVE = "yes")
# Force the shared cache (matches Stata + Python). In CRAN-only mode the
# R client would prompt for shared-vs-isolated; this bypass is dev-only.
Sys.setenv(REGISTREAM_DIR = path.expand("~/.registream"))

EXAMPLES <- normalizePath(
  file.path(getwd(), "..", "examples", "lisa.dta"),
  mustWork = FALSE
)
if (!file.exists(EXAMPLES)) {
  EXAMPLES <- system.file("extdata", "lisa.dta", package = "autolabel")
}
cat(sprintf("\n=== Fixture: %s ===\n", EXAMPLES))


cat("\n=== 1. Download (or refresh) the SCB English bundle ===\n")
print(rs_update_datasets("scb", "eng", force = FALSE))


cat("\n=== 2. Lookups ===\n")
print(rs_lookup("carb", domain = "scb", lang = "eng"))
print(rs_lookup("ssyk*", domain = "scb", lang = "swe"))
print(rs_lookup("ssyk", domain = "scb", lang = "swe", detail = TRUE))


cat("\n=== 3. Scope browse ===\n")
print(scope(domain = "scb", lang = "eng"))
print(scope(domain = "scb", lang = "eng", search = "lisa"))
print(scope(domain = "scb", lang = "eng", search = "election"))
print(scope(domain = "scb", lang = "swe", search = "kommunfullmäktige"))


cat("\n=== 4. Waterfall: drill from a scope down to releases ===\n")
print(scope("LISA", domain = "scb", lang = "eng"))
print(scope("LISA", "Individuals aged 16 and older",
            domain = "scb", lang = "eng"))
# Overflow: third token promotes to release()
print(scope("LISA", "Individuals aged 16 and older", "2005",
            domain = "scb", lang = "eng"))


cat("\n=== 5. Variable-level lookup with scope narrowing ===\n")
print(rs_lookup("kon", domain = "scb", lang = "eng", detail = TRUE))


cat("\n=== 6. Load lisa.dta and auto-label (inferred scope) ===\n")
df <- as.data.frame(haven::read_dta(EXAMPLES))
cat(sprintf("Read lisa.dta: %d rows x %d cols\n", nrow(df), ncol(df)))
labelled <- autolabel(df, domain = "scb", lang = "eng")
n_var <- sum(vapply(labelled,
                    function(c) !is.null(attr(c, "label", exact = TRUE)),
                    logical(1)))
n_val <- sum(vapply(labelled,
                    function(c) inherits(c, "haven_labelled"),
                    logical(1)))
cat(sprintf("Variable labels: %d/%d, value-labelled: %d/%d\n",
            n_var, ncol(labelled), n_val, ncol(labelled)))


cat("\n=== 7. Auto-label with explicit scope pin (LISA) ===\n")
df <- as.data.frame(haven::read_dta(EXAMPLES))
labelled_pinned <- autolabel(df, domain = "scb", lang = "eng",
                             scope = "LISA")
n_var <- sum(vapply(labelled_pinned,
                    function(c) !is.null(attr(c, "label", exact = TRUE)),
                    logical(1)))
cat(sprintf("Variable labels with scope='LISA': %d/%d\n",
            n_var, ncol(labelled_pinned)))


cat("\n=== 8. Auto-label with release pin (overflow-token syntax) ===\n")
df <- as.data.frame(haven::read_dta(EXAMPLES))
labelled_release <- autolabel(
  df, domain = "scb", lang = "eng",
  scope = c("LISA", "Individuals aged 16 and older", "2005")
)
rs_attr <- attr(labelled_release, "registream", exact = TRUE)
cat(sprintf("Resolved release: %s\n",
            if (!is.null(rs_attr$release)) rs_attr$release else "<none>"))


cat("\n=== 9. Multi-domain scope sweep (parity with test_manual.do tail) ===\n")
sweeps <- list(
  c("scb",      "eng"), c("scb",      "swe"),
  c("dst",      "eng"), c("dst",      "dan"),
  c("ssb",      "eng"), c("ssb",      "nor"),
  c("sos",      "eng"), c("sos",      "swe"),
  c("fk",       "eng"), c("fk",       "swe"),
  c("hagstofa", "eng"), c("hagstofa", "isl")
)
for (pair in sweeps) {
  cat(sprintf("\n--- scope(domain='%s', lang='%s') ---\n", pair[[1]], pair[[2]]))
  out <- tryCatch(
    scope(domain = pair[[1]], lang = pair[[2]]),
    error = function(e) {
      cat(sprintf("  ERROR: %s\n", conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(out)) cat(sprintf("  rows: %d\n", nrow(out)))
}


cat("\n=== 10. rs_lab on the inferred-label result ===\n")
print(utils::head(rs_lab(labelled), 5L))


cat("\n=== DONE ===\n")
