#!/usr/bin/env python3
"""Validate that every cinterp version source agrees with the root VERSION.

Checked sources:

* ``VERSION`` (authoritative)
* ``runtime/build.zig.zon`` — the runtime package version
* ``packaging/rust/cinterp-sys/Cargo.toml.in`` — the Rust crate version
  (either the ``@VERSION@`` placeholder or a literal that matches VERSION)
* the release tag — ``--tag TAG`` or, in GitHub Actions, ``GITHUB_REF_NAME``
  when the ref really is a tag (``GITHUB_REF_TYPE=tag`` or ``refs/tags/...``).
  Branch refs such as ``workflow_dispatch`` on ``main`` are skipped.
* SBoM documents — every ``--sbom PATH`` argument (``*`` globs allowed).
  Paths are resolved relative to the repository root.

Exit status is 0 when all checked sources agree and 1 otherwise. Each failure
names the file and the two values involved. ``make check-version`` and the
release workflow call this script before publishing anything.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SEMVER_RE = re.compile(
    r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)
ZON_VERSION_RE = re.compile(r'\.version\s*=\s*"([^"]+)"')
CARGO_VERSION_RE = re.compile(r'^\s*version\s*=\s*"([^"]+)"', re.MULTILINE)
TAG_RE = re.compile(
    r"^v?(?P<semver>\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)$"
)
CARGO_PLACEHOLDER = "@VERSION@"


class Report:
    def __init__(self, quiet: bool = False) -> None:
        self.quiet = quiet
        self.errors = 0

    def ok(self, message: str) -> None:
        if not self.quiet:
            print(f"ok: {message}")

    def skip(self, message: str) -> None:
        if not self.quiet:
            print(f"skip: {message}")

    def error(self, message: str) -> None:
        self.errors += 1
        print(f"error: {message}", file=sys.stderr)


def read_text(path: Path, report: Report) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        report.error(f"cannot read {path}: {exc}")
        return None


def check_version_file(root: Path, report: Report) -> str | None:
    path = root / "VERSION"
    text = read_text(path, report)
    if text is None:
        return None
    version = text.strip()
    if not version:
        report.error(f"{path} is empty")
        return None
    if "\n" in version:
        report.error(f"{path} must contain a single version, found {version!r}")
        return None
    if not SEMVER_RE.match(version):
        report.error(
            f"{path} contains {version!r}, which is not a semantic version "
            "(expected MAJOR.MINOR.PATCH)"
        )
    else:
        report.ok(f"VERSION = {version}")
    return version


def check_zig_zon(root: Path, version: str, report: Report) -> None:
    path = root / "runtime/build.zig.zon"
    text = read_text(path, report)
    if text is None:
        return
    match = ZON_VERSION_RE.search(text)
    if not match:
        report.error(f'{path} has no `.version = "..."` field')
        return
    found = match.group(1)
    if found != version:
        report.error(f"{path}: .version is {found!r}, VERSION is {version!r}")
    else:
        report.ok(f"{path}: .version = {found}")


def check_cargo_template(root: Path, version: str, report: Report) -> None:
    path = root / "packaging/rust/cinterp-sys/Cargo.toml.in"
    text = read_text(path, report)
    if text is None:
        return
    match = CARGO_VERSION_RE.search(text)
    if not match:
        report.error(f"{path} has no `version = ...` field")
        return
    found = match.group(1)
    if found == CARGO_PLACEHOLDER:
        report.ok(f"{path}: version uses {CARGO_PLACEHOLDER}")
    elif found != version:
        report.error(
            f"{path}: version is {found!r}, VERSION is {version!r} "
            f"(use {CARGO_PLACEHOLDER} to inherit VERSION)"
        )
    else:
        report.ok(f"{path}: version = {found}")


def resolve_tag(explicit: str | None) -> tuple[str | None, str]:
    """Return (tag, reason-it-was-skipped)."""
    if explicit is not None:
        tag = explicit.strip()
        if not tag:
            return None, "--tag was empty"
        return tag, ""
    env = os.environ
    ref = env.get("GITHUB_REF", "").strip()
    ref_type = env.get("GITHUB_REF_TYPE", "").strip()
    name = env.get("GITHUB_REF_NAME", "").strip()
    if not name:
        return None, "GITHUB_REF_NAME is not set and --tag was not given"
    if ref_type == "tag" or ref.startswith("refs/tags/"):
        return name, ""
    if TAG_RE.match(name):
        # A version-shaped GITHUB_REF_NAME without tag metadata: treat it as a
        # tag so local runs with GITHUB_REF_NAME exported still get checked.
        return name, ""
    return None, f"GITHUB_REF_NAME={name!r} is not a release tag (skipping tag check)"


def check_tag(tag: str | None, reason: str, version: str, report: Report) -> None:
    if tag is None:
        report.skip(reason)
        return
    match = TAG_RE.match(tag)
    if not match:
        report.error(
            f"release tag {tag!r} is not a version tag "
            f"(expected v{version} or {version})"
        )
        return
    if match.group("semver") != version:
        report.error(
            f"release tag {tag!r} does not match VERSION {version!r} "
            f"(expected v{version})"
        )
        return
    report.ok(f"release tag {tag} matches VERSION {version}")


def expand_sbom_paths(root: Path, values: list[str], report: Report) -> list[Path]:
    paths: list[Path] = []
    for value in values:
        candidate = Path(value)
        if not candidate.is_absolute():
            candidate = root / value
        matches = sorted(glob.glob(str(candidate)))
        if not matches:
            report.error(f"SBOM not found: {value}")
            continue
        for match in matches:
            paths.append(Path(match))
    return paths


def check_sbom(path: Path, version: str, report: Report) -> None:
    text = read_text(path, report)
    if text is None:
        return
    try:
        document = json.loads(text)
    except json.JSONDecodeError as exc:
        report.error(f"{path}: invalid JSON: {exc}")
        return
    if not isinstance(document, dict):
        report.error(f"{path}: SBOM root is not an object")
        return

    package = next(
        (
            entry
            for entry in document.get("packages", [])
            if entry.get("SPDXID") == "SPDXRef-Package-cinterp"
        ),
        None,
    )
    if package is None:
        report.error(
            f"{path}: no SPDXRef-Package-cinterp package (is this a cinterp SBOM?)"
        )
        return
    found = str(package.get("versionInfo", ""))
    if found != version:
        report.error(f"{path}: package versionInfo is {found!r}, VERSION is {version!r}")
        return
    name = str(document.get("name", ""))
    if name and not name.startswith("cinterp-"):
        report.error(f"{path}: document name {name!r} does not start with 'cinterp-'")
        return
    report.ok(f"{path}: package version = {found}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate cinterp version consistency."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help=f"repository root (default: {ROOT})",
    )
    parser.add_argument(
        "--tag",
        default=None,
        help="release tag to check (default: infer from GITHUB_REF_NAME)",
    )
    parser.add_argument(
        "--sbom",
        action="append",
        default=[],
        metavar="PATH",
        help="SPDX JSON SBOM to check; repeatable, '*' globs allowed",
    )
    parser.add_argument("--quiet", action="store_true", help="only print errors")
    args = parser.parse_args()

    root = args.root.resolve()
    report = Report(quiet=args.quiet)
    if not root.is_dir():
        report.error(f"--root is not a directory: {root}")
        return 1

    version = check_version_file(root, report)
    if version is None:
        print("check_version: cannot continue without a valid VERSION", file=sys.stderr)
        return 1

    check_zig_zon(root, version, report)
    check_cargo_template(root, version, report)

    tag, reason = resolve_tag(args.tag)
    check_tag(tag, reason, version, report)

    for sbom in expand_sbom_paths(root, args.sbom, report):
        check_sbom(sbom, version, report)

    if report.errors:
        print(
            f"check_version: {report.errors} version mismatch(es) for VERSION {version}",
            file=sys.stderr,
        )
        return 1
    if not args.quiet:
        print(f"check_version: all version sources agree on {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
