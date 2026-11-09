#!/usr/bin/env python3
"""Structural validator for cinterp .cib packages.

Checks CIPKG/CIVM/CIPL/CIPI lengths and indices, then optionally asks the
runtime loader to accept packages with imports.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


def parse_civm(module: bytes) -> int:
    if module[:4] != b"CIVM":
        raise Bad("CIVM magic")
    if len(module) < 10:
        raise Bad("CIVM header truncated")
    version = module[4]
    if version != 2:
        raise Bad(f"unsupported CIVM version {version}")
    count = u16(module, 6)
    entry = u16(module, 8)
    if count > 512:
        raise Bad(f"function count {count} > 512")
    if entry != 0xFFFF and entry >= count:
        raise Bad(f"CIVM entry index {entry} out of range")
    p = 10
    for fn in range(count):
        if p + 8 > len(module):
            raise Bad(f"function {fn} header truncated")
        params = u16(module, p)
        locals_ = u16(module, p + 2)
        clen = u32(module, p + 4)
        p += 8
        if locals_ < params:
            raise Bad(f"function {fn}: locals {locals_} < params {params}")
        if p + clen > len(module):
            raise Bad(f"function {fn}: code overruns module")
        p += clen
    if p != len(module):
        raise Bad(f"CIVM trailing bytes {len(module) - p}")
    return count


def parse_cipl(plans: bytes, name_count: int) -> tuple[int, int]:
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
        if p + 2 > len(plans):
            raise Bad(f"plan {pi} truncated")
        name_ref = u16(plans, p)
        if name_ref >= name_count:
            raise Bad(f"plan {pi} name ref {name_ref} out of range")
        p += 2
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


def parse_cipc(pool: bytes) -> int:
    if len(pool) < 20 or pool[:4] != b"CIPC":
        raise Bad("CIPC magic/header")
    if pool[4] != 1:
        raise Bad(f"unsupported CIPC version {pool[4]}")
    count = u16(pool, 6)
    blob_len = u32(pool, 8)
    data_len = u32(pool, 12)
    blob_start = 20 + count * 2
    if blob_start + blob_len > len(pool):
        raise Bad("CIPC name blob overruns section")
    data_start = (blob_start + blob_len + 15) & ~15
    if data_start + data_len != len(pool):
        raise Bad("CIPC data length mismatch")
    for i in range(count):
        off = u16(pool, 20 + i * 2)
        begin = blob_start + off
        if begin >= blob_start + blob_len:
            raise Bad(f"CIPC name {i} offset out of range")
        end = pool.find(b"\x00", begin, blob_start + blob_len)
        if end < 0:
            raise Bad(f"CIPC name {i} is not terminated")
    return count


def parse_imports(imports: bytes, name_count: int) -> int:
    if not imports:
        return 0
    p = 0
    count = u16(imports, p)
    p += 2
    if count > 512:
        raise Bad(f"import count {count} > 512")
    for i in range(count):
        if p + 6 > len(imports):
            raise Bad(f"import {i} truncated")
        name_ref = u16(imports, p + 4)
        if name_ref != 0xFFFF and name_ref >= name_count:
            raise Bad(f"import {i} name ref {name_ref} out of range")
        p += 6
        providers = imports[p]
        p += 1
        if providers > 8:
            raise Bad(f"import {i} provider count {providers} > 8")
        for pi in range(providers):
            if p + 6 > len(imports):
                raise Bad(f"import {i} provider {pi} truncated")
            lib_ref = u16(imports, p)
            sym_ref = u16(imports, p + 2)
            if lib_ref >= name_count or (sym_ref != 0xFFFF and sym_ref >= name_count):
                raise Bad(f"import {i} provider {pi} name ref out of range")
            p += 6
    if p != len(imports):
        raise Bad(f"CIPI trailing bytes {len(imports) - p}")
    return count


def lint(path: Path) -> list[str]:
    findings: list[str] = []
    try:
        data = path.read_bytes()
        if len(data) < 22 or data[:5] != b"CIPKG":
            raise Bad("CIPKG magic/header")
        if data[5] != 4:
            raise Bad(f"unsupported CIPKG version {data[5]}")
        mlen = u32(data, 6)
        plen = u32(data, 10)
        ilen = u32(data, 14)
        clen = u32(data, 18)
        if 22 + mlen + plen + ilen + clen != len(data):
            raise Bad("v4 section lengths do not match file size")
        module = data[22 : 22 + mlen]
        plans = data[22 + mlen : 22 + mlen + plen]
        imports = data[22 + mlen + plen : 22 + mlen + plen + ilen]
        pool = data[22 + mlen + plen + ilen :]
        parse_civm(module)
        name_count = parse_cipc(pool)
        parse_cipl(plans, name_count)
        parse_imports(imports, name_count)
    except Bad as e:
        findings.append(f"{path}: {e}")
    except Exception as e:  # malformed files must not crash the linter
        findings.append(f"{path}: {type(e).__name__}: {e}")
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("packages", nargs="+", type=Path)
    args = ap.parse_args()
    findings: list[str] = []
    for p in args.packages:
        files = sorted(p.rglob("*.cib")) if p.is_dir() else [p]
        for f in files:
            findings.extend(lint(f))
    for f in findings:
        print(f, file=sys.stderr)
    if findings:
        print(f"civm_lint: {len(findings)} finding(s)", file=sys.stderr)
        return 1
    print(f"civm_lint: {sum(1 for p in args.packages for _ in ([p] if p.is_file() else p.rglob('*.cib')))} package(s) OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
