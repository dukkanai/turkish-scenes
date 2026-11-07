import importlib.util
import os
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "ci" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check_result = load("run_altool").check_result
check_bundle = load("check_app_bundle").check_bundle


def png(width=120, height=120, optimized=False):
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload)))
    header = b"\x89PNG\r\n\x1a\n"
    if optimized:
        header += chunk(b"CgBI", b"\x40\xa0\x60\x82")
    return header + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))


class AltoolChecks(unittest.TestCase):
    def test_cli_rejects_zero_exit_error_and_accepts_explicit_success(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "xcrun"
            fake.write_text('#!/bin/sh\nprintf "%s\\n" "$FAKE_ALTOOL_OUTPUT"\nexit 0\n')
            fake.chmod(0o700)
            for output, expected in [("UPLOAD FAILED with 2 errors", 1),
                                      ("UPLOAD SUCCEEDED", 0), ("Working...", 1)]:
                env = dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"],
                           FAKE_ALTOOL_OUTPUT=output)
                result = subprocess.run([sys.executable, str(ROOT / "ci/run_altool.py"), "upload"],
                                        env=env, capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_success_requires_explicit_matching_confirmation(self):
        for operation, output in [("upload", "UPLOAD SUCCEEDED"),
                                  ("upload", "No errors uploading package"),
                                  ("validate", "VERIFY SUCCEEDED"),
                                  ("validate", "No errors validating archive")]:
            with self.subTest(operation=operation, output=output):
                check_result(output, 0, operation)

    def test_zero_exit_apple_rejection_fails(self):
        for operation in ("validate", "upload"):
            for output in ("UPLOAD FAILED with 2 errors", "ERROR: Validation failed (409)",
                           "VERIFY SUCCEEDED\nERROR: rejected", "UPLOAD SUCCEEDED\nUPLOAD FAILED"):
                with self.subTest(operation=operation, output=output):
                    with self.assertRaises(ValueError):
                        check_result(output, 0, operation)

    def test_nonzero_unknown_empty_and_wrong_operation_fail(self):
        for output, code, operation in [("UPLOAD SUCCEEDED", 1, "upload"),
                                        ("", 0, "upload"),
                                        ("Working...", 0, "upload"),
                                        ("VERIFY SUCCEEDED", 0, "upload"),
                                        ("UPLOAD SUCCEEDED", 0, "validate")]:
            with self.subTest(output=output, code=code):
                with self.assertRaises(ValueError):
                    check_result(output, code, operation)


class BundleChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name)
        self.info = {"CFBundleIcons": {"CFBundlePrimaryIcon": {
            "CFBundleIconName": "AppIcon", "CFBundleIconFiles": ["AppIcon60x60"]}}}
        self.write_info()
        (self.bundle / "Assets.car").write_bytes(b"fixture")
        self.icon = self.bundle / "AppIcon60x60@2x.png"
        self.icon.write_bytes(png())

    def write_info(self):
        (self.bundle / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_valid_metadata_and_icon(self):
        check_bundle(self.bundle)

    def test_apple_optimized_release_png(self):
        self.icon.write_bytes(png(optimized=True))
        check_bundle(self.bundle)

    def test_missing_catalog(self):
        (self.bundle / "Assets.car").unlink()
        with self.assertRaises(ValueError):
            check_bundle(self.bundle)

    def test_missing_icon_name(self):
        del self.info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"]
        self.write_info()
        with self.assertRaises(ValueError):
            check_bundle(self.bundle)

    def test_wrong_dimensions_or_truncated_icon(self):
        for data in (b"not png", png(180, 180), png(180, 180, optimized=True),
                     png()[:24], png(optimized=True)[:22],
                     b"\x89PNG\r\n\x1a\n" + struct.pack(">I4s", 2**31, b"CgBI")):
            self.icon.write_bytes(data)
            with self.assertRaises(ValueError):
                check_bundle(self.bundle)

    def test_unreferenced_icon_is_not_accepted(self):
        self.info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconFiles"] = ["OtherIcon"]
        self.write_info()
        with self.assertRaises(ValueError):
            check_bundle(self.bundle)


if __name__ == "__main__":
    unittest.main()
