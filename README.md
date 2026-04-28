# autolabel

Automatically apply variable and value labels to register data in Stata, Python, and R. Part of the [RegiStream](https://github.com/registream/registream) ecosystem.

Six agency catalogs across four countries ship at v3.0.0: Statistics Sweden (SCB), Statistics Denmark (DST), Statistics Norway (SSB), Statistics Iceland (Hagstofa), Försäkringskassan (FK), and Socialstyrelsen (SOS). About 64,000 distinct variable names, in Swedish, Danish, Norwegian, Icelandic, and English where each agency provides translations.

## Installation

### Stata

```stata
* Install core (required dependency)
net install registream, from("https://registream.org/install/stata/latest") replace

* Install autolabel
net install autolabel, from("https://registream.org/install/stata/latest") replace
```

Developed and tested under Stata 16. Earlier versions may work but have not been verified.

### Python

```bash
pip install registream-autolabel
```

### R

```r
# install.packages("remotes")
remotes::install_github("registream/autolabel", subdir = "r")
```

(CRAN submission is in flight; this is the development install.)

All three clients consume the same metadata bundle and share the same cache at `~/.registream/`, so mixed-platform teams stay in sync.

## Quick Start

```stata
use lisa_2020.dta, clear
autolabel variables, domain(scb) lang(eng)
autolabel values, domain(scb) lang(eng)
```

That's it. Variable labels and value labels are now applied based on the best-matching register in the SCB metadata.

## Commands

### Apply variable labels

```stata
autolabel variables [varlist], domain(string) lang(string) [options]
```

### Apply value labels

```stata
autolabel values [varlist], domain(string) lang(string) [options]
```

### Look up metadata

```stata
autolabel lookup varlist, domain(string) lang(string) [scope(string)] [detail]
```

### Utilities

```stata
autolabel update [package | datasets]    Check for updates
autolabel version                        Show installed version
autolabel info                           Display configuration
autolabel cite                           Citation for publications
```

## Options

| Option | Description |
|--------|-------------|
| `domain(string)` | Metadata domain (e.g. `scb` for Statistics Sweden). **Required.** |
| `lang(string)` | Language: `eng` or `swe`. **Required.** |
| `scope(string)` | Filter to a scope (e.g. `scope("LISA")` or `scope("LISA" "Individer 16+")`). Optional. |
| `release(string)` | Filter to a release identifier (e.g. `"2005"`). Optional. |
| `exclude(varlist)` | Variables to skip. |
| `suffix(string)` | Create new labeled variables with suffix instead of overwriting. |
| `dryrun` | Preview changes without modifying the dataset. |
| `savedo(filename)` | Save labeling commands to a do-file for reproducibility. |
| `detail` | (lookup only) Show every scope level and release entry. |

## Examples

### Basic labeling

```stata
use lisa_2020.dta, clear

* Apply Swedish variable labels
autolabel variables, domain(scb) lang(swe)

* Apply English value labels
autolabel values, domain(scb) lang(eng)
```

### Scope-specific labeling

```stata
* Label using LISA-specific metadata (correct labels for adult registers)
autolabel variables, domain(scb) lang(eng) scope("LISA" "Individer 16 år och äldre") release("2005")
autolabel values, domain(scb) lang(eng) scope("LISA" "Individer 16 år och äldre") release("2005")
```

### Lookup

```stata
* What labels exist for 'kon' across all registers?
autolabel lookup kon, domain(scb) lang(eng)

* Show full detail (every scope level and release)
autolabel lookup kon kommun loneink, domain(scb) lang(eng) detail
```

### Safe preview

```stata
* Preview without modifying
autolabel variables, domain(scb) lang(eng) dryrun

* Save commands to a do-file
autolabel variables, domain(scb) lang(eng) savedo("label_lisa.do")
```

## Autolabel schema v2

Autolabel's data format preserves register-level context via two hierarchical axes (`scope` and `release`) instead of collapsing variables into a single row via majority vote. This means `kon` (gender) correctly gets "Man/Kvinna" labels from adult registers and "Pojke/Flicka" from child registers, rather than one discarding the other.

Each catalog domain ships 5 CSV files per language (manifest + registers + variables + value labels + release sets), all cross-referenced via integer foreign keys. Scope depth and level names are dynamic per domain, declared in the manifest file.

See the [schema documentation](docs/schema.md) for column definitions, filtering examples, and how to create institutional metadata.

## Automatic Scope Inference

When no `scope()` option is specified, `autolabel` analyzes your dataset's variables to find the best-matching scope in the metadata. It reports which scope was inferred and the match percentage.

## Documentation

- [Schema documentation (autolabel schema v2)](docs/schema.md)
- [Changelog](CHANGELOG.md)
- Type `help autolabel` in Stata for full syntax documentation

## Authors

Jeffrey Clark and Jie Wen

## License

BSD 3-Clause. See [LICENSE](LICENSE).
