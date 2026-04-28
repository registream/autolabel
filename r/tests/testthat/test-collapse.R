# collapse_to_one_per_variable(): sort key + dedup semantics.

test_that("collapse returns one row per variable_name", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  fb <- filter_bundle(bundle, datavars = c("age", "sex", "kon"))
  out <- collapse_to_one_per_variable(fb, bundle)

  # 5 variables in the fixture; all surface (no narrowing when only
  # datavars is passed; primary tagging only).
  expect_identical(nrow(out), 5L)
  expect_setequal(out$variable_name,
                  c("age", "sex", "kon", "income", "birthdate"))
  expect_identical(length(unique(out$variable_name)), 5L)
})


test_that("_is_primary bias wins over label frequency", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  utils::write.table(
    data.frame(
      key = c("domain", "schema_version", "publisher",
              "bundle_release_date", "languages", "scope_depth",
              "scope_level_1_name", "scope_level_1_title"),
      value = c("scb", "2.0", "SCB", "2026-04-17", "eng", "1",
                "register", "Register"),
      stringsAsFactors = FALSE
    ),
    file.path(d, "manifest_eng.csv"),
    sep = ";", row.names = FALSE, col.names = TRUE,
    quote = FALSE, fileEncoding = "UTF-8"
  )

  # LISA has three variables (age, sex, kon) so inference will rank
  # it above BR (which has only one). The "age" rows are:
  #   rs=1 (LISA),  label="Age (LISA)"
  #   rs=2 (BR),    label="Age (common)"
  #   rs=3 (BR),    label="Age (common)"
  # Without _is_primary bias the two BR rows share a label → freq=2
  # wins. With _is_primary=1 on the LISA row after inference, LISA
  # wins despite the freq tie.
  haven::write_dta(
    data.frame(
      variable_name = c("age", "sex", "kon", "age", "age"),
      variable_label = c("Age (LISA)", "Sex (LISA)", "Kon (LISA)",
                         "Age (common)", "Age (common)"),
      variable_type = c("continuous", "categorical", "categorical",
                        "continuous", "continuous"),
      release_set_id = c(1L, 1L, 1L, 2L, 3L),
      stringsAsFactors = FALSE
    ),
    file.path(d, "variables_eng.dta")
  )
  haven::write_dta(
    data.frame(
      value_label_id = "v", value_labels_json = "{}",
      value_labels_stata = "", code_count = 0L,
      stringsAsFactors = FALSE
    ),
    file.path(d, "value_labels_eng.dta")
  )
  haven::write_dta(
    data.frame(
      scope_id = c(1L, 2L, 3L),
      scope_level_1 = c("LISA", "BR", "BR"),
      release = c("2021", "2020", "2019"),
      stringsAsFactors = FALSE
    ),
    file.path(d, "scope_eng.dta")
  )
  haven::write_dta(
    data.frame(
      release_set_id = c(1L, 2L, 3L),
      scope_id       = c(1L, 2L, 3L),
      stringsAsFactors = FALSE
    ),
    file.path(d, "release_sets_eng.dta")
  )

  bundle <- registream::load_bundle("scb", "eng")
  # Explicit scope = LISA → only LISA rows survive the filter; the one
  # "age" row (Age (LISA)) is the only remaining row for that variable.
  fb <- filter_bundle(bundle, scope = "LISA")
  out <- collapse_to_one_per_variable(fb, bundle)
  age_row <- out[out$variable_name == "age", , drop = FALSE]
  expect_identical(nrow(age_row), 1L)
  expect_identical(age_row$variable_label, "Age (LISA)")

  # Inference: LISA has 3 matches (age, sex, kon), BR has 1 (age).
  # infer_scope picks LISA, tags only rs=1 rows with _is_primary=1.
  # Variables stay unfiltered. Collapse on "age" now sees:
  #   rs=1: _is_primary=1, freq=1 for "Age (LISA)"
  #   rs=2: _is_primary=0, freq=2 for "Age (common)"
  #   rs=3: _is_primary=0, freq=2 for "Age (common)"
  # Sort key puts _is_primary DESC first → LISA wins.
  fb2 <- filter_bundle(bundle, datavars = c("age", "sex", "kon"))
  expect_identical(fb2$inferred$levels, "LISA")
  out2 <- collapse_to_one_per_variable(fb2, bundle)
  age2 <- out2[out2$variable_name == "age", , drop = FALSE]
  expect_identical(age2$variable_label, "Age (LISA)")
})


