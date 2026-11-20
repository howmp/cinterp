#!/usr/bin/env python3
"""Execute mutated CIB packages against cinterp-run.

This is an execute-level fuzzer and is not part of CI: mutated bytecode may
legitimately carry arbitrary addresses or form infinite loops, so a green run
requires ``--tolerate-faults --tolerate-timeouts``. Timeouts count as failures
by default (a hang is a real defect); pass ``--tolerate-timeouts`` to keep the
old behaviour. Crash and timeout candidates are written to
``build/fuzz-artifacts`` for local triage.
"""
from __future__ import annotations

import argparse
import random
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
COMPILER = ROOT / "build/cinterp-cc"
BASE_SEEDS = ["hello", "arrays", "structs", "math", "bitfields", "ptrstruct", "longdouble"]
FFI_SEEDS = ["ffi_printf", "ffi_malloc", "ffi_snprintf", "ffi_qsort", "ffi_structs", "ffi_callback"]
DEFAULT_ARTIFACTS = ROOT / "build/fuzz-artifacts"


def compile_seed(name: str, out: Path) -> Path:
    package = out / f"{name}.cib"
    src = str(next(ROOT.glob(f"examples/**/{name}.c")))
    subprocess.run([str(COMPILER), "compile", src, "-o", str(package)],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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


def save_artifact(artifacts: Path, name: str, candidate: Path, stderr: bytes = b"") -> Path:
    artifacts.mkdir(parents=True, exist_ok=True)
    target = artifacts / name
    target.write_bytes(candidate.read_bytes())
    if stderr:
        target.with_suffix(target.suffix + ".stderr.txt").write_bytes(stderr[-8192:])
    return target


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--iterations", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--runtime", type=Path, default=RUNTIME)
    ap.add_argument("--artifacts", type=Path, default=DEFAULT_ARTIFACTS,
                    help="directory for crash/timeout candidates (default: build/fuzz-artifacts)")
    ap.add_argument("--ffi", action="store_true", help="include packages that call native code")
    ap.add_argument(
        "--tolerate-faults",
        action="store_true",
        help="count SIGSEGV/SIGBUS/SIGILL/SIGABRT as expected faults (mutated bytecode)",
    )
    ap.add_argument(
        "--tolerate-timeouts",
        action="store_true",
        help="count timeouts as non-failures (old behaviour; CI does not pass this)",
    )
    args = ap.parse_args()
    runtime = args.runtime.resolve()
    if not runtime.exists():
        print(f"missing runtime: {runtime}", file=sys.stderr)
        return 2
    artifacts = args.artifacts.resolve()
    seeds_names = BASE_SEEDS + (FFI_SEEDS if args.ffi else [])
    rng = random.Random(args.seed)
    crashes = timeouts = faults = runs = 0
    with tempfile.TemporaryDirectory(prefix="cinterp-fuzz-exec-") as td:
        tmp = Path(td)
        seeds = [compile_seed(name, tmp) for name in seeds_names]
        for _ in range(args.iterations):
            data = rng.choice(seeds).read_bytes()
            candidate = tmp / "candidate.cib"
            candidate.write_bytes(mutate(data, rng))
            runs += 1
            try:
                proc = subprocess.run([str(runtime), str(candidate)],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                      timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timeouts += 1
                saved = save_artifact(
                    artifacts, f"fuzz-exec-timeout-r{runs}-seed{args.seed}.cib", candidate)
                if args.tolerate_timeouts:
                    print(f"timeout (tolerated) on mutation #{runs} (saved {saved})", file=sys.stderr)
                else:
                    print(f"TIMEOUT mutation #{runs} exceeded {args.timeout}s (saved {saved})",
                          file=sys.stderr)
                continue
            stderr = proc.stderr.decode("utf-8", "replace")
            if proc.returncode < 0:
                sig = -proc.returncode
                if args.tolerate_faults and sig in (
                    signal.SIGSEGV, signal.SIGBUS, signal.SIGILL, signal.SIGABRT
                ):
                    # Corrupted bytecode may legitimately form arbitrary
                    # pointers or trip runtime safety checks; packages are
                    # trusted build products.
                    faults += 1
                    continue
            if proc.returncode < 0 or proc.returncode >= 128:
                saved = save_artifact(
                    artifacts,
                    f"fuzz-exec-crash-r{runs}-seed{args.seed}.cib",
                    candidate,
                    proc.stderr,
                )
                print(f"CRASH signal/abort rc={proc.returncode} on mutation #{runs} (saved {saved})",
                      file=sys.stderr)
                crashes += 1
    failed_timeouts = 0 if args.tolerate_timeouts else timeouts
    print(
        f"fuzz-exec: {runs} mutations, {crashes} crashes, "
        f"{faults} expected faults, {timeouts} timeouts"
        + ("" if args.tolerate_timeouts else f" ({timeouts} counted as failures)")
    )
    if crashes or failed_timeouts:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
