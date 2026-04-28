"""Shared dataclasses for the autolabel package.

Re-exports :class:`Manifest`, :class:`LabelBundle`, and
:class:`SchemaVersionError` from ``registream-core`` so callers need
only one import path for the in-memory bundle shape. Local additions
(:class:`ScopeInference`, :class:`FilteredBundle`) live here since they
are internal to the labeling pipeline.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd

from registream.metadata import LabelBundle
from registream.schema import Manifest, SchemaError, SchemaVersionError

__all__ = [
    "FilteredBundle",
    "LabelBundle",
    "Manifest",
    "ScopeInference",
    "SchemaError",
    "SchemaVersionError",
]


@dataclass
class ScopeInference:
    """Result of inferring the best-matching scope against a user's columns.

    ``levels`` is the full tuple of ``scope_level_1..N`` values for the
    inferred scope. ``level_aliases`` is the parallel tuple of
    ``scope_level_N_alias`` values (empty string when the alias column
    is absent or blank).

    ``matches`` counts unique ``variable_name`` values matched against
    the user's columns. ``match_pct`` is ``round(matches/total_datavars * 100)``.
    ``has_strong_primary`` is ``True`` when the top scope covers at
    least 10 % of the user's variables, mirroring the Stata threshold.
    """

    levels: tuple[str, ...]
    level_aliases: tuple[str, ...]
    matches: int
    total_datavars: int
    match_pct: int
    has_strong_primary: bool


@dataclass
class FilteredBundle:
    """Output of the scope/release filter pipeline.

    :attr:`variables` and :attr:`value_labels` are already narrowed to
    the selected scope and release. :attr:`scope_rows` is the subset of
    the bundle's scope table that survived filtering; callers use it
    to enumerate releases or drill deeper.

    :attr:`resolved_scope` / :attr:`resolved_release` record what the
    caller actually selected (after overflow-token-to-release promotion
    and auto-drill). :attr:`auto_drilled_release` is set when a single
    release was implied by the scope filter alone.
    """

    variables: pd.DataFrame
    value_labels: pd.DataFrame
    scope_rows: pd.DataFrame | None
    inferred: ScopeInference | None = None
    resolved_scope: tuple[str, ...] | None = None
    resolved_release: str | None = None
    auto_drilled_release: str | None = None
    contributing_scopes: dict[tuple[str, ...], int] = field(default_factory=dict)
