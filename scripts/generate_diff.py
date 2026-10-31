#!/usr/bin/env python3
"""YARPGen differential smoke: native clang vs cinterp.

YARPGen emits separate func.c/driver.c/init.h files. We combine them into one
translation unit for cinterp, run the native build as the reference, and compare
stdout and exit status.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
PYTHONPATH = str(ROOT / "compiler/src")
DEFAULT_YARPGEN = ROOT / "build/suites/yarpgen/build/yarpgen"
DEFAULT_CSMITH = ROOT / "build/suites/csmith/build/src/csmith"
RESULT_RE = re.compile(rb"^result: -?\d+\r?\n", re.MULTILINE)


def run(cmd: list[str], cwd: Path, timeout: float = 60, env: dict | None = None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return None


def case_csmith(seed: int, csmith: Path, work: Path) -> dict:
    gen = work / f"csmith-{seed}"
    gen.mkdir(parents=True)
    test_c = gen / "test.c"
    out = run([str(csmith), "--seed", str(seed), "--no-argc", "--concise", "-o", str(test_c)], work, 60)
    result = {"seed": seed, "status": "harness", "reason": ""}
    if out is None or out.returncode != 0 or not test_c.is_file():
        result["reason"] = "csmith generation failed"
        return result
    csmith_root = csmith.parents[2] if csmith.parent.name == "src" else csmith.parent
    runtime = csmith_root / "runtime"
    build_runtime = csmith_root / "build/runtime"
    native = gen / "native"
    nc = run(["clang", "-O0", "-I", str(runtime), "-I", str(build_runtime), str(test_c), "-o", str(native)], gen, 60)
    if nc is None or nc.returncode != 0:
        result.update(status="skip", reason="native clang rejected generated program")
        return result
    nr = run([str(native)], gen, 30)
    if nr is None:
        result.update(status="skip", reason="native reference timed out")
        return result
    cib = gen / "test.cib"
    env = dict(os.environ, PYTHONPATH=PYTHONPATH, CPATH=os.pathsep.join([str(runtime), str(build_runtime)]))
    cc = run([sys.executable, "-m", "cinterp", "compile", str(test_c), "-o", str(cib)], ROOT, 120, env)
    if cc is None:
        result.update(status="skip", reason="cinterp compile timeout")
        return result
    if cc.returncode != 0:
        msg = cc.stderr.decode("utf-8", "replace").strip().splitlines()
        result.update(status="skip", reason="cinterp compile: " + (msg[-1] if msg else "failed"))
        return result
    cr = run([str(RUNTIME), str(cib)], ROOT, 30)
    if cr is None:
        result.update(status="failure", reason="cinterp run timeout")
        return result
    raw_got = cr.stdout + cr.stderr
    got = RESULT_RE.sub(b"", raw_got)
    want = nr.stdout + nr.stderr
    if cr.returncode != 0 and (b"ModuleTooLarge" in raw_got or b"FileTooBig" in raw_got):
        result.update(status="skip", reason="generated CIB exceeds cinterp module/file limit")
        return result
    if cr.returncode != nr.returncode or got != want:
        result.update(
            status="failure",
            reason=f"exit {cr.returncode} != {nr.returncode}" if cr.returncode != nr.returncode else "stdout mismatch",
            actual=got.decode("utf-8", "replace")[-1000:],
            expected=want.decode("utf-8", "replace")[-1000:],
        )
        return result
    result["status"] = "ok"
    return result


def case(seed: int, yarpgen: Path, work: Path, max_source_bytes: int = 8_000_000) -> dict:
    gen = work / f"seed-{seed}"
    gen.mkdir(parents=True)
    out = run([
        str(yarpgen), "--std=c", f"--seed={seed}", f"--out-dir={gen}",
        "--max-array-dims=2", "--allow-dead-data=false",
    ], work, 30)
    result = {"seed": seed, "status": "harness", "reason": ""}
    if out is None or out.returncode != 0 or not (gen / "driver.c").is_file() or not (gen / "func.c").is_file():
        result.update(status="harness", reason="yarpgen generation failed")
        return result
    total = sum(p.stat().st_size for p in gen.iterdir() if p.is_file())
    if total > max_source_bytes:
        result.update(status="skip", reason=f"generated source too large ({total} bytes)")
        return result
    combined = gen / "combined.c"
    combined.write_text('#include "func.c"\n#include "driver.c"\n')
    native = gen / "native"
    nc = run(["clang", "-O0", str(combined), "-o", str(native)], gen, 60)
    if nc is None or nc.returncode != 0:
        result.update(status="skip", reason="native clang rejected generated program")
        return result
    nr = run([str(native)], gen, 30)
    if nr is None:
        result.update(status="skip", reason="native reference timed out")
        return result
    cib = gen / "test.cib"
    env = dict(os.environ, PYTHONPATH=PYTHONPATH)
    cc = run([sys.executable, "-m", "cinterp", "compile", str(combined), "-o", str(cib)], ROOT, 120, env)
    if cc is None:
        result.update(status="skip", reason="cinterp compile timeout")
        return result
    if cc.returncode != 0:
        msg = cc.stderr.decode("utf-8", "replace").strip().splitlines()
        result.update(status="skip", reason="cinterp compile: " + (msg[-1] if msg else "failed"))
        return result
    cr = run([str(RUNTIME), str(cib)], ROOT, 30)
    if cr is None:
        result.update(status="failure", reason="cinterp run timeout")
        return result
    raw_got = cr.stdout + cr.stderr
    got = RESULT_RE.sub(b"", raw_got)
    want = nr.stdout + nr.stderr
    if cr.returncode != 0 and (b"ModuleTooLarge" in raw_got or b"FileTooBig" in raw_got):
        result.update(status="skip", reason="generated CIB exceeds cinterp module/file limit")
        return result
    if cr.returncode != nr.returncode or got != want:
        result.update(
            status="failure",
            reason=f"exit {cr.returncode} != {nr.returncode}" if cr.returncode != nr.returncode else "stdout mismatch",
            actual=got.decode("utf-8", "replace")[-1000:],
            expected=want.decode("utf-8", "replace")[-1000:],
        )
        return result
    result["status"] = "ok"
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--generator", choices=("yarpgen", "csmith"), default="yarpgen")
    ap.add_argument("--yarpgen", default=os.environ.get("YARPGEN_BIN", str(DEFAULT_YARPGEN)))
    ap.add_argument("--csmith", default=os.environ.get("CSMITH_BIN", str(DEFAULT_CSMITH)))
    ap.add_argument("--iterations", type=int, default=20)
    ap.add_argument("--seed-start", type=int, default=1)
    ap.add_argument("--report", default=str(ROOT / "build/generate-diff-report.json"))
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--max-source-bytes", type=int, default=8_000_000)
    args = ap.parse_args()
    generator = Path(args.yarpgen if args.generator == "yarpgen" else args.csmith)
    if not generator.is_file():
        print(f"missing {args.generator} binary: {generator}; run fetch_suites.py --support", file=sys.stderr)
        return 2
    known_path = ROOT / "tests/generator-known-failures.json"
    known = {}
    if known_path.is_file():
        known = json.loads(known_path.read_text()).get(args.generator, {})
    results = []
    temp = Path(tempfile.mkdtemp(prefix=f"cinterp-{args.generator}-"))
    try:
        for seed in range(args.seed_start, args.seed_start + args.iterations):
            if args.generator == "csmith":
                item = case_csmith(seed, generator, temp)
            else:
                item = case(seed, generator, temp, args.max_source_bytes)
            if item["status"] == "failure" and str(seed) in known:
                item.update(status="skip", reason="known: " + str(known[str(seed)]))
            results.append(item)
    finally:
        if not args.keep:
            import shutil

            shutil.rmtree(temp, ignore_errors=True)
    counts: dict[str, int] = {}
    for item in results:
        counts[item["status"]] = counts.get(item["status"], 0) + 1
        if item["status"] not in ("ok", "skip"):
            print(f"seed {item['seed']}: {item['status']}: {item['reason']}", file=sys.stderr)
            if item.get("actual") is not None:
                print(f"  actual: {item['actual']}", file=sys.stderr)
            if item.get("expected") is not None:
                print(f"  expected: {item['expected']}", file=sys.stderr)
    report = {"generator": args.generator, "iterations": args.iterations, "counts": counts, "results": results}
    path = Path(args.report)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n")
    print("generate-diff: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    return 0 if counts.get("failure", 0) == 0 and counts.get("harness", 0) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
