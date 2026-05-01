# Autolabel Schema v2 — Data Format Reference

This document describes the data format `autolabel` reads — the five-file CSV bundle format produced by the RegiStream catalog pipeline and consumed by `autolabel` (Stata, Python, R).

- **Current version**: v2 (`schema_version = "2.0"` in-band marker)
- **Canonical location**: this file

---

## Overview

An autolabel-compatible catalog bundle contains **5 CSV files per language** for each metadata domain (e.g. `scb` for Statistics Sweden, `dst` for Statistics Denmark, `ssb` for Statistics Norway):

| File | Role | Format notes |
|---|---|---|
| `{domain}_manifest_{lang}.csv` | **Manifest (config)** | Flat key-value CSV: schema version, scope hierarchy names, publisher info |
| `{domain}_scope_{lang}.csv` | **Data** | Atomic manifest of `(scope, release)` instances with per-atom scalar metadata |
| `{domain}_variables_{lang}.csv` | **Data** | Central facts table — one row per stable variable-metadata era, with two integer FKs |
| `{domain}_value_labels_{lang}.csv` | **Data** | Content-hashed value sets, with both JSON and Stata-native format columns |
| `{domain}_release_sets_{lang}.csv` | **Data** | Junction table linking release sets to atomic scope ids |

**All data files are pure rectangular CSVs with scalar columns.** `value_labels.csv` carries two equivalent views of each value set — a JSON column (`value_labels_json`) and a companion pre-formatted string column (`value_labels_stata`) — so consumers pick whichever fits their tool.

**All cross-file references are integer foreign keys.** No inline text duplication. No pipe-delimited multi-value cells.

### CSV conventions

- **Delimiter**: semicolon (`;`) — avoids quoting issues with JSON content and Scandinavian text containing commas
- **Quoting**: double-quote (`"`) with inner quotes doubled (`""`)
- **Encoding**: UTF-8
- **No pipe-separated multi-value cells** — all cells are scalar

### Two hierarchical axes

Every variable's identity is defined by two axes:

- **`scope`** — what slice of reality the variable describes. Stored as separate columns `scope_level_1`, `scope_level_2`, etc. (e.g. `scope_level_1 = LISA`, `scope_level_2 = Individer_16_och_äldre`). Depth declared per domain in the manifest.
- **`release`** — which published release instance. Opaque string (e.g. `2005`, `Höstterminen_2020`, `2019_lone_formansutbetalningar`).

**Scope depth is dynamic** — declared per domain in the manifest. SCB uses 2 levels ("Register" / "Variant"); SSB uses 2 differently-named levels ("Source" / "Group"); a future agency could use 4. `autolabel` reads the manifest at runtime to drive UI labels and browse hierarchy — no code changes needed to support a new depth.

### The five files

A complete domain is five CSV files, each with a fixed role:

- `variables.csv` — variable-level metadata (name, description, value-label group, release-set link)
- `value_labels.csv` — value labels for coded variables
- `scope.csv` — the catalog hierarchy (registers, variants, or equivalent levels)
- `release_sets.csv` — junction linking scope rows to per-release variable definitions
- `manifest.csv` — display titles for scope levels and the list of available languages

The `release_set_id` column on `variables.csv` is the foreign key into `release_sets.csv`; every metadata row is tagged with a release set, even for single-scope single-release domains (use a single scope row and a single release_set in that case).

---

## 1. Manifest — `{domain}_manifest_{lang}.csv`

Flat key-value CSV declaring domain metadata and scope hierarchy semantics. One file per language (titles are localized).

### Columns

| Column | Type | Required | Description |
|---|---|---|---|
| `key` | string | yes | Configuration key |
| `value` | string | yes | Value for the key |

### Required keys

