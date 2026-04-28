# RegiStream citation text -- parity with Stata `autolabel cite` and
# Python `registream.autolabel.cite`. Data sourced from the generated
# `_citation_data.R` (produced from `registream/citations.yaml` by
# `registream/tools/render_citations.py write-r`).
#
# cite() returns the full Stata-style block (header rules, "To cite
# autolabel..." lead-in, versioned APA line). cite_bibtex() returns
# the BibTeX entry. The installed package version is read via
# utils::packageVersion() so every call reflects the in-process build.

.CITATION_HLINE <- strrep("-", 60)


#' @export
cite <- function(versioned = TRUE) {
  apa <- if (isTRUE(versioned)) {
    sprintf(.CITATION_APA_VERSIONED_TEMPLATE, .installed_version())
  } else {
    .CITATION_APA
  }

  lines <- c(
    "",
    .CITATION_HLINE,
    "Citation",
    .CITATION_HLINE,
    "",
    "To cite autolabel in publications, please use:",
    "",
    paste0("  ", apa),
    ""
  )
  paste(lines, collapse = "\n")
}


#' @export
cite_bibtex <- function(versioned = TRUE) {
  if (!isTRUE(versioned)) return(.CITATION_BIBTEX_PLAIN)
  gsub("{{VERSION}}", .installed_version(),
       .CITATION_BIBTEX_VERSIONED_TEMPLATE, fixed = TRUE)
}


.installed_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("autolabel")),
    error = function(e) "X.Y.Z"
  )
}
