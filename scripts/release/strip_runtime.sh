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
        "$OC" --remove-section=.eh_frame --remove-section=.eh_frame_hdr \
            --remove-section=.comment --remove-section=.note.ABI-tag \
            --remove-section=.hash "$BIN" 2>/dev/null || true
        # The ELF loader uses program headers; a stripped release runtime does
        # not need the section header table.
        strip_tool=""
        case "$type" in
            *aarch64*) strip_tool="$(command -v aarch64-linux-gnu-strip || command -v llvm-strip || true)" ;;
            *) strip_tool="$(command -v strip || command -v llvm-strip || true)" ;;
        esac
        if [ -n "$strip_tool" ]; then
            if [ "$(basename "$strip_tool")" = "llvm-strip" ]; then
                "$strip_tool" --strip-sections "$BIN" 2>/dev/null || true
            else
                "$strip_tool" --strip-section-headers "$BIN" 2>/dev/null || true
            fi
        fi
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
