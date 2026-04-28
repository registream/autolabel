"""Apply variable and value labels to pandas DataFrames.

Takes a metadata DataFrame (filtered by
:func:`registream.autolabel._filters.filter_metadata`) and stores
labels under ``df.attrs['registream']``::

    df.attrs["registream"] = {
        "variable_labels": {"age": "Age in years", "sex": "Biological sex"},
        "value_labels": {"sex": {1: "Male", 2: "Female"}, ...},
    }
"""

from __future__ import annotations

from typing import Any, Literal

import pandas as pd

__all__ = [
    "ATTRS_KEY",
    "SCHEMA_VERSION_KEY",
    "VARIABLE_NAME_COLUMN",
    "VARIABLE_LABEL_COLUMN",
    "VARIABLE_UNIT_COLUMN",
    "VALUE_LABEL_ID_COLUMN",
    "VALUE_LABELS_COLUMN",
    "LabelType",
    "ensure_attrs_initialized",
    "stamp_registream_attrs",
    "parse_value_labels_stata",
    "apply_variable_labels",
    "apply_value_labels",
    "apply_labels",
    "get_variable_labels",
    "get_value_labels",
]


# The single namespace key under df.attrs where all RegiStream state lives.
ATTRS_KEY = "registream"
# Sibling key holding the schema version that produced the stored labels.
SCHEMA_VERSION_KEY = "schema_version"

# Column names in the metadata DataFrame (Schema 1.0/2.0).
VARIABLE_NAME_COLUMN = "variable_name"
VARIABLE_LABEL_COLUMN = "variable_label"
VARIABLE_UNIT_COLUMN = "variable_unit"
VALUE_LABEL_ID_COLUMN = "value_label_id"
VALUE_LABELS_COLUMN = "value_labels_stata"


LabelType = Literal["variables", "values", "both"]


# ─── Initialization ──────────────────────────────────────────────────────────


def ensure_attrs_initialized(df: pd.DataFrame) -> None:
    """Ensure ``df.attrs[ATTRS_KEY]`` exists with the expected shape.

    Idempotent: safe to call multiple times. Mutates ``df.attrs``.
    """
    if ATTRS_KEY not in df.attrs:
        df.attrs[ATTRS_KEY] = {"variable_labels": {}, "value_labels": {}}
        return
    attrs = df.attrs[ATTRS_KEY]
    if "variable_labels" not in attrs:
        attrs["variable_labels"] = {}
    if "value_labels" not in attrs:
        attrs["value_labels"] = {}


def stamp_registream_attrs(
    df: pd.DataFrame,
    *,
    domain: str,
    lang: str,
    scope: tuple[str, ...] | list[str] | None,
    release: str | None,
    scope_depth: int,
    schema_version: str = "2.0",
) -> None:
    """Record bundle provenance on ``df.attrs``.

    Sets ``df.attrs[SCHEMA_VERSION_KEY]`` and populates
    ``df.attrs[ATTRS_KEY]`` with ``domain``, ``lang``, ``scope``,
    ``release``, and ``scope_depth`` alongside the label dicts. Called
    from the accessor after labels have been applied.
    """
    ensure_attrs_initialized(df)
    df.attrs[SCHEMA_VERSION_KEY] = schema_version
    attrs = df.attrs[ATTRS_KEY]
    attrs["domain"] = domain
    attrs["lang"] = lang
    attrs["scope"] = list(scope) if scope else []
    attrs["release"] = release
    attrs["scope_depth"] = scope_depth


# ─── Stata value-label format parser ──────────────────────────────────────────


def parse_value_labels_stata(s: object) -> dict[Any, str]:
    """Parse a Stata ``value_labels_stata`` string into a ``{code: label}`` dict.

    The on-disk format uses Stata's word-parsing convention: alternating
    code/label tokens, where each token is either a double-quoted string
    (with ``""`` as the escape for an embedded ``"``) or a bare
    whitespace-separated word. Both codes and labels are typically
    double-quoted in the actual metadata::

        "1" "Male" "2" "Female"
        "K" "Woman" "M" "Man" "1" "Man" "2" "Woman"

    The parser also tolerates unquoted codes (``1 "Male"``) and unquoted
    labels (``1 yes``). Codes that parse as integers become ``int`` keys;
    otherwise the key is kept as ``str`` (so a metadata row with
    ``"K" "Kvinna"`` produces ``{"K": "Kvinna"}``).

    Returns an empty dict for ``None``, ``NaN``, or empty input. Tokens
    after the last complete (code, label) pair are silently dropped (this
    matches Stata's ``forval k = 1(2)nwords`` loop which stops at the
    last complete pair).
    """
    if s is None:
        return {}
    if isinstance(s, float) and pd.isna(s):
        return {}

    text = str(s).strip()
    if not text:
        return {}

    tokens = _stata_tokenize(text)

    result: dict[Any, str] = {}
    # Iterate by pairs; an odd trailing token is dropped (matches Stata's
    # `forval k = 1(2)nwords` which only iterates over complete pairs).
    for i in range(0, len(tokens) - 1, 2):
        code_str = tokens[i]
        label = tokens[i + 1]
        try:
            code: Any = int(code_str)
        except ValueError:
            code = code_str
        result[code] = label

    return result


