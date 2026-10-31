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

echo "== bitfields"
python3 -m cinterp compile examples/bitfields.c -o "$OUT/bitfields.cib" >/dev/null
bits_out="$("$RUNTIME" "$OUT/bitfields.cib" 2>&1)"
printf '%s\n' "$bits_out" | grep -Fq "result: 12"
echo "OK bitfields -> 12"

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

echo "== mixed-class aggregate FFI (i64 + double)"
cc -shared -fPIC -O0 examples/ffi_mixedstruct_helper.c -o "$OUT/libmixedstruct_helpers.so"
python3 -m cinterp compile examples/ffi_mixedstruct.c -o "$OUT/ffi_mixedstruct.cib" >/dev/null
mixed_out="$("$RUNTIME" --lib "$OUT/libmixedstruct_helpers.so" "$OUT/ffi_mixedstruct.cib" 2>&1)"
printf '%s\n' "$mixed_out" | grep -Fq "result: 11"
echo "OK ffi_mixedstruct -> 11"

echo "== double arithmetic"
python3 -m cinterp compile examples/math.c -o "$OUT/math.cib" >/dev/null
math_out="$("$RUNTIME" "$OUT/math.cib" 2>&1)"
printf '%s\n' "$math_out" | grep -Fq "result: 8"
echo "OK math -> 8"

echo "== float32 arithmetic"
python3 -m cinterp compile examples/float_math.c -o "$OUT/float_math.cib" >/dev/null
float_out="$("$RUNTIME" "$OUT/float_math.cib" 2>&1)"
printf '%s\n' "$float_out" | grep -Fq "result: 8"
echo "OK float_math -> 8"

echo "== float32 FFI"
cc -shared -fPIC -O0 examples/ffi_float_helper.c -o "$OUT/libfloat_helpers.so"
python3 -m cinterp compile examples/ffi_float.c -o "$OUT/ffi_float.cib" >/dev/null
ffloat_out="$("$RUNTIME" --lib "$OUT/libfloat_helpers.so" "$OUT/ffi_float.cib" 2>&1)"
printf '%s\n' "$ffloat_out" | grep -Fq "result: 5"
echo "OK ffi_float -> 5"

echo "== callback (qsort)"
python3 -m cinterp compile examples/ffi_qsort.c -o "$OUT/ffi_qsort.cib" >/dev/null
qsort_out="$("$RUNTIME" "$OUT/ffi_qsort.cib" 2>&1)"
printf '%s\n' "$qsort_out" | grep -Fq "result: 1"
echo "OK ffi_qsort -> 1"

echo "all tests passed"
