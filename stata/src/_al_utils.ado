* =============================================================================
* RegiStream Autolabel Utility Functions
* Utilities specific to the autolabel module
* Usage: _al_utils subcommand [args]
* =============================================================================

program define _al_utils, rclass
	version 16.0

	gettoken subcmd 0 : 0, parse(" ,")

	if ("`subcmd'" == "append_csv") {
		_al_append `0'
	}
	else if ("`subcmd'" == "summarize_dataset") {
		_al_summarize `0'
		return add
	}
	else if ("`subcmd'" == "fetch_with_errors") {
		_al_fetch `0'
		return add
	}
	else if ("`subcmd'" == "store_dataset_metadata") {
		_al_store_meta `0'
	}
	else if ("`subcmd'" == "get_dataset_version") {
		_al_get_ver `0'
		return add
	}
	else if ("`subcmd'" == "check_for_updates") {
		_al_check_updates `0'
		return add
	}
	else if ("`subcmd'" == "prompt_user") {
		_rs_utils prompt `0'
		return add
	}
	else if ("`subcmd'" == "update_last_checked") {
		_al_update_checked `0'
	}
	else if ("`subcmd'" == "show_updates") {
		_al_show_updates `0'
	}
	else if ("`subcmd'" == "update_datasets_interactive") {
		_al_update_datasets_interactive `0'
		return add
	}
	else if ("`subcmd'" == "download_bundle") {
		_al_download_bundle `0'
		return add
	}
	else if ("`subcmd'" == "ensure_bundle") {
		_al_ensure_bundle `0'
		return add
	}
	else {
		di as error "Invalid _al_utils subcommand: `subcmd'"
		exit 198
	}
end

