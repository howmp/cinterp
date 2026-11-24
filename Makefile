.PHONY: all help test compiler runtime debug-runtime cross-runtimes-win compiler-test integration lint size keygenme release-check cross-test c-testsuite fuzz fuzz-exec fuzz-ffi-exec fuzz-bytecode fuzz-cross fuzz-capi-asan fuzz-sanitizer differential bench bench-long size-cross clean distclean test-suites-smoke test-suites test-suites-full test-suites-opt test-suites-nightly test-suites-nightly-serial test-suites-report test-suites-cross test-winapi fetch-suites generate-diff generate-diff-nightly generate-diff-csmith release-artifacts evidence check-version

PYTHON ?= python3
BUILD := build
COMPILER := build/cinterp-cc
RUNTIME := runtime/zig-out/bin/cinterp-run
SUITE_RUNNER := scripts/test/test_suites.py
SUITE_CACHE := $(BUILD)/cib-cache-zig-ast
SUITE_CC_OPT ?= 2
SUITE_JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
SUITE_RUN = $(PYTHON) $(SUITE_RUNNER) --compiler-path $(COMPILER) --jobs $(SUITE_JOBS) --cib-cache $(SUITE_CACHE) --cc-opt $(SUITE_CC_OPT)
CROSS_SUITE_JOBS ?= 4
CROSS_RUN = $(PYTHON) $(SUITE_RUNNER) --compiler-path $(COMPILER) --jobs $(CROSS_SUITE_JOBS) --cc-opt $(SUITE_CC_OPT)

# Fuzz seeds: CI runs the fuzz targets once per seed (1 and 2).
FUZZ_SEED ?= 1

# Test-suite concurrency. The runner defaults to CPU count anyway; these make
# the choice explicit and let CI or a loaded workstation cap it.
GEN_JOBS ?= 2
MINIMIZE_JOBS ?= 2
NIGHTLY_MINIMIZE ?= 1
# ReleaseSmall runtime budget. Override for a one-off measurement with
# `make size SIZE_BUDGET=...` or `make size-cross SIZE_BUDGET=...`.
SIZE_BUDGET ?= 135168
CIB_BUDGET ?= 4096
# Cross-suite targets: the default keeps the full matrix; Wine CI selects
# win64,win32 to avoid needing the ARM64 toolchain/qemu in that job.
CROSS_SUITE_TARGETS ?= win64,win32,arm64

all: test

help:
	@printf '%s\n' \
		'all                 run test (default)' \
		'compiler            build compiler into $(COMPILER)' \
		'runtime             build stripped native ReleaseSmall runtime' \
		'test                runtime + compiler tests and examples' \
		'lint                structural CIB lint' \
		'size / size-cross   runtime and CIB size budgets' \
		'keygenme            embedded keygenme binaries for four targets' \
		'cross-test          Win64/Win32/ARM64 example runs' \
		'test-suites-full    full pinned upstream suite' \
		'test-suites-opt     csuite + c-testsuite at the default --cc-opt 2' \
		'bench               benchmark and build/benchmark.json' \
		'bench-long          long-running benchmarks and build/bench-long.json' \
		'release-artifacts   release tarballs + SBOM + SHA256SUMS' \
		'clean / distclean   remove outputs (clean preserves suite cache)'

compiler:
	cd compiler && zig build
	mkdir -p $(BUILD)
	cp compiler/zig-out/bin/cinterp-cc $(COMPILER)

runtime:
	cd runtime && zig build -Doptimize=ReleaseSmall
	./scripts/release/strip_elf.sh

debug-runtime:
	cd runtime && zig build -Doptimize=Debug

cross-runtimes-win: compiler
	mkdir -p $(BUILD)/cross
	cd runtime && zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe $(BUILD)/cross/cinterp-run64.exe
	cd runtime && zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe $(BUILD)/cross/cinterp-run32.exe
	cd runtime && zig build -Doptimize=ReleaseSmall

compiler-test:
	cd compiler && zig build test

integration: test

lint: compiler
	$(COMPILER) compile examples/basics/hello.c -o $(BUILD)/lint-hello.cib
	$(COMPILER) compile examples/ffi/ffi_qsort.c -o $(BUILD)/lint-qsort.cib
	$(COMPILER) compile examples/ffi/ffi_callback.c -o $(BUILD)/lint-callback.cib
	$(PYTHON) scripts/tools/civm_lint.py $(BUILD)/lint-hello.cib $(BUILD)/lint-qsort.cib $(BUILD)/lint-callback.cib

# Needs Wine; the cross-runtimes-win prerequisite supplies build/cross/.
# Without Wine the script fails (2) instead of silently skipping; use
# `python3 scripts/test/test_winapi.py --allow-skip` for a local no-op run.
test-winapi: compiler cross-runtimes-win
	$(PYTHON) scripts/test/test_winapi.py

test: compiler
	./scripts/test/test.sh

