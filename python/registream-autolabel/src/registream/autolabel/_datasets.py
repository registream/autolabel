"""Dataset downloader for autolabel schema v2 (5-file bundle).

Mirrors ``autolabel update datasets`` from ``autolabel.ado`` and the
``download_bundle`` block of ``_al_utils.ado``. Downloads the 5-file
bundle (manifest + scope + variables + value_labels + release_sets)
per (domain, lang), validates against the schema v2 contract, writes
DTA + CSV into ``~/.registream/autolabel/{domain}/``, and updates the
``datasets.csv`` registry.

Cross-client invariant: the on-disk file layout and the ``datasets.csv``
registry format match the Stata writer so both clients can read each
other's cache.
"""

from __future__ import annotations

import io
import logging
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyreadstat
import requests

from registream.dirs import get_registream_dir
from registream.metadata import (
    AUTOLABEL_SUBDIR,
    FileType,
    cache_filename,
    cache_path,
    domain_cache_dir,
)
from registream.schema import (
    SCHEMA_VERSION,
    validate_manifest,
    validate_schema,
    validate_schema_version,
)
from registream.utils import PromptDeclined, confirm, get_api_host

__all__ = [
    "DATASETS_REGISTRY_FILENAME",
    "DOWNLOAD_TIMEOUT_SECONDS",
    "DATASET_CHECK_CACHE_HOURS",
    "REGISTRY_COLUMNS",
    "FileType",
    "DownloadResult",
    "update_datasets",
    "read_registry",
    "write_registry_entry",
    "check_for_dataset_updates",
]


DATASETS_REGISTRY_FILENAME = "datasets.csv"
DOWNLOAD_TIMEOUT_SECONDS = 60
DATASET_CHECK_CACHE_HOURS = 24

REGISTRY_COLUMNS: tuple[str, ...] = (
    "dataset_key",
    "domain",
    "type",
    "lang",
    "version",
    "schema",
    "downloaded",
    "source",
    "file_size_dta",
    "file_size_csv",
    "last_checked",
)

_log = logging.getLogger("registream.autolabel.datasets")

# Folder → file_type map. CSV folder names in the ZIP match the file-type infix.
_BUNDLE_FILES: tuple[tuple[str, FileType], ...] = (
    ("manifest", "manifest"),
    ("variables", "variables"),
    ("value_labels", "values"),
    ("scope", "scope"),
    ("release_sets", "release_sets"),
)

# Which file types are required vs. augmentation (graceful degradation).
_REQUIRED_TYPES: frozenset[FileType] = frozenset({"variables", "values"})


@dataclass
class DownloadResult:
    domain: str
    lang: str
    files: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    failed: list[tuple[str, str]] = field(default_factory=list)

    @property
    def success(self) -> bool:
        return not self.failed


