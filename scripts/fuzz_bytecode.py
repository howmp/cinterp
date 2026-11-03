#!/usr/bin/env python3
"""Structured CIVM bytecode fuzzing: mutate function headers/opcodes in place."""
from __future__ import annotations

import argparse
import os
import random
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
COMPILER = ROOT / "build/cinterp-cc"
DEFAULT_ARTIFACTS = ROOT / "build/fuzz-artifacts"
SEEDS = ["hello", "arrays", "structs", "ffi_printf", "ffi_structs"]

OPCODES = [
    0x01, 0x02, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x38, 0x39, 0x3A, 0x40,
    0x41, 0x42, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x70,
    0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A,
    0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x80, 0x81, 0x82, 0x83, 0x84,
    0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E,
    0x8F, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
    0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xA0, 0xA1, 0xA2,
]


def compile_seed(name: str, out: Path) -> Path:
    package = out / f"{name}.cib"
    src = str(ROOT / "examples" / f"{name}.c")
    subprocess.run(
        [str(COMPILER), "compile", src, "-o", str(package)],
        check=True, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return package


def module_span(data: bytes) -> tuple[int, int] | None:
    if len(data) < 15 or data[:5] != b"CIPKG":
        return None
    version = data[5]
    if version == 1:
        module_len = struct.unpack_from("<I", data, 7)[0]
        start = 15
    elif version == 2:
        if len(data) < 25:
            return None
        module_len = struct.unpack_from("<I", data, 9)[0]
        start = 25
    else:
        return None
    if start + module_len > len(data):
        return None
    return start, module_len


def functions(data: bytes, start: int, length: int) -> list[dict]:
    module = data[start : start + length]
    if len(module) < 10 or module[:4] != b"CIVM":
        return []
    count = struct.unpack_from("<H", module, 6)[0]
    pos = 10
    out = []
    for _ in range(count):
        if pos + 1 > len(module):
            break
        name_len = module[pos]
        pos += 1
        if pos + name_len + 8 > len(module):
            break
        name = module[pos : pos + name_len]
        pos += name_len
        params_off = pos
        params = struct.unpack_from("<H", module, pos)[0]
        locals_off = pos + 2
        locals_count = struct.unpack_from("<H", module, pos + 2)[0]
        code_len_off = pos + 4
        code_len = struct.unpack_from("<I", module, pos + 4)[0]
        code_off = pos + 8
        pos = code_off + code_len
        if pos > len(module):
            break
        out.append({
            "name": name.decode("utf-8", "replace"),
            "params_off": start + params_off,
            "locals_off": start + locals_off,
            "code_len_off": start + code_len_off,
            "code_off": start + code_off,
            "code_len": code_len,
            "params": params,
            "locals": locals_count,
        })
    return out


def mutate(data: bytes, rng: random.Random) -> bytes | None:
    """Return a mutated package, or None when the input could not be mutated.

    ``None`` covers both unparsable packages (no CIVM module span/functions) and
    mutations that left the bytes unchanged; the caller counts those as skipped
    so an all-skipped run cannot look like a clean fuzz pass.
    """
    buf = bytearray(data)
    span = module_span(buf)
    if span is None:
        return None
    start, length = span
    funcs = functions(buf, start, length)
    if not funcs:
        return None
    kind = rng.randrange(7)
    fn = rng.choice(funcs)
    if kind == 0 and fn["code_len"] > 0:
        pos = fn["code_off"] + rng.randrange(fn["code_len"])
        buf[pos] = rng.choice(OPCODES)
    elif kind == 1 and fn["code_len"] >= 4:
        pos = fn["code_off"] + rng.randrange(0, fn["code_len"] - 3)
        struct.pack_into("<I", buf, pos, rng.choice([0, 1, 0xFFFFFFFF, rng.getrandbits(32)]))
    elif kind == 2:
        struct.pack_into("<H", buf, fn["params_off"], rng.choice([0, 1, 0xFFFF, rng.getrandbits(16)]))
    elif kind == 3:
        struct.pack_into("<H", buf, fn["locals_off"], rng.choice([0, 1, 0xFFFF, fn["params"], rng.getrandbits(16)]))
    elif kind == 4:
        limit = start + length - fn["code_off"]
        struct.pack_into("<I", buf, fn["code_len_off"], rng.choice([0, 1, limit, rng.getrandbits(32)]))
    elif kind == 5 and fn["code_len"] > 1:
        pos = fn["code_off"] + rng.randrange(fn["code_len"] - 1)
        buf[pos : pos + 2] = bytes([rng.choice(OPCODES), rng.randrange(256)])
    else:
        pos = fn["code_off"] + rng.randrange(fn["code_len"] or 1)
        buf[pos] ^= 1 << rng.randrange(8)
    mutated = bytes(buf)
    return None if mutated == data else mutated


def save_artifact(artifacts: Path, name: str, candidate: Path) -> Path:
    artifacts.mkdir(parents=True, exist_ok=True)
    target = artifacts / name
    target.write_bytes(candidate.read_bytes())
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=500)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument(
        "--tolerate-timeouts",
        action="store_true",
        help="count mutated-bytecode infinite loops as expected timeouts instead of failures",
    )
    parser.add_argument("--runtime", type=Path, default=RUNTIME)
    parser.add_argument("--artifacts", type=Path, default=DEFAULT_ARTIFACTS,
                        help="directory for crash candidates (default: build/fuzz-artifacts)")
    parser.add_argument("--exec", action="store_true", help="execute mutated packages")
    args = parser.parse_args()
    if not args.runtime.exists():
        print(f"missing runtime: {args.runtime}", file=sys.stderr)
        return 2
    runtime = args.runtime.resolve()
    artifacts = args.artifacts.resolve()
    rng = random.Random(args.seed)
    crashes = timeouts = runs = executed = skipped = 0
    with tempfile.TemporaryDirectory(prefix="cinterp-fuzz-bytecode-") as td:
        tmp = Path(td)
        seeds = [compile_seed(name, tmp) for name in SEEDS]
        for _ in range(args.iterations):
            data = rng.choice(seeds).read_bytes()
            mutated = mutate(data, rng)
            runs += 1
            if mutated is None:
                skipped += 1
                continue
            candidate = tmp / "candidate.cib"
            candidate.write_bytes(mutated)
            command = [str(runtime)]
            if not args.exec:
                command.append("--load-only")
            command.append(str(candidate))
            executed += 1
            try:
                proc = subprocess.run(
                    command,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=args.timeout,
                    cwd=tmp,
                )
            except subprocess.TimeoutExpired:
                timeouts += 1
                saved = save_artifact(
                    artifacts, f"fuzz-bytecode-timeout-r{runs}-seed{args.seed}.cib", candidate)
                print(f"TIMEOUT mutation #{runs} (saved {saved})", file=sys.stderr)
                continue
            if proc.returncode < 0 or proc.returncode >= 128:
                saved = save_artifact(
                    artifacts, f"fuzz-bytecode-crash-r{runs}-seed{args.seed}.cib", candidate)
                print(
                    f"CRASH signal/abort rc={proc.returncode} on mutation #{runs} "
                    f"(saved {saved})",
                    file=sys.stderr,
                )
                crashes += 1
    mode = "exec" if args.exec else "load-only"
    print(
        f"fuzz-bytecode ({mode}): {runs} mutations, {skipped} skipped, "
        f"{executed} executed, {crashes} crashes, {timeouts} timeouts"
    )
    if skipped and skipped == runs:
        print(
            "fuzz-bytecode: every mutation was skipped (unparsable or no-op); "
            "nothing was fuzzed",
            file=sys.stderr,
        )
        return 2
    if executed == 0:
        print("fuzz-bytecode: no mutation was executed; nothing was fuzzed", file=sys.stderr)
        return 2
    if crashes or (timeouts and not args.tolerate_timeouts):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
