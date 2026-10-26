#!/usr/bin/env python3
"""Verify that Linux package normalization preserves upstream shared libraries."""
import hashlib
import importlib.util
from pathlib import Path
import sys
import tarfile
import zipfile

spec = importlib.util.spec_from_file_location(
    "audit", Path(__file__).with_name("audit-upstream.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def verify(upstream, package, rid):
    issues = []
    expected = {}
    with tarfile.open(upstream, "r:gz") as archive:
        for member in archive:
            if not member.isfile() or ".so" not in Path(member.name).name:
                continue
            data = archive.extractfile(member).read()
            parsed = audit.elf(data)
            if not parsed or not parsed.get("soname"):
                continue
            soname = parsed["soname"]
            digest = hashlib.sha256(data).digest()
            if soname in expected and expected[soname] != digest:
                issues.append(f"upstream contains different libraries with SONAME {soname}")
            expected[soname] = digest
    if not expected:
        issues.append("upstream archive contains no ELF shared libraries to verify")
    with zipfile.ZipFile(package) as archive:
        names = set(archive.namelist())
        for soname, digest in sorted(expected.items()):
            name = f"runtimes/{rid}/native/{soname}"
            if name not in names:
                issues.append(f"package is missing upstream shared library {soname}")
            elif hashlib.sha256(archive.read(name)).digest() != digest:
                issues.append(f"packaged shared library {soname} differs from upstream")
    return issues


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: verify-native-payload.py <upstream.tar.gz> <runtime.nupkg> <rid>")
    failures = verify(*sys.argv[1:])
    if failures:
        sys.exit("FAIL: " + "\nFAIL: ".join(failures))
    print(f"Shared libraries preserved byte for byte: {sys.argv[3]}")
