#!/usr/bin/env python3
"""Reject an app without the compiled iPhone icon before contacting Apple."""
import plistlib
import struct
import sys
from pathlib import Path


def png_dimensions(path):
    # iOS Release PNGs may have Apple's CgBI chunk before IHDR. Do not assume
    # IHDR is at byte 12 as it is in ordinary simulator PNGs.
    with Path(path).open("rb") as image:
        if image.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("Invalid PNG signature")
        for index in range(2):
            header = image.read(8)
            if len(header) != 8:
                raise ValueError("Truncated PNG chunk header")
            length, kind = struct.unpack(">I4s", header)
            if kind == b"IHDR" and length == 13:
                payload = image.read(13)
                if len(payload) != 13 or len(image.read(4)) != 4:
                    raise ValueError("Truncated PNG IHDR")
                return struct.unpack(">II", payload[:8])
            if index == 0 and kind == b"CgBI" and length <= 16:
                if len(image.read(length + 4)) != length + 4:
                    raise ValueError("Truncated Apple PNG header")
                continue
            raise ValueError("Missing PNG IHDR after optional Apple CgBI chunk")
    raise ValueError("Missing PNG dimensions")


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
        if png_dimensions(path) == (120, 120):
            with path.open("rb") as image:
                first_chunk = image.read(16)[12:16].decode("ascii", errors="replace")
            print(f"PASS: {path.name} is 120x120; first PNG chunk is {first_chunk}")
            return
    raise ValueError("Missing referenced 120x120 iPhone PNG icon")


if __name__ == "__main__":
    check_bundle(sys.argv[1])
    print("PASS: compiled AppIcon, icon metadata and 120x120 iPhone PNG")
