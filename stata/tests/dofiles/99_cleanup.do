/*==============================================================================
  Test 99: Cleanup and Fresh State Verification

  Purpose: Delete config and dataset files, re-download 4 datasets from scratch,
           and verify a clean working state
  Author: Jeffrey Clark

  Steps:
    1. Delete config_stata.csv
    2. Delete all SCB dataset files from autolabel dir
    3. Fresh download 4 datasets (variables eng/swe, values eng/swe)
    4. Verify clean state: all 4 datasets present, metadata correct
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
di as result "Test 99: Cleanup and Fresh State"
di as result "============================================="
di as result ""

_rs_utils get_dir
local registream_dir "`r(dir)'"
local autolabel_dir "`registream_dir'/autolabel"

cap confirm file "$LISA_DATA"
if (_rc != 0) {
}

* ==========================================================================
* Step 1: Delete config_stata.csv
* ==========================================================================

di as result "STEP 1: Delete config_stata.csv"
di as result "---------------------------------------------"

local config_file "`registream_dir'/config_stata.csv"
cap confirm file "`config_file'"
if (_rc == 0) {
	erase "`config_file'"
	di as text "  Deleted: `config_file'"
}
else {
	di as text "  Config file did not exist (already clean)"
}

* Verify deletion
cap confirm file "`config_file'"
if (_rc != 0) {
	di as result "  PASS: config_stata.csv deleted"
	local ++tests_passed
}
else {
	di as error "  FAIL: config_stata.csv still exists"
	local ++tests_failed
}

* ==========================================================================
* Step 2: Delete all SCB dataset files from autolabel dir
* ==========================================================================

di as result ""
di as result "STEP 2: Delete all SCB dataset files"
di as result "---------------------------------------------"
di as text "  Removing files from: `autolabel_dir'"

* Delete the entire SCB domain subdirectory (new cache layout:
* ~/.registream/autolabel/{domain}/{type}_{lang}.{csv,dta})
local scb_subdir "`autolabel_dir'/scb"
cap _rs_utils del_folder_rec "`scb_subdir'"

* File names we expect inside the subdir (for verification)
local file_patterns "variables_eng variables_swe value_labels_eng value_labels_swe"

* Delete datasets.csv metadata
cap erase "`autolabel_dir'/datasets.csv"

* Delete usage log
cap erase "`registream_dir'/usage_stata.csv"

* Delete any zip files at the autolabel dir root
local zipfiles : dir "`autolabel_dir'" files "*.zip"
foreach zf of local zipfiles {
	cap erase "`autolabel_dir'/`zf'"
}

* Verify cleanup
local still_exists = 0
foreach pat of local file_patterns {
	cap confirm file "`scb_subdir'/`pat'.csv"
	if (_rc == 0) local ++still_exists
	cap confirm file "`scb_subdir'/`pat'.dta"
	if (_rc == 0) local ++still_exists
}

if (`still_exists' == 0) {
	di as result "  PASS: All SCB dataset files deleted"
	local ++tests_passed
}
else {
	di as error "  FAIL: `still_exists' file(s) still remain"
	local ++tests_failed
}

* ==========================================================================
* Step 3: Fresh download of 4 datasets
* ==========================================================================

di as result ""
di as result "STEP 3: Fresh download of 4 datasets"
di as result "---------------------------------------------"
di as text "  Downloading: variables eng, variables swe, values eng, values swe"
di as text ""

local download_ok = 0
local download_fail = 0

* Dataset 1: Variables English
di as text "  [1/4] scb_variables_eng..."
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "    OK"
	local ++download_ok
}
else {
	di as error "    FAILED (rc=`=_rc')"
	local ++download_fail
}

* Dataset 2: Variables Swedish
di as text "  [2/4] scb_variables_swe..."
use "$LISA_DATA", clear
cap noi autolabel variables, domain(scb) lang(swe)
if (_rc == 0) {
	di as result "    OK"
	local ++download_ok
}
else {
	di as error "    FAILED (rc=`=_rc')"
	local ++download_fail
}

* Dataset 3: Values English
di as text "  [3/4] scb_value_labels_eng..."
use "$LISA_DATA", clear
cap noi autolabel values, domain(scb) lang(eng)
if (_rc == 0) {
	di as result "    OK"
	local ++download_ok
}
else {
	di as error "    FAILED (rc=`=_rc')"
	local ++download_fail
}

* Dataset 4: Values Swedish
di as text "  [4/4] scb_value_labels_swe..."
use "$LISA_DATA", clear
cap noi autolabel values, domain(scb) lang(swe)
if (_rc == 0) {
	di as result "    OK"
	local ++download_ok
}
else {
	di as error "    FAILED (rc=`=_rc')"
	local ++download_fail
}

if (`download_ok' == 4) {
	di as result "  PASS: All 4 datasets downloaded successfully"
	local ++tests_passed
}
else {
	di as error "  FAIL: `download_ok'/4 downloaded, `download_fail' failed"
	local ++tests_failed
}

* ==========================================================================
* Step 4: Verify clean state
* ==========================================================================

di as result ""
di as result "STEP 4: Verify clean state"
di as result "---------------------------------------------"

local verify_ok = 0

* Check config exists
cap confirm file "`registream_dir'/config_stata.csv"
if (_rc == 0) {
	di as text "  config_stata.csv:  EXISTS"
	local ++verify_ok
}
else {
	di as error "  config_stata.csv:  MISSING"
}

* Check datasets.csv exists and has entries
cap confirm file "`autolabel_dir'/datasets.csv"
if (_rc == 0) {
	preserve
	quietly import delimited using "`autolabel_dir'/datasets.csv", clear varnames(1) stringcols(_all) delimiter(";")
	local nrows = _N
	restore
	di as text "  datasets.csv:      EXISTS (`nrows' entries)"
	if (`nrows' >= 4) local ++verify_ok
}
else {
	di as error "  datasets.csv:      MISSING"
}

* Check each dataset file exists in the scb subdirectory
foreach pat of local file_patterns {
	cap confirm file "`scb_subdir'/`pat'.dta"
	if (_rc == 0) {
		di as text "  scb/`pat'.dta: EXISTS"
		local ++verify_ok
	}
	else {
		di as error "  scb/`pat'.dta: MISSING"
	}
}

* We expect: config(1) + datasets.csv with >=4 rows(1) + 4 DTA files = 6
if (`verify_ok' >= 6) {
	di as result "  PASS: Clean state verified (`verify_ok'/6 checks)"
	local ++tests_passed
}
else {
	di as error "  FAIL: Clean state incomplete (`verify_ok'/6 checks)"
	local ++tests_failed
}

* ==========================================================================
* Summary
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 99 Results: `tests_passed'/`tests_total' passed"
if (`tests_failed' > 0) {
	di as error "`tests_failed' test(s) FAILED"
	exit 1
}
else {
	di as result "All tests passed!"
}
di as result "============================================="
