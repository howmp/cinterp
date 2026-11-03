#!/usr/bin/env python3
"""Compare the AST and legacy IR frontends on the executable corpus.

All examples and csuite cases must produce byte-identical CIBs. A small,
explicit allowlist records the remaining differences. Every entry names the
root cause and the exact module/import shape it is allowed to change, so an
unexpected section, changed function or added import still fails.

The allowlist may only contain cases where the AST output is the correct one
and matching legacy would mean reproducing a legacy parsing bug. Entries that
become byte-identical are reported as stale: remove them instead of leaving a
dead exception behind.
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CC = Path(os.environ.get("CINTERP_CC", ROOT / "build/cinterp-cc"))

# path -> {
#   reason: human-readable root cause,
#   sections: CIB sections that are allowed to differ,
#   functions: CIVM functions whose code is allowed to differ,
#   imports: symbols the AST is allowed to add to CIPI (legacy has no extras),
# }
ALLOW: dict[str, dict] = {
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/20021010-2.c": {
        "reason": "inttoptr global image: AST writes 40960, legacy writes 0",
        "sections": {"module"},
        "functions": {"main"},
        "imports": set(),
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/pr49886.c": {
        "reason": "call whose callee name ends in 'null' is kept by AST, dropped by legacy",
        "sections": {"module"},
        "functions": {"main"},
        "imports": set(),
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/compile/20030708-1.c": {
        "reason": "external constant @a is imported/addressed by AST, legacy lowers it to 0",
        "sections": {"module", "imports"},
        "functions": {"foo"},
        "imports": {"a"},
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/compile/20031124-1.c": {
        "reason": "external constant @stop is imported/addressed by AST, legacy lowers it to 0",
        "sections": {"module", "imports"},
        "functions": {"f"},
        "imports": {"stop"},
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/compile/20040708-1.c": {
        "reason": "external constant method tables are imported/addressed by AST, legacy lowers them to 0",
        "sections": {"module", "imports"},
        "functions": {"proc_mutex_choose_method"},
        "imports": {
            "apr_proc_mutex_unix_fcntl_methods",
            "apr_proc_mutex_unix_sysv_methods",
            "apr_proc_mutex_unix_proc_pthread_methods",
        },
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/compile/20110913-1.c": {
        "reason": "external constant __exp_deltatable is imported/addressed by AST, legacy lowers it to 0",
        "sections": {"module", "imports"},
        "functions": {"__ieee754_expf"},
        "imports": {"__exp_deltatable"},
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/compile/980816-1.c": {
        "reason": "external constant XtStrings is imported/addressed by AST, legacy lowers it to 0",
        "sections": {"module", "imports"},
        "functions": {"AddButtons"},
        "imports": {"XtStrings"},
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/compile/pr19853.c": {
        "reason": "legacy matches 'global' inside @global_int and drops @test.const_test; AST keeps its layout",
        "sections": {"module"},
        "functions": {"test"},
        "imports": set(),
    },
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/compile/pr39983.c": {
        "reason": "external constant @a is imported/addressed by AST, legacy lowers it to 0",
        "sections": {"module", "imports"},
        "functions": {"foo"},
        "imports": {"a"},
    },
    "build/suites/llvm-test-suite/SingleSource/Regression/C/2003-06-16-InvalidInitializer.c": {
        "reason": "inttoptr global image: AST writes 8, legacy writes 0",
        "sections": {"module"},
        "functions": {"main"},
        "imports": set(),
    },
}


# Former allowlist entries that became byte-identical after both frontends
# agreed to skip LLVM linker metadata globals. They stay in the corpus so a
# regression shows up as an unexpected difference instead of being forgotten.
EXTRA = {
    "build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/pr78791.c",
    "build/suites/llvm-test-suite/SingleSource/Regression/C/gcc-c-torture/execute/20101011-1.c",
}


def u16(b: bytes, o: int) -> int:
    return struct.unpack_from("<H", b, o)[0]


def u32(b: bytes, o: int) -> int:
    return struct.unpack_from("<I", b, o)[0]


def split_cib(data: bytes) -> dict[str, bytes]:
    if data[:5] != b"CIPKG" or data[5] != 2:
        raise ValueError("bad CIPKG header")
    lens = struct.unpack_from("<IIII", data, 9)
    names = ("module", "plans", "meta", "imports")
    off = 25
    out: dict[str, bytes] = {}
    for name, length in zip(names, lens):
        out[name] = data[off:off + length]
        off += length
    if off != len(data):
        raise ValueError("CIPKG section lengths do not cover the package")
    return out


def civm_functions(module: bytes) -> list[tuple[str, int, int, bytes]]:
    if module[:4] != b"CIVM":
        raise ValueError("bad CIVM header")
    count = u16(module, 6)
    p = 10
    funcs: list[tuple[str, int, int, bytes]] = []
    for _ in range(count):
        nlen = module[p]
        p += 1
        name = module[p:p + nlen].decode("utf-8", "replace")
        p += nlen
        params = u16(module, p)
        locals_ = u16(module, p + 2)
        clen = u32(module, p + 4)
        p += 8
        funcs.append((name, params, locals_, module[p:p + clen]))
        p += clen
    if p != len(module):
        raise ValueError("CIVM trailing bytes")
    return funcs


def cipi_imports(imports: bytes) -> list[str]:
    if imports[:4] != b"CIPI":
        raise ValueError("bad CIPI header")
    count = u16(imports, 6)
    p = 10
    names: list[str] = []
    for _ in range(count):
        p += 8  # plan index, kind, flags, conv, pad, u16 reserved
        nlen = imports[p]
        p += 1
        names.append(imports[p:p + nlen].decode("utf-8", "replace"))
        p += nlen + 1  # name + chain byte
        for _ in range(2):  # libc.so.6 / libm.so.6 (or ucrtbase / msvcrt)
            p += 1  # SONAME flag
            llen = imports[p]
            p += 1
            p += llen
            slen = imports[p]
            p += 1
            p += slen
            p += 3  # ordinal u16 + version u8
    if p != len(imports):
        raise ValueError("CIPI trailing bytes")
    return names


def compare(a: bytes, b: bytes) -> tuple[set[str], list[str], list[str], set[str], set[str]]:
    """Return (changed sections, changed functions, header changes, added, removed imports)."""
    sa, sb = split_cib(a), split_cib(b)
    changed = {name for name in sa if sa[name] != sb[name]}

    fa = {f[0]: f for f in civm_functions(sa["module"])}
    fb = {f[0]: f for f in civm_functions(sb["module"])}
    changed_funcs: list[str] = []
    header_changes: list[str] = []
    if list(fa) != list(fb):
        changed_funcs = sorted(set(fa) | set(fb))
        header_changes.append("function list/order")
    else:
        for name in fa:
            if fa[name][1:3] != fb[name][1:3]:
                header_changes.append(name)
            if fa[name][3] != fb[name][3]:
                changed_funcs.append(name)

    ia = set(cipi_imports(sa["imports"]))
    ib = set(cipi_imports(sb["imports"]))
    return changed, changed_funcs, header_changes, ib - ia, ia - ib


def compile_one(src: Path, mode: str, out: Path) -> int:
    return subprocess.run(
        [str(CC), "compile", "--ir-parser=" + mode, str(src), "-o", str(out)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    ).returncode


def main() -> int:
    if not CC.is_file():
        print(f"parser-parity: missing {CC}", file=sys.stderr)
        return 2
    sources = sorted((ROOT / "examples").glob("*.c")) + sorted((ROOT / "tests/csuite").glob("*.c"))
    # Include known allowlisted cases and the former metadata cases when suites
    # are fetched.
    for rel in list(ALLOW) + sorted(EXTRA):
        p = ROOT / rel
        if p.is_file():
            sources.append(p)

    known = 0
    identical = 0
    skipped = 0
    unexpected: list[str] = []
    stale: list[str] = []
    failed_allowed: list[str] = []
    wrong_shape: list[str] = []
    with tempfile.TemporaryDirectory(prefix="cinterp-parity-") as td:
        tmp = Path(td)
        for src in sources:
            rel = str(src.relative_to(ROOT))
            a = tmp / "l.cib"
            b = tmp / "a.cib"
            ra = compile_one(src, "legacy", a)
            rb = compile_one(src, "ast", b)
            if ra != 0 or rb != 0:
                skipped += 1
                if rel in ALLOW:
                    failed_allowed.append(rel)
                continue
            a_bytes = a.read_bytes()
            b_bytes = b.read_bytes()
            if a_bytes == b_bytes:
                identical += 1
                if rel in ALLOW:
                    stale.append(rel)
                continue
            if rel not in ALLOW:
                unexpected.append(rel)
                continue
            known += 1
            case = ALLOW[rel]
            changed, funcs, headers, added, removed = compare(a_bytes, b_bytes)
            if changed != case["sections"] or set(funcs) != case["functions"] or headers:
                wrong_shape.append(
                    f"{rel}: sections={sorted(changed)} functions={funcs} headers={headers}"
                )
            if added != case["imports"] or removed:
                wrong_shape.append(
                    f"{rel}: added imports={sorted(added)} removed imports={sorted(removed)}"
                )
    print(
        f"parser-parity: identical={identical} known-diff={known} skipped={skipped} "
        f"unexpected={len(unexpected)} stale={len(stale)}"
    )
    for rel in unexpected:
        print("UNEXPECTED " + rel, file=sys.stderr)
    for rel in stale:
        print("STALE allowlist entry (now byte-identical): " + rel, file=sys.stderr)
    for rel in failed_allowed:
        print("FAILED allowlisted source (one frontend did not compile): " + rel, file=sys.stderr)
    for msg in wrong_shape:
        print("WRONG DIFF SHAPE: " + msg, file=sys.stderr)
    return 0 if not (unexpected or stale or failed_allowed or wrong_shape) else 1


if __name__ == "__main__":
    raise SystemExit(main())
