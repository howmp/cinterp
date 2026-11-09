#!/usr/bin/env python3
"""Verify plan acceptance from structured build artifacts.

The old checker grepped ``build/evidence-*.txt`` logs that nothing produced, so
it either crashed or verified nothing. This version reads the reports the build
actually writes:

  * ``build/test-suites-smoke.json``     (18 ok)
  * ``build/test-suites.json``           (395 ok / 100 skip)
  * ``build/test-suites-full.json``      (counts are derived from the report)
  * ``build/test-suites-nightly.json``   (consistency only)
  * ``build/generate-diff-nightly.json`` (0 failures)
  * ``build/release/cinterp-*.tar.gz``   (4 tarballs + SHA256SUMS; Linux ships bin/cinterp-cc)
  * ``build/cross/cinterp-run{64,32,-arm64}`` (cross runtimes)

Artifacts that a local run does not produce (full suites, cross runs, nightly,
release tarballs) are reported as NOT PROVIDED and do not fail the run; CI
artifacts or ``--require-*`` make them fatal. A run with no artifact at all
fails unless ``--allow-empty`` is passed, so an empty build tree cannot look
like a green evidence run.
"""
from __future__ import annotations

import argparse
import json
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
B = ROOT / "build"

PASS = "pass"
FAIL = "fail"
MISSING = "missing"

# (label, path, expected ok, expected skip, --require-* key)
SUITE_REPORTS = (
    ("test-suites-smoke", B / "test-suites-smoke.json", 18, 0, "smoke"),
    ("test-suites", B / "test-suites.json", 395, 100, "standard"),
    ("test-suites-full", B / "test-suites-full.json", None, None, "full"),
)
NIGHTLY_REPORT = B / "test-suites-nightly.json"
DIFF_REPORT = B / "generate-diff-nightly.json"
RELEASE_DIR = B / "release"
CROSS_DIR = B / "cross"
CROSS_RUNTIMES = (
    CROSS_DIR / "cinterp-run64.exe",
    CROSS_DIR / "cinterp-run32.exe",
    CROSS_DIR / "cinterp-run-arm64",
)