test_that("label frequency breaks ties within same _is_primary tier", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  utils::write.table(
    data.frame(
      key = c("domain", "schema_version", "publisher",
              "bundle_release_date", "languages", "scope_depth",
              "scope_level_1_name", "scope_level_1_title"),
      value = c("scb", "2.0", "SCB", "2026-04-17", "eng", "1",
                "register", "Register"),
      stringsAsFactors = FALSE
    ),
    file.path(d, "manifest_eng.csv"),
    sep = ";", row.names = FALSE, col.names = TRUE,
    quote = FALSE, fileEncoding = "UTF-8"
  )

  # All three rows have _is_primary=0 (no scope, no inference target).
  # Two rows share "Age (common)" → label_freq=2; one "Age (rare)" → 1.
  # With _is_primary tied, label_freq DESC picks "Age (common)".
  haven::write_dta(
    data.frame(
      variable_name = c("age", "age", "age"),
      variable_label = c("Age (common)", "Age (common)", "Age (rare)"),
      variable_type = c("continuous", "continuous", "continuous"),
      release_set_id = c(1L, 2L, 3L),
      stringsAsFactors = FALSE
    ),
    file.path(d, "variables_eng.dta")
  )
  haven::write_dta(
    data.frame(
      value_label_id = "v", value_labels_json = "{}",
      value_labels_stata = "", code_count = 0L,
      stringsAsFactors = FALSE
    ),
    file.path(d, "value_labels_eng.dta")
  )
  haven::write_dta(
    data.frame(
      scope_id = c(1L, 2L, 3L),
      scope_level_1 = c("A", "B", "C"),
      release = c("2021", "2021", "2021"),
      stringsAsFactors = FALSE
    ),
    file.path(d, "scope_eng.dta")
  )
  haven::write_dta(
    data.frame(
      release_set_id = c(1L, 2L, 3L),
      scope_id       = c(1L, 2L, 3L),
      stringsAsFactors = FALSE
    ),
    file.path(d, "release_sets_eng.dta")
  )

  bundle <- registream::load_bundle("scb", "eng")
  # No scope / no datavars → inference returns NULL, _is_primary=0
  # for every row; the freq=2 label should win.
  fb <- filter_bundle(bundle)
  out <- collapse_to_one_per_variable(fb, bundle)
  expect_identical(out$variable_label, "Age (common)")
})


test_that("scope tuple breaks label-frequency ties (deterministic)", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  utils::write.table(
    data.frame(
      key = c("domain", "schema_version", "publisher",
              "bundle_release_date", "languages", "scope_depth",
              "scope_level_1_name", "scope_level_1_title"),
      value = c("scb", "2.0", "SCB", "2026-04-17", "eng", "1",
                "register", "Register"),
      stringsAsFactors = FALSE
    ),
    file.path(d, "manifest_eng.csv"),
    sep = ";", row.names = FALSE, col.names = TRUE,
    quote = FALSE, fileEncoding = "UTF-8"
  )

  # Two rows, distinct labels, both _is_primary=0, label_freq=1 each.
  # Tie-break on scope_level_1 ASC: "BR" before "LISA".
  haven::write_dta(
    data.frame(
      variable_name = c("age", "age"),
      variable_label = c("Age from LISA", "Age from BR"),
      variable_type = c("continuous", "continuous"),
      release_set_id = c(1L, 2L),
      stringsAsFactors = FALSE
    ),
    file.path(d, "variables_eng.dta")
  )
  haven::write_dta(
    data.frame(
      value_label_id = "v", value_labels_json = "{}",
      value_labels_stata = "", code_count = 0L,
      stringsAsFactors = FALSE
    ),
    file.path(d, "value_labels_eng.dta")
  )
  haven::write_dta(
    data.frame(
      scope_id = c(1L, 2L),
      scope_level_1 = c("LISA", "BR"),
      release = c("2021", "2021"),
      stringsAsFactors = FALSE
    ),
    file.path(d, "scope_eng.dta")
  )
  haven::write_dta(
    data.frame(
      release_set_id = c(1L, 2L),
      scope_id       = c(1L, 2L),
      stringsAsFactors = FALSE
    ),
    file.path(d, "release_sets_eng.dta")
  )

  bundle <- registream::load_bundle("scb", "eng")
  fb <- filter_bundle(bundle)
  out <- collapse_to_one_per_variable(fb, bundle)
  # BR < LISA alphabetically → "Age from BR" wins
  expect_identical(out$variable_label, "Age from BR")
})


test_that("collapse is a no-op on empty variables", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  fb <- filter_bundle(bundle, scope = "LISA", release = "2021")
  fb$variables <- fb$variables[0L, , drop = FALSE]
  out <- collapse_to_one_per_variable(fb, bundle)
  expect_identical(nrow(out), 0L)
})
