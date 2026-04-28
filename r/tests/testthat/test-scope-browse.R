# scope(): 4-mode browser tests. Tokens are positional via `...`.

setup_v3 <- function() {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  withr::local_envvar(REGISTREAM_DIR = tmp, .local_envir = parent.frame())
  make_v3_bundle_scb_eng(tmp)

  cfg <- registream::config_defaults()
  cfg$usage_logging   <- FALSE
  cfg$internet_access <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, tmp)
  tmp
}


test_that("scope() with no tokens browses level 1", {
  skip_without_withr()
  tmp <- setup_v3()

  out <- scope(directory = tmp)
  expect_setequal(as.character(out$scope_level_1), c("LISA", "BR"))
  expect_true("variable_count" %in% colnames(out))
  lisa_count <- out$variable_count[out$scope_level_1 == "LISA"]
  br_count   <- out$variable_count[out$scope_level_1 == "BR"]
  expect_identical(lisa_count, 4L)
  expect_identical(br_count, 1L)
})


test_that("scope('LISA') drills into level 2", {
  skip_without_withr()
  tmp <- setup_v3()

  out <- scope("LISA", directory = tmp)
  expect_setequal(as.character(out$scope_level_2), c("Individer", "Företag"))
})


test_that("scope('LISA', 'Individer') returns releases", {
  skip_without_withr()
  tmp <- setup_v3()

  out <- scope("LISA", "Individer", directory = tmp)
  expect_true("release" %in% colnames(out))
  expect_identical(as.character(out$release), "2021")
})


test_that("scope('LISA', 'Individer', release = '2021') lists variables", {
  skip_without_withr()
  tmp <- setup_v3()

  out <- scope("LISA", "Individer", release = "2021", directory = tmp)
  expect_setequal(out$variable_name, c("age", "sex", "kon"))
  expect_true("variable_label" %in% colnames(out))
})


test_that("scope() overflow-token rule promotes last token to release", {
  skip_without_withr()
  tmp <- setup_v3()

  out <- scope("LISA", "Individer", "2021", directory = tmp)
  expect_setequal(out$variable_name, c("age", "sex", "kon"))
})


test_that("scope() accepts a single vector equivalently", {
  skip_without_withr()
  tmp <- setup_v3()

  out_dots <- scope("LISA", "Individer", directory = tmp)
  out_vec  <- scope(c("LISA", "Individer"), directory = tmp)
  expect_identical(out_dots, out_vec)
})


test_that("scope(search = 'lis') filters distinct values", {
  skip_without_withr()
  tmp <- setup_v3()

  out <- scope(search = "lis", directory = tmp)
  expect_identical(as.character(out$scope_level_1), "LISA")
})


test_that("scope() rejects core-only bundles", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  haven::write_dta(
    data.frame(
      variable_name  = "x",
      variable_label = "X",
      variable_type  = "continuous",
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

  cfg <- registream::config_defaults()
  cfg$usage_logging   <- FALSE
  cfg$internet_access <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, tmp)

  expect_error(scope(directory = tmp), "full v3 bundle")
})
