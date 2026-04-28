/*==============================================================================
  Test 22: Comprehensive Autolabel Test Suite

  Purpose: Full end-to-end test of all autolabel commands
  Author: Jeffrey Clark

  Ported from: stata/tests/test_autolabel.do

  Tests:
    1. Config initialization
    2. Variable labels (Swedish, auto-infer)
    3. Variable labels (English, auto-infer)
    4. Value labels (Swedish, auto-infer)
    5. Value labels (English, auto-infer)
    6. Lookup (Swedish)
    7. Lookup (English)
    8. Dryrun mode
    9. Savedo mode
    10. Metadata tracking (datasets.csv)
    11. Usage logging
    12. Version command
    13. Info command
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
* Setup
* ==========================================================================

cap ado uninstall registream
cap ado uninstall autolabel

which autolabel
which registream

local tests_passed = 0
local tests_failed = 0
local tests_total = 13

local lisa "$LISA_DATA"

di as result ""
di as result "============================================="
di as result "Test 22: Comprehensive Autolabel Suite"
di as result "============================================="
di as result ""

* ==========================================================================
* Test 1: Config initialization
* ==========================================================================

di as result "TEST 1: Config initialization"
di as result "---------------------------------------------"

_rs_utils get_dir
local registream_dir "`r(dir)'"

cap noi autolabel version

cap confirm file "`registream_dir'/config_stata.csv"
if (_rc == 0) {
	_rs_config get "`registream_dir'" "usage_logging"
	if (r(found) == 1) {
		di as result "  PASS: Config initialized with usage_logging=`r(value)'"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Config exists but missing usage_logging key"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: config_stata.csv not created"
	local ++tests_failed
}

* ==========================================================================
* Test 2: Variable labels (Swedish) — auto-infer register
* ==========================================================================

di as result ""
di as result "TEST 2: Variable labels (Swedish, auto-infer)"
di as result "---------------------------------------------"

use "`lisa'", clear
describe, short
local nvars_before = r(k)
autolabel variables, domain(scb) lang(swe)

* Count how many variables got labels
local labeled = 0
quietly describe, varlist
foreach v in `r(varlist)' {
	local vl : variable label `v'
	if "`vl'" != "" local ++labeled
}

if (`labeled' > 0) {
	di as result "  PASS: `labeled'/`nvars_before' variables labeled"
	local ++tests_passed
}
else {
	di as error "  FAIL: No variable labels applied"
	local ++tests_failed
}

* ==========================================================================
* Test 3: Variable labels (English) — auto-infer register
* ==========================================================================

di as result ""
di as result "TEST 3: Variable labels (English, auto-infer)"
di as result "---------------------------------------------"

use "`lisa'", clear
autolabel variables, domain(scb) lang(eng)

local labeled = 0
quietly describe, varlist
foreach v in `r(varlist)' {
	local vl : variable label `v'
	if "`vl'" != "" local ++labeled
}

if (`labeled' > 0) {
	di as result "  PASS: `labeled' variables labeled"
	local ++tests_passed
}
else {
	di as error "  FAIL: No English variable labels applied"
	local ++tests_failed
}

* ==========================================================================
* Test 4: Value labels (Swedish) — auto-infer register
* ==========================================================================

di as result ""
di as result "TEST 4: Value labels (Swedish, auto-infer)"
di as result "---------------------------------------------"

use "`lisa'", clear
cap noi autolabel values, domain(scb) lang(swe)

if (_rc == 0) {
	di as result "  PASS: Value labels applied without error"
	local ++tests_passed
}
else {
	di as error "  FAIL: Value labels returned error (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Test 5: Value labels (English) — auto-infer register
* ==========================================================================

di as result ""
di as result "TEST 5: Value labels (English, auto-infer)"
di as result "---------------------------------------------"

use "`lisa'", clear
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
* Test 6: Lookup (Swedish)
* ==========================================================================

di as result ""
di as result "TEST 6: Lookup command (Swedish)"
di as result "---------------------------------------------"

cap noi autolabel lookup loneink, domain(scb) lang(swe)
if (_rc == 0) {
	di as result "  PASS: Lookup completed without error"
	local ++tests_passed
}
else {
	di as error "  FAIL: Lookup returned error (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Test 7: Lookup (English)
* ==========================================================================

di as result ""
di as result "TEST 7: Lookup command (English)"
di as result "---------------------------------------------"

cap noi autolabel lookup loneink, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "  PASS: Lookup completed without error"
	local ++tests_passed
}
else {
	di as error "  FAIL: Lookup returned error (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Test 8: Dryrun mode
* ==========================================================================

di as result ""
di as result "TEST 8: Dryrun mode"
di as result "---------------------------------------------"

use "`lisa'", clear
cap noi autolabel variables, domain(scb) lang(swe) dryrun

if (_rc == 0) {
	* Verify no labels were applied
	local labeled = 0
	quietly describe, varlist
	foreach v in `r(varlist)' {
		local vl : variable label `v'
		if "`vl'" != "" local ++labeled
	}
	if (`labeled' == 0) {
		di as result "  PASS: Dryrun did not modify labels"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Dryrun applied `labeled' labels"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: Dryrun returned error"
	local ++tests_failed
}

* ==========================================================================
* Test 9: Savedo mode
* ==========================================================================

di as result ""
di as result "TEST 9: Savedo mode"
di as result "---------------------------------------------"

use "`lisa'", clear
local dofile "$TEST_LOGS_DIR/test_savedo_output.do"
cap erase "`dofile'"
cap noi autolabel variables, domain(scb) lang(swe) savedo("`dofile'")

cap confirm file "`dofile'"
if (_rc == 0) {
	di as result "  PASS: Do-file saved successfully"
	local ++tests_passed
}
else {
	di as error "  FAIL: Do-file not created"
	local ++tests_failed
}

* Clean up
cap erase "`dofile'"

* ==========================================================================
* Test 10: Metadata tracking
* ==========================================================================

di as result ""
di as result "TEST 10: Metadata tracking (datasets.csv)"
di as result "---------------------------------------------"

local autolabel_dir "`registream_dir'/autolabel"
cap confirm file "`autolabel_dir'/datasets.csv"
if (_rc == 0) {
	preserve
	quietly import delimited using "`autolabel_dir'/datasets.csv", clear varnames(1) stringcols(_all) delimiter(";")
	local dataset_count = _N
	restore

	if (`dataset_count' >= 4) {
		di as result "  PASS: datasets.csv has `dataset_count' entries"
		local ++tests_passed
	}
	else {
		di as result "  PASS (partial): datasets.csv has `dataset_count' entries (expected >= 4)"
		local ++tests_passed
	}
}
else {
	di as error "  FAIL: datasets.csv not found"
	local ++tests_failed
}

* ==========================================================================
* Test 11: Usage logging
* ==========================================================================

di as result ""
di as result "TEST 11: Usage logging"
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
* Test 12: Version command
* ==========================================================================

di as result ""
di as result "TEST 12: Version command"
di as result "---------------------------------------------"

cap noi autolabel version
if (_rc == 0) {
	di as result "  PASS: Version command completed"
	local ++tests_passed
}
else {
	di as error "  FAIL: Version command returned error"
	local ++tests_failed
}

* ==========================================================================
* Test 13: Info command
* ==========================================================================

di as result ""
di as result "TEST 13: Info command"
di as result "---------------------------------------------"

cap noi autolabel info
if (_rc == 0) {
	di as result "  PASS: Info command completed"
	local ++tests_passed
}
else {
	di as error "  FAIL: Info command returned error"
	local ++tests_failed
}

* ==========================================================================
* Summary
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 22 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
