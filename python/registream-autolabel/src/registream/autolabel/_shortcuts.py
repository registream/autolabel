"""Monkey-patch lambdas that expose ``df.rs.X`` and helper functions as ``df.X``.

Both namespaces point at the same functionality, differing only in
discoverability (``df.rs.autolabel`` lives under the accessor; the
shortcut installs ``df.autolabel`` on :class:`pandas.DataFrame`
directly). Every shortcut is a thin lambda; the accessor remains the
single source of truth.

In addition to the main autolabel / lookup / label-reader shortcuts,
this module installs direct editors (``set_variable_labels``,
``set_value_labels``, ``copy_labels``, ``meta_search``) ported from the
pre-split package so users can mutate label state without going through
the accessor.
"""

from __future__ import annotations

import os

import pandas as pd

from registream.autolabel._edit import (
    copy_labels,
    meta_search,
    set_value_labels,
    set_variable_labels,
)
from registream.autolabel._labels import (
    get_value_labels as _get_value_labels_fn,
    get_variable_labels as _get_variable_labels_fn,
)

__all__ = [
    "SHORTCUT_NAMES",
    "install_shortcuts",
    "are_shortcuts_installed",
]


SHORTCUT_NAMES: tuple[str, ...] = (
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
)


def install_shortcuts() -> None:
    """Install monkey-patch shortcuts on :class:`pandas.DataFrame`.

    Idempotent. Safe to call multiple times. Honors
    ``REGISTREAM_NO_SHORTCUTS=1``: when set, no shortcuts are installed
    and the accessor (``df.rs``) is the only entry point.
    """
    if os.environ.get("REGISTREAM_NO_SHORTCUTS", "").lower() in ("1", "true"):
        return
    pd.DataFrame.autolabel = lambda self, *args, **kwargs: self.rs.autolabel(  # type: ignore[attr-defined]
        *args, **kwargs
    )
    pd.DataFrame.lookup = lambda self, *args, **kwargs: self.rs.lookup(  # type: ignore[attr-defined]
        *args, **kwargs
    )
    # `lab` is a property on the accessor; expose it as a property on
    # DataFrame too so `df.lab.head()` reads like `df.rs.lab.head()` (no parens).
    pd.DataFrame.lab = property(lambda self: self.rs.lab)  # type: ignore[attr-defined]
    pd.DataFrame.variable_labels = lambda self: self.rs.variable_labels()  # type: ignore[attr-defined]
    pd.DataFrame.value_labels = lambda self: self.rs.value_labels()  # type: ignore[attr-defined]
    pd.DataFrame.get_variable_labels = lambda self, columns=None: _lookup_var_labels(self, columns)  # type: ignore[attr-defined]
    pd.DataFrame.get_value_labels = lambda self, columns=None: _lookup_val_labels(self, columns)  # type: ignore[attr-defined]
    pd.DataFrame.set_variable_labels = set_variable_labels  # type: ignore[attr-defined]
    pd.DataFrame.set_value_labels = set_value_labels  # type: ignore[attr-defined]
    pd.DataFrame.copy_labels = copy_labels  # type: ignore[attr-defined]
    pd.DataFrame.meta_search = meta_search  # type: ignore[attr-defined]


def are_shortcuts_installed() -> bool:
    """Return ``True`` if all shortcut methods are on ``pd.DataFrame``."""
    return all(hasattr(pd.DataFrame, name) for name in SHORTCUT_NAMES)


def _lookup_var_labels(df: pd.DataFrame, columns):
    """Column-aware lookup over the variable-label dict.

    - ``columns=None`` → full dict
    - ``columns="kon"`` → single label string (or ``None``)
    - ``columns=["a", "b"]`` → filtered dict
    """
    full = _get_variable_labels_fn(df)
    if columns is None:
        return full
    if isinstance(columns, str):
        return full.get(columns)
    if isinstance(columns, list):
        return {c: full[c] for c in columns if c in full}
    raise TypeError("columns must be None, str, or list[str].")


def _lookup_val_labels(df: pd.DataFrame, columns):
    full = _get_value_labels_fn(df)
    if columns is None:
        return full
    if isinstance(columns, str):
        return full.get(columns)
    if isinstance(columns, list):
        return {c: full[c] for c in columns if c in full}
    raise TypeError("columns must be None, str, or list[str].")
