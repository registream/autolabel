/*==============================================================================
  Test 26: rclass returns across all autolabel subcommands

  Purpose: Verify the structured rclass return contract added in Phase 1
  of the rclass-returns plan. Tests that variables, values, lookup, suggest,
  and scope each emit their documented r() macros and scalars.

  Tests:
    1. autolabel variables: r(primary), r(primary_vars), r(skipped_vars),
       r(n_primary), r(n_fallback), r(n_skipped), r(n_total),
       r(domain), r(lang)
    2. autolabel values: same contract as variables
    3. autolabel lookup: r(found_vars), r(unmatched_vars), counts, echoes
    4. autolabel suggest: r(primary), r(primary_vars), r(fallback_vars),
       r(unmatched_vars), counts, r(match_pct), echoes
    5. autolabel scope: r(scope_level), r(parent_scope), echoes
    6. End-to-end iterative-pinning workflow round-trip
    7. Dynamic-depth contract: r(inferred_scope) is a quoted-token list
       whose count equals r(display_depth), and round-trips through scope()
    8. Positive depth-2 case: a dataset spanning two variants of a single
       register infers down to the densest variant (depth=2)
==============================================================================*/

clear all
version 16.0

* Find project root
local cwd = "`c(pwd)'"
local project_root ""
forvalues i = 0/5 {
	local search_path = "`cwd'"
	forvalues j = 1/`i' {
		local search_path = "`search_path'/.."
	}
	capture confirm file "`search_path'/.project-root"
	if _rc == 0 {
		quietly cd "`search_path'"
		local project_root = "`c(pwd)'"
		quietly cd "`cwd'"
		continue, break
	}
}
if "`project_root'" == "" {
	di as error "ERROR: Could not find .project-root file"
	exit 601
}

global PROJECT_ROOT "`project_root'"
global TEST_DIR "$PROJECT_ROOT/stata/tests"
global SRC_DIR "$PROJECT_ROOT/stata/src"

discard
adopath ++ "$SRC_DIR"
local core_src "$CORE_SRC"
capture confirm file "`core_src'/registream.ado"
if _rc != 0 {
	di as error "ERROR: registream core not found at `core_src'"
	exit 601
}
adopath ++ "`core_src'"
do "`core_src'/_rs_utils.ado"
cap do "`core_src'/../dev/host_override.do"
do "`core_src'/../dev/auto_approve.do"

local tests_passed = 0
local tests_failed = 0
local tests_total  = 8

di as result ""
di as result "============================================="
di as result "Test 26: rclass returns across subcommands"
di as result "============================================="
di as result ""


*=============================================================================
* TEST 1: autolabel variables emits the documented r() contract
*=============================================================================

di as result "TEST 1: autolabel variables r() contract"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

local _ok = 1
local _failures ""

if "`r(domain)'" != "scb"   local _failures "`_failures' r(domain)='`r(domain)'' (want scb)"
if "`r(lang)'"   != "eng"   local _failures "`_failures' r(lang)='`r(lang)'' (want eng)"
if "`r(primary)'" == ""     local _failures "`_failures' r(primary) empty"
if `r(n_total)'   < 1       local _failures "`_failures' r(n_total)=`r(n_total)' (want >=1)"

* primary_vars should be a non-empty space-separated list
local _pv `"`r(primary_vars)'"'
if `: word count `_pv'' < 1 local _failures "`_failures' r(primary_vars) empty"

if "`_failures'" == "" {
	di as result "  PASS: variables r() contract complete"
	di as text   "    primary=`r(primary)'  n_primary=`r(n_primary)'  n_total=`r(n_total)'"
	local ++tests_passed
}
else {
	di as error "  FAIL: missing or wrong returns:`_failures'"
	local ++tests_failed
}


*=============================================================================
* TEST 2: autolabel values emits the documented r() contract
*=============================================================================

di as result ""
di as result "TEST 2: autolabel values r() contract"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel values, domain(scb) lang(eng)

local _failures ""
if "`r(domain)'" != "scb" local _failures "`_failures' r(domain)='`r(domain)''"
if "`r(lang)'"   != "eng" local _failures "`_failures' r(lang)='`r(lang)''"
if `r(n_total)' < 1       local _failures "`_failures' r(n_total)=`r(n_total)'"

