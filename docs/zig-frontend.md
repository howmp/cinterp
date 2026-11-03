# Zig compiler frontend

`cinterp-cc` is the default build-time compiler. It invokes the `zig cc` C
frontend, parses the resulting LLVM IR text with a typed lexer/parser/AST and a
subset verifier, then emits the same CIVM bytecode and CIPKG v2 package format as
the original Python compiler. The typed AST is the only IR frontend; the former
string parser has been removed.

## Requirements

- Zig 0.13 (bundled clang/LLVM 18). Zig is required at build time.
- No libclang, libLLVM, external clang, or Python dependency is required to
  compile C with `cinterp-cc`.

## Flags passed to `zig cc`

```text
-S -emit-llvm -O0 -g0 -fno-discard-value-names
-fno-sanitize=all -fno-stack-protector -ffine-grained-bitfield-accesses
```

`-fno-sanitize=all` is required because Zig's Debug `-O0` would otherwise emit
`llvm.sadd.with.overflow` / `llvm.ubsantrap` intrinsics that are not part of the
CIVM lowering contract. `-fno-stack-protector` removes compiler-inserted stack
checks that have no runtime counterpart.

## IR pipeline

```text
LLVM IR text
  -> ir/lexer.zig        spans/tokens (no-copy)
  -> ir/parser.zig       typed Module/Function/BasicBlock/Instruction AST
  -> ir/verify.zig       subset allowlist + target/datalayout checks
  -> lower_ast.zig       CIVM functions
  -> abi.zig             CIPL call plans (SysV/Win64/Win32/AAPCS64)
```

`cinterp-cc compile --dump-ast` prints a structural summary of the parsed module
(block/instruction counts per function) to stderr for debugging.

The parser only accepts the instruction/type/intrinsic subset consumed by the
lowerer. Unsupported legal IR produces a `line:column` diagnostic instead of a
panic or a silent zero. The exact allowlist is in `docs/ir-subset.md`; target
triple/OS/pointer-width and little-endian consistency are checked before lowering.

## Windows API imports

`cinterp-cc` embeds `winmd.generated.json.gz` and resolves Windows API names
(including Win32 stdcall decoration such as `\01_GetTickCount64@0`) to the
correct DLL/provider. `make test-winapi` compiles `examples/winapi.c` with both
the Python and AST frontends for Win64/Win32 and runs them under Wine.

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
