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


def lookup(target: Target, name: str) -> list[Provider] | None:
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
