#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGETS="${CROSS_TARGETS:-win64,win32,arm64}"
QEMU="${QEMU:-qemu-aarch64}"
SYSROOT="${SYSROOT:-/usr/aarch64-linux-gnu}"
OUT="$ROOT/build/cross"
mkdir -p "$OUT"

while [ $# -gt 0 ]; do
    case "$1" in
        --targets) TARGETS="$2"; shift 2 ;;
        --targets=*) TARGETS="${1#--targets=}"; shift ;;
        *) echo "usage: $0 [--targets win64,win32,arm64]" >&2; exit 2 ;;
    esac
done

want() {
    case ",$TARGETS," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# Pick the compiler the same way `make compiler` produces it. Git Bash/MSYS
# builds name the binary cinterp-cc.exe, so prefer that when it is present.
resolve_cinterp_cc() {
    if [ -n "${CINTERP_COMPILER:-}" ]; then
        echo "$CINTERP_COMPILER"
        return 0
    fi
    if [ -x "$ROOT/build/cinterp-cc.exe" ]; then
        echo "$ROOT/build/cinterp-cc.exe"
        return 0
    fi
    if [ -x "$ROOT/build/cinterp-cc" ]; then
        echo "$ROOT/build/cinterp-cc"
        return 0
    fi
    return 1
}

if ! CINTERP_CC="$(resolve_cinterp_cc)"; then
    echo "error: cinterp compiler not found; expected build/cinterp-cc.exe or build/cinterp-cc." >&2
    echo "       run 'make compiler' (or 'cd compiler && zig build' and copy the binary to build/)," >&2
    echo "       or set CINTERP_COMPILER=/path/to/cinterp-cc" >&2
    exit 2
fi
if [ ! -x "$CINTERP_CC" ]; then
    echo "error: cinterp compiler '$CINTERP_CC' is not executable" >&2
    echo "       run 'make compiler' or set CINTERP_COMPILER=/path/to/cinterp-cc" >&2
    exit 2
fi
echo "compiler: $CINTERP_CC"

is_windows_shell() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

win_runner() {
    case "$1" in
        *64.exe)
            echo "${WIN64_RUNNER:-$(command -v wine64 || command -v wine || echo wine64)}"
            ;;
        *) echo "${WIN32_RUNNER:-wine}" ;;
    esac
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

compile() {
    local target="$1" name="$2"
    "$CINTERP_CC" compile "$(example "$name")" --target "$target" -o "$OUT/$name-$target.cib" >/dev/null
}

compile_source() {
    local target="$1" source="$2" name="$3"
    "$CINTERP_CC" compile "$source" --target "$target" -o "$OUT/$name-$target.cib" >/dev/null
}

# Win32 __stdcall/__fastcall are only correct when the plan carries the calling
# convention, so assert the plan dump instead of only checking the result.
assert_conv() {
    local name="$1" symbol="$2" want="$3" out line
    if ! out="$("$CINTERP_CC" compile "$(example "$name")" --target i686-windows \
        -o "$OUT/$name-dump.cib" --dump 2>&1)"; then
        echo "FAIL $name: compile --dump failed" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    line="$(printf '%s\n' "$out" | grep -F "plan" | grep -F "$symbol" | head -n1)"
    if [ -z "$line" ]; then
        echo "FAIL $name: no plan for '$symbol' in --dump output" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    if ! printf '%s\n' "$line" | grep -Fq "conv=$want"; then
        echo "FAIL $name: expected conv=$want for '$symbol', got: $line" >&2
        echo "      (cinterp-cc --dump must print the plan conv field; see plan item B.5/C.1)" >&2
        exit 1
    fi
    echo "OK $name $symbol conv=$want"
}

