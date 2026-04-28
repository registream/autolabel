# autolabel() v3 end-to-end tests.
#
# The R client is v3-only (no register/variant/version legacy args).
# Every test mounts the synthetic v3 bundle in a tempdir, points
# REGISTREAM_DIR at it, and runs the full pipeline (load_bundle ->
# filter_bundle -> collapse -> apply_labels -> stamp_registream_attrs).

.setup <- function() {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  withr::local_envvar(REGISTREAM_DIR = tmp, .local_envir = parent.frame())
  make_v3_bundle_scb_eng(tmp)

  cfg <- registream::config_defaults()
  cfg$usage_logging       <- FALSE
  cfg$internet_access     <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, tmp)
  tmp
}


test_that("autolabel() applies variable + value labels from v3 bundle", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   stringsAsFactors = FALSE)
  out <- autolabel(df, scope = c("LISA", "Individer"), release = "2021",
                   directory = tmp)

  expect_identical(get_label(out$age), "Age in years (years)")
  expect_identical(get_label(out$sex), "Sex")

  stamp <- attr(out, "registream", exact = TRUE)
  expect_identical(stamp$domain, "scb")
  expect_identical(stamp$scope, c("LISA", "Individer"))
  expect_identical(stamp$release, "2021")
  expect_identical(stamp$scope_depth, 2L)
})


test_that("autolabel() auto-infers scope and reports the match", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   kon = c("1", "2", "1"),
                   stringsAsFactors = FALSE)

  expect_message(
    out <- autolabel(df, directory = tmp),
    "Auto-detected scope: LISA / Individer"
  )
  expect_identical(get_label(out$age), "Age in years (years)")
  expect_identical(get_label(out$sex), "Sex")
  expect_identical(get_label(out$kon), "Sex code (LISA)")
})


test_that("autolabel() overflow-token rule promotes release", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   stringsAsFactors = FALSE)
  out <- autolabel(df, scope = c("LISA", "Individer", "2021"),
                   directory = tmp)
  stamp <- attr(out, "registream", exact = TRUE)
  expect_identical(stamp$release, "2021")
  expect_identical(stamp$scope, c("LISA", "Individer"))
})


test_that("autolabel() auto-drills single release at full-depth scope", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(birthdate = 1:3, stringsAsFactors = FALSE)
  out <- autolabel(df, scope = c("BR", "Barn"), directory = tmp)
  stamp <- attr(out, "registream", exact = TRUE)
  expect_identical(stamp$release, "2020")
})


test_that("autolabel() rejects scope that is too deep", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, stringsAsFactors = FALSE)
  expect_error(
    autolabel(df, scope = c("LISA", "Individer", "2021", "extra"),
              directory = tmp),
    class = "rs_error_filter"
  )
})


test_that("autolabel() label_type='variables' skips value labels", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   stringsAsFactors = FALSE)
  out <- autolabel(df, scope = c("LISA", "Individer"),
                   label_type = "variables", directory = tmp)
  expect_identical(get_label(out$age), "Age in years (years)")
  # No value labels applied; sex should remain a plain character column
  expect_false(inherits(out$sex, "haven_labelled"))
})


test_that("autolabel() include_unit = FALSE drops the unit suffix", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, stringsAsFactors = FALSE)
  out <- autolabel(df, scope = c("LISA", "Individer"),
                   include_unit = FALSE, directory = tmp)
  expect_identical(get_label(out$age), "Age in years")
})


test_that("autolabel() exclude = skips listed columns", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   stringsAsFactors = FALSE)
  out <- autolabel(df, scope = c("LISA", "Individer"),
                   exclude = "sex", directory = tmp)

  expect_identical(get_label(out$age), "Age in years (years)")
  # sex should be untouched; no label, not haven_labelled
  expect_null(get_label(out$sex))
  expect_false(inherits(out$sex, "haven_labelled"))
})


test_that("autolabel() dryrun = TRUE returns plan without mutating df", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   stringsAsFactors = FALSE)
  before_attrs <- attributes(df)
  result <- autolabel(df, scope = c("LISA", "Individer"),
                      release = "2021", dryrun = TRUE, directory = tmp)

  # df must not be mutated
  expect_identical(attributes(df), before_attrs)
  expect_null(get_label(df$age))

  # Result must be the S3 object with expected shape
  expect_s3_class(result, "autolabel_dryrun")
  expect_type(result$variable_labels, "list")
  expect_type(result$value_labels, "list")
  expect_true("age" %in% names(result$variable_labels))
  expect_identical(result$variable_labels$age, "Age in years (years)")
  expect_true("sex" %in% names(result$value_labels))
  expect_identical(result$resolved_scope, c("LISA", "Individer"))
  expect_identical(result$resolved_release, "2021")
})


test_that("autolabel() dryrun + exclude work together", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   stringsAsFactors = FALSE)
  result <- autolabel(df, scope = c("LISA", "Individer"),
                      exclude = "sex", dryrun = TRUE, directory = tmp)

  expect_s3_class(result, "autolabel_dryrun")
  expect_true("age" %in% names(result$variable_labels))
  expect_false("sex" %in% names(result$variable_labels))
  expect_false("sex" %in% names(result$value_labels))
})


test_that("print.autolabel_dryrun renders expected lines", {
  skip_without_withr()
  tmp <- .setup()

  df <- data.frame(age = 1:3, stringsAsFactors = FALSE)
  result <- autolabel(df, scope = c("LISA", "Individer"),
                      dryrun = TRUE, directory = tmp)

  out <- capture.output(print(result))
  expect_match(out[1], "dryrun preview")
  expect_match(paste(out, collapse = "\n"), "variable_labels: 1")
  expect_match(paste(out, collapse = "\n"), "resolved_scope:.*LISA")
})
