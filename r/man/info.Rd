\name{info}
\alias{info}
\title{Autolabel Configuration + Cache Snapshot}
\description{
Prints and returns a compact summary of the autolabel environment:
installed package versions, cache directories, and the four config
switches (\code{internet_access}, \code{usage_logging},
\code{telemetry_enabled}, \code{auto_update_check}).

R port of the Stata \code{autolabel info} subcommand and Python
\code{registream.autolabel.info()}.
}
\usage{
info(directory = NULL)
}
\arguments{
\item{directory}{Override the RegiStream config / cache directory.
  Defaults to \code{REGISTREAM_DIR} env var, then the \code{cache_dir}
  config field, then \code{tools::R_user_dir("registream", "cache")}.}
}
\value{
Invisibly, a named list with components \code{autolabel_version},
\code{registream_version}, \code{registream_dir},
\code{autolabel_cache}, and \code{config} (the parsed
\code{registream_config} record). Prints a formatted summary as a
side effect.
}
\seealso{
\code{\link[registream]{rs_info}}, \code{\link{autolabel}},
\code{\link{cite}}
}
\keyword{utilities}
