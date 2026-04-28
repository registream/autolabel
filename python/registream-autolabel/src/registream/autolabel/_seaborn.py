"""Lazy seaborn + ``pandas.DataFrame.plot`` integration.

When a :class:`LabeledView` is constructed (or any registream-labeled
DataFrame is passed through ``data=``), this module wraps the common
seaborn plotting functions so that value labels are substituted on
categorical axes and variable labels flow into axis titles and legend.

Ports the "autolabel just works in plots" behavior from the pre-split
``~/Github/registream/python/src/registream/autolabel.py`` (the seaborn
monkey-patch block starting at line 683).

Design choices:

- **Lazy import**: seaborn is optional. If it isn't installed, the
  patching silently no-ops.
- **Idempotent**: patching runs at most once per interpreter.
- **Opt-out**: ``REGISTREAM_NO_PLOT_PATCH=1`` disables the wrapper.
- **Accepts two input shapes**: ``data=df.rs.lab`` (a :class:`LabeledView`)
  *or* ``data=df`` where ``df`` has already been labeled via
  ``df.rs.autolabel(...)``. Both cases flow into the same code path.
- **Scatter / line x-axis kept numeric**: substituting value labels on
  the x-axis of a scatter or line plot would render "Year 2005" as a
  category, breaking time-series layouts. We skip x-axis substitution
  for those plot types and keep the raw values.
"""

from __future__ import annotations

import os
from functools import wraps

import pandas as pd

from registream.autolabel._labels import ATTRS_KEY

__all__ = ["patch_plotting_libraries_once"]


_SEABORN_FUNCTIONS_TO_PATCH: tuple[str, ...] = (
    "scatterplot",
    "lineplot",
    "barplot",
    "boxplot",
    "violinplot",
    "stripplot",
    "swarmplot",
    "countplot",
    "histplot",
    "kdeplot",
    "ecdfplot",
    "heatmap",
    "relplot",
    "lmplot",
    "regplot",
    "residplot",
)

_NUMERIC_X_AXIS_PLOT_FUNCS: frozenset[str] = frozenset({"scatterplot", "lineplot"})

_patched: bool = False


def patch_plotting_libraries_once() -> None:
    """Wrap seaborn's public plotting functions with label-aware versions.

    Safe to call many times. Honors ``REGISTREAM_NO_PLOT_PATCH=1``.
    Silently no-ops when seaborn is not installed; the rest of
    autolabel remains usable.
    """
    global _patched
    if _patched:
        return
    if _env_flag_set("REGISTREAM_NO_PLOT_PATCH"):
        _patched = True
        return
    try:
        import seaborn as sns
    except ImportError:
        _patched = True
        return

    for name in _SEABORN_FUNCTIONS_TO_PATCH:
        original = getattr(sns, name, None)
        if original is None:
            continue
        setattr(sns, name, _wrap_seaborn_func(original, name))

    _patched = True


def _wrap_seaborn_func(original, func_name: str):
    @wraps(original)
    def wrapped(*args, **kwargs):
        data = kwargs.get("data")
        unwrapped = _unwrap_if_labeled(data)
        if unwrapped is None:
            return original(*args, **kwargs)

        df, var_labels, val_labels = unwrapped
        x_param = kwargs.get("x")
        y_param = kwargs.get("y")
        hue_param = kwargs.get("hue")

        df_for_plot = _apply_value_labels_for_plot(
            df, val_labels, func_name, x_param, y_param, hue_param
        )
        kwargs["data"] = df_for_plot

        ax = original(*args, **kwargs)

        _apply_axis_labels(ax, x_param, y_param, hue_param, var_labels, val_labels)
        return ax

    return wrapped


def _unwrap_if_labeled(data):
    """Return ``(df, var_labels, val_labels)`` if ``data`` carries labels, else ``None``.

    Accepts a :class:`LabeledView`, or a plain DataFrame with
    ``attrs[ATTRS_KEY]`` populated. Lazy import of LabeledView avoids
    a circular dependency.
    """
    from registream.autolabel._repr import LabeledView

    if data is None:
        return None
    if isinstance(data, LabeledView):
        df = data._df
    elif isinstance(data, pd.DataFrame):
        df = data
    else:
        return None

    attrs = df.attrs.get(ATTRS_KEY)
    if not isinstance(attrs, dict):
        return None
    var_labels = attrs.get("variable_labels") or {}
    val_labels = attrs.get("value_labels") or {}
    if not var_labels and not val_labels:
        return None
    return df, var_labels, val_labels


def _apply_value_labels_for_plot(
    df: pd.DataFrame,
    val_labels: dict,
    func_name: str,
    x_param,
    y_param,
    hue_param,
) -> pd.DataFrame:
    """Return a copy of ``df`` with value labels substituted where sensible."""
    if not val_labels:
        return df

    df_for_plot = df.copy()
    for col, mapping in val_labels.items():
        if col not in df_for_plot.columns or not mapping:
            continue
        if col == x_param and func_name in _NUMERIC_X_AXIS_PLOT_FUNCS:
            # Keep the x-axis numeric for continuous-looking categoricals
            # (e.g. years) in scatter / line plots.
            continue
        lookup = _expand_code_keys(mapping)
        mapped = df_for_plot[col].map(lookup)
        df_for_plot[col] = mapped.where(mapped.notna(), df_for_plot[col])
    return df_for_plot


def _apply_axis_labels(
    ax,
    x_param,
    y_param,
    hue_param,
    var_labels: dict,
    val_labels: dict,
) -> None:
    """Populate axis titles + legend from variable / value labels."""
    if ax is None:
        return
    if x_param and x_param in var_labels and hasattr(ax, "set_xlabel"):
        ax.set_xlabel(var_labels[x_param])
    if y_param and y_param in var_labels and hasattr(ax, "set_ylabel"):
        ax.set_ylabel(var_labels[y_param])
    if hue_param and hasattr(ax, "get_legend"):
        legend = ax.get_legend()
        if legend is not None:
            if hue_param in var_labels:
                legend.set_title(var_labels[hue_param])
            mapping = val_labels.get(hue_param) or {}
            if mapping:
                lookup = _expand_code_keys(mapping)
                for text in legend.get_texts():
                    original = text.get_text()
                    substituted = _substitute_text(original, lookup)
                    if substituted is not None:
                        text.set_text(substituted)


def _substitute_text(original: str, lookup: dict):
    """Resolve a legend text cell against a label mapping in its various types."""
    if original in lookup:
        return lookup[original]
    try:
        as_int = int(original)
    except (TypeError, ValueError):
        return None
    return lookup.get(as_int)


def _expand_code_keys(code_to_label: dict) -> dict:
    """Mirror of ``_repr._expand_code_keys`` for the seaborn path.

    Duplicated locally to keep this module importable without triggering
    the ``_repr`` import, avoiding a circular on package startup.
    """
    expanded: dict = {}
    for raw_code, label in code_to_label.items():
        expanded[raw_code] = label
        if isinstance(raw_code, int):
            expanded.setdefault(str(raw_code), label)
            expanded.setdefault(f"{raw_code:02d}", label)
            expanded.setdefault(f"{raw_code:03d}", label)
        elif isinstance(raw_code, str):
            try:
                expanded.setdefault(int(raw_code), label)
            except ValueError:
                pass
    return expanded


def _env_flag_set(var: str) -> bool:
    return os.environ.get(var, "").strip().lower() in {"1", "true", "yes"}
