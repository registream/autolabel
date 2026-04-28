#!/usr/bin/env bash
# Guards the PEP 420 namespace package invariant for the autolabel repo's
# Python distribution. The `registream/` directory shipped by
# registream-autolabel must NOT contain an `__init__.py`; it is a namespace
# package shared with sibling distributions (registream-core, ...).
#
# Wire this script into CI for the `autolabel` repo.
set -euo pipefail

cd "$(dirname "$0")"

violator="registream-autolabel/src/registream/__init__.py"
if [ -f "$violator" ]; then
    echo "ERROR: $violator exists."
    echo "registream-autolabel must remain a PEP 420 namespace contributor: no top-level __init__.py."
    exit 1
fi

echo "registream-autolabel namespace check OK."
