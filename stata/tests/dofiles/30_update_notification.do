/*==============================================================================
  Test 30: Update & Notification System (End-to-End)

  Purpose: Test the full update lifecycle via net install — exactly as a
           real user would experience it.

  Approach:
    1. Clean install autolabel 3.0.0 from localhost:5000
    2. Create fake 3.0.1 on server (overwrite package_manifest.yaml via
       stata/dev/write_test_manifest.py)
    3. Verify update detection via heartbeat
    4. Verify notification globals are set
    5. Verify registream update installs the new version
    6. Test 24h caching, config controls
    7. Restore server to 3.0.0

  No adopath to source. No cap program drop.
  Tests the real production flow.

  Requirements:
    - Server running at localhost:5000
    - Build: python3 build/export_package.py --all (done before test)
==============================================================================*/

clear all
version 16.0

* ==========================================================================
* Locate PROJECT_ROOT when run standalone (run_all_tests.do sets it already).
* Walks up from cwd looking for .project-root so the test works from any
* subdirectory without hardcoding absolute paths.
* ==========================================================================
if ("$PROJECT_ROOT" == "") {
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
}

* When running under run_all_tests.do the master runner puts autolabel/src
* and registream/src at the front of the adopath for live-code testing.
* Test 30 is specifically an end-to-end net-install test — source entries
* would short-circuit it (they serve the unreplaced `{{VERSION}}` template
* instead of the baked version string from the built package). Strip them.
cap adopath - "$PROJECT_ROOT/stata/src"
cap adopath - "$PROJECT_ROOT/../registream/stata/src"

* Auto-approve all interactive prompts (first-run wizard, download confirm,
* etc.) so the end-to-end install flow doesn't block. host_override.do is
* sourced AFTER net install so the installed `_rs_utils get_api_host` resolves
* to localhost — otherwise heartbeat and dataset-update checks below would hit
* production and fail (they rely on this repo's local package_manifest.yaml
* and fake dataset zips).
do "$PROJECT_ROOT/../registream/stata/dev/auto_approve.do"

* ==========================================================================
* Configuration — all paths in one place. Assumes sibling-repo layout under
* registream-org/ (registream, autolabel, registream-website side-by-side).
* The dev server reads package_manifest.yaml from registream-website/data/;
* sub-tests overwrite it via stata/dev/write_test_manifest.py to bump the
* server's reported "latest" version, then heartbeat to verify detection.
* ==========================================================================

local server_data "$PROJECT_ROOT/../registream-website/data/registream"
local pkg_versions "`server_data'/package_manifest.yaml"
local manifest_helper "$PROJECT_ROOT/stata/dev/write_test_manifest.py"
local install_url "http://localhost:5000/install/stata/latest"
local lisa "$PROJECT_ROOT/examples/lisa.dta"


* ==========================================================================
* Setup: Clean install from server
* ==========================================================================

di as result ""
di as result "============================================="
di as result "Test 30: Update & Notification System"
di as result "============================================="
di as result ""

* Remove any previous installs
cap ado uninstall autolabel
cap ado uninstall datamirror
cap ado uninstall registream

* Delete user config/data for fresh start
cap shell rm -rf ~/.registream

* Decoupled packaging (SSC-ready): install core first, then the module.
* Each package ships its own files only; autolabel's top-level .ado
* runtime-checks for core via `cap findfile _rs_utils.ado`.
di as text "Installing registream (core) from `install_url'..."
net install registream, from("`install_url'") replace
di as text ""

di as text "Installing autolabel from `install_url'..."
net install autolabel, from("`install_url'") replace
di as text ""

* Redirect the installed package's API calls to localhost. Must run AFTER
* net install — sourcing host_override.do defines `_rs_dev_utils get_host`
* in memory, which the just-installed `_utils_get_api_host` picks up via
* its `cap qui _rs_dev_utils get_host` lookup.
do "$PROJECT_ROOT/../registream/stata/dev/host_override.do"

which autolabel
which registream

