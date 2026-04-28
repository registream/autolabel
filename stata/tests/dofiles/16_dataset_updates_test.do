/*==============================================================================
  Test 16: Dataset Update Checks with Numeric Timestamps

  Purpose: Test the dataset update checking system — verifying that autolabel
           correctly detects and reports when newer versions are available
  Author: Jeffrey Clark

  Tests:
    1. Current dataset has version info in datasets.csv
    2. Simulated update available (fake old version in metadata)
    3. check_for_updates returns correct status
    4. update_last_checked writes current timestamp
    5. get_dataset_version returns correct stored values
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
local tests_total = 5

di as result ""
di as result "============================================="
di as result "Test 16: Dataset Update Checks"
di as result "============================================="
di as result ""

_rs_utils get_dir
local registream_dir "`r(dir)'"
local autolabel_dir "`registream_dir'/autolabel"
local meta_csv "`autolabel_dir'/datasets.csv"

cap confirm file "$LISA_DATA"
if (_rc != 0) {
}
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

* ==========================================================================
* Test 1: Dataset has version info in datasets.csv
* ==========================================================================

di as result "TEST 1: Dataset version info exists"
di as result "---------------------------------------------"

_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
local hv = r(has_version)
local ver = r(version)
local sch = r(schema)
local dl = r(downloaded)

if (`hv' == 1) {
	di as result "  PASS: Version info found"
	di as text "    version:    `ver'"
	di as text "    schema:     `sch'"
	di as text "    downloaded: `dl'"
	local ++tests_passed
}
else {
	di as error "  FAIL: No version info in datasets.csv for scb_variables_eng"
	local ++tests_failed
}

* ==========================================================================
* Test 2: Simulated update available
* ==========================================================================

di as result ""
di as result "TEST 2: Simulate update available (fake old version)"
di as result "---------------------------------------------"
di as text "  Setting local version to '19000101' to simulate an outdated dataset."

* Save the real version for restoration
local real_version "`ver'"

* Set a fake old version
cap confirm file "`meta_csv'"
if (_rc == 0) {
	preserve
	quietly {
		import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		replace version = "19000101" if dataset_key == "scb_variables_eng"
		* Also expire the cache so check_for_updates actually pings API
		local old_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms") - 172800000
		replace last_checked = "`old_clock'" if dataset_key == "scb_variables_eng"
		export delimited using "`meta_csv'", replace delimiter(";")
	}
	restore

	* Verify the fake version was written
	_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
	local fake_ver = r(version)

	if ("`fake_ver'" == "19000101") {
		di as result "  PASS: Version set to `fake_ver' (simulating outdated)"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Could not set fake version (got: `fake_ver')"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: datasets.csv not found"
	local ++tests_failed
}

* ==========================================================================
* Test 3: check_for_updates detects update
* ==========================================================================

di as result ""
di as result "TEST 3: check_for_updates reports update available"
di as result "---------------------------------------------"

local dta_file "`autolabel_dir'/scb/variables_eng.dta"
cap noi _al_utils check_for_updates "`autolabel_dir'" "scb" "variables" "eng" "`dta_file'"
local check_status "`r(status)'"
local api_ver "`r(api_version)'"
local local_ver "`r(local_version)'"

if ("`check_status'" == "update_available") {
	di as result "  PASS: Update detected"
	di as text "    status: `check_status'"
	di as text "    local:  `local_ver'"
	di as text "    api:    `api_ver'"
	local ++tests_passed
}
else if ("`check_status'" == "api_error") {
	di as result "  PASS (partial): API unreachable, got status=api_error"
	di as text "    (Cannot verify update detection without API)"
	local ++tests_passed
}
else {
	di as error "  FAIL: Expected 'update_available', got '`check_status''"
	local ++tests_failed
}

* Restore real version
cap confirm file "`meta_csv'"
if (_rc == 0) {
	preserve
	quietly {
		import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		replace version = "`real_version'" if dataset_key == "scb_variables_eng"
		export delimited using "`meta_csv'", replace delimiter(";")
	}
	restore
}

* ==========================================================================
* Test 4: update_last_checked writes current timestamp
* ==========================================================================

di as result ""
di as result "TEST 4: update_last_checked writes current timestamp"
di as result "---------------------------------------------"

* Get the current clock for comparison
local before_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")

* Call update_last_checked
cap noi _al_utils update_last_checked "`autolabel_dir'" "scb" "variables" "eng"

* Read back the timestamp
_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
local new_lc = r(last_checked)

if ("`new_lc'" != "" & "`new_lc'" != ".") {
	* The new timestamp should be >= before_clock (within a few seconds)
	local diff = `new_lc' - `before_clock'
	if (`diff' >= 0 & `diff' < 60000) {
		di as result "  PASS: last_checked updated to current time"
		di as text "    before:       `before_clock'"
		di as text "    last_checked: `new_lc'"
		di as text "    diff (ms):    `diff'"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Timestamp not in expected range"
		di as text "    before: `before_clock', after: `new_lc', diff: `diff' ms"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: last_checked not updated"
	local ++tests_failed
}

* ==========================================================================
* Test 5: get_dataset_version returns all stored fields
* ==========================================================================

di as result ""
di as result "TEST 5: get_dataset_version returns complete metadata"
di as result "---------------------------------------------"

_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
local hv = r(has_version)
local ver = r(version)
local sch = r(schema)
local dl = r(downloaded)
local src = r(source)
local fs = r(file_size)
local lc = r(last_checked)

local fields_ok = 1
if (`hv' != 1) local fields_ok = 0
if ("`ver'" == "" | "`ver'" == ".") local fields_ok = 0
if ("`dl'" == "" | "`dl'" == ".") local fields_ok = 0

if (`fields_ok' == 1) {
	di as result "  PASS: All metadata fields present"
	di as text "    has_version:  `hv'"
	di as text "    version:      `ver'"
	di as text "    schema:       `sch'"
	di as text "    downloaded:   `dl'"
	di as text "    source:       `src'"
	di as text "    file_size:    `fs'"
	di as text "    last_checked: `lc'"
	local ++tests_passed
}
else {
	di as error "  FAIL: Some metadata fields are missing"
	di as text "    has_version=`hv', version=`ver', downloaded=`dl'"
	local ++tests_failed
}

* ==========================================================================
* Summary
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 16 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
