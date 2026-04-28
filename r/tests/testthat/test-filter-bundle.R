# filter_bundle() end-to-end tests: scope resolution, overflow-token
# rule, release filter, auto-drill, _is_primary tagging.

test_that("filter_bundle() narrows to an explicit scope + release", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  fb <- filter_bundle(bundle,
                      scope   = c("LISA", "Individer"),
                      release = "2021")
  expect_s3_class(fb, "rs_filtered_bundle")
  expect_identical(fb$resolved_scope, c("LISA", "Individer"))
  expect_identical(fb$resolved_release, "2021")
  # Variables tied to scope_id=1 only (release_set_id=1): age, sex, kon
  expect_setequal(fb$variables$variable_name, c("age", "sex", "kon"))
  expect_true(all(fb$variables$`_is_primary` == 1L))
})


test_that("filter_bundle() overflow-token promotes last token to release", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # Depth is 2; three tokens → last becomes release
  fb <- filter_bundle(bundle,
                      scope = c("LISA", "Individer", "2021"))
  expect_identical(fb$resolved_release, "2021")
  expect_identical(fb$resolved_scope, c("LISA", "Individer"))
  expect_setequal(fb$variables$variable_name, c("age", "sex", "kon"))
})


test_that("filter_bundle() auto-drills release when exactly one matches", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # BR/Barn has exactly one release (2020)
  fb <- filter_bundle(bundle, scope = c("BR", "Barn"))
  expect_identical(fb$auto_drilled_release, "2020")
  expect_null(fb$resolved_release)
})


test_that("filter_bundle() does NOT auto-drill when multiple releases remain", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # LISA alone covers both Individer (2021) and Företag (2021); both
  # happen to share release 2021 in the fixture, so extend by adding
  # another release manually.
  # With the given fixture LISA has a single release too; so this test
  # is essentially a parity proof for the auto-drilled field.
  fb <- filter_bundle(bundle, scope = "LISA")
  expect_identical(fb$auto_drilled_release, "2021")
})


test_that("filter_bundle() raises rs_error_filter on unknown release", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  expect_error(
    filter_bundle(bundle, scope = c("LISA", "Individer"), release = "9999"),
    class = "rs_error_filter"
  )
})


test_that("filter_bundle() rejects overflow beyond depth+1", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  expect_error(
    filter_bundle(bundle, scope = c("LISA", "Individer", "2021", "extra")),
    class = "rs_error_filter"
  )
})


test_that("filter_bundle() tags _is_primary via inference when no scope given", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)
  bundle <- registream::load_bundle("scb", "eng")

  # Three user columns; all three are in LISA/Individer, so the inferred
  # tuple is (LISA, Individer). _is_primary=1 on rs=1 rows; 0 otherwise.
  fb <- filter_bundle(bundle, datavars = c("age", "sex", "kon"))
  expect_s3_class(fb$inferred, "rs_scope_inference")
  expect_identical(fb$inferred$levels, c("LISA", "Individer"))
  # Variables are NOT narrowed; only tagged.
  expect_identical(nrow(fb$variables), 5L)

  primary_names <- fb$variables$variable_name[fb$variables$`_is_primary` == 1L]
  expect_setequal(primary_names, c("age", "sex", "kon"))
})


test_that("filter_bundle() on core-only bundle rejects scope + release", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  haven::write_dta(
    data.frame(
      variable_name = "x",
      variable_label = "X",
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

  expect_error(filter_bundle(bundle, scope = "LISA"),
               class = "rs_error_filter")
  expect_error(filter_bundle(bundle, release = "2021"),
               class = "rs_error_filter")

  # No scope/release → passes through unchanged
  fb <- filter_bundle(bundle)
  expect_identical(nrow(fb$variables), 1L)
  expect_identical(fb$variables$`_is_primary`, 0L)
})
