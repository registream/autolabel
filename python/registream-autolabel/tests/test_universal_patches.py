"""Tests for the universal pandas monkey-patch layer.

Covers:

- Label preservation on ``df['new'] = df['old']`` (``__setitem__`` patch).
- Label remapping on ``df.rename(columns={...})`` including ``inplace=True``.
- ``df.set_variable_labels`` / ``df.set_value_labels`` / ``df.copy_labels``
  as direct ``pd.DataFrame`` shortcuts.
- ``df.meta_search`` regex over column names + labels + value labels.
- ``df.rs.lab.kon`` returns a labeled Series.
- ``df.rs.lab[["kon", "age"]]`` returns a labeled sub-DataFrame.
- ``df.rs.lab.describe()`` returns a DataFrame with human-readable columns.
"""

from __future__ import annotations

import pandas as pd
import pytest

import registream.autolabel  # noqa: F401  # registers shortcuts + patches
from registream.autolabel._labels import ATTRS_KEY


@pytest.fixture
def labeled_df() -> pd.DataFrame:
    df = pd.DataFrame(
        {
            "kon": [1, 2, 1, 2, 1],
            "age": [30, 40, 50, 60, 70],
            "income": [100.0, 200.0, 150.0, 300.0, 250.0],
        }
    )
    df.set_variable_labels(  # type: ignore[attr-defined]
        {"kon": "Sex", "age": "Age in years", "income": "Annual income"}
    )
    df.set_value_labels("kon", {1: "Man", 2: "Woman"})  # type: ignore[attr-defined]
    return df


# ─── __setitem__ label inheritance ─────────────────────────────────────────────


def test_setitem_propagates_variable_and_value_labels(labeled_df: pd.DataFrame) -> None:
    labeled_df["kon_copy"] = labeled_df["kon"]
    assert labeled_df.variable_labels()["kon_copy"] == "Sex"  # type: ignore[attr-defined]
    assert labeled_df.value_labels()["kon_copy"] == {1: "Man", 2: "Woman"}  # type: ignore[attr-defined]


def test_setitem_with_list_does_not_error() -> None:
    """Plain list RHS must not trigger the label-propagation path."""
    df = pd.DataFrame({"a": [1, 2, 3]})
    df["b"] = [10, 20, 30]
    assert list(df["b"]) == [10, 20, 30]


def test_setitem_on_unlabeled_dataframe_is_pass_through() -> None:
    """Unlabeled DataFrames see zero behavior change from the patch."""
    df = pd.DataFrame({"a": [1, 2]})
    df["a2"] = df["a"]
    assert ATTRS_KEY not in df.attrs
    assert list(df["a2"]) == [1, 2]


def test_setitem_with_same_named_arithmetic_inherits_label() -> None:
    """Same-name arithmetic (pandas preserves ``name``) inherits the label.

    This matches the old-package behavior: a derived column from a
    single source gets that source's label as a sensible default. The
    user can override with ``set_variable_labels`` afterwards.
    """
    df = pd.DataFrame({"a": [1, 2, 3]})
    df.set_variable_labels("a", "Label A")  # type: ignore[attr-defined]
    df["b"] = df["a"] + df["a"]
    assert df.variable_labels()["b"] == "Label A"  # type: ignore[attr-defined]


def test_setitem_with_mixed_arithmetic_does_not_propagate() -> None:
    """Cross-column arithmetic drops ``name``, so no label is carried."""
    df = pd.DataFrame({"a": [1, 2, 3], "b": [10, 20, 30]})
    df.set_variable_labels({"a": "Alpha", "b": "Beta"})  # type: ignore[attr-defined]
    df["c"] = df["a"] + df["b"]
    # pandas sets name=None on differently-named Series arithmetic.
    assert "c" not in df.variable_labels()  # type: ignore[attr-defined]


# ─── rename label remapping ────────────────────────────────────────────────────


def test_rename_with_dict_remaps_variable_labels(labeled_df: pd.DataFrame) -> None:
    renamed = labeled_df.rename(columns={"kon": "gender"})
    assert renamed.variable_labels() == {  # type: ignore[attr-defined]
        "gender": "Sex",
        "age": "Age in years",
        "income": "Annual income",
    }


def test_rename_with_dict_remaps_value_labels(labeled_df: pd.DataFrame) -> None:
    renamed = labeled_df.rename(columns={"kon": "gender"})
    assert renamed.value_labels() == {"gender": {1: "Man", 2: "Woman"}}  # type: ignore[attr-defined]


def test_rename_inplace_preserves_labels_on_self(labeled_df: pd.DataFrame) -> None:
    labeled_df.rename(columns={"kon": "gender"}, inplace=True)
    assert "gender" in labeled_df.variable_labels()  # type: ignore[attr-defined]
    assert "kon" not in labeled_df.variable_labels()  # type: ignore[attr-defined]


def test_rename_without_dict_preserves_existing_labels(
    labeled_df: pd.DataFrame,
) -> None:
    """Callable renamer keeps the label dict intact (no remap)."""
    renamed = labeled_df.rename(columns=str.upper)
    assert renamed.variable_labels()["kon"] == "Sex"  # type: ignore[attr-defined]


def test_rename_on_unlabeled_is_pass_through() -> None:
    df = pd.DataFrame({"a": [1]})
    r = df.rename(columns={"a": "b"})
    assert list(r.columns) == ["b"]
    assert ATTRS_KEY not in r.attrs


