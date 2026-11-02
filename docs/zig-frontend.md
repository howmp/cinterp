# Zig compiler frontend

`cinterp-cc` is the default build-time compiler. It is a Zig program that invokes
the `zig cc` C frontend, parses the resulting LLVM IR text, and emits the same
CIVM bytecode and CIPKG v2 package format as the original Python compiler.

## Requirements

- Zig 0.13 (bundled clang/LLVM 18). Zig is required at build time.
- No libclang, libLLVM, external clang, or Python dependency is required to
  compile C with `cinterp-cc`.

## Flags passed to `zig cc`

```text
-S -emit-llvm -O0 -fno-discard-value-names
-fno-sanitize=all -fno-stack-protector -ffine-grained-bitfield-accesses
```

`-fno-sanitize=all` is required because Zig's Debug `-O0` would otherwise emit
`llvm.sadd.with.overflow` / `llvm.ubsantrap` intrinsics that are not part of the
CIVM lowering contract. `-fno-stack-protector` removes compiler-inserted stack
checks that have no runtime counterpart.

## Build and use

```bash
make compiler-zig
./build/cinterp-cc compile examples/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
```

For cross targets use `--target`:

```bash
./build/cinterp-cc compile --target aarch64-linux examples/hello.c -o build/hello-arm64.cib
./build/cinterp-cc compile --target x86_64-windows examples/hello.c -o build/hello-win64.cib
./build/cinterp-cc compile --target i686-windows examples/hello.c -o build/hello-win32.cib
```

## Rollback

The Python compiler remains in `compiler/`. Use `make test-py`,
`make test-suites-py`, or set `CINTERP_COMPILER=python` for `scripts/test.sh`.
Release tarballs include `bin/cinterp` which prefers the adjacent `cinterp-cc`
and falls back to Python.
