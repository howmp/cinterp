#!/usr/bin/env python3
"""Mutation fuzzing through the C embedding API under ASan/UBSan."""
from __future__ import annotations

import argparse
import os
import random
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMPILER = ROOT / "build/cinterp-cc"
SEEDS = ["hello", "arrays", "structs", "math", "bitfields", "ptrstruct"]
HARNESS = ROOT / "build/fuzz-capi-asan/capi_fuzz"


def compile_seed(name: str, out: Path) -> Path:
    package = out / f"{name}.cib"
    subprocess.run(
        [str(COMPILER), "compile",
         str(ROOT / "examples" / f"{name}.c"), "-o", str(package)],
        check=True, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
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
                buf[rng.randrange(len(buf))] ^= 1 << rng.randrange(8)
        return bytes(buf)
    if kind == 2:
        buf = bytearray(data)
        for _ in range(rng.randrange(1, 5)):
            if buf:
                buf[rng.randrange(len(buf))] = rng.randrange(256)
        return bytes(buf)
    return data + bytes(rng.randrange(256) for _ in range(rng.randrange(1, 32)))


def build_harness() -> None:
    HARNESS.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "cc", "-std=c11", "-g", "-O1",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
            "-I", "runtime/zig-out/include",
            "runtime/tests/capi_fuzz.c",
            "runtime/zig-out/lib/libcinterp.a",
            "-ldl", "-lpthread", "-lm",
            "-o", str(HARNESS),
        ],
        check=True,
        cwd=ROOT,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()

    build_harness()
    env = dict(
        os.environ,
        ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:halt_on_error=1:handle_segv=0",
        UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1",
    )
    rng = random.Random(args.seed)
    crashes = timeouts = faults = runs = 0
    with tempfile.TemporaryDirectory(prefix="cinterp-fuzz-asan-") as td:
        tmp = Path(td)
        seeds = [compile_seed(name, tmp) for name in SEEDS]
        for seed in seeds:
            subprocess.run([str(HARNESS), str(seed)], env=env, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(args.iterations):
            data = rng.choice(seeds).read_bytes()
            candidate = tmp / "candidate.cib"
            candidate.write_bytes(mutate(data, rng))
            runs += 1
            try:
                proc = subprocess.run(
                    [str(HARNESS), str(candidate)],
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    timeout=args.timeout,
                    cwd=tmp,
                )
            except subprocess.TimeoutExpired:
                timeouts += 1
                continue
            stderr = proc.stderr.decode("utf-8", "replace")
            sanitizer = (
                "AddressSanitizer" in stderr
                or "UndefinedBehaviorSanitizer" in stderr
                or "runtime error:" in stderr
            )
            if proc.returncode < 0:
                sig = -proc.returncode
                if sig in (signal.SIGSEGV, signal.SIGBUS, signal.SIGILL) and not sanitizer:
                    # Corrupted bytecode may legitimately dereference arbitrary
                    # pointers; packages are trusted build products.
                    faults += 1
                    continue
            if sanitizer or proc.returncode < 0 or proc.returncode >= 128:
                saved = Path("/tmp/cinterp-fuzz-asan-crash.cib")
                saved.write_bytes(candidate.read_bytes())
                print(
                    f"CRASH rc={proc.returncode} on mutation #{runs} (saved {saved})",
                    file=sys.stderr,
                )
                if stderr:
                    print(stderr[-2000:], file=sys.stderr)
                crashes += 1
    print(
        f"fuzz-capi-asan: {runs} mutations, {crashes} crashes, "
        f"{faults} expected faults, {timeouts} timeouts"
    )
    return 1 if crashes else 0


if __name__ == "__main__":
    raise SystemExit(main())
