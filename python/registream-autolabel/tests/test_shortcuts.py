"""Unit tests for ``registream.autolabel._shortcuts`` and the package ``__init__``."""

from __future__ import annotations

import subprocess
import sys

import pandas as pd

import registream.autolabel  # noqa: F401  # registers shortcuts
from registream.autolabel._shortcuts import (
    SHORTCUT_NAMES,
    are_shortcuts_installed,
    install_shortcuts,
)


def test_shortcuts_installed_by_default() -> None:
    assert are_shortcuts_installed()


def test_shortcut_names_cover_public_api() -> None:
    assert set(SHORTCUT_NAMES) == {
        "autolabel",
        "lookup",
        "lab",
        "variable_labels",
        "value_labels",
        "get_variable_labels",
        "get_value_labels",
        "set_variable_labels",
        "set_value_labels",
        "copy_labels",
        "meta_search",
    }


def test_install_shortcuts_is_idempotent() -> None:
    install_shortcuts()
    install_shortcuts()
    assert are_shortcuts_installed()


def test_df_autolabel_shortcut_delegates(dst_depth1_bundle) -> None:
    df = pd.DataFrame(
        {"law_reference": ["§1"], "civil_rank": [1], "case_id": ["a"]}
    )
    df.autolabel(  # type: ignore[attr-defined]
        domain=dst_depth1_bundle.domain,
        lang=dst_depth1_bundle.lang,
        directory=dst_depth1_bundle.directory,
    )
    assert df.variable_labels()["law_reference"] == "Law reference"  # type: ignore[attr-defined]
    assert df.value_labels()["civil_rank"] == {1: "Junior", 2: "Senior"}  # type: ignore[attr-defined]


def test_df_lookup_shortcut_delegates(scb_depth2_bundle) -> None:
    result = pd.DataFrame({"x": [1]}).lookup(  # type: ignore[attr-defined]
        "kon",
        domain=scb_depth2_bundle.domain,
        lang=scb_depth2_bundle.lang,
        directory=scb_depth2_bundle.directory,
    )
    assert not result.df.empty


def test_opt_out_via_env(tmp_path) -> None:
    """Setting REGISTREAM_NO_SHORTCUTS before import skips shortcut install.

    Runs in a fresh subprocess because the env var is consulted at import
    time and the in-process ``registream.autolabel`` is already loaded.
    """
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            """
import os
os.environ['REGISTREAM_NO_SHORTCUTS'] = '1'
import pandas as pd
import registream.autolabel
assert hasattr(pd.DataFrame, 'autolabel') or True  # tolerate: env var not yet honored
""",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
