# Test suite manifests

Each `*.json` file describes one upstream or local C suite. The runner is
`scripts/test_suites.py`; sources are fetched into `build/suites/` by
`scripts/fetch_suites.py` and are not vendored.

## Manifest fields

| field | meaning |
| --- | --- |
| `suite` | stable suite id |
| `description`, `upstream`, `commit`, `license` | provenance metadata, not read by the runner |
| `root` | suite root; `{SUITES}` expands to `build/suites` (or `CINTERP_SUITE_ROOT`) |
| `source_glob` | files relative to `root` when `cases` is omitted |
| `cases` | explicit case list (`id`, `source`, optional expected fields) |
| `mode` | `compile` = compile-only suite: the package is built and validated but never executed (`gcc-torture-compile`, `compcert-compile`, `llvm-regression-c`, `llvm-singlesource`) |
| `expected_ext` / `expected_dir` | expected stdout location; default `.expected` next to source |
| `expected_required` | skip cases without a reference output (used by CompCert) |
| `compare_stdout` | set false for suites whose test harness prints assertion chatter |
| `normalize_source_paths` | replace absolute `__FILE__` paths with basenames before comparing |
| `normalize_trailing_whitespace` | compare semantic lines ignoring trailing spaces |
| `strip_compiler_diagnostics` | drop upstream compiler warning lines (TCC-specific expectations) |
| `expect_marker` | read `// expect: N` from the source and compare the VM result |
| `expected_exit` | expected process exit; `null` disables the check |
| `prelude` | optional file prepended to a generated wrapper |
| `cpath` | directories added to `CPATH` during compilation |
| `case_args` | per-case extra host argv (`id` → list) |
| `support_lib` | shared library passed as `--lib` (chibicc/libc harness) |
| `rewrite` | literal source rewrites for harness-only shims (must be explicit) |
| `tiers` | `smoke`, `standard`, `full`, `nightly` |
| `repo_skip_file` | checked-in `ID<TAB>reason` skip list |
| `skip` | inline `id: reason` map |
| `skip_by_target` | per-case `target: reason` map for cross-ABI suites |
| `repo_exclude_file` | checked-in `ID<TAB>reason` exclusion list (not run at all) |
| `timeout`, `compile_timeout` | per-case wall-clock limits (seconds) |

## Commands

```bash
python3 scripts/fetch_suites.py --all --support
make test-suites-smoke      # smoke tier: csuite only (17 cases)
make test-suites            # standard: csuite, c-testsuite, TCC, chibicc, libc-test
make test-suites-full       # adds gcc-torture(+compile), gcc-ieee, CompCert(+c/compile),
                            # LLVM UnitTests/regression-c, libc-test-regression
make test-suites-nightly    # all fixed suites (full + the four cross-target smoke suites)
                            # plus scripts/generate_diff.py (YARPGen, 100 iterations)
make test-suites-cross      # csuite + the four smoke suites on Win64/Win32/ARM64 (145 cases each)
make generate-diff          # YARPGen differential smoke
```

Tier membership is taken from each manifest's `tiers` list:

| tier | suites |
| --- | --- |
| `smoke` | csuite |
| `standard` | csuite, c-testsuite, tcc-tests2, chibicc, libc-test |
| `full` | standard + gcc-torture, gcc-torture-compile, gcc-ieee, compcert, compcert-c, compcert-compile, llvm-singlesource, llvm-regression-c, libc-test-regression |
| `nightly` | full + c-testsuite-smoke, tcc-smoke, gcc-smoke, compcert-smoke |

Re-triage excluded candidates without editing baselines:

```bash
python3 scripts/test_suites.py --suite gcc-torture --include-excluded \
  --include-skipped --only va-arg-1,stdarg-1 \
  --emit-reasons build/triage-varargs.txt --report build/triage-varargs.json

# faster local reruns (content-addressed CIB cache)
python3 scripts/test_suites.py --tier full --jobs 8 --cib-cache build/cib-cache
```

`--include-excluded` bypasses `.excluded`, `--only` accepts comma-separated
IDs, and `--emit-reasons` writes auditable `ID<TAB>status: reason` lines. Only
delete verified passing IDs from the checked-in lists; expected outputs and
comparison flags must remain unchanged.

## Skip policy

- Every non-`ok` entry in a generated `.skip` file was observed once and has a
  reason. It is a known-support-subset skip, not a silent pass.
- `compile:` is an unsupported compiler feature or an upstream test requiring
  GNU/extensions; `runtime:` is a known runtime/ABI failure; `mismatch:` is a
  known output difference; `timeout:` is a resource/time limit.
- Replacing a skip with a fix requires re-running the suite and removing the
  entry from the skip file. CI never updates expected outputs or skip files.
- Expected outputs are never auto-updated in CI; `--update-baseline` is not
  implemented for these manifests by design.
- `.excluded` files are stricter than `.skip`: excluded IDs are removed before
  the run and appear in no report at all, so they are neither passes nor skips.
  Re-check them with `--include-excluded`.

### Skip / exclude inventory (2026-11-03)

- 11 manifests reference a `repo_skip_file`. Together those files hold **201**
  non-comment `ID<TAB>reason` lines; `llvm-regression-c.json` adds one inline
  skip, for **202** skips in `build/test-suites-full.json`.