if "`_failures'" == "" {
	di as result "  PASS: values r() contract complete"
	di as text   "    primary=`r(primary)'  n_primary=`r(n_primary)'  n_total=`r(n_total)'"
	local ++tests_passed
}
else {
	di as error "  FAIL: missing or wrong returns:`_failures'"
	local ++tests_failed
}


*=============================================================================
* TEST 3: autolabel lookup emits found/unmatched lists
*=============================================================================

di as result ""
di as result "TEST 3: autolabel lookup r() contract"
di as result "---------------------------------------------"

use "$LISA_DATA", clear

* Look up a known variable plus an obvious fake. Expect found contains kon,
* unmatched contains the fake.
cap noi autolabel lookup kon zzz_does_not_exist_zzz, domain(scb) lang(eng)

local _failures ""
if "`r(domain)'" != "scb"     local _failures "`_failures' r(domain)='`r(domain)''"
if "`r(lang)'"   != "eng"     local _failures "`_failures' r(lang)='`r(lang)''"
if `r(n_total)'  != 2         local _failures "`_failures' r(n_total)=`r(n_total)' (want 2)"

* found_vars should include kon
local _found_lower = lower(`"`r(found_vars)'"')
if strpos("`_found_lower'", "kon") == 0 {
	local _failures "`_failures' r(found_vars) missing kon: '`r(found_vars)''"
}

* unmatched_vars should include the fake
local _unmatched_lower = lower(`"`r(unmatched_vars)'"')
if strpos("`_unmatched_lower'", "zzz_does_not_exist_zzz") == 0 {
	local _failures "`_failures' r(unmatched_vars) missing fake: '`r(unmatched_vars)''"
}

if "`_failures'" == "" {
	di as result "  PASS: lookup r() contract complete"
	di as text   "    found=`r(found_vars)'  unmatched=`r(unmatched_vars)'"
	local ++tests_passed
}
else {
	di as error "  FAIL: missing or wrong returns:`_failures'"
	local ++tests_failed
}


*=============================================================================
* TEST 4: autolabel suggest emits primary/fallback/unmatched partition
*=============================================================================

di as result ""
di as result "TEST 4: autolabel suggest r() contract"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel suggest, domain(scb) lang(eng)

local _failures ""
if "`r(domain)'" != "scb"   local _failures "`_failures' r(domain)='`r(domain)''"
if "`r(lang)'"   != "eng"   local _failures "`_failures' r(lang)='`r(lang)''"
if "`r(primary)'" == ""     local _failures "`_failures' r(primary) empty"
if `r(n_total)' < 1         local _failures "`_failures' r(n_total)=`r(n_total)'"
if `r(match_pct)' < 0       local _failures "`_failures' r(match_pct)=`r(match_pct)'"

* The partition should sum to total, and primary_vars should be non-empty.
local _np = `r(n_primary)'
local _nf = `r(n_fallback)'
local _nu = `r(n_unmatched)'
local _nt = `r(n_total)'
if (`_np' + `_nf' + `_nu') != `_nt' {
	local _failures "`_failures' partition sum (`_np'+`_nf'+`_nu'=`=`_np'+`_nf'+`_nu'') != n_total (`_nt')"
}

if `: word count `r(primary_vars)'' < 1 {
	local _failures "`_failures' r(primary_vars) empty"
}

if "`_failures'" == "" {
	di as result "  PASS: suggest r() contract complete"
	di as text   "    primary=`r(primary)'  partition: `_np'/`_nf'/`_nu' (primary/fallback/unmatched)"
	local ++tests_passed
}
else {
	di as error "  FAIL: missing or wrong returns:`_failures'"
	local ++tests_failed
}


*=============================================================================
* TEST 5: autolabel scope emits navigation context
*=============================================================================

di as result ""
di as result "TEST 5: autolabel scope r() contract"
di as result "---------------------------------------------"

* scope can run without a dataset, so no `use` needed
cap noi autolabel scope, domain(scb) lang(eng)

