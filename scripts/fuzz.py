#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
PYTHONPATH = str(ROOT / "compiler/src")
SEEDS = ["hello", "arrays", "structs", "ffi_qsort", "ffi_structs"]


def compile_seed(name: str, out: Path) -> Path:
    env = dict(os.environ, PYTHONPATH=PYTHONPATH)
    package = out / f"{name}.cib"
    subprocess.run(
        [sys.executable, "-m", "cinterp", "compile", str(ROOT / "examples" / f"{name}.c"), "-o", str(package)],
        check=True,
        env=env,
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
    parser.add_argument("--runtime", type=Path, default=RUNTIME)
    args = parser.parse_args()

    runtime = args.runtime.resolve()
    if not runtime.exists():
        print(f"missing runtime: {runtime}", file=sys.stderr)
        return 2
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
                    [str(runtime), "--load-only", str(candidate)],
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
