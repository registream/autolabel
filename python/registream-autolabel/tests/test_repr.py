"""Unit tests for registream.autolabel._repr."""

from __future__ import annotations

import pandas as pd
import pytest

from registream.autolabel._labels import ATTRS_KEY
from registream.autolabel._repr import LabeledView


# ─── Fixtures ────────────────────────────────────────────────────────────────


def _df_with_labels() -> pd.DataFrame:
    """Build a DataFrame with both numeric and string-coded value labels."""
    df = pd.DataFrame(
        {
            "id": [1, 2, 3, 4],
            "sex": [1, 2, 1, 2],
            "color": ["R", "G", "B", "R"],
        }
    )
    df.attrs[ATTRS_KEY] = {
        "variable_labels": {"sex": "Biological sex", "color": "Favorite color"},
        "value_labels": {
            "sex": {1: "Male", 2: "Female"},
            "color": {"R": "Red", "G": "Green", "B": "Blue"},
        },
    }
    return df


def _df_no_attrs() -> pd.DataFrame:
    return pd.DataFrame({"x": [1, 2, 3], "y": [10, 20, 30]})


# ─── Construction ────────────────────────────────────────────────────────────


def test_labeled_view_construction() -> None:
    df = _df_with_labels()
    view = LabeledView(df)
    assert view._df is df


# ─── Substitution: happy path ────────────────────────────────────────────────


def test_labeled_view_substitutes_numeric_codes() -> None:
    df = _df_with_labels()
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert list(labeled["sex"]) == ["Male", "Female", "Male", "Female"]


def test_labeled_view_substitutes_string_codes() -> None:
    """Mixed string codes (e.g., 'R'/'G'/'B') also substitute correctly."""
    df = _df_with_labels()
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert list(labeled["color"]) == ["Red", "Green", "Blue", "Red"]


def test_labeled_view_unlabeled_columns_unchanged() -> None:
    """Columns without value labels (e.g., `id`) should pass through unchanged."""
    df = _df_with_labels()
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert list(labeled["id"]) == [1, 2, 3, 4]


def test_labeled_view_unmapped_codes_preserved() -> None:
    """Codes not in the label dict are kept as-is (sentinel/missing protection)."""
    df = pd.DataFrame({"sex": [1, 2, 99]})
    df.attrs[ATTRS_KEY] = {
        "variable_labels": {},
        "value_labels": {"sex": {1: "Male", 2: "Female"}},
    }
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert labeled["sex"].iloc[0] == "Male"
    assert labeled["sex"].iloc[1] == "Female"
    assert labeled["sex"].iloc[2] == 99


# ─── Non-mutation invariant ──────────────────────────────────────────────────


def test_labeled_view_does_not_mutate_underlying_data() -> None:
    """The whole point of LabeledView: original df is unchanged after display."""
    df = _df_with_labels()
    view = LabeledView(df)

    _ = view.as_dataframe()
    _ = repr(view)
    _ = view._repr_html_()

    # Original column data is unchanged
    assert list(df["sex"]) == [1, 2, 1, 2]
    assert list(df["color"]) == ["R", "G", "B", "R"]


def test_labeled_view_does_not_mutate_attrs() -> None:
    """The wrapped df.attrs should not be modified by display operations."""
    df = _df_with_labels()
    original_value_labels = dict(df.attrs[ATTRS_KEY]["value_labels"])
    view = LabeledView(df)

    _ = view.as_dataframe()

    assert df.attrs[ATTRS_KEY]["value_labels"] == original_value_labels


def test_labeled_view_returned_dataframe_is_a_copy() -> None:
    """as_dataframe() returns a fresh copy, not a reference to the underlying df."""
    df = _df_with_labels()
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert labeled is not df


# ─── No-attrs / no-value-labels paths ────────────────────────────────────────


def test_labeled_view_no_attrs_returns_copy() -> None:
    """A DataFrame with no registream attrs returns a copy unchanged."""
    df = _df_no_attrs()
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert list(labeled["x"]) == [1, 2, 3]
    assert labeled is not df


def test_labeled_view_empty_value_labels_returns_copy() -> None:
    """A DataFrame with empty value_labels returns a copy unchanged."""
    df = pd.DataFrame({"x": [1, 2]})
    df.attrs[ATTRS_KEY] = {"variable_labels": {"x": "Label"}, "value_labels": {}}
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert list(labeled["x"]) == [1, 2]


