# Minimal RegiStream R port walkthrough — for visual confirmation of the
# interactive flow on a clean machine. Run line by line in RStudio so you
# see each prompt as it fires.
#
# Expected prompts on a TRUE first-ever run (cache + config wiped):
#   1. rs_first_run wizard:
#        Enter choice (1-3):           <- 3  (Full mode, recommended)
#   2. rs_first_run cache location:
#        Select cache location (1-2) [1]:   <- press Enter (default = ~/.registream)
#   3. ensure_bundle download:
#        Download from RegiStream? (yes/no): <- yes

suppressMessages({
  library(autolabel)
  library(haven)
})

# A tiny LISA-style frame. Real SCB variable names so the auto-detected
# scope picks up "Longitudinal Integration Database / Individuals aged 15+".
df <- data.frame(
  Kon             = c(1L, 2L, 1L, 2L, 1L),
  Alder           = c(25L, 47L, 33L, 61L, 19L),
  CIVIL           = c("OG", "G", "G", "S", "OG"),
  Sun2000Niva_Old = c(1L, 3L, 5L, 6L, 2L),
  inkomst         = c(180000, 420000, 350000, 510000, 95000)
)

# Round-trip via .dta for realism (matches what a user reading their own
# Stata file would see).
dta <- tempfile(fileext = ".dta")
haven::write_dta(df, dta)
df <- haven::read_dta(dta)

print(df)

# --- The labelling call. First run prompts the wizard + download. ---
df_lab <- autolabel(df, domain = "scb", lang = "eng")

# Variable labels:
for (v in names(df_lab)) {
  lab <- attr(df_lab[[v]], "label", exact = TRUE)
  cat(sprintf("  %-18s %s\n", v, ifelse(is.null(lab), "<no label>", lab)))
}

# Factor view (English):
print(rs_lab(df_lab))
