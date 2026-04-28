# %% [markdown]
# # autolabel: manual smoke test
#
# Python analog of ``autolabel/stata/dev/test_manual.do``. Runs top-to-bottom
# in a Python interpreter, as a script, or cell-by-cell in Jupyter / VS
# Code's interactive window (each ``# %%`` starts a new cell).
#
# Prerequisites (run once in a shell before starting):
#
# ```bash
# cd ~/Github/registream-org/autolabel/python/registream-autolabel
# rm -rf ~/.registream/autolabel ~/.registream/datasets.csv  # optional clean slate
# uv sync
# ```
#
# The dev API server at ``localhost:5000`` must be running for the
# ``update_datasets`` calls to succeed; without it the bundle loads will
# fail because the cache is empty.

# %% [markdown]
# ## 0. Host override: point at the local dev API

# %%
import os
import sys

os.environ["REGISTREAM_API_HOST"] = "http://localhost:5000"

import pandas as pd

import registream.autolabel
from registream.autolabel import scope, update_datasets

# %% [markdown]
# ## 1. Download the bundle (no-op if already cached, force=True to re-fetch)

# %%
result = update_datasets("scb", "eng", force=False)
print(result)

# %% [markdown]
# ## 2. Lookups
#
# Stata shows clickable SMCL hyperlinks that drill from one command into
# the next. Jupyter / plain Python does not have that affordance, so
# instead of clicking, copy the command shown below each result and paste
# it into the next cell. Every follow-up is a real Python expression.

# %%
pd.DataFrame({"x": [1]}).rs.lookup("carb", domain="scb", lang="eng")

# %%
pd.DataFrame({"x": [1]}).rs.lookup("ssyk3", domain="scb", lang="swe")

# %%
pd.DataFrame({"x": [1]}).rs.lookup("ssyk3", domain="scb", lang="swe", detail=True)

# %% [markdown]
# ## 3. Browse scopes
#
# The module-level ``registream.autolabel.scope()`` is the Python analog
# of ``autolabel scope [<filter>]`` in Stata. At each level it returns a
# DataFrame that Jupyter renders as a table. To "click" into a row,
# copy the ``scope_level_1`` value into the next ``scope=[...]`` call.

# %%
scope(domain="scb", lang="eng")

# %%
scope(domain="scb", lang="eng", search="lisa")

# %%
scope(domain="scb", lang="eng", search="election")

# %%
scope(domain="scb", lang="swe", search="kommunfullmäktige")

# %% [markdown]
# ## 4. Waterfall: drill from a scope down to a single variable's labels

# %%
scope(domain="scb", lang="eng", search="LISA")

# %%
# Level-2 variants under LISA
scope(domain="scb", lang="eng", scope=["LISA"])

# %%
# Releases for one (scope_level_1, scope_level_2) atom
scope(
    domain="scb",
    lang="eng",
    scope=["LISA", "Individuals aged 16 and older"],
)

# %%
# Overflow: third token → release, output is the variables at that atom
scope(
    domain="scb",
    lang="eng",
    scope=["LISA", "Individuals aged 16 and older", "2005"],
)

# %%
# Variable metadata, including the alternative (STATIV) scope
pd.DataFrame({"x": [1]}).rs.lookup("kon", domain="scb", lang="eng", detail=True)

# %% [markdown]
# ## 5. Load the example dataset and auto-label
#
# Uses the shared example at ``autolabel/examples/lisa.dta`` so the
# Python and Stata dev scripts exercise the same data.

# %%
from pathlib import Path

EXAMPLES = Path(__file__).resolve().parents[3] / "examples" / "lisa.dta"
df = pd.read_stata(EXAMPLES)
df.head()

# %%
# Inference should detect LISA from the column names.
df.rs.autolabel(domain="scb", lang="eng")
print("schema_version:", df.attrs.get("schema_version"))
print("inferred scope:", df.attrs["registream"]["scope"])
df.rs.variable_labels()

# %%
df.rs.value_labels()

# %%
# Labeled view (non-mutating): codes shown with labels
df.rs.lab.head()

# %% [markdown]
# ## 6. Reload and pin the scope explicitly

# %%
df = pd.read_stata(EXAMPLES)
df.rs.autolabel(domain="scb", lang="eng", scope=["LISA"])
df.rs.variable_labels()

# %% [markdown]
# ## 7. Release pin: overflow-token syntax
#
# Passing ``scope_depth + 1`` tokens promotes the last one to
# ``release=...``. Mirrors Stata's rule at ``autolabel.ado:1499–1502``.

# %%
df = pd.read_stata(EXAMPLES)
df.rs.autolabel(
    domain="scb",
    lang="eng",
    scope=["LISA", "Individuals aged 16 and older", "2005"],
)
print("release:", df.attrs["registream"]["release"])
df.rs.variable_labels()

# %% [markdown]
# ## 8. Lookup with scope narrowing

# %%
pd.DataFrame({"x": [1]}).rs.lookup(
    "kon",
    domain="scb",
    lang="eng",
    scope=["STATIV"],
    detail=True,
)

# %% [markdown]
# ## 9. Seaborn integration: plots "just work"
#
# Importing ``registream.autolabel`` lazily wraps the common seaborn
# plotting functions so passing ``data=df`` (or ``data=df.rs.lab``) pulls
# value labels onto the categorical axes and sets axis titles from
# ``variable_labels``. Opt out with ``REGISTREAM_NO_PLOT_PATCH=1`` before
# importing.

# %%
import matplotlib.pyplot as plt
import seaborn as sns

df = pd.read_stata(EXAMPLES)
df.autolabel(domain="scb", lang="eng")

categorical_cols = list(df.value_labels().keys())
first = categorical_cols[0]

fig, ax = plt.subplots(figsize=(8, 4))
sns.countplot(data=df, x=first, ax=ax)
ax.tick_params(axis="x", rotation=30)
plt.tight_layout()
# In a non-interactive script, save to disk instead of plt.show() (which
# blocks waiting for window-close). Cell-by-cell in Jupyter still renders.
if "VSCODE_PID" in os.environ or hasattr(sys, "ps1"):
    plt.show()
else:
    out = Path(__file__).parent / "test_manual_plot.png"
    fig.savefig(out, dpi=100)
    print(f"saved plot to {out}")