def test_labeled_view_value_label_for_missing_column_skipped() -> None:
    """If value_labels has an entry for a column not in df, skip it gracefully."""
    df = pd.DataFrame({"x": [1, 2]})
    df.attrs[ATTRS_KEY] = {
        "variable_labels": {},
        "value_labels": {"nonexistent_column": {1: "A"}},
    }
    view = LabeledView(df)
    labeled = view.as_dataframe()
    assert list(labeled["x"]) == [1, 2]


# ─── head / tail / sample ────────────────────────────────────────────────────


def test_labeled_view_head_returns_labeled_view() -> None:
    df = _df_with_labels()
    view = LabeledView(df).head(2)
    assert isinstance(view, LabeledView)
    assert len(view) == 2


def test_labeled_view_head_substitutes_displayed_rows() -> None:
    df = _df_with_labels()
    head_view = LabeledView(df).head(2)
    labeled = head_view.as_dataframe()
    assert list(labeled["sex"]) == ["Male", "Female"]


def test_labeled_view_tail_returns_labeled_view() -> None:
    df = _df_with_labels()
    view = LabeledView(df).tail(2)
    assert isinstance(view, LabeledView)
    assert len(view) == 2


def test_labeled_view_tail_substitutes_displayed_rows() -> None:
    df = _df_with_labels()
    tail_view = LabeledView(df).tail(2)
    labeled = tail_view.as_dataframe()
    assert list(labeled["sex"]) == ["Male", "Female"]  # rows 2 and 3


def test_labeled_view_sample_returns_labeled_view() -> None:
    df = _df_with_labels()
    view = LabeledView(df).sample(2, random_state=42)
    assert isinstance(view, LabeledView)
    assert len(view) == 2


def test_labeled_view_sample_substitutes_codes() -> None:
    df = _df_with_labels()
    view = LabeledView(df).sample(4, random_state=42)
    labeled = view.as_dataframe()
    assert all(v in {"Male", "Female"} for v in labeled["sex"])


# ─── Display hooks: repr and _repr_html_ ─────────────────────────────────────


def test_labeled_view_repr_includes_labels() -> None:
    df = _df_with_labels()
    view = LabeledView(df).head(2)
    text = repr(view)
    assert "Male" in text
    assert "Female" in text


def test_labeled_view_repr_html_returns_string() -> None:
    df = _df_with_labels()
    view = LabeledView(df).head(2)
    html = view._repr_html_()
    assert isinstance(html, str)
    assert html  # non-empty


def test_labeled_view_repr_html_includes_labels() -> None:
    df = _df_with_labels()
    view = LabeledView(df).head(4)
    html = view._repr_html_()
    assert "Male" in html
    assert "Female" in html


def test_labeled_view_repr_no_attrs_falls_back() -> None:
    """A DataFrame with no labels still has a sane repr."""
    df = _df_no_attrs()
    view = LabeledView(df)
    text = repr(view)
    assert text  # non-empty


# ─── shape / len / columns ───────────────────────────────────────────────────


def test_labeled_view_shape() -> None:
    df = _df_with_labels()
    view = LabeledView(df)
    assert view.shape == (4, 3)


def test_labeled_view_len() -> None:
    df = _df_with_labels()
    view = LabeledView(df)
    assert len(view) == 4


def test_labeled_view_columns() -> None:
    df = _df_with_labels()
    view = LabeledView(df)
    assert list(view.columns) == ["id", "sex", "color"]


# ─── Chaining with pandas via as_dataframe() ─────────────────────────────────


def test_labeled_view_chains_with_pandas_query() -> None:
    """as_dataframe() output supports normal pandas chaining."""
    df = _df_with_labels()
    view = LabeledView(df)
    filtered = view.as_dataframe().query("sex == 'Male'")
    assert len(filtered) == 2


def test_labeled_view_round_trip_csv() -> None:
    """Sanity check: as_dataframe() → CSV → DataFrame round-trip works."""
    import io

    df = _df_with_labels()
    view = LabeledView(df)
    buf = io.StringIO()
    view.as_dataframe().to_csv(buf, index=False)
    buf.seek(0)
    reloaded = pd.read_csv(buf)
    assert "Male" in set(reloaded["sex"])
    assert "Female" in set(reloaded["sex"])
