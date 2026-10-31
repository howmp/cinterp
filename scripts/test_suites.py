#!/usr/bin/env python3
"""Unified C test-suite runner for cinterp.

A suite is described by a JSON manifest under tests/manifests. The runner only
executes already-fetched sources; use scripts/fetch_suites.py to populate the
pinned upstream checkouts under build/suites.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime/zig-out/bin/cinterp-run"
RUNTIME_TARGETS = {
    "x86_64-windows": ROOT / "build/cross/cinterp-run64.exe",
    "i686-windows": ROOT / "build/cross/cinterp-run32.exe",
    "aarch64-linux": ROOT / "build/cross/cinterp-run-arm64",
}
PYTHONPATH = str(ROOT / "compiler/src")
RESULT_RE = re.compile(rb"^result: -?\d+\r?\n", re.MULTILINE)
EXPECT_RE = re.compile(rb"^// expect: *(-?\d+)\s*$", re.MULTILINE)
TARGETS = {
    "x86_64-linux": "sysv",
    "x86_64-windows": "win64",
    "i686-windows": "win32",
    "aarch64-linux": "aapcs64",
}
TIERS = ["smoke", "standard", "full", "nightly"]
STATUSES = ("ok", "skip", "compile", "load", "run", "timeout", "mismatch", "harness")


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


def discover_cases(manifest: dict, root: Path) -> list[dict]:
    skip, excluded = load_skip(manifest, root)
    explicit = manifest.get("cases")
    if explicit:
        cases = []
        for item in explicit:
            case = dict(item)
            case["id"] = str(case.get("id") or Path(case["source"]).stem)
            if case["id"] in excluded:
                continue
            if case["id"] in skip:
                case["skip"] = skip[case["id"]]
            cases.append(case)
        return cases
    pattern = manifest.get("source_glob", "*.c")
    expected_ext = manifest.get("expected_ext", ".expected")
    expected_dir = resolve_path(root, manifest.get("expected_dir"))
    cases = []
    for source in sorted(root.glob(pattern)):
        if not source.is_file():
            continue
        cid = source.stem
        if cid in excluded:
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
        if manifest.get("expect_marker"):
            text = source.read_bytes()[:4096]
            m = EXPECT_RE.search(text)
            if m:
                case["expected_result"] = int(m.group(1))
        cases.append(case)
    return cases


def case_skip(case: dict, target: str) -> str | None:
    if case.get("skip"):
        return str(case["skip"])
    by_target = case.get("skip_by_target", {})
    if target in by_target:
        return str(by_target[target])
    return None


def build_env(manifest: dict, root: Path) -> dict:
    env = dict(os.environ)
    env["PYTHONPATH"] = PYTHONPATH + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
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


def expected_bytes(case: dict, root: Path) -> bytes | None:
    if "expected_stdout" not in case:
        return None
    value = case.get("expected_stdout")
    if not value:
        return b""
    path = resolve_path(root, value)
    if not path or not path.is_file():
        raise FileNotFoundError(path)
    return norm_text(path.read_bytes())


def run_on_target(
    target: str,
    cib: Path,
    extra_lib: Path | None,
    case: dict,
    timeout: float,
    runner: dict,
):
    args = []
    if extra_lib:
        args += ["--lib", str(extra_lib)]
    args.append(str(cib))
    if case.get("entry"):
        args.append(str(case["entry"]))
    if target == "x86_64-linux":
        runtime = Path(runner.get("native_runtime") or RUNTIME)
        if not runtime.is_file():
            raise FileNotFoundError(runtime)
        return subprocess.run([str(runtime), *args], cwd=ROOT, capture_output=True, timeout=timeout)
    if target == "aarch64-linux":
        runtime = Path(runner["runtime_dir"]) / "cinterp-run-arm64"
        qemu = runner.get("qemu") or "qemu-aarch64"
        sysroot = runner.get("sysroot") or "/usr/aarch64-linux-gnu"
        if not runtime.is_file():
            raise FileNotFoundError(runtime)
        return subprocess.run([qemu, "-L", sysroot, str(runtime), *args], cwd=ROOT, capture_output=True, timeout=timeout)
    if target in ("x86_64-windows", "i686-windows"):
        exe_name = "cinterp-run64.exe" if target == "x86_64-windows" else "cinterp-run32.exe"
        runtime = Path(runner["runtime_dir"]) / exe_name
        if not runtime.is_file():
            raise FileNotFoundError(runtime)
        host = runner.get("windows_host")
        if not host:
            raise RuntimeError("--windows-host is required for Windows targets")
        remote = runner.get("remote_dir") or "C:/Users/admin/AppData/Local/Temp/cinterp_test/suites"
        remote = remote.rstrip("/")
        subprocess.run(["ssh", host, f"cmd /c if not exist {remote} mkdir {remote}"], capture_output=True, timeout=30)
        remote_cib = f"{remote}/{cib.name}"
        try:
            subprocess.run(["scp", "-q", str(cib), f"{host}:{remote_cib}"], check=True, capture_output=True, timeout=60)
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(f"scp package failed: {exc.stderr.decode('utf-8', 'replace').strip()}") from exc
        remote_lib = ""
        if extra_lib:
            remote_lib_path = f"{remote}/{extra_lib.name}"
            remote_lib = f' --lib "{remote_lib_path}"'
        remote_runtime = f"{remote}/{exe_name}"
        cmdline = f'cmd /c "{remote_runtime}"{remote_lib} "{remote_cib}"'
        if case.get("entry"):
            cmdline += f' "{case["entry"]}"'
        return subprocess.run(["ssh", host, cmdline], capture_output=True, timeout=timeout)
    raise RuntimeError(f"unsupported target {target}")


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
        result.update(status="skip", reason=skip)
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
    cmd = [sys.executable, "-m", "cinterp", "compile", str(source), "-o", str(cib)]
    if target != "x86_64-linux" or manifest.get("force_target"):
        cmd += ["--target", target]
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
        result.update(status="compile", reason=stderr.splitlines()[0] if stderr else f"rc={comp.returncode}")
        result["duration_ms"] = int((time.monotonic() - started) * 1000)
        return result
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
    combined = norm_text(run.stdout + run.stderr)
    clean, result_value = strip_result(combined)
    exp_stdout = expected_bytes(case, root) if manifest.get("compare_stdout", True) else None
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
    ap.add_argument("--target", default="x86_64-linux", choices=sorted(TARGETS))
    ap.add_argument("--tier", default="standard", choices=TIERS)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--report", default=str(ROOT / "build/test-report.json"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--runtime-dir", default=str(ROOT / "build/cross"))
    ap.add_argument("--windows-host", default=os.environ.get("HOST", ""))
    ap.add_argument("--remote-dir", default=os.environ.get("CINTERP_REMOTE_DIR", ""))
    ap.add_argument("--qemu", default=os.environ.get("QEMU", "qemu-aarch64"))
    ap.add_argument("--sysroot", default=os.environ.get("SYSROOT", "/usr/aarch64-linux-gnu"))
    ap.add_argument("--include-skipped", action="store_true", help="run skip-listed cases for re-triage")
    args = ap.parse_args()

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
        "windows_host": args.windows_host,
        "remote_dir": args.remote_dir,
        "qemu": args.qemu,
        "sysroot": args.sysroot,
        "include_skipped": args.include_skipped,
    }
    if args.target in ("x86_64-windows", "i686-windows"):
        if not runner_cfg["windows_host"]:
            print("--windows-host (or HOST) is required for Windows targets", file=sys.stderr)
            return 2
        remote = (runner_cfg["remote_dir"] or "C:/Users/admin/AppData/Local/Temp/cinterp_test/suites").rstrip("/")
        runner_cfg["remote_dir"] = remote
        subprocess.run(
            ["ssh", runner_cfg["windows_host"], f"cmd /c if not exist {remote.replace('/', chr(92))} mkdir {remote.replace('/', chr(92))}"],
            capture_output=True, timeout=30,
        )
        exe = "cinterp-run64.exe" if args.target == "x86_64-windows" else "cinterp-run32.exe"
        runtime = Path(args.runtime_dir) / exe
        if not runtime.is_file():
            print(f"missing Windows runtime: {runtime}", file=sys.stderr)
            return 2
        try:
            subprocess.run(
                ["scp", "-q", str(runtime), f"{runner_cfg['windows_host']}:{remote}/{exe}"],
                check=True, capture_output=True, timeout=60,
            )
        except subprocess.CalledProcessError as exc:
            print(f"cannot upload runtime: {exc.stderr.decode('utf-8', 'replace').strip()}", file=sys.stderr)
            return 2
    results = []
    temp_root = Path(tempfile.mkdtemp(prefix="cinterp-suites-"))
    for suite, manifest in selected.items():
        root = resolve_root(manifest)
        if not root.is_dir():
            print(f"missing suite root for {suite}: {root}", file=sys.stderr)
            return 2
        cases = discover_cases(manifest, root)
        if args.limit:
            cases = cases[: args.limit]
        env = build_env(manifest, root)
        outdir = Path(temp_root)
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
            futures = [
                ex.submit(run_case, suite, case, manifest, root, args.target, outdir, env, runner_cfg)
                for case in cases
            ]
            for fut in as_completed(futures):
                results.append(fut.result())
        if not args.keep:
            import shutil

            shutil.rmtree(outdir, ignore_errors=True)

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
    report = {
        "target": args.target,
        "excluded": {name: len([1 for line in (ROOT / str(manifest.get("repo_exclude_file", ""))).read_text().splitlines() if line.strip() and not line.startswith("#")]) if manifest.get("repo_exclude_file") and (ROOT / manifest["repo_exclude_file"]).is_file() else 0 for name, manifest in selected.items()},
        "tier": args.tier,
        "counts": counts,
        "error_classes": classes,
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
