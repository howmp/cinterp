#!/usr/bin/env python3
"""Reduce a generated failing C program while preserving a native/cinterp divergence.

The oracle is deliberately the same comparison used by generate_diff:
native clang build/run versus cinterp compile/run.  A candidate is kept only
when it still has the same failure class (compile, run, or timeout).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
COMPILER = Path(os.environ.get("CINTERP_COMPILER", str(ROOT / "build/cinterp-cc")))
RESULT_RE = re.compile(rb"^result: -?\d+\r?\n", re.MULTILINE)


def normalize(raw: bytes) -> bytes:
    return RESULT_RE.sub(b"", raw)


def run(cmd, cwd: Path, timeout: float, env=None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return None


@dataclass
class Outcome:
    kind: str
    detail: str = ""
    actual: str = ""
    expected: str = ""


def evaluate(
    source: Path,
    work: Path,
    includes: list[Path],
    clang: str = "clang",
    timeout: float = 30,
) -> Outcome:
    source = source.resolve()
    native = work / ".min_native"
    compile_cmd = [clang, "-O0"]
    for inc in includes:
        compile_cmd += ["-I", str(inc)]
    compile_cmd += [str(source), "-o", str(native)]
    nc = run(compile_cmd, source.parent, max(30, timeout))
    if nc is None:
        return Outcome("native_timeout")
    if nc.returncode != 0:
        return Outcome("native_reject", nc.stderr.decode("utf-8", "replace")[-500:])
    nr = run([str(native)], source.parent, timeout)
    if nr is None:
        return Outcome("native_timeout")

    cib = work / ".min_candidate.cib"
    env = dict(os.environ)
    if includes:
        cpath = os.pathsep.join(str(p) for p in includes)
        env["CPATH"] = cpath + (os.pathsep + env["CPATH"] if env.get("CPATH") else "")
    cc = run(
        [str(COMPILER), "compile", str(source), "-o", str(cib)],
        ROOT,
        max(60, timeout),
        env,
    )
    if cc is None:
        return Outcome("compile_timeout")
    if cc.returncode != 0:
        msg = cc.stderr.decode("utf-8", "replace").strip().splitlines()
        return Outcome("compile", msg[-1] if msg else f"rc={cc.returncode}")

    cr = run([str(RUNTIME), str(cib)], source.parent, timeout)
    if cr is None:
        return Outcome("timeout")
    got = normalize(cr.stdout + cr.stderr)
    want = normalize(nr.stdout + nr.stderr)
    if cr.returncode != nr.returncode or got != want:
        reason = (
            f"exit {cr.returncode} != {nr.returncode}"
            if cr.returncode != nr.returncode
            else "stdout mismatch"
        )
        return Outcome(
            "run",
            reason,
            got.decode("utf-8", "replace")[-1000:],
            want.decode("utf-8", "replace")[-1000:],
        )
    return Outcome("ok")


def flatten_local_includes(path: Path, depth: int = 0, seen: set[Path] | None = None) -> str:
    """Inline quoted includes from the artifact directory before reducing.

    YARPGen's combined.c only contains two include lines; the real failure is in
    func.c/driver.c.  System includes and non-local includes remain untouched.
    """
    if depth > 8:
        return path.read_text(errors="replace")
    seen = seen or set()
    out: list[str] = []
    for line in path.read_text(errors="replace").splitlines():
        m = re.match(r'\s*#\s*include\s+"([^"]+)"\s*$', line)
        if m:
            inc = (path.parent / m.group(1)).resolve()
            if inc.is_file() and inc not in seen:
                seen.add(inc)
                out.extend(flatten_local_includes(inc, depth + 1, seen).splitlines())
                continue
        out.append(line)
    return "\n".join(out)


class Minimizer:
    def __init__(self, source: Path, includes: list[Path], clang: str, timeout: float, max_calls: int):
        self.source = source.resolve()
        self.work = self.source.parent
        self.includes = includes
        self.clang = clang
        self.timeout = timeout
        self.max_calls = max_calls
        self.calls = 0
        self.original = flatten_local_includes(self.source)
        self.original_lines = self.original.splitlines()
        self.candidate = self.work / ".min_candidate.c"
        self.original_outcome = evaluate(self.source, self.work, includes, clang, timeout)
        if self.original_outcome.kind in ("ok", "native_reject", "native_timeout"):
            raise RuntimeError(f"source does not have a cinterp failure: {self.original_outcome.kind}")
        self.kind = self.original_outcome.kind

    def predicate(self, lines: list[str]) -> bool:
        if self.calls >= self.max_calls:
            return False
        self.calls += 1
        self.candidate.write_text("\n".join(lines) + "\n")
        outcome = evaluate(self.candidate, self.work, self.includes, self.clang, self.timeout)
        return outcome.kind == self.kind

    def reduce(self) -> tuple[list[str], Outcome]:
        lines = list(self.original_lines)
        n = 2
        while len(lines) >= 2 and self.calls < self.max_calls:
            chunk = (len(lines) + n - 1) // n
            reduced = False
            for start in range(0, len(lines), chunk):
                candidate = lines[:start] + lines[start + chunk :]
                if candidate and self.predicate(candidate):
                    lines = candidate
                    n = max(2, n - 1)
                    reduced = True
                    break
            if not reduced:
                if n >= len(lines):
                    break
                n = min(len(lines), n * 2)
        # Greedy single-line pass catches interdependent chunks.
        changed = True
        while changed and self.calls < self.max_calls:
            changed = False
            for i in range(len(lines) - 1, -1, -1):
                candidate = lines[:i] + lines[i + 1 :]
                if candidate and self.predicate(candidate):
                    lines = candidate
                    changed = True
        return lines, self.original_outcome

    def write(self, lines: list[str], outcome: Outcome, output: Path) -> None:
        output.write_text("\n".join(lines) + "\n")
        minimized_outcome = evaluate(output, self.work, self.includes, self.clang, self.timeout)
        cib = output.with_suffix(".cib")
        env = dict(os.environ)
        if self.includes:
            env["CPATH"] = os.pathsep.join(str(p) for p in self.includes)
        cc = run(
            [str(COMPILER), "compile", str(output), "-o", str(cib)],
            ROOT,
            60,
            env,
        )
        meta = {
            "source": str(self.source),
            "output": str(output),
            "failure_kind": self.kind,
            "original_outcome": outcome.__dict__,
            "minimized_outcome": minimized_outcome.__dict__,
            "predicate_calls": self.calls,
            "original_bytes": len(self.original.encode()),
            "minimized_bytes": len(output.read_bytes()),
            "original_lines": len(self.original_lines),
            "minimized_lines": len(lines),
        }
        if cc is not None and cc.returncode == 0:
            meta["cib"] = str(cib)
        else:
            meta["cib_error"] = (cc.stderr.decode("utf-8", "replace")[-500:] if cc else "timeout")
        output.with_suffix(".json").write_text(json_dumps(meta))
        for temp in (self.candidate, self.work / ".min_candidate.cib", self.work / ".min_native"):
            temp.unlink(missing_ok=True)


def json_dumps(value) -> str:
    return json.dumps(value, indent=2) + "\n"


def minimize_file(
    source: Path,
    includes: list[Path] | None = None,
    clang: str = "clang",
    timeout: float = 30,
    max_calls: int = 120,
    output: Path | None = None,
) -> dict:
    m = Minimizer(source, includes or [], clang, timeout, max_calls)
    lines, outcome = m.reduce()
    out = output or (source.parent / "minimized.c")
    m.write(lines, outcome, out)
    meta = json.loads(out.with_suffix(".json").read_text())
    return meta


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True)
    ap.add_argument("--include", action="append", default=[])
    ap.add_argument("--clang", default="clang")
    ap.add_argument("--timeout", type=float, default=30)
    ap.add_argument("--max-calls", type=int, default=120)
    ap.add_argument("--output", default="")
    args = ap.parse_args()
    try:
        meta = minimize_file(
            Path(args.source),
            [Path(p) for p in args.include],
            args.clang,
            args.timeout,
            args.max_calls,
            Path(args.output) if args.output else None,
        )
    except Exception as exc:
        print(f"minimize-failure: {exc}", file=sys.stderr)
        return 1
    print(
        "minimize-failure: "
        f"{meta['original_lines']} -> {meta['minimized_lines']} lines, "
        f"{meta['original_bytes']} -> {meta['minimized_bytes']} bytes, "
        f"kind={meta['failure_kind']}, calls={meta['predicate_calls']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