win_run() {
    local exe="$1" package="$2" lib="${3:-}" expected="$4" repeat="${5:-1}" out
    if is_windows_shell; then
        if [[ -n "$lib" ]]; then
            out="$(cd "$OUT" && "./$exe" --lib "$lib" --repeat "$repeat" "$package" 2>&1)"
        else
            out="$(cd "$OUT" && "./$exe" --repeat "$repeat" "$package" 2>&1)"
        fi
    else
        local runner
        runner="$(win_runner "$exe")"
        local first="${runner%% *}"
        if ! have "$first"; then
            echo "missing Windows runner '$first'; install wine or set WIN64_RUNNER/WIN32_RUNNER" >&2
            exit 2
        fi
        local wine_prefix wine_arch
        if [[ "$exe" == *32.exe ]]; then
            wine_prefix="${WINEPREFIX:-$ROOT/build/wine32}"
            wine_arch=win32
        else
            wine_prefix="${WINEPREFIX:-$ROOT/build/wine64}"
            wine_arch=win64
        fi
        if [ ! -f "$wine_prefix/drive_c/windows/system32/kernel32.dll" ]; then
            WINEARCH="$wine_arch" WINEPREFIX="$wine_prefix" WINEDEBUG=-all \
                WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u >/dev/null 2>&1 || true
        fi
        # A crashing test must return an exit status, not open Wine's modal
        # crash dialog and hang the suite.
        WINEARCH="$wine_arch" WINEPREFIX="$wine_prefix" WINEDEBUG=-all \
            WINEDLLOVERRIDES="mscoree,mshtml=" "$runner" reg add \
            'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f \
            >/dev/null 2>&1 || true
        if [[ -n "$lib" ]]; then
            out="$(cd "$OUT" && WINEARCH="$wine_arch" WINEPREFIX="$wine_prefix" \
                WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
                "$runner" "$exe" --lib "$lib" --repeat "$repeat" "$package" 2>&1)"
        else
            out="$(cd "$OUT" && WINEARCH="$wine_arch" WINEPREFIX="$wine_prefix" \
                WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
                "$runner" "$exe" --repeat "$repeat" "$package" 2>&1)"
        fi
    fi
    local got
    got="$(printf '%s\n' "$out" | grep -cF "result: $expected" || true)"
    if [ "$got" != "$repeat" ]; then
        echo "FAIL $package (expected $expected x$repeat, got $got)" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    echo "OK $package -> $expected x$repeat"
}

USUAL=(hello arrays structs ffi_malloc ffi_printf ffi_printf_longdouble ffi_snprintf math ffi_float ffi_structs ffi_regstruct ffi_regstruct_live ffi_mixedstruct ffi_qsort ffi_callback ffi_callback_big ffi_longdouble ffi_longdouble_live ffi_edges ffi_hfa ffi_hfa_stack packed)
HELPERS=(ffi_float_helper ffi_structs_helper ffi_regstruct_helper ffi_mixedstruct_helper ffi_callback_helper ffi_callback_big_helper ffi_longdouble_helper ffi_edges_helper ffi_hfa_helper ffi_hfa_stack_helper packed_helper)

