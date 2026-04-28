/*==============================================================================
  Test 25: Depth-agnostic behavior (autolabel schema v2)

  Purpose: Verify autolabel works for scope_depth=1 (DST) as well as
           scope_depth=2 (SCB), using the same code path. Covers the
           fix for hardcoded scope_level_2 references.

  Requires: DST bundle available on the server (dst/eng).

  Tests:
    1. DST scope browse (depth=1, no scope_level_2 column)
    2. DST scope drill into a single register
    3. DST lookup without scope filter
    4. DST lookup with scope filter (was the scope_level_2 crash)
    5. Apostrophe-insensitive matching (Women's crisis centres)
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

di as result "Test 25: Depth-agnostic behavior (DST depth=1)"

local tests_total = 0
local tests_passed = 0
local tests_failed = 0

* ── TEST 1: DST scope browse (depth=1) ───────────────────────────────
local ++tests_total
di as text _n "Test 1/5: DST scope browse (depth=1)"
cap noisily autolabel scope, domain(dst) lang(eng)
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc') — depth-agnostic browse broken"
	local ++tests_failed
}

* ── TEST 2: DST scope drill ──────────────────────────────────────────
local ++tests_total
di as text _n "Test 2/5: DST scope drill"
cap noisily autolabel scope, domain(dst) lang(eng) scope("Active civil servants in the state")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 3: DST lookup without scope ─────────────────────────────────
local ++tests_total
di as text _n "Test 3/5: DST lookup without scope filter"
cap noisily autolabel lookup law_reference, domain(dst) lang(eng)
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 4: DST lookup with scope filter ─────────────────────────────
local ++tests_total
di as text _n "Test 4/5: DST lookup with scope filter (regression: scope_level_2)"
cap noisily autolabel lookup law_reference, domain(dst) lang(eng) scope("Active civil servants in the state")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc') — depth=1 lookup crash returned"
	local ++tests_failed
}

* ── TEST 5: Apostrophe-insensitive matching ──────────────────────────
local ++tests_total
di as text _n "Test 5/5: Apostrophe-insensitive match (Womens crisis centres)"
cap noisily autolabel scope, domain(dst) lang(eng) scope("Womens crisis centres - Enquiries")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc') — apostrophe sanitization broke matching"
	local ++tests_failed
}

* ── Summary ──────────────────────────────────────────────────────────
di as result _n "Test 25 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