- `domain` — catalog domain identifier (e.g. `scb`, `dst`, `ssb`)
- `schema_version` — wire-format version (currently `2.0`)
- `publisher` — name of the publishing organization
- `bundle_release_date` — ISO 8601 date of this bundle's publication
- `languages` — pipe-separated list of languages in this bundle (e.g. `swe|eng`)
- `scope_depth` — integer N, the fixed depth of the scope hierarchy for this domain
- `scope_level_1_name` through `scope_level_N_name` — short machine-readable level name (lowercase, no spaces)
- `scope_level_1_title` through `scope_level_N_title` — human-readable level title in this file's language

### Optional keys

- `publisher_url`
- `publisher_contact`
- `bundle_license`
- `catalog_provenance`
- Any namespaced extension keys (`{domain}:ext_*`)

### Example — `scb_manifest_eng.csv`

```csv
key,value
domain,scb
schema_version,2.0
publisher,Statistics Sweden (SCB)
bundle_release_date,2026-04-16
languages,swe|eng
scope_depth,2
scope_level_1_name,register
scope_level_1_title,Register
scope_level_2_name,variant
scope_level_2_title,Variant
```

### Example — `ssb_manifest_eng.csv` (different level naming)

```csv
key,value
domain,ssb
schema_version,2.0
publisher,Statistics Norway (SSB)
bundle_release_date,2026-04-20
languages,nob|eng
scope_depth,2
scope_level_1_name,source
scope_level_1_title,Source
scope_level_2_name,group
scope_level_2_title,Group
```

**Rule**: the value of `scope_depth` MUST match the number of `scope_level_*` / `scope_level_*_alias` column pairs in `scope.csv`.

---

## 2. Scope — `{domain}_scope_{lang}.csv`

Atomic manifest. One row per `(scope, release)` combination.

### Columns

| Column | Type | Required | Description |
|---|---|---|---|
| `scope_id` | integer | yes (PK) | Primary key, assigned sequentially during pipeline ingestion |
| `scope_level_1` | string | yes | Full name of scope level 1 (e.g. register name) |
| `scope_level_1_alias` | string | no | Optional short alias (e.g. `LISA`) |
| `scope_level_1_description` | string | no | Free-text description of scope level 1 |
| `scope_level_2` | string | conditional | Second-level name. Required when `scope_depth >= 2` |
| `scope_level_2_alias` | string | no | Optional short alias for level 2 |
| `scope_level_2_description` | string | no | Free-text description of scope level 2 |
| … | … | … | `scope_level_N`, `scope_level_N_alias`, `scope_level_N_description` for N = `scope_depth` |
| `release` | string | yes | Atomic release identifier — opaque string |
| `release_description` | string | no | Description specific to this release |
| `population_date` | string | no | ISO 8601 date |
| `measurement_info` | string | no | Free-text description of data collection |

### Rules

- **Primary key**: `scope_id`
- **Uniqueness**: `(scope_level_1, …, scope_level_N, release)` unique within a domain
- **Every row MUST have `scope_level_1` populated.** Deeper levels MAY be empty per-row when the row has no meaningful sub-scope
- **All columns are scalar strings or integers.** No JSON. No slash-delimited compound values — each scope level is its own column

### Release axis rules

- `release` is an opaque string. May be a year (`2005`), academic term (`Höstterminen_2020-Vårterminen_2021`), calendar date (`2014-10-15`), quarter (`2005_Q1`), content-tagged edition (`2019_lone_formansutbetalningar`), or anything else
- **Each atomic release is one row.** No pipe-delimited multi-release strings. Non-contiguous sequences (e.g. election years 1991, 1994, 1998, …) get one row per year; gap years are absent
- **No range strings like `1990-2009`.** Use 20 rows, one per atomic year

### Example

```csv
scope_id;scope_level_1;scope_level_1_alias;scope_level_2;scope_level_2_alias;release;…
1001;"Longitudinell integrationsdatabas…";"LISA";"Individer 16 år och äldre";"";"1990";…
1002;"Longitudinell integrationsdatabas…";"LISA";"Individer 16 år och äldre";"";"1991";…
…
1020;"Longitudinell integrationsdatabas…";"LISA";"Individer 16 år och äldre";"";"2009";…
```

---

## 3. Variables — `{domain}_variables_{lang}.csv`

