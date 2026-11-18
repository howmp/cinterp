#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CC="${CINTERP_CC:-$ROOT/build/cinterp-cc}"
PYTHON="${PYTHON:-python3}"
SRC="$ROOT/examples/keygenme/keygenme.c"
OUT="$ROOT/build/keygenme"

if [[ ! -x "$CC" ]]; then
    echo "error: missing $CC; run 'make compiler' first" >&2
    exit 1
fi

mkdir -p "$OUT/cib"

build() {
    local name="$1" c_target="$2" zig_target="$3" ext="$4"
    local cib="$OUT/cib/keygenme-$name.cib"
    echo "building $name"
    "$CC" compile "$SRC" --target "$c_target" -o "$cib"
    (
        cd "$ROOT"
        "$PYTHON" scripts/tools/cib_dump.py "build/keygenme/cib/keygenme-$name.cib" \
            > "$OUT/keygenme-$name.dump.txt"
    )
    test -s "$OUT/keygenme-$name.dump.txt"
    (
        cd "$ROOT/examples/keygenme"
        zig build -Doptimize=ReleaseSmall -Dtarget="$zig_target" \
            -Dcib="../../build/keygenme/cib/keygenme-$name.cib" \
            --prefix "$OUT/$name"
    )
    cp "$OUT/$name/bin/keygenme$ext" "$OUT/keygenme-$name$ext"
    rm -rf "$OUT/$name"
}

build linux-x86_64 x86_64-linux x86_64-linux-gnu ""
build linux-aarch64 aarch64-linux aarch64-linux-gnu ""
build windows-x86_64 x86_64-windows x86_64-windows-gnu .exe
build windows-x86 i686-windows x86-windows-gnu .exe

ls -l "$OUT"/keygenme-*
