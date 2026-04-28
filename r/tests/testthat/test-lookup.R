# rs_lookup() v3 tests. Uses the synthetic v3 bundle only; the
# pre-v3 v1/v2 modes have been retired along with register/variant/
# version.

.lookup_setup <- function() {
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


test_that("rs_lookup() finds variables by name (default mode)", {
  skip_without_withr()
  tmp <- .lookup_setup()

  out <- rs_lookup(c("age", "sex"), directory = tmp)
  expect_s3_class(out, "rs_lookup_result")
  expect_setequal(out$df$variable_name, c("age", "sex"))
  expect_identical(length(out$missing), 0L)
})


test_that("rs_lookup() reports missing variables", {
  skip_without_withr()
  tmp <- .lookup_setup()

  out <- rs_lookup(c("age", "does_not_exist"), directory = tmp)
  expect_identical(nrow(out$df), 1L)
  expect_identical(out$missing, "does_not_exist")
})


test_that("rs_lookup() case-insensitive match on requested names", {
  skip_without_withr()
  tmp <- .lookup_setup()

  out <- rs_lookup(c("AGE", "SEX"), directory = tmp)
  expect_setequal(tolower(out$df$variable_name), c("age", "sex"))
})


test_that("rs_lookup(detail = TRUE) attaches scope tuple + release", {
  skip_without_withr()
  tmp <- .lookup_setup()

  out <- rs_lookup("age", detail = TRUE, directory = tmp)
  expect_true("scope_level_1" %in% colnames(out$df))
  expect_true("scope_level_2" %in% colnames(out$df))
  expect_true("release" %in% colnames(out$df))
  expect_identical(as.character(out$df$scope_level_1), "LISA")
})


test_that("rs_lookup() with scope filter narrows to that atom", {
  skip_without_withr()
  tmp <- .lookup_setup()

  # BR/Barn has only birthdate; asking for age under BR returns missing
  out <- rs_lookup("age", scope = c("BR", "Barn"), directory = tmp)
  expect_identical(nrow(out$df), 0L)
  expect_identical(out$missing, "age")
})


test_that("rs_lookup() rejects empty request", {
  skip_without_withr()
  tmp <- .lookup_setup()

  expect_error(rs_lookup(character(0), directory = tmp),
               "non-empty character vector")
})


test_that("rs_lookup() print output includes variable names", {
  skip_without_withr()
  tmp <- .lookup_setup()

  out <- rs_lookup(c("age", "sex"), directory = tmp)
  printed <- utils::capture.output(print(out))
  expect_true(any(grepl("age|sex", printed)))
})
