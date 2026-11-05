#!/usr/bin/env python3
"""Structural validator for cinterp .cib packages.

Checks CIPKG/CIVM/CIPL/CIPI lengths and indices, then optionally asks the
runtime loader to accept packages with imports.
"""
from __future__ import annotations

import argparse
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"


class Bad(Exception):
    pass


def u16(b: bytes, o: int) -> int:
    if o + 2 > len(b):
        raise Bad("truncated u16")
    return struct.unpack_from("<H", b, o)[0]


def u32(b: bytes, o: int) -> int:
    if o + 4 > len(b):
        raise Bad("truncated u32")
    return struct.unpack_from("<I", b, o)[0]


def parse_civm(module: bytes) -> tuple[int, list[str]]:
    if module[:4] != b"CIVM":
        raise Bad("CIVM magic")
    if len(module) < 10:
        raise Bad("CIVM header truncated")
    version = module[4]
    if version != 1:
        raise Bad(f"unsupported CIVM version {version}")
    count = u16(module, 6)
    if count > 512:
        raise Bad(f"function count {count} > 512")
    p = 10
    names: list[str] = []
    for fn in range(count):
        if p >= len(module):
            raise Bad(f"function {fn} header truncated")
        nlen = module[p]
        p += 1
        if nlen == 0 or nlen > 128 or p + nlen > len(module):
            raise Bad(f"function {fn} bad name length {nlen}")
        name = module[p : p + nlen].decode("utf-8", "replace")
        p += nlen
        if p + 8 > len(module):
            raise Bad(f"function {name} header truncated")
        params = u16(module, p)
        locals_ = u16(module, p + 2)
        clen = u32(module, p + 4)
        p += 8
        if locals_ < params:
            raise Bad(f"function {name}: locals {locals_} < params {params}")
        if p + clen > len(module):
            raise Bad(f"function {name}: code overruns module")
        p += clen
        names.append(name)
    if p != len(module):
        raise Bad(f"CIVM trailing bytes {len(module) - p}")
    return count, names


def parse_cipl(plans: bytes) -> tuple[int, int]:
    if not plans:
        return 0, 0
    if len(plans) < 3:
        raise Bad("CIPL header truncated")
    abi = plans[0]
    if abi not in (1, 2, 3, 4):
        raise Bad(f"bad ABI id {abi}")
    count = u16(plans, 1)
    if count > 1024:
        raise Bad(f"plan count {count} > 1024")
    p = 3
    for pi in range(count):
        if p >= len(plans):
            raise Bad(f"plan {pi} truncated")
        nlen = plans[p]
        p += 1
        if nlen == 0 or nlen > 128 or p + nlen > len(plans):
            raise Bad(f"plan {pi} bad name length {nlen}")
        p += nlen
        if p + 7 > len(plans):
            raise Bad(f"plan {pi} header truncated")
        args_count = plans[p]
        ret_count = plans[p + 1]
        stack_size = u16(plans, p + 2)
        p += 7
        if args_count > 64 or ret_count > 8 or stack_size > 4096:
            raise Bad(f"plan {pi}: counts/stack out of range")
        for ai in range(args_count):
            if p + 3 > len(plans):
                raise Bad(f"plan {pi} arg {ai} truncated")
            flags = plans[p]
            locs = flags & 0x0F
            size = u16(plans, p + 1)
            p += 3
            if locs == 0 or locs > 8 or size == 0:
                raise Bad(f"plan {pi} arg {ai}: bad locs/size")
            if p + locs * 7 > len(plans):
                raise Bad(f"plan {pi} arg {ai}: locs overrun")
            p += locs * 7
        if p + ret_count * 7 > len(plans):
            raise Bad(f"plan {pi}: return locs overrun")
        p += ret_count * 7
    if p != len(plans):
        raise Bad(f"CIPL trailing bytes {len(plans) - p}")
    return abi, count

def lint(path: Path, load: bool = True) -> list[str]:
    findings: list[str] = []
    try:
        data = path.read_bytes()
        if len(data) < 18 or data[:5] != b"CIPKG":
            raise Bad("CIPKG magic/header")
        if data[5] != 3:
            raise Bad(f"unsupported CIPKG version {data[5]}")
        mlen = u32(data, 6)
        plen = u32(data, 10)
        ilen = u32(data, 14)
        if 18 + mlen + plen + ilen != len(data):
            raise Bad("v3 section lengths do not match file size")
        module = data[18 : 18 + mlen]
        plans = data[18 + mlen : 18 + mlen + plen]
        imports = data[18 + mlen + plen :]
        parse_civm(module)
        _, _ = parse_cipl(plans)
        if imports and (len(imports) < 10 or imports[:4] != b"CIPI"):
            raise Bad("CIPI magic/header")
        if load and RUNTIME.exists() and imports:
            r = subprocess.run(
                [str(RUNTIME), "--load-only", str(path)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if r.returncode != 0:
                raise Bad("runtime load-only: " + (r.stderr.strip() or r.stdout.strip()))
    except Bad as e:
        findings.append(f"{path}: {e}")
    except Exception as e:  # malformed files must not crash the linter
        findings.append(f"{path}: {type(e).__name__}: {e}")
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("packages", nargs="+", type=Path)
    ap.add_argument("--no-load", action="store_true")
    args = ap.parse_args()
    findings: list[str] = []
    for p in args.packages:
        files = sorted(p.rglob("*.cib")) if p.is_dir() else [p]
        for f in files:
            findings.extend(lint(f, load=not args.no_load))
    for f in findings:
        print(f, file=sys.stderr)
    if findings:
        print(f"civm_lint: {len(findings)} finding(s)", file=sys.stderr)
        return 1
    print(f"civm_lint: {sum(1 for p in args.packages for _ in ([p] if p.is_file() else p.rglob('*.cib')))} package(s) OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
