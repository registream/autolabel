{smcl}
{* *! version {{VERSION}} {{STHLP_DATE}}}{...}

{vieweralsosee "" "--"}{...}
{vieweralsosee "registream" "help registream"}{...}
{viewerjumpto "Syntax" "autolabel##syntax"}{...}
{viewerjumpto "Description" "autolabel##description"}{...}
{viewerjumpto "Options" "autolabel##options"}{...}
{viewerjumpto "Labeling rules" "autolabel##rules"}{...}
{viewerjumpto "Preview coverage (suggest)" "autolabel##suggest"}{...}
{viewerjumpto "Deferred execution" "autolabel##deferred"}{...}
{viewerjumpto "Stored results" "autolabel##results"}{...}
{viewerjumpto "Examples" "autolabel##examples"}{...}
{viewerjumpto "Important Limitations" "autolabel##limitations"}{...}
{viewerjumpto "Institutional metadata" "autolabel##institutional"}{...}
{viewerjumpto "See also" "autolabel##seealso"}{...}
{viewerjumpto "Authors" "autolabel##authors"}{...}
{viewerjumpto "Citing RegiStream" "autolabel##citation"}{...}
{title:Title}

{p2colset 5 18 20 2}{...}
{p2col :{cmd:autolabel} {hline 2}}Automatically apply variable and value labels from structured metadata{p_end}
{p2colreset}{...}

{pstd}
Part of the {help registream:RegiStream} ecosystem for register data research.
{p_end}

{marker syntax}{...}
{title:Syntax}

{pstd}
{ul:Labeling commands}
{p_end}

{p 8 15 2}
{cmd:autolabel variables} [{it:varlist}] {cmd:,} {opth domain(string)} {opth lang(string)}
[{opth scope(string asis)} {opth release(string)}
{opth exclude(varlist)} {opth suffix(string)} {opt dryrun} {opth savedo(filename)}]
{p_end}

{p 8 15 2}
{cmd:autolabel values} [{it:varlist}] {cmd:,} {opth domain(string)} {opth lang(string)}
[{opth scope(string asis)} {opth release(string)}
{opth exclude(varlist)} {opth suffix(string)} {opt dryrun} {opth savedo(filename)}]
{p_end}

{pstd}
{ul:Inspection commands}
{p_end}

{p 8 15 2}
{cmd:autolabel lookup} {it:varlist} {cmd:,} {opth domain(string)} {opth lang(string)}
[{opth scope(string asis)} {opt detail}]
{p_end}

{p 8 15 2}
{cmd:autolabel scope} [{it:search}] {cmd:,} [{opth domain(string)} {opth lang(string)}
{opth scope(string asis)} {opt list}]
{p_end}

{p 8 15 2}
{cmd:autolabel suggest} {cmd:,} {opth domain(string)} {opth lang(string)}
[{opth scope(string asis)} {opt list}]
{p_end}

{pstd}
{ul:Maintenance commands}
{p_end}

{p 8 15 2}
{cmd:autolabel update} [{cmd:package}|{cmd:datasets}] [{cmd:,} {opth domain(string)} {opth lang(string)} {opth version(string)}]
{p_end}

{p 8 15 2}
{cmd:autolabel info}
{p_end}

{p 8 15 2}
{cmd:autolabel version}
{p_end}

{p 8 15 2}
{cmd:autolabel cite}
{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:autolabel} applies variable labels and value labels from structured metadata
to datasets. It downloads and caches metadata from {browse "https://registream.org"},
then matches variables in your dataset against the metadata catalog to apply
human-readable labels.
{p_end}

