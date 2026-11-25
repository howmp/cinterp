#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/runtime/zig-out/bin/cinterp-run"
if ! file "$BIN" | grep -q 'ELF'; then
    echo "strip_elf: not an ELF artifact: $BIN" >&2
    exit 2
fi
if command -v objcopy >/dev/null 2>&1; then
    objcopy --remove-section=.eh_frame --remove-section=.eh_frame_hdr \
        --remove-section=.comment --remove-section=.note.ABI-tag \
        --remove-section=.hash "$BIN" 2>/dev/null || true
elif command -v llvm-objcopy >/dev/null 2>&1; then
    llvm-objcopy --remove-section=.eh_frame --remove-section=.eh_frame_hdr \
        --remove-section=.comment --remove-section=.note.ABI-tag \
        --remove-section=.hash "$BIN" 2>/dev/null || true
else
    echo "strip_elf: objcopy/llvm-objcopy not found" >&2
    exit 2
fi
# The ELF loader uses program headers; the section header table is not needed
# by a stripped release runtime. Removing it saves ~1.6 KiB per ELF target.
if command -v strip >/dev/null 2>&1; then
    strip --strip-section-headers "$BIN" 2>/dev/null || true
elif command -v llvm-strip >/dev/null 2>&1; then
    llvm-strip --strip-sections "$BIN" 2>/dev/null || true
fi
echo "release runtime: $(stat -c '%s' "$BIN") bytes"