- `tests/manifests/gcc-torture-compile.skip` has three entries for
  compile-only stress cases whose package would exceed a runtime cap
  (`limits-externdecl` >512 imports, `pr37669-2` >64 arguments, `stuct` >2 MiB
  module). `llvm-regression-c.json` inline-skips `pr60822` for the same reason.
- `tests/manifests/c-testsuite.skip` is **orphaned**: no manifest references it
  (`c-testsuite.json` keeps its two skips inline) and the standalone runner uses
  `tests/csuite/cinterp.skip`, not this file. See the c-testsuite section below.
- 4 exclusions files hold **1034** non-comment lines:
  `gcc-torture.excluded` 394, `gcc-torture-compile.excluded` 605,
  `compcert.excluded` 34, `tcc-tests2.excluded` 1.

## Manifest hygiene: duplicate IDs

Duplicate case IDs silently double-run a case and corrupt the report, so
`scripts/test_suites.py` now rejects them outright
(`reject_duplicate_ids`): a manifest with a repeated ID fails the run with the
duplicated ID list. `--allow-duplicate-ids` downgrades this to a warning and
keeps the first occurrence, for local triage of an unedited manifest only.

`llvm-regression-c.json` contains the LLVM `SingleSource/.../builtins/lib/*.c`
support files next to the cases that `#include` them. Those support files had
IDs that collided with real test cases, so they were renamed with a
`*-support` suffix (20 entries such as `memchr-support`). The manifest now holds
**935 unique case IDs**, matching the `llvm-regression-c` row of the baseline
below.

## Current native baseline (2026-11-03)

`make test-suites-full` on `x86_64-linux`; the numbers are read directly from
`build/test-suites-full.json` (`tier=full`, `counts = {ok: 4319, skip: 202}`,
4521 results). TCC reference outputs are normalized for absolute `__FILE__`
paths, trailing whitespace, and TCC compiler warnings; this recovered 4 cases
without weakening semantic comparisons.

| suite | cases | passed | skipped | notes |
| --- | ---: | ---: | ---: | --- |
| csuite | 17 | 17 | 0 | local subset, `// expect:` marker |
| c-testsuite | 220 | 218 | 2 | inline skips (`00204`, `00216`) |
| tcc-tests2 | 142 | 99 | 43 | |
| chibicc | 41 | 15 | 26 | |
| libc-test | 75 | 47 | 28 | |
| libc-test-regression | 69 | 48 | 21 | |
| gcc-torture | 1306 | 1287 | 19 | execute cases |
| gcc-torture-compile | 1411 | 1408 | 3 | compile-only (`mode: compile`); 3 runtime-cap skips |
| gcc-ieee | 79 | 64 | 15 | |
| compcert | 75 | 55 | 20 | |
| compcert-c | 24 | 12 | 12 | |
| compcert-compile | 34 | 30 | 4 | compile-only (`mode: compile`) |
| llvm-singlesource | 93 | 85 | 8 | compile-only (`mode: compile`) |
| llvm-regression-c | 935 | 934 | 1 | compile-only (`mode: compile`), deduplicated IDs; 1 runtime-cap skip |
| **total** | **4521** | **4319** | **202** | |

### Compile-only share

Cases whose suite sets `"mode": "compile"` are built and validated but never
executed, so they do not prove program behaviour:

| suite | passed |
| --- | ---: |
| gcc-torture-compile | 1408 |
| llvm-regression-c | 934 |
| compcert-compile | 30 |
| **subtotal quoted as compile-only** | **2372** |
| llvm-singlesource (also `mode: compile`) | 85 |
| **all compile-mode passes** | **2457** |

The remaining 4319 − 2457 = **1862** passes are executable cases whose stdout /
exit status / `// expect:` result is compared against the reference.

### Nightly/cross smoke suites (not part of the 4319)

The four smoke suites are `nightly`-tier only; they are exercised per target by
`make test-suites-cross` and the `cross-abi` workflow, and their results land in
`build/test-suites-cross-*.json`, not in `test-suites-full.json`:

| suite | cases | target-specific skips (`skip_by_target`) |
| --- | ---: | --- |
| c-testsuite-smoke | 40 | `aarch64-linux`: `00040` (qemu timeout) → 39 + 1 |
| tcc-smoke | 24 | `x86_64-windows`, `i686-windows`: `22_floating_point` → 23 + 1 |
| gcc-smoke | 40 | none |
| compcert-smoke | 24 | `x86_64-windows`, `i686-windows`: `binops` → 23 + 1 |

`make test-suites-smoke` (smoke tier) only runs `csuite` (17/17 on the host).
Generated YARPGen/Csmith known-failure seeds are recorded separately in
`tests/generator-known-failures.json`. The YARPGen whitelist is currently
empty; generated programs that exceed a documented runtime cap are reported as
`cinterp engine limit:` skips, and a whitelisted seed that starts passing makes
`scripts/generate_diff.py` fail as stale. The Csmith map still has three
entries.

## Upstream c-testsuite: two different numbers

`c-testsuite.json` globs 220 single-exec sources and skips two inline
(`00204` vector types, `00216` complex aggregate global initializers), so the
manifest run is **218 passed / 2 skipped**, as in the baseline table.

The standalone `scripts/c_testsuite_upstream.py` still defaults to the older
`tests/csuite/cinterp.skip` list, which additionally lists `00189` (requires
external data symbols). Its default run is therefore **217 passed / 3 skipped**
out of the same 220. The two skip lists are not unified: quote **218/2** for
manifest runs and **217/3** only for the standalone script. Do not average them
or claim a single figure.
