*! version {{VERSION}} {{DATE}}
program define autolabel
    version 16.0

	* Core check: registream must be installed. Each package ships its own
	* files only; modules depend on core being present on adopath. See
	* registream-docs/architecture/version_coordination.md.
	cap findfile _rs_utils.ado
	if _rc != 0 {
		di as error ""
		di as error "registream core is not installed."
		di as error ""
		di as error "autolabel requires the registream core package. Install it first:"
		di as error `"  ssc install registream"'
		di as error "  (or from GitHub:)"
		di as error `"  net install registream, from("https://registream.org/install/stata/registream/latest") replace"'
		di as error ""
		exit 198
	}

	* Get core version (can be overridden by stata/dev/version_override.do).
	_rs_utils get_version
	local REGISTREAM_VERSION "`r(version)'"
	local pkg_version "`r(version)'"
    local release_date "{{DATE}}"

	* Min-core version check (Phase 4 of version_coordination.md). MIN_CORE
	* is build-injected from packages.json; in source mode it stays as the
	* literal placeholder, which the regex guard treats as "skip". Routed
	* through the _rs_utils dispatcher because Stata's autoloader registers
	* only the filename-matched program — nested programs in _rs_utils.ado
	* aren't directly callable from outside.
	local AUTOLABEL_MIN_CORE "{{MIN_CORE}}"
	if (regexm("`AUTOLABEL_MIN_CORE'", "^[0-9]")) {
		_rs_utils check_core_version "autolabel" "`AUTOLABEL_MIN_CORE'"
	}

	* Autolabel module version (stamped from packages.json by export_package.py)
	local AUTOLABEL_VERSION "{{VERSION}}"

	* ==========================================================================
	* MASTER WRAPPER (START): Usage tracking + Background update check
	* Runs for ALL autolabel commands
	* ==========================================================================
	_autolabel_wrapper_start "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" `"`0'"'
	local registream_dir "`r(registream_dir)'"

    * Parse first argument to determine command type.
    * parse(" ,") is required so that `autolabel scope, domain(scb)` splits
    * into first_arg="scope", rest=", domain(scb)" instead of attaching
    * the comma to first_arg and making the dispatch checks below miss.
    gettoken first_arg rest : 0, parse(" ,")

	* ==========================================================================
	* ALIASES: Convenience commands that delegate to registream
	* ==========================================================================

	if ("`first_arg'" == "info") {
		_autolabel_info `rest'
		_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
		exit 0
	}
	else if ("`first_arg'" == "update") {
		_autolabel_update `rest'
		_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
		exit 0
	}
	else if ("`first_arg'" == "version") {
		_autolabel_version `rest'
		_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
		exit 0
	}
	else if ("`first_arg'" == "cite") {
		_autolabel_cite "`AUTOLABEL_VERSION'" `rest'
		_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
		exit 0
	}
	else if ("`first_arg'" == "scope") {
		_autolabel_scope "`registream_dir'" `rest'
		_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
		exit 0
	}
	else if ("`first_arg'" == "suggest") {
		_autolabel_suggest `rest'
		_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
		exit 0
	}

	* Otherwise, expect standard syntax (variables/values/lookup)
    * First argument is a required string (either 'variables' or 'values')
    * Followed by an optional varlist, and options: domain, exclude, lang
    syntax anything(name=arguments) , DOMAIN(string) LANG(string) [ EXCLUDE(varlist) SUFFIX(string) DRYRUN SAVEDO(string) SCOPE(string asis) RELEASE(string) DETAIL LIST]

	* Note: scope() tokenization happens inside the helpers that actually
	* need the parsed levels (_al_filter_scope, _al_collapse_metadata,
	* _autolabel_scope). The outer `scope' string is passed through
	* unchanged via compound quotes.

	* Normalize domain and lang to lowercase immediately (case-insensitive)
	local domain = lower("`domain'")
	local lang = lower("`lang'")

	* -----  PARSE THE LABEL_TYPE AND VARLIST ---------


	* Extract the first word from namelist (should be 'variables', 'values', or 'lookup')
    local label_type : word 1 of `arguments'
	local varlist : subinstr local arguments "`label_type'" "", all


    if !inlist("`label_type'", "variables", "values", "lookup") {
        di as error "Invalid first argument `label_type'. Please specify either 'variables', 'values' or 'lookup."
        exit 1
    }



	* Valid variable expression checks for variables and values, not lookup

	if inlist("`label_type'", "variables", "values") {
		
		* Handle case where no varlist is provided (select all variables)
		if "`varlist'" == "" {
			unab varlist : _all  // expand all variables in the dataset
		} 
		else {

			local expanded_all ""
			local error_flag 0

			foreach var of local varlist {
				cap qui ds `var'
				if (_rc == 0) {
					local expanded_all `expanded_all' `r(varlist)'
				}
				else {
					di as error "`var' is not a valid variable in the dataset."
					local error_flag 1
				}
			}

			if `error_flag' == 1 {
				exit 198
			}

			* Token-wise dedupe. `strpos` on a flat string false-positives
			* when a name is a substring of another (e.g. `id` in `pid`).
			local varlist : list uniq expanded_all

		}
		
		
		* -----  HANDLE EXCLUSION OF VARIABLES ---------
		
		if "`exclude'" != "" {
			local exclude_error 0

			foreach ex_var of local exclude {
				cap qui ds `ex_var'
				if _rc != 0 {
					di as error "`ex_var' in the EXCLUDE list is not a valid variable."
					local exclude_error 1
				}
			}

			if `exclude_error' == 1 {
				exit 198
			}

			* Token-wise set difference. `strpos` on a flat string false-positives
			* when a name is a substring of another (e.g. `id` in `pid`).
			local varlist : list varlist - exclude
		}
		
	}

	* ----- DOMAIN, LANGUAGE, DATA_DIR IDENTIFICATION  ---------


    * Ensure domain is specified
    if "`domain'" == "" {
        di as error "Domain not specified. Please specify a domain (e.g., domain(scb))."
        exit 1
    }

    * Ensure language is specified
    if "`lang'" == "" {
        di as error "Language not specified. Please specify a language (e.g., lang(eng))."
        exit 1
    }
	
	* Check if we have $registream_dir override
	if "$registream_dir" != "" {

		_rs_utils confirmdir "$registream_dir"

		if (r(exists) == 0) {
			di as error "The global \$registream_dir is not a valid directory"
			di as error "Current Value: $registream_dir"
			di as error "You have two options:"
			di as error "  1) ensure that the value is a valid directory path."
			di as error "  2) unset the global, which will revert to the default registream directory locations "
			exit 1
		} 
		
		local registream_dir "$registream_dir"
		
		if substr("`registream_dir'", -1, 1) == "/" | substr("`registream_dir'", -1, 1) == "\" {
			local registream_dir = substr("`registream_dir'", 1, length("`registream_dir'") - 1)
		}
		
		local autolabel_dir "`registream_dir'/autolabel"
		
	}
	* Otherwise proceed with default registream locations
	else {
		* Use centralized OS detection from _rs_utils
		_rs_utils get_dir
		local registream_dir "`r(dir)'"
		local autolabel_dir "`registream_dir'/autolabel"
	}
	
	
	* Migrate legacy autolabel_keys → autolabel (one-time rename)
	local legacy_dir "`registream_dir'/autolabel_keys"
	cap confirm file "`legacy_dir'/."
	if (_rc == 0) {
		cap confirm file "`autolabel_dir'/."
		if (_rc != 0) {
			if "`c(os)'" == "Windows" {
				cap shell move "`legacy_dir'" "`autolabel_dir'"
			}
			else {
				cap shell mv "`legacy_dir'" "`autolabel_dir'"
			}
			if (_rc == 0) {
				di as text "Migrated metadata cache: autolabel_keys → autolabel"
			}
		}
	}

	* Confirm that the registream_dir and autolabel_dir exists
	foreach d in "`registream_dir'" "`autolabel_dir'" {

		_rs_utils confirmdir "`d'"

		if (r(exists) == 0) {
			quietly mkdir "`d'"
		}

	}
		
		
	* -----  DOWNLOAD BUNDLED METADATA (variables + value_labels + scope) ---------

	* Construct cache file paths
	local var_filepath_dta = "`autolabel_dir'/`domain'/variables_`lang'.dta"
	local val_filepath_dta = "`autolabel_dir'/`domain'/value_labels_`lang'.dta"
	local scope_filepath_dta = "`autolabel_dir'/`domain'/scope_`lang'.dta"
	local rs_filepath_dta = "`autolabel_dir'/`domain'/release_sets_`lang'.dta"
	local manifest_filepath = "`autolabel_dir'/`domain'/manifest_`lang'.csv"

	* Download bundle (skips if cached, downloads all 3 file types in one ZIP)
	_al_utils download_bundle, ///
		domain("`domain'") lang("`lang'") ///
		registream_dir("`registream_dir'") autolabel_dir("`autolabel_dir'")

	* Check for dataset updates (single check using variables entry, 24h cache)
	_al_utils check_for_updates "`autolabel_dir'" "`domain'" "variables" "`lang'" "`var_filepath_dta'"
	local var_status "`r(status)'"
	local var_key "`r(dataset_key)'"
	local var_current "`r(local_version)'"
	local var_latest "`r(api_version)'"

	* -----  END DOWNLOAD ---------

	* -----  LOAD MANIFEST FOR DISPLAY TITLES ---------
	local l1_title "Scope"
	local _main_scope_depth 1
	cap quietly _al_load_manifest, path("`manifest_filepath'")
	if (_rc == 0 & r(manifest_loaded) == 1) {
		local _main_scope_depth = r(scope_depth_n)
		forval _i = 1/`_main_scope_depth' {
			local lv_`_i'_title "`r(scope_level_`_i'_title)'"
		}
		local l1_title "`lv_1_title'"
	}

	* -----  FILTER METADATA IF NEEDED ---------

	* Filter variables metadata by scope/release.
	* Pass dataset variable names for automatic scope inference (variables/values only).
	* lookup skips inference; no scope list output needed.
	local _datavars_for_filter ""
	if "`label_type'" != "lookup" {
		quietly describe, varlist
		local _datavars_for_filter "`r(varlist)'"
	}
	tempfile _filtered_var_dta
	tempfile _uncollapsed_var_dta
	_al_collapse_metadata, dta("`var_filepath_dta'") output("`_filtered_var_dta'") ///
		uncollapsed("`_uncollapsed_var_dta'") ///
		scope(`scope') release("`release'") ///
		datavars("`_datavars_for_filter'")
	local var_merge_dta "`r(merge_dta)'"
	local var_merge_uncollapsed "`_uncollapsed_var_dta'"
	local n_ambig_meta = r(n_ambiguous)
	local pin_hints = r(pin_hints)
	local _inferred_display = r(inferred_display)
	local _inferred_compact = r(inferred_compact)
	if "`_inferred_compact'" == "" local _inferred_compact "`_inferred_display'"
	local _match_pct = r(match_pct)
	local _has_strong_primary = r(has_strong_primary)
	if "`n_ambig_meta'" == "" local n_ambig_meta 0
	if "`_has_strong_primary'" == "" local _has_strong_primary 0
	* Per-variable provenance counts are computed inside the variables/values
	* loops after the merge with the user's varlist; they can't be computed
	* at collapse time because the metadata covers the whole domain.

	* Collapse note: fires only when there was real label ambiguity (>1 distinct
	* labels for the same variable_name). Simple domains (e.g. DST with no
	* variants) stay silent; feels like v1: labels just appear.
	if "`label_type'" != "lookup" & `n_ambig_meta' > 0 {
		di as text ""
		di as text "  Using {help autolabel##rules:most common label} per variable."
		if "`pin_hints'" != "" {
			di as text "  For exact control, specify: `pin_hints'."
		}
	}

	* ----- AUTOLABEL VARIABLES ---------

    if "`label_type'" == "variables" {

		if "`dryrun'" != "" {
			di as text ""
			di as text "Generating variable labeling commands (dry run)..."
		}
		else if "`savedo'" != "" {
			di as text ""
			di as text "Generating variable labeling commands..."
		}
		else {
			di as text "  Applying variable labels..."
		}

		quietly {

		preserve
		
			keep `varlist'
			
			* reduce number of rows for improved speed (and since we do not need distribution data for labelling)
			set seed 270523
			sample 100, count

			_al_utils summarize_dataset
			gen variable_original = variable
			order variable_original, first
			replace variable = lower(variable)
			rename variable variable_name

			merge 1:1 variable_name using "`var_merge_dta'", keep(1 3) nogen

			gen var_label = variable_label
			replace var_label = variable_label + " (" + variable_unit + ")" if variable_unit != ""


			* Count provenance per USER variable (not per metadata row).
			* This runs BEFORE the loop so the caller can surface the split
			* in the success summary. After merging with var_merge_dta above,
			* each row is one user variable and _is_primary tells us whether
			* its winning metadata row came from the inferred primary scope.
			cap confirm variable _is_primary
			if (_rc == 0) {
				quietly count if _is_primary == 1 & !missing(var_label) & var_label != ""
				local _n_from_primary = r(N)
				quietly count if _is_primary == 0 & !missing(var_label) & var_label != ""
				local _n_from_fallback = r(N)
			}
			else {
				local _n_from_primary = 0
				local _n_from_fallback = 0
			}

			// Create a tempfile for the .do file
			tempfile tmpfile

			// Ensure the file handle is released in case it was previously used
			cap file close myfile

			// Open the tempfile for writing
			file open myfile using `tmpfile', write replace

			local n = _N
			local n_skipped_vars = 0
			local skipped_vars_list ""
			forval i = 1/`n' {

				// Define the variable name
				local var_name = variable_original[`i']

				// Define the variable label
				local var_label = var_label[`i']

				// Skip variables that have no metadata entry; never wipe a
				// pre-existing user label by writing it to "".
				if "`var_label'" == "" {
					local n_skipped_vars = `n_skipped_vars' + 1
					local skipped_vars_list "`skipped_vars_list' `var_name'"
					continue
				}

				// Write the label command to the file
				if "`suffix'" == "" {
					file write myfile `"cap label variable `var_name' "`var_label'" "' _n
				}
				else {
					local var_name_suffix "`var_name'`suffix'"
					file write myfile `"cap gen `var_name_suffix' = `var_name'"' _n
					file write myfile `"cap label variable `var_name_suffix' "`var_label'" "' _n
				}

			}

			local n_labeled_vars = `n' - `n_skipped_vars'

			// Close the file
			file close myfile

		restore

		* Execute, save, or display the generated do-file
		if "`dryrun'" == "" & "`savedo'" == "" {
			do `tmpfile'
		}
		else if "`savedo'" != "" {
			copy `tmpfile' "`savedo'", replace
		}
		}

		if "`dryrun'" != "" {
			di as text ""
			di as result "Generated variable labeling commands (dry run; no labels applied):"
			di as text "{hline 70}"
			type `tmpfile'
			di as text "{hline 70}"
			di as text ""
		}
		else if "`savedo'" != "" {
			di as text ""
			di as result "Variable labeling commands saved to: `savedo'"
			di as text `"  Review with: {stata type "`savedo'"}"'
			di as text `"  Apply with:  {stata do "`savedo'"}"'
			di as text ""
		}
		else {
			di as result "  ✓ `n_labeled_vars'/`n' variable labels applied"

			* Provenance breakdown: only in automatic mode (no scope pin).
			if `"`scope'"' == "" & "`_inferred_display'" != "" & `n_labeled_vars' > 0 {
				if `_has_strong_primary' & `_n_from_primary' > 0 {
					di as text "    `_n_from_primary' from {result:`_inferred_compact'} (primary)"
				}
				if `_n_from_fallback' > 0 {
					local _fallback_word = lower("`l1_title'") + "s"
					di as text "    `_n_from_fallback' from other `_fallback_word' ({help autolabel##rules:majority fallback})"
				}
			}

			if `n_skipped_vars' > 0 {
				* Inline skipped list: comma-separated, truncated
				local _skipped_inline ""
				local _shown 0
				foreach _v of local skipped_vars_list {
					if `_shown' >= 4 continue, break
					if `_shown' == 0 local _skipped_inline "`_v'"
					else local _skipped_inline "`_skipped_inline', `_v'"
					local _shown = `_shown' + 1
				}
				if `n_skipped_vars' > 4 {
					local _skipped_inline "`_skipped_inline', +`=`n_skipped_vars' - 4' more"
				}
				di as text "    `n_skipped_vars' skipped, not in {result:`domain'} metadata: {it:`_skipped_inline'}"
			}
			di as text ""
		}

		* Display update message if available (AFTER applying labels)
		_al_utils show_updates "`var_status'" "`var_key'" "`var_current'" "`var_latest'" "" "" "" ""

    }

	* ----- AUTOLABEL VALUE LABELS ---------

	else if "`label_type'" == "values" {

		* Value labels DTA path (already downloaded with the bundle above)
		local val_filepath_dta = "`autolabel_dir'/`domain'/value_labels_`lang'.dta"
		


        di as text "  Applying value labels..."

		quietly {

		preserve

			keep `varlist'
			
			* reduce number of rows for improved speed (and since we do not need distribution data for labelling)
			set seed 270523
			sample 100, count
			
			_al_utils summarize_dataset
			gen variable_original = variable
			order variable_original, first
			replace variable = lower(variable)
			rename variable variable_name

			merge 1:1 variable_name using "`var_merge_dta'", keep(1 3) nogen
			merge m:1 value_label_id using "`val_filepath_dta'", keep(1 3) nogen

			* Count provenance per USER variable after merge (automatic mode)
			cap confirm variable _is_primary
			if (_rc == 0) {
				quietly count if _is_primary == 1 & !missing(value_labels_stata) & value_labels_stata != ""
				local _n_from_primary = r(N)
				quietly count if _is_primary == 0 & !missing(value_labels_stata) & value_labels_stata != ""
				local _n_from_fallback = r(N)
			}
			else {
				local _n_from_primary = 0
				local _n_from_fallback = 0
			}


			// Create a tempfile for the .do file
			tempfile tmpfile

			// Ensure the file handle is released in case it was previously used
			cap file close myfile

			// Open the tempfile for writing
			file open myfile using `tmpfile', write replace

			local n = _N
			local n_cat = 0
			local n_val_labeled = 0
			local n_val_skipped = 0
			local val_skipped_list ""
			forval i = 1/`n' {

				// Define the variable name
				local var_name = variable_original[`i']

				* ---- APPLY VALUE LABELS
				* Handle both string and numeric categorical variables
				if (variable_type[`i'] == "categorical") {

				local n_cat = `n_cat' + 1
				local is_string = (substr(type[`i'], 1, 3) == "str")

				// Determine the total number of words
				local str_value = value_labels_stata[`i']

				// Count the number of words in the string
				local nwords : word count `str_value'

				if `nwords' == 0 {
					// Categorical in metadata but no value labels bundled
					// (e.g., SCB classifications without a code-table; astsni2002)
					local n_val_skipped = `n_val_skipped' + 1
					local val_skipped_list "`val_skipped_list' `var_name'"
					continue
				}

				local n_val_labeled = `n_val_labeled' + 1
				if `nwords' > 0 {

				* --- APPLY SUFFIX PASSED IN OPTION
				if "`suffix'" == "" {
					// no change
				}
				else {
					local var_name_suffix "`var_name'`suffix'"
					file write myfile `"cap gen `var_name_suffix' = `var_name'"' _n
					local var_name "`var_name_suffix'"
				}
				* ---------------------------------


				local enc_suffix "β"

				* STRING CATEGORICAL: Use encode (creates sequential codes from strings)
				if (`is_string') {
					local enc_var_name "`var_name'`enc_suffix'"
					file write myfile `"cap drop `enc_var_name' "' _n
					file write myfile `"encode `var_name', gen(`enc_var_name') "' _n

					file write myfile `"local labelname : value label `enc_var_name' "' _n
					file write myfile `"levelsof `enc_var_name' , local(levels) "' _n

					* Store the new labels in locals
					forval k = 1(2)`nwords' {
						local j = `k'+1
						local code : word `k' of `str_value'
						local lbl : word `j' of `str_value'
						_rs_utils escape_ascii "`code'"
						local clean_code "`r(escaped_string)'"

						file write myfile `"local nl_`clean_code' "`lbl'" "' _n
					}

					* Replace labels with our metadata labels
					file write myfile "foreach l of local levels {" _n
					file write myfile "    local val : label " _char(96) "labelname" _char(39) " " _char(96) "l" _char(39) _n

					file write myfile " _rs_utils escape_ascii " _char(96) "val" _char(39) _n
					file write myfile " local clean_val " _char(96) "r(escaped_string)" _char(39) _n

					file write myfile "    local nl_value " _char(34) _char(96) "nl_" _char(96) "clean_val" _char(39) _char(39) _char(34) _n
					file write myfile "    if " _char(34) _char(96) "nl_value" _char(39) _char(34) " != " _char(34) _char(34) " {" _n
					file write myfile "        label define " _char(96) "labelname" _char(39) " " _char(96) "l" _char(39) " " _char(34) _char(96) "nl_" _char(96) "clean_val" _char(39) _char(39) _char(34) ", modify" _n
					file write myfile "    }" _n
					file write myfile "}" _n

					file write myfile `"drop `var_name' "' _n
					file write myfile `"rename `enc_var_name' `var_name' "' _n
				}
				* NUMERIC CATEGORICAL: Use label define + label values (preserves original codes)
				else {
					local label_name "`var_name'`enc_suffix'"

					* Smart handling: Filter to ONLY numeric codes if metadata has mixed types
					* Example: kon metadata has "K" "Woman" "M" "Man" "1" "Man" "2" "Woman"
					* For numeric variable, we only use: "1" "Man" "2" "Woman"

					* Create label definition from value_labels_stata
					* Format: "code1" "label1" "code2" "label2" ...
					forval k = 1(2)`nwords' {
						local j = `k'+1
						local code : word `k' of `str_value'
						local lbl : word `j' of `str_value'

						* Check if this code is numeric
						cap confirm number `code'
						if _rc == 0 {
							* Numeric code - use it! (preserves original numeric codes)
							file write myfile `"label define `label_name' `code' "`lbl'", modify"' _n
						}
						* Skip string codes silently (e.g., "K", "M" for numeric variable)
					}

					* Attach the label to the variable (NO recoding!)
					file write myfile `"label values `var_name' `label_name'"' _n
				}

				}

			  }

			}

			// Close the file
			file close myfile

		restore

		* Execute, save, or display the generated do-file
		if "`dryrun'" == "" & "`savedo'" == "" {
			do `tmpfile'
		}
		else if "`savedo'" != "" {
			copy `tmpfile' "`savedo'", replace
		}
		}

		if "`dryrun'" != "" {
			di as text ""
			di as result "Generated value labeling commands (dry run; no labels applied):"
			di as text "{hline 70}"
			type `tmpfile'
			di as text "{hline 70}"
			di as text ""
		}
		else if "`savedo'" != "" {
			di as text ""
			di as result "Value labeling commands saved to: `savedo'"
			di as text `"  Review with: {stata type "`savedo'"}"'
			di as text `"  Apply with:  {stata do "`savedo'"}"'
			di as text ""
		}
		else {
			di as result "  ✓ `n_val_labeled'/`n_cat' value labels applied"

			if `n_val_skipped' > 0 {
				* Inline skipped list
				local _skipped_inline ""
				local _shown 0
				foreach _v of local val_skipped_list {
					if `_shown' >= 4 continue, break
					if `_shown' == 0 local _skipped_inline "`_v'"
					else local _skipped_inline "`_skipped_inline', `_v'"
					local _shown = `_shown' + 1
				}
				if `n_val_skipped' > 4 {
					local _skipped_inline "`_skipped_inline', +`=`n_val_skipped' - 4' more"
				}
				di as text "    `n_val_skipped' skipped, no value labels in {result:`domain'}: {it:`_skipped_inline'}"
			}
			di as text ""
		}

		* Display consolidated update message (AFTER applying labels)
		_al_utils show_updates "`var_status'" "`var_key'" "`var_current'" "`var_latest'" ///
										  "`val_status'" "`val_key'" "`val_current'" "`val_latest'"

    }

	else if "`label_type'" == "lookup" {

		* Require a varlist; browse is handled by autolabel scope
		if "`varlist'" == "" {
			di as error "Specify variables to look up, or use {bf:autolabel scope} to browse."
			di as text ""
			di as text "Examples:"
			di as text "  {cmd:autolabel lookup kon kommun, domain(`domain') lang(`lang')}"
			di as text "  {cmd:autolabel scope LISA, domain(`domain') lang(`lang')}"
			exit 198
		}

		* ── STANDARD LOOKUP: specific variables ──
		preserve

		* Files already downloaded by download_bundle above
		* File paths (var_filepath_dta, val_filepath_dta) set before branching

		* Preserve the user-typed varlist before expansion so the "Show all"
		* SMCL click target re-runs with the original pattern (e.g. `*`) rather
		* than a ~100 KB link containing every expanded variable name.
		local _orig_varlist `"`varlist'"'

		* Expand wildcard patterns (e.g. ssyk*) against metadata variable names.
		* Safe here because preserve above will restore the caller's dataset (or
		* empty state) on exit; we can freely clobber memory with the metadata.
		local _expanded_varlist ""
		foreach v of local varlist {
			if strpos("`v'", "*") > 0 | strpos("`v'", "?") > 0 {
				quietly {
					* Expand wildcards against the scope-filtered universe so
					* scope("LISA") + lookup * returns only LISA's variables.
					use "`var_merge_dta'", clear
					keep if strmatch(lower(variable_name), lower("`v'"))
					duplicates drop variable_name, force
				}
				if _N > 0 {
					forval _j = 1/`=_N' {
						local _expanded_varlist "`_expanded_varlist' `=variable_name[`_j']'"
					}
				}
				else {
					* Pattern matched nothing; keep literal for "not found" reporting
					local _expanded_varlist "`_expanded_varlist' `v'"
				}
			}
			else {
				local _expanded_varlist "`_expanded_varlist' `v'"
			}
		}
		local varlist "`_expanded_varlist'"

		quietly {

		* --- Create a dataset with the passed variables
		clear
		set obs `: word count `varlist''
		gen str50 variable_name = ""
		gen var_id = .

		local i = 1
		foreach v of local varlist {
			replace variable_name = lower("`v'") in `i'
			replace var_id = `i' in `i'
			local ++i
		}

		tempfile lookup_vars
		save `lookup_vars'

		* --- Merge with the variables dataset

		* Use the scope-filtered, majority-collapsed view so lookup respects
		* scope() / release() and never bleeds into other scopes' metadata.
		* var_merge_dta is already one row per variable with scope_level_*
		* columns merged in by _al_collapse_v2; no further joins or
		* register/variant/version filtering needed here (scope() / release()
		* were applied during the collapse itself).
		use "`var_merge_dta'", clear

		merge m:1 variable_name using `lookup_vars', keep(2 3)
		merge m:1 value_label_id using "`val_filepath_dta'", keep(1 3) nogen

		sort var_id variable_name

		* Rank labels by frequency so most common label across registers comes first
		bysort variable_name variable_label: gen _label_freq = _N
		gsort var_id variable_name -_label_freq
		drop _label_freq

		* Initialize a local to store missing variables
		local missing_vars ""

		}

		* ─────────────────────────────────────────────────────────────
		* DISPLAY RESULTS
		* ─────────────────────────────────────────────────────────────

		if "`detail'" == "" {
			* DEFAULT MODE (concise): one block per variable
			* Cap at 20 distinct vars unless `list' is passed; a single
			* variable gets full detail (no cap) regardless. For `lookup *`
			* style dumps this prevents minute-long per-variable rendering.
			quietly count if _merge == 3
			local _n_matched_rows = r(N)
			quietly bysort variable_name: gen _first_in_var = (_n == 1) if _merge == 3
			quietly count if _first_in_var == 1
			local _n_unique_vars = r(N)
			drop _first_in_var

			* ── `list' + many vars → compact 2-col index (same view as the
			*    scope-drill variable level; shared via _al_render_var_list).
			*    For a single variable, `list' still means "expand all value
			*    labels" in the detail block below. Uses a tempfile snapshot
			*    instead of `preserve' (outer block already preserved, and
			*    Stata forbids nested preserve (r(621)).
			local _compact_done = 0
			if ("`list'" != "" & `_n_unique_vars' > 1) {
				tempfile _snap
				quietly save `_snap', replace

				* Missing-var collection (rows with _merge == 2)
				quietly keep if _merge == 2
				quietly bysort variable_name: keep if _n == 1
				forval _mi = 1/`=_N' {
					local missing_vars `missing_vars' "`=variable_name[`_mi']'"
				}

				* Reload and render matched vars compactly
				quietly use `_snap', clear
				quietly keep if _merge == 3
				quietly bysort variable_name: keep if _n == 1
				quietly sort variable_name
				local _clickopts domain(`domain') lang(`lang')
				if `"`scope'"' != "" local _clickopts `_clickopts' scope(`scope')
				if "`release'" != "" local _clickopts `_clickopts' release("`release'")
				_al_render_var_list, ///
					clickcmd(autolabel lookup) ///
					clickopts(`_clickopts') ///
					cap(0) noheading

				* Restore merged view for any downstream consumers
				quietly use `_snap', clear

				local _compact_done = 1
			}

			if (!`_compact_done') {

			local _display_cap = 20
			if `_n_unique_vars' <= 1 local _display_cap = 1000000
			local _shown_vars = 0
			local _truncated = 0

			local prev_var ""
			forval i = 1/`=_N' {
				local current_merge = _merge[`i']
				local this_var = variable_name[`i']

				if `current_merge' == 2 {
					if "`this_var'" != "`prev_var'" {
						local missing_vars `missing_vars' "`this_var'"
						local prev_var "`this_var'"
					}
					continue
				}

				* Skip if same variable as previous (we already displayed it)
				if "`this_var'" == "`prev_var'" continue

				* Respect display cap
				if `_shown_vars' >= `_display_cap' {
					local _truncated = 1
					continue
				}
				local ++_shown_vars
				local prev_var "`this_var'"

				* Use pre-collapse scope + release counts
				local first_row = `i'
				local n_registers 1
				local n_releases 1
				local n_scope2 0
				cap local n_registers = _n_scope1[`first_row']
				if missing(`n_registers') local n_registers 1
				cap local n_releases = _n_releases[`first_row']
				if missing(`n_releases') local n_releases 1
				cap local n_scope2 = _n_scope2[`first_row']
				if missing(`n_scope2') local n_scope2 0

				local _vlabel = variable_label[`first_row']

				* Header: bold-colored name + italic label. Name aligned at the
				* same 2-space indent as body field names (Definition, Type, ...)
				* so everything reads as one uniform column tree.
				local _namelen = strlen("`this_var'")
				local _pad = 13 - `_namelen'
				if (`_pad' < 2) local _pad = 2
				local _padstr = substr("                    ", 1, `_pad')
				di as text ""
				di as result `"  {bf:`this_var'}"' as text `"`_padstr'{it:`_vlabel'}"'

				local _def = variable_definition[`first_row']
				if `"`_def'"' != "" {
					local _avail = c(linesize) - 15
					local _dpad "               "
					local _dnw : word count `_def'
					local _dcur ""
					local _dcurlen 0
					local _dfirst 1
					forval _dwi = 1/`_dnw' {
						local _dw : word `_dwi' of `_def'
						local _dwl = ustrlen("`_dw'")
						if `_dcurlen' == 0 {
							local _dcur "`_dw'"
							local _dcurlen = `_dwl'
						}
						else if `_dcurlen' + 1 + `_dwl' <= `_avail' {
							local _dcur "`_dcur' `_dw'"
							local _dcurlen = `_dcurlen' + 1 + `_dwl'
						}
						else {
							if `_dfirst' {
								di as text "  Definition   `_dcur'"
								local _dfirst 0
							}
							else {
								di as text "`_dpad'`_dcur'"
							}
							local _dcur "`_dw'"
							local _dcurlen = `_dwl'
						}
					}
					if `_dfirst' {
						di as text "  Definition   `_dcur'"
					}
					else {
						di as text "`_dpad'`_dcur'"
					}
				}

				local _vtype = variable_type[`first_row']
				di as text `"  Type         `_vtype'"'

				if (`n_registers' > 1 | `n_releases' > 1) & `"`scope'"' == "" {
					* Multi-scope summary: hyperlinked register count + release count.
					* Scope level terms come from the manifest (l1_title, lv_2_title).
					_al_plural `n_registers' "`l1_title'"
					local _l1_plural "`r(word)'"
					_al_plural `n_releases' "release"
					local _rel_plural "`r(word)'"

					local _det_cmd `"autolabel scope, domain(`domain') lang(`lang') var(`this_var')"'
					local _scope_line `"  Scope        {stata `_det_cmd':`n_registers' `_l1_plural'}"'

					if (`n_scope2' > 1 & `_main_scope_depth' >= 2) {
						_al_plural `n_scope2' "`lv_2_title'"
						local _l2_plural "`r(word)'"
						local _scope_line `"`_scope_line', `n_scope2' `_l2_plural'"'
					}

					local _scope_line `"`_scope_line', `n_releases' `_rel_plural'"'
					di as text `"`_scope_line'"'
				}
				else {
					* Single scope: show level-1 name (alias-first if available),
					* clickable to scope-browse with the variable pinned so the
					* user can drill variants/releases even when a variable lives
					* in only one register.
					cap confirm variable scope_level_1
					if _rc == 0 {
						local _sn = scope_level_1[`first_row']
						local _sa ""
						cap local _sa = scope_level_1_alias[`first_row']
						if ("`_sa'" != "" & "`_sa'" != ".") {
							local _disp "`_sa' ({it:`_sn'})"
						}
						else {
							local _disp "`_sn'"
						}
						local _drill_cmd `"autolabel scope, domain(`domain') lang(`lang') var(`this_var')"'
						di as text `"  Scope        {stata `_drill_cmd':`_disp'}"'
					}
				}

				* Value labels (aligned "code  label", per-entry truncated).
				* Use code_count (from value_labels merge) to decide how many
				* to show; never `word count' the full value_labels_stata since
				* huge value sets (e.g. occupation codes with 1000+ entries)
				* overflow Stata's 645K macro expansion limit.
				local _cc .
				cap local _cc = code_count[`first_row']
				local nlabels = 0
				if "`_cc'" != "" & "`_cc'" != "." local nlabels = `_cc'
				if `nlabels' > 0 {
					* With `list' we show all codes (up to 4000-char safety cap
					* on the string buffer); otherwise cap at 6 with a clickable
					* "+N more" that re-runs with list.
					local _cap = 6
					if "`list'" != "" local _cap = min(`nlabels', 2000)
					local show_labels = min(`nlabels', `_cap')

					* Truncate value_labels_stata to a safe length before word
					* extraction. Strip inner quotes/backticks that would break
					* Stata's string parser on display.
					local _maxchars = 4000
					if "`list'" != "" local _maxchars = 400000
					local str_value = substr(value_labels_stata[`first_row'], 1, `_maxchars')
					forval k = 1/`show_labels' {
						local ki = (`k' - 1) * 2 + 1
						local ji = `ki' + 1
						local code : word `ki' of `str_value'
						local lbl : word `ji' of `str_value'
						local code = subinstr(`"`code'"', `"""', "", .)
						local lbl = subinstr(`"`lbl'"', `"""', "", .)
						local lbl = subinstr(`"`lbl'"', "`", "", .)
						local lbl = subinstr(`"`lbl'"', "'", "", .)
						local _lbl_room = 58 - strlen("`code'") - 2
						if `_lbl_room' < 10 local _lbl_room 10
						if strlen(`"`lbl'"') > `_lbl_room' {
							local lbl = substr(`"`lbl'"', 1, `_lbl_room' - 1) + "…"
						}
						if `k' == 1 {
							di as text `"  Values       `code'  `lbl'"'
						}
						else {
							di as text `"               `code'  `lbl'"'
						}
					}
					if `nlabels' > `show_labels' {
						local remaining = `nlabels' - `show_labels'
						local _scope_arg ""
						if `"`scope'"' != "" local _scope_arg `"scope(`scope')"'
						local _release_arg ""
						if "`release'" != "" local _release_arg `"release("`release'")"'
						di as text `"               {stata autolabel lookup `this_var', domain(`domain') lang(`lang') `_scope_arg' `_release_arg' list:(+`remaining' more)}"'
					}
				}
				di as text ""
			}

			* Truncation notice with "show all" click; click target uses
			* `list' which routes to the compact 2-col index above (NOT a
			* dump of N detail blocks).
			if `_truncated' == 1 {
				local _remaining = `_n_unique_vars' - `_display_cap'
				local _scope_arg ""
				if `"`scope'"' != "" local _scope_arg `"scope(`scope')"'
				local _release_arg ""
				if "`release'" != "" local _release_arg `"release("`release'")"'
				di as text "  Showing `_display_cap' of `_n_unique_vars' variables. `_remaining' more."
				di as text `"  {stata autolabel lookup `_orig_varlist', domain(`domain') lang(`lang') `_scope_arg' `_release_arg' list:Show all `_n_unique_vars'}"'
				di as text ""
			}

			}
		}
		else {
			* DETAIL MODE: delegate to variable-sticky scope-browse.
			* v3.1+ replaces the v3.0.x flat (variable x scope x value-label-id)
			* dump with one drill path that's also reachable via the
			* "N <l1_title>s" hyperlink in concise lookup output.
			*
			* Pre-validate the requested varlist BEFORE handing off: scope-browse's
			* var() filter is UNION semantics and silently ignores unknowns, so we
			* surface missing names here. _merge==2 is requested-but-missing,
			* _merge==3 is matched.
			quietly levelsof variable_name if _merge == 2, local(_missing_detail) clean
			quietly levelsof variable_name if _merge == 3, local(_existing_detail) clean
			if `"`_missing_detail'"' != "" {
				di as error "  {hline 72}"
				di as error "  The following variables were not found in `domain':"
				foreach var of local _missing_detail {
					di as error "     `var'"
				}
				di as error "  {hline 72}"
				di as text ""
			}
			if `"`_existing_detail'"' == "" {
				di as error "  No matching variables to display."
				restore
				_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
				exit 0
			}
			restore
			_autolabel_scope "`registream_dir'" , domain("`domain'") lang("`lang'") var(`_existing_detail')
			_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'
			exit 0
		}

		* If there are any missing variables, display them
		if "`missing_vars'" != "" {
			di as error "  {hline 72}"
			di as error "  The following variables were not found in `domain':"
			foreach var of local missing_vars {
				di as error "     `var'"
			}
			di as error "  {hline 72}"
		}

		* Display consolidated update message (AFTER lookup results)
		_al_utils show_updates "`var_status'" "`var_key'" "`var_current'" "`var_latest'" ///
										  "`val_status'" "`val_key'" "`val_current'" "`val_latest'"

	restore

	}

	* ==========================================================================
	* MASTER WRAPPER (END): Async telemetry + update check + notification
	* Runs for ALL autolabel commands
	* ==========================================================================
	_autolabel_wrapper_end "`REGISTREAM_VERSION'" "`AUTOLABEL_VERSION'" "`registream_dir'" `"`0'"'

end

* =============================================================================
* MASTER WRAPPER FUNCTIONS
* =============================================================================

* Wrapper start: Initialize everything + log usage + background check
program define _autolabel_wrapper_start, rclass
	* Use gettoken (handles compound quotes) so command_line can contain
	* inner quotes from scope("...") without truncation.
	gettoken current_version 0 : 0
	gettoken autolabel_version 0 : 0
	gettoken command_line 0 : 0

	* Get registream directory
	_rs_utils get_dir
	local registream_dir "`r(dir)'"
	return local registream_dir "`registream_dir'"

	* Initialize config
	_rs_config init "`registream_dir'"

	* Parse command for conditional logic
	local first_word : word 1 of `command_line'

	* Log local usage (fast, synchronous)
	_rs_config get "`registream_dir'" "usage_logging"
	if (r(value) == "true" | r(value) == "1") {
		_rs_usage init "`registream_dir'"
		_rs_usage log "`registream_dir'" `"autolabel `command_line'"' "autolabel" "`autolabel_version'" "`current_version'"
	}

	* NOTE: Telemetry and update check moved to wrapper_end for async execution
	* This ensures instant startup with no blocking on network operations
end

* Wrapper end: Consolidated heartbeat (telemetry + update check) + notification
program define _autolabel_wrapper_end
	* gettoken preserves inner quotes in command_line
	gettoken current_version 0 : 0
	gettoken autolabel_version 0 : 0
	gettoken registream_dir 0 : 0
	gettoken command_line 0 : 0

	* Get registream directory if not provided
	if ("`registream_dir'" == "") {
		_rs_utils get_dir
		local registream_dir "`r(dir)'"
	}

	* Parse first word of command (for "is this an 'update' command?" check).
	* Use word 1 of a sanitized copy to avoid gettoken choking on inner quotes.
	local first_word ""
	if (`"`command_line'"' != "") {
		local _first_word_src = subinstr(`"`command_line'"', `"""', "", .)
		local first_word : word 1 of `_first_word_src'
	}

	* Check if we should send heartbeat (telemetry OR update check enabled)
	_rs_config get "`registream_dir'" "telemetry_enabled"
	local telemetry_enabled = r(value)
	_rs_config get "`registream_dir'" "internet_access"
	local internet_access = r(value)
	_rs_config get "`registream_dir'" "auto_update_check"
	local auto_update_enabled = r(value)

	if ("`auto_update_enabled'" == "") local auto_update_enabled "true"

	local should_heartbeat = 0
	if (("`telemetry_enabled'" == "true" | "`telemetry_enabled'" == "1" | "`auto_update_enabled'" == "true" | "`auto_update_enabled'" == "1") & ("`internet_access'" == "true" | "`internet_access'" == "1") & "`first_word'" != "update") {
		local should_heartbeat = 1
	}

	* Defaults in case we skip the heartbeat (cached state not rehydrated).
	local core_update 0
	local core_latest ""
	local al_update 0
	local al_latest ""

	if (`should_heartbeat' == 1) {
		* Positional args: dir ver cmd module module_version al_ver dm_ver
		cap qui _rs_updates send_heartbeat "`registream_dir'" "`current_version'" ///
			`"autolabel `command_line'"' "autolabel" "`autolabel_version'" "" ""
		local core_update = r(update_available)
		local core_latest "`r(latest_version)'"
		local al_update = r(autolabel_update)
		local al_latest "`r(autolabel_latest)'"
	}

	* Show update notification for core + autolabel only. Datamirror banners
	* belong to datamirror-triggered heartbeats and explicit `registream update`.
	_rs_updates show_notification , ///
		current_version("`current_version'") scope(autolabel) ///
		core_update(`core_update') core_latest("`core_latest'") ///
		autolabel_update(`al_update') autolabel_latest("`al_latest'")

end

* Subcommand: autolabel info
program define _autolabel_info
	* Get version from helper function
	_rs_utils get_version
	local REGISTREAM_VERSION "`r(version)'"

	* Get registream directory
	_rs_utils get_dir
	local registream_dir "`r(dir)'"

	* Initialize config (ensures it exists)
	_rs_config init "`registream_dir'"

	* Get config values (with defaults if config is read-only)
	_rs_config get "`registream_dir'" "usage_logging"
	local usage_logging = r(value)
	if ("`usage_logging'" == "") local usage_logging "true"

	_rs_config get "`registream_dir'" "telemetry_enabled"
	local telemetry = r(value)
	if ("`telemetry'" == "") local telemetry "false"

	_rs_config get "`registream_dir'" "internet_access"
	local internet = r(value)
	if ("`internet'" == "") local internet "true"

	_rs_config get "`registream_dir'" "auto_update_check"
	local auto_update = r(value)
	if ("`auto_update'" == "") local auto_update "true"

	* Display info
	di as result ""
	di as result "========================================="
	di as result "RegiStream Configuration"
	di as result "========================================="
	di as text "Directory:        {result:`registream_dir'}"
	di as text "Config file:      {result:`registream_dir'/config_stata.csv}"
	di as text ""
	di as text "Package:"
	di as text "  version:         {result:`REGISTREAM_VERSION'}"
	di as text ""
	di as text "Settings:"
	di as text "  usage_logging:       {result:`usage_logging'} (local only, stays on your machine)"
	di as text "  telemetry_enabled:   {result:`telemetry'} (sends anonymized data to registream.org)"
	di as text "  internet_access:     {result:`internet'}"
	di as text "  auto_update_check:   {result:`auto_update'}"
	di as result "========================================="
	di as text ""
	di as text "Citation:"
	di as text "  Clark, J. & Wen, J. (2024–). RegiStream:"
	di as text "  Infrastructure for Register Data Research. https://registream.org"
	di as text ""
	di as text "Full citation (with version & datasets): {stata autolabel cite:autolabel cite}"
	di as result ""
end

* =============================================================================
* ALIASES: Commands that delegate to registream
* =============================================================================

* Subcommand: autolabel update [datasets]
program define _autolabel_update
	* Parse what to update
	gettoken what rest : 0, parse(" ,")

	if ("`what'" == "" | "`what'" == "package") {
		* Package update: delegate to registream
		registream update `0'
	}
	else if ("`what'" == "dataset" | "`what'" == "datasets") {
		* Dataset update: handle within autolabel
		syntax anything [, DOMAIN(string) LANG(string) VERSION(string)]

		_rs_utils get_dir
		local registream_dir "`r(dir)'"

		di as result ""
		di as result "{hline 60}"
		di as result "Autolabel Dataset Update Check"
		di as result "{hline 60}"
		di as result ""

		if ("`domain'" != "" | "`lang'" != "" | "`version'" != "") {
			_al_utils update_datasets_interactive "`registream_dir'", domain("`domain'") lang("`lang'") version("`version'")
		}
		else {
			_al_utils update_datasets_interactive "`registream_dir'"
		}

		di as result ""
		di as result "{hline 60}"
		di as result ""
	}
	else {
		di as error "Unknown update target: `what'"
		di as text "Usage: autolabel update [package|datasets]"
		exit 198
	}
end

* Subcommand: autolabel version
* Alias that delegates to registream version
program define _autolabel_version
	registream version
end

* Subcommand: autolabel cite
* Alias that delegates to registream cite
program define _autolabel_cite
	version 16.0

	* Caller passes the stamped autolabel version as the first positional
	* arg so the citation block below can expand it via backtick-quoted
	* macro. See registream/tools/render_citations.py _VERSION_LOCALS for
	* the ado_cite_block contract.
	gettoken AUTOLABEL_VERSION 0 : 0

	di as result ""
	di as result "{hline 60}"
	di as result "Citation"
	di as result "{hline 60}"
	di as text ""
	di as text "To cite autolabel in publications, please use:"
	di as text ""
{{CITATION_AUTOLABEL_ADO_CITE_BLOCK}}
	di as text ""
end


* =============================================================================
* SCOPE: Browse available scopes in the metadata cache (autolabel schema v2)
* =============================================================================
*
* Generic depth-agnostic browse. Uses manifest scope_depth to determine
* how many scope levels exist. The user drills by adding tokens to scope():
*
*   scope()                              → browse level 1
*   scope("LISA")                        → browse level 2 (or releases if depth=1)
*   scope("LISA" "Individer 16+")        → browse releases (if depth=2)
*   scope("LISA" "Individer 16+" "2005") → show variables (overflow = release)
*
* Three code blocks, all loop-driven:
*   BLOCK 1: n_tokens < scope_depth      → browse next scope level
*   BLOCK 2: n_tokens == scope_depth     → browse releases
*   BLOCK 3: n_tokens == scope_depth+1   → show variables (last token = release)

program define _autolabel_scope
	local q = char(34)

	gettoken registream_dir 0 : 0
	local 0 = trim(`"`0'"')

	* Extract search term (everything before the comma)
	local search ""
	local comma_pos = strpos(`"`0'"', ",")
	if `comma_pos' > 1 {
		local search = trim(substr(`"`0'"', 1, `comma_pos' - 1))
		local 0 = substr(`"`0'"', `comma_pos', .)
	}
	else if `comma_pos' == 0 & `"`0'"' != "" {
		if strpos(lower(`"`0'"'), "domain(") == 0 & strpos(lower(`"`0'"'), "lang(") == 0 {
			local search `"`0'"'
			local 0 ""
		}
	}

	* Parse options
	if substr(trim(`"`0'"'), 1, 1) != "," {
		local 0 `", `0'"'
	}
	syntax , [DOMAIN(string) LANG(string) LIST SCOPE(string asis) RELEASE(string) VAR(string)]

	if "`domain'" == "" local domain "scb"
	if "`lang'" == "" local lang "eng"
	local domain = lower("`domain'")
	local lang = lower("`lang'")

	* ── var() suffix for click URLs ──
	* Sticky variable filter: every drill click in this view must carry
	* var() forward so the user stays focused on their variable as they
	* navigate the register/variant tree.
	local _var_arg ""
	if "`var'" != "" local _var_arg `" var(`var')"'

	* ── Decode SMCL-safe colon sentinel ──
	* Click URLs encode `:` as U+2236 RATIO (`∶`) so the colon doesn't
	* collide with SMCL's command:label separator. Restore real colons here
	* before the match ladder runs against scope_level_N values.
	if strpos(`"`scope'"', char(8758)) > 0 {
		local scope = subinstr(`"`scope'"', char(8758), ":", .)
	}

	* ── Tokenize scope() into positional locals via shared parser ──
	* Pass scope by bare macro expansion (NOT `"`scope'"'). In this Stata
	* build, syntax's `asis' preserves the compound-quote delimiters we
	* would have wrapped it with, poisoning the value on every subcall.
	_al_parse_scope, scope(`scope')
	local n_tokens = r(n_tokens)
	forval _i = 1/`n_tokens' {
		local _stok_`_i' `"`r(stok_`_i')'"'
	}

	* Build paths
	if "`registream_dir'" == "" {
		_rs_utils get_dir
		local registream_dir "`r(dir)'"
	}
	local autolabel_dir "`registream_dir'/autolabel"
	local var_filepath "`autolabel_dir'/`domain'/variables_`lang'.dta"
	local scope_filepath "`autolabel_dir'/`domain'/scope_`lang'.dta"
	local rs_filepath  "`autolabel_dir'/`domain'/release_sets_`lang'.dta"
	local manifest_path "`autolabel_dir'/`domain'/manifest_`lang'.csv"

	* Download if core files not cached
	cap confirm file "`var_filepath'"
	if (_rc != 0) {
		cap mkdir "`registream_dir'"
		cap mkdir "`autolabel_dir'"
		cap mkdir "`autolabel_dir'/`domain'"
		_al_utils download_bundle, ///
			domain("`domain'") lang("`lang'") ///
			registream_dir("`registream_dir'") autolabel_dir("`autolabel_dir'")
	}

	* Scope browse requires the scope file, but it's not mandatory for other commands
	cap confirm file "`scope_filepath'"
	if _rc != 0 {
		di as error "No scope data available for `domain'/`lang'."
		di as error "This domain may only have variables + value labels (no scope hierarchy)."
		di as error "Use {bf:autolabel lookup} or {bf:autolabel variables} instead."
		exit 601
	}

	* ── Load manifest ──
	quietly _al_load_manifest, path("`manifest_path'")
	if (r(manifest_loaded) == 0) {
		di as error "Manifest not found for `domain'/`lang'. Please re-download:"
		di as error "  {bf:autolabel update datasets, domain(`domain') lang(`lang') force}"
		exit 601
	}
	local scope_depth = r(scope_depth_n)
	* Store per-level names and titles
	forval _i = 1/`scope_depth' {
		local lv_`_i'_name   "`r(scope_level_`_i'_name)'"
		local lv_`_i'_title  "`r(scope_level_`_i'_title)'"
	}

	* ── Handle overflow: if n_tokens == scope_depth+1, last token is release ──
	if (`n_tokens' == `scope_depth' + 1 & "`release'" == "") {
		local release "`_stok_`n_tokens''"
		local n_tokens = `n_tokens' - 1
	}

	* ── Load scope DTA ──
	preserve

		* ── Build scope_id allow-list from var() if given ──
		* Variables → release_set_ids → scope_ids. Inner-join the resulting
		* set against the scope dataset so only scopes containing at least
		* one requested variable survive. UNION semantics across var().
		if "`var'" != "" {
			tempfile _var_rsids _var_scope_ids
			local _vars_lower ""
			foreach _v of local var {
				local _vars_lower `"`_vars_lower' `=lower("`_v'")'"'
			}
			local _vars_lower = trim(`"`_vars_lower'"')

			quietly use "`var_filepath'", clear
			quietly gen _vlow = lower(variable_name)
			quietly gen byte _match = 0
			foreach _v of local _vars_lower {
				quietly replace _match = 1 if _vlow == "`_v'"
			}
			quietly keep if _match == 1
			if _N == 0 {
				di as error `"No metadata for variable(s) "`var'" in `domain'/`lang'."'
				restore
				exit 198
			}
			quietly bysort release_set_id: keep if _n == 1
			quietly keep release_set_id
			quietly save `_var_rsids'

			cap confirm file "`rs_filepath'"
			if _rc != 0 {
				di as error "Release sets file not found. Re-download:"
				di as error "  {bf:autolabel update datasets, domain(`domain') lang(`lang') force}"
				restore
				exit 601
			}
			quietly use "`rs_filepath'", clear
			quietly merge m:1 release_set_id using `_var_rsids', keep(3) nogen
			quietly bysort scope_id: keep if _n == 1
			quietly keep scope_id
			quietly save `_var_scope_ids'
		}

		use "`scope_filepath'", clear

		if "`var'" != "" {
			quietly merge m:1 scope_id using `_var_scope_ids', keep(3) nogen
			if _N == 0 {
				di as error `"No scopes contain variable(s) "`var'" in `domain'/`lang'."'
				restore
				exit 198
			}
		}

		* ══════════════════════════════════════════════════════════
		* GENERIC DEPTH-AGNOSTIC DRILL
		* ══════════════════════════════════════════════════════════

		* ── Apply scope-ladder filter (tokens 1..n_tokens) ──
		* Shared helper owns the "exact alias → exact name → substring name"
		* match semantics. maxdepth(n_tokens) guards against over-filtering
		* when the original scope() held an overflow release token that's
		* already been popped above.
		_al_filter_scope, scope(`scope') maxdepth(`n_tokens')
		if (r(matched) == 0) {
			local _fl = r(failed_level)
			local _ft `"`r(failed_token)'"'
			di as error `"No match for "`_ft'" at `lv_`_fl'_title' level."'
			restore
			exit 198
		}

		* ── Advance past empty sub-levels (schema allows empty deeper
		*    levels per row). If the next level would only show a single
		*    empty value, skip it by pushing an empty token. ──
		forval _skip = `=`n_tokens'+1'/`scope_depth' {
			local _next_col "scope_level_`_skip'"
			cap confirm variable `_next_col'
			if (_rc != 0) continue, break
			quietly bysort `_next_col': gen _check = (_n == 1)
			quietly count if _check == 1
			local _n_unique = r(N)
			quietly count if _check == 1 & trim(`_next_col') == ""
			local _n_empty = r(N)
			drop _check
			if (`_n_unique' == 1 & `_n_empty' == 1) {
				local n_tokens = `n_tokens' + 1
				local _stok_`n_tokens' ""
			}
			else {
				continue, break
			}
		}

		* ── Helper: build scope() click string from tokens 1..K ──
		* _click_scope_N stores the scope("A" "B" ... "N") prefix for click URLs.
		* Names embedded in click URLs are colon-encoded (`:` → U+2236 RATIO,
		* decoded at receiver entry); raw `_canonical_*` is preserved for breadcrumb
		* display where the literal colon is correct.
		local _click_scope_0 ""
		forval _ci = 1/`n_tokens' {
			local _canonical_`_ci' = scope_level_`_ci'[1]
			local _canon_safe = subinstr("`_canonical_`_ci''", ":", char(8758), .)
			if `_ci' == 1 {
				local _click_scope_`_ci' "`q'`_canon_safe'`q'"
			}
			else {
				local _prev = `_ci' - 1
				local _click_scope_`_ci' "`_click_scope_`_prev'' `q'`_canon_safe'`q'"
			}
		}

		* ── Determine next level ──
		local next_level = `n_tokens' + 1

		if (`n_tokens' < `scope_depth') {
			* ══════════════════════════════════════════════════════════
			* BLOCK 1: Browse next scope level
			* ══════════════════════════════════════════════════════════
			local next_col "scope_level_`next_level'"
			local next_title "`lv_`next_level'_title'"
			local next_name  "`lv_`next_level'_name'"

			* Search filter (only at the browse level, not when drilling)
			if "`search'" != "" & `n_tokens' == 0 {
				quietly {
					local search_lower = lower("`search'")
					local loose 0
					if (substr("`search_lower'", 1, 1) == "*") {
						local loose 1
						local search_lower = substr("`search_lower'", 2, .)
					}
					local _rx "\b`search_lower'"

					gen _direct = 0
					gen _via_next = 0
					gen str200 _matched_next = ""

					* Match against current browse level
					gen _sl = lower(`next_col')
					if `loose' {
						replace _direct = 1 if strpos(_sl, "`search_lower'") > 0
					}
					else {
						replace _direct = 1 if ustrregexm(_sl, "`_rx'")
					}
					drop _sl

					* Match against alias
					cap confirm variable `next_col'_alias
					if _rc == 0 {
						gen _al = lower(trim(`next_col'_alias))
						if `loose' {
							replace _direct = 1 if strpos(_al, "`search_lower'") > 0
						}
						else {
							replace _direct = 1 if ustrregexm(_al, "`_rx'")
						}
						drop _al
					}

					* Match against deeper levels (for context annotation)
					forval _si = `=`next_level'+1'/`scope_depth' {
						cap confirm variable scope_level_`_si'
						if _rc == 0 {
							gen _sl = lower(scope_level_`_si')
							if `loose' {
								replace _via_next = 1 if strpos(_sl, "`search_lower'") > 0
								replace _matched_next = scope_level_`_si' if strpos(_sl, "`search_lower'") > 0 & _matched_next == ""
							}
							else {
								replace _via_next = 1 if ustrregexm(_sl, "`_rx'")
								replace _matched_next = scope_level_`_si' if ustrregexm(_sl, "`_rx'") & _matched_next == ""
							}
							drop _sl
						}
					}

					keep if _direct == 1 | _via_next == 1
				}
				if _N == 0 {
					di as text `"No results found matching: `search'"'
					di as text `"  (use *`search' for loose substring match)"'
					restore
					exit 0
				}
			}

			* Collapse to one row per value at next_level
			quietly {
				cap confirm variable `next_col'_alias
				if _rc == 0 {
					gen _alias = trim(`next_col'_alias)
				}
				else {
					gen _alias = ""
				}

				* Count sub-levels (if any deeper levels exist).
				* Exclude empty-string scope_level_N values so sources with
				* no populated deeper level report 0 sub-groups rather than
				* an "empty bucket" counted as 1 group.
				local has_deeper = (`next_level' < `scope_depth')
				if `has_deeper' {
					local deeper = `next_level' + 1
					bysort `next_col' scope_level_`deeper': gen _sub_tag = (_n == 1 & scope_level_`deeper' != "")
					bysort `next_col': egen _n_sub = total(_sub_tag)
					drop _sub_tag
				}
				else {
					gen _n_sub = .
				}

				* Count releases
				bysort `next_col' release: gen _rel_tag = (_n == 1)
				bysort `next_col': egen _n_rel = total(_rel_tag)
				drop _rel_tag

				* Aggregate search match context
				cap confirm variable _direct
				if (_rc == 0) {
					bysort `next_col': egen _row_direct = max(_direct)
					bysort `next_col': egen _row_via = max(_via_next)
					bysort `next_col' (_via_next _matched_next): gen str200 _ml_first = _matched_next[_N]
				}
				else {
					gen _row_direct = 1
					gen _row_via = 0
					gen str1 _ml_first = ""
				}

				* Drop rows where the scope-level name is empty or missing.
				* Some upstream scope CSVs (e.g. Hagstofa) have rows where
				* description text overflows into scope_id and the named
				* scope_level fields are blank; these would otherwise render
				* as empty SMCL links in the listing.
				drop if missing(`next_col') | `next_col' == ""

				bysort `next_col': keep if _n == 1
				sort `next_col'
			}

			local n_rows = _N

			* ── Display ──
			* Header word: English pluralizes the title with +s; other langs
			* keep the singular title (natural plural rules vary per language)
			if ("`lang'" == "eng" | "`lang'" == "en") {
				local _next_plural "`next_title's"
			}
			else {
				local _next_plural "`next_title'"
			}
			di as result ""
			di as result "  {hline 78}"
			if "`search'" != "" {
				di as result "  `_next_plural' matching: {bf:`search'}  (domain=`domain', lang=`lang')"
			}
			else if `n_tokens' > 0 {
				* Show breadcrumb for drilled context, " · "-separated, skip empty
				local _bc ""
				forval _bi = 1/`n_tokens' {
					if "`_canonical_`_bi''" == "" continue
					if "`_bc'" == "" local _bc "`lv_`_bi'_title': {bf:`_canonical_`_bi''}"
					else local _bc "`_bc' · `lv_`_bi'_title': {bf:`_canonical_`_bi''}"
				}
				di as result "  `_bc'"
				di as result ""
				di as result "  `_next_plural'  (domain=`domain', lang=`lang')"
			}
			else {
				di as result "  `_next_plural'  (domain=`domain', lang=`lang')"
			}
			if "`var'" != "" {
				di as result "  Filtered to variable: {bf:`var'}"
			}
			di as result "  {hline 78}"
			di as text ""

			local show_n = `n_rows'
			local truncated = 0
			if "`list'" == "" & `n_rows' > 10 {
				local show_n = 10
				local truncated = 1
			}

			quietly gen str200 _display = subinstr(`next_col', "'", "", .)
			quietly replace _display = subinstr(_display, char(96), "", .)
			* Sanitize for SMCL click URLs: strip/encode chars that break {stata ...} tags.
			* Quotes/backticks break macro expansion; parentheses are SMCL-safe.
			* Colons are the SMCL command:label separator, so a literal `:` in the
			* command part poisons the dispatch. Encode `:` as U+2236 RATIO (`∶`,
			* visually identical), and decode it back to `:` at _autolabel_scope's
			* entry before the match ladder runs. The old `:` -> ` -` mapping was
			* irreversible: receivers couldn't distinguish encoded colons from
			* literal " - " sequences in other names, so click targets like
			* "Swedish Schools Abroad: Pupils ..." failed to match.
			quietly gen str200 _click_safe = subinstr(`next_col', `"""', "", .)
			quietly replace _click_safe = subinstr(_click_safe, ":", char(8758), .)
			quietly replace _click_safe = subinstr(_click_safe, "'", "", .)
			quietly replace _click_safe = subinstr(_click_safe, char(96), "", .)

			forvalues i = 1/`show_n' {
				local _name = _display[`i']
				local _full = _click_safe[`i']
				local _al   = _alias[`i']
				local _nsub = _n_sub[`i']
				local _nrel = _n_rel[`i']

				* Build click: append this value to accumulated scope tokens
				if `n_tokens' == 0 {
					local _clk `"{stata autolabel scope, domain(`domain') lang(`lang') scope(`q'`_full'`q')`_var_arg':`_name'}"'
				}
				else {
					local _clk `"{stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`n_tokens'' `q'`_full'`q')`_var_arg':`_name'}"'
				}

				if "`_al'" != "" & "`_al'" != "." {
					di as result `"  `_clk'"' as text `"  [{it:`_al'}]"'
				}
				else {
					di as result `"  `_clk'"'
				}

				if `has_deeper' & "`_nsub'" != "." & `_nsub' > 0 {
					local deeper_title "`lv_`deeper'_title'"
					* Localized title: only pluralize when language is English
					if ("`lang'" == "eng" | "`lang'" == "en") {
						_al_plural `_nsub' "`deeper_title'"
						local _sub_word "`r(word)'"
					}
					else {
						local _sub_word = lower("`deeper_title'")
					}
					_al_plural `_nrel' "release"
					local _rel_word "`r(word)'"
					di as text `"      `_nsub' `_sub_word', `_nrel' `_rel_word'"'
				}
				else {
					_al_plural `_nrel' "release"
					local _rel_word "`r(word)'"
					di as text `"      `_nrel' `_rel_word'"'
				}

				* Search context annotation
				cap confirm variable _row_direct
				if (_rc == 0) {
					local _rd = _row_direct[`i']
					local _rv = _row_via[`i']
					local _mlf = _ml_first[`i']
					if (`_rd' == 0 & `_rv' == 1 & "`_mlf'" != "") {
						local deeper_name "`lv_`deeper'_name'"
						di as text `"        (matched via `deeper_name': {it:`_mlf'})"'
					}
				}
			}

			di as text ""
			if `truncated' {
				local remaining = `n_rows' - 10
				di as text "  Showing 10 of `n_rows' `next_name's. `remaining' more available."
				if "`search'" != "" {
					local _scope_arg = cond(`n_tokens' > 0, " scope(`_click_scope_`n_tokens'')", "")
					di as text `"  {stata autolabel scope `search', domain(`domain') lang(`lang')`_scope_arg'`_var_arg' list:Show all `n_rows'}"'
				}
				else {
					local _scope_arg = cond(`n_tokens' > 0, " scope(`_click_scope_`n_tokens'')", "")
					di as text `"  {stata autolabel scope, domain(`domain') lang(`lang')`_scope_arg'`_var_arg' list:Show all `n_rows'}"'
				}
			}
			else {
				* next_name is the machine-readable level name (lowercase, English-ish)
				_al_plural `n_rows' "`next_name'"
				di as result "  `n_rows' `r(word)'"
			}

			if "`search'" == "" & `n_tokens' == 0 {
				di as text ""
				di as text "  Search: {bf:autolabel scope {it:term}, domain(`domain') lang(`lang')`_var_arg'}"
			}

			* Back-navigation
			if `n_tokens' > 0 {
				di as text ""
				local _prev = `n_tokens' - 1
				if `_prev' > 0 {
					di as text `"  {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`_prev'')`_var_arg':↩ back to `lv_`n_tokens'_name'}"'
				}
				di as text `"  {stata autolabel scope, domain(`domain') lang(`lang')`_var_arg':↩ back to `lv_1_name's}"'
			}
			if "`var'" != "" {
				if `n_tokens' == 0 di as text ""
				local _drop_scope = cond(`n_tokens' > 0, " scope(`_click_scope_`n_tokens'')", "")
				di as text `"  {stata autolabel scope, domain(`domain') lang(`lang')`_drop_scope':✕ drop variable filter}"'
			}
		}
		else if (`n_tokens' == `scope_depth' & "`release'" == "") {
			* ══════════════════════════════════════════════════════════
			* BLOCK 2: Browse releases (all scope levels specified)
			* ══════════════════════════════════════════════════════════

			* Dedup to unique releases
			quietly {
				bysort release: keep if _n == 1
				sort release
			}
			local n_rel = _N

			* Auto-drill: if only 1 release, skip straight to variables
			if (`n_rel' == 1) {
				local release = release[1]
			}
			else {
				* Display breadcrumb
				di as result ""
				di as result "  {hline 78}"
				forval _bi = 1/`scope_depth' {
					* Skip levels whose canonical value is empty (auto-advanced past)
					if "`_canonical_`_bi''" == "" continue
					local _al ""
					cap confirm variable scope_level_`_bi'_alias
					if _rc == 0 {
						local _al = trim(scope_level_`_bi'_alias[1])
					}
					if "`_al'" != "" & "`_al'" != "." {
						di as result `"  `lv_`_bi'_title': {bf:`_canonical_`_bi''}  [{it:`_al'}]"'
					}
					else {
						di as result `"  `lv_`_bi'_title': {bf:`_canonical_`_bi''}"'
					}
				}
				if "`var'" != "" {
					di as result "  Filtered to variable: {bf:`var'}"
				}
				di as result "  {hline 78}"
				di as text ""
				di as text "  Releases:"

				* Emit clickable release links (overflow token style)
				forvalues i = 1/`n_rel' {
					local _rel = release[`i']
					di as text `"    ▸ {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`scope_depth'' `q'`_rel'`q')`_var_arg':`_rel'}"'
				}

				* Back-navigation
				di as text ""
				local _prev = `scope_depth' - 1
				if `_prev' > 0 {
					di as text `"  {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`_prev'')`_var_arg':↩ back to `lv_`scope_depth'_name'}"'
				}
				di as text `"  {stata autolabel scope, domain(`domain') lang(`lang')`_var_arg':↩ back to `lv_1_name's}"'
				if "`var'" != "" {
					di as text `"  {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`scope_depth''):✕ drop variable filter}"'
				}
			}
		}

		* ── BLOCK 3 runs if release is set (explicitly, via overflow, or via auto-drill) ──
		if (`n_tokens' == `scope_depth' & "`release'" != "") {
			* ══════════════════════════════════════════════════════════
			* BLOCK 3: Show variables (all scope levels + release)
			* ══════════════════════════════════════════════════════════

			* Filter on release
			quietly keep if release == "`release'"
			if _N == 0 {
				di as error `"Release "`release'" not found for this scope."'
				di as text `"  {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`scope_depth'')`_var_arg':See available releases}"'
				restore
				exit 198
			}

			* Collect matching scope_ids, then join to variables via release_sets
			quietly levelsof scope_id, local(_sids)

			cap confirm file "`rs_filepath'"
			if _rc != 0 {
				di as error "Release sets file not found. Re-download with:"
				di as error "  {bf:autolabel update datasets, domain(`domain') lang(`lang') force}"
				restore
				exit 601
			}
			cap confirm file "`var_filepath'"
			if _rc != 0 {
				di as error "Variables file not found."
				restore
				exit 601
			}

			* Resolve canonical names for display
			forval _bi = 1/`scope_depth' {
				local _canonical_`_bi' = scope_level_`_bi'[1]
			}

			* Find release_set_ids matching our scope_ids
			quietly {
				use "`rs_filepath'", clear
				gen byte _match = 0
				foreach _sid of local _sids {
					replace _match = 1 if scope_id == `_sid'
				}
				keep if _match == 1
				drop _match
				bysort release_set_id: keep if _n == 1
				keep release_set_id
				tempfile _matching_rsids
				save `_matching_rsids'
			}

			* Load variables and filter
			quietly {
				use "`var_filepath'", clear
				merge m:1 release_set_id using `_matching_rsids', keep(3) nogen
			}

			* Apply var() filter at the leaf so the variable list stays
			* focused on what brought the user into this drill. UNION over
			* the varlist, same semantics as the upstream scope_id filter.
			if "`var'" != "" {
				quietly {
					local _vars_lower ""
					foreach _v of local var {
						local _vars_lower `"`_vars_lower' `=lower("`_v'")'"'
					}
					local _vars_lower = trim(`"`_vars_lower'"')
					gen _vlow = lower(variable_name)
					gen byte _vmatch = 0
					foreach _v of local _vars_lower {
						replace _vmatch = 1 if _vlow == "`_v'"
					}
					keep if _vmatch == 1
					drop _vlow _vmatch
				}
				if _N == 0 {
					di as error `"No metadata for variable(s) "`var'" in this scope/release."'
					restore
					exit 198
				}
			}

			if "`search'" != "" {
				quietly {
					local _sl = lower("`search'")
					keep if strpos(lower(variable_name), "`_sl'") > 0
				}
			}

			quietly bysort variable_name: keep if _n == 1
			quietly sort variable_name

			local n_vars = _N

			* Display breadcrumb (skip empty levels auto-advanced past)
			di as result ""
			di as result "  {hline 78}"
			forval _bi = 1/`scope_depth' {
				if "`_canonical_`_bi''" == "" continue
				di as result `"  `lv_`_bi'_title': {bf:`_canonical_`_bi''}"'
			}
			di as result `"  Release:  {bf:`release'}"'
			if "`var'" != "" {
				di as result "  Filtered to variable: {bf:`var'}"
			}
			di as result "  {hline 78}"
			di as text ""

			* ── Render the compact variable index via the shared helper ──
			local _cap = cond("`list'" == "", 20, 0)
			local _scope_arg "`_click_scope_`scope_depth''"
			local _showall autolabel scope `search', domain(`domain') lang(`lang') scope(`_scope_arg' `q'`release'`q')`_var_arg' list
			local _clickopts domain(`domain') lang(`lang') scope(`_scope_arg') release("`release'")
			_al_render_var_list, ///
				clickcmd(autolabel lookup) ///
				clickopts(`_clickopts') ///
				showallcmd(`_showall') ///
				search(`search') cap(`_cap')

			* Apply hint: the action the user wants after browsing
			di as text ""
			* Apply Labels: when var() is pinned, propose the same varlist so the
			* hint matches what the user is currently viewing. Otherwise label
			* everything in the scope/release (bulk-labeling default).
			local _apply_vars = cond("`var'" != "", " `var'", "")
			di as text `"  Apply labels: {bf:autolabel variables`_apply_vars', domain(`domain') lang(`lang') scope(`_click_scope_`scope_depth'') release("`release'")}"'

			* Back-navigation
			di as text ""
			di as text `"  {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`scope_depth'')`_var_arg':↩ back to releases}"'
			local _prev = `scope_depth' - 1
			if `_prev' > 0 {
				di as text `"  {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`_prev'')`_var_arg':↩ back to `lv_`scope_depth'_name'}"'
			}
			di as text `"  {stata autolabel scope, domain(`domain') lang(`lang')`_var_arg':↩ back to `lv_1_name's}"'
			if "`var'" != "" {
				di as text `"  {stata autolabel scope, domain(`domain') lang(`lang') scope(`_click_scope_`scope_depth'' `q'`release'`q'):✕ drop variable filter}"'
			}
		}

	restore
