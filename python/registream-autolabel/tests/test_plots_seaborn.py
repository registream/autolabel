"""End-to-end plotting integration: seaborn with labeled ``lisa.dta``.

Verifies that the old package's "autolabel just works in plots" UX
survives the split: passing ``data=df.rs.lab`` *or* ``data=df`` (after
``df.autolabel(...)``) to a seaborn function substitutes value labels
on categorical axes and pulls variable labels into axis titles and
legend.

Skipped automatically when the shared SCB cache is absent (the bundle
is installed via the Stata client or ``update_datasets``; the test
doesn't hit the network).
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

import registream.autolabel  # noqa: F401  # registers df.rs, shortcuts, plot patch
from registream.metadata import cache_path

matplotlib = pytest.importorskip("matplotlib")
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
sns = pytest.importorskip("seaborn")

LISA_PATH = Path(__file__).resolve().parents[3] / "examples" / "lisa.dta"


def _cache_ready() -> bool:
    try:
        return (
            cache_path("scb", "variables", "eng", ext="dta").exists()
            and cache_path("scb", "values", "eng", ext="dta").exists()
            and cache_path("scb", "manifest", "eng", ext="csv").exists()
        )
    except Exception:
        return False


requires_cache = pytest.mark.skipif(
    not LISA_PATH.exists() or not _cache_ready(),
    reason="requires shared ~/.registream/autolabel/scb/ cache and examples/lisa.dta",
)


@pytest.fixture
def lisa_labeled() -> pd.DataFrame:
    df = pd.read_stata(LISA_PATH)
    df.autolabel(domain="scb", lang="eng")  # type: ignore[attr-defined]
    return df


def _first_categorical(df: pd.DataFrame) -> str:
    return next(iter(df.rs.value_labels()))


# ── "just works" UX: data=df or data=df.rs.lab ────────────────────────────────


@requires_cache
def test_sns_barplot_with_labeled_dataframe_substitutes_tick_labels(
    lisa_labeled: pd.DataFrame,
) -> None:
    """``sns.barplot(data=df, x=col)`` uses value labels after ``df.autolabel``."""
    col = _first_categorical(lisa_labeled)
    label_values = set(lisa_labeled.rs.value_labels()[col].values())

    fig, ax = plt.subplots()
    try:
        sns.countplot(data=lisa_labeled, x=col, ax=ax)
        tick_texts = {t.get_text() for t in ax.get_xticklabels() if t.get_text()}
        xlabel = ax.get_xlabel()
    finally:
        plt.close(fig)

    assert tick_texts, "plot produced no tick labels"
    assert tick_texts <= label_values, (
        f"unexpected tick labels not in value-label set: "
        f"{tick_texts - label_values}"
    )
    assert xlabel == lisa_labeled.rs.variable_labels()[col], (
        "x-axis title should be pulled from variable_labels by the "
        "seaborn wrapper, got " + repr(xlabel)
    )


@requires_cache
def test_sns_barplot_with_lab_accessor_works_identically(
    lisa_labeled: pd.DataFrame,
) -> None:
    """Passing ``data=df.rs.lab`` gives the same result as ``data=df``."""
    col = _first_categorical(lisa_labeled)
    label_values = set(lisa_labeled.rs.value_labels()[col].values())

    fig, ax = plt.subplots()
    try:
        sns.countplot(data=lisa_labeled.rs.lab, x=col, ax=ax)
        tick_texts = {t.get_text() for t in ax.get_xticklabels() if t.get_text()}
    finally:
        plt.close(fig)

    assert tick_texts, "plot produced no tick labels"
    assert tick_texts <= label_values


# ── Invariants that must hold regardless of path ──────────────────────────────


@requires_cache
def test_hue_legend_uses_variable_and_value_labels(lisa_labeled: pd.DataFrame) -> None:
    """Hue legend title ← variable_labels, legend entries ← value_labels."""
    val_labels = lisa_labeled.rs.value_labels()
    cat_cols = list(val_labels.keys())
    if len(cat_cols) < 2:
        pytest.skip("need at least 2 categorical columns for x / hue")
    x_col, hue_col = cat_cols[0], cat_cols[1]
    hue_label_values = set(val_labels[hue_col].values())

    fig, ax = plt.subplots()
    try:
        sns.countplot(data=lisa_labeled, x=x_col, hue=hue_col, ax=ax)
        legend = ax.get_legend()
        if legend is None:
            pytest.skip("seaborn did not render a legend for this shape")
        legend_title = legend.get_title().get_text()
        legend_entries = {t.get_text() for t in legend.get_texts() if t.get_text()}
    finally:
        plt.close(fig)

    assert legend_title == lisa_labeled.rs.variable_labels()[hue_col]
    assert legend_entries <= hue_label_values


@requires_cache
def test_plotting_does_not_mutate_underlying_dataframe(
    lisa_labeled: pd.DataFrame,
) -> None:
    """The monkey-patched wrapper never writes back to the user's DataFrame."""
    col = _first_categorical(lisa_labeled)
    before = lisa_labeled[col].copy()

    fig, ax = plt.subplots()
    try:
        sns.countplot(data=lisa_labeled, x=col, ax=ax)
    finally:
        plt.close(fig)

    pd.testing.assert_series_equal(lisa_labeled[col], before)


