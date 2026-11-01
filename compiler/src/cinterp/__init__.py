from __future__ import annotations

import os
from pathlib import Path


def _read_version() -> str:
    override = os.environ.get("CINTERP_VERSION")
    if override:
        return override.strip()
    for parent in Path(__file__).resolve().parents:
        candidate = parent / "VERSION"
        if candidate.is_file():
            return candidate.read_text(encoding="utf-8").strip()
    try:
        from importlib.metadata import PackageNotFoundError, version

        return version("cinterp")
    except (ImportError, PackageNotFoundError):
        return "0.0.0+unknown"


__version__ = _read_version()
