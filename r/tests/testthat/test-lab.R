# Tests for rs_lab and rs_lab_head -- the one-line LabeledView
# substitute. These are thin wrappers around haven::as_factor(), so
# the tests mostly confirm the wiring and the end-to-end pipeline
# shape works.


test_that("rs_lab converts a haven_labelled column to a factor", {
  col <- haven::labelled(c(1L, 2L, 1L),
                         labels = c(Male = 1L, Female = 2L),
                         label  = "Sex")
  result <- rs_lab(col)
  expect_s3_class(result, "factor")
  expect_equal(as.character(result), c("Male", "Female", "Male"))
})

test_that("rs_lab on a data.frame converts haven_labelled columns to factors", {
  df <- data.frame(
    id  = 1:3,
    sex = haven::labelled(c(1L, 2L, 1L),
                          labels = c(Male = 1L, Female = 2L),
                          label  = "Sex"),
    stringsAsFactors = FALSE
  )
  result <- rs_lab(df)
  expect_s3_class(result$sex, "factor")
  expect_equal(as.character(result$sex), c("Male", "Female", "Male"))
  # Non-labelled columns unchanged
  expect_equal(result$id, 1:3)
})

test_that("rs_lab_head returns the first n rows labelled", {
  df <- data.frame(
    id  = 1:10,
    sex = haven::labelled(rep(c(1L, 2L), 5L),
                          labels = c(Male = 1L, Female = 2L),
                          label  = "Sex"),
    stringsAsFactors = FALSE
  )
  result <- rs_lab_head(df, n = 3L)
  expect_equal(nrow(result), 3L)
  expect_s3_class(result$sex, "factor")
  expect_equal(as.character(result$sex), c("Male", "Female", "Male"))
})

test_that("rs_lab end-to-end pipeline after autolabel against v3 bundle", {
  skip_without_withr()
  parent <- withr::local_tempdir()
  make_v3_bundle_scb_eng(parent)
  withr::local_envvar(REGISTREAM_DIR = parent)

  cfg <- registream::config_defaults()
  cfg$usage_logging       <- FALSE
  cfg$internet_access     <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, parent)

  df <- data.frame(sex = c(1L, 2L, 1L))
  labelled  <- autolabel(df, scope = c("LISA", "Individer"),
                         release = "2021", directory = parent)
  displayed <- rs_lab(labelled)
  expect_s3_class(displayed$sex, "factor")
  expect_equal(as.character(displayed$sex), c("Male", "Female", "Male"))
})
