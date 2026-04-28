"""Command-line entry point for ``python -m registream.autolabel``.

Mirrors the Stata ``autolabel`` meta-subcommand surface. Thin dispatcher:
each subcommand calls an existing module-level function and prints the
result.

Subcommands
-----------

- ``version``: print ``registream-autolabel <version>``
- ``info``   : print the ``registream.autolabel.info()`` dict as a table
- ``cite``   : print the APA citation (sourced from ``citations.yaml``)
"""

from __future__ import annotations

import argparse
import sys
from importlib.metadata import PackageNotFoundError, version


def _cmd_version() -> int:
    try:
        v = version("registream-autolabel")
    except PackageNotFoundError:
        print("registream-autolabel (not installed)", file=sys.stderr)
        return 1
    print(f"registream-autolabel {v}")
    return 0


def _cmd_info() -> int:
    from registream.autolabel import info

    data = info()
    width = max((len(str(k)) for k in data), default=0)
    for key, value in data.items():
        if isinstance(value, dict):
            print(f"{key}:")
            inner_width = max((len(str(k)) for k in value), default=0)
            for subkey, subvalue in value.items():
                print(f"  {subkey:<{inner_width}}  {subvalue}")
        else:
            print(f"{key:<{width}}  {value}")
    return 0


def _cmd_cite() -> int:
    from registream.autolabel import cite

    print(cite())
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m registream.autolabel",
        description="autolabel: command-line access to version, info, and citation.",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("version", help="print the installed registream-autolabel version")
    sub.add_parser("info", help="print the autolabel configuration snapshot")
    sub.add_parser("cite", help="print the project citation (APA)")

    args = parser.parse_args(argv)
    if args.command == "version":
        return _cmd_version()
    if args.command == "info":
        return _cmd_info()
    if args.command == "cite":
        return _cmd_cite()
    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