Central facts table. One row per unique variable-metadata era.

### Columns

| Column | Type | Required | Description |
|---|---|---|---|
| `variable_name` | string | yes | Column name in the raw data |
| `variable_label` | string | yes | Human-readable label |
| `variable_definition` | string | no | Full definition text |
| `variable_unit` | string | no | Unit of measurement |
| `variable_type` | enum | yes | `categorical` / `continuous` / `text` / `date` / `identifier` |
| `variable_description` | string | no | Long-form description |
| `variable_source` | string | no | Source authority |
| `variable_external_comment` | string | no | External-facing comment |
| `datatype` | string | no | Storage type (`char(1)`, `int`, `float`, …) |
| `value_label_id` | integer | no | FK → `value_labels.csv` (null for non-categorical) |
| `release_set_id` | integer | yes | FK → `release_sets.csv` (via junction) |

### Rules

- **Primary key**: `(variable_name, datatype, value_label_id, release_set_id)`
- **No scope columns.** Scope is resolved via the FK chain: `release_set_id → release_sets → scope_id → scope.scope_level_1, scope_level_2, …`
- **Metadata drift handling**: when any variable-level attribute changes across releases, the variable splits into multiple rows, each pointing at its own `release_set_id` covering exactly the releases where that metadata applies

---

## 4. Value Labels — `{domain}_value_labels_{lang}.csv`

Content-hashed lookup of unique value sets.

### Columns

| Column | Type | Required | Description |
|---|---|---|---|
| `value_label_id` | integer | yes (PK) | Content-hash-derived primary key |
| `variable_name` | string | no | Representative variable (informational only, not part of identity) |
| `value_labels_json` | string | yes | JSON dict `{"1": "Man", "2": "Kvinna"}` |
| `value_labels_stata` | string | yes | Pre-formatted string: `"1" "Man" "2" "Kvinna"` — direct input to Stata's `label define` |
| `code_count` | integer | yes | Number of distinct codes |

### Two equivalent views

Tools with native JSON parsing (Python pandas, R, DuckDB, JavaScript) MAY parse `value_labels_json`. Tools without convenient JSON parsing (Stata, shell pipelines, spreadsheet apps) MAY use `value_labels_stata`. Both encode the same value set.

### Content-hashing rule

`value_label_id` is a stable integer hash over the canonical-language (English) normalized value set. Swedish and English files share the same IDs for conceptually identical sets.

### Match by FK, not by name

