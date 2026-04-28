# Citation pulls from the generated _citation_data.R (single source of
# truth in registream/citations.yaml). Guard against hand-edits to the
# generated file by asserting a few known-good substrings.

test_that("cite() returns APA text with author + title + URL", {
  out <- cite(versioned = FALSE)
  expect_match(out, "Clark")
  expect_match(out, "Wen")
  expect_match(out, "autolabel:")
  expect_match(out, "https://registream.org/docs/autolabel", fixed = TRUE)
})


test_that("cite() includes the installed version by default", {
  out <- cite(versioned = TRUE)
  v <- as.character(utils::packageVersion("autolabel"))
  expect_match(out, sprintf("Version %s", v), fixed = TRUE)
})


test_that("cite_bibtex() returns a @software entry", {
  out <- cite_bibtex(versioned = TRUE)
  expect_match(out, "^@software")
  expect_match(out, "clark2024autolabel")
  expect_match(out, "version = \\{.*\\}")
})


