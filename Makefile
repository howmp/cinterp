.PHONY: all test runtime compiler-test integration size release-check cross-test c-testsuite fuzz fuzz-exec differential bench size-cross clean test-suites-smoke test-suites test-suites-full test-suites-nightly test-suites-report test-suites-cross fetch-suites generate-diff

all: test

runtime:
	cd runtime && zig build -Doptimize=ReleaseSmall

compiler-test:
	PYTHONPATH=compiler/src python3 -m unittest discover -s compiler/tests

integration:
	./scripts/test.sh

test:
	./scripts/test.sh

size: runtime
	mkdir -p build
	@printf 'runtime ReleaseSmall: '; du -h runtime/zig-out/bin/cinterp-run | cut -f1
	@PYTHONPATH=compiler/src python3 -m cinterp compile examples/hello.c -o build/hello.cib >/dev/null
	@printf 'hello.cib: '; wc -c < build/hello.cib
	@PYTHONPATH=compiler/src python3 -m cinterp compile examples/ffi_qsort.c -o build/ffi_qsort.cib >/dev/null
	@printf 'ffi_qsort.cib: '; wc -c < build/ffi_qsort.cib
	@test "$$(stat -c%s runtime/zig-out/bin/cinterp-run)" -lt 131072
	@test "$$(stat -c%s build/ffi_qsort.cib)" -lt 4096

release-check: test size

cross-test:
	./scripts/test_cross.sh

c-testsuite: runtime
	./scripts/c_testsuite.sh

fetch-suites:
	python3 scripts/fetch_suites.py --all --support

test-suites-smoke: runtime
	python3 scripts/test_suites.py --tier smoke --report build/test-suites-smoke.json

test-suites: runtime
	python3 scripts/test_suites.py --tier standard --report build/test-suites.json

test-suites-full: runtime
	python3 scripts/test_suites.py --tier full --report build/test-suites-full.json

test-suites-nightly: runtime
	python3 scripts/test_suites.py --tier nightly --report build/test-suites-nightly.json
	python3 scripts/generate_diff.py --generator yarpgen --iterations 100 --report build/generate-diff-nightly.json

test-suites-report: test-suites-full
	@test -s build/test-suites-full.json

test-suites-cross: runtime
	cd runtime && zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe build/cross/cinterp-run64.exe
	python3 scripts/test_suites.py --suite csuite --target x86_64-windows --jobs 4 --report build/test-suites-win64.json
	python3 scripts/test_suites.py --suite c-testsuite-smoke --target x86_64-windows --jobs 4 --report build/test-suites-cross-win64.json
	cd runtime && zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run.exe build/cross/cinterp-run32.exe
	python3 scripts/test_suites.py --suite csuite --target i686-windows --jobs 4 --report build/test-suites-win32.json
	python3 scripts/test_suites.py --suite c-testsuite-smoke --target i686-windows --jobs 4 --report build/test-suites-cross-win32.json
	cd runtime && zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall
	cp runtime/zig-out/bin/cinterp-run build/cross/cinterp-run-arm64
	python3 scripts/test_suites.py --suite csuite --target aarch64-linux --jobs 4 --report build/test-suites-arm64.json
	python3 scripts/test_suites.py --suite c-testsuite-smoke --target aarch64-linux --jobs 4 --report build/test-suites-cross-arm64.json
	cd runtime && zig build -Doptimize=ReleaseSmall

generate-diff: runtime
	python3 scripts/generate_diff.py --generator yarpgen --iterations 20 --report build/generate-diff-report.json

generate-diff-nightly: runtime
	python3 scripts/generate_diff.py --generator yarpgen --iterations 100 --report build/generate-diff-nightly.json

generate-diff-csmith: runtime
	python3 scripts/generate_diff.py --generator csmith --iterations 3 --report build/generate-diff-csmith.json

fuzz: runtime
	python3 scripts/fuzz.py --iterations 1000

fuzz-exec: runtime
	python3 scripts/fuzz_exec.py --iterations 500

differential: runtime
	./scripts/differential.sh

bench: runtime
	python3 scripts/benchmark.py

release-artifacts:
	./scripts/package_release.sh

size-cross:
	./scripts/size_cross.sh

clean:
	rm -rf build compiler/src/cinterp/__pycache__ compiler/tests/__pycache__
	cd runtime && rm -rf .zig-cache zig-out
