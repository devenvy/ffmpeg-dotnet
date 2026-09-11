#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-packages.sh <nupkg-dir>
#
# Asserts the shape of built packages without publishing them. Every check here
# exists because the mistake it catches is silent: the package still builds,
# still restores, and only costs bandwidth or breaks a consumer downstream.
# ==============================================================================

DIR="${1:?Usage: verify-packages.sh <nupkg-dir>}"

python3 - "${DIR}" <<'PY'
import sys, zipfile, pathlib, collections, json, re

directory = pathlib.Path(sys.argv[1])
packages = sorted(directory.glob("*.nupkg"))
if not packages:
    sys.exit(f"FAIL: no .nupkg files in {directory}")

failures = []
def check(ok, message):
    if not ok:
        failures.append(message)

print(f"Verifying {len(packages)} package(s) in {directory}\n")

for pkg in packages:
    z = zipfile.ZipFile(pkg)
    names = z.namelist()
    name = pkg.name
    # The package id comes from the nuspec, not the filename: a 4-part version
    # makes "...Runtime.linux-x64.9.0.1.500.nupkg" impossible to split reliably.
    nuspec = next(n for n in names if n.endswith(".nuspec"))
    pkg_id = re.search(r"<id>([^<]+)</id>", z.read(nuspec).decode("utf-8-sig")).group(1)
    payload = [n for n in names if n.startswith("runtimes/") or n.startswith("frameworks/")]

    # Symlinks packed verbatim triple a runtime package's size, and the failure
    # is invisible: the package works, it is just 3x larger than it should be.
    crcs = collections.Counter(z.getinfo(n).CRC for n in payload if z.getinfo(n).file_size > 4096)
    dupes = sum(c - 1 for c in crcs.values() if c > 1)
    check(dupes == 0, f"{name}: {dupes} byte-identical duplicate payload file(s) — symlink normalization regressed")

    # A RID-specific publish flattens everything under native/ into the publish
    # root, so per-library version.h files collide and the build fails NETSDK1152.
    check(not any("/include/" in n for n in names), f"{name}: ships an include/ directory")

    # Anything under runtimes/**/native is a native asset NuGet copies into the
    # consumer's output. Licence text belongs at the package root instead.
    check(not any("native/" in n and "/legal/" in n for n in names),
          f"{name}: legal/ is nested under native/ and would be copied into consumer output")

    # These are file containers. A stray compiled assembly means IncludeBuildOutput leaked.
    if ".Runtime." in pkg_id or pkg_id.endswith(".Apple"):
        check(not any(n.startswith("lib/") and n.endswith(".dll") for n in names),
              f"{name}: contains a lib/*.dll — IncludeBuildOutput leaked into a native package")
        check(any(n.startswith("legal/") for n in names), f"{name}: ships no legal/ notices")
        check(bool(payload), f"{name}: has no native payload at all")

    if ".Runtime." in pkg_id:
        rid = pkg_id.split(".Runtime.")[1]
        stray = [n for n in payload if not n.startswith(f"runtimes/{rid}/native/")]
        check(not stray, f"{name}: payload outside runtimes/{rid}/native/: {stray[:3]}")

    # The whole point of the .Rid meta: RID-conditional dependencies.
    if pkg_id.endswith(".Rid"):
        check("runtime.json" in names, f"{name}: .Rid meta without a runtime.json")
        if "runtime.json" in names:
            rj = json.loads(z.read("runtime.json"))
            rids = rj.get("runtimes", {})
            check(len(rids) >= 13, f"{name}: runtime.json covers only {len(rids)} RIDs, expected 13")
            check("ios-arm64" in rids, f"{name}: runtime.json does not map ios-arm64")

    size = pkg.stat().st_size / 1048576
    print(f"  {name}  ({size:.1f} MB, {len(payload)} payload file(s))")

print()
if failures:
    print("FAILURES:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print(f"All checks passed ({len(packages)} package(s)).")
PY
