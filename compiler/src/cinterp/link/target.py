from __future__ import annotations

import struct
from dataclasses import dataclass, field

from cinterp import __version__

ARCH_IDS = {"x86_64": 1, "x86": 2, "aarch64": 3}
OS_IDS = {"linux": 1, "windows": 2}
ABI_IDS = {"sysv": 1, "win64": 2, "win32": 3, "aapcs64": 4}

FEATURE_F80 = 1 << 0
FEATURE_F128 = 1 << 1
FEATURE_CALLBACK = 1 << 2
FEATURE_VARARGS = 1 << 3
FEATURE_AUTO_LINK = 1 << 4
FEATURE_STDCALL = 1 << 5


@dataclass
class Target:
    name: str
    triple: str
    arch: str
    os: str
    abi: str
    ptr_bits: int
    endian: int = 1
    features: int = FEATURE_CALLBACK | FEATURE_VARARGS | FEATURE_AUTO_LINK | FEATURE_STDCALL
    min_runtime: int = 1
    link_db: str = ""
    producer: str = f"cinterp {__version__}"
    flags: int = 0

    def with_arch_features(self) -> "Target":
        if self.arch in ("x86_64", "x86"):
            self.features |= FEATURE_F80
        if self.arch == "aarch64":
            self.features |= FEATURE_F128
        return self

    def serialize(self) -> bytes:
        triple = self.triple.encode()
        link_db = self.link_db.encode()
        producer = self.producer.encode()
        head = (
            b"CIPM"
            + bytes([1])
            + struct.pack("<H", 29)
            + bytes([
                ARCH_IDS[self.arch],
                OS_IDS[self.os],
                ABI_IDS[self.abi],
                self.ptr_bits,
                self.endian,
                self.flags,
            ])
            + struct.pack("<QH", self.features, self.min_runtime)
            + struct.pack("<HHH", len(triple), len(link_db), len(producer))
        )
        return head + triple + link_db + producer


TARGETS = {
    "x86_64-linux": Target("x86_64-linux", "x86_64-pc-linux-gnu", "x86_64", "linux", "sysv", 64).with_arch_features(),
    "x86_64-windows": Target("x86_64-windows", "x86_64-pc-windows-gnu", "x86_64", "windows", "win64", 64).with_arch_features(),
    "i686-windows": Target("i686-windows", "i686-pc-windows-gnu", "x86", "windows", "win32", 32).with_arch_features(),
    "aarch64-linux": Target("aarch64-linux", "aarch64-linux-gnu", "aarch64", "linux", "aapcs64", 64).with_arch_features(),
}
DEFAULT_TARGET = TARGETS["x86_64-linux"]


def target_for(abi: str, ptr_size: int) -> Target:
    for target in TARGETS.values():
        if target.abi == abi and target.ptr_bits == ptr_size * 8:
            return target
    return DEFAULT_TARGET
