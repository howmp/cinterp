#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
COMPILER = ROOT / "build/cinterp-cc"
CASES = {
    "hello": "basics/hello.c",
    "arrays": "basics/arrays.c",
    "math": "basics/math.c",
    "bitfields": "basics/bitfields.c",
    "ptrstruct": "basics/ptrstruct.c",
    "longdouble": "basics/longdouble.c",
    "ffi_printf": "ffi/ffi_printf.c",
}


def run_once(runtime: Path, cib: Path) -> float:
    start = time.perf_counter()
    subprocess.run(
        [str(runtime), str(cib)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    return time.perf_counter() - start


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--json", type=Path, default=None)
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error("--iterations must be >= 1")
    if not RUNTIME.is_file() or not COMPILER.is_file():
        parser.error("build the compiler/runtime first (make compiler runtime)")

    report = {
        "runtime": str(RUNTIME.relative_to(ROOT)),
        "iterations": args.iterations,
        "cases": [],
    }
    with tempfile.TemporaryDirectory(prefix="cinterp-bench-") as td:
        out = Path(td)
        for name, source in CASES.items():
            cib = out / f"{name}.cib"
            subprocess.run(
                [str(COMPILER), "compile", str(ROOT / "examples" / source), "-o", str(cib)],
                cwd=ROOT,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            # Warm the process/loader path before timing.
            run_once(RUNTIME, cib)
            samples = [run_once(RUNTIME, cib) for _ in range(args.iterations)]
            row = {
                "case": name,
                "mean_us": statistics.mean(samples) * 1e6,
                "median_us": statistics.median(samples) * 1e6,
                "min_us": min(samples) * 1e6,
            }
            report["cases"].append(row)
            print(
                f"{name:16s} mean={row['mean_us']:9.1f} us "
                f"median={row['median_us']:9.1f} us min={row['min_us']:9.1f} us"
            )

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