* -----------------------------------------------------------------------------
* ensure_bundle: guarantee that an unzipped constituent folder is on disk for
* (domain, lang). Three-state cascade, earliest-exit first:
*
*   A. Extracted folder already at {autolabel_dir}/{domain}_{lang}/  → use it
*   B. Bundle ZIP at {autolabel_dir}/{domain}_{lang}_v{version}.zip → unzipfile
*   C. Nothing on disk → resolve version, prompt user, download, unzipfile
*
* States A and B support MONA / secure-env workflows: a sysadmin transfers
* either the unzipped folder or the zip, the user runs autolabel, and the
* cascade picks it up without API access.
*
* Returns r():
*   extract_folder  resolved path to the extracted constituent folder
*   from_api        1 if downloaded fresh (state C), 0 if pre-staged (A/B)
*   actual_version  resolved version (empty for state A, parsed from filename
*                   in state B, from /info in state C)
*   bundle_schema   schema version reported by API (defaults to 2.0)
*   cleanup_zip     path to a zip file that the caller may erase after use
*                   (set in states B and C; empty in A)
* -----------------------------------------------------------------------------
program define _al_ensure_bundle, rclass
	syntax , domain(string) lang(string) registream_dir(string) autolabel_dir(string) [version(string) force]

	local extract_folder "`autolabel_dir'/`domain'_`lang'"

	* `force` means "I want a fresh download" — skip pre-staged states (A, B)
	* and go straight to API. Used by the update workflow to re-pull current
	* bundles even when local copies happen to be on disk.
	local _skip_local = ("`force'" == "force")

	* ---- State A: extracted folder already present ----
	if (`_skip_local' == 0) {
		cap confirm file "`extract_folder'/variables/0000.csv"
		if (_rc == 0) {
			di as text ""
			di as text "  Using extracted bundle at `extract_folder' (no download)."
			return local extract_folder "`extract_folder'"
			return scalar from_api = 0
			return local actual_version ""
			return local bundle_schema "2.0"
			return local cleanup_zip ""
			exit 0
		}
	}

	* ---- State B: bundle ZIP on disk ----
	* Match {domain}_{lang}_v*.zip; if a specific version was requested, prefer it.
	local zip_pattern "`domain'_`lang'_v*.zip"
	if ("`version'" != "" & "`version'" != "latest") {
		local zip_pattern "`domain'_`lang'_v`version'.zip"
	}
	local _zips_in_dir : dir "`autolabel_dir'" files "`zip_pattern'"
	if (`_skip_local' == 0 & `: word count `_zips_in_dir'' > 0) {
		* Pick the lexically last (newest version when YYYYMMDD format) match.
		local _sorted_zips : list sort _zips_in_dir
		local _zip_basename : word `: word count `_sorted_zips'' of `_sorted_zips'
		local _zip_stem = subinstr("`_zip_basename'", ".zip", "", .)

		di as text ""
		di as text "  Using bundle ZIP at `autolabel_dir'/`_zip_basename' (no download)."

		local original_dir `"`c(pwd)'"'
		quietly cd "`autolabel_dir'"
		cap unzipfile "`_zip_basename'", replace
		local unzip_rc = _rc
		quietly cd "`original_dir'"

		if (`unzip_rc' != 0) {
			di as error "Failed to extract `_zip_basename' (rc=`unzip_rc')."
			exit 198
		}

		* Parse version from filename: {domain}_{lang}_v{version}.zip
		local _parsed_version ""
		if (regexm("`_zip_stem'", "_v([0-9A-Za-z._-]+)$")) {
			local _parsed_version = regexs(1)
		}

		return local extract_folder "`extract_folder'"
		return scalar from_api = 0
		return local actual_version "`_parsed_version'"
		return local bundle_schema "2.0"
		return local cleanup_zip "`autolabel_dir'/`_zip_basename'"
		exit 0
	}

	* ---- State C: download from API ----
	* Internet-access gate
	_rs_config get "`registream_dir'" "internet_access"
	local internet_access "`r(value)'"
	if ("`internet_access'" == "") local internet_access "true"
	if ("`internet_access'" == "false") {
		di as error "Cannot download: internet_access is disabled."
		di as error "Enable with: registream config, internet_access(true)"
		di as error "Or pre-stage the bundle ZIP at `autolabel_dir'/`domain'_`lang'_v{ver}.zip"
		exit 198
	}

	* Resolve version + schema from /info endpoint when version is unspecified
	_rs_utils get_api_host
	local api_host "`r(host)'"
	local bundle_schema "2.0"
	if ("`version'" == "" | "`version'" == "latest") {
		local info_url "`api_host'/api/v1/datasets/`domain'/variables/`lang'/latest/info?format=stata&schema_max=2.0"
		local actual_version "latest"
		tempfile info_resp
		cap copy "`info_url'" "`info_resp'", replace
		if (_rc == 0) {
			tempname fh
			cap file open `fh' using "`info_resp'", read text
			if (_rc == 0) {
				file read `fh' line
				while (r(eof) == 0) {
					if (regexm("`line'", "^version=(.+)$")) {
						local actual_version = trim(regexs(1))
					}
					else if (regexm("`line'", "^schema=(.+)$")) {
						local bundle_schema = trim(regexs(1))
					}
					file read `fh' line
				}
				file close `fh'
			}
		}
	}
	else {
		local actual_version "`version'"
	}

	local zip_name "`domain'_`lang'_v`actual_version'"
	local download_url "`api_host'/api/v1/datasets/`domain'/variables/`lang'/`actual_version'?schema_max=2.0"

	* Prompt user (skipped when caller passes `force')
	if ("`force'" != "force") {
		di as text ""
		di as text "  Metadata not cached for `domain'/`lang'."
		_rs_utils prompt ///
			"  Download from RegiStream?"
		* _rs_utils prompt exits on "no"; reaching here means user approved.
	}

	di as text ""
	di as text "  Downloading metadata for `domain'/`lang' (version `actual_version')..."

	local original_dir `"`c(pwd)'"'
	quietly cd "`autolabel_dir'"

	cap copy "`download_url'" "`zip_name'.zip", replace
	if (_rc != 0) {
		quietly cd "`original_dir'"
		di as error "  Download failed (rc=`=_rc')."
		exit _rc
	}

	cap unzipfile "`zip_name'.zip", replace
	local unzip_rc = _rc
	quietly cd "`original_dir'"

	if (`unzip_rc' != 0) {
		di as error "Failed to extract ZIP file (rc=`unzip_rc')."
		cap erase "`autolabel_dir'/`zip_name'.zip"
		exit 198
	}

	return local extract_folder "`extract_folder'"
	return scalar from_api = 1
	return local actual_version "`actual_version'"
	return local bundle_schema "`bundle_schema'"
	return local cleanup_zip "`autolabel_dir'/`zip_name'.zip"
end


