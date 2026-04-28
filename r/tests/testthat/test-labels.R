# Unit tests for apply_variable_labels / apply_value_labels / apply_labels.
#
# These hit the internal functions directly with synthetic in-memory
# metadata data.frames; no cache I/O, no haven I/O. The end-to-end
# autolabel.data.frame() path is covered by test-autolabel-smoke.R.

apply_variable_labels <- getFromNamespace("apply_variable_labels", "autolabel")
apply_value_labels    <- getFromNamespace("apply_value_labels",    "autolabel")
apply_labels          <- getFromNamespace("apply_labels",          "autolabel")


# ── synthetic metadata builders ──────────────────────────────────────────────

v1_var_metadata <- function() {
  data.frame(
    variable_name       = c("age", "sex", "income"),
    variable_label      = c("Age in years", "Biological sex", "Annual income"),
    variable_definition = c("Age", "Sex", "Income"),
    variable_unit       = c("years", "", "SEK"),
    variable_type       = c("continuous", "categorical", "continuous"),
    value_label_id      = c("", "sex_lbl", ""),
    stringsAsFactors    = FALSE
  )
}

v1_val_metadata <- function() {
  data.frame(
    value_label_id     = c("sex_lbl", "color_lbl"),
    variable_name      = c("sex", "color"),
    value_labels_stata = c('"1" "Male" "2" "Female"',
                           '"R" "Red" "G" "Green" "B" "Blue"'),
    stringsAsFactors   = FALSE
  )
}

v1_var_metadata_with_color <- function() {
  rbind(
    v1_var_metadata(),
    data.frame(
      variable_name       = "color",
      variable_label      = "Favorite color",
      variable_definition = "Color",
      variable_unit       = "",
      variable_type       = "categorical",
      value_label_id      = "color_lbl",
      stringsAsFactors    = FALSE
    )
  )
}

# Helper: read the variable-label attribute with EXACT matching. Base
# R's `attr()` does partial matching by default, which silently returns
# the `labels` (plural, i.e. value labels) attribute when you ask for
# `label`. That's a footgun for haven_labelled columns; tests must use
# exact matching.
get_label <- function(x) attr(x, "label", exact = TRUE)


# ── apply_variable_labels ────────────────────────────────────────────────────

test_that("apply_variable_labels writes label attributes on matching columns", {
  df <- data.frame(age = c(30, 40), sex = c(1L, 2L), income = c(100, 200))
  res <- apply_variable_labels(df, v1_var_metadata())

  expect_equal(res$n, 3L)
  expect_equal(get_label(res$df$age), "Age in years (years)")
  expect_equal(get_label(res$df$sex), "Biological sex")
  expect_equal(get_label(res$df$income), "Annual income (SEK)")
})

test_that("apply_variable_labels skips empty unit suffix", {
  df <- data.frame(sex = c(1L, 2L))
  res <- apply_variable_labels(df, v1_var_metadata())
  expect_equal(get_label(res$df$sex), "Biological sex")
})

test_that("apply_variable_labels is case-insensitive on column names", {
  df <- data.frame(Age = c(30, 40), SEX = c(1L, 2L))
  res <- apply_variable_labels(df, v1_var_metadata())
  expect_equal(res$n, 2L)
  expect_equal(get_label(res$df$Age), "Age in years (years)")
  expect_equal(get_label(res$df$SEX), "Biological sex")
})

test_that("apply_variable_labels honors the variables= filter", {
  df <- data.frame(age = c(30, 40), sex = c(1L, 2L), income = c(100, 200))
  res <- apply_variable_labels(df, v1_var_metadata(), variables = c("age"))
  expect_equal(res$n, 1L)
  expect_equal(get_label(res$df$age), "Age in years (years)")
  expect_null(get_label(res$df$sex))
})

test_that("apply_variable_labels include_unit = FALSE strips unit suffix", {
  df <- data.frame(age = c(30, 40))
  res <- apply_variable_labels(df, v1_var_metadata(), include_unit = FALSE)
  expect_equal(get_label(res$df$age), "Age in years")
})

test_that("apply_variable_labels returns 0 for empty df_vars intersection", {
  df <- data.frame(unknown = c(1, 2))
  res <- apply_variable_labels(df, v1_var_metadata())
  expect_equal(res$n, 0L)
})


