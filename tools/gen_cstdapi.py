#!/usr/bin/env python3
"""Generate cinterp's C-standard-library link database from cstdapi.

This is a build-time tool. The generated JSON is checked in; the compiler and
runtime never need network access or the upstream repository.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


def read_names(path: Path) -> list[str]:
    out: list[str] = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(\)", line)
        if m:
            out.append(m.group(1))
    return out


def read_plain(path: Path) -> list[str]:
    out: list[str] = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name = line.split()[0]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
            out.append(name)
    return out


def read_spec(path: Path) -> dict[str, str]:
    """Return canonical export name -> explicit alias, if the spec has one."""
    exports: dict[str, str] = {}
    if not path.is_file():
        return exports
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line.startswith("@ ") or line.startswith("@ stub"):
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        symbol = None
        alias = None
        for part in parts[2:]:
            if "(" in part and symbol is None:
                symbol = part.split("(", 1)[0]
            elif symbol is not None and not part.startswith("-"):
                alias = part
        if symbol:
            exports[symbol] = alias or symbol
    return exports


def variants(name: str, target: str, spec: dict[str, str]) -> list[str]:
    out: list[str] = []
    if target.endswith("linux"):
        out.extend([name])
    else:
        if name == "snprintf":
            out.extend(["snprintf", "_snprintf"])
        elif name == "vsnprintf":
            out.extend(["vsnprintf", "_vsnprintf"])
        else:
            if not name.startswith("_"):
                out.append("_" + name)
            out.append(name)
        if name in spec:
            out.append(spec[name])
        if not name.startswith("_"):
            out.append(name)
    dedup: list[str] = []
    for item in out:
        if item and item not in dedup:
            dedup.append(item)
    return dedup[:4]


def providers(name: str, target: str, msvcrt_spec: dict[str, str], ucrt_spec: dict[str, str]) -> list[dict[str, object]]:
    if target.endswith("linux"):
        return [
            {"kind": 1, "lib": "libc.so.6", "symbol": name},
            {"kind": 1, "lib": "libm.so.6", "symbol": name},
        ]
    if target.endswith("windows"):
        candidates: list[dict[str, object]] = []
        # UCRT first; it is the modern target. Keep decorated fallbacks for x86.
        for sym in variants(name, target, ucrt_spec):
            candidates.append({"kind": 1, "lib": "ucrtbase.dll", "symbol": sym})
        for sym in variants(name, target, msvcrt_spec):
            candidates.append({"kind": 1, "lib": "msvcrt.dll", "symbol": sym})
        candidates.append({"kind": 1, "lib": "ntdll.dll", "symbol": name})
        dedup: list[dict[str, object]] = []
        seen: set[tuple[str, str]] = set()
        for p in candidates:
            key = (str(p["lib"]), str(p["symbol"]))
            if key not in seen:
                seen.add(key)
                dedup.append(p)
        return dedup[:8]
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--commit", default="")
    args = ap.parse_args()
    src = args.source
    if not args.commit:
        try:
            args.commit = subprocess.check_output(
                ["git", "-C", str(src), "rev-parse", "HEAD"], text=True
            ).strip()
        except Exception:
            args.commit = "unknown"
    all_names = read_names(src / "cstdapi.txt") or read_plain(src / "linuxgood.txt")
    good_linux = set(read_plain(src / "linuxgood.txt"))
    bad_linux = set(read_plain(src / "linuxbad.txt"))
    good_win = set(read_plain(src / "wingood.txt"))
    bad_win = set(read_plain(src / "winbad.txt"))
    # cstdapi marks C99 snprintf as unavailable on Windows, but the supported
    # msvcrt/UCRT ABI exposes it as _snprintf. Keep the compatibility alias.
    for alias in ("snprintf", "vsnprintf"):
        bad_win.discard(alias)
        good_win.add(alias)
    msvcrt_spec = read_spec(src / "msvcrt.spec")
    ucrt_spec = read_spec(src / "ucrtbase.spec")
    targets = {
        "x86_64-linux": (good_linux, bad_linux),
        "aarch64-linux": (good_linux, bad_linux),
        "x86_64-windows": (good_win, bad_win),
        "i686-windows": (good_win, bad_win),
    }
    data = {
        "schema": 1,
        "source": "https://github.com/howmp/cstdapi",
        "upstream_commit": args.commit,
        "targets": {},
    }
    for target, (good, bad) in targets.items():
        symbols: dict[str, object] = {}
        for name in sorted(all_names):
            if name in good:
                symbols[name] = {
                    "available": True,
                    "providers": providers(name, target, msvcrt_spec, ucrt_spec),
                }
            elif name in bad:
                symbols[name] = {"available": False, "reason": "not exported by target C runtime"}
        data["targets"][target] = {"symbols": symbols}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n")
    print(f"wrote {args.out} ({args.out.stat().st_size} bytes), commit={args.commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