* -----------------------------------------------------------------------------
* download_bundle: ensure a constituent folder exists (via _al_ensure_bundle's
* 3-state cascade), then process each file type into cached CSV+DTA pairs.
* datasets.csv is updated only when the cascade ran the API path (state C).
* -----------------------------------------------------------------------------
program define _al_download_bundle, rclass
	syntax , domain(string) lang(string) registream_dir(string) autolabel_dir(string) [version(string) force]

	* Cache file paths
	local var_csv "`autolabel_dir'/`domain'/variables_`lang'.csv"
	local var_dta "`autolabel_dir'/`domain'/variables_`lang'.dta"
	local val_csv "`autolabel_dir'/`domain'/value_labels_`lang'.csv"
	local val_dta "`autolabel_dir'/`domain'/value_labels_`lang'.dta"
	local scope_csv "`autolabel_dir'/`domain'/scope_`lang'.csv"
	local scope_dta "`autolabel_dir'/`domain'/scope_`lang'.dta"
	local rs_csv "`autolabel_dir'/`domain'/release_sets_`lang'.csv"
	local rs_dta "`autolabel_dir'/`domain'/release_sets_`lang'.dta"
	local manifest_csv "`autolabel_dir'/`domain'/manifest_`lang'.csv"

	* Already-cached short-circuit (skip cascade entirely if both core DTAs exist)
	if ("`force'" != "force") {
		cap confirm file "`var_dta'"
		local var_ok = (_rc == 0)
		cap confirm file "`val_dta'"
		local val_ok = (_rc == 0)
		if (`var_ok' & `val_ok') {
			return scalar downloaded = 0
			exit 0
		}
	}

	* Run the 3-state cascade. Errors propagate if all three fail.
	_al_ensure_bundle, domain("`domain'") lang("`lang'") ///
		registream_dir("`registream_dir'") autolabel_dir("`autolabel_dir'") ///
		version("`version'") `force'
	local extract_folder   "`r(extract_folder)'"
	local from_api         = r(from_api)
	local actual_version   "`r(actual_version)'"
	local bundle_schema    "`r(bundle_schema)'"
	local cleanup_zip      "`r(cleanup_zip)'"

	* Create domain subdirectory for cached files
	cap mkdir "`autolabel_dir'/`domain'"

	* Process each file type: find constituent CSVs in subfolders, append, import
	foreach ft in "variables" "value_labels" "scope" "release_sets" "manifest" {

		local csv_folder "`extract_folder'/`ft'"

		* Check if this subfolder exists and has CSVs
		cap local csv_files : dir "`csv_folder'" files "*.csv"
		if (_rc != 0 | `: word count `csv_files'' == 0) {
			if ("`ft'" == "scope") {
				di as text "  No scope folder in bundle (optional)."
				continue
			}
			di as error "  `ft' folder not found in bundle!"
			continue
		}

		* Determine output paths
		if ("`ft'" == "variables") {
			local out_csv "`var_csv'"
			local out_dta "`var_dta'"
			local file_type_label "variables"
		}
		else if ("`ft'" == "value_labels") {
			local out_csv "`val_csv'"
			local out_dta "`val_dta'"
			local file_type_label "values"
		}
		else if ("`ft'" == "release_sets") {
			local out_csv "`rs_csv'"
			local out_dta "`rs_dta'"
			local file_type_label "release_sets"
		}
		else if ("`ft'" == "manifest") {
			local out_csv "`manifest_csv'"
			local out_dta ""
			local file_type_label "manifest"
		}
		else {
			local out_csv "`scope_csv'"
			local out_dta "`scope_dta'"
			local file_type_label "scope"
		}

		* Manifest is a raw CSV; copy the single chunk directly, skip DTA conversion
		if ("`ft'" == "manifest") {
			local _mf : dir "`csv_folder'" files "*.csv"
			local _mf_first : word 1 of `_mf'
			quietly copy "`csv_folder'/`_mf_first'" "`out_csv'", replace
			continue
		}

		* Append constituent CSVs + import to DTA (preserve protects user's dataset)
		preserve
		local _dl_rc 0
		quietly {
			_al_utils append_csv "`csv_folder'" "`out_csv'"
			* stringcols(_all) defends against type-inference when an entire
			* column is empty (e.g., variable_unit empty across all SSB rows
			* would otherwise be inferred as byte, causing downstream type
			* mismatch in label concatenation; same issue motivated the scope
			* branch). Destring numeric ID columns afterwards so merge/join
			* semantics are preserved.
			import delimited using "`out_csv'", clear ///
				encoding("utf-8") bindquote(strict) maxquotedrows(unlimited) ///
				stringcols(_all)
			cap destring scope_id, replace
			cap destring value_label_id, replace
			cap destring release_set_id, replace
			cap destring code_count, replace

			* Lowercase variable_name
			cap confirm variable variable_name
			if (_rc == 0) {
				replace variable_name = lower(variable_name)
				sort variable_name

				* v1 dedup applies ONLY to the `variables` file, where
				* variable_name is the actual Stata variable name and
				* deduplicating to one row per variable is meaningful.
				*
				* For value_labels, variable_name is the label-set NAME
				* (e.g. "SUN 2000 - Utbildningsinriktning"), and many
				* distinct value_label_ids legitimately share the same
				* name across registers/versions. Dedup here would silently
				* drop ~43% of label entries (sun2000inr, astsni2007, ...).
				if ("`ft'" == "variables") {
					* Only dedup for v1.0 (no release_set_id); v2.0 keeps
					* all rows (one per release_set_id) for multi-register counts.
					cap confirm variable release_set_id
					if (_rc != 0) {
						bysort variable_name: keep if _n == 1
					}
				}

				* Drop empty variable_name rows
				drop if missing(variable_name) | variable_name == ""
			}

			* Schema version from API (same for all files in the bundle)
			char _dta[schema_version] "`bundle_schema'"

			if ("`ft'" != "manifest") {
				cap noisily _al_validate_schema, type("`file_type_label'")
				if (_rc != 0) {
					local _dl_rc = _rc
				}
			}

			if (`_dl_rc' == 0 & "`out_dta'" != "") {
				save "`out_dta'", replace
			}
		}
		restore
		if (`_dl_rc' != 0) {
			exit `_dl_rc'
		}

		* Store metadata in datasets.csv ONLY when this run came from the API.
		* Pre-staged bundles (states A/B) leave the cache index alone; the user
		* told us where the files are, not what release line they're tracking.
		if (`from_api') {
			_al_utils store_dataset_metadata ///
				"`autolabel_dir'" "`domain'" "`file_type_label'" "`lang'" ///
				"`actual_version'" "`bundle_schema'" "`out_dta'"
		}
	}

	* Cleanup: remove extracted folder and zip the cascade brought in. Pre-
	* staged extract folders (state A) leave nothing to clean; pre-staged
	* zips (state B) and freshly downloaded zips (state C) get erased.
	cap _rs_utils del_folder_rec "`extract_folder'"
	if ("`cleanup_zip'" != "") cap erase "`cleanup_zip'"

	if (`from_api') {
		di as text "  Download complete."
	}
	else {
		di as text "  Bundle ready."
	}
	return scalar downloaded = `from_api'
	return local version "`actual_version'"
end


* -----------------------------------------------------------------------------
* append_csv: Append multiple CSV files into one
* -----------------------------------------------------------------------------
program define _al_append
	args folder output_file

	// List all CSV files in the directory
	local csv_files : dir "`folder'" files "*.csv"

	// For zero-padded files like _0000.csv, _0001.csv, etc.
	// Lexicographic sorting works correctly, so just sort the file list
	local sorted_files : list sort csv_files

	// Initialize a list to store tempfiles for each CSV file
	local tempfiles_list

	// Loop through each file, import it, and save it as a tempfile
	local num_files : word count `sorted_files'
	forval i = 1/`num_files' {
		// Create a new tempfile for each CSV file
		tempfile temp`i'
		local tempfiles_list "`tempfiles_list' `temp`i''"

		local this_file : word `i' of `sorted_files'

		quietly {
			// Import the CSV file (try semicolon delimiter first, then comma)
			cap import delimited using "`folder'/`this_file'", clear encoding("utf-8") bindquote(strict) maxquotedrows(unlimited) delimiter(";")
			if _rc != 0 {
				import delimited using "`folder'/`this_file'", clear encoding("utf-8") bindquote(strict) maxquotedrows(unlimited)
			}

			// Save the imported data to the tempfile
			save `temp`i'', replace
		}

	}

	// Clear memory before starting the append process
	quietly {
		clear

		// Use the first tempfile
		local first_tempfile : word 1 of `tempfiles_list'
		use `first_tempfile', clear

		// Loop through the remaining tempfiles and append them
		forval i = 2/`num_files' {
			local next_tempfile : word `i' of `tempfiles_list'
			append using `next_tempfile'
		}

		// Save the final appended result. `quote` forces every field to be
		// double-quoted: Stata's default conditional quoting only quotes
		// fields containing the delimiter, which is insufficient for fields
		// with embedded newlines or quote chars; the next import cannot then
		// reconstruct row boundaries and rows split/merge silently. Force
		// quoting makes the round-trip lossless.
		export delimited using "`output_file'", replace quote
	}
