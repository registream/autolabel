test_that("log_and_heartbeat() emits autolabel + core banner but not datamirror", {
  captured <- character(0)

  fake_result <- structure(
    list(
      update_available  = TRUE,
      latest_version    = "3.1.0",
      autolabel_update  = TRUE,
      autolabel_latest  = "3.0.1",
      datamirror_update = TRUE,
      datamirror_latest = "1.2.3",
      reason            = "success"
    ),
    class = "registream_heartbeat_result"
  )

  testthat::local_mocked_bindings(
    rs_first_run  = function(...) invisible(NULL),
    usage_log     = function(...) invisible(NULL),
    send_heartbeat = function(...) fake_result,
    .package = "registream"
  )

  msgs <- testthat::capture_messages(log_and_heartbeat("autolabel"))
  text <- paste(msgs, collapse = "\n")

  expect_match(text, "A new version of registream is available", fixed = TRUE)
  expect_match(text, "A new version of autolabel is available",  fixed = TRUE)
  expect_false(grepl("datamirror", text, fixed = TRUE))
})


test_that("log_and_heartbeat() is silent when no updates are reported", {
  fake_result <- structure(
    list(
      update_available  = FALSE,
      latest_version    = "",
      autolabel_update  = FALSE,
      autolabel_latest  = "",
      datamirror_update = FALSE,
      datamirror_latest = "",
      reason            = "success"
    ),
    class = "registream_heartbeat_result"
  )

  testthat::local_mocked_bindings(
    rs_first_run   = function(...) invisible(NULL),
    usage_log      = function(...) invisible(NULL),
    send_heartbeat = function(...) fake_result,
    .package = "registream"
  )

  msgs <- testthat::capture_messages(log_and_heartbeat("autolabel"))
  expect_length(msgs, 0)
})


test_that("log_and_heartbeat() swallows heartbeat errors silently", {
  testthat::local_mocked_bindings(
    rs_first_run   = function(...) invisible(NULL),
    usage_log      = function(...) invisible(NULL),
    send_heartbeat = function(...) stop("simulated network blowup"),
    .package = "registream"
  )

  expect_no_error(log_and_heartbeat("autolabel"))
  msgs <- testthat::capture_messages(log_and_heartbeat("autolabel"))
  expect_length(msgs, 0)
})
