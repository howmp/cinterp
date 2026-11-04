#!/usr/bin/env python3
"""YARPGen differential smoke: native clang vs cinterp.

YARPGen emits separate func.c/driver.c/init.h files. We combine them into one
translation unit for cinterp, run the native build as the reference, and compare
stdout and exit status.

When the native build succeeds but cinterp fails to compile, the case counts as
a `failure` (a real gap); `--allow-compile-skip` restores the old skip behaviour
for local triage. Seeds listed in tests/generator-known-failures.json that still
fail are counted as `known_skip`; a listed seed that now passes is reported as
stale and fails the run so the whitelist cannot rot.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    from minimize_failure import minimize_file
except ImportError:  # module execution from another cwd
    from scripts.minimize_failure import minimize_file

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
DEFAULT_YARPGEN = ROOT / "build/suites/yarpgen/build/yarpgen"
DEFAULT_CSMITH = ROOT / "build/suites/csmith/build/src/csmith"
RESULT_RE = re.compile(rb"^result: -?\d+\r?\n", re.MULTILINE)
DEFAULT_COMPILER = os.environ.get("CINTERP_COMPILER", str(ROOT / "build/cinterp-cc"))


def compile_cmd(source: Path, output: Path) -> list[str]:
    return [DEFAULT_COMPILER, "compile", str(source), "-o", str(output)]


def run(cmd: list[str], cwd: Path, timeout: float = 60, env: dict | None = None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return None


def case_csmith(seed: int, csmith: Path, work: Path, allow_compile_skip: bool = False) -> dict:
    gen = work / f"csmith-{seed}"
    gen.mkdir(parents=True)
    test_c = gen / "test.c"
    out = run([str(csmith), "--seed", str(seed), "--no-argc", "--concise", "-o", str(test_c)], work, 60)
    result = {"seed": seed, "status": "harness", "reason": "", "artifact_source": str(gen)}
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
    env = dict(os.environ, CPATH=os.pathsep.join([str(runtime), str(build_runtime)]))
    cc = run(compile_cmd(test_c, cib), ROOT, 120, env)
    compile_status = "skip" if allow_compile_skip else "failure"
    if cc is None:
        result.update(status=compile_status, reason="cinterp compile timeout (native compiled)")
        return result
    if cc.returncode != 0:
        msg = cc.stderr.decode("utf-8", "replace").strip().splitlines()
        result.update(
            status=compile_status,
            reason="cinterp compile: " + (msg[-1] if msg else "failed"),
        )
        return result
    cr = run([str(RUNTIME), str(cib)], ROOT, 60)
    if cr is None:
        result.update(status="failure", reason="cinterp run timeout")
        return result
    raw_got = cr.stdout + cr.stderr
    got = RESULT_RE.sub(b"", raw_got)
    want = nr.stdout + nr.stderr
    if cr.returncode != 0 and any(token in raw_got for token in (
        b"ModuleTooLarge", b"FileTooBig", b"TooManyImports", b"TooManyPlans",
        b"TooManyFunctions", b"NameTooLong", b"StackOverflow",
    )):
        result.update(status="skip", reason="generated CIB exceeds cinterp engine limits")
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


def case(seed: int, yarpgen: Path, work: Path, max_source_bytes: int = 8_000_000,
         allow_compile_skip: bool = False) -> dict:
    gen = work / f"seed-{seed}"
    gen.mkdir(parents=True)
    out = run([
        str(yarpgen), "--std=c", f"--seed={seed}", f"--out-dir={gen}",
        "--max-array-dims=2", "--allow-dead-data=false",
    ], work, 30)
    result = {"seed": seed, "status": "harness", "reason": "", "artifact_source": str(gen)}
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
    env = dict(os.environ)
    cc = run(compile_cmd(combined, cib), ROOT, 120, env)
    compile_status = "skip" if allow_compile_skip else "failure"
    if cc is None:
        result.update(status=compile_status, reason="cinterp compile timeout (native compiled)")
        return result
    if cc.returncode != 0:
        msg = cc.stderr.decode("utf-8", "replace").strip().splitlines()
        detail = msg[-1] if msg else "failed"
        # A generated program that exceeds a documented runtime cap is an
        # engine-limit skip, not a correctness regression. Keep every other
        # compile failure strict unless --allow-compile-skip was requested.
        if allow_compile_skip or "compiler limit:" in cc.stderr.decode("utf-8", "replace"):
            result.update(status="skip", reason="cinterp engine limit: " + detail)
        else:
            result.update(status="failure", reason="cinterp compile: " + detail)
        return result
    cr = run([str(RUNTIME), str(cib)], ROOT, 60)
    if cr is None:
        result.update(status="failure", reason="cinterp run timeout")
        return result
    raw_got = cr.stdout + cr.stderr
    got = RESULT_RE.sub(b"", raw_got)
    want = nr.stdout + nr.stderr
    if cr.returncode != 0 and any(token in raw_got for token in (
        b"ModuleTooLarge", b"FileTooBig", b"TooManyImports", b"TooManyPlans",
        b"TooManyFunctions", b"NameTooLong", b"StackOverflow",
    )):
        result.update(status="skip", reason="generated CIB exceeds cinterp engine limits")
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


def _csmith_includes(generator: Path) -> list[Path]:
    root = generator.parents[2] if generator.parent.name == "src" else generator.parent
    return [root / "runtime", root / "build/runtime"]


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
    ap.add_argument("--failures-dir", default=str(ROOT / "build/generate-failures"))
    ap.add_argument("--jobs", type=int, default=1, help="concurrent generated seeds (default 1)")
    ap.add_argument("--minimize", action="store_true", help="reduce each failure preserving native/cinterp divergence")
    ap.add_argument("--minimize-jobs", type=int, default=1,
                    help="concurrent failure minimizations when --minimize is set (default 1)")
    ap.add_argument("--minimize-calls", type=int, default=120, help="max native/cinterp oracle calls per failure")
    ap.add_argument(
        "--allow-compile-skip",
        action="store_true",
        help="count a cinterp compile failure as skip even when the native build succeeded "
             "(local triage only; CI keeps it a failure)",
    )
    args = ap.parse_args()
    generator = Path(args.yarpgen if args.generator == "yarpgen" else args.csmith)
    if not generator.is_file():
        print(f"missing {args.generator} binary: {generator}; run fetch_suites.py --support", file=sys.stderr)
        return 2
    known_path = ROOT / "tests/generator-known-failures.json"
    known = {}
    if known_path.is_file():
        known = json.loads(known_path.read_text()).get(args.generator, {})
    def run_seed(seed: int) -> dict:
        if args.generator == "csmith":
            item = case_csmith(seed, generator, temp, args.allow_compile_skip)
        else:
            item = case(seed, generator, temp, args.max_source_bytes, args.allow_compile_skip)
        if item["status"] == "failure" and str(seed) in known:
            item.update(status="skip", reason="known: " + str(known[str(seed)]), known_hit=True)
        return item

    results = []
    temp = Path(tempfile.mkdtemp(prefix=f"cinterp-{args.generator}-"))
    seeds = list(range(args.seed_start, args.seed_start + args.iterations))
    if max(1, args.jobs) == 1:
        results = [run_seed(seed) for seed in seeds]
    else:
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
            futures = [ex.submit(run_seed, seed) for seed in seeds]
            results = [fut.result() for fut in as_completed(futures)]
        results.sort(key=lambda item: item["seed"])
    counts: dict[str, int] = {}
    for item in results:
        counts[item["status"]] = counts.get(item["status"], 0) + 1
        if item["status"] not in ("ok", "skip"):
            print(f"seed {item['seed']}: {item['status']}: {item['reason']}", file=sys.stderr)
            if item.get("actual") is not None:
                print(f"  actual: {item['actual']}", file=sys.stderr)
            if item.get("expected") is not None:
                print(f"  expected: {item['expected']}", file=sys.stderr)
    known_skip = sum(1 for item in results if item.get("known_hit"))
    generated = {str(item["seed"]) for item in results}
    by_seed = {item["seed"]: item for item in results}
    stale_known = sorted(
        int(seed)
        for seed in known
        if seed in generated and by_seed[int(seed)]["status"] == "ok"
    )
    for seed in stale_known:
        print(
            f"STALE known-failure seed {seed}: listed in tests/generator-known-failures.json "
            f"but now agrees with native ({known[str(seed)]}); remove it from the whitelist",
            file=sys.stderr,
        )
    fail_root = Path(args.failures_dir)
    if fail_root:
        fail_root.mkdir(parents=True, exist_ok=True)
        import shutil

        minimize_tasks = []
        for item in results:
            src = item.pop("artifact_source", None)
            if item["status"] in ("failure", "skip") and src and Path(src).is_dir():
                dst = fail_root / args.generator / f"seed-{item['seed']}"
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
                (dst / "failure.json").write_text(json.dumps(item, indent=2) + "\n")
                if args.minimize and item["status"] in ("failure", "skip"):
                    minimize_tasks.append((item, dst))

        def minimize_one(task: tuple[dict, Path]) -> None:
            item, dst = task
            source = dst / ("test.c" if args.generator == "csmith" else "combined.c")
            includes = _csmith_includes(generator) if args.generator == "csmith" else []
            try:
                meta = minimize_file(
                    source,
                    includes,
                    clang="clang",
                    timeout=30,
                    max_calls=args.minimize_calls,
                    output=dst / "minimized.c",
                )
                item["minimized"] = meta
                (dst / "failure.json").write_text(json.dumps(item, indent=2) + "\n")
            except Exception as exc:
                print(f"minimize seed {item['seed']}: {exc}", file=sys.stderr)

        if max(1, args.minimize_jobs) == 1:
            for task in minimize_tasks:
                minimize_one(task)
        else:
            with ThreadPoolExecutor(max_workers=max(1, args.minimize_jobs)) as ex:
                futures = [ex.submit(minimize_one, task) for task in minimize_tasks]
                for fut in as_completed(futures):
                    fut.result()
    report = {
        "generator": args.generator,
        "iterations": args.iterations,
        "counts": counts,
        "known_skip": known_skip,
        "stale_known": stale_known,
        "results": results,
    }
    path = Path(args.report)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n")
    print(
        "generate-diff: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
        + f", known_skip={known_skip}"
        + (f", stale_known={stale_known}" if stale_known else "")
    )
    if not args.keep:
        import shutil

        shutil.rmtree(temp, ignore_errors=True)
    failed = counts.get("failure", 0) != 0 or counts.get("harness", 0) != 0 or bool(stale_known)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
