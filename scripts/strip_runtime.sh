#!/usr/bin/env bash
set -euo pipefail

BIN="${1:-}"
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
    echo "usage: $0 <runtime-executable>" >&2
    exit 2
fi

if command -v llvm-objcopy >/dev/null 2>&1; then
    OC=llvm-objcopy
elif command -v objcopy >/dev/null 2>&1; then
    OC=objcopy
else
    echo "strip_runtime: objcopy/llvm-objcopy not found" >&2
    exit 2
fi

type="$(file -b "$BIN")"
case "$type" in
    *ELF*)
        "$OC" --remove-section=.eh_frame --remove-section=.eh_frame_hdr "$BIN"
        ;;
    *PE32*)
        # MinGW/compiler_rt emits .eh_frame unwind data for i686 PE even in
        # ReleaseSmall. The runtime does not use SEH; strip it post-link.
        "$OC" --remove-section=.eh_fram "$BIN"
        ;;
    *)
        echo "strip_runtime: unsupported artifact type: $type" >&2
        exit 2
        ;;
esac

echo "stripped runtime: $(stat -c '%s' "$BIN") bytes"
