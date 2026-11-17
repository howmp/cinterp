#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "build/fuzz-load/capi_fuzz"
COMPILER = ROOT / "build/cinterp-cc"
SEEDS = ["hello", "arrays", "structs", "ffi_qsort", "ffi_structs"]


def build_harness() -> None:
    HARNESS.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "cc", "-std=c11", "-O1",
            "-I", "runtime/zig-out/include",
            "runtime/tests/capi_fuzz.c",
            "runtime/zig-out/lib/libcinterp.a",
            "-ldl", "-lpthread", "-lm",
            "-o", str(HARNESS),
        ],
        check=True,
        cwd=ROOT,
    )


def compile_seed(name: str, out: Path) -> Path:
    package = out / f"{name}.cib"
    src = str(next(ROOT.glob(f"examples/**/{name}.c")))
    subprocess.run(
        [str(COMPILER), "compile", src, "-o", str(package)],
        check=True,
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return package


def mutate(data: bytes, rng: random.Random) -> bytes:
    kind = rng.randrange(4)
    if kind == 0:
        return data[: rng.randrange(0, len(data) + 1)]
    if kind == 1:
        buf = bytearray(data)
        for _ in range(rng.randrange(1, 9)):
            if buf:
                pos = rng.randrange(len(buf))
                buf[pos] ^= 1 << rng.randrange(8)
        return bytes(buf)
    if kind == 2:
        buf = bytearray(data)
        for _ in range(rng.randrange(1, 5)):
            if buf:
                buf[rng.randrange(len(buf))] = rng.randrange(256)
        return bytes(buf)
    return data + bytes(rng.randrange(256) for _ in range(rng.randrange(1, 32)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    build_harness()
    rng = random.Random(args.seed)
    crashes = 0
    runs = 0
    with tempfile.TemporaryDirectory(prefix="cinterp-fuzz-") as td:
        tmp = Path(td)
        seeds = [compile_seed(name, tmp) for name in SEEDS]
        for _ in range(args.iterations):
            data = rng.choice(seeds).read_bytes()
            mutated = mutate(data, rng)
            candidate = tmp / "candidate.cib"
            candidate.write_bytes(mutated)
            runs += 1
            try:
                proc = subprocess.run(
                    [str(HARNESS), "--load-only", str(candidate)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=3,
                )
            except subprocess.TimeoutExpired:
                print(f"CRASH timeout on mutation #{runs}", file=sys.stderr)
                crashes += 1
                continue
            if proc.returncode < 0 or proc.returncode >= 128:
                print(f"CRASH signal/abort rc={proc.returncode} on mutation #{runs}", file=sys.stderr)
                crashes += 1
    print(f"fuzz: {runs} mutations, {crashes} crashes")
    return 1 if crashes else 0


if __name__ == "__main__":
    raise SystemExit(main())
