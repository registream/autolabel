# rs_lab / rs_lab_head -- display helpers.
#
# The entire LabeledView substitute the runbook specifies. Python has
# a ~150-line `_repr.py` that implements a LabeledView wrapper class
# with its own `_repr_html_` for Jupyter notebooks, because pandas has
# no native concept of "display with labels applied without mutating
# the data". R has `haven::as_factor()` which does exactly that
# natively, and that's the entire replacement.
#
# `rs_lab(x)` returns a new object where value-labelled columns have
# become factors with level names from their `labels` attribute. The
# original `x` is untouched -- this is a display helper, not a mutator.
# The user pipes `df |> autolabel() |> rs_lab()` to see their labelled
# data in "pretty" form while keeping the underlying codes intact
# elsewhere.

#' @export
rs_lab <- function(x) {
  log_and_heartbeat("rs_lab")
  haven::as_factor(x)
}

#' @export
rs_lab_head <- function(x, n = 5L) {
  utils::head(haven::as_factor(x), n)
}
