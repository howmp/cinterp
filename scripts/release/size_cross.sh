#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT/runtime"
OUT="$ROOT/build/size"
BUDGET="${SIZE_BUDGET:-135168}"
mkdir -p "$OUT"
check() {
    local target="$1" name="$2"
    zig build -Dtarget="$target" -Doptimize=ReleaseSmall >/dev/null
    case "$target" in
        *windows*) cp zig-out/bin/cinterp-run.exe "$OUT/$name" ;;
        *) cp zig-out/bin/cinterp-run "$OUT/$name" ;;
    esac
    "$ROOT/scripts/release/strip_runtime.sh" "$OUT/$name" >/dev/null
    local size
    size=$(stat -c%s "$OUT/$name")
    echo "$name: $size bytes"
    if [ "$size" -ge "$BUDGET" ]; then
        echo "size budget exceeded for $name ($size >= $BUDGET)" >&2
        exit 1
    fi
}
check x86_64-linux cinterp-run-sysv
check x86_64-windows-gnu cinterp-run-win64.exe
check x86-windows-gnu cinterp-run-win32.exe
check aarch64-linux-gnu cinterp-run-arm64

# Restore the native runtime: later CI/local steps execute runtime/zig-out directly.
zig build -Doptimize=ReleaseSmall >/dev/null