def update_datasets(
    domain: str,
    lang: str,
    *,
    version: str = "latest",
    force: bool = False,
    directory: Path | str | None = None,
) -> DownloadResult:
    """Download the 5-file bundle for ``(domain, lang)`` and populate the cache."""
    dir_ = _resolve_dir(directory)
    autolabel_dir = dir_ / AUTOLABEL_SUBDIR
    autolabel_dir.mkdir(parents=True, exist_ok=True)
    domain_dir = domain_cache_dir(domain, dir_)
    domain_dir.mkdir(parents=True, exist_ok=True)

    result = DownloadResult(domain=domain, lang=lang)

    if not force and _bundle_cached(domain, lang, dir_):
        result.skipped.append(f"{domain}_{lang}")
        return result

    from registream.config import load as load_config

    cfg = load_config(dir_)
    if not cfg.internet_access:
        if _bundle_cached(domain, lang, dir_, require_augmentation=False):
            result.skipped.append(f"{domain}_{lang}")
            return result
        result.failed.append(
            (f"{domain}_{lang}", "Cannot download: internet_access is disabled.")
        )
        return result

    try:
        actual_version, bundle_schema = _resolve_version(domain, lang, version)
    except Exception as exc:
        result.failed.append((f"{domain}_{lang}", str(exc)))
        return result

    try:
        validate_schema_version(bundle_schema)
    except Exception as exc:
        result.failed.append((f"{domain}_{lang}", str(exc)))
        return result

    if not force:
        try:
            approved = confirm(
                f"\nDataset bundle not cached for {domain}/{lang} "
                f"(version {actual_version}).\n"
                "Download autolabel bundle "
                "(manifest + variables + value_labels + scope + release_sets)?"
            )
        except PromptDeclined as exc:
            result.failed.append((f"{domain}_{lang}", str(exc)))
            return result
        if not approved:
            result.failed.append((f"{domain}_{lang}", "Download declined by user."))
            return result

    api_url = (
        f"{get_api_host()}/api/v1/datasets/{domain}/variables/{lang}/{actual_version}"
    )
    try:
        response = requests.get(api_url, timeout=DOWNLOAD_TIMEOUT_SECONDS)
        response.raise_for_status()
    except Exception as exc:
        result.failed.append((f"{domain}_{lang}", str(exc)))
        return result

    zip_bytes = response.content

    for folder, ft in _BUNDLE_FILES:
        try:
            df = _extract_and_concat(zip_bytes, folder=folder)
        except Exception as exc:
            if ft in _REQUIRED_TYPES:
                result.failed.append((f"{domain}_{ft}_{lang}", str(exc)))
            else:
                _log.info("Augmentation file %s missing from bundle: %s", folder, exc)
            continue

        if df is None:
            if ft in _REQUIRED_TYPES:
                result.failed.append(
                    (f"{domain}_{ft}_{lang}", f"Missing required folder {folder!r} in bundle.")
                )
            continue

        try:
            df = _process_for_cache(df, ft)
            if ft == "manifest":
                manifest = validate_manifest(df)
                scope_depth = manifest.scope_depth
            else:
                scope_depth = None
            if ft == "scope":
                validate_schema(df, "scope", scope_depth=scope_depth)
            elif ft in ("variables", "values", "release_sets"):
                validate_schema(df, ft)

            if "variable_name" in df.columns:
                empty = df["variable_name"].isna() | (
                    df["variable_name"].astype(str).str.strip() == ""
                )
                df = df[~empty].reset_index(drop=True)

            str_cols = df.select_dtypes(include=["object"]).columns
            df[str_cols] = df[str_cols].fillna("")

            filename = cache_filename(ft, lang, ext="dta")
            csv_name = cache_filename(ft, lang, ext="csv")
            csv_full = domain_dir / csv_name
            dta_full = domain_dir / filename
            df.to_csv(csv_full, sep=";", index=False, encoding="utf-8")

            file_size_dta = 0
            if ft != "manifest":
                pyreadstat.write_dta(df, str(dta_full))
                file_size_dta = dta_full.stat().st_size

            write_registry_entry(
                directory=dir_,
                domain=domain,
                file_type=ft,
                lang=lang,
                version=actual_version,
                schema=bundle_schema,
                file_size_dta=file_size_dta,
                file_size_csv=csv_full.stat().st_size,
            )
            result.files.append(filename if ft != "manifest" else csv_name)
        except Exception as exc:
            result.failed.append((f"{domain}_{ft}_{lang}", str(exc)))
            _log.warning("Processing failed for %s/%s/%s: %s", domain, ft, lang, exc)

    return result


def _bundle_cached(
    domain: str,
    lang: str,
    directory: Path,
    *,
    require_augmentation: bool = True,
) -> bool:
    """Return True when the cache has everything needed."""
    required = [
        cache_path(domain, "variables", lang, ext="dta", directory=directory),
        cache_path(domain, "values", lang, ext="dta", directory=directory),
    ]
    if require_augmentation:
        required.extend(
            [
                cache_path(domain, "manifest", lang, ext="csv", directory=directory),
                cache_path(domain, "scope", lang, ext="dta", directory=directory),
                cache_path(domain, "release_sets", lang, ext="dta", directory=directory),
            ]
        )
    return all(p.exists() for p in required)


def read_registry(directory: Path | str | None = None) -> pd.DataFrame:
    dir_ = _resolve_dir(directory)
    registry_path = dir_ / AUTOLABEL_SUBDIR / DATASETS_REGISTRY_FILENAME
    if not registry_path.exists():
        return pd.DataFrame(columns=list(REGISTRY_COLUMNS))
    return pd.read_csv(registry_path, sep=";", dtype=str)


def write_registry_entry(
    *,
    directory: Path | str,
    domain: str,
    file_type: FileType,
    lang: str,
    version: str,
    schema: str,
    file_size_dta: int,
    file_size_csv: int,
) -> None:
    dir_ = Path(directory).expanduser() if isinstance(directory, str) else directory
    file_type_label = {"values": "value_labels"}.get(file_type, file_type)
    dataset_key = f"{domain}_{file_type_label}_{lang}"

    timestamp = _stata_clock_now()

    autolabel_dir = dir_ / AUTOLABEL_SUBDIR
    autolabel_dir.mkdir(parents=True, exist_ok=True)
    registry_path = autolabel_dir / DATASETS_REGISTRY_FILENAME

    if registry_path.exists():
        df = pd.read_csv(registry_path, sep=";", dtype=str)
    else:
        df = pd.DataFrame(columns=list(REGISTRY_COLUMNS))

    new_row = {
        "dataset_key": dataset_key,
        "domain": domain,
        "type": file_type_label,
        "lang": lang,
        "version": version,
        "schema": schema,
        "downloaded": str(timestamp),
        "source": "api",
        "file_size_dta": str(file_size_dta),
        "file_size_csv": str(file_size_csv),
        "last_checked": str(timestamp),
    }

    mask = df["dataset_key"] == dataset_key
    if mask.any():
        old_last_checked = df.loc[mask, "last_checked"].iloc[0]
        new_row["last_checked"] = old_last_checked
        for col, value in new_row.items():
            df.loc[mask, col] = value
    else:
        df = pd.concat(
            [df, pd.DataFrame([new_row], columns=list(REGISTRY_COLUMNS))],
            ignore_index=True,
        )

    df = df[list(REGISTRY_COLUMNS)]
    df.to_csv(registry_path, sep=";", index=False)


