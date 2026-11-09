#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RUNTIME="$ROOT/runtime/zig-out/bin/cinterp-run"
OUT="$ROOT/build"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
COMPILER="$ROOT/build/cinterp-cc"
mkdir -p "$OUT"

compile() {
    "$COMPILER" compile "$@"
}

example() {
    case "$1" in
        hello|arrays|structs|math|float_math|bitfields|longdouble|packed|packed_helper|ptrstruct)
            echo "examples/basics/$1.c" ;;
        ffi_*) echo "examples/ffi/$1.c" ;;
        ifconfig|ps|netstat|route) echo "examples/linux/$1.c" ;;
        winapi) echo "examples/windows/$1.c" ;;
        *) echo "examples/$1.c" ;;
    esac
}

echo "== runtime unit tests"
(cd runtime && zig build test --summary all)

echo "== compiler unit tests"
(cd compiler && zig build test --summary all)

echo "== build runtime"
(cd runtime && zig build -Doptimize=ReleaseSmall)
if grep -a -q -E 'OutOfMemory|StackOverflow|FrameOverflow' "$RUNTIME"; then
    echo "FAIL release runtime retains Zig error-name strings" >&2
    exit 1
fi
echo "OK release runtime has no error-name strings"

run_case() {
    local name="$1"
    local expected="$2"
    local cib="$OUT/$name.cib"
    compile "$(example "$name")" -o "$cib" >/dev/null
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
run_case ffi_printf_longdouble 42
run_case longdouble 8

echo "== Linux command examples"
compile examples/linux/ifconfig.c -o "$OUT/ifconfig.cib" >/dev/null
ifconfig_out="$("$RUNTIME" "$OUT/ifconfig.cib" 2>&1)"
printf '%s\n' "$ifconfig_out" | grep -Fq "result: 42"
printf '%s\n' "$ifconfig_out" | grep -Fq "interfaces:"
printf '%s\n' "$ifconfig_out" | grep -Fq "lo:"
echo "OK ifconfig"

compile examples/linux/ps.c -o "$OUT/ps.cib" >/dev/null
ps_out="$("$RUNTIME" "$OUT/ps.cib" 2>&1)"
printf '%s\n' "$ps_out" | grep -Fq "result: 42"
printf '%s\n' "$ps_out" | grep -Fq "PID"
printf '%s\n' "$ps_out" | grep -Fq "processes:"
echo "OK ps"

compile examples/linux/netstat.c -o "$OUT/netstat.cib" >/dev/null
netstat_out="$("$RUNTIME" "$OUT/netstat.cib" 2>&1)"
printf '%s\n' "$netstat_out" | grep -Fq "result: 42"
printf '%s\n' "$netstat_out" | grep -Fq "Active tcp connections"
printf '%s\n' "$netstat_out" | grep -Fq "Proto"
echo "OK netstat"

compile examples/linux/route.c -o "$OUT/route.cib" >/dev/null
route_out="$("$RUNTIME" "$OUT/route.cib" 2>&1)"
printf '%s\n' "$route_out" | grep -Fq "result: 42"
printf '%s\n' "$route_out" | grep -Fq "IPv4 routes"
printf '%s\n' "$route_out" | grep -Fq "Destination"
echo "OK route"

echo "== bitfields"
compile examples/basics/bitfields.c -o "$OUT/bitfields.cib" >/dev/null
bits_out="$("$RUNTIME" "$OUT/bitfields.cib" 2>&1)"
printf '%s\n' "$bits_out" | grep -Fq "result: 12"
echo "OK bitfields -> 12"

echo "== native calls"
compile examples/ffi/ffi_puts.c -o "$OUT/ffi_puts.cib" >/dev/null
puts_out="$("$RUNTIME" "$OUT/ffi_puts.cib" 2>&1)"
printf '%s\n' "$puts_out" | grep -Fq "hello from cinterp"
printf '%s\n' "$puts_out" | grep -Fq "result: 0"
echo "OK ffi_puts"

compile examples/ffi/ffi_printf.c -o "$OUT/ffi_printf.cib" >/dev/null
printf_out="$("$RUNTIME" "$OUT/ffi_printf.cib" 2>&1)"
printf '%s\n' "$printf_out" | grep -Fq "7 2.5"
printf '%s\n' "$printf_out" | grep -Fq "result: 0"
echo "OK ffi_printf"

echo "== struct FFI (byval + sret)"
# Library-backed cases use the C API runner linked against libcinterp.
cc -std=c11 -I runtime/zig-out/include runtime/tests/capi_runner.c \
    runtime/zig-out/lib/libcinterp.a -ldl -lpthread -lm -o "$OUT/capi_runner"
cc -shared -fPIC -O0 examples/ffi/ffi_structs_helper.c -o "$OUT/libstruct_helpers.so"
compile examples/ffi/ffi_structs.c -o "$OUT/ffi_structs.cib" >/dev/null
struct_out="$("$OUT/capi_runner" "$OUT/ffi_structs.cib" "$OUT/libstruct_helpers.so" 2>&1)"
printf '%s\n' "$struct_out" | grep -Fq "result: 28"
echo "OK ffi_structs -> 28"

echo "== register-class struct FFI (S8 + D16)"
cc -shared -fPIC -O0 examples/ffi/ffi_regstruct_helper.c -o "$OUT/libregstruct_helpers.so"
compile examples/ffi/ffi_regstruct.c -o "$OUT/ffi_regstruct.cib" >/dev/null
reg_out="$("$OUT/capi_runner" "$OUT/ffi_regstruct.cib" "$OUT/libregstruct_helpers.so" 2>&1)"
printf '%s\n' "$reg_out" | grep -Fq "result: 102"
echo "OK ffi_regstruct -> 102"
compile examples/ffi/ffi_regstruct_live.c -o "$OUT/ffi_regstruct_live.cib" >/dev/null
reglive_out="$("$OUT/capi_runner" "$OUT/ffi_regstruct_live.cib" "$OUT/libregstruct_helpers.so" 2>&1)"
printf '%s\n' "$reglive_out" | grep -Fq "result: 10"
echo "OK ffi_regstruct_live -> 10"

echo "== mixed-class aggregate FFI (i64 + double)"
cc -shared -fPIC -O0 examples/ffi/ffi_mixedstruct_helper.c -o "$OUT/libmixedstruct_helpers.so"
compile examples/ffi/ffi_mixedstruct.c -o "$OUT/ffi_mixedstruct.cib" >/dev/null
mixed_out="$("$OUT/capi_runner" "$OUT/ffi_mixedstruct.cib" "$OUT/libmixedstruct_helpers.so" 2>&1)"
printf '%s\n' "$mixed_out" | grep -Fq "result: 11"
echo "OK ffi_mixedstruct -> 11"

echo "== double arithmetic"
compile examples/basics/math.c -o "$OUT/math.cib" >/dev/null
math_out="$("$RUNTIME" "$OUT/math.cib" 2>&1)"
printf '%s\n' "$math_out" | grep -Fq "result: 8"
echo "OK math -> 8"

echo "== float32 arithmetic"
compile examples/basics/float_math.c -o "$OUT/float_math.cib" >/dev/null
float_out="$("$RUNTIME" "$OUT/float_math.cib" 2>&1)"
printf '%s\n' "$float_out" | grep -Fq "result: 8"
echo "OK float_math -> 8"

echo "== float32 FFI"
cc -shared -fPIC -O0 examples/ffi/ffi_float_helper.c -o "$OUT/libfloat_helpers.so"
compile examples/ffi/ffi_float.c -o "$OUT/ffi_float.cib" >/dev/null
ffloat_out="$("$OUT/capi_runner" "$OUT/ffi_float.cib" "$OUT/libfloat_helpers.so" 2>&1)"
printf '%s\n' "$ffloat_out" | grep -Fq "result: 5"
echo "OK ffi_float -> 5"

echo "== ABI edges / HFA / packed"
cc -shared -fPIC -O0 examples/ffi/ffi_edges_helper.c -o "$OUT/libffi_edges_helper.so"
compile examples/ffi/ffi_edges.c -o "$OUT/ffi_edges.cib" >/dev/null
edge_out="$("$OUT/capi_runner" "$OUT/ffi_edges.cib" "$OUT/libffi_edges_helper.so" 2>&1)"
printf '%s\n' "$edge_out" | grep -Fq "result: 55"
echo "OK ffi_edges -> 55"
cc -shared -fPIC -O0 examples/ffi/ffi_hfa_helper.c -o "$OUT/libffi_hfa_helper.so"
compile examples/ffi/ffi_hfa.c -o "$OUT/ffi_hfa.cib" >/dev/null
hfa_out="$("$OUT/capi_runner" "$OUT/ffi_hfa.cib" "$OUT/libffi_hfa_helper.so" 2>&1)"
printf '%s\n' "$hfa_out" | grep -Fq "result: 120"
echo "OK ffi_hfa -> 120"
cc -shared -fPIC -O0 examples/ffi/ffi_hfa_stack_helper.c -o "$OUT/libffi_hfa_stack_helper.so"
compile examples/ffi/ffi_hfa_stack.c -o "$OUT/ffi_hfa_stack.cib" >/dev/null
hfas_out="$("$OUT/capi_runner" "$OUT/ffi_hfa_stack.cib" "$OUT/libffi_hfa_stack_helper.so" 2>&1)"
printf '%s\n' "$hfas_out" | grep -Fq "result: 45"
echo "OK ffi_hfa_stack -> 45"
cc -shared -fPIC -O0 examples/basics/packed_helper.c -o "$OUT/libpacked_helper.so"
compile examples/basics/packed.c -o "$OUT/packed.cib" >/dev/null
packed_out="$("$OUT/capi_runner" "$OUT/packed.cib" "$OUT/libpacked_helper.so" 2>&1)"
printf '%s\n' "$packed_out" | grep -Fq "result: 7"
echo "OK packed -> 7"

echo "== long double FFI"
cc -shared -fPIC -O0 examples/ffi/ffi_longdouble_helper.c -o "$OUT/libffi_longdouble_helper.so"
compile examples/ffi/ffi_longdouble.c -o "$OUT/ffi_longdouble.cib" >/dev/null
ld_out="$("$OUT/capi_runner" "$OUT/ffi_longdouble.cib" "$OUT/libffi_longdouble_helper.so" 2>&1)"
printf '%s\n' "$ld_out" | grep -Fq "result: 60"
echo "OK ffi_longdouble -> 60"
compile examples/ffi/ffi_longdouble_live.c -o "$OUT/ffi_longdouble_live.cib" >/dev/null
ldlive_out="$("$OUT/capi_runner" "$OUT/ffi_longdouble_live.cib" "$OUT/libffi_longdouble_helper.so" 2>&1)"
printf '%s\n' "$ldlive_out" | grep -Fq "result: 15"
echo "OK ffi_longdouble_live -> 15"

echo "== callback (qsort)"
compile examples/ffi/ffi_qsort.c -o "$OUT/ffi_qsort.cib" >/dev/null
qsort_out="$("$RUNTIME" "$OUT/ffi_qsort.cib" 2>&1)"
printf '%s\n' "$qsort_out" | grep -Fq "result: 1"
echo "OK ffi_qsort -> 1"

echo "== explicit callback acquire/release"
compile examples/ffi/ffi_callback_scope.c -o "$OUT/ffi_callback_scope.cib" >/dev/null
cbscope_out="$("$RUNTIME" "$OUT/ffi_callback_scope.cib" 2>&1)"
printf '%s\n' "$cbscope_out" | grep -Fq "result: 1"
echo "OK ffi_callback_scope -> 1"
echo "== callback (stack args + structs)"
cc -shared -fPIC -O0 examples/ffi/ffi_callback_helper.c -o "$OUT/libffi_callback_helper.so"
compile examples/ffi/ffi_callback.c -o "$OUT/ffi_callback.cib" >/dev/null
cb_out="$("$OUT/capi_runner" "$OUT/ffi_callback.cib" "$OUT/libffi_callback_helper.so" 2>&1)"
printf '%s\n' "$cb_out" | grep -Fq "result: 256"
echo "OK ffi_callback -> 256"
cc -shared -fPIC -O0 examples/ffi/ffi_callback_big_helper.c -o "$OUT/libffi_callback_big_helper.so"
compile examples/ffi/ffi_callback_big.c -o "$OUT/ffi_callback_big.cib" >/dev/null
bigcb_out="$("$OUT/capi_runner" "$OUT/ffi_callback_big.cib" "$OUT/libffi_callback_big_helper.so" 2>&1)"
printf '%s\n' "$bigcb_out" | grep -Fq "result: 246"
echo "OK ffi_callback_big -> 246"

echo "== callback HFA + long double"
cc -shared -fPIC -O0 examples/ffi/ffi_callback_hfa_helper.c -o "$OUT/libffi_callback_hfa_helper.so"
compile examples/ffi/ffi_callback_hfa.c -o "$OUT/ffi_callback_hfa.cib" >/dev/null
hfacb_out="$("$OUT/capi_runner" "$OUT/ffi_callback_hfa.cib" "$OUT/libffi_callback_hfa_helper.so" 2>&1)"
printf '%s\n' "$hfacb_out" | grep -Fq "result: 247"
echo "OK ffi_callback_hfa -> 247"

echo "== ordinary signal callback"
compile examples/ffi/ffi_signal.c -o "$OUT/ffi_signal.cib" >/dev/null
signal_out="$("$RUNTIME" "$OUT/ffi_signal.cib" 2>&1)"
printf '%s\n' "$signal_out" | grep -Fq "result: 42"
echo "OK ffi_signal -> 42"

echo "== ordinary atexit symbol"
compile examples/ffi/ffi_atexit.c -o "$OUT/ffi_atexit.cib" >/dev/null
atexit_out="$("$RUNTIME" "$OUT/ffi_atexit.cib" 2>&1)"
printf '%s\n' "$atexit_out" | grep -Fq "result: 42"
printf '%s\n' "$atexit_out" | grep -Fq "bye"
echo "OK ffi_atexit -> 42 + bye"

echo "== error paths"
if compile "$OUT/does-not-exist.c" >/dev/null 2>&1; then
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
compile "$OUT/missing_symbol.c" -o "$OUT/missing_symbol.cib" >/dev/null
if "$RUNTIME" "$OUT/missing_symbol.cib" >/dev/null 2>&1; then
    echo "FAIL unknown symbol accepted" >&2
    exit 1
fi
echo "OK unknown symbol"
"$COMPILER" --version 2>&1 | grep -Fq "cinterp-cc $VERSION"
echo "OK version"

echo "== CIB import metadata"
compile examples/ffi/ffi_printf.c -o "$OUT/ffi_printf.cib" --dump-imports >"$OUT/imports.txt"
# Linux providers come from the build-time glibc abilists index
# (compiler/src/libc_defs.zig), so printf must resolve to libc.so.6.
grep -Fq "import[plan 0] printf: libc.so.6:printf" "$OUT/imports.txt"
echo "OK CIPI metadata"

# Windows API providers come from the build-time MinGW .def index
# (compiler/src/win_defs.zig). Compile-only: no Wine needed here, the
# actual Win64/Win32 execution lives in `make test-winapi`.
echo "== Windows API import metadata (MinGW defs)"
compile examples/windows/winapi.c --target x86_64-windows -o "$OUT/winapi64-meta.cib" --dump-imports >"$OUT/winapi64.txt"
grep -Fq "import[plan 0] GetTickCount64: kernel32.dll:GetTickCount64" "$OUT/winapi64.txt"
grep -Fq "import[plan 1] GetSystemMetrics: user32.dll:GetSystemMetrics" "$OUT/winapi64.txt"
grep -Fq "import[plan 2] GetModuleHandleA: kernel32.dll:GetModuleHandleA" "$OUT/winapi64.txt"
grep -Fq "import[plan 3] wsprintfA: user32.dll:wsprintfA" "$OUT/winapi64.txt"
compile examples/windows/winapi.c --target i686-windows -o "$OUT/winapi32-meta.cib" --dump-imports >"$OUT/winapi32.txt"
# Win32 stdcall decoration stays in the plan name while the provider symbol is
# the undecorated export.
grep -Fq '\01_GetTickCount64@0: kernel32.dll:GetTickCount64' "$OUT/winapi32.txt"
grep -Fq '\01_GetSystemMetrics@4: user32.dll:GetSystemMetrics' "$OUT/winapi32.txt"
grep -Fq 'wsprintfA: user32.dll:wsprintfA' "$OUT/winapi32.txt"
echo "OK Windows API import metadata"

compile examples/ffi/ffi_printf.c --no-auto-link -o "$OUT/ffi_printf-nolink.cib" --dump-imports >"$OUT/nolink.txt"
if grep -Fq "import[plan 0]" "$OUT/nolink.txt"; then
    echo "FAIL --no-auto-link still emitted a function plan import" >&2
    exit 1
fi
nolink_out="$("$RUNTIME" "$OUT/ffi_printf-nolink.cib" 2>&1)"
printf '%s\n' "$nolink_out" | grep -Fq "result: 0"
echo "OK --no-auto-link fallback"

echo "== C embedding API (static + shared)"
compile runtime/tests/capi_argv.c -o "$OUT/capi_argv.cib" >/dev/null
cc -std=c11 -I runtime/zig-out/include -DCINTERP_EXPECT_VERSION="\"$VERSION\"" \
    runtime/tests/capi_smoke.c \
    runtime/zig-out/lib/libcinterp.a -ldl -lpthread -lm -o "$OUT/capi_smoke"
"$OUT/capi_smoke" "$OUT/hello.cib" "$OUT/ffi_qsort.cib" "$OUT/capi_argv.cib"
cc -std=c11 -I runtime/zig-out/include -DCINTERP_EXPECT_VERSION="\"$VERSION\"" \
    runtime/tests/capi_smoke.c \
    -Lruntime/zig-out/lib -Wl,-rpath,"$ROOT/runtime/zig-out/lib" -lcinterp \
    -o "$OUT/capi_smoke_shared"
"$OUT/capi_smoke_shared" "$OUT/hello.cib" "$OUT/ffi_qsort.cib" "$OUT/capi_argv.cib"
echo "OK C embedding API"

echo "== multi-CIB process API (pthreads, static + shared)"
# The busy package spins for about one second of CPU time so capi_multi can
# observe ci_vm_busy / unload / destroy while another thread runs its VM.
cat > "$OUT/capi_multi_busy.c" <<'EOF'
#include <time.h>

int main(void) {
    clock_t start = clock();
    while (clock() - start < CLOCKS_PER_SEC) {
    }
    return 7;
}
EOF
compile "$OUT/capi_multi_busy.c" -o "$OUT/capi_multi_busy.cib" >/dev/null
cc -std=c11 -I runtime/zig-out/include \
    runtime/tests/capi_multi.c \
    runtime/zig-out/lib/libcinterp.a -ldl -lpthread -lm -o "$OUT/capi_multi"
"$OUT/capi_multi" "$OUT/hello.cib" "$OUT/math.cib" "$OUT/ffi_qsort.cib" \
    "$OUT/capi_multi_busy.cib"
cc -std=c11 -I runtime/zig-out/include \
    runtime/tests/capi_multi.c \
    -Lruntime/zig-out/lib -Wl,-rpath,"$ROOT/runtime/zig-out/lib" -lcinterp \
    -o "$OUT/capi_multi_shared"
"$OUT/capi_multi_shared" "$OUT/hello.cib" "$OUT/math.cib" "$OUT/ffi_qsort.cib" \
    "$OUT/capi_multi_busy.cib"
echo "OK multi-CIB process API"

echo "== CLI package and argv"
legacy_out="$("$RUNTIME" "$OUT/hello.cib" 2>&1)"
if [ "$legacy_out" != "result: 42" ]; then
    echo "FAIL package-only run changed its output" >&2
    printf '%s\n' "$legacy_out" >&2
    exit 1
fi
argv_out="$("$RUNTIME" "$OUT/capi_argv.cib" -- x 7 2>&1)"
if [ "$argv_out" != "result: 7" ]; then
    echo "FAIL package -- argv changed its output" >&2
    printf '%s\n' "$argv_out" >&2
    exit 1
fi
echo "OK CLI package and argv"

expect_usage_error() {
    local name="$1"
    shift
    set +e
    "$@" >/dev/null 2>&1
    local rc=$?
    set -e
    if [ "$rc" -ne 2 ]; then
        echo "FAIL $name: expected usage exit 2, got $rc" >&2
        exit 1
    fi
}
expect_usage_error "missing package" "$RUNTIME"
expect_usage_error "unexpected argument" "$RUNTIME" "$OUT/hello.cib" extra
echo "OK CLI usage/error paths"

echo "all tests passed"
