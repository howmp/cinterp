from __future__ import annotations

import re
from dataclasses import dataclass

from .imports import (
    IMPORT_ALLOW_FALLBACK,
    IMPORT_ALLOW_OVERRIDE,
    IMPORT_DATA,
    ImportEntry,
    ImportTable,
    Provider,
)
from .target import Target

# C runtime data symbols that are stable ABI exports on the supported hosts.
# Other external globals are still emitted as data imports, but with no fixed
# provider so --lib/process fallback can resolve harness globals.
KNOWN_DATA = {
    "stdin",
    "stdout",
    "stderr",
    "environ",
    "optarg",
    "optind",
    "opterr",
    "optopt",
    "tzname",
    "timezone",
    "daylight",
    "program_invocation_name",
    "program_invocation_short_name",
    "__environ",
    "_environ",
    "__progname",
    "__progname_full",
    "_pgmptr",
    "_wpgmptr",
    "__argc",
    "__argv",
    "__wargv",
    "_wenviron",
    "_tzname",
    "_timezone",
    "_daylight",
    "_optarg",
    "_optind",
    "_opterr",
    "_optopt",
}


def _providers(target: Target, name: str) -> list[Provider]:
    if target.os == "linux":
        return [Provider(kind=1, name="libc.so.6", symbol=name)]
    if target.os == "windows":
        return [
            Provider(kind=1, name="ucrtbase.dll", symbol=name),
            Provider(kind=1, name="msvcrt.dll", symbol=name),
            Provider(kind=1, name="ntdll.dll", symbol=name),
        ]
    return []


def collect_names(text: str, globals_map: dict[str, int], func_indices: dict[str, int], decls: dict) -> list[str]:
    names: set[str] = set()
    for line in text.splitlines():
        if line.lstrip().startswith(("declare ", "define ")):
            continue
        matches = list(re.finditer(r"@[\w.$-]+", line))
        is_call_line = re.search(r"\b(?:call|invoke)\b", line) is not None
        for m in matches:
            name = m.group(0)[1:]
            if name.startswith("llvm.") or name.startswith("__const"):
                continue
            if name.startswith("."):
                continue
            if name in globals_map or name in func_indices:
                continue
            after = line[m.end() :].lstrip()
            # A call target is handled by a CIPL CallPlan; only other
            # occurrences are function-pointer/data values.
            if is_call_line and after.startswith("("):
                continue
            if len(name) <= 64:
                names.add(name)
    return sorted(names)


@dataclass
class ExternalData:
    index: dict[str, int]
    table: ImportTable


def build(target: Target, names: list[str], imports: ImportTable, decls: dict | None = None) -> ExternalData:
    index: dict[str, int] = {}
    base = len(imports.entries)
    for offset, name in enumerate(names):
        entry = ImportEntry(
            plan_index=0xFFFF,
            name=name,
            kind=IMPORT_DATA,
            flags=IMPORT_ALLOW_FALLBACK | IMPORT_ALLOW_OVERRIDE,
            providers=_providers(target, name) if (name in KNOWN_DATA or (decls is not None and name in decls)) else [],
            arch_mask={"x86_64": 1, "x86": 2, "aarch64": 4}.get(target.arch, 0),
        )
        imports.add(entry)
        index[name] = base + offset
    return ExternalData(index=index, table=imports)
