# suggest(): coverage + primary + pin_command.

test_that("suggest() returns rs_suggest_result with coverage", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)

  cfg <- registream::config_defaults()
  cfg$usage_logging   <- FALSE
  cfg$internet_access <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, tmp)

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   kon = c("1", "2", "1"),
                   stringsAsFactors = FALSE)

  out <- suggest(df, domain = "scb", lang = "eng",
                           directory = tmp)
  expect_s3_class(out, "rs_suggest_result")
  expect_s3_class(out$primary, "rs_scope_inference")
  expect_identical(out$primary$levels, c("LISA", "Individer"))
  expect_identical(out$primary$matches, 3L)

  expect_true(nrow(out$coverage) >= 1L)
  expect_true("matches" %in% colnames(out$coverage))
  expect_true("coverage_pct" %in% colnames(out$coverage))
  expect_true("is_primary" %in% colnames(out$coverage))

  primary_row <- out$coverage[out$coverage$is_primary, , drop = FALSE]
  expect_identical(nrow(primary_row), 1L)
  expect_identical(primary_row$scope_level_1, "LISA")
  expect_identical(primary_row$scope_level_2, "Individer")
})


test_that("suggest() pin_command reproduces the inferred pin", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)

  cfg <- registream::config_defaults()
  cfg$usage_logging   <- FALSE
  cfg$internet_access <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, tmp)

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   kon = c("1", "2", "1"),
                   stringsAsFactors = FALSE)

  out <- suggest(df, domain = "scb", lang = "eng",
                           directory = tmp)
  expect_match(out$pin_command,
               "scope = c\\('LISA', 'Individer'\\)")
})


test_that("suggest() returns NULL primary on mixed-panel data", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)

  cfg <- registream::config_defaults()
  cfg$usage_logging   <- FALSE
  cfg$internet_access <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, tmp)

  # 20 user columns, 1 match → 5% < 10% threshold
  datavars <- c("age", sprintf("zzz%02d", seq_len(19)))
  df <- as.data.frame(
    stats::setNames(replicate(length(datavars), 1:3, simplify = FALSE),
                    datavars)
  )

  out <- suggest(df, domain = "scb", lang = "eng",
                           directory = tmp)
  # match_pct=5% < threshold → has_strong_primary = FALSE → primary=NULL in suggest
  # Actually inferred is still returned; has_strong_primary determines is_primary in table
  expect_false(isTRUE(out$primary$has_strong_primary))
  expect_false(any(out$coverage$is_primary))
})


test_that("suggest() accepts positional scope tokens via `...`", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  make_v3_bundle_scb_eng(tmp)

  cfg <- registream::config_defaults()
  cfg$usage_logging   <- FALSE
  cfg$internet_access <- FALSE
  cfg$first_run_completed <- TRUE
  registream::config_save(cfg, tmp)

  df <- data.frame(age = 1:3, sex = c("1", "2", "1"),
                   kon = c("1", "2", "1"),
                   stringsAsFactors = FALSE)

  out <- suggest(df, "LISA", "Individer", directory = tmp)
  expect_s3_class(out, "rs_suggest_result")
  # Explicit scope pins the coverage calc to that atom.
  expect_true(any(out$coverage$scope_level_1 == "LISA" &
                  out$coverage$scope_level_2 == "Individer"))
})
