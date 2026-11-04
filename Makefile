.PHONY: all test compiler runtime debug-runtime compiler-test integration lint size release-check cross-test c-testsuite fuzz fuzz-exec fuzz-ffi-exec fuzz-bytecode fuzz-cross fuzz-capi-asan fuzz-sanitizer differential bench size-cross clean test-suites-smoke test-suites test-suites-full test-suites-nightly test-suites-nightly-serial test-suites-report test-suites-cross test-winapi fetch-suites generate-diff evidence check-version

# Fuzz seeds: CI runs the fuzz targets once per seed (1 and 2).
FUZZ_SEED ?= 1

# Test-suite concurrency. The runner defaults to CPU count anyway; these make
# the choice explicit and let CI or a loaded workstation cap it.
SUITE_JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
GEN_JOBS ?= 2
MINIMIZE_JOBS ?= 2
NIGHTLY_MINIMIZE ?= 1
# Cross-suite targets: the default keeps the full matrix; Wine CI selects
# win64,win32 to avoid needing the ARM64 toolchain/qemu in that job.
CROSS_SUITE_TARGETS ?= win64,win32,arm64

all: test

compiler:
	cd compiler && zig build
	mkdir -p build
	cp compiler/zig-out/bin/cinterp-cc build/cinterp-cc

runtime:
	cd runtime && zig build -Doptimize=ReleaseSmall
	./scripts/strip_elf.sh

debug-runtime:
	cd runtime && zig build -Doptimize=Debug

compiler-test:
	cd compiler && zig build test

integration:
	./scripts/test.sh

lint: compiler runtime
	build/cinterp-cc compile examples/hello.c -o build/lint-hello.cib
	build/cinterp-cc compile examples/ffi_qsort.c -o build/lint-qsort.cib
	build/cinterp-cc compile examples/ffi_callback.c -o build/lint-callback.cib
	python3 scripts/civm_lint.py build/lint-hello.cib build/lint-qsort.cib build/lint-callback.cib

# Needs Wine and the cross-built runtimes in build/cross (see cross-test).
# Without them the script fails (2) instead of silently skipping; use
# `python3 scripts/test_winapi.py --allow-skip` for a local no-op run.
test-winapi: compiler
	python3 scripts/test_winapi.py

test: compiler
	./scripts/test.sh

size: runtime compiler
	mkdir -p build
	@printf 'runtime ReleaseSmall: '; du -h runtime/zig-out/bin/cinterp-run | cut -f1
	@build/cinterp-cc compile examples/hello.c -o build/hello.cib >/dev/null
	@printf 'hello.cib: '; wc -c < build/hello.cib
	@build/cinterp-cc compile examples/ffi_qsort.c -o build/ffi_qsort.cib >/dev/null
	@printf 'ffi_qsort.cib: '; wc -c < build/ffi_qsort.cib
	@test "$$(stat -c%s runtime/zig-out/bin/cinterp-run)" -lt 131072
	@test "$$(stat -c%s build/ffi_qsort.cib)" -lt 4096

release-check: test size

cross-test: compiler
	./scripts/test_cross.sh

c-testsuite: compiler runtime
	./scripts/c_testsuite.sh

fetch-suites:
	python3 scripts/fetch_suites.py --all --support

test-suites-smoke: compiler runtime
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier smoke --jobs $(SUITE_JOBS) --cib-cache build/cib-cache-zig-ast --report build/test-suites-smoke.json

test-suites: compiler runtime
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier standard --jobs $(SUITE_JOBS) --cib-cache build/cib-cache-zig-ast --report build/test-suites.json

test-suites-full: compiler runtime
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier full --jobs $(SUITE_JOBS) --cib-cache build/cib-cache-zig-ast --report build/test-suites-full.json

# Run the suite and generated-diff phases concurrently. Each phase writes its
# own report/log; the suite pool is global across suites.
test-suites-nightly: compiler runtime
	SUITE_JOBS=$(SUITE_JOBS) GEN_JOBS=$(GEN_JOBS) MINIMIZE_JOBS=$(MINIMIZE_JOBS) \
		NIGHTLY_MINIMIZE=$(NIGHTLY_MINIMIZE) ./scripts/test_nightly.sh

# Sequential fallback for debugging or constrained hosts.
test-suites-nightly-serial: compiler runtime
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier nightly --jobs $(SUITE_JOBS) --cib-cache build/cib-cache-zig-ast --report build/test-suites-nightly.json
	python3 scripts/generate_diff.py --generator yarpgen --iterations 100 --jobs $(GEN_JOBS) --minimize --minimize-jobs $(MINIMIZE_JOBS) --report build/generate-diff-nightly.json

test-suites-report: test-suites-full
	@test -s build/test-suites-full.json

test-suites-cross: compiler runtime
	mkdir -p build/cross