end


* Helper: English plural for count phrases. Returns via r(word).
* Always lowercase, always appends "s" when count != 1. Use this ONLY for
* English words (e.g. the schema term "release", or titles in an
* English-language manifest). For localized titles in non-English manifests,
* callers should use the singular form directly; other languages have
* different plural rules (Norwegian kilde -> kilder, not kildes).
*
*   _al_plural 1 "Variant"  -> variant
*   _al_plural 3 "Variant"  -> variants
*   _al_plural 3 "release"  -> releases
program define _al_plural, rclass
	args n word
	local w = lower("`word'")
	if (`n' == 1) {
		return local word "`w'"
	}
	else {
		return local word "`w's"
	}
end


* =============================================================================
* autolabel suggest: preview metadata coverage for the loaded dataset
* =============================================================================
*
*   autolabel suggest, domain(X) lang(Y)                → per-scope coverage
*   autolabel suggest, domain(X) lang(Y) scope("...")   → vars attributable
*                                                          to the specified
*                                                          scope
*
* Runs `_al_collapse_metadata` with `datavars = <all user vars>` and groups
* the resulting per-variable scope attribution by scope_level_1. Shows what
* automatic-mode labeling would produce WITHOUT touching the user's dataset.
*
* Each scope row in the top-level view is a clickable hyperlink that
* dispatches `autolabel scope <NAME>` for a richer drill-down than the
* recursive suggest detail view.
*
* Schema: v3 only. The collapsed output comes from `_al_collapse_v2`
* (when release_set_id is present) and has columns: variable_name,
* variable_label, scope_level_1..N, scope_level_N_alias, _is_primary.
* Pre-v3 legacy bundles (register column) are not supported here.
* =============================================================================

