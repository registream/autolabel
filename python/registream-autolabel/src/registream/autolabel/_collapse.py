"""Collapse a filtered bundle to one metadata row per ``variable_name``.

Mirrors ``_al_collapse_rep1`` (``autolabel/stata/src/autolabel.ado``
lines 2620-2894). Sort key per variable:

1. ``_is_primary`` DESC: prefer the inferred / pinned primary scope.
2. ``_label_freq`` DESC: prefer the most-common label across scopes.
3. ``scope_level_1`` ASC … ``scope_level_N`` ASC: deterministic
   tie-break via the scope tuple (column count driven by manifest
   ``scope_depth``).

The collapse is lossless: every user variable still gets a row, and
the unused rows are dropped only after sort so the deterministic
tie-break is stable across runs.
"""

from __future__ import annotations

import pandas as pd

from registream.autolabel._types import FilteredBundle, LabelBundle

__all__ = ["collapse_to_one_per_variable"]


def collapse_to_one_per_variable(
    filtered: FilteredBundle,
    bundle: LabelBundle,
) -> pd.DataFrame:
    """Return one row per ``variable_name`` using the sort key above."""
    variables = filtered.variables
    if variables.empty:
        return variables.copy()

    depth = bundle.manifest.scope_depth
    level_cols = [f"scope_level_{i}" for i in range(1, depth + 1)]

    if bundle.scope is None or bundle.release_sets is None or depth == 0:
        joined = variables.copy()
        # No scope tuple available; fall back to label frequency only.
        joined["_label_freq"] = _label_freq(joined)
        joined = joined.sort_values(
            by=["variable_name", "_is_primary", "_label_freq"],
            ascending=[True, False, False],
            kind="mergesort",
        )
        return joined.drop_duplicates(subset=["variable_name"], keep="first").reset_index(
            drop=True
        )

    # Attach scope tuple via release_sets → scope.
    rs_to_scope = bundle.release_sets.merge(
        bundle.scope[["scope_id", *level_cols]],
        on="scope_id",
        how="inner",
    ).drop_duplicates(subset=["release_set_id"])[["release_set_id", *level_cols]]

    joined = variables.merge(rs_to_scope, on="release_set_id", how="left")
    joined["_label_freq"] = _label_freq(joined)

    sort_cols = ["variable_name", "_is_primary", "_label_freq", *level_cols]
    ascending = [True, False, False, *[True] * depth]
    joined = joined.sort_values(by=sort_cols, ascending=ascending, kind="mergesort")
    return joined.drop_duplicates(subset=["variable_name"], keep="first").reset_index(
        drop=True
    )


def _label_freq(df: pd.DataFrame) -> pd.Series:
    """Return the count of rows sharing ``(variable_name, variable_label)``."""
    if "variable_label" not in df.columns:
        return pd.Series(1, index=df.index, dtype=int)
    return df.groupby(["variable_name", "variable_label"])["variable_name"].transform("size")
