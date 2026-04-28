# registream-autolabel

Apply variable and value labels from the RegiStream catalog to pandas
DataFrames. Native schema v2; depth-agnostic scope; Jupyter-friendly
return types; matplotlib + seaborn plot-label integration.

Full documentation: **<https://registream.org/docs/autolabel/python>**.

## Install

```
pip install registream-autolabel
```

Pulls in `registream-core` as a dependency. For the full ecosystem
(core + autolabel + future modules) you can instead
`pip install registream` (meta-package).

Requires Python 3.11 or later. Pandas is the only hard runtime
dependency besides `registream-core`. Seaborn is optional; install it
separately to light up the label-aware plot wrappers.

## Quick start

```python
import pandas as pd
import registream.autolabel  # side effect: installs autolabel methods on pd.DataFrame

df = pd.read_stata("lisa_2020.dta")

# Apply variable and value labels from SCB metadata (English); scope auto-inferred.
df.autolabel(domain="scb", lang="eng")

# Display-time labeled view without mutating df.
df.lab.head()
```

Labels land on `df.attrs['registream']`; the column data itself is
never mutated.

## What you get as DataFrame methods

Importing the package adds a small set of methods directly onto
`pd.DataFrame`, so the API reads like a native pandas method:

| Method | What it does |
|---|---|
| `df.autolabel(domain, lang, scope, release, …)` | Apply variable + value labels |
| `df.lookup(variables, detail=…)` | Metadata for one or more variables (returns a `LookupResult`) |
| `df.lab` | A `LabeledView` for display-time labeling (a property) |
| `df.variable_labels()` | Dict of variable labels |
| `df.value_labels()` | Dict of value labels |
| `df.get_variable_labels(columns)` / `df.get_value_labels(columns)` | Column-aware getters |
| `df.set_variable_labels({...})` / `df.set_value_labels(col, {...})` | In-place edits |
| `df.copy_labels(source, target)` | Copy a label bundle between columns |
| `df.meta_search(pattern)` | Filter label metadata by regex |

This matches the Stata surface (`autolabel variables, domain(scb)
lang(eng)`) and the R surface (`df |> autolabel(domain = "scb", lang =
"eng")`) verb-for-verb: the data is always the subject; the command is
always the verb.

## Module-level functions

For operations that don't have a single DataFrame as their subject:

```python
from registream.autolabel import suggest, scope, info, cite, update_datasets

suggest(df)                                   # preview coverage; returns SuggestResult
scope(domain="scb", lang="eng")               # catalog browser, no df
update_datasets("scb", "eng")                 # refresh the on-disk metadata bundle

info()                                        # dict: config + cache + versions
cite()                                        # versioned APA citation
```

Full signatures, arguments, labeling rules, and worked examples are on
the [Python reference page](https://registream.org/docs/autolabel/python).

## Command-line

```
python -m registream.autolabel version     # installed autolabel version
python -m registream.autolabel info        # config + cache + versions
python -m registream.autolabel cite        # APA citation
```

## Plotting integration

When seaborn is installed, autolabel wraps 16 plotting functions on
import so value labels show on categorical axes and variable labels flow
into axis titles + legend. Zero extra setup:

```python
import seaborn as sns
import registream.autolabel  # wraps seaborn on import

df.autolabel(domain="scb", lang="eng")

sns.barplot(data=df, x="kon", y="alder")
# x-axis ticks: "Man", "Woman"
# x label:     "Sex"
# y label:     "Age (years)"
```

Opt out with `REGISTREAM_NO_PLOT_PATCH=1`. Pandas column patches (labels
follow through `df["new"] = df["old"]` and `df.rename(columns=...)`) opt
out with `REGISTREAM_NO_PANDAS_PATCH=1`. All three opt-outs read the
environment at import time.

## Library-author opt-out

If you're writing a library that imports `registream.autolabel` as a
transitive dependency and don't want to add methods to your users'
DataFrames, set `REGISTREAM_NO_SHORTCUTS=1` before import. The accessor
(`df.rs.*`) and the module-level functions stay fully available:

```python
from registream.autolabel import autolabel, lookup
autolabel(df, domain="scb", lang="eng")
```

End-user documentation uses the method form throughout; this opt-out
exists so library code doesn't surprise end users.

## Catalog coverage

Metadata bundles ship for Statistics Sweden (`scb`), Statistics Denmark
(`dst`), Statistics Norway (`ssb`), Statistics Iceland (`hagstofa`),
Försäkringskassan (`fk`), and Socialstyrelsen (`sos`). Institutions can
create their own domains; see the
[schema v2 reference](https://registream.org/docs/autolabel/schema) and
the [institutional setup guide](https://registream.org/docs/install/institutional).

## Citation

```
Clark, J. & Wen, J. (2024–). RegiStream: Infrastructure for Register Data Research. https://registream.org
```

`registream.autolabel.cite()` returns the versioned APA form.

## Authors

- Jeffrey Clark — <jeffrey@registream.org>
- Jie Wen — <jie@registream.org>

## License

BSD 3-Clause. See [LICENSE](https://github.com/registream/registream/blob/main/LICENSE).
