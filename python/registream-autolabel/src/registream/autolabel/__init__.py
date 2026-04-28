"""RegiStream autolabel: pandas accessor for register data labeling.

Importing this module:

1. Registers the ``df.rs`` accessor via
   ``@pd.api.extensions.register_dataframe_accessor("rs")``.
2. Installs monkey-patch shortcuts (``df.autolabel``, ``df.lookup``,
   ``df.variable_labels``, ``df.value_labels``). Opt out with
   ``REGISTREAM_NO_SHORTCUTS=1``.
3. Re-exports the public API at the package level.
"""

from __future__ import annotations

# Side effect: registers the `rs` accessor on pd.DataFrame.
from registream.autolabel._accessor import DryRunResult, RsAccessor  # noqa: F401
from registream.autolabel._commands import SuggestResult, cite, info, suggest
from registream.autolabel._datasets import (
    DATASETS_REGISTRY_FILENAME,
    REGISTRY_COLUMNS,
    DownloadResult,
    check_for_dataset_updates,
    read_registry,
    update_datasets,
    write_registry_entry,
)
from registream.autolabel._edit import (
    copy_labels,
    meta_search,
    set_value_labels,
    set_variable_labels,
)
from registream.autolabel._filters import FilterError, filter_bundle
from registream.autolabel._inference import infer_scope
from registream.autolabel._labels import (
    apply_labels,
    apply_value_labels,
    apply_variable_labels,
    get_value_labels,
    get_variable_labels,
    parse_value_labels_stata,
    stamp_registream_attrs,
)
from registream.autolabel._lookup import LookupResult, lookup
from registream.autolabel._repr import LabeledView
from registream.autolabel._scope import scope
from registream.autolabel._shortcuts import (
    SHORTCUT_NAMES,
    are_shortcuts_installed,
    install_shortcuts,
)
from registream.autolabel._types import (
    FilteredBundle,
    LabelBundle,
    Manifest,
    SchemaError,
    SchemaVersionError,
    ScopeInference,
)

from importlib.metadata import PackageNotFoundError, version as _pkg_version

try:
    __version__ = _pkg_version("registream-autolabel")
except PackageNotFoundError:
    __version__ = "0.0.0+unknown"


def autolabel(df, domain: str = "scb", lang: str = "eng", **kwargs):
    """Top-level :func:`autolabel` function.

    Thin wrapper over ``df.rs.autolabel(...)`` so users can call
    ``registream.autolabel.autolabel(df, ...)`` in addition to the
    accessor and shortcut forms. Matches the old package's module-level
    function and makes the package usable without first touching the
    accessor.
    """
    return df.rs.autolabel(domain=domain, lang=lang, **kwargs)

__all__ = [
    "__version__",
    # Accessor
    "RsAccessor",
    "DryRunResult",
    # Top-level helpers mirroring Stata subcommands
    "autolabel",
    "suggest",
    "SuggestResult",
    "info",
    "cite",
    # Downloader / dataset cache
    "update_datasets",
    "read_registry",
    "write_registry_entry",
    "check_for_dataset_updates",
    "DownloadResult",
    "REGISTRY_COLUMNS",
    "DATASETS_REGISTRY_FILENAME",
    # Lookup
    "lookup",
    "LookupResult",
    # Scope browse
    "scope",
    # Labels
    "apply_labels",
    "apply_variable_labels",
    "apply_value_labels",
    "get_variable_labels",
    "get_value_labels",
    "parse_value_labels_stata",
    "stamp_registream_attrs",
    # Label editors (mutate df.attrs in place)
    "set_variable_labels",
    "set_value_labels",
    "copy_labels",
    "meta_search",
    # Filters / inference
    "filter_bundle",
    "FilterError",
    "infer_scope",
    # Bundle types
    "LabelBundle",
    "Manifest",
    "ScopeInference",
    "FilteredBundle",
    "SchemaError",
    "SchemaVersionError",
    # Display
    "LabeledView",
    # Shortcut layer
    "install_shortcuts",
    "are_shortcuts_installed",
    "SHORTCUT_NAMES",
]


install_shortcuts()

# Install the seaborn wrapper eagerly so plotting works even when the
# caller never touches ``df.rs.lab`` (e.g. passes a labeled DataFrame
# directly via ``data=df``). Safe no-op when seaborn isn't installed or
# when ``REGISTREAM_NO_PLOT_PATCH=1`` is set.
from registream.autolabel._seaborn import patch_plotting_libraries_once as _patch_plots

_patch_plots()
del _patch_plots

# Install the universal pandas-method patches so variable and value
# labels survive ``df['new'] = df['old']`` and ``df.rename(columns=...)``.
# Conditional; unlabeled DataFrames are completely untouched. Opt out
# via ``REGISTREAM_NO_PANDAS_PATCH=1``.
from registream.autolabel._pandas_patches import (
    install_pandas_patches_once as _install_patches,
)

_install_patches()
del _install_patches
