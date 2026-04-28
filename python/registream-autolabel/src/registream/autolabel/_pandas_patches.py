"""Transparent label preservation across common pandas operations.

Patches :meth:`pandas.DataFrame.__setitem__` and
:meth:`pandas.DataFrame.rename` so that variable and value labels follow
the data through the operations users do without thinking: column
assignment and column renaming. Both patches are conditional; they
short-circuit to the original implementation when the DataFrame has no
``attrs[ATTRS_KEY]``, so unlabeled DataFrames are untouched.

Ported from the pre-split package
(``~/Github/registream/python/src/registream/autolabel.py:212-281``) and
adapted to the schema-v2 attrs layout.

Opt out with ``REGISTREAM_NO_PANDAS_PATCH=1`` set before importing
``registream.autolabel``.
"""

from __future__ import annotations

import os

import pandas as pd

from registream.autolabel._labels import ATTRS_KEY

__all__ = ["install_pandas_patches_once"]


_installed: bool = False
_original_setitem = None
_original_rename = None


def install_pandas_patches_once() -> None:
    """Install the label-preserving patches on ``pd.DataFrame``.

    Idempotent. Honors ``REGISTREAM_NO_PANDAS_PATCH=1``.
    """
    global _installed, _original_setitem, _original_rename
    if _installed:
        return
    if _env_flag_set("REGISTREAM_NO_PANDAS_PATCH"):
        _installed = True
        return

    _original_setitem = pd.DataFrame.__setitem__
    _original_rename = pd.DataFrame.rename

    pd.DataFrame.__setitem__ = _label_preserving_setitem  # type: ignore[method-assign]
    pd.DataFrame.rename = _label_preserving_rename  # type: ignore[method-assign]

    _installed = True


def _label_preserving_setitem(self: pd.DataFrame, key, value) -> None:
    """Propagate labels from the source Series onto the new column.

    Mirrors ``_conditional_setitem`` in the old package
    (``autolabel.py:212``). Runs for column assignment of a pandas
    Series whose ``.name`` matches an existing labeled column. For
    non-Series RHS (lists, scalars, ndarrays) it's a straight
    pass-through.
    """
    _original_setitem(self, key, value)

    attrs = self.attrs.get(ATTRS_KEY)
    if not isinstance(attrs, dict):
        return
    if not isinstance(value, pd.Series):
        return

    source = value.name
    if source is None or source == key:
        return

    var_labels = attrs.setdefault("variable_labels", {})
    val_labels = attrs.setdefault("value_labels", {})
    if source in var_labels:
        var_labels[key] = var_labels[source]
    if source in val_labels:
        val_labels[key] = dict(val_labels[source])


def _label_preserving_rename(self: pd.DataFrame, *args, **kwargs):
    """Remap label keys when columns are renamed via a dict mapping.

    Mirrors ``_conditional_rename`` (old ``autolabel.py:234``). Safe for
    ``inplace=True``: updates ``self.attrs`` in that branch instead of
    crashing on a ``None`` return value (bug in the old port).
    """
    if ATTRS_KEY not in self.attrs:
        return _original_rename(self, *args, **kwargs)

    columns = kwargs.get("columns")
    if args and isinstance(args[0], dict):
        columns = args[0]

    inplace = bool(kwargs.get("inplace", False))
    result = _original_rename(self, *args, **kwargs)

    target = self if inplace else result
    if target is None:
        return result

    existing = self.attrs[ATTRS_KEY]
    # Deep-copy the label dicts so the renamed frame owns its own state.
    target_attrs = target.attrs.setdefault(
        ATTRS_KEY,
        {
            "variable_labels": dict(existing.get("variable_labels", {})),
            "value_labels": {
                k: dict(v) for k, v in existing.get("value_labels", {}).items()
            },
        },
    )
    # Copy over the sibling bundle keys (domain, lang, scope, release, …).
    for k, v in existing.items():
        if k not in target_attrs:
            target_attrs[k] = v
    # Schema version sits one level up on df.attrs; preserve it too.
    if "schema_version" in self.attrs and "schema_version" not in target.attrs:
        target.attrs["schema_version"] = self.attrs["schema_version"]

    if not isinstance(columns, dict):
        # Callable / Index rename: keep labels under their original names.
        # The labels won't match the renamed columns but we don't drop
        # information; users can still call `set_variable_labels` to fix.
        return result

    target_attrs["variable_labels"] = {
        columns.get(k, k): v for k, v in target_attrs["variable_labels"].items()
    }
    target_attrs["value_labels"] = {
        columns.get(k, k): v for k, v in target_attrs["value_labels"].items()
    }

    return result


def _env_flag_set(var: str) -> bool:
    return os.environ.get(var, "").strip().lower() in {"1", "true", "yes"}