program define _autolabel_suggest
	syntax , DOMAIN(string) LANG(string) [SCOPE(string asis) LIST]

	* Literal double-quote for click URLs (same trick as _autolabel_scope)
	local q = char(34)

	local domain = lower("`domain'")
	local lang = lower("`lang'")

	* Validate: need a loaded dataset with variables
	quietly describe, varlist
	local _datavars `r(varlist)'
	local _n_datavars : word count `_datavars'
	if `_n_datavars' == 0 {
		di as error "autolabel suggest requires a dataset in memory (no variables found)."
		di as text  "  Load your panel with: {bf:use mydata, clear}"
		exit 459
	}

	* Resolve cache paths and bootstrap bundle if missing
	_rs_utils get_dir
	local registream_dir "`r(dir)'"
	local autolabel_dir "`registream_dir'/autolabel"
	local var_dta "`autolabel_dir'/`domain'/variables_`lang'.dta"

	cap confirm file "`var_dta'"
	if (_rc != 0) {
		cap mkdir "`registream_dir'"
		cap mkdir "`autolabel_dir'"
		_al_utils download_bundle, ///
			domain("`domain'") lang("`lang'") ///
			registream_dir("`registream_dir'") autolabel_dir("`autolabel_dir'")
	}

	* Run the same collapse that `autolabel variables` uses. Pass `quiet`
	* so the collapse doesn't print its own inference line; suggest
	* renders its own header below. If the caller supplied `scope()`, the
	* collapse applies the scope filter; otherwise it infers the primary
	* from the user's datavars.
	tempfile _collapsed
	_al_collapse_metadata, dta("`var_dta'") output("`_collapsed'") ///
		datavars("`_datavars'") scope(`scope') quiet
	local _primary_display = r(inferred_display)
	local _primary_compact = r(inferred_compact)
	local _match_pct = r(match_pct)
	local _has_strong_primary = r(has_strong_primary)
	if "`_has_strong_primary'" == "" local _has_strong_primary 0

	* Build the user-varlist tempfile BEFORE preserve, using postfile so we
	* don't have to swap the in-memory dataset (nested preserve is illegal).
	tempfile _users
	tempname _ufh
	cap postutil clear
	postfile `_ufh' str50 variable_name using `_users'
	foreach _v of local _datavars {
		post `_ufh' ("`=lower("`_v'")'")
	}
	postclose `_ufh'

	preserve
		* Load collapsed metadata and inner-join with the user's varlist
		* so each remaining row is a (user var → scope) attribution.
		quietly use "`_collapsed'", clear

		cap confirm variable scope_level_1
		if (_rc != 0) {
			di as error "Collapsed metadata is missing scope_level_1."
			di as error "The bundle may be legacy (pre-v3) or corrupt."
			di as error "Re-download with: autolabel update datasets"
			restore
			exit 111
		}

		local _keep_cols "variable_name variable_label scope_level_1"
		cap confirm variable scope_level_1_alias
		if (_rc == 0) local _keep_cols "`_keep_cols' scope_level_1_alias"

		quietly keep `_keep_cols'

		quietly merge 1:1 variable_name using `_users', keep(1 3)
		* _merge==3 → user var with a metadata row (would be labeled)
		* _merge==1 → metadata var not in user dataset (ignore)

		quietly count if _merge == 3
		local _n_matched = r(N)
		local _n_unmatched = `_n_datavars' - `_n_matched'

		quietly keep if _merge == 3
		quietly drop _merge

		* Build the per-scope aggregation tempfile we can reload for both views
		tempfile _matched
		quietly save `_matched'

		if (`"`scope'"' == "") {
			* ══════════════════════════════════════════════════════════
			* Top-level view: per-scope-level-1 coverage table
			* ══════════════════════════════════════════════════════════
			quietly use `_matched', clear
			quietly bysort scope_level_1: gen _n_match = _N
			quietly bysort scope_level_1: keep if _n == 1
			gsort -_n_match scope_level_1

			local n_regs_total = _N
			local _show_n = `n_regs_total'
			local _trunc 0
			if "`list'" == "" & `n_regs_total' > 10 {
				local _show_n = 10
				local _trunc 1
			}

			di as result ""
			di as result "  {hline 72}"
			di as result `"  Label coverage preview   ·   `domain'/`lang'   ·   `_n_matched' of `_n_datavars' covered"'
			di as result "  {hline 72}"
			di as text ""

			forvalues i = 1/`_show_n' {
				local _scope_name = scope_level_1[`i']
				local _scope_alias ""
				cap local _scope_alias = scope_level_1_alias[`i']
				local _nm = _n_match[`i']
				local _share : display %4.1f 100 * `_nm' / `_n_datavars'
				local _scope_safe = subinstr("`_scope_name'", "'", "", .)
				local _scope_safe = subinstr("`_scope_safe'", char(96), "", .)
				* Primary marker: star the strong-primary row by matching
				* either the compact alias or the full scope name.
				local _marker "  "
				if `_has_strong_primary' {
					if ("`_scope_alias'" != "" & "`_scope_alias'" == "`_primary_compact'") {
						local _marker "* "
					}
					else if ("`_scope_safe'" == "`_primary_compact'") {
						local _marker "* "
					}
				}
				* Display: alias (truncated full name) when alias exists,
				* else truncated full name.
				if ("`_scope_alias'" != "" & "`_scope_alias'" != ".") {
					local _full_trunc = substr("`_scope_safe'", 1, 36)
					if (strlen("`_scope_safe'") > 36) local _full_trunc "`_full_trunc'…"
					local _scope_disp "`_scope_alias' ({it:`_full_trunc'})"
					* Click target uses the alias (shorter, stable).
					local _click_target "`_scope_alias'"
				}
				else {
					local _scope_disp = substr("`_scope_safe'", 1, 46)
					if (strlen("`_scope_safe'") > 46) local _scope_disp "`_scope_disp'…"
					local _click_target "`_scope_safe'"
				}
				* Click dispatches to `autolabel scope` (scope browse),
				* richer view than the recursive suggest detail.
				local _click `"{stata autolabel scope `_click_target', domain(`domain') lang(`lang'):`_scope_disp'}"'
				di as text `"   `_marker'`_click'"' _col(58) as result %4.0f `_nm' "  (`_share'%)"
			}

			if `_trunc' {
				local _rem = `n_regs_total' - `_show_n'
				di as text ""
				di as text `"     {stata autolabel suggest, domain(`domain') lang(`lang') list:Show all `n_regs_total' scopes} (`_rem' more)"'
			}
			di as text ""
			di as text   `"  {help autolabel##rules:How labeling works}"'
			di as text ""
		}
		else {
			* ══════════════════════════════════════════════════════════
			* Detail view: variables attributable to the specified scope
			* (the collapse already filtered; _matched IS the subset).
			* ══════════════════════════════════════════════════════════
			quietly use `_matched', clear
			quietly sort variable_name

			local _n_here = _N
			if (`_n_here' == 0) {
				di as error `"No variables in your dataset are attributable to scope: `scope'"'
				di as text `"  Use {stata autolabel suggest, domain(`domain') lang(`lang'):autolabel suggest} to see per-scope coverage."'
				restore
				exit 0
			}

			* Resolve display name for the scope (prefer alias, fall back to name)
			local _scope_display "`scope'"
			cap {
				local _alias_first = scope_level_1_alias[1]
				local _name_first = scope_level_1[1]
				if ("`_alias_first'" != "" & "`_alias_first'" != ".") {
					local _scope_display "`_alias_first' ({it:`_name_first'})"
				}
				else {
					local _scope_display "`_name_first'"
				}
			}

			di as result ""
			di as result "  {hline 78}"
			di as result `"  Scope: {bf:`_scope_display'}"'
			di as result `"  `_n_here' of `_n_datavars' dataset variable(s) would be labeled from this scope"'
			di as result "  {hline 78}"
			di as text ""

			local _show_n = `_n_here'
			local _trunc 0
			if "`list'" == "" & `_n_here' > 20 {
				local _show_n = 20
				local _trunc 1
			}

			forvalues i = 1/`_show_n' {
				local _var = variable_name[`i']
				local _vlabel = variable_label[`i']
				local _var_disp = substr("`_var'", 1, 20)
				if strlen("`_var'") > 20 local _var_disp = substr("`_var'", 1, 19) + "…"
				local _lbl_disp = substr(`"`_vlabel'"', 1, 54)
				if strlen(`"`_vlabel'"') > 54 local _lbl_disp = substr(`"`_vlabel'"', 1, 53) + "…"
				* scope is `string asis`; user's quoting is preserved in the
				* macro, so re-emit as-is rather than wrapping in extra quotes.
				local _click `"{stata autolabel lookup `_var', domain(`domain') lang(`lang') scope(`scope'):`_var_disp'}"'
				di as text `"  `_click'"' _col(25) as text `"`_lbl_disp'"'
			}
			if `_trunc' {
				local _rem = `_n_here' - `_show_n'
				di as text ""
				di as text `"  Showing `_show_n' of `_n_here'. `_rem' more available:"'
				di as text `"  {stata autolabel suggest, domain(`domain') lang(`lang') scope(`scope') list:Show all `_n_here'}"'
			}

			* Copy-paste pin command for this subset
			di as text ""
			di as text "  Explicit-pin command for this subset:"
			local _paste "autolabel variables"
			local _i = 0
			foreach _v in `_datavars' {
				quietly count if variable_name == lower("`_v'")
				if r(N) > 0 {
					local _paste "`_paste' `_v'"
					local ++_i
					if `_i' >= 8 continue, break
				}
			}
			local _suffix ""
			if `_n_here' > 8 local _suffix " ..."
			di as text `"    `_paste'`_suffix' ///"'
			di as text `"      domain(`domain') lang(`lang') scope(`scope')"'

			di as text ""
			di as text `"  {stata autolabel suggest, domain(`domain') lang(`lang'):↩ back to coverage summary}"'
			di as text ""
		}

	restore
