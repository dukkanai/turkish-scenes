#!/usr/bin/env python3
"""Reject an app without the compiled iPhone icon before contacting Apple."""
import plistlib
import struct
import sys
from pathlib import Path


def check_bundle(bundle):
    bundle = Path(bundle)
    info = plistlib.loads((bundle / "Info.plist").read_bytes())
    primary = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    if primary.get("CFBundleIconName", info.get("CFBundleIconName")) != "AppIcon":
        raise ValueError("Missing compiled AppIcon name in Info.plist")
    if not (bundle / "Assets.car").is_file():
        raise ValueError("Missing compiled asset catalog")
    prefixes = primary.get("CFBundleIconFiles", info.get("CFBundleIconFiles", []))
    if not isinstance(prefixes, list) or not prefixes:
        raise ValueError("Missing iPhone icon file references")
    for path in bundle.glob("*.png"):
        if not any(path.name.startswith(Path(prefix).stem) for prefix in prefixes):
            continue
        header = path.read_bytes()[:24]
        if (len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n"
                and header[12:16] == b"IHDR"
                and struct.unpack(">II", header[16:24]) == (120, 120)):
            return
    raise ValueError("Missing referenced 120x120 iPhone PNG icon")


if __name__ == "__main__":
    check_bundle(sys.argv[1])
    print("PASS: compiled AppIcon, icon metadata and 120x120 iPhone PNG")
