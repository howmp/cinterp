#!/usr/bin/env python3
"""Fetch pinned upstream C test suites into build/suites.

The upstream sources are not vendored. This script is intentionally explicit:
it fetches one or more fixed commits, optionally sparse-checkouts large trees,
and builds the small support libraries needed by the suite manifests.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "build/suites"

SPECS = {
    "c-testsuite": {
        "repo": "https://github.com/c-testsuite/c-testsuite",
        "commit": "5c7275656d751de0e68b2d340a95b5681858ed07",
        "sparse": [],
    },
    "tcc": {
        "repo": "https://github.com/TinyCC/tinycc",
        "commit": "e23dabed154a8495f3ac1ff3cc9d04fa1c207893",
        "sparse": [],
    },
    "chibicc": {
        "repo": "https://github.com/rui314/chibicc",
        "commit": "90d1f7f199cc55b13c7fdb5839d1409806633fdb",
        "sparse": [],
    },
    "libc-test": {
        "repo": "https://github.com/kraj/libc-test",
        "commit": "b7ec467969a53756258778fa7d9b045f912d1c93",
        "sparse": [],
    },
    "gcc-torture": {
        "repo": "https://github.com/gcc-mirror/gcc",
        "commit": "f75e33b7c1ddc42ce9d6d455e0076dbe373b46b5",
        "sparse": ["gcc/testsuite/gcc.c-torture", "gcc/testsuite/gcc.dg"],
    },
    "CompCert": {
        "repo": "https://github.com/AbsInt/CompCert",
        "commit": "e26caf9fa6cd91665c9e8ee2b5194f413c796821",
        "sparse": [],
        "submodules": ["test"],
    },
    "llvm-test-suite": {
        "repo": "https://github.com/llvm/llvm-test-suite",
        "commit": "28644d9795d11dcc30f5bdeb398a76a52ca53869",
        "sparse": ["SingleSource"],
    },
    "yarpgen": {
        "repo": "https://github.com/intel/yarpgen",
        "commit": "1adb290f453505838f3aa33dc571f292b0c1810f",
        "sparse": [],
    },
    "csmith": {
        "repo": "https://github.com/csmith-project/csmith",
        "commit": "0cdc710315cfee9035e22ef4363ca479270d1934",
        "sparse": [],
    },
}


def run(cmd: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def fetch(name: str, force: bool) -> Path:
    spec = SPECS[name]
    dest = DEST / name
    if dest.exists() and force:
        shutil.rmtree(dest)
    if not (dest / ".git").is_dir():
        dest.mkdir(parents=True, exist_ok=True)
        run(["git", "init", "-q", str(dest)])
        run(["git", "-C", str(dest), "remote", "add", "origin", spec["repo"]])
    try:
        current = subprocess.check_output(
            ["git", "-C", str(dest), "rev-parse", "HEAD"], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except subprocess.CalledProcessError:
        current = ""
    if current != spec["commit"]:
        run(["git", "-C", str(dest), "fetch", "--depth", "1", "--filter=blob:none", "origin", spec["commit"]])
        run(["git", "-C", str(dest), "checkout", "-q", "--detach", "FETCH_HEAD"])
    if spec.get("sparse"):
        run(["git", "-C", str(dest), "sparse-checkout", "init", "--cone"])
        run(["git", "-C", str(dest), "sparse-checkout", "set", *spec["sparse"]])
    if spec.get("submodules"):
        run(["git", "-C", str(dest), "submodule", "update", "--init", "--depth", "1", *spec["submodules"]])
    actual = subprocess.check_output(["git", "-C", str(dest), "rev-parse", "HEAD"], text=True).strip()
    if actual != spec["commit"]:
        raise RuntimeError(f"{name}: HEAD {actual} != pinned {spec['commit']}")
    return dest


def build_support() -> None:
    chibicc = DEST / "chibicc"
    if (chibicc / "test/common").is_file():
        run(["cc", "-x", "c", "-shared", "-fPIC", "-O0", str(chibicc / "test/common"), "-o", str(chibicc / "test/libchibicc_test.so")])
    libc = DEST / "libc-test"
    common = libc / "src/common"
    if (common / "print.c").is_file():
        sources = sorted(str(p) for p in common.glob("*.c"))
        run(["cc", "-shared", "-fPIC", "-O0", "-I", str(common), *sources, "-o", str(common / "libtest.so")])
    yarp = DEST / "yarpgen"
    if (yarp / "CMakeLists.txt").is_file():
        run(["cmake", "-S", str(yarp), "-B", str(yarp / "build"), "-DCMAKE_BUILD_TYPE=Release"])
        run(["cmake", "--build", str(yarp / "build"), "-j", "2"])
    csmith = DEST / "csmith"
    if (csmith / "CMakeLists.txt").is_file() and shutil.which("m4"):
        run(["cmake", "-S", str(csmith), "-B", str(csmith / "build"), "-DCMAKE_BUILD_TYPE=Release"])
        run(["cmake", "--build", str(csmith / "build"), "-j", "2"])


def main() -> int:
    global DEST
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", action="append", choices=sorted(SPECS), default=[])
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--support", action="store_true", help="build chibicc/libc-test/YARPGen support artifacts")
    ap.add_argument("--dest", default=str(DEST))
    args = ap.parse_args()
    DEST = Path(args.dest)
    names = sorted(SPECS) if args.all else (args.suite or [])
    if not names:
        print("choose --all or --suite NAME", file=sys.stderr)
        return 2
    for name in names:
        fetch(name, args.force)
    if args.support or args.all:
        build_support()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