end


* =============================================================================
* _al_collapse_metadata: v3-only thin wrapper around _al_collapse_v2.
*
* Given the variables DTA for a v3 bundle, apply scope / release filters
* (or infer primary scope from the user's datavars when no scope is given),
* collapse to one row per variable_name via majority-rule on the label, and
* save to `output'. This function is kept as a public entry point so
* callers (`autolabel variables`, `autolabel lookup`, `autolabel suggest`)
* don't have to know about the `_v2` implementation name.
*
* Arguments:
*   dta       - path to the variables DTA file (v3 bundle)
*   output    - path where the collapsed DTA will be saved
*   scope     - string-asis scope tokens (e.g. "LISA" or `"LISA" "Adults"')
*   release   - release atom to filter by (optional)
*   datavars  - space-separated user-dataset variable names, used for
*               primary scope inference when scope() is empty
*   quiet     - suppress the "Primary Scope (inferred)" banner
*
* Returns (passed through from _al_collapse_v2 via `return add'):
*   r(merge_dta)          - path to the collapsed DTA (same as output)
*   r(n_ambiguous)        - # variables with >1 distinct labels before collapse
*   r(pin_hints)          - filters that would further disambiguate
*   r(inferred_register)  - display name of inferred primary scope
*   r(inferred_display)   - ditto (kept for caller compat)
*   r(inferred_compact)   - compact form (alias if available, else name)
*   r(match_pct)          - % of datavars covered by the primary scope
*   r(primary_matches)    - # datavars covered by the primary scope
*   r(n_datavars)         - total # of datavars passed to inference
*   r(has_strong_primary) - 1 if the primary covers >=10% of datavars
* =============================================================================
program define _al_collapse_metadata, rclass
	syntax, dta(string) output(string) [scope(string asis) release(string) datavars(string) uncollapsed(string) QUIet]

	* v3 requires release_set_id on the variables table. Anything else is a
	* legacy bundle that pre-dates the 5-file bundle design and is no longer
	* supported client-side; surface a clean "re-download" error.
	quietly describe using "`dta'", varlist
	if (strpos("`r(varlist)'", "release_set_id") == 0) {
		di as error "Metadata for this domain/language is missing release_set_id."
		di as error "The cached bundle pre-dates schema v3 and is no longer supported."
		di as error "Re-download with: autolabel update datasets"
		exit 198
	}

	_al_collapse_v2, dta("`dta'") output("`output'") ///
		scope(`scope') release("`release'") ///
		datavars("`datavars'") uncollapsed("`uncollapsed'") `quiet'
	return add
end


* =============================================================================
* _al_collapse_v2: schema v2 metadata filtering via FK chain
*
* Resolves the release_set_id → release_sets → scope chain,
* filters by scope_level_1/scope_level_2/release, infers primary scope
* if none specified, and collapses to one row per variable_name via
* majority-label rule.
*
* Called by _al_collapse_metadata when release_set_id column is detected.
* =============================================================================
program define _al_collapse_v2, rclass
	syntax, dta(string) output(string) [scope(string asis) release(string) datavars(string) uncollapsed(string) QUIet]

	* Note: scope tokenization lives in _al_filter_scope. This function
	* only needs to know whether scope was provided (non-empty) to pick
	* between the inference and explicit-filter branches below.

	* Load manifest for scope_depth + display titles
	local _manifest_csv = subinstr(subinstr("`dta'", "/variables_", "/manifest_", 1), ".dta", ".csv", 1)
	local l1_title "Scope"
	local scope_depth 1
	cap quietly _al_load_manifest, path("`_manifest_csv'")
	if (_rc == 0 & r(manifest_loaded) == 1) {
		local l1_title "`r(scope_level_1_title)'"
		local scope_depth = r(scope_depth_n)
	}

	* Build dynamic keepusing list from scope_depth
	local _scope_keepvars ""
	forval _i = 1/`scope_depth' {
		local _scope_keepvars "`_scope_keepvars' scope_level_`_i' scope_level_`_i'_alias"
	}

	* Build dynamic grouping columns (for bysort)
	local _scope_group ""
	forval _i = 1/`scope_depth' {
		local _scope_group "`_scope_group' scope_level_`_i'"
	}

	preserve
		* ─────────────────────────────────────────────────────────────
		* Build scope lookup from release_sets + scope.
		* NOTE: Stata does not support nested preserve. All sub-loads
		* use tempfiles to avoid nesting.
		* ─────────────────────────────────────────────────────────────
		local rs_dta = subinstr("`dta'", "/variables_", "/release_sets_", 1)
		local scope_dta = subinstr("`dta'", "/variables_", "/scope_", 1)

		cap confirm file "`rs_dta'"
		if (_rc != 0) {
			di as error "Release sets file not found: `rs_dta'"
			di as error "Re-download with: autolabel update datasets"
			restore
			exit 601
		}
		cap confirm file "`scope_dta'"
		if (_rc != 0) {
			di as error "Scope file not found: `scope_dta'"
			restore
			exit 601
		}

		* ─────────────────────────────────────────────────────────────
		* RELEASE FILTER (scope-id level): if user specified release(),
		* resolve which scope_ids match that release atom up front, then
		* use that set to narrow both the scope_lookup (so displayed scope
		* rows are release-matching only) and the surviving release_set_ids
		* for the variables filter.
		* ─────────────────────────────────────────────────────────────
		if "`release'" != "" {
			tempfile _release_scope_ids
			quietly {
				use "`scope_dta'", clear
				keep if release == "`release'"
				if _N == 0 {
					di as error "No metadata found for release '`release''."
					restore
					exit 198
				}
				keep scope_id
				bysort scope_id: keep if _n == 1
				save `_release_scope_ids'
			}
		}

		* Create scope lookup: one row per release_set_id (per scope_id when
		* release is pinned, since a single release_set can contain scope_ids
		* from multiple releases).
		tempfile _scope_lookup
		quietly {
			use "`rs_dta'", clear
			if "`release'" != "" {
				* Drop (release_set_id, scope_id) pairs whose scope_id doesn't
				* match the pinned release, so downstream display only pulls
				* release-matching scope rows.
				merge m:1 scope_id using `_release_scope_ids', keep(3) nogen
				bysort release_set_id scope_id: keep if _n == 1
			}
			else {
				bysort release_set_id: keep if _n == 1
			}
			keep release_set_id scope_id
			* Bring scope_level columns from scope (dynamic based on depth)
			merge m:1 scope_id using "`scope_dta'", ///
				keep(1 3) nogen keepusing(`_scope_keepvars')
			* Ensure all expected scope columns exist (even if scope file lacked them)
			forval _i = 1/`scope_depth' {
				cap confirm variable scope_level_`_i'
				if (_rc != 0) gen str1 scope_level_`_i' = ""
				cap confirm variable scope_level_`_i'_alias
				if (_rc != 0) gen str1 scope_level_`_i'_alias = ""
			}
			save `_scope_lookup'
		}

		* Derive surviving release_set_ids from the filtered scope_lookup.
		if "`release'" != "" {
			tempfile _surviving_rsids
			quietly {
				use `_scope_lookup', clear
				bysort release_set_id: keep if _n == 1
				keep release_set_id
				save `_surviving_rsids'
			}
		}

		* Now load the variables data
		quietly use "`dta'", clear

		* variable_name is the merge key for downstream joins. Some bundles
		* ship it as strL (Stata's variable-length string) when source values
		* include non-ASCII bytes; `merge` cannot use strL keys. Convert via
		* gen→drop→rename then save+reload so stale strL pool references are
		* cleared (otherwise a later `save` reports the strL component as
		* corrupt). No-op when already str#.
		local _vn_type : type variable_name
		if ("`_vn_type'" == "strL") {
			qui gen str244 _vn_fixed = variable_name
			qui drop variable_name
			qui rename _vn_fixed variable_name
			qui compress variable_name
			tempfile _vn_fixed_dta
			qui save "`_vn_fixed_dta'", replace
			qui use "`_vn_fixed_dta'", clear
		}

		* Apply release filter if computed
		if "`release'" != "" {
			quietly merge m:1 release_set_id using `_surviving_rsids', keep(3) nogen

			if _N == 0 {
				di as error "No variables found for release '`release''."
				di as error "Use {bf:autolabel scope} to see available releases."
				restore
				exit 198
			}
		}

		* ─────────────────────────────────────────────────────────────
		* Merge scope into variables via the lookup
		* ─────────────────────────────────────────────────────────────
		quietly merge m:1 release_set_id using `_scope_lookup', keep(1 3) nogen

		* ─────────────────────────────────────────────────────────────
		* SCOPE INFERENCE: If no scope specified, detect from data
		* Group by all scope levels for full granularity.
		* ─────────────────────────────────────────────────────────────
		if `"`scope'"' == "" & "`datavars'" != "" {

			local n_datavars : word count `datavars'

			quietly gen _in_dataset = 0
			foreach v of local datavars {
				quietly replace _in_dataset = 1 if lower(variable_name) == lower("`v'")
			}

			* Count unique variable matches per scope group
			quietly bysort `_scope_group' variable_name: gen _first_in_scope = (_n == 1)
			quietly gen _unique_match = _in_dataset * _first_in_scope
			quietly bysort `_scope_group': egen _scope_matches = total(_unique_match)
			drop _first_in_scope _unique_match

			quietly summarize _scope_matches
			local max_matches = r(max)

			if (`max_matches' > 0) {
				gsort -_scope_matches `_scope_group'
				* Capture inferred scope values at each level
				forval _i = 1/`scope_depth' {
					local _inferred_`_i' = scope_level_`_i'[1]
				}

				* Compact display: alias-first when available, else truncated name
				local _alias1 ""
				cap local _alias1 = scope_level_1_alias[1]
				if ("`_alias1'" != "" & "`_alias1'" != ".") {
					* alias + truncated full name if different
					local _fn "`_inferred_1'"
					if (strlen("`_fn'") > 40) local _fn = substr("`_fn'", 1, 37) + "..."
					local display_name "`_alias1' ({it:`_fn'})"
				}
				else {
					local _fn "`_inferred_1'"
					if (strlen("`_fn'") > 60) local _fn = substr("`_fn'", 1, 57) + "..."
					local display_name "`_fn'"
				}

				local match_pct = round(`max_matches' / `n_datavars' * 100, 1)

				if (`match_pct' >= 10) {
					if "`quiet'" == "" {
						di as text "  Primary `l1_title': {result:`display_name'}, `max_matches'/`n_datavars' ({result:`match_pct'%})"
					}
					return scalar has_strong_primary = 1
				}
				else {
					if "`quiet'" == "" {
						di as text "  No strong primary `l1_title' (top: {result:`display_name'}, `max_matches'/`n_datavars')"
					}
					return scalar has_strong_primary = 0
				}

				* Tag primary scope for dedup preference (match all levels)
				quietly gen _is_primary = 1
				forval _i = 1/`scope_depth' {
					quietly replace _is_primary = 0 if scope_level_`_i' != "`_inferred_`_i''"
				}

				* Compact display: alias if available, else truncated name
				local _compact "`_alias1'"
				if ("`_compact'" == "" | "`_compact'" == ".") {
					local _compact "`_inferred_1'"
					if (strlen("`_compact'") > 40) local _compact = substr("`_compact'", 1, 37) + "..."
				}
				return local inferred_register "`display_name'"
				return local inferred_display "`display_name'"
				return local inferred_compact "`_compact'"
				return scalar match_pct = `match_pct'
				return scalar primary_matches = `max_matches'
				return scalar n_datavars = `n_datavars'
			}
			else {
				* Inference ran but no strong primary. Leave _is_primary
				* unset — gsort below will fall through to frequency-only,
				* and the end-of-function safety net fills it with 0 for
				* any downstream caller that reads it.
				return scalar has_strong_primary = 0
				return scalar match_pct = 0
			}

			cap drop _in_dataset _scope_matches
		}

		* ─────────────────────────────────────────────────────────────
		* EXPLICIT SCOPE FILTER: delegate to shared _al_filter_scope.
		* The helper owns the match ladder (exact alias → exact name →
		* substring) so semantics can't drift from the scope-drill path.
		* ─────────────────────────────────────────────────────────────
		else if `"`scope'"' != "" {
			_al_filter_scope, scope(`scope') maxdepth(`scope_depth')
			if (r(matched) == 0) {
				local _fl = r(failed_level)
				local _ft `"`r(failed_token)'"'
				di as error `"No variables found for "`_ft'" at scope level `_fl' in domain metadata."'
				di as error "Use {bf:autolabel scope} to see available scopes."
				restore
				exit 198
			}

			* User pinned this scope, so every filtered row is primary by
			* declaration. Downstream coverage reports ("N labels from
			* primary scope") depend on this being set.
			gen _is_primary = 1
		}
		* Else: bare lookup (no scope, no datavars). No primary signal
		* exists — _is_primary stays unset. The gsort falls through to
		* frequency-only ordering; the end-of-function safety net fills
		* _is_primary = 0 for downstream callers.

		* ─────────────────────────────────────────────────────────────
		* COLLAPSE to one row per variable_name (majority-label rule)
		* Same algorithm as pre-finalized path.
		* ─────────────────────────────────────────────────────────────

		* Measure REAL ambiguity: variables with >1 distinct label
		quietly bysort variable_name variable_label: gen _lbl_first = (_n == 1)
		quietly bysort variable_name: egen _n_distinct = total(_lbl_first)
		quietly egen _ambig_tag = tag(variable_name) if _n_distinct > 1
		quietly count if _ambig_tag == 1
		local n_ambiguous_vars = r(N)
		quietly drop _ambig_tag _n_distinct _lbl_first

		* Build dynamic pin-hint
		local pin_hints ""
		if `"`scope'"' == "" {
			local pin_hints "scope()"
		}
		if "`release'" == "" {
			local pin_hints = cond("`pin_hints'"=="", "release()", "`pin_hints' / release()")
		}

		* Pre-collapse: count distinct registers/variants/release-sets per variable
		* by fanning variable_name → release_set_id → scope_id → scope_level_1.
		* Must go through the FK chain because variables.dta may already be
		* collapsed to one row per variable (the counts live in scope.dta).
		tempfile _wk_snap _counts
		quietly save `_wk_snap'
		quietly {
			bysort variable_name release_set_id: keep if _n == 1
			keep variable_name release_set_id

			joinby release_set_id using "`rs_dta'"

			local _sc2k ""
			if `scope_depth' >= 2 local _sc2k "scope_level_2"
			merge m:1 scope_id using "`scope_dta'", keep(1 3) nogen ///
				keepusing(scope_level_1 `_sc2k')

			* Count distinct non-empty scope_level_N values per variable.
			* scope_depth is a MAX, not uniform: a domain may declare
			* scope_depth=2 while many scope rows have empty scope_level_2
			* (only some sources/registers have sub-variants). Excluding
			* empty-string values keeps the counts honest — "X groups"
			* reports real groups, not an empty-bucket placeholder.
			bysort variable_name scope_level_1: gen _s1 = (_n == 1 & scope_level_1 != "")
			bysort variable_name: egen _n_scope1 = total(_s1)
			drop _s1

			cap confirm variable scope_level_2
			if _rc == 0 {
				bysort variable_name scope_level_2: gen _s2 = (_n == 1 & scope_level_2 != "")
				bysort variable_name: egen _n_scope2 = total(_s2)
				drop _s2
			}
			else {
				* Scope depth 1: no level-2 axis. Generate a zero column so
				* the downstream keep + merge works uniformly regardless of
				* the domain's scope depth.
				gen int _n_scope2 = 0
			}

			bysort variable_name release_set_id: gen _rs = (_n == 1)
			bysort variable_name: egen _n_releases = total(_rs)
			drop _rs

			bysort variable_name: keep if _n == 1
			keep variable_name _n_scope1 _n_scope2 _n_releases
			save `_counts'
		}
		quietly {
			use `_wk_snap', clear
			merge m:1 variable_name using `_counts', keep(1 3) nogen
		}

		* Pre-collapse snapshot for callers (e.g. lookup detail mode) that
		* need the full variable x scope cross product after filtering, but
		* before the majority-rule reduction below collapses to one row per
		* variable_name. Caller owns the tempfile path via uncollapsed().
		if (`"`uncollapsed'"' != "") {
			quietly save `"`uncollapsed'"', replace
		}

		* Majority-rule collapse: prefer primary scope, then most-common
		* variable_label, then most-common value_label_id, with value_label_id
		* itself as the final deterministic tiebreaker. The _vf key ensures
		* the chosen variable_label text and its paired value_label_id come
		* from the same winning row, so downstream merges on value_label_id
		* pull value codes that belong to the same register as the label.
		quietly bysort variable_name variable_label: gen _lf = _N
		quietly bysort variable_name value_label_id: gen _vf = _N

		cap confirm variable _is_primary
		local has_primary = (_rc == 0)
		if `has_primary' {
			gsort variable_name -_is_primary -_lf -_vf value_label_id `_scope_group'
		}
		else {
			gsort variable_name -_lf -_vf value_label_id `_scope_group'
		}
		quietly bysort variable_name: keep if _n == 1
		quietly drop _lf _vf

		* Ensure _is_primary exists for caller
		cap confirm variable _is_primary
		if (_rc != 0) {
			gen byte _is_primary = 0
		}

		return scalar n_ambiguous = `n_ambiguous_vars'
		return local pin_hints "`pin_hints'"

		quietly save "`output'", replace
	restore

	return local merge_dta "`output'"
end




* =============================================================================
* RegiStream Manifest Loader (schema v2)
* Reads {domain}_manifest_{lang}.csv and returns scope level metadata
* via r() macros. Designed for flat key;value CSV manifests.
*
* Usage: _al_load_manifest, path(string)
*
* Returns:
*   r(domain)           - catalog domain (e.g. "scb")
*   r(schema_version)   - schema version (e.g. "2.0")
*   r(publisher)        - publisher name
*   r(release_date)     - bundle release date (ISO 8601)
*   r(languages)        - pipe-separated language list
*   r(scope_depth)      - integer depth of scope hierarchy
*   r(scope_level_N_name)  - machine-readable level name for level N
*   r(scope_level_N_title) - human-readable level title for level N
*   r(manifest_loaded)  - 1 if successfully loaded
* =============================================================================

program define _al_load_manifest, rclass
	version 16.0
	syntax , path(string)

	* Verify manifest file exists
	cap confirm file "`path'"
	if (_rc != 0) {
		* No manifest = pre-v2 bundle. Signal to caller.
		return scalar manifest_loaded = 0
		exit 0
	}

	* Read the key;value CSV
	preserve
		import delimited using "`path'", clear varnames(1) ///
			delimiter(";") stringcols(_all) encoding(utf-8)

		* Validate we have key and value columns
		cap confirm variable key
		if (_rc != 0) {
			di as error "Manifest file missing 'key' column: `path'"
			return scalar manifest_loaded = 0
			restore
			exit 198
		}
		cap confirm variable value
		if (_rc != 0) {
			di as error "Manifest file missing 'value' column: `path'"
			return scalar manifest_loaded = 0
			restore
			exit 198
		}

		* Extract required keys
		local required_keys "domain schema_version publisher bundle_release_date languages scope_depth"
		foreach k of local required_keys {
			quietly count if key == "`k'"
			if (r(N) == 0) {
				di as error "Manifest missing required key: `k'"
				return scalar manifest_loaded = 0
				restore
				exit 198
			}
			quietly levelsof value if key == "`k'", local(_val) clean
			return local `k' `"`_val'"'
		}

		* Extract scope_depth as numeric
		quietly levelsof value if key == "scope_depth", local(_depth_str) clean
		local scope_depth = real("`_depth_str'")
		if missing(`scope_depth') | `scope_depth' < 1 {
			di as error "Invalid scope_depth in manifest: `_depth_str'"
			return scalar manifest_loaded = 0
			restore
			exit 198
		}
		return scalar scope_depth_n = `scope_depth'

		* Extract scope level names and titles for each level
		forval i = 1/`scope_depth' {
			* Level name (machine-readable)
			quietly count if key == "scope_level_`i'_name"
			if (r(N) == 0) {
				di as error "Manifest missing required key: scope_level_`i'_name"
				return scalar manifest_loaded = 0
				restore
				exit 198
			}
			quietly levelsof value if key == "scope_level_`i'_name", local(_lname) clean
			return local scope_level_`i'_name `"`_lname'"'

			* Level title (human-readable, may be missing → fallback to name)
			quietly count if key == "scope_level_`i'_title"
			if (r(N) > 0) {
				quietly levelsof value if key == "scope_level_`i'_title", local(_ltitle) clean
				return local scope_level_`i'_title `"`_ltitle'"'
			}
			else {
				return local scope_level_`i'_title `"`_lname'"'
			}
		}

	restore

	return scalar manifest_loaded = 1
end


* =============================================================================
* _al_filter_scope: schema v2 scope-ladder filter (shared)
*
* Applies the canonical match ladder at each scope level of the in-memory
* dataset:
*
*     1. exact match on scope_level_N_alias   (if column exists)
*     2. exact match on scope_level_N (name)  (if column exists)
*     3. substring match on scope_level_N     (fallback when 1 & 2 miss)
*
* If any step at a level returns 0 rows, r(matched) = 0 and the caller
* surfaces the error with its own copy (different phrasing for scope-drill
* vs collapse). Short-circuits on first miss.
*
* This is the ONE place scope filtering lives; both `_autolabel_scope`
* (drills scope.dta) and `_al_collapse_v2` (drills variables.dta joined
* to scope) delegate here. Same semantics, no drift.
*
* USAGE
*   _al_filter_scope, scope(`scope') [maxdepth(int)]
*
* NOTE on quoting: pass scope by BARE macro expansion (no `"..."' compound
* wrap). In this Stata build, `string asis' in the receiver's syntax
* preserves any compound-quote delimiters we'd glue on, poisoning the
* value on every subcall. See _al_parse_scope for details.
*
* INPUTS
*   scope     - raw scope() option value (with outer quotes preserved).
*               Tokenized via gettoken so empty middle tokens are retained.
*   maxdepth  - cap on how many tokens to apply. 0 = auto-detect from the
*               scope_level_N columns present in memory. Useful when the
*               caller has an overflow token that represents a release
*               rather than a scope level (e.g. autolabel scope drill).
*
* RETURNS
*   r(matched)       - 1 if every applied level matched at least one row
*   r(n_tokens)      - tokens parsed from scope()
*   r(applied_depth) - min(n_tokens, maxdepth): levels actually filtered
*   r(failed_level)  - 1-based level where the filter went empty (0 on success)
*   r(failed_token)  - the token that failed
*   r(stok_1..stok_N) - parsed tokens, for caller-side display / click URLs
*
* PRECONDITIONS
*   Caller has preserve'd. Dataset in memory has scope_level_N (and
*   optionally scope_level_N_alias) columns as strings.
* =============================================================================

program define _al_filter_scope, rclass
	version 16.0
	syntax, [scope(string asis) maxdepth(integer 0)]

	* ── Auto-detect available scope_level_N depth if maxdepth not pinned ──
	if (`maxdepth' <= 0) {
		local _detected 0
		forval _i = 1/20 {
			cap confirm variable scope_level_`_i'
			if (_rc != 0) continue, break
			local _detected = `_i'
		}
		local maxdepth = `_detected'
	}

	* ── Delegate scope tokenization to the shared parser ──
	* Bare `scope'; see _al_parse_scope for why.
	_al_parse_scope, scope(`scope')
	local _nt = r(n_tokens)
	forval _i = 1/`_nt' {
		local _stok_`_i' `"`r(stok_`_i')'"'
		return local stok_`_i' `"`r(stok_`_i')'"'
	}
	return scalar n_tokens = `_nt'

	local _apply_n = min(`_nt', `maxdepth')
	return scalar applied_depth = `_apply_n'

	* ── Apply ladder at each level 1..applied_depth ──
	forval _i = 1/`_apply_n' {
		local _tok `"`_stok_`_i''"'
		local _ftok = lower(subinstr(`"`_tok'"', "'", "", .))
		quietly {
			gen byte _sm_exact = 0
			cap confirm string variable scope_level_`_i'_alias
			if (_rc == 0) {
				replace _sm_exact = 1 if ///
					lower(subinstr(trim(scope_level_`_i'_alias), "'", "", .)) == "`_ftok'"
			}
			cap confirm string variable scope_level_`_i'
			if (_rc == 0) {
				replace _sm_exact = 1 if _sm_exact == 0 & ///
					lower(subinstr(scope_level_`_i', "'", "", .)) == "`_ftok'"
			}

			count if _sm_exact == 1
			if (r(N) > 0) {
				keep if _sm_exact == 1
				drop _sm_exact
			}
			else {
				drop _sm_exact
				cap confirm string variable scope_level_`_i'
				if (_rc == 0) {
					gen byte _sm = ///
						strpos(lower(subinstr(scope_level_`_i', "'", "", .)), "`_ftok'") > 0
					keep if _sm == 1
					drop _sm
				}
			}
		}
		if _N == 0 {
			return scalar matched = 0
			return scalar failed_level = `_i'
			return local failed_token `"`_tok'"'
			exit 0
		}
	}

	return scalar matched = 1
	return scalar failed_level = 0
end


* =============================================================================
* _al_render_var_list: compact 2-column "variable_name → variable_label" index
*
* The shared renderer behind:
*   1. `autolabel scope` at the variable level (scope drill final leaf)
*   2. `autolabel lookup *, ..., list`      (wildcard browse)
*
* Both are answering the same question ("which variables live in this
* scope?"), so they share the same visual: one clickable name per row, a
* truncated label alongside, optional "Showing X of N / show all" footer.
*
* PRECONDITIONS
*   Current dataset has `variable_name` + `variable_label` (strings), one
*   row per variable, in the order the caller wants rendered.
*
* USAGE
*   _al_render_var_list, clickcmd(string asis)    ///
*       [clickopts(string asis) showallcmd(string asis) ///
*        search(string asis) cap(integer) NOHEADing]
*
* INPUTS
*   clickcmd    - command stem for per-variable SMCL click (e.g.
*                 `"autolabel lookup"'). Variable name is appended. Leave
*                 empty to render non-clickable names.
*   clickopts   - options appended after `cmd var,` (e.g.
*                 `"domain(scb) lang(eng) scope("LISA")"').
*   showallcmd  - full command (with options) to fire when the user
*                 clicks "Show all N" after truncation. If empty, no
*                 click appears even when truncated.
*   search      - optional filter label for the header line.
*   cap         - row cap. 0 means no cap. Default 20.
*   noheading   - suppress the "`n' variables [matching X]" header.
* =============================================================================

program define _al_render_var_list
	version 16.0
	syntax, [CLICKcmd(string asis) CLICKopts(string asis) ///
		 SHOWALLcmd(string asis) search(string asis) ///
		 cap(integer 20) NOHEADing]

	local n_vars = _N

	if (`n_vars' == 0) {
		di as text "  No variables match."
		if `"`search'"' != "" {
			di as text `"  (filter: "`search'")"'
		}
		exit 0
	}

	if ("`noheading'" == "") {
		if `"`search'"' != "" {
			di as text `"  `n_vars' variables matching "{bf:`search'}""'
		}
		else {
			di as text "  `n_vars' variables"
		}
		di as text ""
	}

	local _show_n = `n_vars'
	local _trunc 0
	if (`cap' > 0 & `n_vars' > `cap') {
		local _show_n = `cap'
		local _trunc 1
	}

	forvalues i = 1/`_show_n' {
		local _var = variable_name[`i']
		local _vlabel = variable_label[`i']

		local _var_disp = substr("`_var'", 1, 20)
		if (strlen("`_var'") > 20) local _var_disp = substr("`_var'", 1, 19) + "…"
		local _lbl_disp = substr(`"`_vlabel'"', 1, 54)
		if (strlen(`"`_vlabel'"') > 54) local _lbl_disp = substr(`"`_vlabel'"', 1, 53) + "…"

		if `"`clickcmd'"' != "" {
			local _cmd `"`clickcmd' `_var'"'
			if `"`clickopts'"' != "" local _cmd `"`_cmd', `clickopts'"'
			di as text `"  {stata `_cmd':`_var_disp'}"' _col(25) as text `"`_lbl_disp'"'
		}
		else {
			di as result `"  `_var_disp'"' _col(25) as text `"`_lbl_disp'"'
		}
	}

	if (`_trunc') {
		local _rem = `n_vars' - `_show_n'
		di as text ""
		di as text "  Showing `_show_n' of `n_vars'. `_rem' more available."
		if `"`showallcmd'"' != "" {
			di as text `"  {stata `showallcmd':Show all `n_vars'}"'
		}
	}