end

* -----------------------------------------------------------------------------
* summarize_dataset: Create summary statistics of dataset variables
* -----------------------------------------------------------------------------
program define _al_summarize, rclass
	syntax [, Savefile(string)]

	* Check if a file path is provided for using
	if ("`using'" == "") {
		// display "No dataset provided. Using dataset in memory."
	}
	else {
		* Load the dataset if a file path is provided
		use `"`using'"', clear
	}

	* Create a temporary file to store results
	tempname memhold
	tempfile results
	cap postutil clear
	postfile `memhold' str32 variable str10 type str80 categories min max mean byte is_integer using `results'

	* Loop through all variables
	quietly ds
	foreach var in `r(varlist)' {
		* Determine if the variable is numeric or categorical
		local type "`:type `var''"

		if inlist("`type'", "long", "int", "float", "double", "byte") {
			* Numeric operations
			quietly summarize `var'
			local min = r(min)
			local max = r(max)
			local mean = r(mean)

			* Check if the variable is an integer
			gen double temp_var = round(`var')
			gen is_int = (`var' == temp_var)
			egen is_integer_temp = min(is_int)
			local is_integer = is_integer_temp[1]
			drop temp_var is_int is_integer_temp

			post `memhold' ("`var'") ("`type'") ("") (`min') (`max') (`mean') (`is_integer')

		}
		else if strpos("`type'", "str") {
			* String operations
			quietly levelsof `var', local(levels)
			local values = ""
			local count = 1
			foreach level of local levels {
				local values = "`values' `level'"
				local ++count
				if `count' > 10 {
					break
				}
			}

			post `memhold' ("`var'") ("`type'") ("`values'") (.) (.) (.) (.)

		}
		else {
			di as error "_al_summarize: cannot summarize variable `var' with type `type' (expected numeric or string)."
			exit 198
		}
	}

	* Close post file, which creates the dataset results
	postclose `memhold'

	* Load the results into memory
	use `results', clear

	* Export results to Excel
	if "`savefile'" != "" {
		export excel using "`savefile'", replace firstrow(var)
	}
	else {
		// display "No save file provided. Results are in memory."
	}

end

