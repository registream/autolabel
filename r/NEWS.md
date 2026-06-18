# autolabel (R port) — NEWS

## autolabel 3.0.2 (2026-06-18)

### New features

- **Offline bundle install.** `rs_update_datasets()` and the `autolabel()` cold-start now build the metadata cache from a bundle staged on disk (an extracted `<domain>_<lang>/` folder or a `<domain>_<lang>_v*.zip`) ahead of the internet gate, mirroring the Stata client. Users in secure environments (e.g. SCB MONA) can install with no network and no download prompt.

### Bug fixes

- **Cache CSV writes quote embedded delimiters.** `write.table()` now uses `quote = TRUE, qmethod = "double"`, so a `value_labels_json` field containing `;` (and `"`) round-trips losslessly and reads back identically in every client.


## autolabel 3.0.1 (2026-05-08)

R-port-only patch. Stata and Python clients are unaffected.

### Cold-start parity with Stata

- **`ensure_bundle()` cascade**: prompt + auto-download fires before the first label apply when the metadata cache is empty. Mirrors Stata's `_al_ensure_bundle` (`autolabel/stata/src/_al_utils.ado:83`). Interactive sessions see *"Metadata not cached for scb/eng. Download from RegiStream? (yes/no):"*; non-interactive scripts and `R CMD check` keep the existing CRAN-safe `rs_error_missing_bundle` behavior. Honors `REGISTREAM_AUTO_APPROVE=yes` for CI / automation.
- **Manifest file now downloaded**: `rs_update_datasets()` previously skipped the manifest file (Stata's `_al_download_bundle` had always pulled it). Without `manifest_<lang>.csv` on disk, `load_bundle()` silently fell back to `core_only` mode and `scope` / `release` pinning was disabled in every R-port session. Manifest is now part of the downloaded set.

### Performance

- **`data.table::fread` + `rbindlist`** (Suggests, soft dep): replaces base R `read.csv` + `do.call(rbind, ...)` in `extract_and_concat()` and `read_csv_with_delimiter_fallback()`. SCB cold-start drops from > 7 minutes (effectively unbounded) to ~25 seconds. Falls back to base R cleanly when `data.table` is not installed.
- **`unescape_doubled_quotes()` helper**: post-processes `fread` output to undo CSV `""` → `"` escaping, which fread does not handle by default in this version. Required for `value_labels_json` and `value_labels_stata` columns whose contents carry embedded quotes.

### Bug fixes

- **Cold-start no longer requires manual `rs_update_datasets()`**: the docs example at `https://registream.org/docs/autolabel/r` previously failed for every fresh install with `rs_error_missing_bundle`. The new cascade prompts the user transparently.

### Tests

- 5 new tests in `test-datasets.R` covering the four behavior branches of `ensure_bundle()` (cache-present, internet-disabled, non-interactive, auto-approve) plus a `skip_on_cran` integration test for the full cold-start path.
- Pre-existing namespace failures in `test-registry.R` and `test-telemetry.R` fixed: bare `REGISTRY_COLUMNS` / `log_and_heartbeat` qualified with `autolabel:::`. Suite now green under `R CMD INSTALL` + `testthat::test_dir`, not only under `devtools::test()`.

### Dependencies

- `data.table` added to `Suggests` (used opportunistically; not a hard dep).
- `registream` core dep bumped to `>= 3.0.1` — the value-label character-type filtering fix is in core.


## autolabel 3.0.0 (2026-04-08)

First public release of the R port. See the ecosystem [`CHANGELOG.md`](../CHANGELOG.md) at the autolabel repo root for the v3.0.0 release notes.
