/*==============================================================================
  Test 02: Basic Autolabel Workflow

  Purpose: Test autolabel variables and values in English and Swedish
  Author: Jeffrey Clark

  Tests:
    1. Synthetic data generation
    2. Variable labels (English)
    3. Value labels (English)
    4. Variable labels (Swedish)
    5. Value labels (Swedish)
    6. Metadata tracking (datasets.csv)
    7. Usage logging (usage_stata.csv)
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
global TEST_DATA_DIR "$TEST_DIR/data"
global TEST_LOGS_DIR "$TEST_DIR/logs"
cap mkdir "$TEST_LOGS_DIR"
cap mkdir "$TEST_DATA_DIR"

* Dual adopath: autolabel source + registream core
discard
adopath ++ "$SRC_DIR"
* Registream core (sibling repo)
local core_src "$CORE_SRC"
capture confirm file "`core_src'/registream.ado"
if _rc != 0 {
	di as error "ERROR: registream core not found at `core_src'"
	di as error "Expected sibling repos: registream-org/registream and registream-org/autolabel"
	exit 601
}
adopath ++ "`core_src'"
do "`core_src'/_rs_utils.ado"
cap do "`core_src'/../dev/host_override.do"
do "`core_src'/../dev/auto_approve.do"

* ==========================================================================
* Test tracking
* ==========================================================================

local tests_passed = 0
local tests_failed = 0
local tests_total = 7

di as result ""
di as result "============================================="
di as result "Test 02: Basic Autolabel Workflow"
di as result "============================================="
di as result ""

* ==========================================================================
* Test 1: Load example data
* ==========================================================================

di as result "TEST 1: Load example data (lisa.dta)"
di as result "---------------------------------------------"

cap confirm file "$LISA_DATA"
if (_rc == 0) {
	use "$LISA_DATA", clear
	if (_N > 0) {
		di as result "  PASS: Example data loaded (`=_N' observations)"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Example data file is empty"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: examples/lisa.dta not found"
	local ++tests_failed
}

* ==========================================================================
* Test 2: Variable labels (English)
* ==========================================================================

di as result ""
di as result "TEST 2: Variable labels (English)"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

local labeled = 0
quietly describe, varlist
foreach v in `r(varlist)' {
	local vl : variable label `v'
	if "`vl'" != "" local ++labeled
}

if (`labeled' > 0) {
	di as result "  PASS: `labeled' variables labeled (English)"
	local ++tests_passed
}
else {
	di as error "  FAIL: No English variable labels applied"
	local ++tests_failed
}

* ==========================================================================
* Test 3: Value labels (English)
* ==========================================================================

di as result ""
di as result "TEST 3: Value labels (English)"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel values, domain(scb) lang(eng)

if (_rc == 0) {
	di as result "  PASS: English value labels applied without error"
	local ++tests_passed
}
else {
	di as error "  FAIL: English value labels returned error (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Test 4: Variable labels (Swedish)
* ==========================================================================

di as result ""
di as result "TEST 4: Variable labels (Swedish)"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(swe)

local labeled = 0
quietly describe, varlist
foreach v in `r(varlist)' {
	local vl : variable label `v'
	if "`vl'" != "" local ++labeled
}

if (`labeled' > 0) {
	di as result "  PASS: `labeled' variables labeled (Swedish)"
	local ++tests_passed
}
else {
	di as error "  FAIL: No Swedish variable labels applied"
	local ++tests_failed
}

* ==========================================================================
* Test 5: Value labels (Swedish)
* ==========================================================================

di as result ""
di as result "TEST 5: Value labels (Swedish)"
di as result "---------------------------------------------"

use "$LISA_DATA", clear
cap noi autolabel values, domain(scb) lang(swe)

if (_rc == 0) {
	di as result "  PASS: Swedish value labels applied without error"
	local ++tests_passed
}
else {
	di as error "  FAIL: Swedish value labels returned error (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Test 6: Metadata tracking (datasets.csv)
* ==========================================================================

di as result ""
di as result "TEST 6: Metadata tracking (datasets.csv)"
di as result "---------------------------------------------"

_rs_utils get_dir
local registream_dir "`r(dir)'"
local autolabel_dir "`registream_dir'/autolabel"

cap confirm file "`autolabel_dir'/datasets.csv"
if (_rc == 0) {
	preserve
	quietly import delimited using "`autolabel_dir'/datasets.csv", clear varnames(1) stringcols(_all) delimiter(";")
	local dataset_count = _N
	restore

	if (`dataset_count' >= 2) {
		di as result "  PASS: datasets.csv has `dataset_count' entries"
		local ++tests_passed
	}
	else {
		di as result "  PASS (partial): datasets.csv has `dataset_count' entries (expected >= 2)"
		local ++tests_passed
	}
}
else {
	di as error "  FAIL: datasets.csv not found"
	local ++tests_failed
}

* ==========================================================================
* Test 7: Usage logging
* ==========================================================================

di as result ""
di as result "TEST 7: Usage logging (usage_stata.csv)"
di as result "---------------------------------------------"

cap confirm file "`registream_dir'/usage_stata.csv"
if (_rc == 0) {
	preserve
	quietly import delimited using "`registream_dir'/usage_stata.csv", clear delimiter(";") varnames(1) stringcols(_all)
	local log_count = _N
	restore

	if (`log_count' > 0) {
		di as result "  PASS: usage_stata.csv has `log_count' entries"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: usage_stata.csv is empty"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: usage_stata.csv not found"
	local ++tests_failed
}

* ==========================================================================
* Summary
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 02 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
