"""Pandas accessor for register data labeling: ``df.rs``.

Registered via ``@pd.api.extensions.register_dataframe_accessor("rs")``
so every :class:`pandas.DataFrame` gets a ``.rs`` attribute. The
methods are thin wrappers over the functional pipeline:

    load_bundle → filter_bundle → collapse_to_one_per_variable →
    apply_labels → stamp_registream_attrs
"""

from __future__ import annotations

import logging
import warnings
from pathlib import Path

import pandas as pd

from dataclasses import dataclass, field

from registream.autolabel._collapse import collapse_to_one_per_variable
from registream.autolabel._filters import filter_bundle
from registream.autolabel._labels import (
    LabelType,
    apply_labels,
    get_value_labels,
    get_variable_labels,
    stamp_registream_attrs,
)
from registream.autolabel._lookup import LookupResult
from registream.autolabel._lookup import lookup as _lookup_fn
from registream.autolabel._repr import LabeledView
from registream.metadata import load_bundle

__all__ = ["RsAccessor", "DryRunResult"]


@dataclass
class DryRunResult:
    """Preview of what :meth:`RsAccessor.autolabel` would stamp.

    Returned when ``dryrun=True``; the DataFrame's ``attrs`` stay
    untouched so callers can inspect the planned changes.
    """

    variable_labels: dict = field(default_factory=dict)
    value_labels: dict = field(default_factory=dict)
    skipped_vars: list = field(default_factory=list)
    resolved_scope: tuple | None = None
    resolved_release: str | None = None

    def __repr__(self) -> str:
        return (
            f"DryRunResult(variable_labels={len(self.variable_labels)}, "
            f"value_labels={len(self.value_labels)}, "
            f"skipped_vars={len(self.skipped_vars)}, "
            f"resolved_scope={self.resolved_scope}, "
            f"resolved_release={self.resolved_release!r})"
        )

_log = logging.getLogger("registream.autolabel.accessor")


@pd.api.extensions.register_dataframe_accessor("rs")
class RsAccessor:
    """The ``df.rs`` namespace: register data labeling for pandas DataFrames."""

    def __init__(self, df: pd.DataFrame) -> None:
        self._df = df

    def autolabel(
        self,
        domain: str = "scb",
        lang: str = "eng",
        *,
        scope: list[str] | tuple[str, ...] | None = None,
        release: str | None = None,
        label_type: LabelType = "both",
        variables: list[str] | None = None,
        exclude: list[str] | None = None,
        include_unit: bool = True,
        dryrun: bool = False,
        directory: Path | str | None = None,
    ) -> pd.DataFrame | DryRunResult:
        """Apply variable + value labels from the metadata cache to this DataFrame.

        Mirrors Stata ``autolabel variables/values, domain() lang()
        scope() release() exclude() dryrun``. Labels are stored under
        ``df.attrs["registream"]``; the column data is not mutated.

        When ``scope`` is ``None``, the best-matching scope is inferred
        from the dataset's column names. Pass an explicit
        ``scope=["LISA", "Individuals 16+"]`` to override.

        The overflow-token rule applies: when ``len(scope) == scope_depth + 1``
        and ``release is None``, the last token is promoted to ``release``.

        :param exclude: column names to skip when applying labels. Applied
            after ``variables``; supports the Stata ``exclude()`` option.
        :param dryrun: return a :class:`DryRunResult` describing what
            would be stamped without mutating ``df.attrs``.
        """
        bundle = load_bundle(domain, lang, directory=directory)

        datavars = list(self._df.columns)
        filtered = filter_bundle(
            bundle,
            scope=list(scope) if scope else None,
            release=release,
            datavars=datavars if not scope else None,
        )

        if filtered.inferred is not None and filtered.inferred.has_strong_primary:
            _log.info(
                "Auto-detected scope: %s (%d%% match)",
                " / ".join(filtered.inferred.levels),
                filtered.inferred.match_pct,
            )

        collapsed = collapse_to_one_per_variable(filtered, bundle)

        effective_vars = _resolve_target_columns(
            self._df, variables, exclude
        )

        if dryrun:
            result = _plan_label_stamps(
                self._df,
                collapsed,
                filtered.value_labels if label_type in ("values", "both") else None,
                label_type=label_type,
                variables=effective_vars,
                include_unit=include_unit,
            )
            result.resolved_scope = filtered.resolved_scope or (
                filtered.inferred.levels if filtered.inferred else None
            )
            result.resolved_release = (
                filtered.resolved_release or filtered.auto_drilled_release
            )
            return result

        apply_labels(
            self._df,
            collapsed,
            filtered.value_labels if label_type in ("values", "both") else None,
            label_type=label_type,
            variables=effective_vars,
            include_unit=include_unit,
        )

        resolved_scope = filtered.resolved_scope or (
            filtered.inferred.levels if filtered.inferred else None
        )
        stamp_registream_attrs(
            self._df,
            domain=domain,
            lang=lang,
            scope=resolved_scope,
            release=filtered.resolved_release or filtered.auto_drilled_release,
            scope_depth=bundle.manifest.scope_depth,
        )

        _emit_usage_and_updates(
            command=_fmt_autolabel_cmd(domain, lang, scope, release, label_type),
            domain=domain,
            lang=lang,
            directory=directory,
        )

        return self._df

    def lookup(
        self,
        variables: str | list[str] | None = None,
        *,
        domain: str = "scb",
        lang: str = "eng",
        scope: list[str] | tuple[str, ...] | None = None,
        release: str | None = None,
        detail: bool = False,
        directory: Path | str | None = None,
    ) -> LookupResult:
        """Look up metadata for one or more variables.

        Pass a variable name or list. ``scope`` / ``release`` narrow the
        search to a specific scope atom (same semantics as
        :meth:`autolabel`).
        """
        if variables is None:
            raise ValueError(
                "lookup() requires a variable name or list of names. "
                "To browse the catalog, call registream.autolabel.scope(...)."
            )

        bundle = load_bundle(domain, lang, directory=directory)
        filtered = filter_bundle(
            bundle,
            scope=list(scope) if scope else None,
            release=release,
        )

        result = _lookup_fn(variables, bundle, filtered, detail=detail)

        _emit_usage_and_updates(
            command=_fmt_lookup_cmd(variables, domain, lang, scope, release, detail),
            domain=domain,
            lang=lang,
            directory=directory,
        )
        return result

    @property
    def lab(self) -> LabeledView:
        """A :class:`LabeledView` over this DataFrame for display-time labeling."""
        return LabeledView(self._df)

    def variable_labels(self) -> dict[str, str]:
        """Return a copy of the variable labels dict from ``df.attrs``."""
        return get_variable_labels(self._df)

    def value_labels(self) -> dict[str, dict]:
        """Return a copy of the value labels dict from ``df.attrs``."""
        return get_value_labels(self._df)