* -----------------------------------------------------------------------------
* fetch_with_errors: Download dataset with version resolution and error handling
* Resolves "latest" to actual version (e.g., "20260407") via info endpoint,
* then downloads the versioned file; never stores "latest" as the version.
* All API calls use native Stata `copy` (no shell, cross-platform).
* Returns r(status) = 0 on success, 1 on error
* Returns r(version) = resolved version (e.g., "20260407")
* Returns r(schema) = schema version (e.g., "2.0")
* -----------------------------------------------------------------------------
program define _al_fetch, rclass
	args api_url zip_dest domain type lang version

	local actual_version "`version'"
	local schema_version "2.0"

	* Resolve "latest" to actual dated version via info endpoint
	if ("`version'" == "latest") {
		_rs_utils get_api_host
		local api_host "`r(host)'"
		local info_url "`api_host'/api/v1/datasets/`domain'/`type'/`lang'/latest/info?format=stata&schema_max=2.0"

		tempfile info_response
		cap copy "`info_url'" "`info_response'", replace

		if (_rc == 0) {
			tempname fh
			cap file open `fh' using "`info_response'", read text
			if (_rc == 0) {
				file read `fh' line
				while (r(eof) == 0) {
					if (regexm("`line'", "^version=(.+)$")) {
						local actual_version = trim(regexs(1))
					}
					else if (regexm("`line'", "^schema=(.+)$")) {
						local schema_version = trim(regexs(1))
					}
					file read `fh' line
				}
				file close `fh'
			}
		}

		* Use resolved versioned URL instead of /latest
		if ("`actual_version'" != "latest" & "`actual_version'" != "") {
			local api_url = subinstr("`api_url'", "/latest", "/`actual_version'", 1)
		}
	}

	* Download the dataset (native Stata, cross-platform)
	cap copy "`api_url'" "`zip_dest'", replace
	local download_rc = _rc

	if (`download_rc' == 0 & fileexists("`zip_dest'")) {
		return scalar status = 0
		return local version "`actual_version'"
		return local schema "`schema_version'"
		exit 0
	}

	* Download failed
	di as error ""
	di as error "{hline 60}"
	di as error "Download Failed"
	di as error "{hline 60}"
	di as error "  Domain:   {result:`domain'}"
	di as error "  Type:     {result:`type'}"
	di as error "  Language: {result:`lang'}"
	di as error "  Version:  {result:`actual_version'}"
	di as error "  URL:      {result:`api_url'}"
	di as error ""

	if (`download_rc' == 601 | `download_rc' == 630 | `download_rc' == 631) {
		di as error "Dataset not found or server error."
		di as error "Check that the domain, type, and language are correct."
	}
	else if (`download_rc' == 677 | `download_rc' == 2) {
		di as error "Network error. Check your internet connection."
		di as error "If using offline mode, place files in ~/.registream/autolabel/"
	}
	else {
		di as error "Unexpected error (code: `download_rc')"
	}

	di as error "{hline 60}"
	di as error ""

	return scalar status = 1
	return local version ""
	return local schema ""
end

* -----------------------------------------------------------------------------
* store_dataset_metadata: Delegate to core _rs_metadata
* -----------------------------------------------------------------------------
program define _al_store_meta
	args autolabel_dir domain type lang ds_version ds_schema dta_file
	_rs_metadata store "`autolabel_dir'" "`domain'" "`type'" "`lang'" "`ds_version'" "`ds_schema'" "`dta_file'"
end

* -----------------------------------------------------------------------------
* get_dataset_version: Retrieve stored version info for a dataset from CSV
* Returns r(has_version)=1 if found, r(version), r(schema), r(downloaded), r(file_size), r(last_checked)
* -----------------------------------------------------------------------------
program define _al_get_ver, rclass
	args autolabel_dir domain type lang

	* Delegate to core _rs_metadata
	_rs_metadata get_version "`autolabel_dir'" "`domain'" "`type'" "`lang'"

	return scalar has_version = r(has_version)
	return local version "`r(version)'"
	return local schema "`r(schema)'"
	return local downloaded "`r(downloaded)'"
	return local source "`r(source)'"
	return local file_size "`r(file_size_dta)'"
	return local file_size_csv "`r(file_size_csv)'"
	return local last_checked "`r(last_checked)'"
end

