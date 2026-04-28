"""Depth-agnostic scope / release filter pipeline.

Mirrors ``_al_filter_scope`` (``autolabel/stata/src/autolabel.ado`` lines
3053-3160) and the overflow-token / auto-drill rules at lines
1499-1502 and 1527-1535 respectively. The match ladder per level is:

1. exact match on ``scope_level_N_alias``
2. exact match on ``scope_level_N``
3. substring match on ``scope_level_N``

with case- and apostrophe-insensitive comparison. The first
level-miss raises :class:`FilterError` citing the failed level.
"""

from __future__ import annotations

import pandas as pd

from registream.autolabel._inference import infer_scope
from registream.autolabel._types import FilteredBundle, LabelBundle, ScopeInference

__all__ = ["FilterError", "filter_bundle", "resolve_scope", "normalize_token"]


class FilterError(ValueError):
    """Raised when a scope / release filter cannot be satisfied."""


def normalize_token(s: object) -> str:
    """Lowercase + strip apostrophes for case/apostrophe-insensitive comparison."""
    if s is None or (isinstance(s, float) and pd.isna(s)):
        return ""
    return str(s).lower().replace("'", "")


def filter_bundle(
    bundle: LabelBundle,
    *,
    scope: list[str] | tuple[str, ...] | None = None,
    release: str | None = None,
    datavars: list[str] | tuple[str, ...] | None = None,
) -> FilteredBundle:
    """Apply the scope/release filter and return a :class:`FilteredBundle`.

    When ``scope`` is ``None`` and ``datavars`` is provided, the bundle
    is not narrowed; instead :func:`infer_scope` tags the winning
    scope tuple with ``_is_primary=1`` on the variables DataFrame so a
    later collapse step can prefer primary-scope labels.

    When ``scope`` is provided, it is tokenized into level values. If
    ``len(scope) == scope_depth + 1`` and ``release is None``, the last
    token is promoted to ``release`` (overflow rule).
    """
    tokens = list(scope) if scope else []
    depth = bundle.manifest.scope_depth

    # Core-only mode: no scope filter possible.
    if bundle.core_only or bundle.scope is None or bundle.release_sets is None:
        if tokens:
            raise FilterError(
                "scope() requires a full bundle (manifest + scope + release_sets); "
                "the loaded bundle is core-only. Re-download via update_datasets()."
            )
        if release is not None:
            raise FilterError(
                "release() requires a full bundle (manifest + scope + release_sets); "
                "the loaded bundle is core-only. Re-download via update_datasets()."
            )
        return FilteredBundle(
            variables=bundle.variables.assign(_is_primary=0),
            value_labels=bundle.value_labels,
            scope_rows=None,
        )

    # Overflow-token → release (autolabel.ado:1499-1502).
    if len(tokens) == depth + 1 and release is None:
        release = tokens[-1]
        tokens = tokens[:-1]
    elif len(tokens) > depth:
        raise FilterError(
            f"scope() has {len(tokens)} tokens but manifest declares scope_depth={depth} "
            f"(overflow allows {depth + 1} tokens where the last becomes release)."
        )

    inferred: ScopeInference | None = None
    scope_rows = bundle.scope

    if tokens:
        scope_rows, resolved_levels = resolve_scope(bundle, tokens)
    else:
        resolved_levels = None
        if datavars:
            inferred = infer_scope(bundle, datavars)

    if release is not None:
        rel_mask = scope_rows["release"].astype(str) == str(release)
        scope_rows = scope_rows[rel_mask]
        if scope_rows.empty:
            raise FilterError(
                f"No metadata found for release={release!r} at the requested scope."
            )

    # Auto-drill: scope specified but no release, and the resolved scope
    # has exactly one release; surface it for the caller's UI
    # (autolabel.ado:1527-1535).
    auto_drilled_release: str | None = None
    if tokens and release is None:
        rels = scope_rows["release"].astype(str).unique()
        if len(rels) == 1:
            auto_drilled_release = rels[0]

    # Map scope rows → release_set_ids → variables.
    scope_ids = scope_rows["scope_id"].unique()
    rs = bundle.release_sets
    release_set_ids = rs.loc[rs["scope_id"].isin(scope_ids), "release_set_id"].unique()

    variables = bundle.variables
    if tokens or release is not None:
        variables = variables[variables["release_set_id"].isin(release_set_ids)].reset_index(drop=True)

    # Tag _is_primary: explicit tokens → all surviving rows are primary.
    # Inference → only rows whose scope tuple matches the inferred tuple.
    variables = variables.copy()
    if tokens:
        variables["_is_primary"] = 1
    elif inferred is not None:
        variables["_is_primary"] = _tag_primary(
            variables, bundle, inferred.levels
        )
    else:
        variables["_is_primary"] = 0

    return FilteredBundle(
        variables=variables,
        value_labels=bundle.value_labels,
        scope_rows=scope_rows.reset_index(drop=True),
        inferred=inferred,
        resolved_scope=tuple(resolved_levels) if resolved_levels else None,
        resolved_release=release,
        auto_drilled_release=auto_drilled_release,
    )