def check_for_dataset_updates(
    domain: str,
    lang: str,
    *,
    directory: Path | str | None = None,
) -> str:
    dir_ = _resolve_dir(directory)

    from registream.config import load as load_config

    cfg = load_config(dir_)
    if not cfg.internet_access:
        return ""

    registry = read_registry(dir_)
    if registry.empty:
        return ""

    key = f"{domain}_variables_{lang}"
    rows = registry[registry["dataset_key"] == key]
    if rows.empty:
        return ""

    row = rows.iloc[0]
    cached_version = str(row.get("version", ""))
    last_checked = int(row.get("last_checked", 0) or 0)

    now_stata = _stata_clock_now()
    ms_per_hour = 1000 * 60 * 60
    if (now_stata - last_checked) < (DATASET_CHECK_CACHE_HOURS * ms_per_hour):
        return ""

    try:
        latest_version, _ = _resolve_version(domain, lang, "latest")
    except Exception:
        return ""
    finally:
        _update_last_checked(dir_, key, now_stata)

    if latest_version not in ("latest", "") and latest_version != cached_version:
        return (
            f"Newer metadata available for {domain}/{lang} "
            f"(cached: {cached_version}, latest: {latest_version}). "
            f'Run: update_datasets("{domain}", "{lang}", force=True)'
        )
    return ""


def _update_last_checked(directory: Path, dataset_key: str, timestamp: int) -> None:
    autolabel_dir = directory / AUTOLABEL_SUBDIR
    registry_path = autolabel_dir / DATASETS_REGISTRY_FILENAME
    if not registry_path.exists():
        return
    try:
        df = pd.read_csv(registry_path, sep=";", dtype=str)
        mask = df["dataset_key"] == dataset_key
        if mask.any():
            df.loc[mask, "last_checked"] = str(timestamp)
            df.to_csv(registry_path, sep=";", index=False)
    except Exception:
        pass


def _resolve_version(
    domain: str,
    lang: str,
    version: str,
) -> tuple[str, str]:
    if version != "latest":
        return version, SCHEMA_VERSION

    # Server defaults schema_max=1.0 for old-client backward compat. Send
    # SCHEMA_VERSION explicitly so the server returns the latest version
    # whose schema fits what this client can parse (schema 2.0).
    info_url = (
        f"{get_api_host()}/api/v1/datasets/{domain}/variables/{lang}/latest/info"
        f"?format=stata&schema_max={SCHEMA_VERSION}"
    )
    try:
        response = requests.get(info_url, timeout=DOWNLOAD_TIMEOUT_SECONDS)
        response.raise_for_status()
    except requests.RequestException:
        return "latest", SCHEMA_VERSION

    actual_version = "latest"
    schema_version = SCHEMA_VERSION
    for raw_line in response.text.splitlines():
        line = raw_line.strip()
        if line.startswith("version="):
            actual_version = line[len("version=") :].strip() or "latest"
        elif line.startswith("schema="):
            schema_version = line[len("schema=") :].strip() or SCHEMA_VERSION
    return actual_version, schema_version


def _extract_and_concat(zip_bytes: bytes, folder: str) -> pd.DataFrame | None:
    dfs: list[pd.DataFrame] = []
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        names = sorted(name for name in zf.namelist() if name.endswith(".csv"))
        names = [n for n in names if f"/{folder}/" in n or n.startswith(f"{folder}/")]
        if not names:
            return None
        for name in names:
            dfs.append(_read_csv_with_delimiter_fallback(zf.read(name)))
    if not dfs:
        return None
    return pd.concat(dfs, ignore_index=True)


def _read_csv_with_delimiter_fallback(csv_bytes: bytes) -> pd.DataFrame:
    text = csv_bytes.decode("utf-8")
    df = pd.read_csv(io.StringIO(text), sep=";", on_bad_lines="skip")
    if len(df.columns) > 1:
        return df
    return pd.read_csv(io.StringIO(text), sep=",", on_bad_lines="skip")


def _process_for_cache(df: pd.DataFrame, file_type: FileType) -> pd.DataFrame:
    df = df.copy()
    if file_type in ("variables", "values") and "variable_name" in df.columns:
        df["variable_name"] = df["variable_name"].astype(str).str.lower()
        df = df.sort_values("variable_name").reset_index(drop=True)
    if file_type == "values" and "value_labels_json" in df.columns:
        non_empty = df["value_labels_json"].fillna("").astype(str) != "{}"
        df = df[non_empty].reset_index(drop=True)
    return df


def _stata_clock_now() -> int:
    epoch = datetime(1960, 1, 1, tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    delta = now - epoch
    return int(delta.total_seconds() * 1000)


def _resolve_dir(directory: Path | str | None) -> Path:
    if directory is None:
        return get_registream_dir()
    return Path(directory).expanduser()
