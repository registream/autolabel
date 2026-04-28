\name{rs_update_datasets}
\alias{rs_update_datasets}
\alias{print.rs_download_result}
\title{Download and Cache RegiStream Metadata Bundles}
\usage{
rs_update_datasets(domain, lang, version = "latest", force = FALSE,
                   directory = NULL)
}
\arguments{
  \item{domain}{Dataset domain (e.g. \code{"scb"}).}
  \item{lang}{Language code (e.g. \code{"eng"} or \code{"swe"}).}
  \item{version}{Dataset version, default \code{"latest"}. Resolves to
    a concrete \code{YYYYMMDD} value via the \code{/info} endpoint.}
  \item{force}{If \code{TRUE}, re-download even if all three cache
    files already exist.}
  \item{directory}{Optional base directory. Defaults to
    \code{REGISTREAM_DIR} if set, otherwise
    \code{tools::R_user_dir("registream", "cache")}.}
}
\description{
Download a bundled ZIP of variables, value-labels, and registers
metadata for a \code{(domain, lang, version)} triple from the
RegiStream API, extract each file type, validate the schema, and
write the cache files (DTA + CSV) plus a \code{datasets.csv} registry
entry. Cross-compatible with the Stata and Python clients -- all
three write and read the same on-disk formats.
}
\value{
An \code{rs_download_result} list with fields \code{domain},
\code{lang}, \code{files} (freshly downloaded), \code{skipped}
(already cached), and \code{failed} (filename + error-message pairs).
The object has a \code{print} method.
}
\keyword{datasets}
