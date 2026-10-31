"""Binary package writer: CIVM bytecode module + CIPL FFI plan table."""
from __future__ import annotations

import struct

PACKAGE_MAGIC = b"CIPKG"
PACKAGE_VERSION = 1
PACKAGE_VERSION_V2 = 2


def write_package(module: bytes, plans: bytes) -> bytes:
    return (
        PACKAGE_MAGIC
        + bytes([PACKAGE_VERSION, 0])
        + struct.pack("<II", len(module), len(plans))
        + module
        + plans
    )


def write_package_v2(module: bytes, plans: bytes, meta: bytes, imports: bytes) -> bytes:
    flags = 0x1 | (0x2 if imports else 0)
    return (
        PACKAGE_MAGIC
        + bytes([PACKAGE_VERSION_V2, flags])
        + struct.pack("<HIIII", 25, len(module), len(plans), len(meta), len(imports))
        + module
        + plans
        + meta
        + imports
    )
