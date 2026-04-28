"""LabeledView: display-time code-to-label substitution for ``df.rs.lab``.

A view wrapper that substitutes value codes with their labels using
``df.attrs['registream']['value_labels']``. The underlying DataFrame
is **not** mutated. Only value labels are substituted; column names
stay as their short codes.
"""

from __future__ import annotations

from typing import Any

import pandas as pd

from registream.autolabel._labels import ATTRS_KEY

__all__ = ["LabeledView"]


class LabeledView:
    """Display-time labeled view of a DataFrame.

    Wraps a DataFrame and substitutes value codes with their labels at
    display time, without mutating the wrapped data. Use ``df.rs.lab``
    to construct one (via the accessor; final Phase 2 checkpoint).

    Common usage::

        df.rs.lab               # full labeled view
        df.rs.lab.head()        # first 5 rows, labeled
        df.rs.lab.tail()        # last 5 rows, labeled
        df.rs.lab.sample(10)    # random 10 rows, labeled
        df.rs.lab.as_dataframe() # extract as a regular pandas DataFrame

    The displayed values come from substituting ``int`` / ``str`` codes
    using the dict at ``df.attrs['registream']['value_labels'][col]``.
    Codes that aren't in the dict are left as-is.
    """

    def __init__(self, df: pd.DataFrame) -> None:
        self._df = df
        # Lazy install of the seaborn wrapper so ``sns.barplot(data=df.rs.lab, ...)``
        # picks up the labels automatically. No-op if seaborn isn't installed.
        from registream.autolabel._seaborn import patch_plotting_libraries_once

        patch_plotting_libraries_once()

    # ─── Duck-type enough DataFrame surface to pass through seaborn ──────────
    # Seaborn's `data=` accepts anything that behaves like a DataFrame. The
    # monkey-patched functions unwrap ``self._df`` before calling the
    # underlying seaborn implementation, but the initial argument validation
    # still inspects ``data``; these forwards keep that validation happy.

    def __getitem__(self, key):
        """Labeled column / sub-DataFrame access.

        - ``df.rs.lab["kon"]`` → a :class:`~pandas.Series` named after the
          variable label, with value codes substituted where a value-label
          mapping exists.
        - ``df.rs.lab[["kon", "age"]]`` → a DataFrame with both columns
          substituted, named after their variable labels.
        - Any other key (boolean mask, slice, …) falls through to the
          underlying DataFrame.
        """
        if isinstance(key, str) and key in self._df.columns:
            return self._labeled_series(key)
        if isinstance(key, list) and all(
            isinstance(k, str) for k in key
        ):
            cols = [k for k in key if k in self._df.columns]
            if len(cols) == len(key):
                return self._labeled_subframe(cols)
        return self._df[key]

    def __contains__(self, key) -> bool:
        return key in self._df

    def __iter__(self):
        return iter(self._df)

    def keys(self):
        return self._df.keys()

    # ─── Attribute fallback: labeled Series or labeled DataFrame methods ─────

    def __getattr__(self, attr: str):
        """Route attribute access through the labeled view.

        - ``df.rs.lab.kon`` returns a labeled :class:`~pandas.Series`
          (same shape as ``df.rs.lab["kon"]``).
        - Any other attribute (e.g. ``describe``, ``corr``, ``to_csv``)
          is looked up on a copy of the DataFrame whose columns have
          been renamed to their variable labels, so the result comes
          out with human-readable names.
        - Falls back to the raw DataFrame on the very last miss.

        ``__getattr__`` only fires when normal attribute resolution
        fails, so methods defined on :class:`LabeledView` (``head``,
        ``tail``, ``as_dataframe``, …) take precedence.
        """
        # Avoid infinite recursion for pickling / dataclass probes.
        if attr.startswith("__") and attr.endswith("__"):
            raise AttributeError(attr)

        df = object.__getattribute__(self, "_df")
        if attr in df.columns:
            return self._labeled_series(attr)

        var_labels = _var_labels_of(df)
        if var_labels:
            renamed = df.rename(columns=var_labels)
            if hasattr(renamed, attr):
                return getattr(renamed, attr)
        if hasattr(df, attr):
            return getattr(df, attr)
        raise AttributeError(attr)

    # ─── Plot wrapper (delegates to the labeled DataFrame's plot) ────────────

    def plot(self, *args, **kwargs):
        """Call ``DataFrame.plot`` on the labeled view.

        Substitutes value labels onto categorical columns (same rule as
        seaborn: skip substitution when the column is the x-axis of a
        line/scatter-like plot) and sets the x/y axis titles from
        :attr:`variable_labels` after the plot returns.
        """
        kind = kwargs.get("kind", "line")
        x_param = kwargs.get("x")
        y_param = kwargs.get("y")
        from registream.autolabel._seaborn import _NUMERIC_X_AXIS_PLOT_FUNCS

        numeric_x_kinds = {"line", "scatter", "hexbin", "area"}
        keep_x_numeric = kind in numeric_x_kinds or f"{kind}plot" in _NUMERIC_X_AXIS_PLOT_FUNCS

        labeled_df = self._labeled_df_for_plot(
            x_param if keep_x_numeric else None
        )
        ax = labeled_df.plot(*args, **kwargs)

        var_labels = _var_labels_of(self._df)
        if x_param and x_param in var_labels and hasattr(ax, "set_xlabel"):
            ax.set_xlabel(var_labels[x_param])
        if y_param and y_param in var_labels and hasattr(ax, "set_ylabel"):
            ax.set_ylabel(var_labels[y_param])
        return ax

    # ─── Display hooks ────────────────────────────────────────────────────────

    def __repr__(self) -> str:
        return repr(self._labeled_df())

    def _repr_html_(self) -> str:
        """Jupyter HTML hook, used by notebook frontends for rich display."""
        labeled = self._labeled_df()
        html = getattr(labeled, "_repr_html_", None)
        if html is not None:
            result = html()
            if isinstance(result, str):
                return result
        return repr(labeled)

    # ─── DataFrame-like row selectors ─────────────────────────────────────────

    def head(self, n: int = 5) -> "LabeledView":
        """Return a :class:`LabeledView` of the first ``n`` rows."""
        return LabeledView(self._df.head(n))

    def tail(self, n: int = 5) -> "LabeledView":
        """Return a :class:`LabeledView` of the last ``n`` rows."""
        return LabeledView(self._df.tail(n))

    def sample(self, n: int = 5, **kwargs: Any) -> "LabeledView":
        """Return a :class:`LabeledView` of a random sample of ``n`` rows.

        ``**kwargs`` is forwarded to :meth:`pandas.DataFrame.sample`
        (e.g., ``random_state=42`` for deterministic sampling in tests).
        """
        return LabeledView(self._df.sample(n=n, **kwargs))

    # ─── Extraction ───────────────────────────────────────────────────────────

    def as_dataframe(self) -> pd.DataFrame:
        """Return a copy of the underlying DataFrame with value codes substituted.

        Use this when you want to extract the labeled view into a normal
        :class:`pandas.DataFrame` for further chaining, saving to CSV,
        passing to a plotting library, etc. The original DataFrame held
        by this view is not modified.
        """
        return self._labeled_df()

    # ─── Convenience properties ───────────────────────────────────────────────

    @property
    def shape(self) -> tuple[int, int]:
        """Forward to the underlying DataFrame's shape."""
        return self._df.shape

    @property
    def columns(self) -> pd.Index:
        """Forward to the underlying DataFrame's columns."""
        return self._df.columns

    def __len__(self) -> int:
        return len(self._df)

    # ─── Internal: build the labeled DataFrame ────────────────────────────────

    def _labeled_series(self, col: str) -> pd.Series:
        """Return a Series with value codes substituted and name set to the label."""
        var_labels = _var_labels_of(self._df)
        val_labels = _val_labels_of(self._df)
        series = self._df[col].copy()
        mapping = val_labels.get(col)
        if mapping:
            lookup = _expand_code_keys(mapping)
            mapped = series.map(lookup)
            series = mapped.where(mapped.notna(), series)
        series.name = var_labels.get(col, col)
        return series

    def _labeled_subframe(self, cols: list[str]) -> pd.DataFrame:
        """Return a DataFrame containing only ``cols``, with labels applied."""
        var_labels = _var_labels_of(self._df)
        val_labels = _val_labels_of(self._df)
        out = self._df[cols].copy()
        for col in cols:
            mapping = val_labels.get(col)
            if mapping:
                lookup = _expand_code_keys(mapping)
                mapped = out[col].map(lookup)
                out[col] = mapped.where(mapped.notna(), out[col])
        rename_map = {c: var_labels[c] for c in cols if c in var_labels}
        if rename_map:
            out = out.rename(columns=rename_map)
        return out

    def _labeled_df_for_plot(self, skip_column: str | None) -> pd.DataFrame:
        """Return a DataFrame copy with substitutions applied, except ``skip_column``."""
        val_labels = _val_labels_of(self._df)
        out = self._df.copy()
        for col, mapping in val_labels.items():
            if col not in out.columns or col == skip_column or not mapping:
                continue
            lookup = _expand_code_keys(mapping)
            mapped = out[col].map(lookup)
            out[col] = mapped.where(mapped.notna(), out[col])
        return out

    def _labeled_df(self) -> pd.DataFrame:
        """Build a copy of the wrapped DataFrame with value codes substituted.

        Algorithm:

        1. Make a shallow copy of the underlying DataFrame.
        2. For each ``(col, code_to_label)`` in ``df.attrs[ATTRS_KEY]['value_labels']``:
           - Skip if ``col`` is not actually in the DataFrame's columns.
           - Use :meth:`pandas.Series.map` to substitute codes with labels.
           - Use :meth:`pandas.Series.fillna` with the original column to
             preserve values that aren't in the label dict (e.g., missing
             codes, sentinel values, codes not in the metadata).
        3. Return the labeled copy.

        Round-tripping: this method is idempotent on the wrapped data; it
        always returns a fresh copy and never mutates ``self._df``.
        """
        if ATTRS_KEY not in self._df.attrs:
            return self._df.copy()

        attrs = self._df.attrs.get(ATTRS_KEY, {})
        value_labels = attrs.get("value_labels", {}) if isinstance(attrs, dict) else {}

        if not value_labels:
            return self._df.copy()

        labeled = self._df.copy()
        for col, code_to_label in value_labels.items():
            if col not in labeled.columns:
                continue
            if not code_to_label:
                continue
            lookup = _expand_code_keys(code_to_label)
            mapped = labeled[col].map(lookup)
            # fillna() restores the original value for codes not in the label dict.
            labeled[col] = mapped.where(mapped.notna(), labeled[col])

        return labeled