# ── apply_value_labels ───────────────────────────────────────────────────────

test_that("apply_value_labels attaches haven_labelled to integer column", {
  df <- data.frame(sex = c(1L, 2L, 1L))
  res <- apply_value_labels(df, v1_var_metadata(), v1_val_metadata())

  expect_equal(res$n, 1L)
  expect_s3_class(res$df$sex, "haven_labelled")
  expect_identical(attr(res$df$sex, "labels"),
                   c(Male = 1L, Female = 2L))
  # underlying data is unchanged
  expect_identical(as.integer(res$df$sex), c(1L, 2L, 1L))
})

test_that("apply_value_labels coerces integer labels to double for double cols", {
  df <- data.frame(sex = c(1, 2, 1))  # double, not integer
  res <- apply_value_labels(df, v1_var_metadata(), v1_val_metadata())

  expect_equal(res$n, 1L)
  expect_s3_class(res$df$sex, "haven_labelled")
  expect_identical(typeof(attr(res$df$sex, "labels")), "double")
  expect_equal(unname(attr(res$df$sex, "labels")), c(1, 2))
  expect_equal(names(attr(res$df$sex, "labels")), c("Male", "Female"))
})

test_that("apply_value_labels handles character codes on character column", {
  df <- data.frame(color = c("R", "G", "B"), stringsAsFactors = FALSE)
  res <- apply_value_labels(df,
                            v1_var_metadata_with_color(),
                            v1_val_metadata())

  expect_equal(res$n, 1L)
  expect_s3_class(res$df$color, "haven_labelled")
  expect_identical(attr(res$df$color, "labels"),
                   c(Red = "R", Green = "G", Blue = "B"))
})

test_that("apply_value_labels skips when no value_label_id matches", {
  df <- data.frame(age = c(30, 40))
  res <- apply_value_labels(df, v1_var_metadata(), v1_val_metadata())
  expect_equal(res$n, 0L)
  expect_false(inherits(res$df$age, "haven_labelled"))
})

test_that("apply_value_labels preserves an existing variable label", {
  df <- data.frame(sex = structure(c(1L, 2L), label = "Biological sex"))
  res <- apply_value_labels(df, v1_var_metadata(), v1_val_metadata())
  expect_equal(get_label(res$df$sex), "Biological sex")
  expect_identical(attr(res$df$sex, "labels"), c(Male = 1L, Female = 2L))
})


# ── apply_labels orchestrator ────────────────────────────────────────────────

test_that("apply_labels with both label_type writes variable + value labels", {
  df <- data.frame(age = c(30, 40), sex = c(1L, 2L))
  res <- apply_labels(df, v1_var_metadata(), v1_val_metadata(), label_type = "both")

  expect_equal(res$n_variables, 2L)
  expect_equal(res$n_values,    1L)
  expect_equal(get_label(res$df$age), "Age in years (years)")
  expect_s3_class(res$df$sex, "haven_labelled")
})

test_that("apply_labels label_type='variables' does not write value labels", {
  df <- data.frame(sex = c(1L, 2L))
  res <- apply_labels(df, v1_var_metadata(), v1_val_metadata(),
                      label_type = "variables")
  expect_equal(res$n_values, 0L)
  expect_false(inherits(res$df$sex, "haven_labelled"))
  expect_equal(get_label(res$df$sex), "Biological sex")
})

test_that("apply_labels label_type='values' does not write variable labels", {
  df <- data.frame(sex = c(1L, 2L))
  res <- apply_labels(df, v1_var_metadata(), v1_val_metadata(),
                      label_type = "values")
  expect_equal(res$n_variables, 0L)
  expect_null(get_label(res$df$sex))
  expect_s3_class(res$df$sex, "haven_labelled")
})

test_that("apply_labels with NULL val_metadata silently skips value labels", {
  df <- data.frame(sex = c(1L, 2L))
  res <- apply_labels(df, v1_var_metadata(), val_metadata = NULL,
                      label_type = "both")
  expect_equal(res$n_variables, 1L)
  expect_equal(res$n_values, 0L)
})