if want win64; then
    echo "== Win64"
    (cd runtime && zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall)
    cp runtime/zig-out/bin/cinterp-run.exe "$OUT/cinterp-run64.exe"
    for name in "${USUAL[@]}"; do compile x86_64-windows "$name"; done
    compile x86_64-windows winapi
    compile_source x86_64-windows tests/csuite/external_data.c external_data
    for h in "${HELPERS[@]}"; do
        zig cc -target x86_64-windows-gnu -shared -O0 -Wl,--export-all-symbols \
            -o "$OUT/lib${h}64.dll" "$(example "$h")"
    done
    win_run cinterp-run64.exe hello-x86_64-windows.cib "" 42
    win_run cinterp-run64.exe arrays-x86_64-windows.cib "" 10
    win_run cinterp-run64.exe structs-x86_64-windows.cib "" 34
    win_run cinterp-run64.exe ffi_malloc-x86_64-windows.cib "" 42
    win_run cinterp-run64.exe ffi_printf-x86_64-windows.cib "" 0
    win_run cinterp-run64.exe ffi_printf_longdouble-x86_64-windows.cib "" 42
    win_run cinterp-run64.exe ffi_snprintf-x86_64-windows.cib "" 55
    win_run cinterp-run64.exe math-x86_64-windows.cib "" 8
    win_run cinterp-run64.exe ffi_float-x86_64-windows.cib libffi_float_helper64.dll 5
    win_run cinterp-run64.exe ffi_structs-x86_64-windows.cib libffi_structs_helper64.dll 28
    win_run cinterp-run64.exe ffi_regstruct-x86_64-windows.cib libffi_regstruct_helper64.dll 102
    win_run cinterp-run64.exe ffi_regstruct_live-x86_64-windows.cib libffi_regstruct_helper64.dll 10
    win_run cinterp-run64.exe ffi_mixedstruct-x86_64-windows.cib libffi_mixedstruct_helper64.dll 11
    win_run cinterp-run64.exe ffi_qsort-x86_64-windows.cib "" 1
    win_run cinterp-run64.exe ffi_qsort-x86_64-windows.cib "" 1 2
    win_run cinterp-run64.exe ffi_callback-x86_64-windows.cib libffi_callback_helper64.dll 256
    win_run cinterp-run64.exe ffi_callback_big-x86_64-windows.cib libffi_callback_big_helper64.dll 246
    win_run cinterp-run64.exe ffi_longdouble-x86_64-windows.cib libffi_longdouble_helper64.dll 60
    win_run cinterp-run64.exe ffi_longdouble_live-x86_64-windows.cib libffi_longdouble_helper64.dll 15
    win_run cinterp-run64.exe ffi_edges-x86_64-windows.cib libffi_edges_helper64.dll 55
    win_run cinterp-run64.exe ffi_hfa-x86_64-windows.cib libffi_hfa_helper64.dll 120
    win_run cinterp-run64.exe ffi_hfa_stack-x86_64-windows.cib libffi_hfa_stack_helper64.dll 45
    win_run cinterp-run64.exe packed-x86_64-windows.cib libpacked_helper64.dll 7
    win_run cinterp-run64.exe winapi-x86_64-windows.cib "" 7
    win_run cinterp-run64.exe external_data-x86_64-windows.cib "" 42
fi

