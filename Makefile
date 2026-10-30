.PHONY: all test runtime compiler-test integration clean

all: test

runtime:
	cd runtime && zig build -Doptimize=ReleaseSmall

compiler-test:
	PYTHONPATH=compiler/src python3 -m unittest discover -s compiler/tests

integration:
	./scripts/test.sh

test:
	./scripts/test.sh

clean:
	rm -rf build compiler/src/cinterp/__pycache__ compiler/tests/__pycache__
	cd runtime && rm -rf .zig-cache zig-out
