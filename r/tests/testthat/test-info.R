# info(): config + cache snapshot

test_that("info() prints a config snapshot", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- registream::config_defaults()
  cfg$usage_logging     <- TRUE
  cfg$telemetry_enabled <- FALSE
  registream::config_save(cfg, tmp)

  out <- utils::capture.output(res <- info(directory = tmp))
  expect_true(any(grepl("autolabel configuration", out)))
  expect_true(any(grepl("autolabel_version", out)))
  expect_true(any(grepl("registream_dir", out)))
  expect_true(is.list(res))
  expect_false(is.null(res$autolabel_version))
})
