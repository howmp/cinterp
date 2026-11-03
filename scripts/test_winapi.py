#!/usr/bin/env python3
"""Run examples/winapi.c through cinterp-cc under Wine.

``make test-winapi`` needs the cross-built runtimes in ``build/cross`` and a
working Wine installation. When neither is available the run is a no-op; that
used to exit 0 (a false green), so it now fails with status 2 unless
``--allow-skip`` is passed for a local convenience run.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPILER_CANDIDATES = (ROOT / "build/cinterp-cc.exe", ROOT / "build/cinterp-cc")
WINE = os.environ.get("WINE", "wine")
RUNTIME = {
    "x86_64-windows": (ROOT / "build/cross/cinterp-run64.exe", ROOT / "build/wine64"),
    "i686-windows": (ROOT / "build/cross/cinterp-run32.exe", ROOT / "build/wine32"),
}


def run(cmd: list[str], env: dict | None = None, timeout: int = 30):
    return subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)


def find_compiler() -> Path | None:
    override = os.environ.get("CINTERP_COMPILER")
    if override:
        return Path(override)
    for candidate in COMPILER_CANDIDATES:
        if candidate.is_file():
            return candidate
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--allow-skip",
        action="store_true",
        help="exit 0 when no target can run (local use); CI must not pass this",
    )
    args = parser.parse_args()

    compiler = find_compiler()
    if compiler is None or not compiler.is_file():
        print(
            "winapi: missing cinterp compiler: expected build/cinterp-cc.exe or "
            "build/cinterp-cc (run 'make compiler')",
            file=sys.stderr,
        )
        return 2

    failed = 0
    ran = 0
    wine_bin = WINE.split()[0]
    if shutil.which(wine_bin) is None:
        print(f"SKIP all targets: Wine not found ('{WINE}'); install Wine or set WINE=/path/to/wine")
    for target, (runner, prefix) in RUNTIME.items():
        if not runner.is_file():
            print(
                f"SKIP {target}: missing {runner} "
                "(build it with './scripts/test_cross.sh --targets win64,win32' or "
                "'make test-suites-cross')"
            )
            continue
        if shutil.which(wine_bin) is None:
            continue
        env = dict(os.environ, WINEPREFIX=str(prefix), WINEDEBUG="-all")
        cib = Path(f"/tmp/winapi-{target}.cib")
        comp = run([str(compiler), "compile", "--target", target, "examples/winapi.c", "-o", str(cib)])
        if comp.returncode != 0:
            print(f"FAIL {target}: compile: {comp.stderr.strip().splitlines()[-1:]}")
            failed += 1
            continue
        result = run([WINE, str(runner), str(cib)], env)
        ran += 1
        if result.returncode != 0 or "result: 7" not in (result.stdout + result.stderr):
            print(f"FAIL {target}: rc={result.returncode} out={(result.stdout + result.stderr).strip()[-160:]}")
            failed += 1
        else:
            print(f"OK {target}: result: 7")

    if failed:
        print(f"winapi: {failed} failure(s)", file=sys.stderr)
        return 1
    if ran == 0:
        print(
            "winapi: no target actually ran (missing build/cross runtimes or Wine), "
            "so nothing was verified",
            file=sys.stderr,
        )
        if args.allow_skip:
            print("winapi: --allow-skip given; treating as a local skip", file=sys.stderr)
            return 0
        print(
            "winapi: refusing to report success; install Wine and run "
            "'./scripts/test_cross.sh --targets win64,win32' first, "
            "or pass --allow-skip for a local run",
            file=sys.stderr,
        )
        return 2
    print(f"winapi: {ran} target(s) verified under Wine")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