def display(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


class Checker:
    def __init__(self, require: set[str]) -> None:
        self.require = require
        self.checks: list[dict] = []
        self.artifacts = 0

    def _record(self, name: str, status: str, detail: str) -> None:
        self.checks.append({"check": name, "status": status, "ok": status == PASS, "detail": detail})
        prefix = {PASS: "PASS ", FAIL: "FAIL ", MISSING: "NOT PROVIDED "}[status]
        print(prefix + name + " — " + detail)

    def check(self, name: str, ok: bool, detail: str, artifact: bool = False) -> bool:
        self._record(name, PASS if ok else FAIL, detail)
        if ok and artifact:
            self.artifacts += 1
        return ok

    def missing(self, name: str, path: Path, hint: str, required: bool) -> None:
        detail = f"{display(path)} not provided"
        if hint:
            detail += f"; run {hint}"
        if required:
            self._record(name, FAIL, detail + " (required)")
        else:
            self._record(name, MISSING, detail)

    def required(self, key: str) -> bool:
        return "all" in self.require or key in self.require


def load_json(path: Path) -> tuple[dict | None, str]:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        return None, f"{type(exc).__name__}: {exc}"
    if not isinstance(data, dict):
        return None, "top-level JSON value is not an object"
    return data, ""


def report_counts(data: dict) -> tuple[dict, int, int]:
    counts = data.get("counts") if isinstance(data.get("counts"), dict) else {}
    total = sum(int(v) for v in counts.values() if isinstance(v, int))
    results = data.get("results")
    return counts, total, len(results) if isinstance(results, list) else 0


def hint_for_suite(label: str) -> str:
    return {
        "test-suites-smoke": "make test-suites-smoke",
        "test-suites": "make test-suites",
        "test-suites-full": "make test-suites-full",
        "test-suites-nightly": "make test-suites-nightly",
    }.get(label, "")


def check_suite_report(c: Checker, label: str, path: Path, expect_ok: int | None,
                       expect_skip: int | None, key: str) -> None:
    if not path.is_file():
        c.missing(label, path, hint_for_suite(label), c.required(key))
        return
    data, err = load_json(path)
    if data is None:
        c.check(label, False, f"unreadable report: {err}")
        return
    counts, total, n_results = report_counts(data)
    ok = int(counts.get("ok", 0))
    skip = int(counts.get("skip", 0))
    other = {k: v for k, v in counts.items() if k not in ("ok", "skip") and v}
    skip_classes = data.get("skip_classes") if isinstance(data.get("skip_classes"), dict) else {}
    known_failures = int(skip_classes.get("known-failure", 0))
    detail = f"ok={ok} skip={skip} total={total} results={n_results} known-failure={known_failures}"
    if other:
        detail += " unexpected=" + json.dumps(other, sort_keys=True)
    if expect_ok is not None and expect_skip is not None:
        want_total = expect_ok + expect_skip
        detail += f" (expected ok={expect_ok} skip={expect_skip} total={want_total})"
        ok_match = ok == expect_ok and skip == expect_skip and total == want_total
    else:
        # Full/nightly tiers are baseline-free: every discovered case must be
        # accounted for, and the report must expose known failures separately.
        ok_match = ok + skip == total
    consistent = n_results == total
    c.check(label, ok_match and consistent and not other,
            detail if consistent else detail + " (results length != counts total)",
            artifact=True)


def check_diff(c: Checker) -> None:
    required = c.required("nightly")
    if not DIFF_REPORT.is_file():
        c.missing("generate-diff-nightly", DIFF_REPORT, "make test-suites-nightly", required)
        return
    data, err = load_json(DIFF_REPORT)
    if data is None:
        c.check("generate-diff-nightly", False, f"unreadable report: {err}")
        return
    counts = data.get("counts") if isinstance(data.get("counts"), dict) else {}
    failures = int(counts.get("failure", 0))
    harness = int(counts.get("harness", 0))
    total = sum(int(v) for v in counts.values() if isinstance(v, int))
    iterations = int(data.get("iterations", 0))
    known_skip = int(data.get("known_skip", 0))
    stale = data.get("stale_known") or []
    detail = (
        f"iterations={iterations} total={total} failure={failures} harness={harness} "
        f"known_skip={known_skip}"
    )
    if stale:
        detail += f" stale_known={stale}"
    ok = failures == 0 and harness == 0 and not stale and (iterations == 0 or total == iterations)
    c.check("generate-diff-nightly", ok, detail, artifact=True)


def check_release(c: Checker) -> None:
    required = c.required("release")
    if not RELEASE_DIR.is_dir():
        c.missing("release tarballs", RELEASE_DIR, "make release-artifacts", required)
        return
    tarballs = sorted(RELEASE_DIR.glob("cinterp-*.tar.gz"))
    if not tarballs:
        c.missing("release tarballs", RELEASE_DIR, "make release-artifacts", required)
        return
    c.check("release tarballs", len(tarballs) == 4,
            f"{len(tarballs)} tarballs: " + ", ".join(t.name for t in tarballs),
            artifact=True)
    sums = RELEASE_DIR / "SHA256SUMS"
    if sums.is_file() and sums.stat().st_size > 0:
        body = sums.read_text(errors="replace")
        listed = [t.name for t in tarballs if t.name in body]
        c.check("release SHA256SUMS", len(listed) == len(tarballs),
                f"{sums.name} lists {len(listed)}/{len(tarballs)} tarballs", artifact=True)
    else:
        c.check("release SHA256SUMS", False, f"missing or empty {display(sums)}")
    linux = [t for t in tarballs if "-sysv-" in t.name]
    if not linux:
        c.check("release Linux tarball", False, "no cinterp-*-sysv-*.tar.gz tarball")
        return
    tar = linux[0]
    try:
        with tarfile.open(tar) as tf:
            members = tf.getnames()
    except (OSError, tarfile.TarError) as exc:
        c.check("release Linux tarball", False, f"{tar.name}: unreadable ({exc})")
        return
    has_compiler = any(name.endswith("/bin/cinterp-cc") for name in members)
    c.check("release Linux tarball", has_compiler,
            f"{tar.name} contains bin/cinterp-cc" if has_compiler
            else f"{tar.name} has no bin/cinterp-cc entry")


def check_cross(c: Checker) -> None:
    required = c.required("cross")
    present = [p for p in CROSS_RUNTIMES if p.is_file()]
    if not present:
        c.missing("cross runtimes", CROSS_DIR,
                  "./scripts/test/test_cross.sh --targets win64,win32,arm64 (needs Wine/qemu)",
                  required)
        return
    missing = [p.name for p in CROSS_RUNTIMES if not p.is_file() or p.stat().st_size == 0]
    c.check("cross runtimes", not missing,
            ", ".join(p.name for p in CROSS_RUNTIMES) if not missing
            else "missing/empty: " + ", ".join(missing), artifact=True)
    reports = [
        p for p in sorted(B.glob("test-suites-*.json"))
        if any(tag in p.name for tag in ("win64", "win32", "arm64", "cross"))
    ]
    if not reports:
        return
    bad = []
    for path in reports:
        data, err = load_json(path)
        if data is None:
            bad.append(f"{path.name}: {err}")
            continue
        counts, total, _ = report_counts(data)
        ok = int(counts.get("ok", 0))
        skip = int(counts.get("skip", 0))
        if ok + skip != total:
            bad.append(f"{path.name}: ok+skip={ok + skip} total={total}")
    c.check("cross suite reports", not bad,
            f"{len(reports)} report(s) accounted for" if not bad else "; ".join(bad),
            artifact=True)


def check_repo_invariants(c: Checker) -> None:
    makefile = (ROOT / "Makefile").read_text()
    test_sh = (ROOT / "scripts/test/test.sh").read_text()
    c.check("Makefile default compiler",
            "build/cinterp-cc" in makefile and "test: compiler" in makefile,
            "test target builds and uses build/cinterp-cc")
    c.check("test.sh default compiler",
            "build/cinterp-cc" in test_sh and "compiler" in test_sh,
            "scripts/test/test.sh runs the Zig compiler")
    c.check("Makefile evidence target", "\nevidence:" in makefile,
            "make evidence runs the checker")
    c.check("Makefile check-version target",
            "\ncheck-version:" in makefile and "scripts/tools/check_version.py" in makefile,
            "make check-version calls scripts/tools/check_version.py")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--require-full", action="store_true",
                    help="fail when build/test-suites-full.json is missing")
    ap.add_argument("--require-cross", action="store_true",
                    help="fail when the cross runtimes/reports are missing")
    ap.add_argument("--require-nightly", action="store_true",
                    help="fail when the nightly suite/diff reports are missing")
    ap.add_argument("--require-release", action="store_true",
                    help="fail when build/release tarballs are missing")
    ap.add_argument("--require-smoke", action="store_true",
                    help="fail when build/test-suites-smoke.json is missing")
    ap.add_argument("--require-standard", action="store_true",
                    help="fail when build/test-suites.json is missing")
    ap.add_argument("--require-all", action="store_true",
                    help="fail when any artifact is missing")
    ap.add_argument("--allow-empty", action="store_true",
                    help="do not fail when no artifact at all was provided")
    ap.add_argument("--report", default=str(B / "plan-verification.json"),
                    help="where to write the JSON report")
    args = ap.parse_args()

    require: set[str] = set()
    if args.require_all:
        require.add("all")
    for flag, key in (
        (args.require_full, "full"),
        (args.require_cross, "cross"),
        (args.require_nightly, "nightly"),
        (args.require_release, "release"),
        (args.require_smoke, "smoke"),
        (args.require_standard, "standard"),
    ):
        if flag:
            require.add(key)

    c = Checker(require)
    for label, path, expect_ok, expect_skip, key in SUITE_REPORTS:
        check_suite_report(c, label, path, expect_ok, expect_skip, key)
    check_suite_report(c, "test-suites-nightly", NIGHTLY_REPORT, None, None, "nightly")
    check_diff(c)
    check_release(c)
    check_cross(c)
    check_repo_invariants(c)

    if c.artifacts == 0:
        c.check("evidence present", args.allow_empty,
                "no build artifact was provided; run 'make evidence' "
                "(or pass --allow-empty to permit an empty check)")

    failed = [item for item in c.checks if item["status"] == FAIL]
    missing = [item for item in c.checks if item["status"] == MISSING]
    report = {
        "ok": not failed,
        "counts": {
            "total": len(c.checks),
            "passed": len([i for i in c.checks if i["status"] == PASS]),
            "failed": len(failed),
            "not_provided": len(missing),
        },
        "require": sorted(require),
        "checks": c.checks,
    }
    path = Path(args.report)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["counts"]))
    if failed:
        print(f"evidence: {len(failed)} check(s) failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
