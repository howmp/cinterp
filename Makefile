.PHONY: all test runtime compiler-test integration size release-check cross-test c-testsuite fuzz fuzz-exec differential bench size-cross clean

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

fuzz: runtime
	python3 scripts/fuzz.py --iterations 200

fuzz-exec: runtime
	python3 scripts/fuzz_exec.py --iterations 200

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
