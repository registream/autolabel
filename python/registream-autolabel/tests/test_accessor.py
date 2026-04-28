"""Unit tests for ``registream.autolabel._accessor`` (the ``RsAccessor`` class)."""

from __future__ import annotations

import pandas as pd
import pytest

import registream.autolabel  # noqa: F401  # registers the df.rs accessor
from registream.autolabel._lookup import LookupResult
from registream.autolabel._repr import LabeledView


def _df_for_dst() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "law_reference": ["§1", "§2", "§3"],
            "civil_rank": [1, 2, 1],
            "case_id": ["a", "b", "c"],
        }
    )


def _df_for_scb() -> pd.DataFrame:
    return pd.DataFrame({"kon": [1, 2, 1], "kommun": [101, 102, 103]})


# ── autolabel ─────────────────────────────────────────────────────────────────


def test_autolabel_applies_variable_and_value_labels(dst_depth1_bundle) -> None:
    df = _df_for_dst()
    df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    assert df.rs.variable_labels()["law_reference"] == "Law reference"
    assert df.rs.value_labels()["civil_rank"] == {1: "Junior", 2: "Senior"}


def test_autolabel_stamps_schema_version_and_scope(scb_depth2_bundle) -> None:
    df = _df_for_scb()
    df.rs.autolabel(
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    assert df.attrs["schema_version"] == "2.0"
    attrs = df.attrs["registream"]
    assert attrs["domain"] == "scb"
    assert attrs["lang"] == "eng"
    assert attrs["scope_depth"] == 2


def test_autolabel_infers_scope_from_columns(scb_depth2_bundle) -> None:
    """LISA wins when ``kon`` and ``kommun`` are both in the dataset."""
    df = _df_for_scb()
    df.rs.autolabel(
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    # "Gender" (LISA) wins over "Gender (STATIV)".
    assert df.rs.variable_labels()["kon"] == "Gender"


def test_autolabel_explicit_scope_filter(scb_depth2_bundle) -> None:
    df = _df_for_scb()
    df.rs.autolabel(
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        scope=["STATIV"],
        directory=scb_depth2_bundle.directory,
    )
    assert df.rs.variable_labels()["kon"] == "Gender (STATIV)"


def test_autolabel_overflow_token_becomes_release(scb_depth2_bundle) -> None:
    """Third token at depth=2 is promoted to ``release``."""
    df = _df_for_scb()
    df.rs.autolabel(
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        scope=["LISA", "Individuals aged 16 and older", "2005"],
        directory=scb_depth2_bundle.directory,
    )
    assert df.attrs["registream"]["release"] == "2005"


def test_autolabel_does_not_mutate_column_data(dst_depth1_bundle) -> None:
    df = _df_for_dst()
    original = df["civil_rank"].copy()
    df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    pd.testing.assert_series_equal(df["civil_rank"], original)


def test_autolabel_chaining_supports_query(dst_depth1_bundle) -> None:
    df = _df_for_dst()
    filtered = df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    ).query("civil_rank == 1")
    assert len(filtered) == 2


# ── lookup ────────────────────────────────────────────────────────────────────


def test_lookup_returns_lookup_result(scb_depth2_bundle) -> None:
    result = pd.DataFrame({"x": [1]}).rs.lookup(
        "kon",
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    assert isinstance(result, LookupResult)
    assert not result.df.empty
    assert result.missing == []


def test_lookup_detail_returns_all_rows(scb_depth2_bundle) -> None:
    result = pd.DataFrame({"x": [1]}).rs.lookup(
        "kon",
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        detail=True,
        directory=scb_depth2_bundle.directory,
    )
    assert len(result.df) >= 2


def test_lookup_without_variables_raises() -> None:
    with pytest.raises(ValueError):
        pd.DataFrame({"x": [1]}).rs.lookup(None, domain="scb", lang="eng")


# ── lab / accessors ───────────────────────────────────────────────────────────


def test_lab_returns_labeled_view(dst_depth1_bundle) -> None:
    df = _df_for_dst()
    df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    assert isinstance(df.rs.lab, LabeledView)


def test_variable_and_value_labels_are_copies(dst_depth1_bundle) -> None:
    df = _df_for_dst()
    df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    var = df.rs.variable_labels()
    var["mutation"] = "should not leak"
    assert "mutation" not in df.rs.variable_labels()


def test_two_dataframes_have_independent_state(dst_depth1_bundle) -> None:
    df_a = _df_for_dst()
    df_b = pd.DataFrame({"case_id": ["x"]})
    df_a.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    assert df_b.rs.variable_labels() == {}
    assert df_a.rs.variable_labels() != {}
