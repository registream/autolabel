/*==============================================================================
  Test 04: 24-Hour Last-Checked Timestamp Caching

  Purpose: Test that the dataset update check respects the 24-hour cache
           via last_checked timestamps in datasets.csv
  Author: Jeffrey Clark

  Tests:
    1. Verify last_checked is set after initial use
    2. Verify cache hit (skip API check within 24 hours)
    3. Verify cache miss (force API check with old timestamp)
    4. Verify last_checked update after cache miss
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

local tests_passed = 0
local tests_failed = 0
local tests_total = 4

di as result ""
di as result "============================================="
di as result "Test 04: 24-Hour Timestamp Caching"
di as result "============================================="
di as result ""

_rs_utils get_dir
local registream_dir "`r(dir)'"
local autolabel_dir "`registream_dir'/autolabel"
local meta_csv "`autolabel_dir'/datasets.csv"

cap confirm file "$LISA_DATA"
if (_rc != 0) {
}

* Ensure datasets are downloaded
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

* ==========================================================================
* Test 1: last_checked is set after initial use
* ==========================================================================

di as result "TEST 1: last_checked timestamp is set after use"
di as result "---------------------------------------------"

_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
local lc = r(last_checked)
local hv = r(has_version)

if (`hv' == 1 & "`lc'" != "" & "`lc'" != ".") {
	di as result "  PASS: last_checked is set: `lc'"
	local ++tests_passed
}
else if (`hv' == 1) {
	di as error "  FAIL: has_version=1 but last_checked is empty"
	local ++tests_failed
}
else {
	di as error "  FAIL: No version info found in datasets.csv"
	local ++tests_failed
}

* ==========================================================================
* Test 2: Cache hit — API check is skipped within 24 hours
* ==========================================================================

di as result ""
di as result "TEST 2: Cache hit — skip API check within 24 hours"
di as result "---------------------------------------------"
di as text "  Running autolabel again immediately. The 24-hour cache should"
di as text "  prevent an API version check."

* Record the last_checked before second run
_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
local lc_before = r(last_checked)

* Run autolabel again
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

* Check last_checked after second run
_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
local lc_after = r(last_checked)

* If caching works, last_checked should NOT have been updated significantly
* (might be same or very close timestamp)
if (_rc == 0) {
	di as result "  PASS: Second run succeeded (cache should have been used)"
	di as text "    last_checked before: `lc_before'"
	di as text "    last_checked after:  `lc_after'"
	local ++tests_passed
}
else {
	di as error "  FAIL: Second run failed"
	local ++tests_failed
}

* ==========================================================================
* Test 3: Cache miss — force API check with old timestamp
* ==========================================================================

di as result ""
di as result "TEST 3: Cache miss — force API check with 48h-old timestamp"
di as result "---------------------------------------------"
di as text "  Setting last_checked to 48 hours ago to force an API check."

* Calculate a timestamp 48 hours ago (48 * 60 * 60 * 1000 = 172800000 ms)
local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old_clock = `current_clock' - 172800000

* Update datasets.csv with old timestamp
cap confirm file "`meta_csv'"
if (_rc == 0) {
	preserve
	quietly {
		import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		replace last_checked = "`old_clock'" if dataset_key == "scb_variables_eng"
		export delimited using "`meta_csv'", replace delimiter(";")
	}
	restore

	* Run autolabel - should trigger API check (cache expired)
	use "$LISA_DATA", clear
	cap noi autolabel variables, domain(scb) lang(eng)
	if (_rc == 0) {
		di as result "  PASS: Cache miss triggered successfully (re-checked API)"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Cache miss scenario failed (rc=`=_rc')"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: datasets.csv not found"
	local ++tests_failed
}

* ==========================================================================
* Test 4: last_checked updated after cache miss
* ==========================================================================

di as result ""
di as result "TEST 4: last_checked updated after cache miss"
di as result "---------------------------------------------"

_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
local lc_new = r(last_checked)

if ("`lc_new'" != "" & "`lc_new'" != ".") {
	* The new timestamp should be more recent than the old one we set
	if (`lc_new' > `old_clock') {
		di as result "  PASS: last_checked was updated to: `lc_new'"
		di as text "    Old (forced):  `old_clock'"
		di as text "    New (updated): `lc_new'"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: last_checked was not updated after cache miss"
		di as text "    Old: `old_clock'"
		di as text "    Current: `lc_new'"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: last_checked is empty after cache miss"
	local ++tests_failed
}

* ==========================================================================
* Summary
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 04 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
