"""Shared pytest fixtures for autolabel tests.

Builds synthetic 5-file bundles (manifest + scope + variables +
value_labels + release_sets) in the per-domain cache subdirectory
layout ``{tmp_path}/autolabel/{domain}/{type}_{lang}.csv``. The CSVs
use semicolon delimiters per ``autolabel/docs/schema.md`` §CSV
conventions.

Fixtures are exposed as tuples ``(registream_dir, domain, lang)`` so
call sites pass the ``directory=`` kwarg through to ``load_bundle`` /
``filter_bundle`` / the accessor.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pandas as pd
import pytest

from registream.config import Config
from registream.config import save as save_config
from registream.metadata import AUTOLABEL_SUBDIR

DEV_API_HOST = "http://localhost:5000"


@dataclass
class BundleFixture:
    directory: Path
    domain: str
    lang: str


@pytest.fixture(autouse=True)
def _auto_approve_prompts(monkeypatch: pytest.MonkeyPatch) -> None:
    """Auto-approve interactive prompts for every test."""
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "yes")


def _dev_server_available() -> bool:
    try:
        import requests

        r = requests.get(
            f"{DEV_API_HOST}/api/v1/datasets/scb/variables/eng/latest/info?format=stata",
            timeout=3,
        )
        return r.status_code == 200
    except Exception:
        return False


def _disable_network(tmp_path: Path) -> None:
    save_config(Config(internet_access=False), tmp_path)


def pytest_collection_modifyitems(config, items):
    if _dev_server_available():
        return
    skip_integration = pytest.mark.skip(reason="Dev API server not available at localhost:5000")
    for item in items:
        if "integration" in item.keywords:
            item.add_marker(skip_integration)


def _write_bundle(
    directory: Path,
    domain: str,
    lang: str,
    *,
    manifest: pd.DataFrame,
    scope: pd.DataFrame,
    variables: pd.DataFrame,
    value_labels: pd.DataFrame,
    release_sets: pd.DataFrame,
) -> None:
    ddir = directory / AUTOLABEL_SUBDIR / domain
    ddir.mkdir(parents=True, exist_ok=True)
    manifest.to_csv(ddir / f"manifest_{lang}.csv", sep=";", index=False, encoding="utf-8")
    scope.to_csv(ddir / f"scope_{lang}.csv", sep=";", index=False, encoding="utf-8")
    variables.to_csv(
        ddir / f"variables_{lang}.csv", sep=";", index=False, encoding="utf-8"
    )
    value_labels.to_csv(
        ddir / f"value_labels_{lang}.csv", sep=";", index=False, encoding="utf-8"
    )
    release_sets.to_csv(
        ddir / f"release_sets_{lang}.csv", sep=";", index=False, encoding="utf-8"
    )


@pytest.fixture
def dst_depth1_bundle(tmp_path: Path) -> BundleFixture:
    """5-file DST bundle with ``scope_depth = 1``.

    Covers the depth-agnostic regression: only one scope level exists
    (``scope_level_1 = "Active civil servants in the state"`` and a
    second scope with an apostrophe in the name for the
    apostrophe-insensitive match test). Three variables, one with a
    value-label set.
    """
    manifest = pd.DataFrame(
        {
            "key": [
                "domain",
                "schema_version",
                "publisher",
                "bundle_release_date",
                "languages",
                "scope_depth",
                "scope_level_1_name",
                "scope_level_1_title",
            ],
            "value": [
                "dst",
                "2.0",
                "Statistics Denmark (DST)",
                "2026-04-16",
                "eng",
                "1",
                "register",
                "Register",
            ],
        }
    )
    scope = pd.DataFrame(
        {
            "scope_id": [1, 2, 3, 4],
            "scope_level_1": [
                "Active civil servants in the state",
                "Active civil servants in the state",
                "Women's crisis centres - Enquiries",
                "Women's crisis centres - Enquiries",
            ],
            "scope_level_1_alias": ["CIVIL", "CIVIL", "KRISE", "KRISE"],
            "scope_level_1_description": [""] * 4,
            "release": ["2020", "2021", "2020", "2021"],
            "release_description": ["", "", "", ""],
        }
    )
    release_sets = pd.DataFrame(
        {
            "release_set_id": [10, 10, 11, 11, 12, 12, 13, 13],
            "scope_id": [1, 2, 1, 2, 3, 4, 3, 4],
        }
    )
    variables = pd.DataFrame(
        {
            "variable_name": ["law_reference", "civil_rank", "inquiry_count", "case_id"],
            "variable_label": [
                "Law reference",
                "Civil servant rank",
                "Number of inquiries",
                "Case identifier",
            ],
            "variable_type": ["text", "categorical", "continuous", "identifier"],
            "variable_unit": ["", "", "cases", ""],
            "datatype": ["str", "int", "int", "str"],
            "value_label_id": ["", "rank_lbl", "", ""],
            "release_set_id": [10, 10, 12, 13],
        }
    )
    value_labels = pd.DataFrame(
        {
            "value_label_id": ["rank_lbl"],
            "variable_name": ["civil_rank"],
            "value_labels_json": ['{"1": "Junior", "2": "Senior"}'],
            "value_labels_stata": ['"1" "Junior" "2" "Senior"'],
            "code_count": [2],
        }
    )
    _write_bundle(
        tmp_path,
        "dst",
        "eng",
        manifest=manifest,
        scope=scope,
        variables=variables,
        value_labels=value_labels,
        release_sets=release_sets,
    )
    _disable_network(tmp_path)
    return BundleFixture(directory=tmp_path, domain="dst", lang="eng")


@pytest.fixture
def scb_depth2_bundle(tmp_path: Path) -> BundleFixture:
    """5-file SCB bundle with ``scope_depth = 2`` (Register / Variant).

    Three variables across two registers: ``kon`` in LISA (Individers
    16+) and in STATIV; ``kommun`` in LISA only. Designed to exercise
    scope inference (LISA wins), explicit scope pin, release pinning,
    and overflow-token → release promotion.
    """
    manifest = pd.DataFrame(
        {
            "key": [
                "domain",
                "schema_version",
                "publisher",
                "bundle_release_date",
                "languages",
                "scope_depth",
                "scope_level_1_name",
                "scope_level_1_title",
                "scope_level_2_name",
                "scope_level_2_title",
            ],
            "value": [
                "scb",
                "2.0",
                "Statistics Sweden (SCB)",
                "2026-04-16",
                "eng",
                "2",
                "register",
                "Register",
                "variant",
                "Variant",
            ],
        }
    )
    scope = pd.DataFrame(
        {
            "scope_id": [1001, 1002, 1003, 2001],
            "scope_level_1": [
                "Longitudinell integrationsdatabas",
                "Longitudinell integrationsdatabas",
                "Longitudinell integrationsdatabas",
                "Statistik över individers inkomster",
            ],
            "scope_level_1_alias": ["LISA", "LISA", "LISA", "STATIV"],
            "scope_level_1_description": ["", "", "", ""],
            "scope_level_2": [
                "Individuals aged 16 and older",
                "Individuals aged 16 and older",
                "Individuals aged 16 and older",
                "Individuals",
            ],
            "scope_level_2_alias": ["", "", "", ""],
            "scope_level_2_description": ["", "", "", ""],
            "release": ["2005", "2006", "2007", "2005"],
            "release_description": ["", "", "", ""],
        }
    )
    release_sets = pd.DataFrame(
        {
            "release_set_id": [42, 42, 42, 43, 44],
            "scope_id": [1001, 1002, 1003, 1001, 2001],
        }
    )
    variables = pd.DataFrame(
        {
            "variable_name": ["kon", "kommun", "kon"],
            "variable_label": ["Gender", "Municipality of residence", "Gender (STATIV)"],
            "variable_type": ["categorical", "categorical", "categorical"],
            "variable_unit": ["", "", ""],
            "datatype": ["int", "int", "int"],
            "value_label_id": ["kon_lbl", "", "kon_lbl"],
            "release_set_id": [42, 43, 44],
        }
    )
    value_labels = pd.DataFrame(
        {
            "value_label_id": ["kon_lbl"],
            "variable_name": ["kon"],
            "value_labels_json": ['{"1": "Man", "2": "Woman"}'],
            "value_labels_stata": ['"1" "Man" "2" "Woman"'],
            "code_count": [2],
        }
    )
    _write_bundle(
        tmp_path,
        "scb",
        "eng",
        manifest=manifest,
        scope=scope,
        variables=variables,
        value_labels=value_labels,
        release_sets=release_sets,
    )
    _disable_network(tmp_path)
    return BundleFixture(directory=tmp_path, domain="scb", lang="eng")


@pytest.fixture
def scb_core_only_bundle(tmp_path: Path) -> BundleFixture:
    """Core-only SCB bundle: only ``variables`` + ``value_labels``, no augmentation."""
    ddir = tmp_path / AUTOLABEL_SUBDIR / "scb"
    ddir.mkdir(parents=True, exist_ok=True)

    pd.DataFrame(
        {
            "variable_name": ["kon", "kommun"],
            "variable_label": ["Gender", "Municipality"],
            "variable_type": ["categorical", "categorical"],
            "variable_unit": ["", ""],
            "datatype": ["int", "int"],
            "value_label_id": ["kon_lbl", ""],
            "release_set_id": [1, 2],
        }
    ).to_csv(ddir / "variables_eng.csv", sep=";", index=False, encoding="utf-8")
    pd.DataFrame(
        {
            "value_label_id": ["kon_lbl"],
            "variable_name": ["kon"],
            "value_labels_json": ['{"1": "Man", "2": "Woman"}'],
            "value_labels_stata": ['"1" "Man" "2" "Woman"'],
            "code_count": [2],
        }
    ).to_csv(ddir / "value_labels_eng.csv", sep=";", index=False, encoding="utf-8")

    _disable_network(tmp_path)
    return BundleFixture(directory=tmp_path, domain="scb", lang="eng")
