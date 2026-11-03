#!/usr/bin/env python3
from __future__ import annotations
import argparse, os, random, signal, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
COMPILER = ROOT / "build/cinterp-cc"
BASE_SEEDS = ["hello", "arrays", "structs", "math", "bitfields", "ptrstruct", "longdouble"]
FFI_SEEDS = ["ffi_printf", "ffi_malloc", "ffi_snprintf", "ffi_qsort", "ffi_structs", "ffi_callback"]

def compile_seed(name: str, out: Path) -> Path:
    package = out / f"{name}.cib"
    src = str(ROOT / "examples" / f"{name}.c")
    subprocess.run([str(COMPILER), "compile", src, "-o", str(package)],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return package

def mutate(data: bytes, rng: random.Random) -> bytes:
    kind = rng.randrange(4)
    if kind == 0:
        return data[: rng.randrange(0, len(data) + 1)]
    if kind == 1:
        buf = bytearray(data)
        for _ in range(rng.randrange(1, 9)):
            if buf:
                pos = rng.randrange(len(buf))
                buf[pos] ^= 1 << rng.randrange(8)
        return bytes(buf)
    if kind == 2:
        buf = bytearray(data)
        for _ in range(rng.randrange(1, 5)):
            if buf:
                buf[rng.randrange(len(buf))] = rng.randrange(256)
        return bytes(buf)
    return data + bytes(rng.randrange(256) for _ in range(rng.randrange(1, 32)))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--iterations", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--runtime", type=Path, default=RUNTIME)
    ap.add_argument("--ffi", action="store_true", help="include packages that call native code")
    ap.add_argument(
        "--tolerate-faults",
        action="store_true",
        help="count SIGSEGV/SIGBUS/SIGILL as expected faults (mutated native calls)",
    )
    args = ap.parse_args()
    runtime = args.runtime.resolve()
    if not runtime.exists():
        print(f"missing runtime: {runtime}", file=sys.stderr)
        return 2
    seeds_names = BASE_SEEDS + (FFI_SEEDS if args.ffi else [])
    rng = random.Random(args.seed)
    crashes = timeouts = faults = runs = 0
    with tempfile.TemporaryDirectory(prefix="cinterp-fuzz-exec-") as td:
        tmp = Path(td)
        seeds = [compile_seed(name, tmp) for name in seeds_names]
        for _ in range(args.iterations):
            data = rng.choice(seeds).read_bytes()
            candidate = tmp / "candidate.cib"
            candidate.write_bytes(mutate(data, rng))
            runs += 1
            try:
                proc = subprocess.run([str(runtime), str(candidate)],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                      timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timeouts += 1
                continue
            stderr = proc.stderr.decode("utf-8", "replace")
            if proc.returncode < 0:
                sig = -proc.returncode
                safe_panic = sig == signal.SIGABRT and any(
                    marker in stderr
                    for marker in (
                        "Segmentation fault at address",
                        "General protection exception",
                        "Bus error",
                        "Illegal instruction",
                    )
                )
                if args.tolerate_faults and (
                    sig in (signal.SIGSEGV, signal.SIGBUS, signal.SIGILL) or safe_panic
                ):
                    # Corrupted bytecode may legitimately form arbitrary
                    # pointers; packages are trusted build products.
                    faults += 1
                    continue
            if proc.returncode < 0 or proc.returncode >= 128:
                crash_path = Path("/tmp/cinterp-fuzz-crash.cib")
                crash_path.write_bytes(candidate.read_bytes())
                print(f"CRASH signal/abort rc={proc.returncode} on mutation #{runs} (saved {crash_path})", file=sys.stderr)
                crashes += 1
    print(
        f"fuzz-exec: {runs} mutations, {crashes} crashes, "
        f"{faults} expected faults, {timeouts} timeouts"
    )
    return 1 if crashes else 0

if __name__ == "__main__":
    raise SystemExit(main())