def _var_labels_of(df: pd.DataFrame) -> dict:
    attrs = df.attrs.get(ATTRS_KEY)
    if not isinstance(attrs, dict):
        return {}
    return attrs.get("variable_labels") or {}


def _val_labels_of(df: pd.DataFrame) -> dict:
    attrs = df.attrs.get(ATTRS_KEY)
    if not isinstance(attrs, dict):
        return {}
    return attrs.get("value_labels") or {}


def _expand_code_keys(code_to_label: dict) -> dict:
    """Return a dict with both raw and string-coerced versions of each key.

    Value-label metadata encodes codes as ``int`` whenever they are
    int-parseable (see :func:`parse_value_labels_stata`), but the
    user's data may carry the same code as a zero-padded string (e.g.
    ``"00"``, ``"01"``) or as an untyped string (``"1"``). Indexing
    against both representations keeps the map robust to Stata's
    mixed numeric / string-categorical conventions without forcing a
    dtype conversion on the underlying column.
    """
    expanded: dict = {}
    for raw_code, label in code_to_label.items():
        expanded[raw_code] = label
        if isinstance(raw_code, int):
            expanded.setdefault(str(raw_code), label)
            # zero-padded variants (2-digit and 3-digit are the common
            # SCB/SSB formatting widths).
            expanded.setdefault(f"{raw_code:02d}", label)
            expanded.setdefault(f"{raw_code:03d}", label)
        elif isinstance(raw_code, str):
            try:
                expanded.setdefault(int(raw_code), label)
            except ValueError:
                pass
    return expanded