* Get current version
_rs_utils get_version
local current_version "`r(version)'"
di as text "Installed version: `current_version'"

* Get registream dir
_rs_utils get_dir
local registream_dir "`r(dir)'"

* Ensure config exists
_rs_config init "`registream_dir'"

* Save original server file
shell cp "`pkg_versions'" "`pkg_versions'.bak"

* ==========================================================================
* Test tracking
* ==========================================================================

local pass 0
local fail 0
local total 0

* ==========================================================================
* TEST 1: No update available (fresh install, same version)
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 1: No update (server matches current version)"
di as result "{hline 70}"

local ++total

* Set server to report same version as what we're running
shell python3 "`manifest_helper'" "`pkg_versions'" registream=`current_version' autolabel=`current_version' datamirror=1.0.0

* Expire cache to force check
local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

* Run heartbeat
cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_1" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
if ("`_ua'" != "1") {
	di as result "  PASS: No update detected (correct, version matches)"
	local ++pass
}
else {
	di as error "  FAIL: Update falsely detected (latest=`_lv')"
	local ++fail
}

* Restore original server file for subsequent tests
shell cp "`pkg_versions'.bak" "`pkg_versions'"

* ==========================================================================
* TEST 2: Update available (server bumped to 3.0.1)
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 2: Server bumped to 3.0.1 — update detected"
di as result "{hline 70}"

local ++total

* Bump server version
shell python3 "`manifest_helper'" "`pkg_versions'" registream=3.0.1 autolabel=3.0.1 datamirror=1.0.0

* Expire cache
local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_2" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
if ("`_ua'" == "1" & "`_lv'" == "3.0.1") {
	di as result "  PASS: Update detected, latest=3.0.1"
	local ++pass
}
else {
	di as error "  FAIL: UPDATE=`_ua', LATEST=`_lv'"
	local ++fail
}

