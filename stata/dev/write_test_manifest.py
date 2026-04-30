#!/usr/bin/env python3
"""Write a stub package_manifest.yaml for end-to-end heartbeat tests.

Usage:
    python3 write_test_manifest.py <output_path> registream=X autolabel=Y datamirror=Z

Overwrites <output_path> with a minimal but well-formed manifest where each
package's `latest:` reports the requested version. Sufficient for the
`/api/v1/heartbeat` update-detection path (reads `latest` directly via
`get_package_latest_versions`).

Test 30 (`30_update_notification.do`) calls this between sub-tests to bump the
server's reported version, validate detection, then restore from a `.bak`.
"""
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 3 or any(a in ("-h", "--help") for a in sys.argv):
        print(__doc__)
        sys.exit(2)
    out = Path(sys.argv[1])
    pairs = [arg.split("=", 1) for arg in sys.argv[2:]]
    if any(len(p) != 2 for p in pairs):
        sys.stderr.write("Each pkg arg must be name=version\n")
        sys.exit(2)
    pkgs = dict(pairs)

    lines = ["schema_version: 1", "", "packages:"]
    for name, ver in pkgs.items():
        role = "core" if name == "registream" else "module"
        lines += [
            "",
            f"  {name}:",
            f"    role: {role}",
            f'    latest: "{ver}"',
            "    versions:",
            f'      "{ver}":',
            '        released: "2026-04-12"',
        ]
    out.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
