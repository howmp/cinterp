#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
COMPILER = ROOT / "build/cinterp-cc"
SUITES = ROOT / "build/suites"
CASES = {
    "mandelbrot": "CompCert/test/c/mandelbrot.c",
    "fannkuch": "CompCert/test/c/fannkuch.c",
    "nsieve": "CompCert/test/c/nsieve.c",
    "nsievebits": "CompCert/test/c/nsievebits.c",
    "vmach": "CompCert/test/c/vmach.c",
    "qsort": "CompCert/test/c/qsort.c",
    "00040": "c-testsuite/tests/single-exec/00040.c",
    "fft": "CompCert/test/c/fft.c",
    "fftsp": "CompCert/test/c/fftsp.c",
    "perlin": "CompCert/test/c/perlin.c",
}


def run_checked(cmd: list[str], timeout: float) -> None:
    try:
        subprocess.run(
            cmd,
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=True,
            timeout=timeout,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.decode(errors="replace") if exc.stderr else ""
        raise SystemExit(f"command failed: {' '.join(cmd)}\n{stderr}") from exc
    except subprocess.TimeoutExpired as exc:
        raise SystemExit(f"command timed out after {timeout:g}s: {' '.join(cmd)}") from exc


def run_once(runtime: Path, cib: Path, timeout: float) -> float:
    start = time.perf_counter()
    run_checked([str(runtime), str(cib)], timeout)
    return time.perf_counter() - start


def parse_cc_opts(value: str) -> list[int]:
    opts: list[int] = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            opt = int(part)
        except ValueError as exc:
            raise SystemExit(f"invalid --cc-opt value: {part!r}") from exc
        if opt < 0 or opt > 3:
            raise SystemExit(f"--cc-opt must be 0..3: {opt}")
        if opt not in opts:
            opts.append(opt)
    if not opts:
        raise SystemExit("--cc-opt must list at least one level")
    return opts


def main() -> int:
    parser = argparse.ArgumentParser(description="Long-running C interpreter benchmarks")
    parser.add_argument("--cc-opt", default="0,2", help="comma-separated C frontend opt levels")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=300.0, help="seconds per benchmark run")
    parser.add_argument("--compile-timeout", type=float, default=180.0)
    parser.add_argument("--json", type=Path, default=None)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be >= 1")
    if args.timeout <= 0 or args.compile_timeout <= 0:
        parser.error("timeouts must be > 0")
    if not RUNTIME.is_file() or not COMPILER.is_file():
        parser.error("build the compiler/runtime first (make compiler runtime)")

    opts = parse_cc_opts(args.cc_opt)
    missing = [f"{name} ({rel})" for name, rel in CASES.items() if not (SUITES / rel).is_file()]
    if missing:
        parser.error(
            "missing benchmark sources under build/suites (run make fetch-suites):\n  "
            + "\n  ".join(missing)
        )

    rows: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="cinterp-bench-long-") as td:
        out = Path(td)
        for opt in opts:
            print(f"cc-opt {opt} ({args.runs} runs)", flush=True)
            for name, rel in CASES.items():
                source = SUITES / rel
                cib = out / f"{name}-O{opt}.cib"
                print(f"  compiling {name} ...", flush=True)
                run_checked(
                    [
                        str(COMPILER),
                        "compile",
                        str(source),
                        "-o",
                        str(cib),
                        "--cc-opt",
                        str(opt),
                    ],
                    args.compile_timeout,
                )
                run_once(RUNTIME, cib, args.timeout)
                samples = [run_once(RUNTIME, cib, args.timeout) for _ in range(args.runs)]
                row = {
                    "case": name,
                    "source": rel,
                    "cc_opt": opt,
                    "min_us": min(samples) * 1e6,
                    "median_us": statistics.median(samples) * 1e6,
                    "mean_us": statistics.mean(samples) * 1e6,
                }
                rows.append(row)
                print(
                    f"  {name:16s} min={row['min_us'] / 1000:9.3f} ms "
                    f"median={row['median_us'] / 1000:9.3f} ms",
                    flush=True,
                )

    speedups: dict[str, dict] = {}
    if 0 in opts and len(opts) > 1:
        base = {(row["case"], row["cc_opt"]): row["min_us"] for row in rows}
        for opt in opts:
            if opt == 0:
                continue
            per_case: dict[str, float] = {}
            logs: list[float] = []
            for name in CASES:
                factor = base[(name, 0)] / base[(name, opt)]
                per_case[name] = factor
                logs.append(math.log(factor))
            speedups[f"{opt}_vs_0"] = {
                "per_case": per_case,
                "geomean": math.exp(sum(logs) / len(logs)),
            }

    report = {
        "compiler": str(COMPILER.relative_to(ROOT)),
        "runtime": str(RUNTIME.relative_to(ROOT)),
        "runs": args.runs,
        "cc_opts": opts,
        "cases": rows,
        "speedups": speedups,
    }
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n")

    for label, data in speedups.items():
        print(f"{label}: geomean {data['geomean']:.3f}x")
        for name, factor in data["per_case"].items():
            print(f"  {name:16s} {factor:.3f}x")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
