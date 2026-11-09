#!/usr/bin/env python3
"""Unified C test-suite runner for cinterp.

A suite is described by a JSON manifest under tests/manifests. The runner only
executes already-fetched sources; use scripts/test/fetch_suites.py to populate the
pinned upstream checkouts under build/suites.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import shutil
import sys

import re
import subprocess
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_COMPILER = ROOT / "build/cinterp-cc"
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
RESULT_RE = re.compile(rb"^result: -?\d+\r?\n", re.MULTILINE)
EXPECT_RE = re.compile(rb"^// expect: *(-?\d+)\s*$", re.MULTILINE)
DG_OPTIONS_RE = re.compile(r'dg-options\s+"([^"]*)"')
SUPPORTED_CC_FLAGS = {"-fgnu89-inline"}
TIERS = ["smoke", "standard", "full", "nightly"]
TARGET_NAMES = ["aarch64-linux", "i686-windows", "x86_64-linux", "x86_64-windows"]
WINDOWS_TARGETS = ("x86_64-windows", "i686-windows")
STATUSES = ("ok", "skip", "compile", "load", "run", "timeout", "mismatch", "harness")

WINE_LOCK = threading.Lock()
WINE_ENVS: dict[tuple[str, str], dict[str, str]] = {}


def norm_text(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def strip_result(data: bytes) -> tuple[bytes, int | None]:
    matches = list(RESULT_RE.finditer(data))
    if matches:
        value = int(matches[-1].group(0).split(b":", 1)[1].strip())
        return RESULT_RE.sub(b"", data), value
    # Test output without a trailing newline is followed directly by the
    # runtime's `result: N` diagnostic. Strip that tail as harness output.
    tail = re.search(rb"result: -?\d+\s*$", data)
    if tail:
        value = int(tail.group(0).split(b":", 1)[1].strip())
        return data[: tail.start()], value
    return data, None


def normalize_output(data: bytes, manifest: dict) -> bytes:
    data = norm_text(data)
    if manifest.get("normalize_source_paths"):
        # TCC/CompCert tests use __FILE__; the reference output often keeps
        # only the basename while cinterp sees an absolute checkout path.
        data = re.sub(rb"(?:[A-Za-z]:)?(?:/[^\s:]+)+/([^/\s:]+\.c)", rb"\1", data)
    if manifest.get("normalize_trailing_whitespace"):
        data = b"\n".join(line.rstrip() for line in data.split(b"\n"))
    if manifest.get("strip_compiler_diagnostics"):
        # Upstream TCC reference output includes its compiler warnings; cinterp
        # uses clang and does not emit those TCC-specific diagnostics.
        data = b"\n".join(line for line in data.split(b"\n") if b" warning:" not in line)
    return data


def resolve_root(manifest: dict) -> Path:
    root = str(manifest.get("root", "."))
    suites = Path(os.environ.get("CINTERP_SUITE_ROOT", str(ROOT / "build/suites")))
    root = root.replace("{SUITES}", str(suites))
    path = Path(root)
    if not path.is_absolute():
        path = ROOT / path
    return path


def resolve_path(root: Path, value: str | None) -> Path | None:
    if not value:
        return None
    path = Path(value.replace("{ROOT}", str(root)))
    if not path.is_absolute():
        path = root / path
    return path


def load_manifests() -> dict[str, dict]:
    out: dict[str, dict] = {}
    directory = ROOT / "tests/manifests"
    for path in sorted(directory.glob("*.json")):
        data = json.loads(path.read_text())
        data["_path"] = str(path)
        out[data["suite"]] = data
    return out


def load_skip(manifest: dict, root: Path) -> tuple[dict, set[str]]:
    skip = dict(manifest.get("skip", {}))
    skip_file = resolve_path(root, manifest.get("skip_file"))
    if manifest.get("repo_skip_file"):
        skip_file = ROOT / str(manifest["repo_skip_file"])
    if skip_file and skip_file.is_file():
        for line in skip_file.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            skip[parts[0]] = parts[1].strip() if len(parts) > 1 else "listed in " + str(skip_file)
    excluded: set[str] = set()
    exclude_file = resolve_path(root, manifest.get("exclude_file"))
    if manifest.get("repo_exclude_file"):
        exclude_file = ROOT / str(manifest["repo_exclude_file"])
    if exclude_file and exclude_file.is_file():
        for line in exclude_file.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            excluded.add(line.split()[0])
    return skip, excluded


def discover_cases(manifest: dict, root: Path, include_excluded: bool = False,
                   allow_duplicate_ids: bool = False) -> list[dict]:
    skip, excluded = load_skip(manifest, root)
    explicit = manifest.get("cases")
    if explicit:
        cases = []
        for item in explicit:
            case = dict(item)
            case["id"] = str(case.get("id") or Path(case["source"]).stem)
            if case["id"] in excluded and not include_excluded:
                continue
            if case["id"] in skip:
                case["skip"] = skip[case["id"]]
            if manifest.get("case_args", {}).get(case["id"]):
                case["args"] = list(manifest["case_args"][case["id"]])
            cases.append(case)
        return reject_duplicate_ids(cases, manifest, allow_duplicate_ids)
    pattern = manifest.get("source_glob", "*.c")
    expected_ext = manifest.get("expected_ext", ".expected")
    expected_dir = resolve_path(root, manifest.get("expected_dir"))
    cases = []
    for source in sorted(root.glob(pattern)):
        if not source.is_file():
            continue
        cid = source.stem
        if cid in excluded and not include_excluded:
            continue
        expected = None
        if expected_dir:
            expected = expected_dir / (cid + expected_ext)
        elif expected_ext:
            expected = source.with_name(cid + expected_ext)
        has_expected = bool(expected and expected.is_file())
        case = {
            "id": cid,
            "source": str(source.relative_to(root)),
            "expected_stdout": str(expected.relative_to(root)) if has_expected else "",
        }
        if manifest.get("expected_required") and not has_expected and cid not in skip:
            skip[cid] = "no reference output in suite manifest"
        if cid in skip:
            case["skip"] = skip[cid]
        if manifest.get("case_args", {}).get(cid):
            case["args"] = list(manifest["case_args"][cid])
        if manifest.get("expect_marker"):
            text = source.read_bytes()[:4096]
            m = EXPECT_RE.search(text)
            if m:
                case["expected_result"] = int(m.group(1))
        cases.append(case)
    return reject_duplicate_ids(cases, manifest, allow_duplicate_ids)


def reject_duplicate_ids(cases: list[dict], manifest: dict, allow_duplicate_ids: bool) -> list[dict]:
    """Reject duplicate case IDs; they silently double-run and corrupt reports.

    ``--allow-duplicate-ids`` downgrades the hard error to a warning and keeps
    the first occurrence, for local triage of an unedited manifest.
    """
    seen: set[str] = set()
    duplicates: list[str] = []
    unique: list[dict] = []
    for case in cases:
        cid = case["id"]
        if cid in seen:
            duplicates.append(cid)
            continue
        seen.add(cid)
        unique.append(case)
    if not duplicates:
        return cases
    label = manifest.get("suite", "?")
    listed = ", ".join(sorted(set(duplicates)))
    if not allow_duplicate_ids:
        raise ValueError(
            f"{label}: duplicate case ID(s) in {manifest.get('_path', 'manifest')}: {listed}\n"
            "  fix the manifest (give each case a unique id), or pass "
            "--allow-duplicate-ids to keep the first occurrence"
        )
    print(
        f"warning: {label}: duplicate case ID(s) {listed}; keeping the first occurrence "
        "(pass without --allow-duplicate-ids to make this an error)",
        file=sys.stderr,
    )
    return unique


def case_skip(case: dict, target: str) -> str | None:
    if case.get("skip"):
        return str(case["skip"])
    by_target = case.get("skip_by_target", {})
    if target in by_target:
        return str(by_target[target])
    return None


def classify_skip(reason: str) -> str:
    """Separate unsupported feature exclusions from observed failures.

    The manifests predate this distinction. Keep the existing status for
    compatibility, but make known crashes/mismatches/timeouts visible in the
    structured report instead of hiding them as an undifferentiated skip.
    """
    text = reason.lower()
    unsupported = (
        "non-goal",
        "unsupported",
        "dialect",
        "frontend",
        "harness/test-entry",
        "platform header",
        "platform/diagnostic",
        "threads:",
        "inline asm",
        "atomic",
        "external inline",
        "gcc builtin",
        ">64-bit",
        "compiler limit",
    )
    if any(token in text for token in unsupported):
        return "unsupported"
    known = (
        "mismatch",
        "timeout",
        "exit -",
        "run:",
        "bug",
        "crash",
        "sigsegv",
        "sigabrt",
        "abort/divergence",
        "unresolved external symbol",
        "failed",
    )
    if any(token in text for token in known):
        return "known-failure"
    return "unsupported"


def build_env(manifest: dict, root: Path) -> dict:
    env = dict(os.environ)
    cpath = []
    for item in manifest.get("cpath", []):
        p = resolve_path(root, item)
        if p:
            cpath.append(str(p))
    if cpath:
        env["CPATH"] = os.pathsep.join(cpath + ([env["CPATH"]] if env.get("CPATH") else []))
    return env


def prepare_wrapper(case: dict, manifest: dict, root: Path, temp: Path) -> Path:
    source = resolve_path(root, case["source"])
    if not source or not source.is_file():
        raise FileNotFoundError(source)
    text = source.read_text(errors="replace")
    changed = False
    for item in manifest.get("rewrite", []):
        old = str(item["from"])
        new = str(item["to"])
        if old in text:
            text = text.replace(old, new)
            changed = True
    prelude = manifest.get("prelude")
    if not prelude and not changed:
        return source
    if prelude:
        prelude_path = resolve_path(root, prelude)
        if not prelude_path or not prelude_path.is_file():
            raise FileNotFoundError(prelude_path)
        text = (
            '#include "' + str(prelude_path).replace("\\", "\\\\") + '"\n'
            '#include "' + str(source).replace("\\", "\\\\") + '"\n'
        ) + text
    target = temp / (case["id"] + "__prepared.c")
    target.write_text(text)
    return target


def expected_bytes(case: dict, root: Path, manifest: dict | None = None) -> bytes | None:
    if "expected_stdout" not in case:
        return None
    value = case.get("expected_stdout")
    if not value:
        return b""
    path = resolve_path(root, value)
    if not path or not path.is_file():
        raise FileNotFoundError(path)
    raw = path.read_bytes()
    return normalize_output(raw, manifest or {})


def run_on_target(
    target: str,
    cib: Path,
    extra_lib: Path | None,
    case: dict,
    timeout: float,
    runner: dict,
):
    args = [str(cib)]
    if case.get("args"):
        args.append("--")
        args.extend(str(a) for a in case["args"])
    run_env = None
    if extra_lib:
        # The simplified runtime CLI has no --lib; expose support libraries
        # through the host loader for native suites.
        run_env = os.environ.copy()
        old = run_env.get("LD_PRELOAD", "")
        run_env["LD_PRELOAD"] = str(extra_lib) + ((":" + old) if old else "")
    if target == "x86_64-linux":
        runtime = Path(runner.get("native_runtime") or RUNTIME)
        if not runtime.is_file():
            raise FileNotFoundError(runtime)
        return subprocess.run([str(runtime), *args], cwd=ROOT, env=run_env, capture_output=True, timeout=timeout)
    if target == "aarch64-linux":
        runtime = Path(runner["runtime_dir"]) / "cinterp-run-arm64"
        qemu = runner.get("qemu") or "qemu-aarch64"
        sysroot = runner.get("sysroot") or "/usr/aarch64-linux-gnu"
        if not runtime.is_file():
            raise FileNotFoundError(runtime)
        return subprocess.run([qemu, "-L", sysroot, str(runtime), *args], cwd=ROOT, capture_output=True, timeout=timeout)
    if target in WINDOWS_TARGETS:
        exe_name = "cinterp-run64.exe" if target == "x86_64-windows" else "cinterp-run32.exe"
        runtime = Path(runner["runtime_dir"]) / exe_name
        if not runtime.is_file():
            raise FileNotFoundError(runtime)
        if sys.platform == "win32":
            return subprocess.run([str(runtime), *args], cwd=ROOT, env=run_env, capture_output=True, timeout=timeout)
        return subprocess.run(
            [*wine_runner(target), str(runtime), *args],
            cwd=ROOT,
            env=wine_env(target),
            capture_output=True,
            timeout=timeout,
        )
    raise RuntimeError(f"unsupported target {target}")


def wine_runner(target: str) -> list[str]:
    """Wine command for a Windows target, overridable like test_cross.sh."""
    if target == "x86_64-windows":
        value = os.environ.get("WIN64_RUNNER", "")
        if not value:
            value = "wine64" if shutil.which("wine64") else "wine"
    else:
        value = os.environ.get("WIN32_RUNNER", "wine") or "wine"
    return shlex.split(value) or ["wine"]


def wine_env(target: str) -> dict[str, str]:
    """Environment for local Wine runs.

    `WINEDEBUG=-all` silences debug output; `ShowCrashDialog=0` in the prefix
    registry disables Wine's modal crash dialog, which otherwise can block a
    test run even when the failing process has already exited. Disabling
    Mono/Gecko overrides prevents their install prompts as well.
    """
    arch = "win64" if target == "x86_64-windows" else "win32"
    prefix = Path(os.environ.get("WINEPREFIX") or (ROOT / "build" / f"wine{arch}"))
    key = (str(prefix), arch)
    with WINE_LOCK:
        cached = WINE_ENVS.get(key)
        if cached is not None:
            return dict(cached)
        env = dict(os.environ)
        env.update(
            WINEPREFIX=str(prefix),
            WINEARCH=arch,
            WINEDEBUG="-all",
            WINEDLLOVERRIDES="mscoree,mshtml=",
        )
        if not (prefix / "drive_c/windows/system32/kernel32.dll").exists():
            wineboot = shutil.which("wineboot")
            if wineboot:
                subprocess.run(
                    [wineboot, "-u"],
                    env=env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
        subprocess.run(
            [
                *wine_runner(target),
                "reg",
                "add",
                r"HKCU\Software\Wine\WineDbg",
                "/v",
                "ShowCrashDialog",
                "/t",
                "REG_DWORD",
                "/d",
                "0",
                "/f",
            ],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        WINE_ENVS[key] = env
        return dict(env)


def compiler_fingerprint(compiler_path: Path) -> str:
    h = hashlib.sha256()
    try:
        st = compiler_path.stat()
        h.update(str(compiler_path.resolve()).encode())
        h.update(str(st.st_mtime_ns).encode())
        h.update(str(st.st_size).encode())
    except OSError:
        h.update(str(compiler_path).encode())
        h.update(b"missing")
    return h.hexdigest()


def source_cc_flags(source: Path) -> list[str]:
    """Return the small subset of dg-options we deliberately forward."""
    try:
        text = source.read_text(errors="replace")
    except OSError:
        return []
    out: list[str] = []
    for match in DG_OPTIONS_RE.findall(text):
        for flag in shlex.split(match):
            if flag in SUPPORTED_CC_FLAGS and flag not in out:
                out.append(flag)
    return out


def cib_cache_key(source: Path, case: dict, target: str, env: dict, manifest: dict,
                  compiler_path: Path, cc_flags: list[str]) -> str:
    h = hashlib.sha256()
    h.update(compiler_fingerprint(compiler_path).encode())
    h.update(target.encode())
    h.update(str(case.get("source", "")).encode())
    h.update(source.read_bytes())
    h.update(env.get("CPATH", "").encode())
    h.update(str(manifest.get("force_target", False)).encode())
    h.update("\0".join(cc_flags).encode())
    return h.hexdigest()


def summarize_failure(stderr: str, rc: int) -> str:
    lines = [line.strip() for line in stderr.splitlines() if line.strip()]
    if not lines:
        return f"rc={rc}"
    if any("Traceback (most recent call last):" in line for line in lines):
        return "compiler crash: " + lines[-1]
    for line in lines:
        if line.startswith("cinterp:") or re.search(r"\b(?:fatal error|error):", line, re.IGNORECASE):
            return line
    return lines[0]


def run_case(
    suite: str,
    case: dict,
    manifest: dict,
    root: Path,
    target: str,
    outdir: Path,
    env: dict,
    runner: dict,
) -> dict:
    cid = case["id"]
    started = time.monotonic()
    source = resolve_path(root, case["source"])
    result = {
        "suite": suite,
        "id": cid,
        "target": target,
        "source": str(source),
        "status": "harness",
        "reason": "",
        "error_class": "harness",
        "duration_ms": 0,
    }
    skip = None if runner.get("include_skipped") else case_skip(case, target)
    if skip:
        result.update(status="skip", reason=skip, skip_class=classify_skip(skip))
        return result
    work = outdir / suite / target / cid
    work.mkdir(parents=True, exist_ok=True)
    try:
        source = prepare_wrapper(case, manifest, root, work)
    except Exception as exc:
        result["reason"] = f"prepare: {exc}"
        return result
    cib = work / (cid + ".cib")
    timeout = float(case.get("timeout", manifest.get("timeout", 30)))
    compile_timeout = float(manifest.get("compile_timeout", 300))
    compiler_path = Path(runner["compiler_path"])
    cc_flags = source_cc_flags(source)
    cmd = [str(compiler_path), "compile", str(source), "-o", str(cib)]
    for flag in cc_flags:
        cmd += ["--cc-flag", flag]
    if target != "x86_64-linux" or manifest.get("force_target"):
        cmd += ["--target", target]
    cached = False
    cache_path: Path | None = None
    if runner.get("cib_cache"):
        cache_dir = runner["cib_cache"]
        cache_dir.mkdir(parents=True, exist_ok=True)
        cache_path = cache_dir / (
            cib_cache_key(source, case, target, env, manifest, compiler_path, cc_flags) + ".cib"
        )
        if cache_path.is_file():
            shutil.copyfile(cache_path, cib)
            cached = True
            result["cached"] = True

    if not cached:
        try:
            comp = subprocess.run(
                cmd, cwd=ROOT, env=env, capture_output=True, timeout=compile_timeout
            )
        except subprocess.TimeoutExpired:
            result.update(status="timeout", reason="compile timeout")
            result["duration_ms"] = int((time.monotonic() - started) * 1000)
            return result
        if comp.returncode != 0:
            stderr = norm_text(comp.stderr).decode("utf-8", "replace").strip()
            result.update(status="compile", reason=summarize_failure(stderr, comp.returncode))
            if stderr:
                result["detail"] = stderr[-2000:]
            result["duration_ms"] = int((time.monotonic() - started) * 1000)
            return result
    if not cached and cache_path is not None and cib.is_file():
        shutil.copyfile(cib, cache_path)

    if manifest.get("mode") == "compile":
        result.update(status="ok")
        result["duration_ms"] = int((time.monotonic() - started) * 1000)
        return result

    extra_lib = resolve_path(root, manifest.get("support_lib"))
    if target != "x86_64-linux" and extra_lib:
        result.update(status="skip", reason="cross-target support library not wired")
        return result
    try:
        run = run_on_target(target, cib, extra_lib, case, timeout, runner)
    except FileNotFoundError as exc:
        result.update(status="harness", reason=f"missing runtime: {exc}")
        return result
    except RuntimeError as exc:
        result.update(status="harness", reason=str(exc))
        return result
    except subprocess.TimeoutExpired:
        result.update(status="timeout", reason="run timeout")
        result["duration_ms"] = int((time.monotonic() - started) * 1000)
        return result
    combined = normalize_output(run.stdout + run.stderr, manifest)
    clean, result_value = strip_result(combined)
    exp_stdout = expected_bytes(case, root, manifest) if manifest.get("compare_stdout", True) else None
    expected_exit = case.get("expected_exit", manifest.get("expected_exit", 0))
    if exp_stdout is not None and clean.rstrip(b"\n") != exp_stdout.rstrip(b"\n"):
        result.update(status="mismatch", reason="stdout mismatch")
        result["actual"] = clean.decode("utf-8", "replace")[-2000:]
        result["expected"] = exp_stdout.decode("utf-8", "replace")[-2000:]
        result["duration_ms"] = int((time.monotonic() - started) * 1000)
        return result
    if "expected_result" in case or manifest.get("expect_marker"):
        expected_result = case.get("expected_result")
        if expected_result is not None and result_value != expected_result:
            result.update(status="mismatch", reason=f"result {result_value} != {expected_result}")
            result["duration_ms"] = int((time.monotonic() - started) * 1000)
            return result
    if expected_exit is not None and run.returncode != expected_exit:
        result.update(status="run", reason=f"exit {run.returncode} != {expected_exit}")
        result["actual"] = clean.decode("utf-8", "replace")[-2000:]
        result["duration_ms"] = int((time.monotonic() - started) * 1000)
        return result
    result.update(status="ok")
    result["duration_ms"] = int((time.monotonic() - started) * 1000)
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", action="append", default=[], help="suite name (repeatable)")
    ap.add_argument("--target", default="x86_64-linux", choices=TARGET_NAMES)
    ap.add_argument("--tier", default="standard", choices=TIERS)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--report", default=str(ROOT / "build/test-report.json"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--runtime-dir", default=str(ROOT / "build/cross"))
    ap.add_argument("--qemu", default=os.environ.get("QEMU", "qemu-aarch64"))
    ap.add_argument("--sysroot", default=os.environ.get("SYSROOT", "/usr/aarch64-linux-gnu"))
    ap.add_argument("--include-skipped", action="store_true", help="run skip-listed cases for re-triage")
    ap.add_argument("--cib-cache", default="", help="directory for content-addressed CIB cache")
    ap.add_argument("--compiler-path", default=str(DEFAULT_COMPILER),
                    help="path to the cinterp-cc executable")
    ap.add_argument("--include-excluded", action="store_true", help="include .excluded cases for re-triage")
    ap.add_argument("--allow-duplicate-ids", action="store_true",
                    help="warn about duplicate manifest case IDs and keep the first occurrence "
                         "instead of failing (local triage only)")
    ap.add_argument("--only", action="append", default=[], help="only run IDs (comma-separated, repeatable)")
    ap.add_argument("--emit-reasons", default="", help="write auditable ID<TAB>status: reason for non-ok cases")
    args = ap.parse_args()

    compiler_path = Path(args.compiler_path)
    if not compiler_path.is_file():
        print(f"missing compiler: {compiler_path} (run make compiler)", file=sys.stderr)
        return 2
    print(f"compiler: {compiler_path}", file=sys.stderr)

    manifests = load_manifests()
    selected: dict[str, dict] = {}
    if args.suite:
        for name in args.suite:
            if name not in manifests:
                print(f"unknown suite: {name}", file=sys.stderr)
                return 2
            selected[name] = manifests[name]
    else:
        tier_set = set(TIERS[: TIERS.index(args.tier) + 1])
        for name, manifest in manifests.items():
            if set(manifest.get("tiers", ["standard"])) & tier_set:
                selected[name] = manifest
    if not selected:
        print("no suites selected", file=sys.stderr)
        return 2
    if args.list:
        for name, manifest in selected.items():
            print(f"{name}: {manifest.get('description', '')}")
        return 0

    runner_cfg = {
        "native_runtime": ROOT / "runtime/zig-out/bin/cinterp-run",
        "runtime_dir": Path(args.runtime_dir),
        "qemu": args.qemu,
        "sysroot": args.sysroot,
        "include_skipped": args.include_skipped,
        "cib_cache": Path(args.cib_cache) if args.cib_cache else None,
        "compiler_path": str(compiler_path),
    }
    if args.target in WINDOWS_TARGETS:
        exe = "cinterp-run64.exe" if args.target == "x86_64-windows" else "cinterp-run32.exe"
        runtime = Path(args.runtime_dir) / exe
        if not runtime.is_file():
            print(f"missing Windows runtime: {runtime}", file=sys.stderr)
            return 2
        if sys.platform != "win32":
            wine = wine_runner(args.target)
            if shutil.which(wine[0]) is None:
                print(
                    f"missing Wine runner '{wine[0]}' for {args.target}; "
                    "install Wine or set WIN64_RUNNER/WIN32_RUNNER",
                    file=sys.stderr,
                )
                return 2
    results = []
    temp_root = Path(tempfile.mkdtemp(prefix="cinterp-suites-"))
    tasks = []
    for suite, manifest in selected.items():
        root = resolve_root(manifest)
        if not root.is_dir():
            print(f"missing suite root for {suite}: {root}", file=sys.stderr)
            return 2
        try:
            cases = discover_cases(manifest, root, args.include_excluded, args.allow_duplicate_ids)
        except ValueError as exc:
            print(f"manifest error: {exc}", file=sys.stderr)
            return 2
        only = {item.strip() for group in args.only for item in group.split(",") if item.strip()}
        if only:
            cases = [case for case in cases if case["id"] in only]
        if args.limit:
            cases = cases[: args.limit]
        env = build_env(manifest, root)
        for case in cases:
            tasks.append((suite, case, manifest, root, args.target, temp_root, env, runner_cfg))

    # One global pool across every selected suite. Per-suite pools left the CPU
    # idle at suite boundaries (and when a suite had fewer cases than workers);
    # the per-case work directory is `<temp>/<suite>/<target>/<id>`, so cases
    # from different suites cannot collide.
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        futures = [ex.submit(run_case, *task) for task in tasks]
        for fut in as_completed(futures):
            results.append(fut.result())
    if not args.keep:
        shutil.rmtree(temp_root, ignore_errors=True)

    results.sort(key=lambda x: (x["suite"], x["id"]))
    for item in results:
        if item["status"] == "skip":
            item["error_class"] = "skip"
        elif item["status"] != "ok":
            reason = item.get("reason", "")
            if "timeout" in reason:
                item["error_class"] = "timeout"
            elif item["status"] == "compile":
                item["error_class"] = "compile"
            elif item["status"] == "mismatch":
                item["error_class"] = "mismatch"
            elif item["status"] == "run":
                item["error_class"] = "run-error"
            else:
                item["error_class"] = item["status"]
        else:
            item["error_class"] = "ok"
    counts: dict[str, int] = {}
    classes: dict[str, int] = {}
    for item in results:
        counts[item["status"]] = counts.get(item["status"], 0) + 1
        classes[item["error_class"]] = classes.get(item["error_class"], 0) + 1
    for item in results:
        if item["status"] != "ok" and item["status"] != "skip":
            print(f"{item['suite']}/{item['id']}: {item['status']}: {item['reason']}", file=sys.stderr)
            if item.get("actual") is not None:
                print(f"  actual: {item['actual']}", file=sys.stderr)
            if item.get("expected") is not None:
                print(f"  expected: {item['expected']}", file=sys.stderr)
    if args.emit_reasons:
        lines = [
            f"{item['id']}\t{item['status']}: {item.get('reason', '')}"
            for item in results
            if item["status"] != "ok"
        ]
        reasons_path = Path(args.emit_reasons)
        reasons_path.parent.mkdir(parents=True, exist_ok=True)
        reasons_path.write_text("\n".join(lines) + ("\n" if lines else ""))

    skip_classes: dict[str, int] = {}
    for item in results:
        if item["status"] == "skip":
            klass = item.get("skip_class", "unsupported")
            skip_classes[klass] = skip_classes.get(klass, 0) + 1
    report = {
        "target": args.target,
        "excluded": {name: len([1 for line in (ROOT / str(manifest.get("repo_exclude_file", ""))).read_text().splitlines() if line.strip() and not line.startswith("#")]) if manifest.get("repo_exclude_file") and (ROOT / manifest["repo_exclude_file"]).is_file() else 0 for name, manifest in selected.items()},
        "tier": args.tier,
        "counts": counts,
        "error_classes": classes,
        "skip_classes": skip_classes,
        "results": results,
    }
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    total = len(results)
    passed = counts.get("ok", 0)
    skipped = counts.get("skip", 0)
    print(
        f"suites: {passed}/{total} passed, {skipped} skipped; "
        + ", ".join(f"{k}={v}" for k, v in sorted(counts.items() if counts else {}))
    )
    return 0 if counts.get("ok", 0) + skipped == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
