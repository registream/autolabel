# Synthetic bundle fixture builder, parallel to
# `registream/r/tests/testthat/test-bundle.R` helpers and the Python
# `conftest.py` bundle fixtures. v3-only; the pre-v3 flat-layout
# builders were retired when `register`/`variant`/`version` were
# removed.

skip_without_withr <- function() {
  testthat::skip_if_not_installed("withr")
}

# Read the variable-label attribute with EXACT matching. Base R's
# `attr()` does partial matching by default, which silently returns the
# `labels` (plural, i.e. value labels) attribute when you ask for `label`.
# That's a footgun for haven_labelled columns; tests must use exact.
get_label <- function(x) attr(x, "label", exact = TRUE)


# v3 English bundle (5-file: manifest + variables + value_labels + scope
# + release_sets), depth = 2. Scope tuples:
#   (LISA, Individer)  scope_id=1 release=2021
#   (LISA, Företag)    scope_id=2 release=2021
#   (BR,   Barn)       scope_id=3 release=2020
# release_sets:
#   rs=1 -> scope 1 (LISA/Individer)
#   rs=2 -> scope 2 (LISA/Företag)
#   rs=3 -> scope 3 (BR/Barn)
# variables:
#   age, sex, kon (rs=1); income (rs=2); birthdate (rs=3)
# Written to the per-domain subdirectory: {parent}/autolabel/scb/...
make_v3_bundle_scb_eng <- function(parent_dir) {
  d <- file.path(parent_dir, "autolabel", "scb")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)

  manifest_df <- data.frame(
    key = c("domain", "schema_version", "publisher",
            "bundle_release_date", "languages", "scope_depth",
            "scope_level_1_name", "scope_level_1_title",
            "scope_level_2_name", "scope_level_2_title"),
    value = c("scb", "2.0", "SCB",
              "2026-04-17", "eng|swe", "2",
              "register", "Register",
              "population", "Population"),
    stringsAsFactors = FALSE
  )
  utils::write.table(manifest_df, file.path(d, "manifest_eng.csv"),
                     sep = ";", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, fileEncoding = "UTF-8")

  variables <- data.frame(
    variable_name  = c("age", "sex", "kon", "income", "birthdate"),
    variable_label = c("Age in years", "Sex", "Sex code (LISA)",
                       "Annual income", "Birth date"),
    variable_type  = c("continuous", "categorical", "categorical",
                       "continuous", "date"),
    value_label_id = c(" ", "sex_lbl", "kon_lbl", " ", " "),
    variable_unit  = c("years", " ", " ", "SEK", " "),
    release_set_id = c(1L, 1L, 1L, 2L, 3L),
    stringsAsFactors = FALSE
  )
  haven::write_dta(variables, file.path(d, "variables_eng.dta"))

  value_labels <- data.frame(
    value_label_id     = c("sex_lbl", "kon_lbl"),
    value_labels_json  = c('{"1":"Male","2":"Female"}',
                           '{"1":"Man","2":"Woman"}'),
    value_labels_stata = c('"1" "Male" "2" "Female"',
                           '"1" "Man" "2" "Woman"'),
    code_count         = c(2L, 2L),
    stringsAsFactors = FALSE
  )
  haven::write_dta(value_labels, file.path(d, "value_labels_eng.dta"))

  scope <- data.frame(
    scope_id            = c(1L, 2L, 3L),
    scope_level_1       = c("LISA", "LISA", "BR"),
    scope_level_1_alias = c("LISA", "LISA", "Barnregistret"),
    scope_level_2       = c("Individer", "Företag", "Barn"),
    scope_level_2_alias = c("Persons", "Firms", "Children"),
    release             = c("2021", "2021", "2020"),
    stringsAsFactors    = FALSE
  )
  haven::write_dta(scope, file.path(d, "scope_eng.dta"))

  release_sets <- data.frame(
    release_set_id = c(1L, 2L, 3L),
    scope_id       = c(1L, 2L, 3L),
    stringsAsFactors = FALSE
  )
  haven::write_dta(release_sets, file.path(d, "release_sets_eng.dta"))

  invisible(parent_dir)
}
