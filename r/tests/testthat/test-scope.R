# Depth-agnostic scope ladder tests.

test_that("normalize_token() lowercases and strips apostrophes", {
  expect_identical(normalize_token("LISA"), "lisa")
  expect_identical(normalize_token("O'Brien"), "obrien")
  expect_identical(normalize_token(NA), "")
  expect_identical(normalize_token(NULL), "")
  expect_identical(normalize_token(""), "")
  expect_identical(normalize_token(c("LISA", "Barn's")), c("lisa", "barns"))
})


test_that("resolve_scope() uses the alias→name→substring ladder", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # Exact alias match: "Barnregistret" → BR (level 1 alias)
  r <- resolve_scope(bundle, list("Barnregistret"))
  expect_identical(nrow(r$scope_df), 1L)
  expect_identical(r$resolved, "BR")

  # Exact name match: "LISA"
  r <- resolve_scope(bundle, list("LISA"))
  expect_gt(nrow(r$scope_df), 1L)
  expect_identical(r$resolved, "LISA")

  # Substring match: "lis" matches LISA
  r <- resolve_scope(bundle, list("lis"))
  expect_identical(r$resolved, "LISA")

  # Case-insensitive at level 2 alias: "persons" → Individer
  r <- resolve_scope(bundle, list("LISA", "persons"))
  expect_identical(r$resolved, c("LISA", "Individer"))
})


test_that("resolve_scope() raises rs_error_scope with a hint on miss", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  expect_error(resolve_scope(bundle, list("DOES_NOT_EXIST")),
               class = "rs_error_scope")
})


test_that("resolve_scope() rejects tokens deeper than scope_depth", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # depth = 2; three tokens should trip the level-i > depth check
  expect_error(
    resolve_scope(bundle, list("LISA", "Individer", "extra")),
    class = "rs_error_scope"
  )
})


test_that("resolve_scope() apostrophe-insensitive match", {
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
  haven::write_dta(
    data.frame(
      variable_name = "x",
      variable_label = "x",
      variable_type = "continuous",
      release_set_id = 1L,
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
      scope_id = 1L,
      scope_level_1 = "Women's crisis centres",
      release = "2021",
      stringsAsFactors = FALSE
    ),
    file.path(d, "scope_eng.dta")
  )
  haven::write_dta(
    data.frame(release_set_id = 1L, scope_id = 1L,
               stringsAsFactors = FALSE),
    file.path(d, "release_sets_eng.dta")
  )

  bundle <- registream::load_bundle("scb", "eng")
  r <- resolve_scope(bundle, list("womens crisis centres"))
  expect_identical(r$resolved, "Women's crisis centres")
})
