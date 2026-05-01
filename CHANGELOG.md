# Autolabel Changelog

## v3.0.0 (2026-04-08)

First release as a standalone module (split from RegiStream monorepo).

### New Features

- **Schema v2.0 support**: 5-file bundle (`variables`, `value_labels`, `manifest`, `scope`, `release_sets`) declares the catalog's scope hierarchy in the manifest, so a domain can ship arbitrary scope-level names (`register`/`variant` for SCB, `source`/`group` for SSB) without code changes.
- **Automatic primary-scope inference**: when no `scope()` is specified, autolabel analyses the dataset's variables, matches them against all scopes in the metadata, and selects the densest scope tuple. The inferred scope is reported at the deepest level where narrowing actually reduces matched-variable coverage, rendered as a quoted-token list (`"LISA"` for level-1, `"LISA" "Individuals 16+"` for level-2). Falls back to majority-rule across other scopes for unmatched variables.
- **`scope()` option**: pin labelling to a specific scope by passing one or more quoted tokens, one per scope level. Example: `scope("LISA")` pins level-1; `scope("LISA" "Individuals aged 16 and older")` pins level-1 + level-2.
- **`release()` option**: pin labelling to a specific metadata release for reproducibility (e.g. `release("2010")`).
- **`dryrun` option**: display the labelling commands without applying them.
- **`savedo()` option**: save labelling commands to a .do file for inspection or later use.
- **`autolabel update datasets`**: check for and download metadata updates directly from the autolabel command (previously required `registream update datasets`).
- **`autolabel suggest`**: preview which scope each variable would label from before applying anything; surfaces the same primary/fallback/unmatched partition as `autolabel variables` would produce.
- **`autolabel scope`**: clickable scope-hierarchy browser, filtered by a keyword or variable name.
- **`autolabel lookup`**: print metadata (definition, type, scope counts, value codes) for one or more variables without modifying the dataset.
- **rclass return contract**: every subcommand sets a documented `r()` contract for composable workflows.
  - `autolabel variables` and `autolabel values` set `r(primary)`, `r(inferred_scope)`, `r(primary_vars)`, `r(fallback_vars)`, `r(skipped_vars)`, plus counts (`n_primary`, `n_fallback`, `n_skipped`, `n_total`), `r(display_depth)`, and `r(domain)` / `r(lang)` echoes.
  - `autolabel suggest` surfaces the same primary/fallback partition plus `r(unmatched_vars)` and `r(match_pct)`, enabling the canonical workflow: run `suggest` once, then compose iterative scope-pinned labelling calls using the returned variable lists.
  - `autolabel lookup` sets `r(found_vars)`, `r(unmatched_vars)`, and counts.
  - `autolabel scope` sets `r(scope_level)` and `r(parent_scope)` for navigation context.
  - The contract closes the previous "fallback opacity" gap: callers can see exactly which dataset variables would label from primary vs. via majority fallback vs. not in the catalog at all, without re-running primary inference.
- **Per-module version tracking**: heartbeat sends `autolabel=3.0.0` to server, receives per-package update notifications.

### Architecture Changes

- **Modular separation**: autolabel is now an independent package that depends on `registream` core for config, telemetry, and utilities.
- **Dataset management moved to autolabel**: `scan_datasets`, `check_datasets_bulk`, `update_datasets_interactive`, `rebuild_datasets_csv` — previously in core `_rs_updates.ado`, now in `_rs_autolabel_utils.ado`.
- **Schema validation moved to autolabel**: `_rs_validate_schema.ado` now lives in the autolabel package.
- **Config format**: `config_stata.yaml` replaced with `config_stata.csv` (simpler key;value format, native Stata I/O).
- **Data directory**: `~/.registream/autolabel_keys/` renamed to `~/.registream/autolabel/`.
- **Naming convention unified**: all private programs in `autolabel.ado` use the `_al_*` prefix. Section comments separate subcommand handlers from internal helpers.

### Bug Fixes

- **`scope()` syntax declared `string asis`** in the help file: matches the production ado, which has always parsed the option that way. Previously the help file showed `scope(string)`, understating the supported multi-token form.
- **strL key conversion**: `_al_collapse_v2` converts `variable_name` from strL to str# before merges, since Stata's `merge` cannot use strL keys.

### Syntax

```
autolabel variables [varlist], domain(string) lang(string)
    [scope(string asis) release(string)]
    [exclude(varlist) suffix(string) dryrun savedo(string)]

autolabel values [varlist], domain(string) lang(string)
    [scope(string asis) release(string)]
    [exclude(varlist) suffix(string)]

autolabel lookup varlist, domain(string) lang(string)
    [scope(string asis) release(string) detail]

autolabel suggest, domain(string) lang(string)
    [scope(string asis) list]

autolabel scope, domain(string) lang(string)
    [scope(string asis) var(varlist)]

autolabel update [package|datasets]
autolabel version
autolabel info
autolabel cite
```

### Scope-selection logic

When labelling with Schema v2.0 metadata:

1. **`scope()` specified**: filters to the matching scope tuple (token-by-token match against `scope_level_1`, `scope_level_2`, ... aliases; case-insensitive).
2. **`scope()` not specified**: infers the densest scope tuple by counting variable overlap between the dataset and each scope group; reports the inferred scope at the deepest level where narrowing reduced matched coverage. Variables not in the inferred scope receive labels via majority-rule fallback across the catalog's other scopes.
3. **`release()` specified**: keeps metadata rows whose scope-row matches the requested release atom.
4. **Row collapse**: after filtering, if a variable still has multiple metadata rows (variants/releases), the deterministic collapse rule prefers `_is_primary == 1`, then most-common `variable_label`, then most-common `value_label_id`, with `value_label_id` as the final tiebreaker.
