.PHONY: all test compiler runtime debug-runtime compiler-test integration lint size release-check cross-test c-testsuite fuzz fuzz-exec fuzz-exec-strict fuzz-ffi-exec fuzz-bytecode fuzz-cross fuzz-capi-asan fuzz-sanitizer differential bench size-cross clean test-suites-smoke test-suites test-suites-full test-suites-nightly test-suites-report test-suites-cross test-winapi fetch-suites generate-diff

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
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier smoke --cib-cache build/cib-cache-zig-ast --report build/test-suites-smoke.json

test-suites: compiler runtime
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier standard --cib-cache build/cib-cache-zig-ast --report build/test-suites.json

test-suites-full: compiler runtime
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier full --cib-cache build/cib-cache-zig-ast --report build/test-suites-full.json

test-suites-nightly: compiler runtime
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --tier nightly --cib-cache build/cib-cache-zig-ast --report build/test-suites-nightly.json
	python3 scripts/generate_diff.py --generator yarpgen --iterations 100 --report build/generate-diff-nightly.json --minimize

test-suites-report: test-suites-full
	@test -s build/test-suites-full.json

test-suites-cross: compiler runtime
	cd runtime && zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe build/cross/cinterp-run64.exe
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite csuite --target x86_64-windows --jobs 4 --report build/test-suites-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite c-testsuite-smoke --target x86_64-windows --jobs 4 --report build/test-suites-cross-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite tcc-smoke --target x86_64-windows --jobs 4 --report build/test-suites-tcc-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite gcc-smoke --target x86_64-windows --jobs 4 --report build/test-suites-gcc-win64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite compcert-smoke --target x86_64-windows --jobs 4 --report build/test-suites-compcert-win64.json
	cd runtime && zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe build/cross/cinterp-run32.exe
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite csuite --target i686-windows --jobs 4 --report build/test-suites-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite c-testsuite-smoke --target i686-windows --jobs 4 --report build/test-suites-cross-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite tcc-smoke --target i686-windows --jobs 4 --report build/test-suites-tcc-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite gcc-smoke --target i686-windows --jobs 4 --report build/test-suites-gcc-win32.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite compcert-smoke --target i686-windows --jobs 4 --report build/test-suites-compcert-win32.json
	cd runtime && zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run build/cross/cinterp-run-arm64
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite csuite --target aarch64-linux --jobs 4 --report build/test-suites-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite c-testsuite-smoke --target aarch64-linux --jobs 4 --report build/test-suites-cross-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite tcc-smoke --target aarch64-linux --jobs 4 --report build/test-suites-tcc-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite gcc-smoke --target aarch64-linux --jobs 4 --report build/test-suites-gcc-arm64.json
	python3 scripts/test_suites.py --compiler-path build/cinterp-cc --suite compcert-smoke --target aarch64-linux --jobs 4 --report build/test-suites-compcert-arm64.json
	cd runtime && zig build -Doptimize=ReleaseSmall

generate-diff: compiler runtime
	python3 scripts/generate_diff.py --generator yarpgen --iterations 20 --report build/generate-diff-report.json

generate-diff-nightly: compiler runtime
	python3 scripts/generate_diff.py --generator yarpgen --iterations 100 --report build/generate-diff-nightly.json --minimize

generate-diff-csmith: compiler runtime
	python3 scripts/generate_diff.py --generator csmith --iterations 3 --report build/generate-diff-csmith.json

fuzz: compiler runtime
	python3 scripts/fuzz.py --iterations 1000

fuzz-exec: compiler runtime
	python3 scripts/fuzz_exec.py --iterations 500 --tolerate-faults

fuzz-exec-strict: compiler runtime
	python3 scripts/fuzz_exec.py --iterations 500

fuzz-ffi-exec: compiler runtime
	python3 scripts/fuzz_exec.py --iterations 300 --ffi --tolerate-faults

fuzz-bytecode: compiler runtime
	python3 scripts/fuzz_bytecode.py --iterations 500

fuzz-cross: compiler runtime
	python3 scripts/fuzz_cross.py --iterations 100

fuzz-capi-asan: compiler runtime
	python3 scripts/fuzz_capi_sanitizer.py --iterations 200

fuzz-sanitizer: compiler
	mkdir -p build/fuzz-sanitizer
	cd runtime && zig build -Doptimize=ReleaseSafe
	cp runtime/zig-out/bin/cinterp-run build/fuzz-sanitizer/cinterp-run
	python3 scripts/fuzz.py --iterations 500 --runtime build/fuzz-sanitizer/cinterp-run
	python3 scripts/fuzz_exec.py --iterations 200 --tolerate-faults --runtime build/fuzz-sanitizer/cinterp-run
	python3 scripts/fuzz_bytecode.py --iterations 300 --runtime build/fuzz-sanitizer/cinterp-run

differential: compiler runtime
	./scripts/differential.sh

bench: compiler runtime
	python3 scripts/benchmark.py

release-artifacts:
	./scripts/package_release.sh

size-cross:
	./scripts/size_cross.sh

clean:
	rm -rf build
	cd compiler && rm -rf .zig-cache zig-out
	cd runtime && rm -rf .zig-cache zig-out
