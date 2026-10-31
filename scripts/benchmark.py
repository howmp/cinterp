#!/usr/bin/env python3
from __future__ import annotations
import os, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
PYTHONPATH = str(ROOT / "compiler/src")
CASES = ["hello", "arrays", "math", "bitfields", "ptrstruct", "longdouble", "ffi_printf"]
ITERS = 20

def main() -> int:
    env = dict(os.environ, PYTHONPATH=PYTHONPATH)
    with tempfile.TemporaryDirectory(prefix="cinterp-bench-") as td:
        for name in CASES:
            cib = Path(td) / f"{name}.cib"
            subprocess.run([sys.executable, "-m", "cinterp", "compile", str(ROOT / "examples" / f"{name}.c"), "-o", str(cib)],
                           env=env, cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([str(RUNTIME), str(cib)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            start = time.perf_counter()
            for _ in range(ITERS):
                subprocess.run([str(RUNTIME), str(cib)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            elapsed = (time.perf_counter() - start) / ITERS
            print(f"{name:16s} {elapsed * 1e6:10.1f} us/run")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
