#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SUITE_JOBS="${SUITE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
GEN_JOBS="${GEN_JOBS:-2}"
MINIMIZE_JOBS="${MINIMIZE_JOBS:-2}"
NIGHTLY_MINIMIZE="${NIGHTLY_MINIMIZE:-1}"

mkdir -p build
suite_log="build/nightly-suite.log"
diff_log="build/nightly-diff.log"

python3 scripts/test_suites.py \
    --compiler-path build/cinterp-cc \
    --tier nightly \
    --jobs "$SUITE_JOBS" \
    --cib-cache build/cib-cache-zig-ast \
    --report build/test-suites-nightly.json >"$suite_log" 2>&1 &
suite_pid=$!

gen_args=(
    --generator yarpgen
    --iterations 100
    --jobs "$GEN_JOBS"
    --report build/generate-diff-nightly.json
)
if [ "$NIGHTLY_MINIMIZE" != "0" ]; then
    gen_args+=(--minimize --minimize-jobs "$MINIMIZE_JOBS")
fi
python3 scripts/generate_diff.py "${gen_args[@]}" >"$diff_log" 2>&1 &
diff_pid=$!

rc=0
wait "$suite_pid" || rc=1
wait "$diff_pid" || rc=1

echo "== nightly suite (jobs=$SUITE_JOBS)"
tail -n 20 "$suite_log"
echo "== generate-diff (jobs=$GEN_JOBS, minimize=${NIGHTLY_MINIMIZE})"
tail -n 20 "$diff_log"
exit "$rc"
