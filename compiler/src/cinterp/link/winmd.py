from __future__ import annotations

import gzip
import json
from dataclasses import replace
from pathlib import Path

from .imports import (
    IMPORT_ALLOW_OVERRIDE,
    IMPORT_LAZY,
    IMPORT_REQUIRED,
    ImportEntry,
    ImportTable,
    Provider,
)
from .target import Target

_ARCH_MASK = {"x86_64": 1, "x86": 2, "aarch64": 4}
_CALLCONV = {"cdecl": 0, "winapi": 1}
_DATA: dict | None = None
_PATH: Path | None = None


def _database_path() -> Path:
    if _PATH is not None:
        return _PATH
    return Path(__file__).with_name("winmd.generated.json.gz")


def set_database(path: str | Path) -> None:
    """Use a directory containing winmd.generated.json.gz, or the gz file itself."""
    global _DATA, _PATH
    p = Path(path)
    if p.is_dir():
        p = p / "winmd.generated.json.gz"
    _PATH = p if p.is_file() else None
    _DATA = None


def _load() -> dict:
    global _DATA
    if _DATA is None:
        with gzip.open(_database_path(), "rt") as fh:
            _DATA = json.load(fh)
    return _DATA


def database_id() -> str:
    data = _load()
    return f"winmd@{data.get('upstream_commit', 'unknown')}"


def _names(name: str) -> list[str]:
    if name.startswith("callback:") or name.startswith("llvm."):
        return []
    base = name.split("@", 1)[0]
    out = [base]
    if base.startswith("_"):
        out.append(base[1:])
    return out


def lookup(target: Target, name: str) -> tuple[list[Provider], int, int] | None:
    if target.os != "windows":
        return None
    data = _load()
    sym = ""
    entries = None
    for candidate in _names(name):
        entries = data.get("apis", {}).get(candidate)
        if entries:
            sym = candidate
            break
    if not entries:
        return None
    mask = _ARCH_MASK.get(target.arch, 0)
    matched = [entry for entry in entries if int(entry.get("arch_mask", 7)) & mask]
    if not matched:
        raise ValueError(f"Windows API {sym!r} is not available on {target.name}")
    providers: list[Provider] = []
    conv = 0
    min_os = 0
    for entry in matched:
        dll = str(entry["dll"])
        provider = Provider(kind=1, name=dll, symbol=sym)
        if provider not in providers:
            providers.append(provider)
        conv = _CALLCONV.get(str(entry.get("callconv", "winapi")), 1)
        min_os = max(min_os, int(entry.get("min_os", 0)))
    return providers[:8], conv, min_os


def apply(target: Target, plans, imports: ImportTable, enabled: bool = True) -> Target:
    if not enabled or target.os != "windows" or not plans.plans:
        return target
    db_id = database_id()
    if db_id not in target.link_db:
        target = replace(target, link_db=(target.link_db + ";" + db_id).strip(";"))
    existing = {entry.plan_index for entry in imports.entries}
    for index, plan in enumerate(plans.plans):
        if index in existing:
            continue
        result = lookup(target, plan.name)
        if result is None:
            continue
        providers, conv, min_os = result
        imports.add(
            ImportEntry(
                plan_index=index,
                name=plan.name,
                providers=providers,
                flags=IMPORT_REQUIRED | IMPORT_LAZY | IMPORT_ALLOW_OVERRIDE,
                callconv=conv,
                arch_mask=_ARCH_MASK.get(target.arch, 0),
                min_os=min_os,
            )
        )
    return target