def resolve_scope(
    bundle: LabelBundle,
    tokens: list[str] | tuple[str, ...],
) -> tuple[pd.DataFrame, list[str]]:
    """Resolve user tokens against ``scope`` via the match ladder.

    Returns the narrowed scope DataFrame and the list of resolved
    level values. Raises :class:`FilterError` on the first level that
    fails to match.
    """
    if bundle.scope is None:
        raise FilterError("scope() requires the bundle's scope file.")

    depth = bundle.manifest.scope_depth
    scope_df = bundle.scope
    resolved: list[str] = []

    for i, raw in enumerate(tokens, start=1):
        if i > depth:
            raise FilterError(
                f"scope() level {i} exceeds manifest scope_depth={depth}."
            )
        if raw is None or str(raw).strip() == "":
            # Empty token at this level = "all values at this level".
            resolved.append("")
            continue

        name_col = f"scope_level_{i}"
        alias_col = f"scope_level_{i}_alias"
        target = normalize_token(raw)

        candidate_mask: pd.Series | None = None

        # Step 1: exact on alias.
        if alias_col in scope_df.columns:
            alias_norm = scope_df[alias_col].map(normalize_token)
            mask = alias_norm == target
            if mask.any():
                candidate_mask = mask

        # Step 2: exact on name.
        if candidate_mask is None:
            name_norm = scope_df[name_col].map(normalize_token)
            mask = name_norm == target
            if mask.any():
                candidate_mask = mask

        # Step 3: substring on name.
        if candidate_mask is None:
            name_norm = scope_df[name_col].map(normalize_token)
            mask = name_norm.str.contains(target, regex=False, na=False)
            if mask.any():
                candidate_mask = mask

        if candidate_mask is None:
            available = sorted(
                {v for v in scope_df[name_col].dropna().astype(str).unique()}
            )[:10]
            hint = ""
            if available:
                hint = "\n  Available values: " + ", ".join(repr(v) for v in available)
            raise FilterError(
                f"No scope match at level {i} for {raw!r}.{hint}"
            )

        scope_df = scope_df[candidate_mask]
        # The resolved level value is the first distinct name from the
        # surviving rows (we don't lose alternatives if substring matched
        # multiple names; caller can drill further).
        resolved.append(str(scope_df[name_col].iloc[0]))

    return scope_df, resolved


def _tag_primary(
    variables: pd.DataFrame,
    bundle: LabelBundle,
    primary_levels: tuple[str, ...],
) -> pd.Series:
    """Return a 0/1 Series marking rows whose scope tuple matches ``primary_levels``."""
    if bundle.scope is None or bundle.release_sets is None:
        return pd.Series(0, index=variables.index, dtype=int)

    depth = bundle.manifest.scope_depth
    level_cols = [f"scope_level_{i}" for i in range(1, depth + 1)]

    matching = bundle.scope
    for col, val in zip(level_cols, primary_levels, strict=False):
        matching = matching[matching[col].astype(str).fillna("") == val]
    primary_scope_ids = matching["scope_id"].unique()
    primary_rs_ids = bundle.release_sets.loc[
        bundle.release_sets["scope_id"].isin(primary_scope_ids), "release_set_id"
    ].unique()

    return variables["release_set_id"].isin(primary_rs_ids).astype(int)
