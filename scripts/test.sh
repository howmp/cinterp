#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PYTHONPATH="$ROOT/compiler/src"
RUNTIME="$ROOT/runtime/zig-out/bin/cinterp-run"
OUT="$ROOT/build"
mkdir -p "$OUT"

echo "== runtime unit tests"
(cd runtime && zig build test --summary all)

echo "== compiler unit tests"
python3 -m unittest discover -s compiler/tests

echo "== build runtime"
(cd runtime && zig build -Doptimize=ReleaseSmall)

run_case() {
    local name="$1"
    local expected="$2"
    local cib="$OUT/$name.cib"
    python3 -m cinterp compile "examples/$name.c" -o "$cib" >/dev/null
    local out
    out="$("$RUNTIME" "$cib" 2>&1)"
    if ! printf '%s\n' "$out" | grep -Fq "result: $expected"; then
        echo "FAIL $name: expected result $expected" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    echo "OK $name -> $expected"
}

run_case hello 42
run_case ffi_malloc 42
run_case arrays 10
run_case structs 34
run_case ffi_snprintf 55

echo "== native calls"
python3 -m cinterp compile examples/ffi_puts.c -o "$OUT/ffi_puts.cib" >/dev/null
puts_out="$("$RUNTIME" "$OUT/ffi_puts.cib" 2>&1)"
printf '%s\n' "$puts_out" | grep -Fq "hello from cinterp"
printf '%s\n' "$puts_out" | grep -Fq "result: 0"
echo "OK ffi_puts"

python3 -m cinterp compile examples/ffi_printf.c -o "$OUT/ffi_printf.cib" >/dev/null
printf_out="$("$RUNTIME" "$OUT/ffi_printf.cib" 2>&1)"
printf '%s\n' "$printf_out" | grep -Fq "7 2.5"
printf '%s\n' "$printf_out" | grep -Fq "result: 0"
echo "OK ffi_printf"

echo "== struct FFI (byval + sret)"
cc -shared -fPIC -O0 examples/ffi_structs_helper.c -o "$OUT/libstruct_helpers.so"
python3 -m cinterp compile examples/ffi_structs.c -o "$OUT/ffi_structs.cib" >/dev/null
struct_out="$("$RUNTIME" --lib "$OUT/libstruct_helpers.so" "$OUT/ffi_structs.cib" 2>&1)"
printf '%s\n' "$struct_out" | grep -Fq "result: 28"
echo "OK ffi_structs -> 28"

echo "== register-class struct FFI (S8 + D16)"
cc -shared -fPIC -O0 examples/ffi_regstruct_helper.c -o "$OUT/libregstruct_helpers.so"
python3 -m cinterp compile examples/ffi_regstruct.c -o "$OUT/ffi_regstruct.cib" >/dev/null
reg_out="$("$RUNTIME" --lib "$OUT/libregstruct_helpers.so" "$OUT/ffi_regstruct.cib" 2>&1)"
printf '%s\n' "$reg_out" | grep -Fq "result: 102"
echo "OK ffi_regstruct -> 102"

echo "all tests passed"