def _resolve_target_columns(
    df: pd.DataFrame,
    variables: list[str] | None,
    exclude: list[str] | None,
) -> list[str] | None:
    """Combine ``variables`` and ``exclude`` into the final target column list.

    Returns ``None`` when no restriction is needed (caller labels every
    matching column in the DataFrame). Unknown column names are silently
    dropped (mirrors the Stata behaviour that expands / filters the
    varlist at the dispatcher level).
    """
    if variables is None and not exclude:
        return None
    base = [c for c in (variables if variables is not None else df.columns) if c in df.columns]
    if exclude:
        excluded = set(exclude)
        base = [c for c in base if c not in excluded]
    return base


def _plan_label_stamps(
    df: pd.DataFrame,
    variables_metadata: pd.DataFrame,
    values_metadata: pd.DataFrame | None,
    *,
    label_type: LabelType,
    variables: list[str] | None,
    include_unit: bool,
) -> DryRunResult:
    """Build a DryRunResult mirror of what ``apply_labels`` would stamp."""
    import pandas as _pd

    if variables is None:
        target_cols = {col.lower(): col for col in df.columns}
    else:
        target_cols = {col.lower(): col for col in variables if col in df.columns}

    planned_var: dict[str, str] = {}
    skipped: list[str] = []

    if label_type in ("variables", "both") and "variable_name" in variables_metadata.columns:
        for _, row in variables_metadata.iterrows():
            raw_name = row["variable_name"]
            if _pd.isna(raw_name):
                continue
            key = str(raw_name).lower()
            if key not in target_cols:
                continue
            label = row.get("variable_label")
            if label is None or _pd.isna(label) or str(label).strip() == "":
                skipped.append(target_cols[key])
                continue
            label_str = str(label).strip()
            if include_unit:
                unit = row.get("variable_unit")
                if unit is not None and _pd.notna(unit) and str(unit).strip():
                    label_str = f"{label_str} ({str(unit).strip()})"
            planned_var[target_cols[key]] = label_str

    planned_val: dict[str, dict] = {}
    if (
        label_type in ("values", "both")
        and values_metadata is not None
        and "value_label_id" in variables_metadata.columns
    ):
        from registream.autolabel._labels import parse_value_labels_stata

        # Collect only the value_label_ids actually referenced by target
        # columns; parsing every row of values_metadata is O(n) in the full
        # bundle (~12k rows for SCB) and dominates wall-time on real data.
        needed_lids: set[str] = set()
        for _, row in variables_metadata.iterrows():
            raw_name = row["variable_name"]
            if _pd.isna(raw_name):
                continue
            if str(raw_name).lower() not in target_cols:
                continue
            lid = row.get("value_label_id")
            if lid is None or _pd.isna(lid):
                continue
            key = str(lid).strip()
            if key:
                needed_lids.add(key)

        id_to_mapping: dict[str, dict] = {}
        if needed_lids:
            lid_series = values_metadata["value_label_id"].astype(str).str.strip()
            sub = values_metadata[lid_series.isin(needed_lids)]
            for _, row in sub.iterrows():
                lid = row.get("value_label_id")
                if lid is None or _pd.isna(lid):
                    continue
                key = str(lid).strip()
                if not key or key in id_to_mapping:
                    continue
                parsed = parse_value_labels_stata(row.get("value_labels_stata"))
                if parsed:
                    id_to_mapping[key] = parsed

        for _, row in variables_metadata.iterrows():
            raw_name = row["variable_name"]
            if _pd.isna(raw_name):
                continue
            key = str(raw_name).lower()
            if key not in target_cols:
                continue
            lid = row.get("value_label_id")
            if lid is None or _pd.isna(lid):
                continue
            mapping = id_to_mapping.get(str(lid).strip())
            if mapping:
                planned_val[target_cols[key]] = dict(mapping)

    return DryRunResult(
        variable_labels=planned_var,
        value_labels=planned_val,
        skipped_vars=sorted(set(skipped)),
    )


