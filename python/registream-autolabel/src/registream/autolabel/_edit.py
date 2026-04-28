"""Direct-edit helpers for ``df.attrs[ATTRS_KEY]``.

Ported from the old package (``set_variable_labels`` /
``set_value_labels`` / ``copy_labels`` / ``meta_search`` in
``~/Github/registream/python/src/registream/autolabel.py``). Exposed
both as module-level functions and as ``pd.DataFrame`` shortcuts so
users can write ``df.set_variable_labels({"kon": "Sex"})``.
"""

from __future__ import annotations

import re
from typing import Any, Callable

import pandas as pd

from registream.autolabel._labels import (
    ATTRS_KEY,
    ensure_attrs_initialized,
)

__all__ = [
    "set_variable_labels",
    "set_value_labels",
    "copy_labels",
    "meta_search",
]


def set_variable_labels(
    df: pd.DataFrame,
    labels: str | list[str] | dict[str, str | Callable[[str | None], str]],
    label: str | Callable[[str | None], str] | None = None,
) -> pd.DataFrame:
    """Set or update variable labels in place.

    Accepts three forms, matching the old-package signature:

    - ``set_variable_labels(df, "kon", "Sex")``: single column
    - ``set_variable_labels(df, ["a", "b"], "Same label")``: multiple columns
    - ``set_variable_labels(df, {"kon": "Sex", "kommun": "Municipality"})``
    - ``set_variable_labels(df, "kon", lambda old: (old or "").upper())``

    Returns ``df`` for method chaining.
    """
    ensure_attrs_initialized(df)
    var_labels = df.attrs[ATTRS_KEY]["variable_labels"]

    def _resolve(col: str, candidate: Any) -> str:
        if callable(candidate):
            return candidate(var_labels.get(col))
        return candidate

    if isinstance(labels, str):
        if label is None:
            raise ValueError("label= is required when labels is a single column name.")
        var_labels[labels] = _resolve(labels, label)
    elif isinstance(labels, list):
        if label is None:
            raise ValueError("label= is required when labels is a list of columns.")
        for col in labels:
            var_labels[col] = _resolve(col, label)
    elif isinstance(labels, dict):
        for col, col_label in labels.items():
            var_labels[col] = _resolve(col, col_label)
    else:
        raise TypeError("labels must be a str, list of str, or dict.")

    return df


def set_value_labels(
    df: pd.DataFrame,
    columns: str | list[str] | dict[str, dict],
    value_labels: dict | None = None,
    *,
    overwrite: bool = False,
) -> pd.DataFrame:
    """Set or update value labels for one or more columns in place.

    Accepts:

    - ``set_value_labels(df, "kon", {1: "Man", 2: "Woman"})``
    - ``set_value_labels(df, ["a", "b"], {0: "No", 1: "Yes"})``
    - ``set_value_labels(df, {"kon": {1: "Man", 2: "Woman"}})``

    By default, the new dict is merged into any existing mapping for
    the column. Pass ``overwrite=True`` to replace wholesale.
    """
    ensure_attrs_initialized(df)
    store = df.attrs[ATTRS_KEY]["value_labels"]

    def _assign(col: str, mapping: dict) -> None:
        if overwrite or col not in store:
            store[col] = dict(mapping)
        else:
            store[col] = {**store[col], **mapping}

    if isinstance(columns, str):
        if value_labels is None:
            raise ValueError("value_labels= is required when columns is a single name.")
        _assign(columns, value_labels)
    elif isinstance(columns, list):
        if value_labels is None:
            raise ValueError("value_labels= is required when columns is a list.")
        for col in columns:
            _assign(col, value_labels)
    elif isinstance(columns, dict):
        for col, mapping in columns.items():
            _assign(col, mapping)
    else:
        raise TypeError("columns must be a str, list of str, or dict.")

    return df


def copy_labels(df: pd.DataFrame, source: str, target: str) -> pd.DataFrame:
    """Copy the variable + value label bundle from ``source`` to ``target``.

    Returns ``df`` unchanged; mutates ``df.attrs`` in place. Silent
    no-op if ``source`` has no labels. Does not check that ``target``
    is a real column; calling code may want to copy before the target
    column is materialized.
    """
    if ATTRS_KEY not in df.attrs:
        return df
    attrs = df.attrs[ATTRS_KEY]
    var = attrs.get("variable_labels", {})
    val = attrs.get("value_labels", {})
    if source in var:
        var[target] = var[source]
    if source in val:
        val[target] = dict(val[source])
    return df


def meta_search(
    df: pd.DataFrame,
    pattern: str,
    *,
    include_values: bool = False,
) -> pd.DataFrame:
    """Regex search across column names, variable labels, and value labels.

    Returns a DataFrame (one row per matched column) with columns
    ``variable``, ``label``, ``matched_in``, and (when
    ``include_values=True``) ``value_matches``. The old package
    printed ANSI-colored terminal output; returning a DataFrame is
    more Jupyter-friendly and still readable in a terminal.

    Matching is case-insensitive. Regex metacharacters are supported.
    """
    regex = re.compile(pattern, re.IGNORECASE)
    attrs = df.attrs.get(ATTRS_KEY) if isinstance(df.attrs.get(ATTRS_KEY), dict) else {}
    var_labels = attrs.get("variable_labels", {}) if attrs else {}
    val_labels = attrs.get("value_labels", {}) if attrs else {}

    rows: list[dict[str, Any]] = []
    for col in df.columns:
        name_hit = bool(regex.search(col))
        var_label = var_labels.get(col, "")
        label_hit = bool(var_label) and bool(regex.search(str(var_label)))

        value_hits: list[str] = []
        if include_values and col in val_labels:
            for code, label in val_labels[col].items():
                if regex.search(str(label)):
                    value_hits.append(f"{code}: {label}")

        if not (name_hit or label_hit or value_hits):
            continue

        matched_in: list[str] = []
        if name_hit:
            matched_in.append("name")
        if label_hit:
            matched_in.append("label")
        if value_hits:
            matched_in.append("values")

        rows.append(
            {
                "variable": col,
                "label": var_label,
                "matched_in": ",".join(matched_in),
                "value_matches": "; ".join(value_hits) if value_hits else "",
            }
        )

    columns = ["variable", "label", "matched_in"]
    if include_values:
        columns.append("value_matches")
    if not rows:
        return pd.DataFrame(columns=columns)
    return pd.DataFrame(rows, columns=columns)
