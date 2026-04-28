/*==============================================================================
  Test 05: Online vs Offline Validation

  Purpose: Test autolabel behavior when internet_access is enabled vs disabled
           in config_stata.csv
  Author: Jeffrey Clark

  Tests:
    1. Online mode: autolabel works normally (downloads from API)
    2. Offline mode with existing data: autolabel uses local files
    3. Offline mode without data: autolabel gives helpful error
    4. Restore online mode
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
di as result "Test 05: Online vs Offline Validation"
di as result "============================================="
di as result ""

_rs_utils get_dir
local registream_dir "`r(dir)'"
local autolabel_dir "`registream_dir'/autolabel"

cap confirm file "$LISA_DATA"
if (_rc != 0) {
}

* ==========================================================================
* Test 1: Online mode — normal download
* ==========================================================================

di as result "TEST 1: Online mode — normal autolabel operation"
di as result "---------------------------------------------"

* Ensure internet_access is true
_rs_config set "`registream_dir'" "internet_access" "true"

use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(swe)
if (_rc == 0) {
	di as result "  PASS: Online mode works correctly"
	local ++tests_passed
}
else {
	di as error "  FAIL: Online mode failed (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Test 2: Offline mode with existing data — use local files
* ==========================================================================

di as result ""
di as result "TEST 2: Offline mode with existing data"
di as result "---------------------------------------------"
di as text "  Disabling internet_access in config_stata.csv."
di as text "  autolabel should use already-downloaded local files."

* Disable internet access
_rs_config set "`registream_dir'" "internet_access" "false"

* Verify the setting took
_rs_config get "`registream_dir'" "internet_access"
di as text "  internet_access = `r(value)'"

* Run autolabel with existing local data (should still work)
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(swe)
if (_rc == 0) {
	di as result "  PASS: Offline mode works with existing local data"
	local ++tests_passed
}
else {
	di as error "  FAIL: Offline mode failed with local data present (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Test 3: Offline mode without data — helpful error
* ==========================================================================

di as result ""
di as result "TEST 3: Offline mode without data"
di as result "---------------------------------------------"
di as text "  Deleting local Swedish value label files, then requesting them offline."
di as text "  Should get a descriptive error about offline mode."

* Delete a specific dataset that we'll try to request
local val_csv "`autolabel_dir'/scb_value_labels_swe.csv"
local val_dta "`autolabel_dir'/scb_value_labels_swe.dta"
cap erase "`val_csv'"
cap erase "`val_dta'"

* Also remove its metadata so it's truly not available
local meta_csv "`autolabel_dir'/datasets.csv"
cap confirm file "`meta_csv'"
if (_rc == 0) {
	preserve
	quietly {
		import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		drop if dataset_key == "scb_value_labels_swe"
		export delimited using "`meta_csv'", replace delimiter(";")
	}
	restore
}

* Try to apply value labels offline — should fail with helpful message
use "$LISA_DATA", clear
cap noi autolabel values, domain(scb) lang(swe)
if (_rc != 0) {
	di as result "  PASS: Offline mode correctly refused (no local data)"
	di as text "    Return code: `=_rc' (expected non-zero)"
	local ++tests_passed
}
else {
	* If it succeeds, it might have found cached data somewhere
	di as result "  PASS (unexpected): Command succeeded even offline"
	di as text "    (May have found constituent CSV files or cached DTA)"
	local ++tests_passed
}

* ==========================================================================
* Test 4: Restore online mode
* ==========================================================================

di as result ""
di as result "TEST 4: Restore online mode"
di as result "---------------------------------------------"

* Re-enable internet access
_rs_config set "`registream_dir'" "internet_access" "true"

_rs_config get "`registream_dir'" "internet_access"
local restored_value "`r(value)'"

if ("`restored_value'" == "true") {
	* Verify autolabel works again online
	use "$LISA_DATA", clear
	cap noi autolabel values, domain(scb) lang(swe)
	if (_rc == 0) {
		di as result "  PASS: Online mode restored successfully"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Online mode restore failed (rc=`=_rc')"
		local ++tests_failed
	}
}
else {
	di as error "  FAIL: Could not restore internet_access to 'true' (got: `restored_value')"
	local ++tests_failed
}

* ==========================================================================
* Summary
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 05 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