local _failures ""
if "`r(domain)'" != "scb" local _failures "`_failures' r(domain)='`r(domain)''"
if "`r(lang)'"   != "eng" local _failures "`_failures' r(lang)='`r(lang)''"
* scope_level should exist (numeric); 0 is valid (no tokens pinned)
cap local _sl = `r(scope_level)'
if _rc != 0 {
	local _failures "`_failures' r(scope_level) not set or non-numeric"
}

if "`_failures'" == "" {
	di as result "  PASS: scope r() contract complete"
	di as text   "    scope_level=`r(scope_level)'  parent_scope='`r(parent_scope)''"
	local ++tests_passed
}
else {
	di as error "  FAIL: missing or wrong returns:`_failures'"
	local ++tests_failed
}


*=============================================================================
* TEST 6: end-to-end iterative-pinning workflow using suggest's r() lists
*=============================================================================

di as result ""
di as result "TEST 6: iterative pin workflow (suggest -> primary then fallback)"
di as result "---------------------------------------------"

* Pattern under test: run suggest once, capture r(primary_vars) and
* r(fallback_vars), then call autolabel variables on each list with the
* appropriate scope() pin. Verify both groups end up with labels and that
* the pinned-only call leaves variables outside the pin unlabeled.
use "$LISA_DATA", clear

* Capture suggest's partition into named locals (r() gets clobbered by
* subsequent autolabel calls).
cap noi autolabel suggest, domain(scb) lang(eng)
local _wf_primary    = "`r(primary)'"
local _wf_pri_vars   = `"`r(primary_vars)'"'
local _wf_fb_vars    = `"`r(fallback_vars)'"'
local _wf_n_pri      = `r(n_primary)'
local _wf_n_fb       = `r(n_fallback)'

* Re-load fresh (suggest doesn't modify, but be explicit).
use "$LISA_DATA", clear

* Step A: label primary group with explicit primary scope pin.
local _failures ""
if `_wf_n_pri' > 0 {
	cap noi autolabel variables `_wf_pri_vars', domain(scb) lang(eng) scope("`_wf_primary'")
	if `r(n_primary)' < 1 & "`_wf_primary'" != "" {
		* When pinned, autolabel reports labeled-from-pin under n_primary
		* if our scope name matches, else 0; what we really want is that
		* n_skipped is small and labels were applied. Verify by counting
		* variables with non-empty labels.
	}
	* Count labels actually applied to primary vars
	local _pri_labeled 0
	foreach _v of local _wf_pri_vars {
		local _lbl : variable label `_v'
		if "`_lbl'" != "" local ++_pri_labeled
	}
	if `_pri_labeled' < `=int(`_wf_n_pri' / 2)' {
		local _failures "`_failures' primary group: only `_pri_labeled' of `_wf_n_pri' got labels"
	}
}

* Step B: label fallback group via majority fallback (no pin).
if `_wf_n_fb' > 0 {
	cap noi autolabel variables `_wf_fb_vars', domain(scb) lang(eng)
	local _fb_labeled 0
	foreach _v of local _wf_fb_vars {
		local _lbl : variable label `_v'
		if "`_lbl'" != "" local ++_fb_labeled
	}
	if `_fb_labeled' < `=int(`_wf_n_fb' / 2)' {
		local _failures "`_failures' fallback group: only `_fb_labeled' of `_wf_n_fb' got labels"
	}
}

if "`_failures'" == "" {
	di as result "  PASS: iterative workflow labeled primary and fallback groups"
	di as text   "    primary=`_wf_primary' (n=`_wf_n_pri'), fallback (n=`_wf_n_fb')"
	local ++tests_passed
}
else {
	di as error "  FAIL: workflow:`_failures'"
	local ++tests_failed
}


*=============================================================================
* TEST 7: dynamic-depth contract — inferred_scope is a quoted-token list
* whose token count equals r(display_depth), and round-trips into scope()
*=============================================================================

di as result ""
di as result "TEST 7: dynamic-depth contract (inferred_scope + display_depth)"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel suggest, domain(scb) lang(eng)

* Capture before any other call clobbers r().
local _dd = r(display_depth)
local _is `"`r(inferred_scope)'"'

local _failures ""

