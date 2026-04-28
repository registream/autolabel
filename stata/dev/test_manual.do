*** -------
* start with clean install, no registream dir, nothing
cap ado uninstall autolabel
cap ado uninstall registream

* Adjust to your local sibling-repo root if not the default below.
* (Layout: $REGISTREAM_ORG/{registream, autolabel, datamirror}.)
if "$REGISTREAM_ORG" == "" global REGISTREAM_ORG "~/Github/registream-org"

* Install autolabel
net install registream, from("http://localhost:5000/install/stata") replace
net install autolabel,  from("http://localhost:5000/install/stata") replace
* net install datamirror, from("https://registream.org/install/stata") replace


* Activate host override (redirects API calls to localhost:5000)
do "$REGISTREAM_ORG/registream/stata/dev/host_override.do"


* lookups
autolabel lookup carb, domain(scb) lang(eng)
autolabel lookup ssyk*, domain(scb) lang(swe)
autolabel lookup ssyk, domain(scb) lang(swe) detail

* browse scopes
autolabel scope, domain(scb) lang(eng)
autolabel scope lisa, domain(scb) lang(eng)
autolabel scope election, domain(scb) lang(eng)
autolabel scope kommunfullmäktige, domain(scb) lang(swe)

* waterfall — search → drill → variable lookup
autolabel scope lisa, domain(scb) lang(eng)
autolabel scope LISA, domain(scb) lang(eng)
autolabel lookup ssyk, domain(scb) lang(eng) scope(LISA)
autolabel lookup ssyk, domain(scb) lang(eng) scope(LISA) detail
autolabel lookup kon, domain(scb) lang(eng) detail


use "$REGISTREAM_ORG/autolabel/examples/lisa.dta" , clear

* label variables — inference should kick in
autolabel variables, domain(scb) lang(eng)

* label values
autolabel values, domain(scb) lang(eng)

* reload and pin scope
use "$REGISTREAM_ORG/autolabel/examples/lisa.dta" , clear
autolabel variables, domain(scb) lang(eng) scope(LISA)


autolabel scope, domain(scb) lang(eng)
autolabel scope, domain(scb) lang(swe)
autolabel scope, domain(dst) lang(eng)
autolabel scope, domain(dst) lang(dan)
autolabel scope, domain(ssb) lang(nor)
autolabel scope, domain(ssb) lang(eng)
autolabel scope, domain(sos) lang(swe)
autolabel scope, domain(sos) lang(eng)
autolabel scope, domain(fk) lang(swe)
autolabel scope, domain(fk) lang(eng)
autolabel scope, domain(hagstofa) lang(isl)
autolabel scope, domain(hagstofa) lang(eng)
