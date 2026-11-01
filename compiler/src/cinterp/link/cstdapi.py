from __future__ import annotations

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
_DATA: dict | None = None
_PATH: Path | None = None
_WRAPPERS: dict | None = None


def _database_path() -> Path:
    if _PATH is not None:
        return _PATH
    return Path(__file__).with_name("cstdapi.generated.json")


def set_database(path: str | Path) -> None:
    """Use a directory containing cstdapi.generated.json, or the JSON file itself."""
    global _DATA, _PATH
    p = Path(path)
    if p.is_dir():
        p = p / "cstdapi.generated.json"
    _PATH = p if p.is_file() else None
    _DATA = None


def _load() -> dict:
    global _DATA
    if _DATA is None:
        _DATA = json.loads(_database_path().read_text())
    return _DATA


def _wrappers_path() -> Path:
    return Path(__file__).with_name("link_wrappers.json")


def _load_wrappers() -> dict:
    global _WRAPPERS
    if _WRAPPERS is None:
        _WRAPPERS = json.loads(_wrappers_path().read_text())
    return _WRAPPERS


def _abi_os(abi: str) -> str:
    return "windows" if abi in ("win64", "win32") else "linux"


def wrapper(abi: str, name: str) -> tuple[str, list[str], list[str]] | None:
    """Return a target link-ABI wrapper for an external symbol.

    Some C-library entry points are supplied by a static nonshared archive
    (for example glibc's atexit -> __cxa_atexit wrapper), so neither LLVM IR
    nor the public header contains the real call shape.  Keeping this in link
    metadata lets lowering emit the real symbol and arguments once.
    """
    entry = _load_wrappers().get("targets", {}).get(_abi_os(abi), {}).get(name)
    if not entry:
        return None
    extra = entry.get("extra_args", [])
    return str(entry["symbol"]), [str(a["type"]) for a in extra], [str(a["const"]) for a in extra]


def database_id() -> str:
    data = _load()
    return f"cstdapi@{data.get('upstream_commit', 'unknown')}"


def _symbol_name(name: str) -> str:
    if name.startswith("callback:"):
        return ""
    if name.startswith("llvm."):
        return ""
    base = name.split("@", 1)[0]
    return base


_WINDOWS_UCRT_HELPERS = {
    "_errno",
    "__acrt_iob_func",
    "__p__environ",
    "__p__wenviron",
}


def lookup(target: Target, name: str) -> list[Provider] | None:
    for entry in _load_wrappers().get("targets", {}).get(target.os, {}).values():
        if entry.get("symbol") == name:
            return [
                Provider(kind=int(p.get("kind", 1)), name=str(p["lib"]), symbol=str(p["symbol"]))
                for p in entry.get("providers", [])
            ] or None
    if target.os == "windows" and name in _WINDOWS_UCRT_HELPERS:
        return [Provider(kind=1, name="ucrtbase.dll", symbol=name)]
    data = _load()
    target_data = data.get("targets", {}).get(target.name)
    if not target_data:
        return None
    sym = _symbol_name(name)
    entry = target_data.get("symbols", {}).get(sym)
    if entry is None and sym.startswith("_"):
        entry = target_data.get("symbols", {}).get(sym[1:])
    if entry is None:
        return None
    if not entry.get("available", False):
        raise ValueError(f"C standard library symbol {sym!r} is unavailable on {target.name}")
    providers: list[Provider] = []
    for item in entry.get("providers", []):
        providers.append(
            Provider(
                kind=int(item.get("kind", 1)),
                name=str(item["lib"]),
                symbol=str(item["symbol"]),
            )
        )
    return providers or None


def apply(target: Target, plans, imports: ImportTable, enabled: bool = True) -> Target:
    if not enabled:
        return target
    target = replace(target, link_db=database_id())
    mask = _ARCH_MASK.get(target.arch, 0)
    added = False
    for index, plan in enumerate(plans.plans):
        try:
            providers = lookup(target, plan.name)
        except ValueError:
            raise
        if not providers:
            continue
        imports.add(
            ImportEntry(
                plan_index=index,
                name=plan.name,
                providers=providers,
                flags=IMPORT_REQUIRED | IMPORT_LAZY | IMPORT_ALLOW_OVERRIDE,
                arch_mask=mask,
            )
        )
        added = True
    _ = added
    return target