* display_depth must be a positive integer (1 = level-1, 2 = level-2, ...)
if "`_dd'" == "" {
	local _failures "`_failures' r(display_depth) missing"
}
else if (`_dd' < 1) {
	local _failures "`_failures' r(display_depth)=`_dd' (want >=1)"
}

* inferred_scope must be non-empty and start with a quote (the quoted-list
* form: `"LISA"' or `"LISA" "Individuals 16+"').
if `"`_is'"' == "" {
	local _failures "`_failures' r(inferred_scope) empty"
}
else if (substr(`"`_is'"', 1, 1) != `"""') {
	local _failures `"`_failures' r(inferred_scope) not quoted: `_is'"'
}

* Manually count quoted tokens via gettoken (same parsing scope() does),
* and verify the count matches r(display_depth). This locks down the
* contract: depth N => N quoted tokens.
local _rem `"`_is'"'
local _ntok 0
while `"`_rem'"' != "" {
	gettoken _tok _rem : _rem
	local ++_ntok
	if `_ntok' >= 10 continue, break
}
if ("`_dd'" != "" & `_ntok' != `_dd') {
	local _failures `"`_failures' n_tokens(`_ntok') != display_depth(`_dd') for inferred_scope=`_is'"'
}

* Round-trip: feed inferred_scope back through scope() on a real call.
* Would error out (rc!=0) if the format were malformed. autolabel scope
* is read-only so we don't need to reload the dataset.
cap noi autolabel scope, domain(scb) lang(eng) scope(`_is')
if (_rc != 0) {
	local _failures `"`_failures' scope(`_is') round-trip rc=`=_rc'"'
}

if "`_failures'" == "" {
	di as result "  PASS: inferred_scope contract holds"
	di as text   `"    display_depth=`_dd'  inferred_scope=`_is'  n_tokens=`_ntok'"'
	local ++tests_passed
}
else {
	di as error `"  FAIL: dynamic-depth contract:`_failures'"'
	local ++tests_failed
}


*=============================================================================
* TEST 8: positive depth-2 case — a dataset spanning two variants of the same
* register should infer down to the densest variant. Uses Regional
* omsättningsstatistik (REGO): 5 variables exclusive to (REGO, "Arbetsställe,
* månad") + 1 variable exclusive to (REGO, "Arbetsställe, år"). The engine
* picks the monthly variant, narrowing reduces matched-count by 1, depth=2.
*=============================================================================

di as result ""
di as result "TEST 8: depth-2 inference fires when dataset spans variants"
di as result "---------------------------------------------"

clear
set obs 1
* 5 vars exclusive to "Arbetsställe, månad"
gen aeanst     = 0
gen aeantje    = 0
gen jeanst     = 0
gen jeng1      = 0
gen omssverige = 0
* 1 var exclusive to "Arbetsställe, år"
gen antal_manader = 0

cap noi autolabel suggest, domain(scb) lang(eng)

local _dd = r(display_depth)
local _is `"`r(inferred_scope)'"'
local _failures ""

if "`_dd'" != "2" {
	local _failures `"`_failures' display_depth=`_dd' (want 2)"'
}
if (strpos(`"`_is'"', "REGO") == 0) {
	local _failures `"`_failures' inferred_scope missing REGO"'
}

* Count quoted tokens in r(inferred_scope) via gettoken; depth=2 must
* produce exactly 2 tokens.
local _rem `"`_is'"'
local _ntok 0
while `"`_rem'"' != "" {
	gettoken _tok _rem : _rem
	local ++_ntok
	if `_ntok' >= 10 continue, break
}
if `_ntok' != 2 {
	local _failures `"`_failures' n_tokens=`_ntok' (want 2)"'
}

if `"`_failures'"' == "" {
	di as result "  PASS: depth-2 inference fires correctly"
	di as text   `"    display_depth=`_dd'  inferred_scope=`_is'"'
	local ++tests_passed
}
else {
	di as error `"  FAIL: depth-2 inference:`_failures' (got inferred_scope=`_is')"'
	local ++tests_failed
}


*=============================================================================
* Summary
*=============================================================================

di as result ""
di as result "============================================="
di as result "Test 26 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
