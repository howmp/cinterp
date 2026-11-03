#!/usr/bin/env python3
"""Run examples/winapi.c through cinterp-cc under Wine."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CC = ROOT / "build/cinterp-cc"
RUNTIME = {
    "x86_64-windows": (ROOT / "build/cross/cinterp-run64.exe", ROOT / "build/wine64"),
    "i686-windows": (ROOT / "build/cross/cinterp-run32.exe", ROOT / "build/wine32"),
}


def run(cmd: list[str], env: dict | None = None, timeout: int = 30):
    return subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)


def main() -> int:
    failed = 0
    for target, (runner, prefix) in RUNTIME.items():
        if not runner.is_file():
            print(f"SKIP {target}: missing {runner}")
            continue
        env = dict(os.environ, WINEPREFIX=str(prefix), WINEDEBUG="-all")
        cib = Path(f"/tmp/winapi-{target}.cib")
        comp = run([str(CC), "compile", "--target", target, "examples/winapi.c", "-o", str(cib)])
        if comp.returncode != 0:
            print(f"FAIL {target}: compile: {comp.stderr.strip().splitlines()[-1:]}")
            failed += 1
            continue
        result = run(["wine", str(runner), str(cib)], env)
        if result.returncode != 0 or "result: 7" not in (result.stdout + result.stderr):
            print(f"FAIL {target}: rc={result.returncode} out={(result.stdout + result.stderr).strip()[-160:]}")
            failed += 1
        else:
            print(f"OK {target}: result: 7")
    if failed:
        print(f"winapi: {failed} failure(s)", file=sys.stderr)
        return 1
    print("winapi: cinterp-cc frontend under Wine")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
