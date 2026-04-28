# Autolabel Changelog

## v3.0.0 (2026-04-08)

First release as a standalone module (split from RegiStream monorepo).

### New Features

- **Schema v2.0 support**: Metadata now includes `register`, `variant`, `version`, and `datatype` columns. Each variable can appear in multiple registers with register-specific labels.
- **Automatic register inference**: When no `register()` is specified, autolabel analyzes your dataset's variables, matches them against all registers in the metadata, and selects the best-matching register. Displays the detected register and match percentage.
- **`register()` option**: Filter metadata to a specific register (partial match, case-insensitive). Example: `register(LISA)` matches "Longitudinell integrationsdatabas ... (LISA)".
- **`variant()` option**: Filter by register variant.
- **`version()` option**: Filter by year/version range. Example: `version(2005)` matches ranges like "1990-2009".
- **`dryrun` option**: Preview labeling commands without applying them.
- **`savedo()` option**: Save labeling commands to a .do file for inspection or later use.
- **`autolabel update datasets`**: Check for and download metadata updates directly from the autolabel command (previously required `registream update datasets`).
- **Per-module version tracking**: Heartbeat sends `autolabel=3.0.0` to server, receives per-package update notifications.

### Architecture Changes

- **Modular separation**: autolabel is now an independent package that depends on `registream` core for config, telemetry, and utilities.
- **Dataset management moved to autolabel**: `scan_datasets`, `check_datasets_bulk`, `update_datasets_interactive`, `rebuild_datasets_csv` — previously in core `_rs_updates.ado`, now in `_rs_autolabel_utils.ado`.
- **Schema validation moved to autolabel**: `_rs_validate_schema.ado` now lives in the autolabel package (validates both Schema 1.0 and 2.0).
- **Config format**: `config_stata.yaml` replaced with `config_stata.csv` (simpler key;value format, native Stata I/O).
- **Data directory**: `~/.registream/autolabel_keys/` renamed to `~/.registream/autolabel/`.
- **DTA build**: No longer deduplicates v2.0 metadata during DTA creation (preserves all register rows).

### Bug Fixes

- **Schema version detection**: DTA files now correctly tagged as Schema 2.0 when built from v2.0 CSVs.
- **Schema validation**: Accepts both Schema 1.0 and 2.0 (previously rejected 2.0).
- **Version deduplication**: When multiple versions exist for a variable, prefers the most recent version range.

### Syntax

```
autolabel variables [varlist], domain(string) lang(string)
    [register(string) variant(string) version(string)]
    [exclude(varlist) suffix(string) dryrun savedo(string)]

autolabel values [varlist], domain(string) lang(string)
    [register(string) variant(string) version(string)]
    [exclude(varlist) suffix(string)]

autolabel lookup varlist, domain(string) lang(string)
    [register(string)]

autolabel update [package|datasets] [, domain(string) lang(string) version(string)]
autolabel version
autolabel info
autolabel cite
```

### Selection Logic (v2.0)

When labeling with Schema v2.0 metadata:

1. **Register specified** (`register(LISA)`): Filters to matching register (partial match, case-insensitive).
2. **Register not specified**: Infers the best-matching register by counting variable overlap between your dataset and each register's metadata.
3. **Variant specified** (`variant(...)`): Further filters within the register.
4. **Version specified** (`version(2005)`): Keeps metadata rows where the requested year falls within the version range.
5. **Deduplication**: After all filtering, if a variable still has multiple rows, the most recent version range is preferred.