Look up the variable in `variables.csv` to get `value_label_id`, then look up that ID in `value_labels.csv`. Do NOT match on `variable_name` (it's informational only — e.g. `kon` appears in many variables.csv rows across registers with potentially different value_label_ids).

---

## 5. Release Sets — `{domain}_release_sets_{lang}.csv`

Junction table. One row per `(release_set_id, scope_id)` pair.

### Columns

| Column | Type | Required | Description |
|---|---|---|---|
| `release_set_id` | integer | yes | Content-hash-derived ID for the release set |
| `scope_id` | integer | yes | FK → `scope.scope_id` |

### Rules

- **Primary key**: composite `(release_set_id, scope_id)`
- **Content-hashing**: `release_set_id` is a stable integer hash over the sorted ascending list of `scope_id`s in the set. All variables.csv rows that apply to exactly the same set of scope atoms share the same `release_set_id`
- **Scope invariant**: within a single `release_set_id`, all referenced `scope_id`s MUST resolve to the same scope (identical values across all `scope_level_*` columns)

### Example reader pattern (Stata)

```stata
import delimited using "scb_release_sets_eng.csv", clear delimiters(";")
keep if scope_id == 1015                   // from a scope filter
levelsof release_set_id, local(matching)

import delimited using "scb_variables_eng.csv", clear delimiters(";")
keep if inlist(release_set_id, `matching')
```

---

## 6. Referential integrity

A conformant bundle MUST satisfy:

1. Every non-null `value_label_id` in `variables.csv` exists in `value_labels.csv`
2. Every `release_set_id` in `variables.csv` has at least one row in `release_sets.csv`
3. Every `scope_id` in `release_sets.csv` exists in `scope.csv`
4. Within each `release_set_id`, all referenced `scope_id`s resolve to the same scope (identical `scope_level_*` values)
5. Every `scope.csv` row has `scope_level_1` populated. Deeper levels may be empty per-row. `scope_depth` is the MAXIMUM depth, not a per-row requirement
6. The manifest file exists for every language listed in its `languages` key

---

## 7. `schema_version` — wire-format gate

Every autolabel-readable dataset carries a `schema_version` marker:

- **Stata**: `char _dta[schema_version] "2.0"` (dataset characteristic)
- **Python / pandas**: `df.attrs['schema_version'] = '2.0'`
- **R / haven**: `attr(df, 'schema_version') <- '2.0'`

This is a runtime compatibility check — autolabel reads it to decide whether an installed tool version can parse the bundle. A future breaking change (e.g. required column added to `variables.csv`) would bump `schema_version` to `3.0`, and the tool version gate would reject the new bundle until the tool upgrades.

---

## 8. Multilingual convention

Bundles ship one set of 5 files per language:

```
{domain}_manifest_{lang}.csv
{domain}_scope_{lang}.csv
{domain}_variables_{lang}.csv
{domain}_value_labels_{lang}.csv
{domain}_release_sets_{lang}.csv
```

**English is REQUIRED** at the field level. Native-language files are REQUIRED where the source is non-English. Additional languages are OPTIONAL.

**IDs are canonical across language files.** `scope_id`, `value_label_id`, and `release_set_id` MUST be identical across all language variants. Only localized text columns differ.

**Manifest titles are localized per file.** Level *names* (lowercase, machine-readable) are canonical and MUST match across language files; *titles* (human-readable) differ per language.

---

## 9. Extension namespacing

Producers MAY add extension columns to any data file or extension keys to the manifest. Extension names MUST use a colon-prefix matching the catalog domain:

- `scb:ext_ansvarig_enhet` (column)
- `scb:ext_internal_notes` (manifest key)
- `dst:ext_hq_flag`
- `healthdcat:ext_access_rights`

**Consumer tools MUST ignore unrecognized namespaced columns and keys.** This enables non-breaking extension without bumping `schema_version`.

---

## 10. Design rationale

### Why CSV-only on-disk with companion columns for structured content

CSV is the lowest common denominator of tabular-data interchange. Every statistical package, every programming language, every data pipeline reads rectangular CSV natively. JSON is convenient in some environments (Python, JavaScript) and inconvenient in others (Stata, shell scripts). Committing to CSV throughout keeps the bundle readable in any rectangular-data tool.

Where a value naturally has structured form (the value set `{code: label}` dict), `value_labels.csv` provides **both** a JSON column and a companion pre-formatted string column. Redundant on purpose — consumers pick whichever fits.

Concrete consequences:

1. `release_sets.csv` is a junction table, not a JSON-array-per-row file. Any rectangular tool reads it with a standard merge / join
2. `value_labels.csv` provides both JSON and pre-formatted views
3. The manifest is a flat key-value CSV, not JSON
4. No JSON columns in `scope.csv`, `variables.csv`, or `release_sets.csv` — all scalar
5. Scope depth is declared in the manifest via integer + string keys and loops — any key-value-CSV reader can iterate `scope_level_N_*` keys to learn the hierarchy depth

### Why `scope` (not `context`, not `register`) — and why separate columns per level

"Register" is SCB-inflected. "Context" is overloaded in the LLM era. **"Scope"** is unambiguous, matches programming semantics (variable scope = the range where a declaration applies), and reads naturally in filter syntax.

Scope levels are stored as **separate columns** rather than a single slash-separated string because:

1. **No delimiter collision.** Agency names can contain slashes (e.g. `Hälso-/sjukvårdsregistret`). Separate columns eliminate sanitization — original names are used directly.
2. **Each level is independently queryable.** `keep if scope_level_1 == "LISA"` works without substring parsing.
3. **Native argument passing.** `autolabel variables, scope("LISA" "Individer 16 år och äldre")` — users pass levels as separate quoted strings. No slash-splitting boilerplate.
4. **Each level can have its own alias.** `scope_level_1_alias` enables short-code lookups without conflating alias semantics with the hierarchical path.

### Why `release` (not `version`, not `period`)

"Version" implies semver. "Period" implies continuous time intervals — but SCB's six observed release patterns include calendar dates, content-tagged editions, and future pre-announced events. **"Release"** is the universal data-publishing term with no temporal presumption.

### Why scope and release are separate axes

**Scope is identity.** `kon` in LISA and `kon` in STATIV are different conceptual variables — different labels, different value sets, different meaning.

**Release is temporal.** `kon` in LISA 2005 and `kon` in LISA 2006 are the *same* conceptual variable across editions.

This asymmetry is what enables `release_sets.csv` to compress variable rows. A release set captures "this exact variable metadata was stable across *these releases* within a fixed scope" — a many-to-many relationship between variable-metadata tuples and temporal atoms. For SCB, this compresses what would otherwise be ~521,000 (variable × atom) flat rows into ~80,230 `variables.csv` rows + ~81,693 junction rows.

The release_set invariant (§6 rule 4) formalizes this: all atoms within a release set must share the same scope. This constraint is only expressible when scope and release are distinguished axes.

### Why integer foreign keys throughout

No text duplication, referential integrity enforceable, integer-join performance.

### Why atomic scope.csv

Non-contiguous releases (election years) are explicit. Each row is one fact. No range parsing.

### Why junction-table release_sets.csv

A junction table reads natively in every rectangular-data tool — Stata (`import delimited` + `merge`), Python (`pandas.read_csv` + `merge`), R (`read.csv` + `merge`), DuckDB or any SQL engine (`SELECT … JOIN`). A JSON array inside a CSV cell would force consumers to parse JSON. Bundle-size cost of junction-vs-array is modest (~81,693 rows / 1.2 MB for SCB). Universal readability wins.

### Why dynamic scope depth (not fixed register+variant)

Fixed 2-level scope would lock the format to a Nordic register-data taxonomy. Future agencies with different hierarchies (3-level, 5-level, or differently-named 2-level) would require a breaking schema bump. Dynamic depth declared in the manifest is agency-neutral and future-proof. SCB and DST use 2 levels (register/variant); SSB uses 2 differently-named levels (source/group); a hypothetical future agency can use 4.

---

## Worked examples

### Example 1 — `kon` in LISA, stable across 1990–2009

**`scb_scope_eng.csv`** (20 atomic rows):
```csv
scope_id;scope_level_1;scope_level_1_alias;scope_level_2;release;…
1001;"Longitudinell integrationsdatabas…";"LISA";"Individer 16 år och äldre";"1990";…
…
1020;"Longitudinell integrationsdatabas…";"LISA";"Individer 16 år och äldre";"2009";…
```

**`scb_variables_eng.csv`** (1 row — fully compressed via both FKs):
```csv
variable_name;variable_label;…;datatype;value_label_id;release_set_id
kon;Gender;…;char(1);1;42
```

**`scb_value_labels_eng.csv`** (1 row with both JSON and Stata columns):
```csv
value_label_id;variable_name;value_labels_json;value_labels_stata;code_count
1;kon;"{""1"":""Man"",""2"":""Kvinna""}";"""1"" ""Man"" ""2"" ""Kvinna""";2
```

**`scb_release_sets_eng.csv`** (20 junction rows for release_set_id=42):
```csv
release_set_id;scope_id
42;1001
42;1002
…
42;1020
```

Stata query for "kon in LISA 2005":
```stata
import delimited using "scb_scope_eng.csv", clear delimiters(";")
keep if scope_level_1_alias == "LISA" & release == "2005"
levelsof scope_id, local(rv)    // gets 1015

import delimited using "scb_release_sets_eng.csv", clear delimiters(";")
keep if scope_id == `rv'
levelsof release_set_id, local(rs)    // gets 42

import delimited using "scb_variables_eng.csv", clear delimiters(";")
keep if variable_name == "kon" & release_set_id == `rs'
```

### Example 2 — `V_antros` with datatype change

`V_antros` is `float` in Regionfullmäktigeval elections 1988–2018 (12 elections) and `int` in 2022.

**`scb_variables_eng.csv`** (2 rows — metadata drift causes split):
```csv
variable_name;…;datatype;value_label_id;release_set_id
V_antros;…;float;;43
V_antros;…;int;;44
```

**`scb_release_sets_eng.csv`**:
```csv
release_set_id;scope_id
43;2791
43;2795
…
43;2835
44;2847
```

12 rows for set 43 (float era) + 1 row for set 44 (2022 int).

### Example 3 — hypothetical 4-level agency

Manifest declares `scope_depth = 4`. `scope.csv` has 12 scope columns (4 levels × 3 columns each: name, alias, description). `autolabel`'s browse code loops `1/scope_depth` and handles 4 levels without code changes. Zero schema modification.

---

## Filtering in autolabel

### By scope

```stata
autolabel variables, domain(scb) lang(eng) scope("LISA" "Individer_16_och_äldre")
autolabel variables, domain(scb) lang(eng) scope("LISA")    // level 1 only — matches all LISA variants
```

### By release

```stata
autolabel variables, domain(scb) lang(eng) scope("LISA") release("2005")
```

### Automatic inference

When no `scope()` is specified, `autolabel` analyzes your dataset's variables to find the best-matching scope and reports which one was inferred with a match percentage.

---

## Institutional metadata

Any institution can create autolabel-compatible metadata for use with `autolabel`. Create the 5 semicolon-delimited CSV files following the schema above, place them in `~/.registream/autolabel/{domain}/`, and use with:

```stata
autolabel variables, domain(yourdomain) lang(eng)
```

No internet access required.

---

## Stata usage

### Basic

```stata
autolabel variables, domain(scb) lang(eng)
autolabel values, domain(scb) lang(eng)
```

### Scope-specific

```stata
autolabel variables, domain(scb) lang(eng) scope("LISA" "Individer_16_och_äldre") release("2005")
autolabel values, domain(scb) lang(eng) scope("LISA" "Individer_16_och_äldre") release("2005")
```

### Lookup

```stata
autolabel lookup kon, domain(scb) lang(eng)
autolabel lookup kon, domain(scb) lang(eng) detail
autolabel lookup kon, domain(scb) lang(eng) scope("LISA")
```

### Browse scopes

```stata
autolabel scope, domain(scb) lang(eng)
autolabel scope LISA, domain(scb) lang(eng)
```

---

## Python usage

```python
import registream.autolabel

df.autolabel(domain="scb", lang="eng")                                              # auto-infer scope
df.autolabel(domain="scb", lang="eng", scope=["LISA", "Individer_16_och_äldre"])   # by scope levels
df.autolabel(domain="scb", lang="eng", release="2005")                              # filter by release

df.rs.lookup("kon")                 # all scopes
df.rs.lookup("kon", detail=True)    # all rows
```

---

## Migration from the pre-finalized format

Older bundles (3 files: `variables` + `value_labels` + `registers` with inline `register/variant/versions` columns and pipe-delimited `versions`) are obsolete. Autolabel schema v2 replaces them with the 5-file normalized layout described here.

| Pre-finalized layout | Autolabel schema v2 |
|---|---|
| 3 files per language | **5 files** per language (+ manifest + release_sets) |
| `register_id` FK on variables | **`release_set_id`** FK (junction table) |
| Pipe-delimited `versions` column | **Atomic rows** in scope; **junction table** in release_sets |
| `register` + `variant` columns | **`scope_level_N`** separate columns (dynamic depth) |
| `version` column | **`release`** opaque string |
| No manifest | **Manifest CSV** per language per domain |

---

## Further reading

- Type `help autolabel` in Stata for full syntax documentation
- See [autolabel/README.md](../README.md) for command reference and examples
