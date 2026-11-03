#!/usr/bin/env python3
"""Verify P3/P4/P5 acceptance from evidence logs and artifacts."""
from __future__ import annotations

import json
import os
import re
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
B = ROOT / "build"
checks: list[dict] = []


def check(name: str, ok: bool, detail: str) -> None:
    checks.append({"check": name, "ok": bool(ok), "detail": detail})
    print(("PASS " if ok else "FAIL ") + name + " — " + detail)


def text(name: str) -> str:
    p = B / name
    return p.read_text(errors="replace") if p.is_file() else ""


def need(name: str, pattern: str, label: str, flags=0) -> None:
    body = text(name)
    m = re.search(pattern, body, flags)
    check(label, m is not None, (m.group(0) if m else f"missing in build/{name}"))


# ---- P3: csuite four targets -------------------------------------------------
for target in ("x86_64-linux", "aarch64-linux", "x86_64-windows", "i686-windows"):
    need("evidence-csuite.txt", rf"^{re.escape(target)} 17/17 bad \[\]$", f"P3 csuite {target} 17/17", re.M)
for f in ("build/cross/cinterp-run-arm64", "build/cross/cinterp-run64.exe", "build/cross/cinterp-run32.exe"):
    p = ROOT / f
    check(f"P3 runtime {f}", p.is_file() and p.stat().st_size > 0, f"{p.stat().st_size if p.exists() else 0} bytes")

# ---- P4: differential / generated diff / suites / lint / fuzz ----------------
diff = text("evidence-differential.txt")
names = ("hello", "arrays", "structs", "math", "bitfields", "ptrstruct", "longdouble")
check("P4 differential 7/7", all(re.search(rf"^OK {n} -> .+ \(native/zig agree\)$", diff, re.M) for n in names), "7 cases agree")
check("P4 differential no FAIL", "FAIL" not in diff, "no FAIL line")
gen = json.loads((B / "generate-diff-nightly.json").read_text())
check("P4 yarpgen 100 no failure", gen["counts"].get("failure", 0) == 0 and sum(gen["counts"].values()) == 100, json.dumps(gen["counts"]))
need("evidence-smoke.txt", r"suites: 17/17 passed, 0 skipped", "P4 smoke 17/17")
need("evidence-standard.txt", r"suites: 396/495 passed, 99 skipped", "P4 standard 396/495")
need("evidence-full.txt", r"suites: 4323/4521 passed, 198 skipped", "P4 full 4323/4521")
need("evidence-lint.txt", r"civm_lint: 3 package\(s\) OK", "P4 lint 3/3")
fuzz = text("evidence-fuzz.txt")
for pat in (
    r"fuzz: 1000 mutations, 0 crashes",
    r"fuzz-exec: 500 mutations, 0 crashes",
    r"fuzz-bytecode \(load-only\): 500 mutations, 0 crashes",
    r"fuzz-exec: 300 mutations, 0 crashes",
):
    check("P4 " + pat.split(":")[0], re.search(pat, fuzz) is not None, pat)
san = text("evidence-fuzz-sanitizer.txt")
for pat in (
    r"fuzz: 500 mutations, 0 crashes",
    r"fuzz-exec: 200 mutations, 0 crashes",
    r"fuzz-bytecode \(load-only\): 300 mutations, 0 crashes",
):
    check("P4 sanitizer " + pat.split(":")[0], re.search(pat, san) is not None, pat)
need("evidence-fuzz-capi-asan.txt", r"fuzz-capi-asan: 200 mutations, 0 crashes", "P4 C API sanitizer fuzz")

# ---- P5: default compiler, tests, size, release ------------------------------
body = text("evidence-make-test.txt")
check("P5 make test", "all tests passed" in body and "OK C embedding API" in body and "FAIL" not in body, "all tests passed + C API")
size = text("evidence-size.txt")
m = re.search(r"runtime ReleaseSmall: (\S+)", size)
check("P5 runtime size", m is not None, m.group(0) if m else "missing")
check("P5 hello.cib size", re.search(r"hello.cib: (\d+)", size) is not None, (re.search(r"hello.cib: (\d+)", size) or [""])[0] if re.search(r"hello.cib: (\d+)", size) else "missing")
check("P5 qsort CIB size", re.search(r"ffi_qsort.cib: (\d+)", size) is not None, (re.search(r"ffi_qsort.cib: (\d+)", size) or [""])[0] if re.search(r"ffi_qsort.cib: (\d+)", size) else "missing")
rel = B / "release"
tars = list(rel.glob("cinterp-*-*.tar.gz"))
check("P5 release tarballs", len(tars) == 4, f"{len(tars)} tarballs")
check("P5 release sums", (rel / "SHA256SUMS").is_file(), "SHA256SUMS")
linux_tar = rel / "cinterp-0.1.0-sysv-x86_64.tar.gz"
with tarfile.open(linux_tar) as tf:
    members = tf.getnames()
check("P5 tarball compiler", any(n.endswith("/bin/cinterp-cc") for n in members), "bin/cinterp-cc present")
smoke = text("evidence-release-smoke.txt")
check("P5 tarball smoke", "compile_rc=0" in smoke and "run_rc=0" in smoke and "result: 42" in smoke, "compile_rc=0 run_rc=0 result:42")
mk = (ROOT / "Makefile").read_text()
ts = (ROOT / "scripts/test.sh").read_text()
check("P5 Makefile default", "build/cinterp-cc" in mk and "test: compiler-zig" in mk, "default + compiler-zig target")
check("P5 test.sh default", "build/cinterp-cc" in ts and "compiler-zig" in ts, "Zig compiler default")
removed_compiler = "compiler" + "/src"
check("P5 Python compiler removed", removed_compiler not in mk and "test-py" not in mk, "no Python compiler path")

# ---- report -----------------------------------------------------------------
failed = [c for c in checks if not c["ok"]]
report = {
    "ok": not failed,
    "counts": {"total": len(checks), "passed": len(checks) - len(failed), "failed": len(failed)},
    "checks": checks,
}
(B / "plan-verification.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report["counts"]))
sys.exit(0 if not failed else 1)
