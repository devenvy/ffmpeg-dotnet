#!/usr/bin/env python3
"""Assert the shape of built packages without publishing them.

Every check here exists because the mistake it catches is silent: the package
still builds, still restores, and only costs bandwidth or breaks a consumer
downstream.

Kept as its own file rather than a heredoc inside the shell wrapper, because
`python3 - <<EOF` discards the interpreter's exit code - the wrapper reported
success even when this printed FAILURES.
"""
import sys, zipfile, pathlib, collections, json, re, struct, importlib.util

# The PE parser and the Windows system-DLL allowlist already exist in
# audit-upstream.py and are loaded rather than duplicated, so the allowlist has
# one definition to keep current. The hyphen in the filename rules out a plain
# import.
_spec = importlib.util.spec_from_file_location(
    "_audit", pathlib.Path(__file__).parent / "audit-upstream.py")
_audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_audit)
_pe, _SYSTEM_DLL = _audit.pe, _audit.SYSTEM_DLL

directory = pathlib.Path(sys.argv[1])
packages = sorted(directory.glob("*.nupkg"))
if not packages:
    sys.exit(f"FAIL: no .nupkg files in {directory}")

failures = []
all_ids = set()
all_metas = {}
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
    all_ids.add(pkg_id)
    payload = [n for n in names if n.startswith("runtimes/") or n.startswith("frameworks/")]

    # Symlinks packed verbatim triple a runtime package's size, and the failure
    # is invisible: the package works, it is just 3x larger than it should be.
    #
    # RID-native packages only. An xcframework carries its headers identically in
    # the device and simulator slices, so duplicates there are structural to
    # Apple's format rather than a normalization regression.
    if payload and "frameworks/" not in "".join(payload):
        crcs = collections.Counter(z.getinfo(n).CRC for n in payload if z.getinfo(n).file_size > 4096)
        dupes = sum(c - 1 for c in crcs.values() if c > 1)
        check(dupes == 0, f"{name}: {dupes} byte-identical duplicate payload file(s) — symlink normalization regressed")

    # Apple instead gets a build-residue check: debug symbols and bitcode maps
    # are link-time artifacts that would be dead weight in a shipped app.
    # Apple packages ship one slice as plain .framework bundles, split out of
    # upstream's merged .xcframework so each RID downloads only what it can use.
    if any(n.startswith("frameworks/") for n in names):
        rid = pkg_id.rsplit(".", 1)[1]
        residue = [n for n in names if ".dSYM/" in n or n.endswith(".bcsymbolmap")]
        check(not residue, f"{name}: ships build residue: {residue[:3]}")
        check(not any(".xcframework" in n for n in names),
              f"{name}: still ships a merged .xcframework rather than one slice")
        # The slice directory name is gone after splitting, so "which slice is
        # this?" can only be answered from the Mach-O LC_BUILD_VERSION platform.
        # Catalyst ships universal, so fat binaries are walked per architecture.
        CPU = {0x01000007: "x86_64", 0x0100000C: "arm64"}

        def mach_platforms(data):
            out = []
            if len(data) < 8:
                return out
            if struct.unpack_from(">I", data, 0)[0] in (0xCAFEBABE, 0xCAFEBABF):
                for i in range(struct.unpack_from(">I", data, 4)[0]):
                    cpu, _sub, off = struct.unpack_from(">III", data, 8 + i * 20)[:3]
                    out += mach_platforms(data[off:])
                return out
            if struct.unpack_from("<I", data, 0)[0] not in (0xFEEDFACF, 0xCFFAEDFE):
                return out
            ncmds = struct.unpack_from("<I", data, 16)[0]
            off = 32
            for _ in range(min(ncmds, 4096)):
                cmd, sz = struct.unpack_from("<II", data, off)
                if sz == 0:
                    break
                if cmd == 0x32:          # LC_BUILD_VERSION
                    return [struct.unpack_from("<I", data, off + 8)[0]]
                off += sz
            return out

        want = {"ios-arm64": 2, "iossimulator-arm64": 7,
                "maccatalyst-arm64": 6, "maccatalyst-x64": 6}.get(rid)
        if want:
            binaries = [n for n in names
                        if n.startswith("frameworks/") and "." not in n.rsplit("/", 1)[-1]]
            checked = 0
            for b in binaries[:3]:
                got = mach_platforms(z.read(b))
                if not got:
                    continue
                checked += 1
                check(all(g == want for g in got),
                      f"{name}: {b} has Mach-O platform(s) {got}, expected {want} for {rid}")
            check(checked > 0, f"{name}: found no Mach-O binary to verify the slice platform")
        fw = {n.split("/")[1] for n in names if n.startswith("frameworks/") and n.count("/") > 1}
        check(len(fw) >= 6, f"{name}: only {len(fw)} frameworks, expected at least 6")

    # A RID-specific publish flattens everything under native/ into the publish
    # root, so per-library version.h files collide and the build fails NETSDK1152.
    check(not any("/include/" in n for n in names), f"{name}: ships an include/ directory")

    # A PackagePath ending in "/" makes NuGet append the file's whole relative
    # path, so adding %(RecursiveDir) to it emits A/B/C/A/B/C. The package still
    # restores, the files are just unreachable at the paths anything expects.
    def doubled(path):
        seg = path.split("/")[:-1]
        return any(seg[i:i + k] == seg[i + k:i + 2 * k]
                   for k in range(1, len(seg) // 2 + 1)
                   for i in range(len(seg) - 2 * k + 1))
    bad = [n for n in names if doubled(n)]
    check(not bad, f"{name}: doubled path segments (PackagePath/%(RecursiveDir) bug): {bad[:2]}")

    # Anything under runtimes/**/native is a native asset NuGet copies into the
    # consumer's output. Licence text belongs at the package root instead.
    check(not any("native/" in n and "/legal/" in n for n in names),
          f"{name}: legal/ is nested under native/ and would be copied into consumer output")

    # These are file containers. A stray compiled assembly means IncludeBuildOutput leaked.
    if payload:
        check(not any(n.startswith("lib/") and n.endswith(".dll") for n in names),
              f"{name}: contains a lib/*.dll — IncludeBuildOutput leaked into a native package")
        check(any(n.startswith("legal/") for n in names), f"{name}: ships no legal/ notices")
        check(bool(payload), f"{name}: has no native payload at all")

    if payload and "frameworks/" not in "".join(payload):
        rid = pkg_id.rsplit(".", 1)[1]
        stray = [n for n in payload if not n.startswith(f"runtimes/{rid}/native/")]
        check(not stray, f"{name}: payload outside runtimes/{rid}/native/: {stray[:3]}")

    # A Windows library that hard-imports a DLL the package does not ship and
    # Windows does not guarantee cannot be loaded at all on a host lacking it:
    # the loader resolves the whole import table at process start, so a single
    # missing dependency means ffmpeg.exe will not launch, with no way for the
    # consumer to catch it. This is how a build machine's incidental SDK leaks
    # into a package - the artifact runs fine where it was built and nowhere
    # else. Delay imports are exempt: they resolve on first use, so they cost a
    # feature rather than the process.
    if pkg_id.rsplit(".", 1)[1].startswith("win-"):
        shipped = {n.rsplit("/", 1)[-1].lower()
                   for n in payload if n.lower().endswith((".dll", ".exe"))}
        for entry in payload:
            if not entry.lower().endswith((".dll", ".exe")):
                continue
            parsed = _pe(z.read(entry))
            if not parsed:
                continue
            foreign = sorted({d for d in parsed["imports"]
                              if d.lower() not in shipped and not _SYSTEM_DLL.match(d)})
            check(not foreign,
                  f"{name}: {entry.rsplit('/', 1)[-1]} hard-imports "
                  f"{foreign}, which the package does not ship and Windows does "
                  f"not guarantee - it will fail to load on a host without it")

    # The .All meta must reach every platform, or a RID-less consumer silently
    # loses one.
    if pkg_id.endswith(".Runtime.All"):
        nuspec_xml = z.read(nuspec).decode("utf-8-sig")
        deps = re.findall(r'<dependency id="([^"]+)"', nuspec_xml)
        platforms = [d for d in deps if not d.endswith("DevEnvy.FFmpeg.Binaries")]
        check(not payload, f"{name}: .All should carry no binaries of its own")
        all_metas[pkg_id] = platforms

    size = pkg.stat().st_size / 1048576
    print(f"  {name}  ({size:.1f} MB, {len(payload)} payload file(s))")

# Every packed platform must be reachable through its variant's .All, or a
# RID-less consumer silently loses one.
#
# The comparison is against gen-nuspec.sh's canonical RID list, not against
# whatever happens to sit in the directory. CI packs a handful of representative
# RIDs on purpose, so "listed but not packed" is the normal case there and
# asserting the two sets match fails every correct CI run. Reading the canonical
# list instead keeps the check meaningful on a subset feed and makes it stricter
# on a full one: a .All that drifts from the shipped platform set is caught even
# when the drift happens to agree with what was packed.
gen = (pathlib.Path(__file__).parent / "gen-nuspec.sh").read_text(encoding="utf-8")
canonical = set(re.search(r"ALL_RIDS=\((.*?)\)", gen, re.S).group(1).split())
if not canonical:
    failures.append("could not parse ALL_RIDS out of gen-nuspec.sh")

# --expect-complete is passed by the release workflow, where a short feed means
# a platform silently failed to pack rather than a deliberate subset.
expect_complete = "--expect-complete" in sys.argv[2:]

for meta_id, listed in all_metas.items():
    variant = meta_id.split(".")[-3]
    prefix = f"DevEnvy.FFmpeg.Binaries.{variant}.Runtime."
    listed_rids = {d[len(prefix):] for d in listed if d.startswith(prefix)}
    packed = {i[len(prefix):] for i in all_ids if i.startswith(prefix) and i != meta_id}

    drift = listed_rids ^ canonical
    check(not drift,
          f"{meta_id}: .All dependencies do not match gen-nuspec.sh ALL_RIDS: "
          f"missing {sorted(canonical - listed_rids)}, unexpected {sorted(listed_rids - canonical)}")

    orphaned = packed - listed_rids
    check(not orphaned,
          f"{meta_id}: packed but unreachable through .All: {sorted(orphaned)}")

    if expect_complete:
        check(not (canonical - packed),
              f"{meta_id}: release feed is missing platforms: {sorted(canonical - packed)}")
    elif canonical - packed:
        print(f"  note: {variant} feed is a subset, "
              f"{len(packed)}/{len(canonical)} platforms packed")

print()
if failures:
    print("FAILURES:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print(f"All checks passed ({len(packages)} package(s)).")
