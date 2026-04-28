"""Python parity for Stata ``stata/tests/dofiles/25_depth_agnostic.do``.

Verifies autolabel works for ``scope_depth == 1`` bundles (DST) using
the same code paths as ``scope_depth == 2`` (SCB). Covers the regression
from hardcoded ``scope_level_2`` references and the
apostrophe-insensitive match that came with the schema-v2 rewrite.
"""

from __future__ import annotations

import pandas as pd
import pytest

from registream.autolabel._collapse import collapse_to_one_per_variable
from registream.autolabel._filters import FilterError, filter_bundle
from registream.autolabel._lookup import lookup
from registream.autolabel._scope import scope as scope_browse
from registream.metadata import load_bundle


def test_depth1_bundle_loads(dst_depth1_bundle) -> None:
    """scope_depth=1 bundle loads, manifest parses, validation passes."""
    b = load_bundle(
        dst_depth1_bundle.domain, dst_depth1_bundle.lang, directory=dst_depth1_bundle.directory
    )
    assert b.manifest.scope_depth == 1
    assert b.manifest.level_names == ["register"]
    assert b.manifest.level_titles == ["Register"]
    assert b.scope is not None and b.release_sets is not None
    assert not b.core_only


def test_scope_browse_depth1(dst_depth1_bundle) -> None:
    """Empty scope at depth=1 returns level-1 values with variable counts."""
    df = scope_browse(
        dst_depth1_bundle.domain,
        dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    assert "scope_level_1" in df.columns
    assert "variable_count" in df.columns
    assert (df["variable_count"] > 0).any()


def test_scope_drill_to_releases_at_depth1(dst_depth1_bundle) -> None:
    """scope=[level1] at depth=1 lists releases for that atom."""
    df = scope_browse(
        dst_depth1_bundle.domain,
        dst_depth1_bundle.lang,
        scope=["Active civil servants in the state"],
        directory=dst_depth1_bundle.directory,
    )
    assert "release" in df.columns
    assert set(df["release"].astype(str)) == {"2020", "2021"}


def test_apostrophe_insensitive_match(dst_depth1_bundle) -> None:
    """``Womens`` matches ``Women's`` in scope (apostrophe-insensitive)."""
    b = load_bundle(
        dst_depth1_bundle.domain, dst_depth1_bundle.lang, directory=dst_depth1_bundle.directory
    )
    filtered = filter_bundle(b, scope=["Womens crisis centres - Enquiries"])
    assert filtered.resolved_scope == ("Women's crisis centres - Enquiries",)


def test_lookup_without_scope_filter_depth1(dst_depth1_bundle) -> None:
    """Lookup across the full depth=1 bundle; no ``scope_level_2`` crash."""
    b = load_bundle(
        dst_depth1_bundle.domain, dst_depth1_bundle.lang, directory=dst_depth1_bundle.directory
    )
    filtered = filter_bundle(b)
    result = lookup("law_reference", b, filtered)
    assert not result.df.empty
    assert result.missing == []


def test_lookup_with_scope_filter_depth1(dst_depth1_bundle) -> None:
    """Lookup with scope filter works at depth=1 (regression: hardcoded scope_level_2)."""
    b = load_bundle(
        dst_depth1_bundle.domain, dst_depth1_bundle.lang, directory=dst_depth1_bundle.directory
    )
    filtered = filter_bundle(b, scope=["Active civil servants in the state"])
    result = lookup("law_reference", b, filtered)
    assert not result.df.empty


def test_autolabel_applies_variable_and_value_labels(dst_depth1_bundle) -> None:
    """End-to-end: load → filter → collapse → apply, labels land on df.attrs."""
    df = pd.DataFrame(
        {
            "law_reference": ["§1", "§2", "§3"],
            "civil_rank": [1, 2, 1],
            "case_id": ["a", "b", "c"],
        }
    )
    df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    var_labels = df.rs.variable_labels()
    val_labels = df.rs.value_labels()
    assert var_labels.get("law_reference") == "Law reference"
    assert var_labels.get("civil_rank") == "Civil servant rank"
    assert val_labels.get("civil_rank") == {1: "Junior", 2: "Senior"}
    assert df.attrs["schema_version"] == "2.0"


def test_no_match_raises(dst_depth1_bundle) -> None:
    """A missing scope raises FilterError with a helpful hint."""
    b = load_bundle(
        dst_depth1_bundle.domain, dst_depth1_bundle.lang, directory=dst_depth1_bundle.directory
    )
    with pytest.raises(FilterError):
        filter_bundle(b, scope=["NONEXISTENT_XYZ_1234"])


def test_collapse_is_stable_across_scope_columns(dst_depth1_bundle) -> None:
    """Collapse uses dynamic scope_level_N column list; no hardcoded depth."""
    b = load_bundle(
        dst_depth1_bundle.domain, dst_depth1_bundle.lang, directory=dst_depth1_bundle.directory
    )
    filtered = filter_bundle(b)
    collapsed = collapse_to_one_per_variable(filtered, b)
    assert collapsed["variable_name"].is_unique
    # Four variables in the DST fixture.
    assert len(collapsed) == 4
