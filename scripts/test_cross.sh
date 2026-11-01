#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PYTHONPATH="$ROOT/compiler/src"

TARGETS="${CROSS_TARGETS:-win64,win32,arm64}"
HOST="${HOST:-}"
REMOTE="${REMOTE:-}"
QEMU="${QEMU:-qemu-aarch64}"
SYSROOT="${SYSROOT:-/usr/aarch64-linux-gnu}"
PYTHON="${PYTHON:-python3}"
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

compile() {
    local target="$1" name="$2"
    "$PYTHON" -m cinterp compile "examples/$name.c" --target "$target" -o "$OUT/$name-$target.cib" >/dev/null
}

win_run() {
    local exe="$1" package="$2" lib="${3:-}" expected="$4" out
    if [ -n "$HOST" ]; then
        [ -n "$REMOTE" ] || { echo "REMOTE must be set with HOST" >&2; exit 2; }
        local prefix="C:\\Users\\admin\\AppData\\Local\\Temp\\cinterp_test"
        local cmd="$prefix\\$exe"
        if [[ -n "$lib" ]]; then cmd="$cmd --lib $prefix\\$lib"; fi
        cmd="$cmd $prefix\\$package"
        out="$(ssh "$HOST" "cmd /c \"$cmd\"" 2>&1)"
    elif is_windows_shell; then
        if [[ -n "$lib" ]]; then
            out="$(cd "$OUT" && "./$exe" --lib "$lib" "$package" 2>&1)"
        else
            out="$(cd "$OUT" && "./$exe" "$package" 2>&1)"
        fi
    else
        local runner
        runner="$(win_runner "$exe")"
        local first="${runner%% *}"
        if ! have "$first"; then
            echo "missing Windows runner '$first'; install wine or set WIN64_RUNNER/WIN32_RUNNER or HOST" >&2
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
                wineboot -u >/dev/null 2>&1 || true
        fi
        if [[ -n "$lib" ]]; then
            out="$(cd "$OUT" && WINEARCH="$wine_arch" WINEPREFIX="$wine_prefix" \
                WINEDEBUG=-all "$runner" "$exe" --lib "$lib" "$package" 2>&1)"
        else
            out="$(cd "$OUT" && WINEARCH="$wine_arch" WINEPREFIX="$wine_prefix" \
                WINEDEBUG=-all "$runner" "$exe" "$package" 2>&1)"
        fi
    fi
    if ! printf '%s\n' "$out" | grep -Fq "result: $expected"; then
        echo "FAIL $package (expected $expected)" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    echo "OK $package -> $expected"
}

USUAL=(hello arrays structs ffi_malloc ffi_printf ffi_snprintf math ffi_float ffi_structs ffi_regstruct ffi_mixedstruct ffi_qsort ffi_callback ffi_callback_big ffi_longdouble ffi_edges ffi_hfa ffi_hfa_stack packed)
HELPERS=(ffi_float_helper ffi_structs_helper ffi_regstruct_helper ffi_mixedstruct_helper ffi_callback_helper ffi_callback_big_helper ffi_longdouble_helper ffi_edges_helper ffi_hfa_helper ffi_hfa_stack_helper packed_helper)

