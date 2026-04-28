test_that("read_registry() on a missing file returns an empty canonical frame", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  df <- read_registry()
  expect_s3_class(df, "data.frame")
  expect_identical(nrow(df), 0L)
  expect_identical(colnames(df), REGISTRY_COLUMNS)
})


test_that("write_registry_entry() inserts a new row with all REGISTRY_COLUMNS", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  write_registry_entry(
    directory     = NULL,
    domain        = "scb",
    file_type     = "variables",
    lang          = "eng",
    version       = "20260309",
    schema        = "2.0",
    file_size_dta = 1234L,
    file_size_csv = 5678L
  )

  df <- read_registry()
  expect_identical(nrow(df), 1L)
  expect_identical(colnames(df), REGISTRY_COLUMNS)
  expect_identical(df$dataset_key[[1]], "scb_variables_eng")
  expect_identical(df$file_size_dta[[1]], "1234")
  expect_identical(df$file_size_csv[[1]], "5678")
  expect_identical(df$version[[1]], "20260309")
  expect_identical(df$schema[[1]], "2.0")
  expect_identical(df$source[[1]], "api")
  expect_identical(df$type[[1]], "variables")
})


test_that("write_registry_entry() maps file_type='values' to 'value_labels'", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  write_registry_entry(
    directory     = NULL,
    domain        = "scb",
    file_type     = "values",
    lang          = "eng",
    version       = "20260309",
    schema        = "2.0",
    file_size_dta = 100L,
    file_size_csv = 200L
  )

  df <- read_registry()
  expect_identical(df$dataset_key[[1]], "scb_value_labels_eng")
  expect_identical(df$type[[1]], "value_labels")
})


test_that("write_registry_entry() preserves last_checked on update", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  write_registry_entry(
    directory     = NULL,
    domain        = "scb",
    file_type     = "variables",
    lang          = "eng",
    version       = "20260309",
    schema        = "2.0",
    file_size_dta = 100L,
    file_size_csv = 200L
  )
  df1 <- read_registry()
  original_last_checked <- df1$last_checked[[1]]

  Sys.sleep(0.05)  # ensure stata_clock_now() advances
  write_registry_entry(
    directory     = NULL,
    domain        = "scb",
    file_type     = "variables",
    lang          = "eng",
    version       = "20260310",
    schema        = "2.0",
    file_size_dta = 300L,
    file_size_csv = 400L
  )

  df2 <- read_registry()
  expect_identical(nrow(df2), 1L)
  expect_identical(df2$version[[1]], "20260310")
  expect_identical(df2$file_size_dta[[1]], "300")
  # last_checked pinned to original; downloaded advanced
  expect_identical(df2$last_checked[[1]], original_last_checked)
  expect_false(identical(df2$downloaded[[1]], original_last_checked))
})


test_that("write_registry_entry() adds a second row for a different key", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  for (ft in c("variables", "values", "registers")) {
    write_registry_entry(
      directory     = NULL,
      domain        = "scb",
      file_type     = ft,
      lang          = "eng",
      version       = "20260309",
      schema        = "2.0",
      file_size_dta = 100L,
      file_size_csv = 200L
    )
  }

  df <- read_registry()
  expect_identical(nrow(df), 3L)
  expect_setequal(
    df$dataset_key,
    c("scb_variables_eng", "scb_value_labels_eng", "scb_registers_eng")
  )
})


test_that("REGISTRY_COLUMNS order is pinned for cross-client compat", {
  # If this test fails, the Stata + Python clients cannot read a
  # registry file written by the R client and vice versa. Only change
  # this order with a corresponding change in stata _al_store_meta
  # and python _datasets.REGISTRY_COLUMNS.
  expect_identical(
    REGISTRY_COLUMNS,
    c("dataset_key", "domain", "type", "lang", "version", "schema",
      "downloaded", "source", "file_size_dta", "file_size_csv",
      "last_checked")
  )
})
