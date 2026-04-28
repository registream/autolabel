"""Tests for the top-level autolabel commands mirroring the Stata surface.

Covers ``suggest``, ``info``, ``cite``, the top-level ``autolabel()``
function, the accessor's ``exclude=`` / ``dryrun=`` parameters, and the
old-package ``get_variable_labels`` / ``get_value_labels`` shortcut
aliases.
"""

from __future__ import annotations

import pandas as pd
import pytest

import registream.autolabel  # noqa: F401  # registers df.rs + shortcuts
from registream.autolabel import (
    DryRunResult,
    SuggestResult,
    autolabel,
    cite,
    info,
    suggest,
)


def _df_for_scb() -> pd.DataFrame:
    return pd.DataFrame({"kon": [1, 2, 1], "kommun": [101, 102, 103]})


# ── suggest() ─────────────────────────────────────────────────────────────────


def test_suggest_returns_suggest_result(scb_depth2_bundle) -> None:
    df = _df_for_scb()
    result = suggest(
        df,
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    assert isinstance(result, SuggestResult)
    assert not result.coverage.empty
    assert "matches" in result.coverage.columns
    assert "coverage_pct" in result.coverage.columns
    assert "is_primary" in result.coverage.columns


def test_suggest_identifies_primary_scope(scb_depth2_bundle) -> None:
    df = _df_for_scb()
    result = suggest(
        df,
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    # LISA should be inferred primary; kon + kommun both appear there.
    assert result.primary is not None
    assert (
        "Longitudinell integrationsdatabas" in result.primary.levels
        or "LISA" in (result.primary.level_aliases or ())
    )
    assert result.primary.has_strong_primary


def test_suggest_does_not_mutate_dataframe(scb_depth2_bundle) -> None:
    df = _df_for_scb()
    before_attrs = dict(df.attrs)
    suggest(
        df,
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    assert dict(df.attrs) == before_attrs


def test_suggest_pin_command_is_runnable_form(scb_depth2_bundle) -> None:
    df = _df_for_scb()
    result = suggest(
        df,
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    assert result.pin_command.startswith("df.autolabel(")
    assert "domain='scb'" in result.pin_command
    assert "lang='eng'" in result.pin_command


# ── info() ────────────────────────────────────────────────────────────────────


def test_info_returns_config_and_versions() -> None:
    snapshot = info()
    assert "registream_dir" in snapshot
    assert "autolabel_cache" in snapshot
    assert "core_version" in snapshot
    assert "autolabel_version" in snapshot
    assert isinstance(snapshot.get("config"), dict)


def test_info_honors_directory_override(tmp_path) -> None:
    snapshot = info(directory=tmp_path)
    assert snapshot["registream_dir"] == str(tmp_path)


# ── cite() ────────────────────────────────────────────────────────────────────


def test_cite_matches_stata_format() -> None:
    s = cite()
    assert "Clark, J. & Wen, J." in s
    assert "registream.org" in s
    assert "Version" in s


# ── top-level autolabel(df, ...) ─────────────────────────────────────────────


def test_top_level_autolabel_delegates_to_accessor(dst_depth1_bundle) -> None:
    df = pd.DataFrame({"law_reference": ["§1"], "civil_rank": [1], "case_id": ["a"]})
    autolabel(
        df,
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    assert df.variable_labels()["law_reference"] == "Law reference"  # type: ignore[attr-defined]


# ── dryrun / exclude on accessor ─────────────────────────────────────────────


def test_dryrun_returns_plan_without_mutating(dst_depth1_bundle) -> None:
    df = pd.DataFrame(
        {"law_reference": ["§1", "§2"], "civil_rank": [1, 2], "case_id": ["a", "b"]}
    )
    before_attrs = dict(df.attrs)
    plan = df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
        dryrun=True,
    )
    assert isinstance(plan, DryRunResult)
    assert plan.variable_labels.get("law_reference") == "Law reference"
    assert plan.value_labels.get("civil_rank") == {1: "Junior", 2: "Senior"}
    # df.attrs must be unchanged (no labels stamped).
    assert dict(df.attrs) == before_attrs


def test_dryrun_reports_resolved_scope(dst_depth1_bundle) -> None:
    df = pd.DataFrame({"law_reference": ["§1"], "civil_rank": [1], "case_id": ["a"]})
    plan = df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
        scope=["Active civil servants in the state"],
        dryrun=True,
    )
    assert plan.resolved_scope == ("Active civil servants in the state",)


def test_exclude_skips_listed_columns(dst_depth1_bundle) -> None:
    df = pd.DataFrame(
        {"law_reference": ["§1"], "civil_rank": [1], "case_id": ["a"]}
    )
    df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
        exclude=["civil_rank"],
    )
    labels = df.rs.variable_labels()
    # civil_rank is in the metadata but was excluded → no label.
    assert "law_reference" in labels
    assert "civil_rank" not in labels


def test_exclude_honors_variables_filter(dst_depth1_bundle) -> None:
    df = pd.DataFrame(
        {"law_reference": ["§1"], "civil_rank": [1], "case_id": ["a"]}
    )
    df.rs.autolabel(
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
        variables=["law_reference", "civil_rank"],
        exclude=["civil_rank"],
    )
    labels = df.rs.variable_labels()
    assert "law_reference" in labels
    assert "civil_rank" not in labels


# ── get_variable_labels / get_value_labels aliases ───────────────────────────


@pytest.fixture
def mini_labeled_df() -> pd.DataFrame:
    df = pd.DataFrame({"kon": [1, 2], "age": [30, 40]})
    df.set_variable_labels({"kon": "Sex", "age": "Age"})  # type: ignore[attr-defined]
    df.set_value_labels("kon", {1: "Man", 2: "Woman"})  # type: ignore[attr-defined]
    return df


def test_get_variable_labels_all(mini_labeled_df: pd.DataFrame) -> None:
    assert mini_labeled_df.get_variable_labels() == {"kon": "Sex", "age": "Age"}  # type: ignore[attr-defined]


def test_get_variable_labels_single(mini_labeled_df: pd.DataFrame) -> None:
    assert mini_labeled_df.get_variable_labels("kon") == "Sex"  # type: ignore[attr-defined]


def test_get_variable_labels_missing_returns_none(mini_labeled_df: pd.DataFrame) -> None:
    assert mini_labeled_df.get_variable_labels("nonexistent") is None  # type: ignore[attr-defined]


def test_get_variable_labels_list(mini_labeled_df: pd.DataFrame) -> None:
    result = mini_labeled_df.get_variable_labels(["kon", "missing"])  # type: ignore[attr-defined]
    assert result == {"kon": "Sex"}


def test_get_value_labels_all(mini_labeled_df: pd.DataFrame) -> None:
    assert mini_labeled_df.get_value_labels() == {"kon": {1: "Man", 2: "Woman"}}  # type: ignore[attr-defined]


def test_get_value_labels_single(mini_labeled_df: pd.DataFrame) -> None:
    assert mini_labeled_df.get_value_labels("kon") == {1: "Man", 2: "Woman"}  # type: ignore[attr-defined]


def test_get_value_labels_bad_type_raises(mini_labeled_df: pd.DataFrame) -> None:
    with pytest.raises(TypeError):
        mini_labeled_df.get_value_labels(42)  # type: ignore[attr-defined, arg-type]