def _stata_tokenize(s: str) -> list[str]:
    """Split a Stata-format string into a list of word tokens.

    A token is either:

    - A double-quoted string (with ``""`` as the escape for an embedded ``"``)
    - A bare whitespace-separated word

    Mirrors Stata's ``word count`` / ``word N of`` behaviour for the
    ``value_labels_stata`` column. The opening and closing quotes are
    consumed; the unescaped content becomes the token text.
    """
    tokens: list[str] = []
    i = 0
    n = len(s)

    while i < n:
        # Skip whitespace between tokens.
        while i < n and s[i].isspace():
            i += 1
        if i >= n:
            break

        if s[i] == '"':
            # Quoted token: read until matching `"`, with `""` as escape.
            i += 1  # consume opening "
            chars: list[str] = []
            while i < n:
                if s[i] == '"':
                    if i + 1 < n and s[i + 1] == '"':
                        # Escaped quote: append one " and skip both.
                        chars.append('"')
                        i += 2
                    else:
                        # Closing quote.
                        i += 1
                        break
                else:
                    chars.append(s[i])
                    i += 1
            tokens.append("".join(chars))
        else:
            # Bare token: read until next whitespace.
            start = i
            while i < n and not s[i].isspace():
                i += 1
            tokens.append(s[start:i])

    return tokens


# ─── Variable label application ───────────────────────────────────────────────


def apply_variable_labels(
    df: pd.DataFrame,
    metadata: pd.DataFrame,
    *,
    variables: list[str] | None = None,
    include_unit: bool = True,
) -> int:
    """Apply variable labels from ``metadata`` to ``df.attrs[ATTRS_KEY]``.

    Mutates ``df.attrs`` in place. Returns the number of labels applied.

    The matching is **case-insensitive** (matches Stata's
    ``replace variable = lower(variable)`` step at line 289 of
    ``autolabel.ado``) but the label is stored under the user's ORIGINAL
    column name (so ``df["Age"]`` and ``df["age"]`` both look up
    ``variable_name="age"`` in metadata, but the result is keyed by the
    original column name in ``df.attrs``).

    :param df: the user's pandas DataFrame.
    :param metadata: variables metadata DataFrame, already filtered to
        one row per ``variable_name`` (call
        :func:`registream.autolabel._filters.filter_metadata` first).
    :param variables: optional restriction list. If ``None``, applies
        labels for all columns in ``df`` that have a metadata entry.
        Names in ``variables`` that are not columns of ``df`` are ignored.
    :param include_unit: if ``True`` (default), append ``" (unit)"`` to
        the label when ``variable_unit`` is non-empty (matches the Stata
        behaviour at line 295: ``var_label = variable_label + " (" + variable_unit + ")"``).
    :return: count of labels applied.
    """
    ensure_attrs_initialized(df)

    if VARIABLE_NAME_COLUMN not in metadata.columns:
        return 0
    if VARIABLE_LABEL_COLUMN not in metadata.columns:
        return 0

    # Build a lowercase → original column name mapping for case-insensitive lookup.
    if variables is None:
        df_vars = {col.lower(): col for col in df.columns}
    else:
        df_vars = {col.lower(): col for col in variables if col in df.columns}

    if not df_vars:
        return 0

    label_dict = df.attrs[ATTRS_KEY]["variable_labels"]
    count = 0

    # Iterate metadata rows; for each one whose lowered name is in df_vars,
    # build the label string and store it under the original column name.
    for _, row in metadata.iterrows():
        var_name = row[VARIABLE_NAME_COLUMN]
        if pd.isna(var_name):
            continue
        var_lower = str(var_name).lower()
        if var_lower not in df_vars:
            continue

        label = row[VARIABLE_LABEL_COLUMN]
        if pd.isna(label):
            continue
        label_str = str(label).strip()
        if not label_str:
            continue

        if include_unit and VARIABLE_UNIT_COLUMN in metadata.columns:
            unit = row.get(VARIABLE_UNIT_COLUMN)
            if pd.notna(unit) and str(unit).strip():
                label_str = f"{label_str} ({str(unit).strip()})"

        original_col_name = df_vars[var_lower]
        label_dict[original_col_name] = label_str
        count += 1

    return count


# ─── Value label application ──────────────────────────────────────────────────


