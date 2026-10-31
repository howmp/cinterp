from __future__ import annotations

import struct
from dataclasses import dataclass, field

PROVIDER_SYSTEM = 0
PROVIDER_SONAME = 1
PROVIDER_PATH = 2

IMPORT_FUNCTION = 0
IMPORT_DATA = 1

IMPORT_REQUIRED = 1 << 0
IMPORT_LAZY = 1 << 1
IMPORT_ALLOW_FALLBACK = 1 << 2
IMPORT_ALLOW_OVERRIDE = 1 << 3


@dataclass
class Provider:
    kind: int
    name: str
    symbol: str
    ordinal: int = 0
    version: str = ""


@dataclass
class ImportEntry:
    plan_index: int
    name: str
    providers: list[Provider]
    kind: int = IMPORT_FUNCTION
    flags: int = IMPORT_REQUIRED | IMPORT_LAZY | IMPORT_ALLOW_OVERRIDE
    callconv: int = 0
    arch_mask: int = 0
    min_os: int = 0


@dataclass
class ImportTable:
    entries: list[ImportEntry] = field(default_factory=list)

    def add(self, entry: ImportEntry) -> None:
        self.entries.append(entry)

    def serialize(self) -> bytes:
        out = bytearray(b"CIPI")
        out += bytes([1, 0])
        out += struct.pack("<HH", len(self.entries), 0)
        for entry in self.entries:
            name = entry.name.encode("utf-8")
            if len(name) > 255 or len(entry.providers) > 255:
                raise ValueError("import entry too large")
            out += struct.pack(
                "<HBBBBH",
                entry.plan_index,
                entry.kind,
                entry.flags,
                entry.callconv,
                entry.arch_mask,
                entry.min_os,
            )
            out += bytes([len(name)]) + name
            out += bytes([len(entry.providers)])
            for provider in entry.providers:
                pname = provider.name.encode("utf-8")
                psym = provider.symbol.encode("utf-8")
                pver = provider.version.encode("utf-8")
                if max(len(pname), len(psym), len(pver)) > 255:
                    raise ValueError("provider string too long")
                out += bytes([provider.kind, len(pname)]) + pname
                out += bytes([len(psym)]) + psym
                out += struct.pack("<H", provider.ordinal)
                out += bytes([len(pver)]) + pver
        return bytes(out)
