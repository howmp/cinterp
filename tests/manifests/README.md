# Test suite manifests

Each `*.json` file describes one upstream or local C suite. The runner is
`scripts/test_suites.py`; sources are fetched into `build/suites/` by
`scripts/fetch_suites.py` and are not vendored.

## Manifest fields

| field | meaning |
| --- | --- |
| `suite` | stable suite id |
| `root` | suite root; `{SUITES}` expands to `build/suites` (or `CINTERP_SUITE_ROOT`) |
| `source_glob` | files relative to `root` when `cases` is omitted |
| `cases` | explicit case list (`id`, `source`, optional expected fields) |
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
| `support_lib` | shared library passed as `--lib` (chibicc/libc harness) |
| `rewrite` | literal source rewrites for harness-only shims (must be explicit) |
| `tiers` | `smoke`, `standard`, `full`, `nightly` |
| `repo_skip_file` | checked-in `ID<TAB>reason` skip list |
| `skip` | inline `id: reason` map |

## Commands

```bash
python3 scripts/fetch_suites.py --all --support
make test-suites-smoke      # csuite + critical metadata
make test-suites            # csuite, c-testsuite, TCC, chibicc, libc-test
make test-suites-full       # adds GCC torture, CompCert, LLVM UnitTests
make test-suites-nightly    # all fixed suites
make test-suites-cross      # csuite + upstream smoke on Win64/Win32/ARM64
make generate-diff          # YARPGen differential smoke
```

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

## Current native baseline (2026-10-31)

TCC reference outputs are normalized for absolute `__FILE__` paths, trailing whitespace, and TCC compiler warnings; this recovered 4 cases without weakening semantic comparisons.

| suite | passed | skipped |
| --- | ---: | ---: |
| csuite | 17 | 0 |
| c-testsuite | 218 | 2 |
| tcc-tests2 | 97 | 45 |
| chibicc | 15 | 26 |
| libc-test | 49 | 26 |
| gcc-torture | 1194 | 52 |
| gcc-torture-compile | 1407 | 0 |
| compcert | 55 | 20 |
| llvm-singlesource | 85 | 8 |
| gcc-ieee | 59 | 20 |
| compcert-c | 12 | 12 |
| compcert-compile | 30 | 4 |
| llvm-regression-c | 935 | 0 |
| libc-test-regression | 48 | 21 |
| c-testsuite-smoke | 12 | 0 |
| tcc-smoke / gcc-smoke / compcert-smoke | 12 each | 0 |
| **total** | **4221** | **236** |

`make test-suites-full` is the command that produced this table; generated
YARPGen/Csmith known-failure seeds are recorded separately in
`tests/generator-known-failures.json`.

`gcc-torture.excluded` and `gcc-torture-compile.excluded` contain 1098 compile/runtime cases that depend on explicit non-goals (varargs/builtins/asm/vectors/etc). They are separate from the supported subset and not counted as passes or skips.