* -----------------------------------------------------------------------------
* check_for_updates: Check API for dataset updates (internet required)
* If dataset not in datasets.csv but exists locally → prompt to re-download
* If dataset in datasets.csv → check for newer version and inform user
* Implements 24-hour caching using last_checked timestamp
* -----------------------------------------------------------------------------
program define _al_check_updates, rclass
	args autolabel_dir domain type lang dta_file

	* Get registream_dir from autolabel_dir (remove /autolabel suffix)
	local registream_dir = substr("`autolabel_dir'", 1, length("`autolabel_dir'") - 10)

	* Check if we have internet access (via config)
	_rs_config get "`registream_dir'" "internet_access"
	local has_internet = r(value)
	local config_found = r(found)

	* Default to enabled if config doesn't exist or value not found
	if (`config_found' == 0 | "`has_internet'" == "") {
		local has_internet "true"
	}

	if ("`has_internet'" != "true" & "`has_internet'" != "1") {
		* No internet, skip check
		return scalar checked = 0
		return local status "no_internet"
		exit 0
	}

	* Get local version info from datasets.csv (single call; used for caching + comparison)
	_al_utils get_dataset_version "`autolabel_dir'" "`domain'" "`type'" "`lang'"
	local has_version = r(has_version)
	local local_version = r(version)
	local last_checked = r(last_checked)

	* Check 24-hour cache based on last_checked timestamp
	if (`has_version' == 1 & "`last_checked'" != "" & "`last_checked'" != ".") {
		local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")
		local time_diff_ms = `current_clock' - `last_checked'

		if (`time_diff_ms' < 86400000) {
			return scalar checked = 0
			return local status "cached"
			exit 0
		}
	}

	* Check if DTA file exists locally
	cap confirm file "`dta_file'"
	if (_rc != 0) {
		return scalar checked = 0
		return local status "file_not_found"
		exit 0
	}

	* Get API host
	_rs_utils get_api_host
	local api_host "`r(host)'"

	* Construct info endpoint to get latest version with Stata format
	local info_url "`api_host'/api/v1/datasets/`domain'/`type'/`lang'/latest/info?format=stata&schema_max=2.0"

	* Try to get version from API (native Stata copy - Windows compatible, no shell commands)
	tempfile response
	cap copy "`info_url'" "`response'", replace
	local copy_rc = _rc

	* Check if API call succeeded
	if (`copy_rc' != 0) {
		* API unreachable or dataset not on API
		return scalar checked = 1
		return local status "api_error"
		exit 0
	}

	* Parse Stata format response (key=value pairs, one per line)
	local api_version = ""
	local api_schema = "2.0"
	tempname fh
	cap file open `fh' using "`response'", read text
	if (_rc == 0) {
		file read `fh' line
		while (r(eof) == 0) {
			if (regexm("`line'", "^version=(.+)$")) {
				local api_version = trim(regexs(1))
			}
			else if (regexm("`line'", "^schema=(.+)$")) {
				local api_schema = trim(regexs(1))
			}
			file read `fh' line
		}
		file close `fh'
	}

	* Case 1: Dataset NOT in datasets.csv but exists locally
	if (`has_version' == 0) {
		if ("`api_version'" != "") {
			* Dataset exists on API - create metadata entry automatically
			di as text ""
			di as result "{hline 60}"
			di as text "Dataset Available on RegiStream"
			di as result "{hline 60}"
			di as text "Dataset: {result:`domain'_`type'_`lang'}"
			di as text "Local:   No version tracking"
			di as text "API:     Version {result:`api_version'} available"
			di as text ""
			di as text "Creating datasets.csv entry with API version info..."
			di as result "{hline 60}"
			di as text ""

			* Get DTA file path to compute file size (DTA is the cross-client artifact)
			local file_type = cond("`type'" == "values", "value_labels", "`type'")
			local dta_file "`autolabel_dir'/`domain'_`file_type'_`lang'.dta"

			* Store metadata with API version and schema
			_al_utils store_dataset_metadata "`autolabel_dir'" "`domain'" "`type'" "`lang'" "`api_version'" "`api_schema'" "`dta_file'"

			* Update last_checked since we just checked
			_al_utils update_last_checked "`autolabel_dir'" "`domain'" "`type'" "`lang'"

			return scalar checked = 1
			return local status "not_tracked_api_available"
			return local api_version "`api_version'"
		}
		else {
			* Not on API either - create entry with unknown version (user-created)
			local file_type = cond("`type'" == "values", "value_labels", "`type'")
			local dta_file "`autolabel_dir'/`domain'_`file_type'_`lang'.dta"
			_al_utils store_dataset_metadata "`autolabel_dir'" "`domain'" "`type'" "`lang'" "unknown" "unknown" "`dta_file'"

			return scalar checked = 1
			return local status "not_tracked_not_on_api"
		}
		exit 0
	}

	* Update last_checked timestamp since we checked the API
	_al_utils update_last_checked "`autolabel_dir'" "`domain'" "`type'" "`lang'"

	* Case 2: Dataset IS in datasets.csv - check for updates
	if ("`api_version'" != "" & "`api_version'" != "`local_version'") {
		* Newer version available - return info without displaying
		return scalar checked = 1
		return local status "update_available"
		return local dataset_key "`domain'_`type'_`lang'"
		return local local_version "`local_version'"
		return local api_version "`api_version'"
	}
	else {
		* Up to date or same version
		return scalar checked = 1
		return local status "up_to_date"
		return local local_version "`local_version'"
	}
end

* -----------------------------------------------------------------------------
* update_last_checked: Update last_checked timestamp in datasets.csv
* -----------------------------------------------------------------------------
program define _al_update_checked
	args autolabel_dir domain type lang

	* Create dataset key
	local file_type = cond("`type'" == "values", "value_labels", "`type'")
	local dataset_key "`domain'_`file_type'_`lang'"

	* Get current timestamp (numeric clock value for easy comparison)
	local timestamp = clock("`c(current_date)' `c(current_time)'", "DMY hms")

	* CSV file location
	local meta_csv "`autolabel_dir'/datasets.csv"

	* Check if CSV exists
	cap confirm file "`meta_csv'"
	if (_rc != 0) {
		* No metadata file, nothing to update
		exit 0
	}

	* Update last_checked field
	quietly {
		preserve
		cap import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		if (_rc == 0) {
			* Ensure last_checked column exists (for backwards compatibility)
			cap confirm variable last_checked
			if (_rc != 0) {
				gen last_checked = ""
			}

			* Update timestamp for this dataset
			replace last_checked = "`timestamp'" if dataset_key == "`dataset_key'"
			export delimited using "`meta_csv'", replace delimiter(";")
		}
		restore
	}
end

* -----------------------------------------------------------------------------
* show_updates: Display dataset update notifications
* -----------------------------------------------------------------------------
program define _al_show_updates
	args var_status var_key var_current var_latest val_status val_key val_current val_latest

	local has_updates = 0
	if ("`var_status'" == "update_available") local has_updates = 1
	if ("`val_status'" == "update_available") local has_updates = 1

	if (`has_updates' == 1) {
		di as text ""
		di as result "Dataset Updates Available"
		di as text _dup(70)("-")

		if ("`var_status'" == "update_available") {
			di as text "• `var_key': {result:`var_current'} → {result:`var_latest'}"
		}
		if ("`val_status'" == "update_available") {
			di as text "• `val_key': {result:`val_current'} → {result:`val_latest'}"
		}

		di as text ""
		di as text "To update: {stata autolabel update datasets:autolabel update datasets}"
		di as text _dup(70)("-")
		di as text ""
	}
