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
run_case longdouble 8

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

echo "== ABI edges / HFA / packed"
cc -shared -fPIC -O0 examples/ffi_edges_helper.c -o "$OUT/libffi_edges_helper.so"
python3 -m cinterp compile examples/ffi_edges.c -o "$OUT/ffi_edges.cib" >/dev/null
edge_out="$("$RUNTIME" --lib "$OUT/libffi_edges_helper.so" "$OUT/ffi_edges.cib" 2>&1)"
printf '%s\n' "$edge_out" | grep -Fq "result: 55"
echo "OK ffi_edges -> 55"
cc -shared -fPIC -O0 examples/ffi_hfa_helper.c -o "$OUT/libffi_hfa_helper.so"
python3 -m cinterp compile examples/ffi_hfa.c -o "$OUT/ffi_hfa.cib" >/dev/null
hfa_out="$("$RUNTIME" --lib "$OUT/libffi_hfa_helper.so" "$OUT/ffi_hfa.cib" 2>&1)"
printf '%s\n' "$hfa_out" | grep -Fq "result: 120"
echo "OK ffi_hfa -> 120"
cc -shared -fPIC -O0 examples/ffi_hfa_stack_helper.c -o "$OUT/libffi_hfa_stack_helper.so"
python3 -m cinterp compile examples/ffi_hfa_stack.c -o "$OUT/ffi_hfa_stack.cib" >/dev/null
hfas_out="$("$RUNTIME" --lib "$OUT/libffi_hfa_stack_helper.so" "$OUT/ffi_hfa_stack.cib" 2>&1)"
printf '%s\n' "$hfas_out" | grep -Fq "result: 45"
echo "OK ffi_hfa_stack -> 45"
cc -shared -fPIC -O0 examples/packed_helper.c -o "$OUT/libpacked_helper.so"
python3 -m cinterp compile examples/packed.c -o "$OUT/packed.cib" >/dev/null
packed_out="$("$RUNTIME" --lib "$OUT/libpacked_helper.so" "$OUT/packed.cib" 2>&1)"
printf '%s\n' "$packed_out" | grep -Fq "result: 7"
echo "OK packed -> 7"

echo "== long double FFI"
cc -shared -fPIC -O0 examples/ffi_longdouble_helper.c -o "$OUT/libffi_longdouble_helper.so"
python3 -m cinterp compile examples/ffi_longdouble.c -o "$OUT/ffi_longdouble.cib" >/dev/null
ld_out="$("$RUNTIME" --lib "$OUT/libffi_longdouble_helper.so" "$OUT/ffi_longdouble.cib" 2>&1)"
printf '%s\n' "$ld_out" | grep -Fq "result: 60"
echo "OK ffi_longdouble -> 60"

echo "== callback (qsort)"
python3 -m cinterp compile examples/ffi_qsort.c -o "$OUT/ffi_qsort.cib" >/dev/null
qsort_out="$("$RUNTIME" "$OUT/ffi_qsort.cib" 2>&1)"
printf '%s\n' "$qsort_out" | grep -Fq "result: 1"
echo "OK ffi_qsort -> 1"

echo "== callback (stack args + structs)"
cc -shared -fPIC -O0 examples/ffi_callback_helper.c -o "$OUT/libffi_callback_helper.so"
python3 -m cinterp compile examples/ffi_callback.c -o "$OUT/ffi_callback.cib" >/dev/null
cb_out="$("$RUNTIME" --lib "$OUT/libffi_callback_helper.so" "$OUT/ffi_callback.cib" 2>&1)"
printf '%s\n' "$cb_out" | grep -Fq "result: 256"
echo "OK ffi_callback -> 256"
cc -shared -fPIC -O0 examples/ffi_callback_big_helper.c -o "$OUT/libffi_callback_big_helper.so"
python3 -m cinterp compile examples/ffi_callback_big.c -o "$OUT/ffi_callback_big.cib" >/dev/null
bigcb_out="$("$RUNTIME" --lib "$OUT/libffi_callback_big_helper.so" "$OUT/ffi_callback_big.cib" 2>&1)"
printf '%s\n' "$bigcb_out" | grep -Fq "result: 246"
echo "OK ffi_callback_big -> 246"

echo "== callback HFA + long double"
cc -shared -fPIC -O0 examples/ffi_callback_hfa_helper.c -o "$OUT/libffi_callback_hfa_helper.so"
python3 -m cinterp compile examples/ffi_callback_hfa.c -o "$OUT/ffi_callback_hfa.cib" >/dev/null
hfacb_out="$("$RUNTIME" --lib "$OUT/libffi_callback_hfa_helper.so" "$OUT/ffi_callback_hfa.cib" 2>&1)"
printf '%s\n' "$hfacb_out" | grep -Fq "result: 247"
echo "OK ffi_callback_hfa -> 247"

