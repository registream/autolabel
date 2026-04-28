"""Scope inference: pick the scope tuple that best covers a dataset's columns.

Mirrors the inference block of ``autolabel/stata/src/autolabel.ado``
(inside ``_al_collapse_rep1``). For each unique ``(scope_level_1, ...,
scope_level_N)`` tuple in the bundle, count how many distinct
``variable_name`` values appear in both the bundle and the user's
column list (case-insensitive). Break ties by total distinct-variable
coverage of the scope, then alphabetically on the level tuple.
"""

from __future__ import annotations

import pandas as pd

from registream.autolabel._types import LabelBundle, ScopeInference

__all__ = ["infer_scope"]

_STRONG_PRIMARY_PCT = 10


def infer_scope(
    bundle: LabelBundle,
    datavars: list[str] | tuple[str, ...],
) -> ScopeInference | None:
    """Return the best-matching :class:`ScopeInference` or ``None``.

    Returns ``None`` when the bundle is core-only (no scope/release_sets
    tables), when ``datavars`` is empty, or when no variables match.
    """
    if not datavars:
        return None
    if bundle.core_only or bundle.scope is None or bundle.release_sets is None:
        return None

    depth = bundle.manifest.scope_depth
    if depth < 1:
        return None

    level_cols = [f"scope_level_{i}" for i in range(1, depth + 1)]
    alias_cols = [f"scope_level_{i}_alias" for i in range(1, depth + 1)]

    datavars_lower = {v.lower() for v in datavars if isinstance(v, str)}
    if not datavars_lower:
        return None

    var_names = bundle.variables["variable_name"].astype(str).str.lower()
    matching_mask = var_names.isin(datavars_lower)

    if not matching_mask.any():
        return None

    # Attach scope tuples via release_sets → scope. A release_set_id
    # can be associated with multiple scope_ids, but by §6 rule 4 they
    # all share the same scope tuple, so we dedupe on release_set_id
    # before joining to variables.
    scope_per_rs = (
        bundle.release_sets.merge(
            bundle.scope[["scope_id", *level_cols, *[c for c in alias_cols if c in bundle.scope.columns]]],
            on="scope_id",
            how="inner",
        )
        .drop_duplicates(subset=["release_set_id"])
    )

    variables = bundle.variables.loc[matching_mask, ["variable_name", "release_set_id"]].copy()
    variables["variable_name"] = variables["variable_name"].astype(str).str.lower()
    joined = variables.merge(scope_per_rs, on="release_set_id", how="inner")

    if joined.empty:
        return None

    group_cols = level_cols
    unique_matches = (
        joined.drop_duplicates(subset=[*group_cols, "variable_name"])
        .groupby(group_cols, dropna=False)
        .size()
        .rename("matches")
    )

    coverage = (
        bundle.variables.merge(scope_per_rs, on="release_set_id", how="inner")
        .drop_duplicates(subset=[*group_cols, "variable_name"])
        .groupby(group_cols, dropna=False)
        .size()
        .rename("coverage")
    )

    ranking = pd.concat([unique_matches, coverage], axis=1).reset_index()
    ranking = ranking[ranking["matches"] > 0]
    if ranking.empty:
        return None

    ranking = ranking.sort_values(
        by=["matches", "coverage", *group_cols],
        ascending=[False, False, *[True] * depth],
        kind="mergesort",
    )

    top = ranking.iloc[0]
    levels = tuple(str(top[c]) if not pd.isna(top[c]) else "" for c in group_cols)

    # Alias lookup for the winning tuple
    alias_row_mask = True
    for col, val in zip(group_cols, levels, strict=True):
        alias_row_mask = alias_row_mask & (
            scope_per_rs[col].astype(str).fillna("") == val
        )
    alias_rows = scope_per_rs[alias_row_mask]
    level_aliases: list[str] = []
    for col in alias_cols:
        if col in alias_rows.columns and not alias_rows.empty:
            vals = alias_rows[col].dropna().astype(str).str.strip()
            vals = vals[vals != ""]
            level_aliases.append(vals.iloc[0] if not vals.empty else "")
        else:
            level_aliases.append("")

    total_datavars = len(datavars_lower)
    matches = int(top["matches"])
    match_pct = round(matches / total_datavars * 100) if total_datavars else 0
    has_strong_primary = match_pct >= _STRONG_PRIMARY_PCT

    return ScopeInference(
        levels=levels,
        level_aliases=tuple(level_aliases),
        matches=matches,
        total_datavars=total_datavars,
        match_pct=match_pct,
        has_strong_primary=has_strong_primary,
    )