# ─── set_* and copy_labels shortcuts ───────────────────────────────────────────


def test_set_variable_labels_dict_form() -> None:
    df = pd.DataFrame({"a": [1], "b": [2]})
    df.set_variable_labels({"a": "Alpha", "b": "Beta"})  # type: ignore[attr-defined]
    assert df.variable_labels() == {"a": "Alpha", "b": "Beta"}  # type: ignore[attr-defined]


def test_set_variable_labels_callable_transforms_existing() -> None:
    df = pd.DataFrame({"a": [1]})
    df.set_variable_labels("a", "Alpha")  # type: ignore[attr-defined]
    df.set_variable_labels("a", lambda old: (old or "").upper())  # type: ignore[attr-defined]
    assert df.variable_labels()["a"] == "ALPHA"  # type: ignore[attr-defined]


def test_set_value_labels_merges_by_default() -> None:
    df = pd.DataFrame({"kon": [1, 2]})
    df.set_value_labels("kon", {1: "Man"})  # type: ignore[attr-defined]
    df.set_value_labels("kon", {2: "Woman"})  # type: ignore[attr-defined]
    assert df.value_labels()["kon"] == {1: "Man", 2: "Woman"}  # type: ignore[attr-defined]


def test_set_value_labels_overwrite_replaces() -> None:
    df = pd.DataFrame({"kon": [1, 2]})
    df.set_value_labels("kon", {1: "Man", 2: "Woman"})  # type: ignore[attr-defined]
    df.set_value_labels("kon", {9: "Unknown"}, overwrite=True)  # type: ignore[attr-defined]
    assert df.value_labels()["kon"] == {9: "Unknown"}  # type: ignore[attr-defined]


def test_copy_labels_duplicates_bundle(labeled_df: pd.DataFrame) -> None:
    labeled_df.copy_labels("kon", "sex_clone")  # type: ignore[attr-defined]
    assert labeled_df.variable_labels()["sex_clone"] == "Sex"  # type: ignore[attr-defined]
    assert labeled_df.value_labels()["sex_clone"] == {1: "Man", 2: "Woman"}  # type: ignore[attr-defined]


# ─── meta_search ───────────────────────────────────────────────────────────────


def test_meta_search_matches_column_and_label(labeled_df: pd.DataFrame) -> None:
    hits = labeled_df.meta_search("income")  # type: ignore[attr-defined]
    assert "income" in set(hits["variable"])
    # "income" appears in both the column name ("income") and the
    # variable label ("Annual income") → matched_in lists both.
    matched_in = hits.loc[hits["variable"] == "income", "matched_in"].iloc[0]
    assert "name" in matched_in
    assert "label" in matched_in


def test_meta_search_matches_label_text(labeled_df: pd.DataFrame) -> None:
    hits = labeled_df.meta_search("sex")  # type: ignore[attr-defined]
    assert set(hits["variable"]) == {"kon"}


def test_meta_search_includes_value_labels(labeled_df: pd.DataFrame) -> None:
    hits = labeled_df.meta_search("woman", include_values=True)  # type: ignore[attr-defined]
    row = hits[hits["variable"] == "kon"].iloc[0]
    assert "values" in row["matched_in"]
    assert "Woman" in row["value_matches"]


def test_meta_search_empty_when_no_match(labeled_df: pd.DataFrame) -> None:
    hits = labeled_df.meta_search("__nothing__")  # type: ignore[attr-defined]
    assert hits.empty


# ─── LabeledView labeled column access ─────────────────────────────────────────


def test_lab_column_access_returns_labeled_series(labeled_df: pd.DataFrame) -> None:
    s = labeled_df.rs.lab["kon"]
    assert s.name == "Sex"
    assert list(s) == ["Man", "Woman", "Man", "Woman", "Man"]


def test_lab_dot_access_returns_labeled_series(labeled_df: pd.DataFrame) -> None:
    s = labeled_df.rs.lab.kon
    assert s.name == "Sex"


def test_lab_list_key_returns_labeled_subframe(labeled_df: pd.DataFrame) -> None:
    sub = labeled_df.rs.lab[["kon", "age"]]
    assert list(sub.columns) == ["Sex", "Age in years"]
    assert list(sub["Sex"]) == ["Man", "Woman", "Man", "Woman", "Man"]
    assert list(sub["Age in years"]) == [30, 40, 50, 60, 70]


def test_lab_describe_has_labeled_columns(labeled_df: pd.DataFrame) -> None:
    desc = labeled_df.rs.lab.describe()
    assert "Age in years" in desc.columns
    assert "Annual income" in desc.columns


def test_lab_to_csv_uses_labeled_columns(labeled_df: pd.DataFrame, tmp_path) -> None:
    target = tmp_path / "out.csv"
    labeled_df.rs.lab.to_csv(target, index=False)
    first_line = target.read_text(encoding="utf-8").splitlines()[0]
    assert "Age in years" in first_line
    assert "Annual income" in first_line


# ─── Plot wrapper on LabeledView ──────────────────────────────────────────────


def test_labeled_view_plot_uses_variable_labels_for_axis_titles(
    labeled_df: pd.DataFrame,
) -> None:
    matplotlib = pytest.importorskip("matplotlib")
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    ax = labeled_df.rs.lab.plot(kind="bar", x="age", y="income")
    try:
        assert ax.get_xlabel() == "Age in years"
        assert ax.get_ylabel() == "Annual income"
    finally:
        plt.close(ax.get_figure() if ax is not None else None)