end

* =============================================================================
* Dataset management functions (moved from _rs_updates.ado)
* These are autolabel-specific and don't belong in core
* =============================================================================

* -----------------------------------------------------------------------------
* update_datasets_interactive: refresh every cached (domain, lang) bundle
*
* For v3.0.0 schema-2.0-only world, "update datasets" is just "force-redownload
* every cached bundle". Distinct (domain, lang) pairs are pulled from
* datasets.csv; for each, _al_utils download_bundle runs with `force` so the
* 3-state cascade falls through to state C (API download), refreshes the
* bundle in place, and re-indexes datasets.csv.
*
* The previous implementation made a bulk /api/v1/datasets/check_updates call
* with per-type version tuples and ran v1 _al_download per file_type per
* domain. That whole apparatus is retired with v1 schema support.
*
* Args: registream_dir, domain(optional filter), lang(optional filter),
*       version(optional, currently unused in v3)
* -----------------------------------------------------------------------------
program define _al_update_datasets_interactive, rclass
	syntax anything [, DOMAIN(string) LANG(string) VERSION(string)]
	local registream_dir `anything'
	local autolabel_dir "`registream_dir'/autolabel"

	* Internet-access gate
	_rs_config get "`registream_dir'" "internet_access"
	if (r(found) == 1 & "`r(value)'" == "false") {
		di as text "Update disabled (offline mode)."
		di as text "To enable: registream config, internet_access(true)"
		return scalar updates_downloaded = 0
		return local reason "internet_disabled"
		exit 0
	}

	* Load datasets.csv to discover what bundles are cached
	local meta_csv "`autolabel_dir'/datasets.csv"
	preserve
	cap qui import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
	if (_rc != 0 | _N == 0) {
		restore
		di as text "No datasets cached. Download a bundle first:"
		di as text "  autolabel scope, domain(scb) lang(eng)"
		return scalar updates_downloaded = 0
		return local reason "no_datasets"
		exit 0
	}

	* Optional filters
	if ("`domain'" != "") qui keep if domain == "`domain'"
	if ("`lang'" != "")   qui keep if lang   == "`lang'"
	if (_N == 0) {
		restore
		di as text "No datasets match the specified filters."
		return scalar updates_downloaded = 0
		return local reason "no_matching_datasets"
		exit 0
	}

	* Distinct (domain, lang) pairs — bundles refresh per (domain, lang)
	quietly {
		bysort domain lang : keep if _n == 1
		sort domain lang
	}
	local n = _N
	forval i = 1/`n' {
		local _dom_`i' = domain[`i']
		local _lang_`i' = lang[`i']
	}
	restore

	* Show what will refresh + prompt
	di as text ""
	di as text "Refreshing `n' bundle(s):"
	di as text "{hline 60}"
	forval i = 1/`n' {
		di as text "  `_dom_`i''/`_lang_`i''"
	}
	di as text "{hline 60}"

	if ("$REGISTREAM_AUTO_APPROVE" == "yes") {
		local user_input "yes"
		di as text "Auto-approved (REGISTREAM_AUTO_APPROVE=yes)."
	}
	else {
		di as input "Continue? (yes/no): " _request(rsinput)
		local user_input = trim(lower("$rsinput"))
		global rsinput ""
	}

	if !inlist("`user_input'", "yes", "y") {
		di as text ""
		di as text "Update cancelled."
		return scalar updates_downloaded = 0
		return local reason "cancelled"
		exit 0
	}

	* Iterate distinct bundles, force-redownload each via the bundled path.
	* _al_download_bundle with `force' falls through to ensure_bundle's state C
	* (resolve /info, download, unzip, process, update datasets.csv).
	local updated = 0
	forval i = 1/`n' {
		di as text ""
		di as result "[`i'/`n'] Refreshing `_dom_`i''/`_lang_`i''..."
		cap noisily _al_utils download_bundle, ///
			domain("`_dom_`i''") lang("`_lang_`i''") ///
			registream_dir("`registream_dir'") ///
			autolabel_dir("`autolabel_dir'") ///
			force
		if (_rc == 0) {
			local updated = `updated' + 1
		}
		else {
			di as error "  Refresh failed (rc=`=_rc')"
		}
	}

	di as text ""
	di as result "Refresh complete: `updated'/`n' bundle(s) updated."
	return scalar updates_downloaded = `updated'
	return local reason "success"
end



* =============================================================================
* RegiStream Schema Validator (autolabel schema v2)
* Validates that loaded DTA file matches the expected schema.
*
* Supports:
* Schema 2.0 final only (scope_id/scope_level_N, release_set_id).
*
* Usage: _al_validate_schema, type(variables|values|scope|release_sets|manifest)
* =============================================================================

program define _al_validate_schema
	version 16.0
	syntax , type(string)

	if inlist("`type'", "variables", "values") {
		cap local schema_ver : char _dta[schema_version]
		if (_rc == 0 & "`schema_ver'" != "") {
			if "`schema_ver'" != "2.0" {
				di as error ""
				di as error "Schema version mismatch detected!"
				di as error "  Found: Schema `schema_ver'"
				di as error "  Required: Schema 2.0"
				di as error ""
				di as error "Your cached metadata needs updating."
				di as error "Solution: autolabel update datasets"
				di as error ""
				exit 198
			}
		}
		else {
			di as error ""
			di as error "No schema version found in cached metadata."
			di as error "autolabel requires Schema 2.0."
			di as error ""
			di as error "Solution: autolabel update datasets, force"
			di as error ""
			exit 198
		}
	}

	if ("`type'" == "variables") {
		local required_cols "variable_name variable_label variable_type value_label_id"

		foreach col of local required_cols {
			cap confirm variable `col'
			if (_rc != 0) {
				di as error "Schema validation failed: Required column '`col'' not found!"
				di as error "  File type: Variables | Schema: `schema_ver'"
				exit 198
			}
		}

		cap confirm variable release_set_id
		if (_rc != 0) {
			di as error "Metadata format is outdated or incomplete."
			di as error "  Solution: autolabel update datasets, force"
			exit 198
		}

		cap confirm variable variable_type
		if (_rc == 0) {
			quietly {
				cap count if !inlist(variable_type, "categorical", "continuous", "text", "date", "identifier", "binary", "")
				if (_rc == 0) {
					local bad_types = r(N)
				}
				else {
					local bad_types = 0
				}
			}
			if (`bad_types' > 0) {
				di as text "Warning: Found `bad_types' rows with non-standard variable_type values"
			}
		}

		quietly count if missing(variable_name) | variable_name == ""
		if (r(N) > 0) {
			di as text "  Warning: Dropped `r(N)' rows with empty variable_name"
			quietly drop if missing(variable_name) | variable_name == ""
		}
	}
	else if ("`type'" == "values") {
		local required_cols "value_label_id variable_name value_labels_stata"

		foreach col of local required_cols {
			cap confirm variable `col'
			if (_rc != 0) {
				di as error "Schema validation failed: Required column '`col'' not found!"
				di as error "  File type: Value Labels"
				exit 198
			}
		}

		quietly count if missing(value_label_id)
		if (r(N) > 0) {
			di as error "Data validation failed: Found `r(N)' rows with empty value_label_id!"
			exit 198
		}
	}
	else if ("`type'" == "scope") {
		cap confirm variable scope_id
		if (_rc != 0) {
			di as error "Metadata format is outdated or incomplete."
			di as error "  Solution: autolabel update datasets, force"
			exit 198
		}
		cap confirm variable scope_level_1
		if (_rc != 0) {
			di as error "Schema validation: scope file missing 'scope_level_1' column!"
			exit 198
		}
		cap confirm variable release
		if (_rc != 0) {
			di as error "Schema validation: scope file missing 'release' column!"
			exit 198
		}
	}
	else if ("`type'" == "release_sets") {
		cap confirm variable release_set_id
		if (_rc != 0) {
			di as error "Metadata format is outdated or incomplete."
			di as error "  Solution: autolabel update datasets, force"
			exit 198
		}
		cap confirm variable scope_id
		if (_rc != 0) {
			di as error "Metadata format is outdated or incomplete."
			di as error "  Solution: autolabel update datasets, force"
			exit 198
		}
	}
	else if ("`type'" == "manifest") {
		* Manifest is key-value, validated by _al_load_manifest, not here
	}
	else {
		di as error "Invalid validation type: `type'"
		di as error "Must be 'variables', 'values', 'scope', 'release_sets', or 'manifest'"
		exit 198
	}

	* If we got here, validation passed (silent; errors only)
end
