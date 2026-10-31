#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/runtime/zig-out/bin/cinterp-run"
if ! file "$BIN" | grep -q 'ELF'; then
    echo "strip_elf: not an ELF artifact: $BIN" >&2
    exit 2
fi
if command -v objcopy >/dev/null 2>&1; then
    objcopy --remove-section=.eh_frame --remove-section=.eh_frame_hdr "$BIN"
elif command -v llvm-objcopy >/dev/null 2>&1; then
    llvm-objcopy --remove-section=.eh_frame --remove-section=.eh_frame_hdr "$BIN"
else
    echo "strip_elf: objcopy/llvm-objcopy not found" >&2
    exit 2
fi
echo "release runtime: $(stat -c '%s' "$BIN") bytes"