if want win32; then
    echo "== Win32"
    (cd runtime && zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall)
    cp runtime/zig-out/bin/cinterp-run.exe "$OUT/cinterp-run32.exe"
    for name in "${USUAL[@]}"; do compile i686-windows "$name"; done
    compile i686-windows winapi
    compile_source i686-windows tests/csuite/external_data.c external_data
    for h in "${HELPERS[@]}"; do
        zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols \
            -o "$OUT/lib${h}32.dll" "$(example "$h")"
    done
    "$CINTERP_CC" compile examples/ffi/ffi_stdcall.c --target i686-windows -o "$OUT/ffi_stdcall-i686-windows.cib" >/dev/null
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols -o "$OUT/libffi_stdcall_helper32.dll" examples/ffi/ffi_stdcall_helper.c
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols -o "$OUT/libffi_fastcall_helper32.dll" examples/ffi/ffi_fastcall_helper.c
    "$CINTERP_CC" compile examples/ffi/ffi_fastcall.c --target i686-windows -o "$OUT/ffi_fastcall-i686-windows.cib" >/dev/null
    # Plan conv must be 1/2/3 for the Win32 stdcall/fastcall/thiscall plans.
    assert_conv ffi_stdcall c_std_add3 1
    assert_conv ffi_fastcall fast_add 2
    assert_conv ffi_thiscall c_tc_add3 3
    assert_conv ffi_callback_fastcall 'callback:' 2
    assert_conv ffi_callback_thiscall 'callback:' 3
    # __stdcall callback (workstream E). The helper calls an int(__stdcall *)(int,int).
    for required in examples/ffi/ffi_callback_stdcall.c examples/ffi/ffi_callback_stdcall_helper.c; do
        if [ ! -f "$required" ]; then
            echo "FAIL Win32: missing $required; the stdcall callback case cannot be verified" >&2
            exit 1
        fi
    done
    "$CINTERP_CC" compile examples/ffi/ffi_callback_stdcall.c --target i686-windows \
        -o "$OUT/ffi_callback_stdcall-i686-windows.cib" >/dev/null
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols \
        -o "$OUT/libffi_callback_stdcall_helper32.dll" examples/ffi/ffi_callback_stdcall_helper.c
    # __fastcall callback: first two int args arrive in ECX/EDX.
    for required in examples/ffi/ffi_callback_fastcall.c examples/ffi/ffi_callback_fastcall_helper.c; do
        if [ ! -f "$required" ]; then
            echo "FAIL Win32: missing $required; the fastcall callback case cannot be verified" >&2
            exit 1
        fi
    done
    "$CINTERP_CC" compile examples/ffi/ffi_callback_fastcall.c --target i686-windows \
        -o "$OUT/ffi_callback_fastcall-i686-windows.cib" >/dev/null
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols \
        -o "$OUT/libffi_callback_fastcall_helper32.dll" examples/ffi/ffi_callback_fastcall_helper.c
    # __thiscall native call and callback: first arg in ECX, rest callee-popped stack.
    "$CINTERP_CC" compile examples/ffi/ffi_thiscall.c --target i686-windows \
        -o "$OUT/ffi_thiscall-i686-windows.cib" >/dev/null
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols \
        -o "$OUT/libffi_thiscall_helper32.dll" examples/ffi/ffi_thiscall_helper.c
    "$CINTERP_CC" compile examples/ffi/ffi_callback_thiscall.c --target i686-windows \
        -o "$OUT/ffi_callback_thiscall-i686-windows.cib" >/dev/null
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols \
        -o "$OUT/libffi_callback_thiscall_helper32.dll" examples/ffi/ffi_callback_thiscall_helper.c
    win_run cinterp-run32.exe hello-i686-windows.cib "" 42
    win_run cinterp-run32.exe arrays-i686-windows.cib "" 10
    win_run cinterp-run32.exe structs-i686-windows.cib "" 34
    win_run cinterp-run32.exe ffi_malloc-i686-windows.cib "" 42
    win_run cinterp-run32.exe ffi_printf-i686-windows.cib "" 0
    win_run cinterp-run32.exe ffi_printf_longdouble-i686-windows.cib "" 42
    win_run cinterp-run32.exe ffi_snprintf-i686-windows.cib "" 55
    win_run cinterp-run32.exe math-i686-windows.cib "" 8
    win_run cinterp-run32.exe ffi_float-i686-windows.cib libffi_float_helper32.dll 5
    win_run cinterp-run32.exe ffi_structs-i686-windows.cib libffi_structs_helper32.dll 28
    win_run cinterp-run32.exe ffi_regstruct-i686-windows.cib libffi_regstruct_helper32.dll 102
    win_run cinterp-run32.exe ffi_regstruct_live-i686-windows.cib libffi_regstruct_helper32.dll 10
    win_run cinterp-run32.exe ffi_mixedstruct-i686-windows.cib libffi_mixedstruct_helper32.dll 11
    win_run cinterp-run32.exe ffi_qsort-i686-windows.cib "" 1
    win_run cinterp-run32.exe ffi_qsort-i686-windows.cib "" 1 2
    win_run cinterp-run32.exe ffi_callback-i686-windows.cib libffi_callback_helper32.dll 256
    win_run cinterp-run32.exe ffi_callback_big-i686-windows.cib libffi_callback_big_helper32.dll 246
    win_run cinterp-run32.exe ffi_longdouble-i686-windows.cib libffi_longdouble_helper32.dll 60
    win_run cinterp-run32.exe ffi_longdouble_live-i686-windows.cib libffi_longdouble_helper32.dll 15
    win_run cinterp-run32.exe ffi_edges-i686-windows.cib libffi_edges_helper32.dll 55
    win_run cinterp-run32.exe ffi_hfa-i686-windows.cib libffi_hfa_helper32.dll 120
    win_run cinterp-run32.exe ffi_hfa_stack-i686-windows.cib libffi_hfa_stack_helper32.dll 45
    win_run cinterp-run32.exe packed-i686-windows.cib libpacked_helper32.dll 7
    win_run cinterp-run32.exe ffi_stdcall-i686-windows.cib libffi_stdcall_helper32.dll 60
    win_run cinterp-run32.exe ffi_fastcall-i686-windows.cib libffi_fastcall_helper32.dll 123
    win_run cinterp-run32.exe ffi_callback_stdcall-i686-windows.cib libffi_callback_stdcall_helper32.dll 42
    win_run cinterp-run32.exe ffi_callback_fastcall-i686-windows.cib libffi_callback_fastcall_helper32.dll 42
    win_run cinterp-run32.exe ffi_thiscall-i686-windows.cib libffi_thiscall_helper32.dll 123
    win_run cinterp-run32.exe ffi_callback_thiscall-i686-windows.cib libffi_callback_thiscall_helper32.dll 42
    win_run cinterp-run32.exe winapi-i686-windows.cib "" 7
    win_run cinterp-run32.exe external_data-i686-windows.cib "" 42
