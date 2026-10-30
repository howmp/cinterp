"""Binary package writer: CIVM bytecode module + CIPL FFI plan table."""
from __future__ import annotations

import struct

PACKAGE_MAGIC = b"CIPKG"
PACKAGE_VERSION = 1


def write_package(module: bytes, plans: bytes) -> bytes:
    return (
        PACKAGE_MAGIC
        + bytes([PACKAGE_VERSION, 0])
        + struct.pack("<II", len(module), len(plans))
        + module
        + plans
    )