size: compiler runtime
	mkdir -p $(BUILD)
	$(COMPILER) compile examples/basics/hello.c -o $(BUILD)/hello.cib >/dev/null
	$(COMPILER) compile examples/ffi/ffi_qsort.c -o $(BUILD)/ffi_qsort.cib >/dev/null
	@printf 'runtime ReleaseSmall: %s bytes\n' "$$(stat -c%s $(RUNTIME))"
	@printf 'hello.cib: %s bytes\n' "$$(stat -c%s $(BUILD)/hello.cib)"
	@printf 'ffi_qsort.cib: %s bytes\n' "$$(stat -c%s $(BUILD)/ffi_qsort.cib)"
	@test "$$(stat -c%s $(RUNTIME))" -lt $(SIZE_BUDGET)
	@test "$$(stat -c%s $(BUILD)/hello.cib)" -lt $(CIB_BUDGET)
	@test "$$(stat -c%s $(BUILD)/ffi_qsort.cib)" -lt $(CIB_BUDGET)

release-check: test size

keygenme: compiler
	PYTHON='$(PYTHON)' ./examples/keygenme/build.sh

cross-test: compiler
	./scripts/test/test_cross.sh

c-testsuite: compiler runtime
	./scripts/test/c_testsuite.sh

fetch-suites:
	$(PYTHON) scripts/test/fetch_suites.py --all --support

test-suites-smoke: compiler runtime
	$(SUITE_RUN) --tier smoke --report $(BUILD)/test-suites-smoke.json

test-suites: compiler runtime
	$(SUITE_RUN) --tier standard --report $(BUILD)/test-suites.json

test-suites-full: compiler runtime
	$(SUITE_RUN) --tier full --report $(BUILD)/test-suites-full.json

# Fast default-optimization smoke (--cc-opt 2): csuite + c-testsuite.
# Use --cc-opt 0 to run the legacy -O0 contract.
test-suites-opt: compiler runtime
	$(PYTHON) $(SUITE_RUNNER) --compiler-path $(COMPILER) --jobs $(SUITE_JOBS) \
		--cib-cache $(SUITE_CACHE) --cc-opt 2 \
		--suite csuite --suite c-testsuite --report $(BUILD)/test-suites-opt.json

# Run the suite and generated-diff phases concurrently. Each phase writes its
# own report/log; the suite pool is global across suites.
test-suites-nightly: compiler runtime
	SUITE_JOBS=$(SUITE_JOBS) GEN_JOBS=$(GEN_JOBS) MINIMIZE_JOBS=$(MINIMIZE_JOBS) \
		NIGHTLY_MINIMIZE=$(NIGHTLY_MINIMIZE) ./scripts/test/test_nightly.sh

# Sequential fallback for debugging or constrained hosts.
test-suites-nightly-serial: compiler runtime
	$(SUITE_RUN) --tier nightly --report $(BUILD)/test-suites-nightly.json
	$(PYTHON) scripts/fuzz/generate_diff.py --generator yarpgen --iterations 100 --jobs $(GEN_JOBS) --minimize --minimize-jobs $(MINIMIZE_JOBS) --report $(BUILD)/generate-diff-nightly.json

test-suites-report: test-suites-full
	@test -s $(BUILD)/test-suites-full.json

test-suites-cross: compiler runtime cross-runtimes-win
	mkdir -p $(BUILD)/cross
ifneq ($(findstring win64,$(CROSS_SUITE_TARGETS)),)
	$(CROSS_RUN) --suite csuite --target x86_64-windows --report $(BUILD)/test-suites-win64.json
	$(CROSS_RUN) --suite c-testsuite-smoke --target x86_64-windows --report $(BUILD)/test-suites-cross-win64.json
	$(CROSS_RUN) --suite tcc-smoke --target x86_64-windows --report $(BUILD)/test-suites-tcc-win64.json
	$(CROSS_RUN) --suite gcc-smoke --target x86_64-windows --report $(BUILD)/test-suites-gcc-win64.json
	$(CROSS_RUN) --suite compcert-smoke --target x86_64-windows --report $(BUILD)/test-suites-compcert-win64.json
endif
ifneq ($(findstring win32,$(CROSS_SUITE_TARGETS)),)
	$(CROSS_RUN) --suite csuite --target i686-windows --report $(BUILD)/test-suites-win32.json
	$(CROSS_RUN) --suite c-testsuite-smoke --target i686-windows --report $(BUILD)/test-suites-cross-win32.json
	$(CROSS_RUN) --suite tcc-smoke --target i686-windows --report $(BUILD)/test-suites-tcc-win32.json
	$(CROSS_RUN) --suite gcc-smoke --target i686-windows --report $(BUILD)/test-suites-gcc-win32.json
	$(CROSS_RUN) --suite compcert-smoke --target i686-windows --report $(BUILD)/test-suites-compcert-win32.json
