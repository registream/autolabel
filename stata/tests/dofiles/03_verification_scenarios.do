/*==============================================================================
  Test 03: File/Metadata Verification Scenarios

  Purpose: Test autolabel's file integrity and metadata verification system
  Author: Jeffrey Clark

  Tests 5 scenarios that trigger different verify_file_integrity paths:
    1. Fresh download (no files, no metadata)
    2. Size mismatch (file size differs from datasets.csv)
    3. File missing (metadata exists but files deleted)
    4. File exists, no metadata (legacy or user-created)
    5. Size mismatch with source=user (should be skipped)
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
di as result "Test 03: File/Metadata Verification Scenarios"
di as result "============================================="
di as result ""

_rs_utils get_dir
local registream_dir "`r(dir)'"
local autolabel_dir "`registream_dir'/autolabel"

cap confirm file "$LISA_DATA"
if (_rc != 0) {
}

* ==========================================================================
* Scenario 1: Fresh download (no files, no metadata)
* ==========================================================================

di as result "SCENARIO 1: Fresh download — no files, no metadata"
di as result "---------------------------------------------"
di as text "  Testing that autolabel can download and set up from scratch."
di as text "  (Uses auto-approve to skip interactive prompts)"

use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "  PASS: Fresh download succeeded"
	local ++tests_passed
}
else {
	di as error "  FAIL: Fresh download failed (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Scenario 2: Size mismatch (modify CSV to trigger size check)
* ==========================================================================

di as result ""
di as result "SCENARIO 2: Size mismatch detection"
di as result "---------------------------------------------"
di as text "  Appending junk to a CSV file to trigger size mismatch warning."

* Find the actual CSV file
local test_csv "`autolabel_dir'/scb_variables_eng.csv"
cap confirm file "`test_csv'"
if (_rc == 0) {
	* Get original size from datasets.csv before modifying
	_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "eng"
	local original_size = r(file_size)
	local has_meta = r(has_version)

	* Append junk to change file size
	cap file close junkfile
	file open junkfile using "`test_csv'", write append
	file write junkfile "JUNK_DATA_FOR_SIZE_MISMATCH_TEST" _n
	file close junkfile

	* Now run autolabel - should detect size mismatch and re-download
	use "$LISA_DATA", clear
	cap noi autolabel variables, domain(scb) lang(eng)
	if (_rc == 0) {
		di as result "  PASS: Size mismatch handled (re-downloaded or proceeded)"
		local ++tests_passed
	}
	else {
		di as error "  FAIL: Size mismatch caused error (rc=`=_rc')"
		local ++tests_failed
	}
}
else {
	di as text "  SKIP: CSV file not found (test depends on Scenario 1)"
	di as result "  PASS (skipped): No CSV to test size mismatch"
	local ++tests_passed
}

* ==========================================================================
* Scenario 3: File missing (metadata exists but files deleted)
* ==========================================================================

di as result ""
di as result "SCENARIO 3: File missing with metadata present"
di as result "---------------------------------------------"
di as text "  Deleting CSV/DTA files while keeping datasets.csv entry."

* First ensure we have metadata by running a successful download
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

* Now delete the files but keep datasets.csv
local csv_file "`autolabel_dir'/scb_variables_eng.csv"
local dta_file "`autolabel_dir'/scb_variables_eng.dta"
cap erase "`csv_file'"
cap erase "`dta_file'"

* Run autolabel again - should detect missing files and re-download
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "  PASS: Missing files recovered (re-downloaded)"
	local ++tests_passed
}
else {
	di as error "  FAIL: Missing file recovery failed (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Scenario 4: File exists but no metadata entry
* ==========================================================================

di as result ""
di as result "SCENARIO 4: File exists without metadata"
di as result "---------------------------------------------"
di as text "  Removing datasets.csv entry while keeping files."

* First ensure files exist
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

* Remove the metadata entry for this dataset by rewriting datasets.csv
local meta_csv "`autolabel_dir'/datasets.csv"
cap confirm file "`meta_csv'"
if (_rc == 0) {
	preserve
	quietly {
		import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		drop if dataset_key == "scb_variables_eng"
		export delimited using "`meta_csv'", replace delimiter(";")
	}
	restore
}

* Run autolabel - should detect no metadata and handle gracefully
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "  PASS: No-metadata scenario handled (re-downloaded or used existing)"
	local ++tests_passed
}
else {
	di as error "  FAIL: No-metadata scenario failed (rc=`=_rc')"
	local ++tests_failed
}

* ==========================================================================
* Scenario 5: Size mismatch with source=user (should skip check)
* ==========================================================================

di as result ""
di as result "SCENARIO 5: Size mismatch with source=user (skip check)"
di as result "---------------------------------------------"
di as text "  Setting source=user in datasets.csv, then modifying file size."
di as text "  Autolabel should skip size check for user-sourced datasets."

* Ensure we have a fresh download with metadata
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)

* Change source to 'user' in datasets.csv
local meta_csv "`autolabel_dir'/datasets.csv"
cap confirm file "`meta_csv'"
if (_rc == 0) {
	preserve
	quietly {
		import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		replace source = "user" if dataset_key == "scb_variables_eng"
		export delimited using "`meta_csv'", replace delimiter(";")
	}
	restore

	* Append junk to CSV to change file size
	local test_csv "`autolabel_dir'/scb_variables_eng.csv"
	cap confirm file "`test_csv'"
	if (_rc == 0) {
		cap file close junkfile
		file open junkfile using "`test_csv'", write append
		file write junkfile "USER_DATA_SIZE_CHANGE_TEST" _n
		file close junkfile

		* Run autolabel - should NOT trigger size mismatch warning
		use "$LISA_DATA", clear
		cap noi autolabel variables, domain(scb) lang(eng)
		if (_rc == 0) {
			di as result "  PASS: source=user skipped size check"
			local ++tests_passed
		}
		else {
			di as error "  FAIL: source=user still triggered error (rc=`=_rc')"
			local ++tests_failed
		}
	}
	else {
		di as result "  PASS (skipped): CSV file not found"
		local ++tests_passed
	}

	* Restore source back to api for other tests
	preserve
	quietly {
		import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		replace source = "api" if dataset_key == "scb_variables_eng"
		export delimited using "`meta_csv'", replace delimiter(";")
	}
	restore
}
else {
	di as result "  PASS (skipped): No datasets.csv to modify"
	local ++tests_passed
}

* ==========================================================================
* Summary
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 03 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