fi

if want arm64; then
    echo "== ARM64"
    (cd runtime && zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall)
    cp runtime/zig-out/bin/cinterp-run "$OUT/cinterp-run-arm64"
    for name in "${USUAL[@]}"; do compile aarch64-linux "$name"; done
    for h in "${HELPERS[@]}"; do
        aarch64-linux-gnu-gcc -shared -fPIC -O0 -o "$OUT/lib${h}-arm64.so" "$(example "$h")"
    done
    arm_run() {
        local name="$1" expected="$2" lib="${3:-}" repeat="${4:-1}"
        local out got
        if [[ -n "$lib" ]]; then
            out="$("$QEMU" -L "$SYSROOT" "$OUT/cinterp-run-arm64" --lib "$OUT/$lib" --repeat "$repeat" "$OUT/$name-aarch64-linux.cib" 2>&1)"
        else
            out="$("$QEMU" -L "$SYSROOT" "$OUT/cinterp-run-arm64" --repeat "$repeat" "$OUT/$name-aarch64-linux.cib" 2>&1)"
        fi
        got="$(printf '%s\n' "$out" | grep -cF "result: $expected" || true)"
        if [ "$got" != "$repeat" ]; then
            echo "FAIL $name-arm64 (expected $expected x$repeat, got $got)" >&2
            printf '%s\n' "$out" >&2
            exit 1
        fi
        echo "OK $name-arm64 -> $expected x$repeat"
    }
    arm_run hello 42
    arm_run arrays 10
    arm_run structs 34
    arm_run ffi_malloc 42
    arm_run ffi_printf 0
    arm_run ffi_printf_longdouble 42
    arm_run ffi_snprintf 55
    arm_run math 8
    arm_run ffi_float 5 libffi_float_helper-arm64.so
    arm_run ffi_structs 28 libffi_structs_helper-arm64.so
    arm_run ffi_regstruct 102 libffi_regstruct_helper-arm64.so
    arm_run ffi_regstruct_live 10 libffi_regstruct_helper-arm64.so
    arm_run ffi_mixedstruct 11 libffi_mixedstruct_helper-arm64.so
    arm_run ffi_qsort 1
    arm_run ffi_qsort 1 "" 2
    arm_run ffi_callback 256 libffi_callback_helper-arm64.so
    arm_run ffi_callback_big 246 libffi_callback_big_helper-arm64.so
    arm_run ffi_longdouble 60 libffi_longdouble_helper-arm64.so
    arm_run ffi_longdouble_live 15 libffi_longdouble_helper-arm64.so
    arm_run ffi_edges 55 libffi_edges_helper-arm64.so
    arm_run ffi_hfa 120 libffi_hfa_helper-arm64.so
    arm_run ffi_hfa_stack 45 libffi_hfa_stack_helper-arm64.so
    arm_run packed 7 libpacked_helper-arm64.so
fi

echo "cross-target tests passed"