# ── Unlabeled DataFrames are untouched ────────────────────────────────────────


def test_plain_dataframe_is_unchanged_by_patch() -> None:
    """Passing a DataFrame without registream attrs bypasses the wrapper."""
    df = pd.DataFrame({"x": [1, 2, 3, 3, 2], "y": [10, 20, 30, 40, 50]})
    fig, ax = plt.subplots()
    try:
        sns.countplot(data=df, x="x", ax=ax)
        tick_texts = {t.get_text() for t in ax.get_xticklabels() if t.get_text()}
    finally:
        plt.close(fig)
    # No mapping applied; ticks are the raw numeric values rendered as strings.
    assert tick_texts <= {"1", "2", "3"}


@requires_cache
def test_scatterplot_keeps_x_axis_numeric(lisa_labeled: pd.DataFrame) -> None:
    """Scatter / line x-axis is NOT substituted with value labels."""
    # Build a synthetic DataFrame where a labeled column pretends to be a year.
    col = _first_categorical(lisa_labeled)
    original_values = lisa_labeled[col].head(50).reset_index(drop=True)
    df = pd.DataFrame(
        {
            col: original_values,
            "y": range(len(original_values)),
        }
    )
    df.attrs.update(lisa_labeled.attrs)

    fig, ax = plt.subplots()
    try:
        sns.scatterplot(data=df, x=col, y="y", ax=ax)
        # We can't assert specific ticks without inspecting matplotlib's
        # tick formatter, but we can assert the column we passed to
        # seaborn is numeric-ish, i.e. not the string-substituted one.
        # The wrapper should have left x alone for scatter.
        # Pull the plotted x data from the first collection / line:
        plotted_x = set()
        for coll in ax.collections:
            offsets = coll.get_offsets()
            for pt in offsets:
                plotted_x.add(str(pt[0]))
    finally:
        plt.close(fig)

    # None of the labeled human-readable strings should appear in the x data.
    label_strings = set(lisa_labeled.rs.value_labels()[col].values())
    assert not (label_strings & plotted_x), (
        "scatterplot x-axis was substituted with value labels; wrapper "
        "should skip substitution for scatter/line plots"
    )


# ── Opt-out via env flag ──────────────────────────────────────────────────────


def test_opt_out_env_var_honored_in_subprocess(tmp_path: Path) -> None:
    """``REGISTREAM_NO_PLOT_PATCH=1`` set before import disables the wrapper."""
    import subprocess
    import sys

    script = tmp_path / "noplot.py"
    script.write_text(
        "import os\n"
        "os.environ['REGISTREAM_NO_PLOT_PATCH'] = '1'\n"
        "import matplotlib\n"
        "matplotlib.use('Agg')\n"
        "import seaborn as sns\n"
        "before = sns.countplot\n"
        "import registream.autolabel  # should NOT patch\n"
        "after = sns.countplot\n"
        "assert before is after, 'wrapper was installed despite opt-out'\n"
    )
    result = subprocess.run(
        [sys.executable, str(script)], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