end


* =============================================================================
* _al_parse_scope: quote-aware tokenization of scope() option values
*
* Stata's `SCOPE(string asis)` has asymmetric quote handling:
*   - scope("LISA")                 → asis strips outer quotes → "LISA"
*   - scope("Adapted Upper School") → asis strips outer quotes → "Adapted Upper School"
*   - scope("A" "B")                → asis preserves quotes → `"A" "B"'
*
* So a simple `gettoken` loop over the stripped form whitespace-splits
* single-quoted phrases into multiple wrong tokens. This helper detects
* the no-quote case (no `"` characters anywhere in the value) and treats
* the whole value as one token. When quotes ARE present, it tokenizes
* via gettoken, which handles quoted sub-tokens correctly.
*
* USAGE
*   _al_parse_scope, scope(`scope')
*
* NOTE on quoting: pass scope by BARE macro expansion; do NOT wrap in
* `"..."' compound quotes. This Stata build's `string asis' preserves the
* compound delimiters as literal chars in the received value, so each
* subcall hop accumulates another layer. Bare passing avoids that.
*
* RETURNS
*   r(n_tokens)      - number of tokens parsed (0..20)
*   r(stok_1..stok_N) - individual token values (quotes stripped)
* =============================================================================

program define _al_parse_scope, rclass
	version 16.0
	syntax, [scope(string asis)]

	* Strip quote chars + whitespace via the `:' macro form (avoids
	* expression-time parsing of embedded quotes). If nothing survives
	* the input was effectively empty.
	local _strip `"`scope'"'
	local _strip : subinstr local _strip `"""' "", all
	local _strip = trim("`_strip'")
	if "`_strip'" == "" {
		return scalar n_tokens = 0
		exit 0
	}

	* No quote character anywhere in the value → single token.
	* Covers both scope(foo) bare and scope("foo bar baz") where asis
	* stripped the outer quotes on a single-quoted phrase.
	if (strpos(`"`scope'"', `"""') == 0) {
		return local stok_1 `"`scope'"'
		return scalar n_tokens = 1
		exit 0
	}

	* Has quote chars → multi-token form (asis preserved quotes).
	* gettoken peels each quoted sub-token, stripping surrounding quotes.
	local _rem `"`scope'"'
	local _nt 0
	while `"`_rem'"' != "" {
		gettoken _tok _rem : _rem
		local ++_nt
		return local stok_`_nt' `"`_tok'"'
		if `_nt' >= 20 continue, break
	}
	return scalar n_tokens = `_nt'
end
