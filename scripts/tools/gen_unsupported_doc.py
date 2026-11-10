#!/usr/bin/env python3
"""Generate docs/unsupported-cases.md from a suite report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REPORT = ROOT / "build/test-suites-full.json"
DEFAULT_OUTPUT = ROOT / "docs/unsupported-cases.md"

SUITE_ORDER = [
    "c-testsuite",
    "chibicc",
    "compcert",
    "compcert-c",
    "compcert-compile",
    "gcc-ieee",
    "gcc-torture",
    "gcc-torture-compile",
    "libc-test",
    "libc-test-regression",
    "llvm-regression-c",
    "llvm-singlesource",
    "tcc-tests2",
]


def normalize_reason(reason: str) -> str:
    return reason.replace("\n", " ").strip().replace(
        str(ROOT / "build/suites") + "/", "build/suites/"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    report = json.loads(args.report.read_text())
    rows = [
        row
        for row in report.get("results", [])
        if row.get("status") == "skip"
        and row.get("skip_class") == "unsupported"
    ]
    by_suite: dict[str, list[dict]] = {name: [] for name in SUITE_ORDER}
    for row in rows:
        by_suite.setdefault(row["suite"], []).append(row)

    lines = [
        "# Unsupported 用例",
        "",
        f"本文件由 `scripts/tools/gen_unsupported_doc.py` 从 "
        f"`{args.report.relative_to(ROOT)}` 生成，列出当前 **{len(rows)}** 个 "
        "`unsupported` skip。",
        "",
        "说明：`reason` 保留 suite runner 记录的 skip 原因；编译诊断在 report "
        "中可能只保留首行。绝对路径的 "
        "`build/suites/` 前缀会被规范化为相对路径。",
        "",
    ]
    for suite in SUITE_ORDER:
        suite_rows = by_suite.get(suite, [])
        if not suite_rows:
            continue
        lines.extend([f"## {suite} ({len(suite_rows)})", ""])
        for row in sorted(suite_rows, key=lambda item: item["id"]):
            reason = normalize_reason(str(row.get("reason", "")))
            lines.append(f"- `{row['id']}` — {reason}")
        lines.append("")

    args.output.write_text("\n".join(lines) + "\n")
    print(f"{args.output}: {len(rows)} unsupported cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
