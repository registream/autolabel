"""Unit tests for ``registream.autolabel._lookup``."""

from __future__ import annotations

import pandas as pd

from registream.autolabel._filters import filter_bundle
from registream.autolabel._lookup import LookupResult, lookup
from registream.metadata import load_bundle


def _load(fixture) -> tuple:
    bundle = load_bundle(fixture.domain, fixture.lang, directory=fixture.directory)
    return bundle, filter_bundle(bundle)


def test_lookup_returns_lookup_result(scb_depth2_bundle) -> None:
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup("kon", bundle, filtered)
    assert isinstance(result, LookupResult)


def test_lookup_single_variable_name(scb_depth2_bundle) -> None:
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup("kon", bundle, filtered)
    assert len(result.df) == 1
    assert result.df.iloc[0]["variable_name"] == "kon"


def test_lookup_detail_returns_all_rows(scb_depth2_bundle) -> None:
    """``detail=True`` expands the FK chain: every (variable × scope × release) row."""
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup("kon", bundle, filtered, detail=True)
    # "kon" appears in LISA with 3 releases (42,42,42) and in STATIV with 1 (44).
    assert len(result.df) == 4
    assert set(result.df["release"].astype(str)) == {"2005", "2006", "2007"}


def test_lookup_missing_variables_tracked(scb_depth2_bundle) -> None:
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup(["kon", "nonexistent"], bundle, filtered)
    assert "nonexistent" in result.missing
    assert "kon" not in result.missing


def test_lookup_case_insensitive(scb_depth2_bundle) -> None:
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup("KON", bundle, filtered)
    assert not result.df.empty


def test_lookup_scope_counts_set(scb_depth2_bundle) -> None:
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup("kon", bundle, filtered)
    # "kon" appears in LISA and STATIV → 2 distinct scope tuples.
    assert result.scope_counts.get("kon") == 2


def test_lookup_parsed_value_labels(scb_depth2_bundle) -> None:
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup("kon", bundle, filtered)
    row = result.df.iloc[0]
    assert row["value_labels"] == {1: "Man", 2: "Woman"}


def test_lookup_with_scope_filter_narrows(scb_depth2_bundle) -> None:
    bundle = load_bundle(
        scb_depth2_bundle.domain, scb_depth2_bundle.lang, directory=scb_depth2_bundle.directory
    )
    filtered = filter_bundle(bundle, scope=["STATIV"])
    result = lookup("kon", bundle, filtered)
    assert result.df.iloc[0]["variable_label"] == "Gender (STATIV)"


def test_lookup_empty_metadata_returns_all_missing(scb_depth2_bundle) -> None:
    bundle = load_bundle(
        scb_depth2_bundle.domain, scb_depth2_bundle.lang, directory=scb_depth2_bundle.directory
    )
    # Force-filter to a scope with no overlap with the requested var.
    empty_filtered = filter_bundle(bundle, scope=["STATIV"])
    result = lookup("kommun", bundle, empty_filtered)
    assert result.missing == ["kommun"]


def test_lookup_result_is_list_not_set(scb_depth2_bundle) -> None:
    bundle, filtered = _load(scb_depth2_bundle)
    result = lookup(["missing_a", "missing_b"], bundle, filtered)
    assert isinstance(result.missing, list)
