#!/usr/bin/env python3
"""为 cinterp keygenme 示例生成合法序列号。

用法:
    keygen.py alice
    keygen.py alice --salt 0xabcde
    keygen.py alice --count 3
"""
from __future__ import annotations

import argparse

MASK32 = 0xFFFFFFFF
MASK64 = 0xFFFFFFFFFFFFFFFF
MASK60 = (1 << 60) - 1
MASK30 = (1 << 30) - 1
ROUNDS = 24
ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
MAX_SALT = (1 << 20) - 1


def mix32(x: int) -> int:
    x &= MASK32
    x ^= x >> 16
    x = (x * 0x7FEB352D) & MASK32
    x ^= x >> 15
    x = (x * 0x846CA68B) & MASK32
    x ^= x >> 16
    return x & MASK32


def mix64(x: int) -> int:
    x &= MASK64
    x ^= x >> 30
    x = (x * 0xBF58476D1CE4E5B9) & MASK64
    x ^= x >> 27
    x = (x * 0x94D049BB133111EB) & MASK64
    x ^= x >> 31
    return x & MASK64


def hash_a(name: str) -> int:
    data = name.encode()
    h = 0x811C9DC5
    for byte in data:
        h = ((h ^ byte) * 16777619) & MASK32
    return mix32(h ^ ((len(data) * 0x9E3779B9) & MASK32))


def hash_b(name: str) -> int:
    data = name.encode()
    h = 0x9E3779B9
    for index, byte in enumerate(data):
        h = (h + byte + 0x85EBCA6B) & MASK32
        h = ((h << 7) | (h >> 25)) & MASK32
        h ^= mix32((index + 0xC2B2AE35) & MASK32)
    return mix32(h ^ len(data))


def name_tag(name: str) -> int:
    length = len(name.encode())
    value = ((hash_a(name) << 32) | hash_b(name))
    value ^= (0x9E3779B97F4A7C15 * (length + 1)) & MASK64
    value = mix64(value)
    return mix64(value ^ 0x452821E638D01377) & MASK60


def schedule(tag: int, salt: int) -> list[int]:
    value = (tag & MASK32) ^ ((tag >> 30) & MASK32) ^ ((salt * 0x85EBCA6B) & MASK32)
    round_keys = []
    for index in range(ROUNDS):
        value = mix32((value + index * 0x9E3779B9 + 0x7F4A7C15) & MASK32)
        round_keys.append(value & MASK30)
    return round_keys


def round_f(right: int, round_key: int) -> int:
    value = mix32(right ^ round_key)
    value = mix32(value + ((right * 0x85EBCA6B) & MASK32) + 0x9E3779B9)
    return value & MASK30


def permute(state: int, round_keys: list[int]) -> int:
    left = (state >> 30) & MASK30
    right = state & MASK30
    for round_key in round_keys:
        left, right = right, (left ^ round_f(right, round_key)) & MASK30
    return (left << 30) | right


def invert(tag: int, round_keys: list[int]) -> int:
    left = (tag >> 30) & MASK30
    right = tag & MASK30
    for round_key in reversed(round_keys):
        left, right = (right ^ round_f(left, round_key)) & MASK30, left
    return (left << 30) | right


def encode_group(value: int) -> str:
    return "".join(ALPHABET[(value >> shift) & 31] for shift in (15, 10, 5, 0))


def serial_for(name: str, salt: int = 0) -> str:
    if not 0 <= salt <= MAX_SALT:
        raise ValueError(f"salt must be in 0..0x{MAX_SALT:x}")

    tag = name_tag(name)
    round_keys = schedule(tag, salt)
    state = invert(tag, round_keys)
    if permute(state, round_keys) != tag:
        raise RuntimeError("internal Feistel inversion mismatch")

    groups = (
        (state >> 40) & 0xFFFFF,
        (state >> 20) & 0xFFFFF,
        state & 0xFFFFF,
        salt,
    )
    return "-".join(encode_group(group) for group in groups)


def parse_salt(text: str) -> int:
    try:
        value = int(text, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("salt must be an integer, e.g. 0xabcde") from exc
    if not 0 <= value <= MAX_SALT:
        raise argparse.ArgumentTypeError(f"salt must be in 0..0x{MAX_SALT:x}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", help="user name")
    parser.add_argument("--salt", type=parse_salt, default=0,
                        help="20-bit salt (default: 0)")
    parser.add_argument("--count", type=int, default=1,
                        help="number of serials to emit with consecutive salts")
    args = parser.parse_args()

    if not 1 <= args.count <= (1 << 20):
        parser.error("--count must be in 1..1048576")

    for index in range(args.count):
        salt = (args.salt + index) & MAX_SALT
        print(serial_for(args.name, salt))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