def _fmt_autolabel_cmd(
    domain: str,
    lang: str,
    scope: list[str] | tuple[str, ...] | None,
    release: str | None,
    label_type: LabelType,
) -> str:
    parts = [f"autolabel domain={domain} lang={lang}"]
    if label_type != "both":
        parts.append(f"label_type={label_type}")
    if scope:
        parts.append("scope=" + ",".join(f'"{s}"' for s in scope))
    if release is not None:
        parts.append(f"release={release}")
    return " ".join(parts)


def _fmt_lookup_cmd(
    variables: str | list[str],
    domain: str,
    lang: str,
    scope: list[str] | tuple[str, ...] | None,
    release: str | None,
    detail: bool,
) -> str:
    vars_str = variables if isinstance(variables, str) else ",".join(variables)
    parts = [f"lookup {vars_str} domain={domain} lang={lang}"]
    if scope:
        parts.append("scope=" + ",".join(f'"{s}"' for s in scope))
    if release is not None:
        parts.append(f"release={release}")
    if detail:
        parts.append("detail")
    return " ".join(parts)


def _emit_usage_and_updates(
    *,
    command: str,
    domain: str,
    lang: str,
    directory: Path | str | None,
) -> None:
    """Fire-and-forget usage logging + update check. Never raises."""
    dir_ = Path(directory).expanduser() if directory is not None else None
    try:
        from importlib.metadata import version as _get_version

        _core_ver = _get_version("registream-core")
        _al_ver = _get_version("registream-autolabel")

        from registream.usage import log as _usage_log

        _usage_log(
            command,
            module="autolabel",
            module_version=_al_ver,
            core_version=_core_ver,
            directory=dir_,
        )

        from registream.updates import send_heartbeat

        _hb = send_heartbeat(
            _core_ver,
            "autolabel",
            directory=dir_,
            autolabel_version=_al_ver,
        )

        if _hb.reason == "success":
            from registream.updates import check_pypi_updates

            for _pkg, _cur, _lat in check_pypi_updates():
                warnings.warn(
                    f"A newer version of {_pkg} is available "
                    f"({_cur} \u2192 {_lat}). Run: pip install --upgrade {_pkg}",
                    stacklevel=2,
                )

        from registream.autolabel._datasets import check_for_dataset_updates

        _ds_note = check_for_dataset_updates(domain, lang, directory=dir_)
        if _ds_note:
            warnings.warn(_ds_note, stacklevel=2)
    except Exception:
        pass
