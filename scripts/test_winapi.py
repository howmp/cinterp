#!/usr/bin/env python3
"""Run examples/winapi.c through Python and AST frontends under Wine."""
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
    py_env = dict(os.environ, PYTHONPATH=str(ROOT / "compiler/src"))
    failed = 0
    for target, (runner, prefix) in RUNTIME.items():
        if not runner.is_file():
            print(f"SKIP {target}: missing {runner}")
            continue
        env = dict(os.environ, WINEPREFIX=str(prefix), WINEDEBUG="-all")
        outputs = {}
        for kind in ("python", "ast"):
            cib = Path(f"/tmp/winapi-{target}-{kind}.cib")
            if kind == "python":
                comp = run(
                    [sys.executable, "-m", "cinterp", "compile", "examples/winapi.c",
                     "--target", target, "-o", str(cib)],
                    py_env,
                )
            else:
                comp = run([str(CC), "compile", "--target", target, "examples/winapi.c", "-o", str(cib)])
            if comp.returncode != 0:
                print(f"FAIL {target} {kind}: compile: {comp.stderr.strip().splitlines()[-1:]}")
                failed += 1
                continue
            result = run(["wine", str(runner), str(cib)], env)
            outputs[kind] = (result.returncode, result.stdout, result.stderr)
            if result.returncode != 0 or "result: 7" not in (result.stdout + result.stderr):
                print(f"FAIL {target} {kind}: rc={result.returncode} out={(result.stdout + result.stderr).strip()[-160:]}")
                failed += 1
        if "python" in outputs and "ast" in outputs:
            if outputs["python"] != outputs["ast"]:
                print(f"FAIL {target}: python/ast output differs")
                failed += 1
            else:
                print(f"OK {target}: python/ast both result: 7")
    if failed:
        print(f"winapi: {failed} failure(s)", file=sys.stderr)
        return 1
    print("winapi: python/ast parity under Wine")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
