#!/usr/bin/env python3
"""Generate a compact Windows API link index from winmd's apis.json."""
from __future__ import annotations

import argparse
import gzip
import json
import re
import subprocess
from pathlib import Path

ARCH_MASK = {"x86": 2, "x64": 1, "arm64": 4}

_OS = {
    "windows5.0": 0x0500,
    "windows5.1": 0x0501,
    "windows5.1.2600": 0x0501,
    "windows6.0": 0x0600,
    "windows6.0.6000": 0x0600,
    "windows6.1": 0x0601,
    "windows6.2": 0x0602,
    "windows6.3": 0x0603,
    "windows8.0": 0x0602,
    "windows8.1": 0x0603,
    "windows10.0.10240": 0x0A00,
}


def arch_mask(value: str | None) -> int:
    if not value:
        return 7
    mask = 0
    for part in value.replace(" ", "").split(","):
        mask |= ARCH_MASK.get(part, 0)
    return mask or 7


def min_os(value: str | None) -> int:
    if not value:
        return 0
    if value in _OS:
        return _OS[value]
    m = re.match(r"windows(\d+)\.(\d+)", value)
    if m:
        return (int(m.group(1)) << 8) | int(m.group(2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--commit", default="")
    args = ap.parse_args()
    src = args.source
    apis_path = src / "apis.json"
    data = json.loads(apis_path.read_text())
    if not args.commit:
        try:
            args.commit = subprocess.check_output(
                ["git", "-C", str(src), "rev-parse", "HEAD"], text=True
            ).strip()
        except Exception:
            args.commit = "unknown"

    apis: dict[str, list[dict[str, object]]] = {}
    for api in data:
        name = api.get("name")
        dll = api.get("dll")
        if not name or not dll:
            continue
        entries = apis.setdefault(name, [])
        item = {
            "dll": dll,
            "callconv": api.get("callconv", "winapi"),
            "min_os": min_os(api.get("os")),
            "arch_mask": arch_mask(api.get("arch")),
        }
        if item not in entries:
            entries.append(item)
    out = {
        "schema": 1,
        "source": "https://github.com/howmp/winmd",
        "upstream_commit": args.commit,
        "license": "MIT",
        "apis": apis,
    }
    raw = json.dumps(out, separators=(",", ":"), sort_keys=True).encode()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "wb") as raw_file:
        with gzip.GzipFile(filename="", fileobj=raw_file, mode="wb", compresslevel=9, mtime=0) as fh:
            fh.write(raw)
    print(f"wrote {args.out} ({args.out.stat().st_size} bytes, {len(apis)} APIs), commit={args.commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