echo "== error paths"
if python3 -m cinterp compile "$OUT/does-not-exist.c" >/dev/null 2>&1; then
    echo "FAIL missing input accepted" >&2
    exit 1
fi
echo "OK missing input"
printf 'BAD' > "$OUT/bad.cib"
if "$RUNTIME" "$OUT/bad.cib" >/dev/null 2>&1; then
    echo "FAIL bad package accepted" >&2
    exit 1
fi
echo "OK bad package"
for n in 0 4 5 14 15 30 100; do
    head -c "$n" "$OUT/ffi_qsort.cib" > "$OUT/trunc.cib"
    set +e
    "$RUNTIME" "$OUT/trunc.cib" >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] || [ "$rc" -ge 128 ]; then
        echo "FAIL truncated package ($n bytes) exited $rc" >&2
        exit 1
    fi
done
echo "OK truncated packages"
cat > "$OUT/missing_symbol.c" <<'EOF'
void definitely_not_a_real_symbol(void);
int main(void) { definitely_not_a_real_symbol(); return 0; }
EOF
python3 -m cinterp compile "$OUT/missing_symbol.c" -o "$OUT/missing_symbol.cib" >/dev/null
if "$RUNTIME" "$OUT/missing_symbol.cib" >/dev/null 2>&1; then
    echo "FAIL unknown symbol accepted" >&2
    exit 1
fi
echo "OK unknown symbol"
python3 -m cinterp --version 2>&1 | grep -Fq "cinterp 0.1.0"
"$RUNTIME" --version 2>&1 | grep -Fq "cinterp-run 0.1.0"
echo "OK version"

echo "all tests passed"

echo "== CIB v2 target/import metadata"
python3 -m cinterp compile examples/ffi_printf.c -o "$OUT/ffi_printf.cib" --dump-imports >"$OUT/imports.txt"
grep -Fq "target=x86_64-linux" "$OUT/imports.txt"
grep -Fq "import[plan " "$OUT/imports.txt"
"$RUNTIME" --dump-target --dump-imports --load-only "$OUT/ffi_printf.cib" >"$OUT/imports-runtime.txt" 2>&1
grep -Fq "target: x86_64-pc-linux-gnu" "$OUT/imports-runtime.txt"
grep -Fq "printf: libc.so.6:printf" "$OUT/imports-runtime.txt"
echo "OK CIPM/CIPI metadata"

python3 -m cinterp compile examples/hello.c --target x86_64-windows -o "$OUT/hello-win.cib" >/dev/null
if "$RUNTIME" "$OUT/hello-win.cib" >"$OUT/target-mismatch.txt" 2>&1; then
    echo "FAIL target mismatch was accepted" >&2
    exit 1
fi
grep -Fq "TargetMismatch" "$OUT/target-mismatch.txt"
echo "OK target mismatch rejected"

python3 -m cinterp compile examples/hello.c --cib-version 1 -o "$OUT/hello-v1.cib" >/dev/null
v1_out="$("$RUNTIME" "$OUT/hello-v1.cib" 2>&1)"
printf '%s\n' "$v1_out" | grep -Fq "result: 42"
echo "OK legacy CIPKG v1"

python3 -m cinterp compile examples/ffi_printf.c --no-auto-link -o "$OUT/ffi_printf-nolink.cib" --dump-imports >"$OUT/nolink.txt"
grep -Fq "imports=0" "$OUT/nolink.txt"
nolink_out="$("$RUNTIME" "$OUT/ffi_printf-nolink.cib" 2>&1)"
printf '%s\n' "$nolink_out" | grep -Fq "result: 0"
echo "OK --no-auto-link fallback"

python3 -m cinterp compile examples/ffi_printf.c -o "$OUT/ffi_printf-linkdb.cib" --link-db compiler/src/cinterp/link --dump-imports >"$OUT/linkdb.txt"
grep -Fq "imports=1" "$OUT/linkdb.txt"
echo "OK --link-db override"

if "$RUNTIME" --safe "$OUT/ffi_printf.cib" >"$OUT/safe-import.txt" 2>&1; then
    echo "FAIL --safe accepted native call" >&2
    exit 1
fi
grep -Fq "SafeMode" "$OUT/safe-import.txt"
echo "OK --safe rejects imported call"
