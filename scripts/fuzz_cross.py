#!/usr/bin/env python3
"""Run load-only package fuzzing against the cross-compiled runtimes."""
from __future__ import annotations

import argparse
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYTHONPATH = str(ROOT / "compiler/src")
SEEDS = ["hello", "arrays", "ffi_structs"]

TARGETS = {
    "aarch64-linux": {
        "zig": "aarch64-linux-gnu",
        "cib": "aarch64-linux",
        "exe": "cinterp-run",
        "prefix": ["qemu-aarch64", "-L", "/usr/aarch64-linux-gnu"],
    },
    "win64": {
        "zig": "x86_64-windows-gnu",
        "cib": "x86_64-windows",
        "exe": "cinterp-run.exe",
        "wine_arch": "win64",
    },
    "win32": {
        "zig": "x86-windows-gnu",
        "cib": "i686-windows",
        "exe": "cinterp-run.exe",
        "wine_arch": "win32",
    },
}


def mutate(data: bytes, rng: random.Random) -> bytes:
    kind = rng.randrange(4)
    if kind == 0:
        return data[: rng.randrange(0, len(data) + 1)]
    if kind == 1:
        buf = bytearray(data)
        for _ in range(rng.randrange(1, 9)):
            if buf:
                buf[rng.randrange(len(buf))] ^= 1 << rng.randrange(8)
        return bytes(buf)
    if kind == 2:
        buf = bytearray(data)
        for _ in range(rng.randrange(1, 5)):
            if buf:
                buf[rng.randrange(len(buf))] = rng.randrange(256)
        return bytes(buf)
    return data + bytes(rng.randrange(256) for _ in range(rng.randrange(1, 32)))


def compile_seed(name: str, target: str, out: Path) -> Path:
    env = dict(os.environ, PYTHONPATH=PYTHONPATH)
    package = out / f"{name}-{target}.cib"
    subprocess.run(
        [sys.executable, "-m", "cinterp", "compile",
         str(ROOT / "examples" / f"{name}.c"), "--target", target, "-o", str(package)],
        check=True, env=env, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return package


def build_runtime(name: str, info: dict) -> Path:
    dest = ROOT / "build/fuzz-cross" / name
    dest.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["zig", "build", f"-Dtarget={info['zig']}", "-Doptimize=ReleaseSmall"],
        check=True, cwd=ROOT / "runtime", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    src = ROOT / "runtime/zig-out/bin" / info["exe"]
    dst = dest / info["exe"]
    dst.write_bytes(src.read_bytes())
    return dst


def runner_for(name: str, info: dict, runtime: Path) -> list[str]:
    if sys.platform == "win32":
        return [str(runtime)]
    if "prefix" in info:
        return list(info["prefix"]) + [str(runtime)]
    wine = os.environ.get("WIN64_RUNNER" if name == "win64" else "WIN32_RUNNER", "wine")
    return [wine, str(runtime)]


def env_for(name: str, info: dict) -> dict:
    env = dict(os.environ)
    if "wine_arch" in info and sys.platform != "win32":
        prefix = ROOT / "build" / f"wine-{info['wine_arch']}"
        if not (prefix / "drive_c/windows/system32/kernel32.dll").exists():
            subprocess.run(
                ["wineboot", "-u"],
                env=dict(env, WINEPREFIX=str(prefix), WINEARCH=info["wine_arch"],
                         WINEDEBUG="-all"),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
            )
        env.update(
            WINEPREFIX=str(prefix),
            WINEARCH=info["wine_arch"],
            WINEDEBUG="-all",
        )
    return env


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", default="aarch64-linux,win64,win32")
    parser.add_argument("--iterations", type=int, default=100)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()

    names = [item for item in args.targets.split(",") if item]
    unknown = [name for name in names if name not in TARGETS]
    if unknown:
        print(f"unknown targets: {','.join(unknown)}", file=sys.stderr)
        return 2

    rng = random.Random(args.seed)
    crashes = timeouts = runs = 0
    with tempfile.TemporaryDirectory(prefix="cinterp-fuzz-cross-") as td:
        tmp = Path(td)
        for name in names:
            info = TARGETS[name]
            runtime = build_runtime(name, info)
            command = runner_for(name, info, runtime)
            env = env_for(name, info)
            seeds = [compile_seed(seed, info["cib"], tmp) for seed in SEEDS]
            for _ in range(args.iterations):
                data = rng.choice(seeds).read_bytes()
                candidate = tmp / "candidate.cib"
                candidate.write_bytes(mutate(data, rng))
                runs += 1
                try:
                    proc = subprocess.run(
                        command + ["--load-only", str(candidate)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=args.timeout,
                        cwd=tmp,
                        env=env,
                    )
                except subprocess.TimeoutExpired:
                    timeouts += 1
                    continue
                if proc.returncode < 0 or proc.returncode >= 128:
                    print(
                        f"CRASH {name} signal/abort rc={proc.returncode} "
                        f"on mutation #{runs}",
                        file=sys.stderr,
                    )
                    crashes += 1
    print(f"fuzz-cross: {runs} mutations, {crashes} crashes, {timeouts} timeouts")
    return 1 if crashes else 0


if __name__ == "__main__":
    raise SystemExit(main())
