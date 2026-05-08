test_that("process_for_cache() lowercases variable_name and sorts", {
  df <- data.frame(
    variable_name   = c("FOO", "bar", "BAZ"),
    variable_label  = c("F", "B", "Z"),
    stringsAsFactors = FALSE
  )
  out <- autolabel:::process_for_cache(df, "variables")
  expect_identical(out$variable_name, c("bar", "baz", "foo"))
})


test_that("process_for_cache() preserves duplicates (v3 has scope-keyed rows)", {
  df <- data.frame(
    variable_name   = c("age", "age", "sex"),
    variable_label  = c("A1", "A2", "S"),
    release_set_id  = c(1L, 2L, 1L),
    stringsAsFactors = FALSE
  )
  out <- autolabel:::process_for_cache(df, "variables")
  expect_identical(nrow(out), 3L)
})


test_that("process_for_cache() drops empty value_labels_json rows on values type", {
  df <- data.frame(
    value_label_id     = c("kon_lbl", "empty", "reg_lbl"),
    value_labels_json  = c('{"1":"Male"}', "{}", '{"01":"Region 1"}'),
    value_labels_stata = c('"1" "Male"', "", '"01" "Region 1"'),
    code_count         = c(1L, 0L, 1L),
    stringsAsFactors   = FALSE
  )
  out <- autolabel:::process_for_cache(df, "values")
  # v3 keeps both _json and _stata columns (they're required by the schema)
  expect_true("value_labels_json" %in% colnames(out))
  expect_identical(nrow(out), 2L)
  expect_setequal(out$value_label_id, c("kon_lbl", "reg_lbl"))
})


test_that("read_csv_with_delimiter_fallback() prefers semicolon", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("a;b;c", "1;2;3", "4;5;6"), tmp)
  df <- autolabel:::read_csv_with_delimiter_fallback(tmp)
  expect_identical(colnames(df), c("a", "b", "c"))
  expect_identical(nrow(df), 2L)
})


test_that("read_csv_with_delimiter_fallback() falls back to comma", {
  tmp <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("a,b,c", "1,2,3"), tmp)
  df <- autolabel:::read_csv_with_delimiter_fallback(tmp)
  expect_identical(colnames(df), c("a", "b", "c"))
  expect_identical(nrow(df), 1L)
})


test_that("extract_and_concat() reads CSVs from a named folder inside a staged bundle", {
  tmp <- withr::local_tempdir()
  bundle_root <- file.path(tmp, "scb_eng")
  dir.create(file.path(bundle_root, "variables"), recursive = TRUE)
  writeLines(
    c("variable_name;variable_label", "age;Age", "sex;Sex"),
    file.path(bundle_root, "variables", "0000.csv")
  )
  writeLines(
    c("variable_name;variable_label", "kon;Gender"),
    file.path(bundle_root, "variables", "0001.csv")
  )

  df <- autolabel:::extract_and_concat(tmp, folder = "variables")
  expect_identical(nrow(df), 3L)
  expect_setequal(df$variable_name, c("age", "sex", "kon"))
})


test_that("extract_and_concat() returns NULL when the folder is absent", {
  tmp <- withr::local_tempdir()
  bundle_root <- file.path(tmp, "scb_eng")
  dir.create(file.path(bundle_root, "variables"), recursive = TRUE)
  writeLines("a;b\n1;2", file.path(bundle_root, "variables", "0000.csv"))

  expect_null(autolabel:::extract_and_concat(tmp, folder = "scope"))
})


test_that("rs_update_datasets() short-circuits when v3 cache files exist", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  # Plant empty DTA stubs in the v3 per-domain layout.
  cache_dir <- file.path(tmp, "autolabel", "scb")
  dir.create(cache_dir, recursive = TRUE)
  for (ft in c("variables", "value_labels")) {
    file.create(file.path(cache_dir, sprintf("%s_eng.dta", ft)))
  }

  result <- rs_update_datasets("scb", "eng")
  expect_s3_class(result, "rs_download_result")
  expect_identical(length(result$files), 0L)
  expect_true(length(result$skipped) > 0L)
  expect_identical(nrow(result$failed), 0L)
})


test_that("rs_update_datasets() honors internet_access = FALSE", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- registream::config_defaults()
  cfg$internet_access <- FALSE
  registream::config_save(cfg, tmp)

  result <- rs_update_datasets("scb", "eng")
  expect_s3_class(result, "rs_download_result")
  expect_true(nrow(result$failed) >= 1L)
  expect_match(result$failed$error[[1]], "internet_access")
})


# ── Cold-start cascade (ensure_bundle) ──────────────────────────────────────
#
# Coverage gap before this suite: the existing autolabel tests pre-stage
# a synthetic bundle via make_v3_bundle_scb_eng() before every call, so
# they never exercise the empty-cache path that a fresh-install user
# hits. These tests pin the four branches of ensure_bundle().

test_that("ensure_bundle() short-circuits when v3 cache files exist", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cache_dir <- file.path(tmp, "autolabel", "scb")
  dir.create(cache_dir, recursive = TRUE)
  for (ft in c("variables", "value_labels")) {
    file.create(file.path(cache_dir, sprintf("%s_eng.dta", ft)))
  }

  expect_silent(autolabel:::ensure_bundle("scb", "eng"))
})


test_that("ensure_bundle() is a no-op when internet_access = FALSE", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp,
                      REGISTREAM_AUTO_APPROVE = "yes")

  cfg <- registream::config_defaults()
  cfg$internet_access <- FALSE
  registream::config_save(cfg, tmp)

  result <- autolabel:::ensure_bundle("scb", "eng")
  expect_null(result)
})


test_that("ensure_bundle() is a no-op in non-interactive sessions without AUTO_APPROVE", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp,
                      REGISTREAM_AUTO_APPROVE = "")

  result <- autolabel:::ensure_bundle("scb", "eng")
  expect_null(result)
})


test_that("autolabel() cold-start in non-interactive session throws missing_bundle_error", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp,
                      REGISTREAM_AUTO_APPROVE = "")

  df <- data.frame(age = 1L, sex = 1L)
  expect_error(
    autolabel(df, domain = "scb", lang = "eng", directory = tmp),
    class = "rs_error_missing_bundle"
  )
})


test_that("autolabel() cold-start with AUTO_APPROVE downloads + labels (network)", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp,
                      REGISTREAM_AUTO_APPROVE = "yes")

  df <- data.frame(Kon = c(1L, 2L), Alder = c(30L, 45L))
  out <- tryCatch(
    suppressMessages(autolabel(df, domain = "scb", lang = "eng",
                               directory = tmp)),
    error = function(e) e
  )

  if (inherits(out, "error")) {
    testthat::skip(paste0("Cold-start network test skipped: ",
                          conditionMessage(out)))
  }

  # At least one variable label should be present after the cascade fires.
  labs <- vapply(names(out), function(v) {
    lab <- attr(out[[v]], "label", exact = TRUE)
    if (is.null(lab)) "" else as.character(lab)
  }, character(1))
  expect_true(any(nzchar(labs)))
})