def apply_value_labels(
    df: pd.DataFrame,
    metadata: pd.DataFrame,
    value_labels: pd.DataFrame,
    *,
    variables: list[str] | None = None,
) -> int:
    """Apply value labels to ``df.attrs[ATTRS_KEY]['value_labels']``.

    Two-step lookup mirroring the Stata join at line 418 of ``autolabel.ado``::

        merge 1:1 variable_name using "`var_merge_dta'", keep(1 3) nogen
        merge m:1 value_label_id using "`val_filepath_dta'", keep(1 3) nogen

    1. For each variable in ``df``, find its ``value_label_id`` in
       ``metadata`` (the variables file).
    2. For each ``value_label_id``, find the ``value_labels_stata`` string
       in ``value_labels`` (the value-labels file) and parse it via
       :func:`parse_value_labels_stata`.
    3. Store as ``{column_name: {code: label, ...}}`` under
       ``df.attrs[ATTRS_KEY]["value_labels"]``.

    Mutates ``df.attrs``. Returns the number of variables that received
    a (non-empty) value-label dict.
    """
    ensure_attrs_initialized(df)

    if VARIABLE_NAME_COLUMN not in metadata.columns:
        return 0
    if VALUE_LABEL_ID_COLUMN not in metadata.columns:
        return 0
    if VALUE_LABEL_ID_COLUMN not in value_labels.columns:
        return 0
    if VALUE_LABELS_COLUMN not in value_labels.columns:
        return 0

    # Build value_label_id → parsed_dict cache. We parse once per id even
    # if multiple variables share the same id.
    label_lookup: dict[str, dict[Any, str]] = {}
    for _, row in value_labels.iterrows():
        label_id = row[VALUE_LABEL_ID_COLUMN]
        if pd.isna(label_id):
            continue
        label_id_str = str(label_id).strip()
        if not label_id_str:
            continue
        if label_id_str in label_lookup:
            continue  # already parsed
        labels_str = row[VALUE_LABELS_COLUMN]
        parsed = parse_value_labels_stata(labels_str)
        if parsed:
            label_lookup[label_id_str] = parsed

    if not label_lookup:
        return 0

    # Build df column lookup: lowercase → original.
    if variables is None:
        df_vars = {col.lower(): col for col in df.columns}
    else:
        df_vars = {col.lower(): col for col in variables if col in df.columns}

    if not df_vars:
        return 0

    val_dict = df.attrs[ATTRS_KEY]["value_labels"]
    count = 0

    for _, row in metadata.iterrows():
        var_name = row[VARIABLE_NAME_COLUMN]
        if pd.isna(var_name):
            continue
        var_lower = str(var_name).lower()
        if var_lower not in df_vars:
            continue

        label_id = row[VALUE_LABEL_ID_COLUMN]
        if pd.isna(label_id):
            continue
        label_id_str = str(label_id).strip()
        if not label_id_str:
            continue

        parsed = label_lookup.get(label_id_str)
        if not parsed:
            continue

        original_col_name = df_vars[var_lower]
        val_dict[original_col_name] = dict(parsed)  # copy so callers can't mutate the cache
        count += 1

    return count


# ─── Top-level orchestrator ──────────────────────────────────────────────────


def apply_labels(
    df: pd.DataFrame,
    variables_metadata: pd.DataFrame,
    values_metadata: pd.DataFrame | None = None,
    *,
    label_type: LabelType = "both",
    variables: list[str] | None = None,
    include_unit: bool = True,
) -> tuple[int, int]:
    """Apply variable and/or value labels to a DataFrame.

    Returns ``(variable_labels_applied, value_labels_applied)``.

    :param df: user's DataFrame (mutated in place via ``df.attrs``).
    :param variables_metadata: the variables metadata DataFrame
        (filtered + deduped). Required for both ``"variables"`` and
        ``"values"`` label types because the value-labels lookup goes
        through ``variable_name → value_label_id``.
    :param values_metadata: the value-labels metadata DataFrame.
        Required for ``label_type="values"`` and ``"both"``. Pass
        ``None`` if you only want variable labels.
    :param label_type: ``"variables"``, ``"values"``, or ``"both"``
        (default).
    :param variables: optional restriction list of column names.
    :param include_unit: append unit suffix to variable labels (default True).
    """
    var_count = 0
    val_count = 0

    if label_type in ("variables", "both"):
        var_count = apply_variable_labels(
            df, variables_metadata, variables=variables, include_unit=include_unit
        )

    if label_type in ("values", "both"):
        if values_metadata is None:
            raise ValueError(
                f"label_type={label_type!r} requires `values_metadata` to be provided."
            )
        val_count = apply_value_labels(
            df, variables_metadata, values_metadata, variables=variables
        )

    return var_count, val_count


# ─── Accessors (read-only public API) ─────────────────────────────────────────


def get_variable_labels(df: pd.DataFrame) -> dict[str, str]:
    """Return a copy of the variable labels dict from ``df.attrs[ATTRS_KEY]``.

    Returns an empty dict if no labels have been applied. The returned
    dict is a shallow copy; mutating it does not affect ``df.attrs``.
    """
    if ATTRS_KEY not in df.attrs:
        return {}
    return dict(df.attrs[ATTRS_KEY].get("variable_labels", {}))


def get_value_labels(df: pd.DataFrame) -> dict[str, dict[Any, str]]:
    """Return a copy of the value labels dict from ``df.attrs[ATTRS_KEY]``.

    Returns ``{column_name: {code: label, ...}}``. Empty dict if no
    labels have been applied. Two levels of shallow copy.
    """
    if ATTRS_KEY not in df.attrs:
        return {}
    raw = df.attrs[ATTRS_KEY].get("value_labels", {})
    return {k: dict(v) for k, v in raw.items()}