{pstd}
RegiStream hosts metadata for six Nordic register agencies: Statistics
Sweden ({cmd:scb}), Statistics Denmark ({cmd:dst}), Statistics Norway
({cmd:ssb}), F{c o:}rs{c a:}kringskassan ({cmd:fk}), Socialstyrelsen
({cmd:sos}), and Statistics Iceland ({cmd:hagstofa}). More domains will
be announced as they ship; see
{browse "https://registream.org/catalog":registream.org/catalog} for the
current list. Any institution can also create metadata files for their
own data sources; see
{help autolabel##institutional:Institutional metadata} below.
{p_end}

{pstd}
{bf:Autolabel schema v2} metadata preserves register-level context: each
variable can appear in multiple scopes (registers, sub-populations) with different
labels, value definitions, and releases. When no {opt scope()} is specified,
{cmd:autolabel} automatically infers the best-matching scope by analyzing the
variables in your dataset.
{p_end}

{pstd}
{bf:Scope levels} are defined per domain. For Statistics Sweden, the two scope
levels are {it:Register} (e.g. LISA) and {it:Variant} (e.g. Individer 16 år och
äldre). For Statistics Norway, the levels are {it:Source} and {it:Group}. Scope
levels and their names are declared in each domain's manifest file and can vary
across providers. The schema supports any depth.
{p_end}

{pstd}
{bf:First-run setup:} When you first use {cmd:autolabel}, RegiStream will ask you to
choose a setup mode (Offline, Standard, or Full Mode). This determines whether
metadata is downloaded automatically and whether usage data is collected.
You can change these settings later using {cmd:registream config}.
See {help registream:registream} for details.
{p_end}


{marker options}{...}
{title:Options}

{dlgtab:Required}

{phang}
{opt domain(string)}
The metadata domain. Each domain represents an institution or data provider
(e.g., {cmd:scb} for Statistics Sweden, {cmd:dst} for Statistics Denmark).
Institutions can create custom domains for their own data;
see {help autolabel##institutional:Institutional metadata}.
{p_end}

{phang}
{opt lang(string)}
The language for labels. Available languages depend on the domain.
For {cmd:scb}: {cmd:eng} (English) or {cmd:swe} (Swedish).
{p_end}

{dlgtab:Filtering}

{phang}
{opt scope(string asis)}
Filter metadata to a specific scope within the domain. Pass one or more
quoted strings, one per scope level. For SCB (2-level: Register + Variant):
{p_end}

{pmore}
{cmd:scope("LISA")}: matches all sub-scopes under LISA{break}
{cmd:scope("LISA" "Individer 16 år och äldre")}: matches that specific scope
{p_end}

{pmore}
Each quoted token is matched against the corresponding scope level column.
Matching priority per level: (1) exact alias match (case-insensitive),
then (2) name substring match (case-insensitive). For example,
{cmd:scope("LISA")} matches the alias "LISA"; {cmd:scope("Integration")} matches
the full name "Longitudinell integrationsdatabas..." via substring.
{p_end}

{pmore}
When omitted, {cmd:autolabel} automatically infers the best-matching scope
by analyzing which scope's variable list best overlaps your dataset's variables.
The detected scope and match percentage are displayed.
{p_end}

{phang}
{opt release(string)}
Filter to a specific release. For example, {cmd:release(2005)} keeps metadata
rows whose release set includes the "2005" release. Useful when value
label sets change over time (e.g., municipality codes, education classifications).
{p_end}

{dlgtab:Output}

{phang}
{opt exclude(varlist)}
Variables to exclude from labeling.
{p_end}

{phang}
{opt suffix(string)}
Append a suffix to create new labeled variables instead of modifying existing ones.
When using {cmd:autolabel values} on string categorical variables, the original
string codes are permanently replaced with numeric codes. Use {opt suffix()} to
preserve the original variable. See {help autolabel##limitations:Important Limitations}.
{p_end}

{phang}
{opt detail}
For {cmd:autolabel lookup} only. Equivalent to {cmd:autolabel scope, var(}{it:varlist}{cmd:)}:
opens the scope/register tree filtered to the looked-up variable(s) so you
can drill register {c -} variant {c -} release while keeping the variable in focus.
Without {opt detail}, lookup shows one block per variable with the most
common label and a scope count.
{p_end}

{phang}
{opt var(varlist)}
For {cmd:autolabel scope} only. Restrict the scope-browse to scopes that
contain at least one of the listed variables. The filter is sticky: every
drill click in the resulting view carries {opt var()} forward, so the user
stays focused on the variable as they navigate. Drop the filter by re-running
{cmd:autolabel scope} without {opt var()}.
{p_end}

{phang}
{opt list}
For {cmd:autolabel scope} and {cmd:autolabel suggest}. Show all matching
scopes (or coverage entries) instead of the default top-10 view.
{p_end}

{dlgtab:Deferred execution}

{phang}
{opt dryrun}
Display the generated labeling commands without executing them. The commands are
shown exactly as they would be applied, so you can inspect what {cmd:autolabel}
will do before it modifies your dataset. See
{help autolabel##deferred:Deferred execution} below.
{p_end}

{phang}
{opt savedo(filename)}
Save the generated labeling commands to a do-file without executing them.
The saved file is a complete, executable do-file that can be reviewed, edited,
and run later with {cmd:do}. See {help autolabel##deferred:Deferred execution} below.
{p_end}


{marker rules}{...}
{title:Labeling rules}

{pstd}
When multiple metadata rows match a variable, {cmd:autolabel} resolves
the ambiguity via the rules below.
{p_end}

{dlgtab:Automatic mode (no pin)}

{pstd}
With no {opt scope()} or {opt release()}, {cmd:autolabel} infers a
{it:primary scope} by counting how many of your variables each scope
covers. The winner is reported as "Primary scope (inferred)". For each
variable with at least one metadata row, autolabel then picks the
winning row by priority:
{p_end}

{phang2}{it:(a)} if the variable is in the inferred primary scope, use
that scope's row;
{p_end}

{phang2}{it:(b)} otherwise use the row whose {it:label} appears most
often across the variable's candidate rows (majority fallback);
{p_end}

{phang2}{it:(c)} deterministic tiebreak on scope-level columns for
reproducibility.
{p_end}

{pstd}
Every variable with a metadata row gets labeled. The primary is a
{it:preference}, not a filter. The success message reports the split
("X from primary scope, Y from majority fallback, Z skipped, existing
labels preserved"). If the top scope covers fewer than 10% of
variables, autolabel reports "no strong primary scope" and falls back
to majority-rule for every variable.
{p_end}

{dlgtab:Explicit-pin mode}

{pstd}
With {opt scope()} (and optionally {opt release()}), autolabel filters
metadata to the pinned subset before the collapse. Variables not found
in the pinned subset are skipped. {bf:Their pre-existing labels are
preserved}, making it safe to chain multiple pins for multi-scope
panels without overwriting earlier work.
{p_end}

{phang2}{cmd:. autolabel variables lopnr kon alder, ///}{break}
{cmd:    domain(scb) lang(eng) scope("LISA" "Individer 16 år och äldre")}{break}
{cmd:. autolabel variables cfarnr bransch, ///}{break}
{cmd:    domain(scb) lang(eng) scope("Företagsregister")}{p_end}

{pstd}
If the same variable is listed in two pinned calls, the later call
wins (standard Stata {cmd:label variable} semantics).
{p_end}


{marker suggest}{...}
{title:Preview coverage (autolabel suggest)}

{pstd}
{cmd:autolabel suggest} reports which scopes would contribute labels
under automatic mode on your currently-loaded dataset, without
applying anything. Recommended first step for mixed-panel workflows.
{p_end}

{p 8 15 2}
{cmd:autolabel suggest} {cmd:,} {opth domain(string)} {opth lang(string)}
[{opth scope(string asis)} {opt list}]
{p_end}

{dlgtab:Top-level view}

{phang2}{cmd:. autolabel suggest, domain(scb) lang(eng)}{p_end}

{pstd}
Prints a coverage table: {it:Scope} (name, clickable), {it:Count}
(variables labeled from this scope), {it:Share} (% of dataset).
Leading {cmd:*} marks the inferred primary. Top 10 by default; pass
{opt list} to show all.
{p_end}

{dlgtab:Scope-detail view}

{phang2}{cmd:. autolabel suggest, domain(scb) lang(eng) scope("LISA")}{p_end}

{pstd}
Lists the variables that would be labeled from LISA, their labels,
and a copy-pasteable explicit-pin command for the subset. This is
the foundation of the multi-scope panel workflow in
{help autolabel##rules:Labeling rules}.
{p_end}


{marker deferred}{...}
{title:Deferred execution}

{pstd}
{opt dryrun} prints the labeling commands without executing them.
{opt savedo(filename)} writes them to an executable do-file you can
review, edit, and {cmd:do} later. Both options apply to
{cmd:autolabel variables} and {cmd:autolabel values};
{cmd:lookup} is always non-destructive.
{p_end}

{phang2}{cmd:. autolabel variables, domain(scb) lang(eng) dryrun}{p_end}
{pmore}Preview the commands that would run.{p_end}

{phang2}{cmd:. autolabel variables, domain(scb) lang(eng) savedo("my_labels.do")}{p_end}
{pmore}Save for review, then {cmd:do "my_labels.do"} when satisfied.{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
Every {cmd:autolabel} subcommand sets {cmd:r()} so callers can inspect or compose
follow-up commands. The shared core (always set) is:
{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(status)}}0 on success, 1 on error{p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:r(dir)}}resolved metadata directory for the active domain{p_end}
{synopt:{cmd:r(domain)}}echo of the {opt domain()} argument{p_end}
{synopt:{cmd:r(lang)}}echo of the {opt lang()} argument{p_end}

{pstd}
{cmd:autolabel variables} and {cmd:autolabel values} additionally set:
{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(n_total)}}total dataset variables walked{p_end}
{synopt:{cmd:r(n_primary)}}variables labeled from the primary scope{p_end}
{synopt:{cmd:r(n_fallback)}}variables labeled via majority fallback{p_end}
{synopt:{cmd:r(n_skipped)}}variables not in the catalog{p_end}
{synopt:{cmd:r(display_depth)}}depth at which {cmd:r(inferred_scope)} was rendered{p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:r(primary)}}primary scope chosen by inference (empty if {opt scope()} pinned){p_end}
{synopt:{cmd:r(inferred_scope)}}inferred primary scope as a quoted-token list, round-trippable into {cmd:scope()}{p_end}
{synopt:{cmd:r(primary_vars)}}space-separated list, variables labeled from primary{p_end}
{synopt:{cmd:r(fallback_vars)}}space-separated list, variables labeled from other scopes{p_end}
{synopt:{cmd:r(skipped_vars)}}space-separated list, variables not in the catalog{p_end}

{pstd}
{cmd:autolabel suggest} sets the same partition as a preview, plus {cmd:r(unmatched_vars)}
listing dataset variables not matched anywhere in the catalog and {cmd:r(match_pct)}
giving the primary scope's coverage as a percentage of {cmd:r(n_total)}. The contract is:
{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(n_total)}}total dataset variables{p_end}
{synopt:{cmd:r(n_primary)}}variables in primary scope{p_end}
{synopt:{cmd:r(n_fallback)}}variables matched via majority fallback{p_end}
{synopt:{cmd:r(n_unmatched)}}variables not in catalog at all{p_end}
{synopt:{cmd:r(match_pct)}}primary scope coverage (percent of n_total){p_end}
{synopt:{cmd:r(display_depth)}}depth at which {cmd:r(inferred_scope)} was rendered{p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:r(primary)}}primary scope name{p_end}
{synopt:{cmd:r(inferred_scope)}}inferred primary scope as a quoted-token list, round-trippable into {cmd:scope()}{p_end}
{synopt:{cmd:r(primary_vars)}}variables that would label from primary{p_end}
{synopt:{cmd:r(fallback_vars)}}variables that would label via fallback{p_end}
{synopt:{cmd:r(unmatched_vars)}}variables not in the catalog{p_end}

{pstd}
{cmd:autolabel lookup} sets:
{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(n_total)}}variables looked up{p_end}
{synopt:{cmd:r(n_found)}}variables found in the catalog{p_end}
{synopt:{cmd:r(n_unmatched)}}variables not found{p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:r(found_vars)}}space-separated list, variables found{p_end}
{synopt:{cmd:r(unmatched_vars)}}space-separated list, variables not found{p_end}

{pstd}
{cmd:autolabel scope} sets:
{p_end}

{synoptset 22 tabbed}{...}
{p2col 5 22 26 2: Scalars}{p_end}
{synopt:{cmd:r(scope_level)}}depth of the current navigation (0, 1, 2, ...){p_end}

{p2col 5 22 26 2: Macros}{p_end}
{synopt:{cmd:r(parent_scope)}}the {opt scope()} token chain in effect, if any{p_end}

{pstd}
The partition macros enable a composable pattern: run {cmd:autolabel suggest} once,
then loop or compose follow-up calls without re-running primary inference. See the
example block below.
{p_end}


{marker examples}{...}
{title:Examples}

{dlgtab:Basic labeling}

{phang2}{cmd:. autolabel variables, domain(scb) lang(eng)}{p_end}
{pmore}Label all variables using SCB metadata in English.{p_end}

{phang2}{cmd:. autolabel values, domain(scb) lang(swe)}{p_end}
{pmore}Apply value labels to all variables using SCB metadata in Swedish.{p_end}

{phang2}{cmd:. autolabel variables ku*ink yrkarbtyp, domain(scb) lang(eng) exclude(ku3ink)}{p_end}
{pmore}Label specific variables (with wildcard), excluding {cmd:ku3ink}.{p_end}

{phang2}{cmd:. autolabel values kon, domain(scb) lang(eng) suffix("_lbl")}{p_end}
{pmore}Create a new labeled variable {cmd:kon_lbl}, preserving the original.{p_end}

{dlgtab:Scope-specific labeling}

{phang2}{cmd:. autolabel variables, domain(scb) lang(eng) scope("LISA") release("2005")}{p_end}
{pmore}Apply labels specific to LISA for the 2005 release.
For example, {cmd:kon} receives the label "Gender" (from LISA),
not "Gender of child" (from Barnregistret).{p_end}

{phang2}{cmd:. autolabel variables, domain(scb) lang(eng) scope("LISA" "Individer 16 år och äldre")}{p_end}
{pmore}Apply labels from a specific scope level 1 + level 2 combination using
multi-string syntax.{p_end}

{phang2}{cmd:. autolabel values, domain(scb) lang(eng) scope("Barnregistret")}{p_end}
{pmore}Apply value labels from Barnregistret using scope level 1 match.{p_end}

{dlgtab:Lookup and inspection}

{phang2}{cmd:. autolabel lookup kon kommun, domain(scb) lang(eng)}{p_end}
{pmore}Display metadata for {cmd:kon} and {cmd:kommun} across all scopes.{p_end}

{phang2}{cmd:. autolabel lookup kon, domain(scb) lang(eng) detail}{p_end}
{pmore}Open the register/variant tree filtered to {cmd:kon} (equivalent to
{cmd:autolabel scope, var(kon)}). Drill registers and variants with the
variable carried as a sticky filter.{p_end}

{dlgtab:Browse and drill into scopes}

{phang2}{cmd:. autolabel scope, domain(scb) lang(eng)}{p_end}
{pmore}Browse top-level scopes (first 10).{p_end}

{phang2}{cmd:. autolabel scope LISA, domain(scb) lang(eng)}{p_end}
{pmore}Search for scopes matching "LISA" by name or alias.{p_end}

{phang2}{cmd:. autolabel scope, domain(scb) lang(eng) scope("LISA")}{p_end}
{pmore}Drill into LISA, showing sub-scopes (variants) with release counts.{p_end}

{phang2}{cmd:. autolabel scope, domain(scb) lang(eng) scope("LISA" "Individer 16 år och äldre")}{p_end}
{pmore}Show releases for a specific scope.{p_end}

{phang2}{cmd:. autolabel scope, domain(scb) lang(eng) scope("LISA" "Individer 16 år och äldre" "2005")}{p_end}
{pmore}Show variables in a specific release (overflow token = release).{p_end}

{phang2}{cmd:. autolabel scope, domain(scb) lang(eng) list}{p_end}
{pmore}Show all scopes (no 10-row limit).{p_end}

{phang2}{cmd:. autolabel scope, domain(scb) lang(eng) var(ssyk4)}{p_end}
{pmore}Browse only registers that contain {cmd:ssyk4}; drill clicks keep
the filter active.{p_end}

{dlgtab:Deferred execution}

{phang2}{cmd:. autolabel variables, domain(scb) lang(eng) dryrun}{p_end}
{pmore}Preview labeling commands without applying them.{p_end}

{phang2}{cmd:. autolabel values, domain(scb) lang(eng) savedo("my_value_labels.do")}{p_end}
{pmore}Save value labeling commands to a do-file for review.{p_end}

{dlgtab:Composing labels via stored returns}

{phang2}{cmd:. autolabel suggest, domain(scb) lang(eng)}{p_end}
{pmore}Preview which scopes cover which dataset variables.{p_end}

{phang2}{cmd:. autolabel variables `r(primary_vars)', domain(scb) lang(eng) scope("`r(primary)'")}{p_end}
{pmore}Label the primary-scope variables cleanly with one explicit pin.{p_end}

{phang2}{cmd:. autolabel lookup `r(fallback_vars)', domain(scb) lang(eng)}{p_end}
{pmore}Inspect fallback variables to decide which scope to pin per group.{p_end}

{dlgtab:Dataset updates}

{phang2}{cmd:. autolabel update datasets}{p_end}
{pmore}Check for and download metadata updates for all cached domains.{p_end}

{phang2}{cmd:. autolabel update datasets, domain(scb) lang(eng)}{p_end}
{pmore}Check for updates for a specific domain and language.{p_end}

{marker limitations}{...}
{title:Important Limitations}

{pstd}
{bf:String categorical variables lose original data}
{p_end}

{pstd}
When using {cmd:autolabel values} on {bf:string categorical variables}, the original
string codes are permanently replaced with sequential numeric codes (1, 2, 3...).
This means:
{p_end}

{phang2}
{hline 2} Original string codes cannot be recovered after encoding{break}
{hline 2} You cannot filter by original string values after labeling{break}
{hline 2} Re-running {cmd:autolabel values} requires reloading original data
{p_end}

{pstd}
{bf:Numeric categorical variables} do not have this limitation; they preserve
original numeric codes when labels are applied.
{p_end}

{pstd}
{ul:Solution}: Use the {opt suffix()} option to preserve original data:
{p_end}

{phang2}{cmd:. autolabel values astsni2007, domain(scb) lang(eng) suffix("_lbl")}{p_end}

{pstd}
This keeps the original {cmd:astsni2007} variable unchanged and creates a new
labeled variable {cmd:astsni2007_lbl}.
{p_end}


{marker institutional}{...}
{title:Institutional metadata}

{pstd}
Any institution can author metadata for use with {cmd:autolabel}. The
minimum-viable bundle is two CSV files
({cmd:{it:domain}_variables_{it:lang}.csv} and
{cmd:{it:domain}_value_labels_{it:lang}.csv}). Adding
{cmd:_scope_}, {cmd:_release_sets_}, and {cmd:_manifest_} files enables
scope-level context and release-version filtering.
{p_end}

{pstd}
Place the files in {cmd:~/.registream/autolabel/{it:domain}/}. No
network access is required; files are read directly from disk:
{p_end}

{phang2}{cmd:. autolabel variables, domain({it:yourdomain}) lang({it:yourlang})}{p_end}

{pstd}
See {browse "https://registream.org/docs/autolabel/schema":registream.org/docs/autolabel/schema}
for the full schema specification, column definitions, and worked examples.
{p_end}

{pstd}
For secure environments (e.g., MONA, remote desktops): an authorized person copies
the CSV files onto the secure server. No runtime network access is needed.
{p_end}


{marker seealso}{...}
{title:See also}

{pstd}
{help registream:registream}: RegiStream core, configuration, updates, and telemetry
{p_end}

{pmore2}
{hline 2} View configuration: {cmd:registream info}{break}
{hline 2} Change settings: {cmd:registream config, option(value)}{break}
{hline 2} Check package updates: {cmd:registream update}{break}
{hline 2} View usage statistics: {cmd:registream stats}
{p_end}


{marker authors}{...}
{title:Authors}

{pstd}Jeffrey Clark{break}
{{AFFILIATION_JEFFREY}}{break}
Email: {browse "mailto:{{EMAIL_JEFFREY}}":{{EMAIL_JEFFREY}}}
{p_end}

{pstd}Jie Wen{break}
{{AFFILIATION_JIE}}{break}
Email: {browse "mailto:{{EMAIL_JIE}}":{{EMAIL_JIE}}}
{p_end}

{marker citation}{...}
{title:Citing RegiStream}

{pstd}
{cmd:autolabel} is part of the {help registream:RegiStream} ecosystem.
Please cite the package as:
{p_end}

{pstd}
{{CITATION_AUTOLABEL_STHLP_APA_VERSIONED}}
{p_end}
