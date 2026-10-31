#!/usr/bin/env python3
from __future__ import annotations
import argparse, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
PYTHONPATH = str(ROOT / "compiler/src")
RESULT_RE = re.compile(rb"^result: -?\d+\r?\n", re.MULTILINE)

def run_case(src: Path, outdir: Path) -> tuple[str, str]:
    expected_path = Path(str(src) + ".expected")
    expected = expected_path.read_bytes() if expected_path.exists() else b""
    cib = outdir / (src.stem + ".cib")
    env = dict(os.environ, PYTHONPATH=PYTHONPATH)
    try:
        comp = subprocess.run(
            [sys.executable, "-m", "cinterp", "compile", str(src), "-o", str(cib)],
            env=env, cwd=ROOT, capture_output=True, timeout=300,
        )
    except subprocess.TimeoutExpired:
        return src.stem, "compile-timeout"
    if comp.returncode != 0:
        msg = comp.stderr.decode("utf-8", "replace").strip().splitlines()
        return src.stem, "compile: " + (msg[0] if msg else "unknown")
    try:
        run = subprocess.run([str(RUNTIME), str(cib)], capture_output=True, timeout=300)
    except subprocess.TimeoutExpired:
        return src.stem, "run-timeout"
    output = RESULT_RE.sub(b"", run.stdout + run.stderr)
    if run.returncode != 0 or output != expected:
        return src.stem, "mismatch"
    return src.stem, "ok"

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.environ.get("C_TESTSUITE_DIR", "/tmp/c-testsuite/tests/single-exec"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--report", default="")
    ap.add_argument("--skip-file", default=str(ROOT / "tests/csuite/cinterp.skip"))
    args = ap.parse_args()
    directory = Path(args.dir)
    skip = set()
    skip_path = Path(args.skip_file)
    if skip_path.exists():
        skip = {line.strip() for line in skip_path.read_text().splitlines() if line.strip() and not line.startswith("#")}
    sources = [src for src in sorted(directory.glob("*.c")) if src.stem not in skip]
    if args.limit:
        sources = sources[: args.limit]
    results: list[tuple[str, str]] = []
    with tempfile.TemporaryDirectory(prefix="cinterp-csuite-") as td:
        outdir = Path(td)
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futures = [ex.submit(run_case, src, outdir) for src in sources]
            for fut in as_completed(futures):
                results.append(fut.result())
    results.sort()
    ok = sum(1 for _, s in results if s == "ok")
    counts: dict[str, int] = {}
    for _, status in results:
        key = status.split(":", 1)[0]
        counts[key] = counts.get(key, 0) + 1
    for name, status in results:
        if status != "ok":
            print(f"{name}: {status}")
    print(f"c-testsuite: {ok}/{len(results)} passed, {len(skip)} skipped; " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    if args.report:
        Path(args.report).write_text("\n".join(f"{n}\t{s}" for n, s in results) + "\n")
    return 0 if ok == len(results) else 1

if __name__ == "__main__":
    raise SystemExit(main())