if want win64; then
    echo "== Win64"
    (cd runtime && zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall)
    cp runtime/zig-out/bin/cinterp-run.exe "$OUT/cinterp-run64.exe"
    for name in "${USUAL[@]}"; do compile x86_64-windows "$name"; done
    compile x86_64-windows winapi
    for h in "${HELPERS[@]}"; do
        zig cc -target x86_64-windows-gnu -shared -O0 -Wl,--export-all-symbols \
            -o "$OUT/lib${h}64.dll" "examples/$h.c"
    done
    if [ -n "$HOST" ]; then
        ssh "$HOST" 'cmd /c if not exist C:\Users\admin\AppData\Local\Temp\cinterp_test mkdir C:\Users\admin\AppData\Local\Temp\cinterp_test' >/dev/null 2>&1 || true
        scp "$OUT/cinterp-run64.exe" "$OUT"/*-x86_64-windows.cib "$OUT"/lib*64.dll "$HOST:$REMOTE" >/dev/null
    fi
    win_run cinterp-run64.exe hello-x86_64-windows.cib "" 42
    win_run cinterp-run64.exe arrays-x86_64-windows.cib "" 10
    win_run cinterp-run64.exe structs-x86_64-windows.cib "" 34
    win_run cinterp-run64.exe ffi_malloc-x86_64-windows.cib "" 42
    win_run cinterp-run64.exe ffi_printf-x86_64-windows.cib "" 0
    win_run cinterp-run64.exe ffi_snprintf-x86_64-windows.cib "" 55
    win_run cinterp-run64.exe math-x86_64-windows.cib "" 8
    win_run cinterp-run64.exe ffi_float-x86_64-windows.cib libffi_float_helper64.dll 5
    win_run cinterp-run64.exe ffi_structs-x86_64-windows.cib libffi_structs_helper64.dll 28
    win_run cinterp-run64.exe ffi_regstruct-x86_64-windows.cib libffi_regstruct_helper64.dll 102
    win_run cinterp-run64.exe ffi_mixedstruct-x86_64-windows.cib libffi_mixedstruct_helper64.dll 11
    win_run cinterp-run64.exe ffi_qsort-x86_64-windows.cib "" 1
    win_run cinterp-run64.exe ffi_callback-x86_64-windows.cib libffi_callback_helper64.dll 256
    win_run cinterp-run64.exe ffi_callback_big-x86_64-windows.cib libffi_callback_big_helper64.dll 246
    win_run cinterp-run64.exe ffi_longdouble-x86_64-windows.cib libffi_longdouble_helper64.dll 60
    win_run cinterp-run64.exe ffi_edges-x86_64-windows.cib libffi_edges_helper64.dll 55
    win_run cinterp-run64.exe ffi_hfa-x86_64-windows.cib libffi_hfa_helper64.dll 120
    win_run cinterp-run64.exe ffi_hfa_stack-x86_64-windows.cib libffi_hfa_stack_helper64.dll 45
    win_run cinterp-run64.exe packed-x86_64-windows.cib libpacked_helper64.dll 7
    win_run cinterp-run64.exe winapi-x86_64-windows.cib "" 7
fi

if want win32; then
    echo "== Win32"
    (cd runtime && zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall)
    cp runtime/zig-out/bin/cinterp-run.exe "$OUT/cinterp-run32.exe"
    for name in "${USUAL[@]}"; do compile i686-windows "$name"; done
    compile i686-windows winapi
    for h in "${HELPERS[@]}"; do
        zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols \
            -o "$OUT/lib${h}32.dll" "examples/$h.c"
    done
    "$PYTHON" -m cinterp compile examples/ffi_stdcall.c --target i686-windows -o "$OUT/ffi_stdcall-i686-windows.cib" >/dev/null
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols -o "$OUT/libffi_stdcall_helper32.dll" examples/ffi_stdcall_helper.c
    zig cc -target x86-windows-gnu -shared -O0 -Wl,--export-all-symbols -o "$OUT/libffi_fastcall_helper32.dll" examples/ffi_fastcall_helper.c
    "$PYTHON" -m cinterp compile examples/ffi_fastcall.c --target i686-windows -o "$OUT/ffi_fastcall-i686-windows.cib" >/dev/null
    if [ -n "$HOST" ]; then
        scp "$OUT/cinterp-run32.exe" "$OUT"/*-i686-windows.cib "$OUT"/lib*32.dll "$HOST:$REMOTE" >/dev/null
    fi
    win_run cinterp-run32.exe hello-i686-windows.cib "" 42
    win_run cinterp-run32.exe arrays-i686-windows.cib "" 10
    win_run cinterp-run32.exe structs-i686-windows.cib "" 34
    win_run cinterp-run32.exe ffi_malloc-i686-windows.cib "" 42
    win_run cinterp-run32.exe ffi_printf-i686-windows.cib "" 0
    win_run cinterp-run32.exe ffi_snprintf-i686-windows.cib "" 55
    win_run cinterp-run32.exe math-i686-windows.cib "" 8
    win_run cinterp-run32.exe ffi_float-i686-windows.cib libffi_float_helper32.dll 5
    win_run cinterp-run32.exe ffi_structs-i686-windows.cib libffi_structs_helper32.dll 28
    win_run cinterp-run32.exe ffi_regstruct-i686-windows.cib libffi_regstruct_helper32.dll 102
    win_run cinterp-run32.exe ffi_mixedstruct-i686-windows.cib libffi_mixedstruct_helper32.dll 11
    win_run cinterp-run32.exe ffi_qsort-i686-windows.cib "" 1
    win_run cinterp-run32.exe ffi_callback-i686-windows.cib libffi_callback_helper32.dll 256
    win_run cinterp-run32.exe ffi_callback_big-i686-windows.cib libffi_callback_big_helper32.dll 246
    win_run cinterp-run32.exe ffi_longdouble-i686-windows.cib libffi_longdouble_helper32.dll 60
    win_run cinterp-run32.exe ffi_edges-i686-windows.cib libffi_edges_helper32.dll 55
    win_run cinterp-run32.exe ffi_hfa-i686-windows.cib libffi_hfa_helper32.dll 120
    win_run cinterp-run32.exe ffi_hfa_stack-i686-windows.cib libffi_hfa_stack_helper32.dll 45
    win_run cinterp-run32.exe packed-i686-windows.cib libpacked_helper32.dll 7
    win_run cinterp-run32.exe ffi_stdcall-i686-windows.cib libffi_stdcall_helper32.dll 60
    win_run cinterp-run32.exe ffi_fastcall-i686-windows.cib libffi_fastcall_helper32.dll 123
    win_run cinterp-run32.exe winapi-i686-windows.cib "" 7
fi

if want arm64; then
    echo "== ARM64"
    (cd runtime && zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall)
    cp runtime/zig-out/bin/cinterp-run "$OUT/cinterp-run-arm64"
    for name in "${USUAL[@]}"; do compile aarch64-linux "$name"; done
    for h in "${HELPERS[@]}"; do
        aarch64-linux-gnu-gcc -shared -fPIC -O0 -o "$OUT/lib${h}-arm64.so" "examples/$h.c"
    done
    arm_run() {
        local name="$1" expected="$2" lib="${3:-}"
        local out
        if [[ -n "$lib" ]]; then
            out="$("$QEMU" -L "$SYSROOT" "$OUT/cinterp-run-arm64" --lib "$OUT/$lib" "$OUT/$name-aarch64-linux.cib" 2>&1)"
        else
            out="$("$QEMU" -L "$SYSROOT" "$OUT/cinterp-run-arm64" "$OUT/$name-aarch64-linux.cib" 2>&1)"
        fi
        if ! printf '%s\n' "$out" | grep -Fq "result: $expected"; then
            echo "FAIL $name-arm64 (expected $expected)" >&2
            printf '%s\n' "$out" >&2
            exit 1
        fi
        echo "OK $name-arm64 -> $expected"
    }
    arm_run hello 42
    arm_run arrays 10
    arm_run structs 34
    arm_run ffi_malloc 42
    arm_run ffi_printf 0
    arm_run ffi_snprintf 55
    arm_run math 8
    arm_run ffi_float 5 libffi_float_helper-arm64.so
    arm_run ffi_structs 28 libffi_structs_helper-arm64.so
    arm_run ffi_regstruct 102 libffi_regstruct_helper-arm64.so
    arm_run ffi_mixedstruct 11 libffi_mixedstruct_helper-arm64.so
    arm_run ffi_qsort 1
    arm_run ffi_callback 256 libffi_callback_helper-arm64.so
    arm_run ffi_callback_big 246 libffi_callback_big_helper-arm64.so
    arm_run ffi_longdouble 60 libffi_longdouble_helper-arm64.so
    arm_run ffi_edges 55 libffi_edges_helper-arm64.so
    arm_run ffi_hfa 120 libffi_hfa_helper-arm64.so
    arm_run ffi_hfa_stack 45 libffi_hfa_stack_helper-arm64.so
    arm_run packed 7 libpacked_helper-arm64.so
fi

echo "cross-target tests passed"
