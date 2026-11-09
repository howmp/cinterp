# Scripts

Repository automation is grouped by responsibility:

| Directory | Contents |
| --- | --- |
| `tools/` | Developer utilities: `cib_dump.py`, `civm_lint.py`, `check_version.py`, `check_plan_evidence.py`, `gen_sbom.py`, `benchmark.py` |
| `test/` | Test entry points and suite infrastructure: `test.sh`, `test_cross.sh`, `test_winapi.py`, `test_suites.py`, `test_nightly.sh`, `c_testsuite.sh`, `c_testsuite_upstream.py`, `fetch_suites.py` |
| `fuzz/` | Fuzzing and differential tooling: `fuzz*.py`, `generate_diff.py`, `minimize_failure.py`, `differential.sh` |
| `release/` | Packaging and binary post-processing: `package_release.sh`, `size_cross.sh`, `strip_elf.sh`, `strip_runtime.sh` |

All scripts resolve the repository root from their own location, so they can be
invoked from any working directory. The Makefile and CI workflows use the paths
above; run `make help`-style entry points from the repository root.
