#!/usr/bin/env python3
"""Exercise shared-library preservation using real ELF metadata and archives."""
import importlib.util
import io
from pathlib import Path
import struct
import tarfile
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "payload", Path(__file__).with_name("verify-native-payload.py"))
payload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(payload)


def shared_library(soname):
    """A minimal ELF64 DSO with a real DT_SONAME and no code to execute."""
    strings = b"\0" + soname.encode() + b"\0"
    data = bytearray(448)
    struct.pack_into("<16sHHIQQQIHHHHHH", data, 0,
                     b"\x7fELF\x02\x01\x01" + b"\0" * 9,
                     3, 62, 1, 0, 0, 256, 0, 64, 56, 0, 64, 3, 0)
    data[64:64 + len(strings)] = strings
    struct.pack_into("<qQqQ", data, 128, 14, 1, 0, 0)
    struct.pack_into("<IIQQQQIIQQ", data, 320,
                     0, 3, 0, 0, 64, len(strings), 0, 0, 1, 0)
    struct.pack_into("<IIQQQQIIQQ", data, 384,
                     0, 6, 0, 0, 128, 32, 1, 0, 8, 16)
    return bytes(data)


class NativePayloadTests(unittest.TestCase):
    def check_payload(self, source, packaged):
        with tempfile.TemporaryDirectory() as work:
            archive = Path(work) / "upstream.tar.gz"
            package = Path(work) / "runtime.nupkg"
            with tarfile.open(archive, "w:gz") as output:
                for name, data in source.items():
                    member = tarfile.TarInfo(name)
                    member.size = len(data)
                    output.addfile(member, io.BytesIO(data))
            with zipfile.ZipFile(package, "w") as output:
                for name, data in packaged.items():
                    output.writestr(f"runtimes/linux-x64/native/{name}", data)
            return payload.verify(archive, package, "linux-x64")

    def test_normalized_soname_preserves_exact_upstream_bytes(self):
        library = shared_library("libsupport.so.1")
        self.assertEqual(self.check_payload(
            {"libsupport.so.1.2.3": library}, {"libsupport.so.1": library}), [])

    def test_primary_ffmpeg_library_does_not_hide_missing_dependency(self):
        primary = shared_library("libavutil.so.60")
        dependency = shared_library("libsupport.so.1")
        issues = self.check_payload(
            {"libavutil.so.60.1.0": primary, "libsupport.so.1.2.3": dependency},
            {"libavutil.so.60": primary})
        self.assertEqual(len(issues), 1)
        self.assertIn("libsupport.so.1", issues[0])

    def test_unversioned_link_name_does_not_satisfy_runtime_soname(self):
        library = shared_library("libsupport.so.1")
        self.assertTrue(self.check_payload(
            {"libsupport.so.1.2.3": library}, {"libsupport.so": library}))

    def test_changed_library_bytes_fail(self):
        library = shared_library("libsupport.so.1")
        issues = self.check_payload(
            {"libsupport.so.1.2.3": library}, {"libsupport.so.1": library + b"changed"})
        self.assertEqual(len(issues), 1)
        self.assertIn("differs", issues[0])

    def test_wrong_source_archive_cannot_pass_without_checking_libraries(self):
        self.assertTrue(self.check_payload({"README": b"not a runtime"}, {}))


if __name__ == "__main__":
    unittest.main()
