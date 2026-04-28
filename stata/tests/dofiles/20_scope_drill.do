/*==============================================================================
  Test 20: Scope drill — depth-agnostic browse (autolabel schema v2)

  Purpose: Verify the autolabel scope browse works across all drill levels
           for a 2-level domain (SCB), and that the overflow-token-as-release
           convention routes to variables.

  Tests:
    1. L0 browse — top-level scopes listed
    2. L0 search — filter by term
    3. L0 loose search — *term substring
    4. L1 drill — scope("LISA") shows variants
    5. L2 releases — scope("LISA" "variant") shows releases
    6. L3 variables via overflow — scope("LISA" "variant" "2005")
    7. Auto-drill on single release
    8. No match errors gracefully
    9. Exact match preferred over substring
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

di as result "Test 20: Scope drill (depth=2, SCB)"

local tests_total = 0
local tests_passed = 0
local tests_failed = 0

* ── TEST 1: L0 browse ────────────────────────────────────────────────
local ++tests_total
di as text _n "Test 1/9: L0 browse"
cap noisily autolabel scope, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 2: L0 search ────────────────────────────────────────────────
local ++tests_total
di as text _n "Test 2/9: L0 search (LISA)"
cap noisily autolabel scope LISA, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 3: L0 loose search ──────────────────────────────────────────
local ++tests_total
di as text _n "Test 3/9: L0 loose search (*child)"
cap noisily autolabel scope *child, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 4: L1 drill ─────────────────────────────────────────────────
local ++tests_total
di as text _n `"Test 4/9: L1 drill — scope("LISA")"'
cap noisily autolabel scope, domain(scb) lang(eng) scope("LISA")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 5: L2 releases ──────────────────────────────────────────────
local ++tests_total
di as text _n "Test 5/9: L2 releases"
cap noisily autolabel scope, domain(scb) lang(eng) scope("LISA" "Individuals aged 16 and older")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 6: L3 via overflow ──────────────────────────────────────────
local ++tests_total
di as text _n "Test 6/9: L3 variables via overflow token (release as 3rd token)"
cap noisily autolabel scope, domain(scb) lang(eng) scope("LISA" "Individuals aged 16 and older" "2005")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 7: Auto-drill on single release ─────────────────────────────
local ++tests_total
di as text _n "Test 7/9: Auto-drill on single release"
cap noisily autolabel scope, domain(scb) lang(eng) ///
	scope("Energy Use in the Construction Sector" "Energy use in the construction sector")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── TEST 8: No match errors gracefully ───────────────────────────────
local ++tests_total
di as text _n "Test 8/9: No match errors gracefully"
cap noisily autolabel scope, domain(scb) lang(eng) scope("NONEXISTENT_XYZ_1234")
if (_rc != 0) {
	di as result "  PASS (correctly errored)"
	local ++tests_passed
}
else {
	di as error "  FAIL (should have errored)"
	local ++tests_failed
}

* ── TEST 9: Exact match precedence (alias) ───────────────────────────
local ++tests_total
di as text _n "Test 9/9: Exact alias match — scope(LISA)"
cap noisily autolabel scope, domain(scb) lang(eng) scope("LISA")
if (_rc == 0) {
	di as result "  PASS"
	local ++tests_passed
}
else {
	di as error "  FAIL (rc=`=_rc')"
	local ++tests_failed
}

* ── Summary ──────────────────────────────────────────────────────────
di as result _n "Test 20 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
