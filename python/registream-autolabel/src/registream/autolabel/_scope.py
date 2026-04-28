"""``autolabel scope``: depth-agnostic scope browse for the catalog.

Module-level Python analog of the Stata ``autolabel scope [<filter>], domain() lang() scope() release()`` command. Returns a
:class:`pandas.DataFrame` at every level so Jupyter / notebook users
see a tabular result and can chain downstream ops.

Level mapping:

- no ``scope``, no ``release`` → one row per level-1 value with count
  of variables in that level.
- ``scope=[lvl1]`` → one row per level-2 value under ``lvl1`` (or,
  when ``scope_depth == 1``, the releases at that level-1 atom).
- ``scope=[lvl1, …, lvlN]`` (full depth) → one row per release for
  that scope atom.
- full-depth scope + ``release=<r>`` (or overflow as the extra token)
  → one row per variable in that ``(scope, release)``.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from registream.autolabel._filters import filter_bundle, resolve_scope
from registream.autolabel._types import LabelBundle
from registream.metadata import load_bundle

__all__ = ["scope"]


def scope(
    domain: str = "scb",
    lang: str = "eng",
    *,
    search: str | None = None,
    scope: list[str] | tuple[str, ...] | None = None,
    release: str | None = None,
    directory: Path | str | None = None,
) -> pd.DataFrame:
    """Browse the catalog for ``(domain, lang)``."""
    bundle = load_bundle(domain, lang, directory=directory)
    if bundle.core_only or bundle.scope is None or bundle.release_sets is None:
        raise ValueError(
            f"scope browse requires the augmentation files (manifest + scope + "
            f"release_sets) which are not present for {domain}/{lang}. "
            f"Re-download via update_datasets()."
        )

    tokens = [t for t in (scope or []) if t is not None]
    depth = bundle.manifest.scope_depth

    if len(tokens) > depth and release is None:
        release = tokens[-1]
        tokens = tokens[:-1]

    # Release pinned (explicit or overflow) → show variables at the atom.
    if release is not None:
        return _variables_at_atom(bundle, tokens, release)

    # No tokens → browse level 1.
    if not tokens:
        return _browse_level(bundle, level_index=1, search=search)

    # Resolve the tokens provided so far.
    scope_df, _ = resolve_scope(bundle, tokens)

    # Full-depth tokens → list releases at this atom.
    if len(tokens) == depth:
        return _releases_at_scope(bundle, scope_df)

    # Partial depth → browse the next level under the resolved prefix.
    return _browse_level(
        bundle,
        level_index=len(tokens) + 1,
        scope_df=scope_df,
        search=search,
    )


def _browse_level(
    bundle: LabelBundle,
    *,
    level_index: int,
    scope_df: pd.DataFrame | None = None,
    search: str | None = None,
) -> pd.DataFrame:
    """Return a DataFrame of distinct values at ``scope_level_{level_index}``."""
    src = scope_df if scope_df is not None else bundle.scope
    assert src is not None
    name_col = f"scope_level_{level_index}"
    alias_col = f"scope_level_{level_index}_alias"
    cols = [name_col]
    if alias_col in src.columns:
        cols.append(alias_col)
    distinct = src[cols].drop_duplicates().copy()
    if search:
        needle = search.lower().replace("'", "")
        distinct = distinct[
            distinct[name_col]
            .astype(str)
            .str.lower()
            .str.replace("'", "", regex=False)
            .str.contains(needle, na=False, regex=False)
        ]
    if distinct.empty:
        return distinct.reset_index(drop=True)

    # Count variables reachable at each distinct value.
    assert bundle.release_sets is not None and bundle.scope is not None
    joined = bundle.variables.merge(bundle.release_sets, on="release_set_id").merge(
        bundle.scope[["scope_id", name_col]], on="scope_id"
    )
    counts = (
        joined.drop_duplicates(subset=["variable_name", name_col])
        .groupby(name_col)
        .size()
        .rename("variable_count")
        .reset_index()
    )
    out = distinct.merge(counts, on=name_col, how="left").fillna({"variable_count": 0})
    out["variable_count"] = out["variable_count"].astype(int)
    return out.sort_values(name_col, kind="mergesort").reset_index(drop=True)


def _releases_at_scope(bundle: LabelBundle, scope_df: pd.DataFrame) -> pd.DataFrame:
    """Return one row per release at the resolved scope."""
    cols = ["release"]
    if "release_description" in scope_df.columns:
        cols.append("release_description")
    if "population_date" in scope_df.columns:
        cols.append("population_date")
    return (
        scope_df[cols]
        .drop_duplicates()
        .sort_values("release", kind="mergesort")
        .reset_index(drop=True)
    )


def _variables_at_atom(
    bundle: LabelBundle,
    tokens: list[str] | tuple[str, ...],
    release: str | None,
) -> pd.DataFrame:
    """Return the variables at a pinned ``(scope, release)`` atom."""
    filtered = filter_bundle(bundle, scope=list(tokens) or None, release=release)
    cols = ["variable_name", "variable_label", "variable_type"]
    existing = [c for c in cols if c in filtered.variables.columns]
    out = filtered.variables[existing].drop_duplicates(subset=["variable_name"])
    return out.sort_values("variable_name", kind="mergesort").reset_index(drop=True)
