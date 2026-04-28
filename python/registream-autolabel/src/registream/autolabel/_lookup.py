"""Variable lookup over a loaded :class:`~registream.metadata.LabelBundle`.

Given one or more variable names, return a :class:`LookupResult`
containing:

- the matched metadata rows (one per variable in default mode, all
  matching rows in detail mode);
- the list of variable names that were requested but not found;
- ``scope_counts``: the number of distinct scope tuples per matched
  variable: useful for surfacing "appears in N scopes" in the UI.

The caller passes a pre-filtered :class:`~registream.autolabel._types.FilteredBundle`
(scope / release filtering already applied). This mirrors Stata's
flow where ``autolabel lookup`` operates on the already-filtered
metadata.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd

from registream.autolabel._labels import (
    VALUE_LABEL_ID_COLUMN,
    VALUE_LABELS_COLUMN,
    VARIABLE_LABEL_COLUMN,
    VARIABLE_NAME_COLUMN,
    parse_value_labels_stata,
)
from registream.autolabel._types import FilteredBundle, LabelBundle

__all__ = ["LookupResult", "lookup"]


_DISPLAY_COLUMNS: tuple[str, ...] = (
    "variable_name",
    "variable_label",
    "variable_type",
    "variable_unit",
    "value_labels",
    "scope_level_1",
    "scope_level_2",
    "release",
)


@dataclass
class LookupResult:
    """Result of a :func:`lookup` call.

    :attr:`df` carries the matched metadata rows (enriched with a
    ``value_labels`` dict column parsed from ``value_labels_stata``).
    :attr:`scope_counts` maps lowercased ``variable_name`` to the
    number of distinct scope tuples the variable appears in within the
    (filtered) bundle.

    The object renders as a DataFrame in Jupyter (``_repr_html_``) and
    as a compact table in a plain REPL (``__repr__``); the wrapping
    is for attribute access (``.missing``, ``.scope_counts``) without
    forcing callers to reach into ``.df``.
    """

    df: pd.DataFrame
    missing: list[str]
    scope_counts: dict[str, int] = field(default_factory=dict)

    def _display_df(self) -> pd.DataFrame:
        """Curated column subset for rendering.

        The raw ``df`` holds a dozen columns (definition, source, FK
        ids, …); for display we keep the fields users actually read so
        the table fits typical Jupyter / terminal widths. Call
        ``.df`` directly for the full row.
        """
        if self.df.empty:
            return self.df
        cols = [c for c in _DISPLAY_COLUMNS if c in self.df.columns]
        return self.df[cols] if cols else self.df

    def __repr__(self) -> str:
        if self.df.empty:
            body = "(no matches)"
        else:
            body = repr(self._display_df())
        missing = f"\nMissing: {self.missing}" if self.missing else ""
        return body + missing

    def _repr_html_(self) -> str:
        if self.df.empty:
            body = "<p><i>no matches</i></p>"
        else:
            html = getattr(self._display_df(), "_repr_html_", None)
            body = html() if callable(html) else repr(self._display_df())
        if self.missing:
            body += f"<p><b>Missing:</b> {', '.join(self.missing)}</p>"
        return body


def lookup(
    variables: str | list[str],
    bundle: LabelBundle,
    filtered: FilteredBundle,
    *,
    detail: bool = False,
) -> LookupResult:
    """Look up metadata for ``variables`` in the filtered bundle."""
    if isinstance(variables, str):
        variables = [variables]

    requested_lower = [v.lower() for v in variables]
    requested_pairs = list(zip(variables, requested_lower, strict=False))

    metadata = filtered.variables
    if VARIABLE_NAME_COLUMN not in metadata.columns or metadata.empty:
        return LookupResult(df=pd.DataFrame(), missing=list(variables))

    metadata = metadata.copy()
    metadata["_var_lower"] = metadata[VARIABLE_NAME_COLUMN].astype(str).str.lower()
    matched = metadata[metadata["_var_lower"].isin(requested_lower)]

    matched_lower = set(matched["_var_lower"]) if not matched.empty else set()
    missing = [orig for orig, low in requested_pairs if low not in matched_lower]

    scope_counts = _scope_counts(matched, bundle)

    if matched.empty:
        result_df = matched
    elif detail:
        result_df = _attach_scope_tuple(matched, bundle)
    else:
        result_df = _aggregate_default(matched)

    result_df = _enrich_with_value_labels(result_df, filtered.value_labels)
    if "_var_lower" in result_df.columns:
        result_df = result_df.drop(columns=["_var_lower"])

    return LookupResult(
        df=result_df.reset_index(drop=True),
        missing=missing,
        scope_counts=scope_counts,
    )


def _aggregate_default(matched: pd.DataFrame) -> pd.DataFrame:
    """Pick the most-common label per variable and return one row each."""
    df = matched.copy()
    df["_label_freq"] = df.groupby(
        [VARIABLE_NAME_COLUMN, VARIABLE_LABEL_COLUMN]
    )[VARIABLE_NAME_COLUMN].transform("size")
    sort_cols = [VARIABLE_NAME_COLUMN, "_label_freq"]
    ascending = [True, False]
    if "_is_primary" in df.columns:
        sort_cols.insert(1, "_is_primary")
        ascending.insert(1, False)
    sorted_df = df.sort_values(by=sort_cols, ascending=ascending, kind="stable")
    deduped = sorted_df.drop_duplicates(subset=[VARIABLE_NAME_COLUMN], keep="first")
    return deduped.drop(columns=["_label_freq"])


def _attach_scope_tuple(matched: pd.DataFrame, bundle: LabelBundle) -> pd.DataFrame:
    """Add ``scope_level_1..N`` and ``release`` columns via the FK chain."""
    depth = bundle.manifest.scope_depth
    if depth == 0 or bundle.scope is None or bundle.release_sets is None:
        return matched

    level_cols = [f"scope_level_{i}" for i in range(1, depth + 1)]
    scope_cols = ["scope_id", *level_cols, "release"] if "release" in bundle.scope.columns else ["scope_id", *level_cols]
    joined = matched.merge(bundle.release_sets, on="release_set_id", how="left").merge(
        bundle.scope[scope_cols], on="scope_id", how="left"
    )
    return joined


def _scope_counts(matched: pd.DataFrame, bundle: LabelBundle) -> dict[str, int]:
    """Count the distinct scope tuples per (lowered) ``variable_name``."""
    if matched.empty or bundle.scope is None or bundle.release_sets is None:
        return {}
    depth = bundle.manifest.scope_depth
    if depth == 0:
        return {}
    level_cols = [f"scope_level_{i}" for i in range(1, depth + 1)]
    joined = matched.merge(bundle.release_sets, on="release_set_id", how="left").merge(
        bundle.scope[["scope_id", *level_cols]], on="scope_id", how="left"
    )
    grouped = (
        joined.drop_duplicates(subset=["_var_lower", *level_cols])
        .groupby("_var_lower")
        .size()
    )
    return {str(k): int(v) for k, v in grouped.to_dict().items()}


def _enrich_with_value_labels(
    df: pd.DataFrame,
    value_labels: pd.DataFrame | None,
) -> pd.DataFrame:
    df = df.copy()
    if df.empty:
        df["value_labels"] = pd.Series([], dtype=object)
        return df

    # Parse only the value-label rows actually referenced by `df`. The full
    # SCB-English value_labels table is ~12k rows; eager parsing scales O(n)
    # in the bundle even for a single-variable lookup.
    cache: dict[str, dict] = {}
    needed_lids: set[str] = set()
    if VALUE_LABEL_ID_COLUMN in df.columns:
        for lid in df[VALUE_LABEL_ID_COLUMN].dropna():
            key = str(lid).strip()
            if key:
                needed_lids.add(key)

    if (
        needed_lids
        and value_labels is not None
        and VALUE_LABEL_ID_COLUMN in value_labels.columns
        and VALUE_LABELS_COLUMN in value_labels.columns
    ):
        lid_series = value_labels[VALUE_LABEL_ID_COLUMN].astype(str).str.strip()
        sub = value_labels[lid_series.isin(needed_lids)]
        for _, row in sub.iterrows():
            label_id = row[VALUE_LABEL_ID_COLUMN]
            if pd.isna(label_id):
                continue
            label_id_str = str(label_id).strip()
            if not label_id_str or label_id_str in cache:
                continue
            parsed = parse_value_labels_stata(row[VALUE_LABELS_COLUMN])
            if parsed:
                cache[label_id_str] = parsed

    def _one(lid: object) -> dict:
        if lid is None or (isinstance(lid, float) and pd.isna(lid)):
            return {}
        key = str(lid).strip()
        if not key:
            return {}
        return dict(cache.get(key, {}))

    if VALUE_LABEL_ID_COLUMN in df.columns:
        df["value_labels"] = df[VALUE_LABEL_ID_COLUMN].apply(_one)
    else:
        df["value_labels"] = [{} for _ in range(len(df))]
    return df
