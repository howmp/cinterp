#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PYTHONPATH="$ROOT/compiler/src"
RUNTIME="$ROOT/runtime/zig-out/bin/cinterp-run"
DIR="${C_TESTSUITE_DIR:-$ROOT/tests/csuite}"
OUT="$ROOT/build/csuite"
mkdir -p "$OUT"

if [[ ! -x "$RUNTIME" ]]; then
    echo "c-testsuite: build the native runtime first (make runtime)" >&2
    exit 2
fi

pass=0
fail=0
skip=0
for source in "$DIR"/*.c; do
    [[ -e "$source" ]] || continue
    name="$(basename "$source" .c)"
    expect="$(sed -n 's@^// expect: *@@p' "$source" | head -n1)"
    if [[ -z "$expect" ]]; then
        echo "SKIP $name (no // expect marker)"
        skip=$((skip + 1))
        continue
    fi
    cib="$OUT/$name.cib"
    if ! python3 -m cinterp compile "$source" -o "$cib" >/dev/null 2>"$OUT/$name.compile.log"; then
        echo "FAIL $name (compile)"
        sed -n '1,5p' "$OUT/$name.compile.log" >&2
        fail=$((fail + 1))
        continue
    fi
    set +e
    output="$("$RUNTIME" "$cib" 2>&1)"
    rc=$?
    set -e
    got="$(printf '%s\n' "$output" | sed -n 's/^result: //p' | tail -n1)"
    if [[ $rc -eq 0 && "$got" == "$expect" ]]; then
        echo "OK $name -> $expect"
        pass=$((pass + 1))
    else
        echo "FAIL $name (rc=$rc got=${got:-none}, want $expect)"
        printf '%s\n' "$output" | tail -n5 >&2
        fail=$((fail + 1))
    fi
done

echo "c-testsuite subset: $pass passed, $fail failed, $skip skipped"
[[ $fail -eq 0 ]]
