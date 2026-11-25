"""LICENSES.md: what the iOS app ships, with licences. Apple's frameworks
are part of iOS; WebRTC is a reviewed binary (WebRTC/Package.swift); the
end-to-end library and the Rust crates inside it come from ci/e2e-lib.sh
(.deps/e2e/crates.txt and rev).

    python3 tools/licences.py > LICENSES.md
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    e2e = os.path.join(ROOT, ".deps", "e2e")
    try:
        rows = [line.rstrip("\n").split("|") for line in open(os.path.join(e2e, "crates.txt")) if line.strip()]
        rev = open(os.path.join(e2e, "rev")).read().strip()
    except OSError:
        print("licences: .deps/e2e is missing: run ci/e2e-lib.sh", file=sys.stderr)
        return 1
    print("# Licences of what the Ortus iOS app ships\n")
    print("The app is MIT OR Apache-2.0. Apple's system frameworks (SwiftUI, Foundation, CryptoKit, Security, LocalAuthentication) are part of iOS and not shipped in it. It carries:\n")
    print("- **WebRTC** (BSD-3-Clause), Google's, for native calls: the reviewed binary that `WebRTC/Package.swift` names by checksum (the owner's exception of 22 November 2026).")
    print(f"- **The end-to-end library** libortus_e2e_ffi (MIT OR Apache-2.0), from ortus-chat `phones/e2e` at {rev}, and the {len(rows)} Rust crates inside it, below. The MPL-2.0 ones are allowed for this library only, unmodified (the owner's decision of 25 November 2026); their source is at crates.io under the versions named.\n")
    print("`ci/check.sh` fails if another third-party package is added, until its licence is reviewed and listed here.\n")
    print("| Crate | Version | Licence |\n| --- | --- | --- |")
    for name, version, lic in rows:
        print(f"| {name} | {version} | {lic} |")
    unknown = [r for r in rows if not r[2]]
    for name, version, _ in unknown:
        print(f"licences: the crate {name} {version} names no licence", file=sys.stderr)
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