ifneq ($(findstring win64,$(CROSS_SUITE_TARGETS)),)
	cd runtime && zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe build/cross/cinterp-run64.exe
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite csuite --target x86_64-windows --jobs 4 --report build/test-suites-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite c-testsuite-smoke --target x86_64-windows --jobs 4 --report build/test-suites-cross-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite tcc-smoke --target x86_64-windows --jobs 4 --report build/test-suites-tcc-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite gcc-smoke --target x86_64-windows --jobs 4 --report build/test-suites-gcc-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite compcert-smoke --target x86_64-windows --jobs 4 --report build/test-suites-compcert-win64.json
endif
ifneq ($(findstring win32,$(CROSS_SUITE_TARGETS)),)
	cd runtime && zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe build/cross/cinterp-run32.exe
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite csuite --target i686-windows --jobs 4 --report build/test-suites-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite c-testsuite-smoke --target i686-windows --jobs 4 --report build/test-suites-cross-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite tcc-smoke --target i686-windows --jobs 4 --report build/test-suites-tcc-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite gcc-smoke --target i686-windows --jobs 4 --report build/test-suites-gcc-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite compcert-smoke --target i686-windows --jobs 4 --report build/test-suites-compcert-win32.json
endif
ifneq ($(findstring arm64,$(CROSS_SUITE_TARGETS)),)
	cd runtime && zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run build/cross/cinterp-run-arm64
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite csuite --target aarch64-linux --jobs 4 --report build/test-suites-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite c-testsuite-smoke --target aarch64-linux --jobs 4 --report build/test-suites-cross-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite tcc-smoke --target aarch64-linux --jobs 4 --report build/test-suites-tcc-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite gcc-smoke --target aarch64-linux --jobs 4 --report build/test-suites-gcc-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite compcert-smoke --target aarch64-linux --jobs 4 --report build/test-suites-compcert-arm64.json
endif
	# Always restore the native runtime, including Windows-only CI runs.
	cd runtime && zig build -Doptimize=ReleaseSmall

generate-diff: compiler runtime
	python3 scripts/generate_diff.py --generator yarpgen --iterations 20 --jobs $(GEN_JOBS) --report build/generate-diff-report.json

generate-diff-nightly: compiler runtime
	python3 scripts/generate_diff.py --generator yarpgen --iterations 100 --jobs $(GEN_JOBS) --minimize --minimize-jobs $(MINIMIZE_JOBS) --report build/generate-diff-nightly.json

generate-diff-csmith: compiler runtime
	python3 scripts/generate_diff.py --generator csmith --iterations 3 --report build/generate-diff-csmith.json

# Fuzzing notes: mutated packages are trusted build products, so corrupted
# bytecode may legitimately segfault under the ReleaseSmall runtime; fuzz-exec
# tolerates those faults but fails on timeouts. A fully strict variant cannot be
# green against ReleaseSmall, so it is intentionally not exposed as a target.
fuzz: compiler runtime
	python3 scripts/fuzz.py --iterations 1000 --seed $(FUZZ_SEED)

fuzz-exec: compiler runtime
	python3 scripts/fuzz_exec.py --iterations 500 --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED)

fuzz-ffi-exec: compiler runtime
	python3 scripts/fuzz_exec.py --iterations 300 --ffi --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED)

fuzz-bytecode: compiler runtime
	python3 scripts/fuzz_bytecode.py --iterations 500 --tolerate-timeouts --seed $(FUZZ_SEED)

fuzz-cross: compiler runtime
	python3 scripts/fuzz_cross.py --iterations 100 --seed $(FUZZ_SEED)

fuzz-capi-asan: compiler runtime
	python3 scripts/fuzz_capi_sanitizer.py --iterations 200 --seed $(FUZZ_SEED)

fuzz-sanitizer: compiler
	mkdir -p build/fuzz-sanitizer
	cd runtime && zig build -Doptimize=ReleaseSafe
	cp runtime/zig-out/bin/cinterp-run build/fuzz-sanitizer/cinterp-run
	python3 scripts/fuzz.py --iterations 500 --seed $(FUZZ_SEED) --runtime build/fuzz-sanitizer/cinterp-run
	python3 scripts/fuzz_exec.py --iterations 200 --tolerate-faults --tolerate-timeouts --seed $(FUZZ_SEED) --runtime build/fuzz-sanitizer/cinterp-run
	python3 scripts/fuzz_bytecode.py --iterations 300 --tolerate-timeouts --seed $(FUZZ_SEED) --runtime build/fuzz-sanitizer/cinterp-run

differential: compiler runtime
	./scripts/differential.sh

bench: compiler runtime
	python3 scripts/benchmark.py

release-artifacts:
	./scripts/package_release.sh

size-cross:
	./scripts/size_cross.sh

# Local plan-evidence run: the targets below produce the structured reports
# scripts/check_plan_evidence.py validates. full/cross/nightly reports are
# optional locally (reported as NOT PROVIDED); CI artifacts complete them.
.NOTPARALLEL: evidence
evidence: test lint size test-suites-smoke differential
	python3 scripts/check_plan_evidence.py

# Cross-checks VERSION against runtime/build.zig.zon, the Rust crate and SBOM
# metadata (scripts/check_version.py).
check-version:
	python3 scripts/check_version.py

clean:
	rm -rf build
	cd compiler && rm -rf .zig-cache zig-out
	cd runtime && rm -rf .zig-cache zig-out
