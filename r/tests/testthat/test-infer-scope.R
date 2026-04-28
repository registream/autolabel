# infer_scope(): depth-agnostic scope inference with 10% threshold.

test_that("infer_scope() picks the highest-match scope tuple", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # User has age, sex, kon → all three live in (LISA, Individer)
  result <- infer_scope(bundle, c("age", "sex", "kon"))
  expect_s3_class(result, "rs_scope_inference")
  expect_identical(result$levels, c("LISA", "Individer"))
  expect_identical(result$matches, 3L)
  expect_identical(result$total_datavars, 3L)
  expect_identical(result$match_pct, 100L)
  expect_true(result$has_strong_primary)
})


test_that("infer_scope() returns aliases for the winning tuple", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  result <- infer_scope(bundle, c("age", "sex"))
  expect_identical(result$level_aliases, c("LISA", "Persons"))
})


test_that("infer_scope() is case-insensitive on user columns", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  result <- infer_scope(bundle, c("AGE", "SEX"))
  expect_identical(result$levels, c("LISA", "Individer"))
  expect_identical(result$matches, 2L)
})


test_that("infer_scope() returns NULL when no match", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  expect_null(infer_scope(bundle, c("foo", "bar", "baz")))
})


test_that("infer_scope() returns NULL for empty datavars", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  expect_null(infer_scope(bundle, character(0)))
})


test_that("infer_scope() returns NULL on core-only bundles", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  haven::write_dta(
    data.frame(
      variable_name = "age",
      variable_label = "Age",
      variable_type = "continuous",
      release_set_id = 1L,
      stringsAsFactors = FALSE
    ),
    file.path(d, "variables_eng.dta")
  )
  haven::write_dta(
    data.frame(value_label_id = "v", value_labels_json = "{}",
               value_labels_stata = "", code_count = 0L,
               stringsAsFactors = FALSE),
    file.path(d, "value_labels_eng.dta")
  )

  bundle <- registream::load_bundle("scb", "eng")
  expect_true(bundle$core_only)
  expect_null(infer_scope(bundle, c("age")))
})


test_that("infer_scope() match_pct threshold governs has_strong_primary", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # 1 match out of 20 user columns = 5% → below 10% threshold
  datavars <- c("age", sprintf("zzz%02d", seq_len(19)))
  result <- infer_scope(bundle, datavars)
  expect_identical(result$matches, 1L)
  expect_identical(result$total_datavars, 20L)
  expect_identical(result$match_pct, 5L)
  expect_false(result$has_strong_primary)

  # 2 matches out of 20 = 10% → exactly at threshold (inclusive)
  datavars2 <- c("age", "sex", sprintf("zzz%02d", seq_len(18)))
  r2 <- infer_scope(bundle, datavars2)
  expect_identical(r2$match_pct, 10L)
  expect_true(r2$has_strong_primary)
})
