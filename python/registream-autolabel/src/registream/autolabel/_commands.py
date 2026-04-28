"""Module-level analogs of the Stata ``autolabel suggest / info / cite`` commands.

Python doesn't need SMCL click-through, so these return plain values
(DataFrame for coverage tables, dict for config, str for citations)
which render naturally in Jupyter and can still be printed in a REPL.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd

from registream.autolabel._filters import filter_bundle
from registream.autolabel._types import LabelBundle, ScopeInference
from registream.metadata import load_bundle

__all__ = ["SuggestResult", "suggest", "info", "cite"]


@dataclass
class SuggestResult:
    """Preview of what ``df.rs.autolabel()`` would do without mutating ``df``.

    :attr:`coverage`: one row per candidate scope tuple, columns
    ``scope_level_1..N``, ``matches`` (count of user variables covered),
    ``coverage_pct`` (share of user variables covered), ``is_primary``
    (boolean, set for the inferred primary scope when it crosses the
    10 % threshold).

    :attr:`primary`: the :class:`ScopeInference` chosen as primary, or
    ``None`` when no scope hit the 10 % threshold (mixed-panel data).

    :attr:`pin_command`: a copy-pasteable Python snippet that would
    reproduce the primary pin (useful for notebook workflows).
    """

    coverage: pd.DataFrame
    primary: ScopeInference | None
    pin_command: str

    def __repr__(self) -> str:
        if self.primary is None:
            header = "No strong primary scope (mixed-panel dataset)."
        else:
            header = (
                f"Primary scope: {' / '.join(self.primary.levels)} "
                f"({self.primary.match_pct}% of dataset variables)"
            )
        return f"{header}\n\n{self.coverage}"

    def _repr_html_(self) -> str:
        header = (
            "<p><b>No strong primary scope</b> (mixed-panel dataset).</p>"
            if self.primary is None
            else (
                f"<p><b>Primary scope:</b> "
                f"{' / '.join(self.primary.levels)} "
                f"({self.primary.match_pct}% of dataset variables)</p>"
            )
        )
        table = getattr(self.coverage, "_repr_html_", lambda: repr(self.coverage))()
        return header + table


def suggest(
    df: pd.DataFrame,
    *,
    domain: str = "scb",
    lang: str = "eng",
    scope: list[str] | tuple[str, ...] | None = None,
    release: str | None = None,
    directory: Path | str | None = None,
) -> SuggestResult:
    """Preview the labeling plan for ``df`` without mutating it.

    Mirrors Stata's ``autolabel suggest, domain() lang() [scope()]``.
    Counts variables per candidate scope tuple, identifies the inferred
    primary (≥10 % coverage), and returns a :class:`SuggestResult`.
    """
    bundle = load_bundle(domain, lang, directory=directory)
    datavars = [c for c in df.columns if isinstance(c, str)]
    filtered = filter_bundle(
        bundle,
        scope=list(scope) if scope else None,
        release=release,
        datavars=datavars if not scope else None,
    )

    coverage = _coverage_table(bundle, filtered, datavars)
    primary = filtered.inferred
    pin_command = _build_pin_command(domain, lang, primary, scope, release)
    return SuggestResult(
        coverage=coverage,
        primary=primary,
        pin_command=pin_command,
    )


def info(directory: Path | str | None = None) -> dict[str, Any]:
    """Return the autolabel configuration snapshot.

    Mirrors Stata's ``autolabel info``. Reads the shared config via
    :mod:`registream.config` and pairs it with package metadata
    (installed versions, cache directory, citation line). Returns a
    plain ``dict``; Jupyter renders the dict nicely, and REPL users
    can ``print()`` it.
    """
    from registream.config import load as load_config
    from registream.dirs import get_registream_dir
    from registream.metadata import cache_dir

    from importlib.metadata import version as _v

    dir_ = Path(directory).expanduser() if directory is not None else get_registream_dir()
    try:
        cfg = load_config(dir_)
        cfg_dict = {
            "internet_access": cfg.internet_access,
            "usage_logging": cfg.usage_logging,
            "telemetry_enabled": cfg.telemetry_enabled,
            "auto_update_check": getattr(cfg, "auto_update_check", None),
        }
    except Exception:
        cfg_dict = {}

    def _safe_version(pkg: str) -> str:
        try:
            return _v(pkg)
        except Exception:
            return "unknown"

    return {
        "registream_dir": str(dir_),
        "autolabel_cache": str(cache_dir(dir_)),
        "core_version": _safe_version("registream-core"),
        "autolabel_version": _safe_version("registream-autolabel"),
        "config": cfg_dict,
    }


_HLINE = "-" * 60


def cite() -> str:
    """Return the full citation block, matching Stata's ``autolabel cite``.

    Produces the header rules + "To cite autolabel..." lead-in + the
    versioned APA line. Matches the Stata ``.ado`` output verbatim so
    the Python and Stata clients quote the package identically.

    Title / authors / URL come from the generated ``_citation_data`` module
    (sourced from the ecosystem-wide ``registream/citations.yaml``). Edit the
    YAML and regenerate; do not hand-edit the template here.
    """
    from importlib.metadata import version as _v

    from . import _citation_data as _cd

    try:
        v = _v("registream-autolabel")
    except Exception:
        v = "X.Y.Z"
    apa = _cd.APA_VERSIONED_TEMPLATE.format(version=v)

    lines = [
        "",
        _HLINE,
        "Citation",
        _HLINE,
        "",
        "To cite autolabel in publications, please use:",
        "",
        f"  {apa}",
        "",
    ]
    return "\n".join(lines)


# ─── Internal helpers ──────────────────────────────────────────────────────────


def _coverage_table(
    bundle: LabelBundle,
    filtered,
    datavars: list[str],
) -> pd.DataFrame:
    """Build the per-scope coverage table shown by ``suggest``."""
    if bundle.core_only or bundle.scope is None or bundle.release_sets is None:
        return pd.DataFrame(
            columns=["scope_level_1", "matches", "coverage_pct", "is_primary"]
        )

    depth = bundle.manifest.scope_depth
    level_cols = [f"scope_level_{i}" for i in range(1, depth + 1)]

    datavars_lower = {v.lower() for v in datavars}

    vars_in_scope = filtered.variables.copy()
    if vars_in_scope.empty:
        return pd.DataFrame(columns=level_cols + ["matches", "coverage_pct", "is_primary"])

    scope_per_rs = bundle.release_sets.merge(
        bundle.scope[["scope_id", *level_cols]], on="scope_id", how="inner"
    ).drop_duplicates(subset=["release_set_id"])

    joined = vars_in_scope.merge(scope_per_rs, on="release_set_id", how="inner")
    joined["_in_data"] = (
        joined["variable_name"].astype(str).str.lower().isin(datavars_lower)
    )

    grouped = (
        joined[joined["_in_data"]]
        .drop_duplicates(subset=[*level_cols, "variable_name"])
        .groupby(level_cols, dropna=False)
        .size()
        .rename("matches")
        .reset_index()
    )

    n = max(len(datavars), 1)
    grouped["coverage_pct"] = (grouped["matches"] / n * 100).round().astype(int)
    grouped = grouped.sort_values(
        ["matches", *level_cols], ascending=[False, *[True] * depth]
    ).reset_index(drop=True)

    primary_tuple = filtered.inferred.levels if filtered.inferred else None
    if primary_tuple is None or not filtered.inferred.has_strong_primary:
        grouped["is_primary"] = False
    else:
        grouped["is_primary"] = True
        for col, val in zip(level_cols, primary_tuple, strict=False):
            grouped["is_primary"] &= grouped[col].astype(str).fillna("") == val

    return grouped


def _build_pin_command(
    domain: str,
    lang: str,
    primary: ScopeInference | None,
    scope: list[str] | tuple[str, ...] | None,
    release: str | None,
) -> str:
    """Return a copy-pasteable ``df.autolabel(...)`` call that pins the scope."""
    if scope:
        scope_repr = list(scope)
    elif primary is not None:
        scope_repr = list(primary.levels)
    else:
        scope_repr = None

    parts = [f"domain={domain!r}", f"lang={lang!r}"]
    if scope_repr:
        parts.append(f"scope={scope_repr!r}")
    if release is not None:
        parts.append(f"release={release!r}")
    return "df.autolabel(" + ", ".join(parts) + ")"
