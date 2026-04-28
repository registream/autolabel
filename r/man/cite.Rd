\name{cite}
\alias{cite}
\alias{cite_bibtex}
\title{Citation Output for the autolabel Package}
\description{
Produce the citation information for \pkg{autolabel}. \code{cite()}
returns the full Stata-style citation block (horizontal rules,
"To cite autolabel..." lead-in, and the versioned APA line). The
output matches \code{autolabel cite} in Stata and
\code{python -m registream.autolabel cite} in Python byte-for-byte,
so users see the same thing across clients.

\code{cite_bibtex()} returns the BibTeX entry for the installed
version.

Citation strings are generated from the single-source
\code{registream/citations.yaml} by
\code{registream/tools/render_citations.py} and stored in
\code{R/citation_data.R}. Do not hand-edit that file -- regenerate
from YAML.
}
\usage{
cite(versioned = TRUE)

cite_bibtex(versioned = TRUE)
}
\arguments{
\item{versioned}{If \code{TRUE} (default), include the installed
  package version in the APA line. If \code{FALSE}, emit the short /
  version-free form.}
}
\value{
A single multi-line character string. \code{cite()} returns the full
citation block (print with \code{cat()} for readable output; the raw
string includes newline separators). \code{cite_bibtex()} returns a
\code{@software\{...\}} BibTeX entry.
}
\examples{
\dontrun{
cat(cite())
cat(cite_bibtex())
}
}
\seealso{
The core-package counterparts \code{rs_cite()} and
\code{rs_cite_bibtex()} from \pkg{registream};
\code{\link[utils]{citation}} (generic R citation lookup, served
by \code{inst/CITATION}).
}
\keyword{utilities}