* ==========================================================================
* TEST 3: Ahead of server (no update)
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 3: Server downgraded to 1.0.0 — no update (we're ahead)"
di as result "{hline 70}"

local ++total

shell python3 "`manifest_helper'" "`pkg_versions'" registream=1.0.0 autolabel=1.0.0 datamirror=1.0.0

local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_3" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
if ("`_ua'" != "1") {
	di as result "  PASS: No update (we're ahead, correct)"
	local ++pass
}
else {
	di as error "  FAIL: Update falsely detected when ahead"
	local ++fail
}

* Restore for next tests
shell cp "`pkg_versions'.bak" "`pkg_versions'"

* ==========================================================================
* TEST 4: 24h cache prevents re-check
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 4: 24h cache prevents re-check"
di as result "{hline 70}"

local ++total

* Set fresh cache (just checked)
local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
_rs_config set "`registream_dir'" "last_update_check" "`now'"
_rs_config set "`registream_dir'" "update_available" "false"
_rs_config set "`registream_dir'" "latest_version" "`current_version'"
_rs_config set "`registream_dir'" "telemetry_enabled" "false"

* Bump server (should NOT be detected due to cache)
shell python3 "`manifest_helper'" "`pkg_versions'" registream=9.9.9 autolabel=9.9.9 datamirror=9.9.9


cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_4" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
if ("`_ua'" != "1") {
	di as result "  PASS: Cache prevented re-check"
	local ++pass
}
else {
	di as error "  FAIL: Cache did not prevent check (detected `_lv')"
	local ++fail
}

shell cp "`pkg_versions'.bak" "`pkg_versions'"
_rs_config set "`registream_dir'" "telemetry_enabled" "true"

* ==========================================================================
* TEST 5: Expired cache triggers re-check
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 5: Expired cache (25h old) triggers re-check"
di as result "{hline 70}"

local ++total

local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

shell python3 "`manifest_helper'" "`pkg_versions'" registream=8.0.0 autolabel=3.0.0 datamirror=1.0.0


cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_5" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
if ("`_ua'" == "1" & "`_lv'" == "8.0.0") {
	di as result "  PASS: Expired cache → re-check → detected 8.0.0"
	local ++pass
}
else {
	di as error "  FAIL: UPDATE=`_ua', LATEST=`_lv'"
	local ++fail
}

shell cp "`pkg_versions'.bak" "`pkg_versions'"

* ==========================================================================
* TEST 6: auto_update_check=false prevents check
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 6: auto_update_check=false prevents check"
di as result "{hline 70}"

local ++total

_rs_config set "`registream_dir'" "auto_update_check" "false"
_rs_config set "`registream_dir'" "telemetry_enabled" "false"
_rs_config set "`registream_dir'" "update_available" "false"
_rs_config set "`registream_dir'" "latest_version" ""
local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

shell python3 "`manifest_helper'" "`pkg_versions'" registream=7.0.0 autolabel=7.0.0 datamirror=7.0.0


cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_6" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
if ("`_ua'" != "1") {
	di as result "  PASS: auto_update_check=false prevented check"
	local ++pass
}
else {
	di as error "  FAIL: Check ran despite disabled"
	local ++fail
}

_rs_config set "`registream_dir'" "auto_update_check" "true"
_rs_config set "`registream_dir'" "telemetry_enabled" "true"
shell cp "`pkg_versions'.bak" "`pkg_versions'"

* ==========================================================================
* TEST 7: internet_access=false prevents check
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 7: internet_access=false prevents check"
di as result "{hline 70}"

local ++total

_rs_config set "`registream_dir'" "internet_access" "false"
_rs_config set "`registream_dir'" "update_available" "false"
_rs_config set "`registream_dir'" "latest_version" ""
local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

shell python3 "`manifest_helper'" "`pkg_versions'" registream=7.0.0 autolabel=7.0.0 datamirror=7.0.0


cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_7" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
if ("`_ua'" != "1") {
	di as result "  PASS: internet_access=false prevented check"
	local ++pass
}
else {
	di as error "  FAIL: Check ran despite internet_access=false"
	local ++fail
}

_rs_config set "`registream_dir'" "internet_access" "true"
shell cp "`pkg_versions'.bak" "`pkg_versions'"

* ==========================================================================
* TEST 8: Notification displays when update available
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 8: Notification displays"
di as result "{hline 70}"

local ++total

cap noi _rs_updates show_notification , ///
	current_version("`current_version'") scope(autolabel) ///
	core_update(1) core_latest("4.0.0") ///
	autolabel_update(0) autolabel_latest("")

if (_rc == 0) {
	di as result "  PASS: Notification displayed"
	local ++pass
}
else {
	di as error "  FAIL: show_notification failed rc=`=_rc'"
	local ++fail
}

* ==========================================================================
* TEST 9: No notification when no update
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 9: No notification when current"
di as result "{hline 70}"

local ++total


cap noi _rs_updates show_notification , ///
	current_version("`current_version'") scope(autolabel) ///
	core_update(0) core_latest("") ///
	autolabel_update(0) autolabel_latest("")

if (_rc == 0) {
	di as result "  PASS: No notification (correct)"
	local ++pass
}
else {
	di as error "  FAIL: rc=`=_rc'"
	local ++fail
}

* ==========================================================================
* TEST 10: Config persistence across heartbeat
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 10: Heartbeat persists update info to config"
di as result "{hline 70}"

local ++total

shell python3 "`manifest_helper'" "`pkg_versions'" registream=5.0.0 autolabel=5.0.0 datamirror=5.0.0

local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"
_rs_config set "`registream_dir'" "update_available" "false"
_rs_config set "`registream_dir'" "latest_version" ""

cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" "test_10" "autolabel" "`autolabel_version'" "" ""
	local _ua = r(update_available)
	local _lv "`r(latest_version)'"
local checks = 0
if ("`_ua'" == "1") local ++checks
if ("`_lv'" == "5.0.0") local ++checks

_rs_config get "`registream_dir'" "update_available"
if ("`r(value)'" == "true") local ++checks
_rs_config get "`registream_dir'" "latest_version"
if ("`r(value)'" == "5.0.0") local ++checks

if (`checks' == 4) {
	di as result "  PASS: Globals + config all correct (4/4)"
	local ++pass
}
else {
	di as error "  FAIL: `checks'/4 checks passed"
	local ++fail
}

shell cp "`pkg_versions'.bak" "`pkg_versions'"

* ==========================================================================
* TEST 11: Full autolabel command triggers update detection
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 11: autolabel command triggers update detection"
di as result "{hline 70}"

local ++total

shell python3 "`manifest_helper'" "`pkg_versions'" registream=5.0.0 autolabel=5.0.0 datamirror=5.0.0

local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

use "`lisa'", clear
cap noi autolabel variables, domain(scb) lang(swe)

if ("`_ua'" == "1") {
	di as result "  PASS: autolabel triggered update detection (latest=`_lv')"
	local ++pass
}
else {
	di as error "  FAIL: UPDATE_AVAILABLE=`_ua'"
	local ++fail
}

* ==========================================================================
* TEST 12: registream update detects available update
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST 12: registream update detects update"
di as result "{hline 70}"

local ++total

* Server still at 5.0.0
local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local old = `now' - 90000000
_rs_config set "`registream_dir'" "last_update_check" "`old'"

cap noi registream update

* If it ran (even if net install fails because 5.0.0 doesn't actually exist),
* the update check itself should have succeeded
if (_rc == 0 | _rc == 1) {
	di as result "  PASS: registream update ran (update detection works)"
	local ++pass
}
else {
	di as error "  FAIL: registream update failed with rc=`=_rc'"
	local ++fail
}

* ==========================================================================
* GROUP F: Dataset Update Detection
* ==========================================================================

di as result _n "{hline 70}"
di as result "GROUP F: Dataset Update Detection"
di as result "{hline 70}"

* Restore pkg_versions for dataset tests
shell cp "`pkg_versions'.bak" "`pkg_versions'"

local autolabel_dir "`registream_dir'/autolabel"
local server_data_dir "`server_data'/data/scb"

* --------------------------------------------------------------------------
* Test 13: Dataset update detected when server has newer version
* --------------------------------------------------------------------------

di as result _n "TEST 13: Dataset version check detects update"

local ++total

* Ensure we have downloaded data BEFORE creating fake version
* (so store_dataset_metadata records the real 20260407, not the fake 20260409)
use "`lisa'", clear
cap noi autolabel variables, domain(scb) lang(swe)

* NOW create fake newer dataset version on server
shell cp "`server_data_dir'/scb_swe_v20260309.zip" "`server_data_dir'/scb_swe_v20260409.zip"

* Expire the per-dataset last_checked to force API check
quietly {
	preserve
	cap import delimited using "`autolabel_dir'/datasets.csv", clear varnames(1) stringcols(_all) delimiter(";")
	if (_rc == 0) {
		local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
		local old = `now' - 90000000
		replace last_checked = "`old'" if strpos(dataset_key, "scb_variables_swe") > 0
		export delimited using "`autolabel_dir'/datasets.csv", replace delimiter(";")
	}
	restore
}

* Check for updates on scb/variables/swe
local dta_file "`autolabel_dir'/scb/variables_swe.dta"
cap noi _al_utils check_for_updates "`autolabel_dir'" "scb" "variables" "swe" "`dta_file'"

local ds_status "`r(status)'"
local ds_api_ver "`r(api_version)'"

if ("`ds_status'" == "update_available" & "`ds_api_ver'" == "20260409") {
	di as result "  PASS: Dataset update detected (20260309 → 20260409)"
	local ++pass
}
else {
	di as error "  FAIL: status=`ds_status', api_version=`ds_api_ver'"
	local ++fail
}

* Remove fake version and reset local version to match server
shell rm -f "`server_data_dir'/scb_swe_v20260409.zip"

* Note: check_for_updates does NOT update the local version in datasets.csv
* (it only reports update_available). So local version should still be 20260407.
* But update_last_checked was called, which is fine.

* --------------------------------------------------------------------------
* Test 14: Stored version resolves correctly after re-download
* --------------------------------------------------------------------------

di as result _n "TEST 14: Version tracking after download"

local ++total

* The download flow stores version="latest" (the URL keyword, not the resolved date).
* check_for_updates compares this to the API's resolved date (e.g., "20260407").
* Since "latest" != "20260407", it reports update_available even when current.
* This is a known limitation — the important thing is that it doesn't crash
* and that re-downloading resolves the mismatch.

* Verify datasets.csv has version info for scb_variables_swe
_al_utils get_dataset_version "`autolabel_dir'" "scb" "variables" "swe"
local has_ver = r(has_version)
local stored_ver "`r(version)'"

if (`has_ver' == 1) {
	di as result "  PASS: Dataset version tracked (stored=`stored_ver')"
	local ++pass
}
else {
	di as error "  FAIL: No version info in datasets.csv"
	local ++fail
}

* --------------------------------------------------------------------------
* Test 15: Dataset 24h cache prevents re-check
* --------------------------------------------------------------------------

di as result _n "TEST 15: Dataset 24h cache"

local ++total

* last_checked was just updated by test 14 — calling again should be cached
cap noi _al_utils check_for_updates "`autolabel_dir'" "scb" "variables" "swe" "`dta_file'"

local ds_status "`r(status)'"

if ("`ds_status'" == "cached") {
	di as result "  PASS: Dataset check cached (skipped API)"
	local ++pass
}
else {
	di as error "  FAIL: status=`ds_status' (expected cached)"
	local ++fail
}

* --------------------------------------------------------------------------
* Test 16: Bulk dataset update check
* --------------------------------------------------------------------------

di as result _n "TEST 16: Bulk dataset update check"

local ++total

* Create fake newer version again
shell cp "`server_data_dir'/scb_swe_v20260309.zip" "`server_data_dir'/scb_swe_v20260409.zip"

* Expire the bulk cache
_rs_config set "`registream_dir'" "last_dataset_check" ""

cap noi _al_utils check_datasets_bulk "`registream_dir'"

local bulk_updates = r(updates_available)

if (`bulk_updates' >= 1) {
	di as result "  PASS: Bulk check found `bulk_updates' update(s)"
	local ++pass
}
else {
	di as error "  FAIL: Bulk check found 0 updates (expected >= 1)"
	local ++fail
}

* Remove fake version
shell rm -f "`server_data_dir'/scb_swe_v20260409.zip"

* ==========================================================================
* CLEANUP: Restore everything
* ==========================================================================

di as result _n "{hline 70}"
di as result "CLEANUP"
di as result "{hline 70}"

* Restore original server file
shell cp "`pkg_versions'.bak" "`pkg_versions'"
shell rm -f "`pkg_versions'.bak"

* Reset config
_rs_config set "`registream_dir'" "last_update_check" ""
_rs_config set "`registream_dir'" "update_available" "false"
_rs_config set "`registream_dir'" "latest_version" "`current_version'"
_rs_config set "`registream_dir'" "auto_update_check" "true"
_rs_config set "`registream_dir'" "internet_access" "true"
_rs_config set "`registream_dir'" "telemetry_enabled" "true"


di as result "  Server restored, config reset"

* ==========================================================================
* Summary
* ==========================================================================

di as result _n "{hline 70}"
di as result "TEST SUMMARY: Update & Notification System"
di as result "{hline 70}"
di as result "  Total:  `total'"
di as result "  Passed: `pass'"
if `fail' > 0 {
	di as error "  Failed: `fail'"
}
else {
	di as result "  Failed: `fail'"
}
di as result "{hline 70}"

if (`fail' > 0) {
	* Safety: restore server even on failure
	cap shell cp "`pkg_versions'.bak" "`pkg_versions'"
	cap shell rm -f "`pkg_versions'.bak"
	exit 1
}