endif
ifneq ($(findstring arm64,$(CROSS_SUITE_TARGETS)),)
	cd runtime && zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run $(BUILD)/cross/cinterp-run-arm64
	$(CROSS_RUN) --suite csuite --target aarch64-linux --report $(BUILD)/test-suites-arm64.json
	$(CROSS_RUN) --suite c-testsuite-smoke --target aarch64-linux --report $(BUILD)/test-suites-cross-arm64.json
	$(CROSS_RUN) --suite tcc-smoke --target aarch64-linux --report $(BUILD)/test-suites-tcc-arm64.json
	$(CROSS_RUN) --suite gcc-smoke --target aarch64-linux --report $(BUILD)/test-suites-gcc-arm64.json
	$(CROSS_RUN) --suite compcert-smoke --target aarch64-linux --report $(BUILD)/test-suites-compcert-arm64.json
endif
	# Always restore the native runtime, including Windows-only CI runs.
	cd runtime && zig build -Doptimize=ReleaseSmall

generate-diff: compiler runtime
	$(PYTHON) scripts/fuzz/generate_diff.py --generator yarpgen --iterations 20 --jobs $(GEN_JOBS) --report $(BUILD)/generate-diff-report.json

generate-diff-nightly: compiler runtime
	$(PYTHON) scripts/fuzz/generate_diff.py --generator yarpgen --iterations 100 --jobs $(GEN_JOBS) --minimize --minimize-jobs $(MINIMIZE_JOBS) --report $(BUILD)/generate-diff-nightly.json

generate-diff-csmith: compiler runtime
	$(PYTHON) scripts/fuzz/generate_diff.py --generator csmith --iterations 3 --report $(BUILD)/generate-diff-csmith.json

# Fuzzing notes. `fuzz` is load-only: it only checks that the loader rejects
# corrupted packages with CI_* errors, has no tolerance switches, and is the one
# target CI runs as a gate.
#
# Every other target executes mutated bytecode. Such packages are trusted build
# products, so they may legitimately carry arbitrary addresses or loop forever;
# these targets only stay green with --tolerate-faults/--tolerate-timeouts and
# are therefore kept for local investigation rather than CI.
fuzz: compiler runtime
	$(PYTHON) scripts/fuzz/fuzz.py --iterations 1000 --seed $(FUZZ_SEED)

fuzz-exec: compiler runtime
	$(PYTHON) scripts/fuzz/fuzz_exec.py --iterations 500 --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED)

fuzz-ffi-exec: compiler runtime
	$(PYTHON) scripts/fuzz/fuzz_exec.py --iterations 300 --ffi --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED)

fuzz-bytecode: compiler runtime
	$(PYTHON) scripts/fuzz/fuzz_bytecode.py --iterations 500 --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED)

fuzz-cross: compiler runtime
	$(PYTHON) scripts/fuzz/fuzz_cross.py --iterations 100 --tolerate-faults --seed $(FUZZ_SEED)

fuzz-capi-asan: compiler runtime
	$(PYTHON) scripts/fuzz/fuzz_capi_sanitizer.py --iterations 200 --seed $(FUZZ_SEED)

fuzz-sanitizer: compiler
	mkdir -p $(BUILD)/fuzz-sanitizer
	cd runtime && zig build -Doptimize=ReleaseSafe
	cp runtime/zig-out/bin/cinterp-run $(BUILD)/fuzz-sanitizer/cinterp-run
	$(PYTHON) scripts/fuzz/fuzz.py --iterations 500 --seed $(FUZZ_SEED)
	$(PYTHON) scripts/fuzz/fuzz_exec.py --iterations 200 --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED) --runtime $(BUILD)/fuzz-sanitizer/cinterp-run
	$(PYTHON) scripts/fuzz/fuzz_bytecode.py --iterations 300 --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED) --runtime $(BUILD)/fuzz-sanitizer/cinterp-run

differential: compiler runtime
	./scripts/fuzz/differential.sh

bench: compiler runtime
	mkdir -p $(BUILD)
	$(PYTHON) scripts/tools/benchmark.py --json $(BUILD)/benchmark.json

bench-long: compiler runtime
	mkdir -p $(BUILD)
	$(PYTHON) scripts/tools/bench_long.py --json $(BUILD)/bench-long.json

release-artifacts:
	./scripts/release/package_release.sh

size-cross:
	SIZE_BUDGET=$(SIZE_BUDGET) ./scripts/release/size_cross.sh

# Local plan-evidence run: the targets below produce the structured reports
# scripts/tools/check_plan_evidence.py validates. full/cross/nightly reports are
# optional locally (reported as NOT PROVIDED); CI artifacts complete them.
.NOTPARALLEL: evidence
evidence: test lint size test-suites-smoke differential
	$(PYTHON) scripts/tools/check_plan_evidence.py

# Cross-checks VERSION against runtime/build.zig.zon, the Rust crate and SBOM
# metadata (scripts/tools/check_version.py).
check-version:
	$(PYTHON) scripts/tools/check_version.py

clean:
	cd compiler && rm -rf .zig-cache zig-out
	cd runtime && rm -rf .zig-cache zig-out
	@if [ -d $(BUILD) ]; then \
		find $(BUILD) -mindepth 1 -maxdepth 1 \
			! -name suites ! -name cib-cache-zig-ast \
			-exec rm -rf {} +; \
	fi

distclean: clean
	rm -rf $(BUILD)
