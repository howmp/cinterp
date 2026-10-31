# cinterp — small C bytecode interpreter with direct C FFI

`cinterp` compiles C at build time into a compact stack bytecode module plus
compile-time FFI plans, then executes it in a small Zig VM. Native calls go
through a fixed assembly ABI engine; there is no libffi, no `@call` stub matrix,
and no runtime code generation / executable memory.

- **Compiler** (Python, build-time): `clang -S -emit-llvm -O0`, LLVM IR → CIVM
  bytecode, FFI `CallPlan` table, `CIPKG` package.
- **Runtime** (Zig 0.13): stack VM with linear memory, C ABI (`ci_vm_*`),
  compile-time ABI selection, fixed assembly engines for SysV x86-64,
  Win64, Win32 cdecl and AArch64 AAPCS64, and native symbol resolution
  (`dlopen`/`dlsym` on Unix, `LoadLibraryA`/`GetProcAddress` on Windows).
- **Targets**: Linux x64, Windows x64, Windows x86, Linux AArch64. Build with
  `--target` on the compiler and `-Dtarget` on the runtime.

## Quick start

Requirements: Zig 0.13, clang, Python 3.10+.

```bash
# build runtime
cd runtime && zig build -Doptimize=ReleaseSmall && cd ..

# compile and run a C file
PYTHONPATH=compiler/src python3 -m cinterp compile examples/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
# result: 42

PYTHONPATH=compiler/src python3 -m cinterp compile examples/ffi_printf.c -o build/printf.cib
./runtime/zig-out/bin/cinterp-run build/printf.cib
# 7 2.5
# result: 0

# struct byval + sret FFI through a user shared library
cc -shared -fPIC -O0 examples/ffi_structs_helper.c -o build/libstruct_helpers.so
PYTHONPATH=compiler/src python3 -m cinterp compile examples/ffi_structs.c -o build/ffi_structs.cib
./runtime/zig-out/bin/cinterp-run --lib build/libstruct_helpers.so build/ffi_structs.cib
# result: 28

# versions
PYTHONPATH=compiler/src python3 -m cinterp --version
./runtime/zig-out/bin/cinterp-run --version

# cross-target packages (build the runtime with the matching -Dtarget)
PYTHONPATH=compiler/src python3 -m cinterp compile examples/hello.c \
  --target x86_64-windows -o build/hello-win64.cib
cd runtime && zig build -Dtarget=x86_64-windows-gnu && cd ..
# HOST=user@windows-box make cross-test   # Win64/Win32/ARM64 suite

# C subset suite
make c-testsuite

# full test suite
make test

# release-size check (runtime < 128K, qsort package < 4K)
make release-check
```

`make test` runs runtime/compiler unit tests, all end-to-end examples, and
negative paths (missing input, corrupt/truncated packages, unknown symbol).
`make c-testsuite` runs a local C subset; set `C_TESTSUITE_DIR` to point at an
external c-testsuite directory (tests without `// expect: N` are skipped).

## Validation and trust

The runtime validates package lengths, function/plan counts, plan argument
counts, ABI location indices, and marshal offsets/sizes before invoking native
code; malformed packages fail cleanly. C pointers to native allocations are
necessarily trusted, so run untrusted packages under an OS sandbox.

## Compiler

```bash
PYTHONPATH=compiler/src python3 -m cinterp compile source.c -o out.cib [--dump] [--keep-ir] [--target TARGET]
```

`--dump` prints functions and FFI plans; `--keep-ir` keeps the generated LLVM IR
next to the package. Targets: `x86_64-linux` (default native), `x86_64-windows`,
`i686-windows`, `aarch64-linux`.

The compiler currently supports:

- scalar `i1/i8/i16/i32/i64`, integer arithmetic/div/rem/bitwise/shift
- signed/unsigned comparisons, trunc/zext/sext, switch/goto
- alloca/load/store over a linear memory, arrays, structs, pointer parameters,
  GEP, union aliasing, `memcpy`/`memset`, globals and string literals
- external scalar/pointer/varargs calls (FFI plans), e.g. `puts`, `printf`,
  `malloc`, `free`, `snprintf`
- external MEMORY structs by value (`byval`) and struct returns through `sret`
  (see `examples/ffi_structs.c` + `--lib`)
- register-class small structs: coerced 8-byte (S8) and 16-byte double-HFA
  aggregate returns (D16), including `extractvalue` and `fptosi` (see
  `examples/ffi_regstruct.c`)
- callbacks: a VM function passed as a C function pointer becomes a static
  trampoline; the dispatcher re-enters the VM without unwinding the outer
  frame (see `examples/ffi_qsort.c`)
- mixed-class register aggregates of two eightbytes (e.g. `{ i64, double }`
  returned in RAX + XMM0; see `examples/ffi_mixedstruct.c`)
- float32/double arithmetic: `fadd`/`fsub`/`fmul`/`fdiv`, `fcmp`,
  `fpext`/`fptrunc`, `sitofp`/`fptosi` (see `examples/math.c`,
  `examples/float_math.c`, `examples/ffi_float.c`)
- bitfields via clang's integer shift/mask lowering (see
  `examples/bitfields.c`)
- `long double` storage/arithmetic (16-byte memory, 64-bit precision; no
  long-double FFI/printf yet; see `examples/longdouble.c`)

Not yet in the compiler (the runtime engines and spikes validate the ABI):
aggregates larger than two eightbytes outside MEMORY/sret, `long double`.

## Binary formats

- `CIVM`: bytecode module (header, function table, code). VM linear memory is
  initialized by code emitted at the start of `main` for globals/strings.
- `CIPL` v2: FFI plan table (magic/version/ABI, named `CallPlan`s, arg/ret locs,
  stack/sret/sse/ret_size).
- `CIPKG`: package = `CIPKG` v1 + module length + plan length + module + plans.

## Runtime

```bash
./runtime/zig-out/bin/cinterp-run <package.cib> [entry]
```

The runtime exports a C ABI from `runtime/src/vm.zig`:

```c
ci_vm_create, ci_vm_destroy,
ci_vm_load_module, ci_vm_load_plans, ci_vm_load_package, ci_vm_load_library,
ci_vm_run, ci_vm_last_error
```

The VM is single-threaded, reentrant at the host C ABI boundary, uses a linear
memory for stack/global data, and resolves native symbols through the process,
loaded `--lib` libraries, and the platform C runtime. Static callback
trampolines are currently available on the SysV x86-64 engine.

## Repository layout

```text
compiler/              Python package (build-time compiler)
  src/cinterp/
    llvm_ir/lower.py   LLVM IR parser/lowerer (CIVM + plans)
    ffi/plan.py        CallPlan model, per-ABI plan builders, CIPL serializer
    codegen/           CIPKG writer
    cli.py             cinterp compile
runtime/               Zig VM/runtime (shipped)
  src/vm.zig           VM, linear memory, C ABI, callback dispatcher
  src/ffi/platform.zig compile-time ABI/frame/marshal/invoke selection
  src/ffi/native.zig   dlopen/LoadLibrary symbol resolution
  src/ffi/asm/         SysV, Win64, Win32, AArch64 engines
  src/main.zig         cinterp-run CLI
examples/              hello, arrays, structs, puts/printf/snprintf, malloc/free,
                       MEMORY/register/mixed struct FFI, qsort callback, math,
                       float32 FFI, bitfields
scripts/test.sh        integration suite
spike/                 validated ABI/VM/callback feasibility spikes (gitignored)
plan.md, dev.md        implementation plan and architecture/decisions
```

See `dev.md` for the architecture and `plan.md` for milestone/spike history.
