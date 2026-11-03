#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build/differential"
mkdir -p "$OUT"
CASES=(hello arrays structs math bitfields ptrstruct longdouble)
ZIG_CC="${CINTERP_ZIG_CC:-$ROOT/build/cinterp-cc}"
fail=0
for name in "${CASES[@]}"; do
    clang -O0 "examples/$name.c" -o "$OUT/$name.native"
    set +e
    "$OUT/$name.native"
    native_rc=$?
    set -e
    "$ZIG_CC" compile "examples/$name.c" -o "$OUT/$name.zig.cib" >/dev/null
    zig_out="$("$ROOT/runtime/zig-out/bin/cinterp-run" "$OUT/$name.zig.cib" 2>&1)"
    zig_rc="$(printf '%s\n' "$zig_out" | sed -n 's/^result: //p' | tail -n1)"
    if [[ "$native_rc" != "$zig_rc" ]]; then
        echo "FAIL $name native=$native_rc zig=${zig_rc:-none}" >&2
        printf '%s\n' "$zig_out" | tail -n3 >&2
        fail=1
    else
        echo "OK $name -> $native_rc (native/zig agree)"
    fi
done
exit "$fail"
