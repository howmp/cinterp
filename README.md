# cinterp — small C bytecode interpreter with direct C FFI

`cinterp` compiles C at build time into a compact stack bytecode module plus
compile-time FFI plans, then executes it in a small Zig VM. Native calls go
through a fixed assembly ABI engine; there is no libffi, no `@call` stub matrix,
and no runtime code generation / executable memory.

- **Compiler** (Python, build-time): `clang -S -emit-llvm -O0`, LLVM IR → CIVM
  bytecode, FFI `CallPlan` table, and a `CIPKG` v2 package with target metadata
  (`CIPM`) and external-symbol link metadata (`CIPI`).
- **Runtime** (Zig 0.13): stack VM with linear memory, C ABI (`ci_vm_*`),
  compile-time ABI selection, fixed assembly engines for SysV x86-64,
  Win64, Win32 cdecl/stdcall and AArch64 AAPCS64, native symbol resolution
  (`dlopen`/`dlsym` on Unix, `LoadLibraryA`/`GetProcAddress` on Windows),
  automatic provider loading from `CIPI`, and static callback pools on every ABI.
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

# inspect target/import metadata
./runtime/zig-out/bin/cinterp-run --dump-target --dump-imports --load-only build/printf.cib

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

# upstream c-testsuite supported set (217/217; 3 categorized skips)
git clone --depth 1 https://github.com/c-testsuite/c-testsuite /tmp/c-testsuite
python3 scripts/c_testsuite_upstream.py --dir /tmp/c-testsuite/tests/single-exec

# full test suite
make test

# release-size check (runtime < 128K, qsort package < 4K)
make release-check

# fuzz: load-only package/plan, and safe bytecode execution
make fuzz
make fuzz-exec

# native-vs-cinterp differential check
make differential

# benchmarks and per-target size budgets
make bench
make size-cross

# release tarballs for all four targets
make release-artifacts
```

`make test` runs runtime/compiler unit tests, all end-to-end examples, and
negative paths (missing input, corrupt/truncated packages, unknown symbol).
`make c-testsuite` runs the local 10-case C subset. The upstream
c-testsuite supported set currently passes 217/217 with 3 explicitly skipped
tests (external data symbols, vector types, complex aggregate initializers);
set `C_TESTSUITE_DIR` to point at an external directory.

## C test suites

Upstream suites are pinned by commit and fetched into `build/suites/` (not
vendored). The unified runner reads `tests/manifests/*.json`, records explicit
skips and writes `build/test-suites-*.json`.

```bash
python3 scripts/fetch_suites.py --all --support
make test-suites-smoke      # fast local subset
make test-suites            # c-testsuite + TCC + chibicc + libc-test
make test-suites-full       # adds GCC torture, CompCert, LLVM UnitTests
make test-suites-cross      # csuite on Win64/Win32/ARM64
make generate-diff          # YARPGen differential smoke
```

Current native baseline: 4110 passed / 343 explicitly skipped across csuite,
c-testsuite, TCC tests2, chibicc, libc-test, GCC torture, CompCert and LLVM
SingleSource. Skip files record unsupported features and known failures; they
are never auto-updated by CI. See [`tests/manifests/README.md`](tests/manifests/README.md).

## Validation and trust

The runtime validates package lengths, target metadata (arch/OS/ABI/pointer
width/features), CIPI plan/provider references, function/plan counts, plan
argument counts, ABI location indices, and marshal offsets/sizes before
invoking native code; malformed packages fail cleanly. `cinterp-run
--load-only` validates a package without executing it; `make fuzz`
mutates/truncates seed packages and checks for crashes. Automatic providers
must be library names (no paths) and are loaded from the system loader. C
pointers to native allocations are necessarily trusted, so run untrusted
packages under an OS sandbox.

Format reference: [`docs/cib.md`](docs/cib.md) covers CIPKG v2, CIPM, CIPI,
CIPL and the opcode table.

## Compiler

```bash
PYTHONPATH=compiler/src python3 -m cinterp compile source.c -o out.cib \
  [--dump] [--dump-imports] [--keep-ir] [--target TARGET] \
  [--cib-version 1|2] [--no-auto-link] [--link-db DIR]
```

`--dump` prints functions and FFI plans; `--dump-imports` prints CIB provider
bindings; `--keep-ir` keeps the generated LLVM IR next to the package.
`--cib-version 1` emits legacy packages without CIPM/CIPI. `--no-auto-link`
disables automatic C-standard-library/Windows-API binding. `--link-db DIR`
overrides the generated cstdapi/winmd databases. Targets: `x86_64-linux`
(default native), `x86_64-windows`, `i686-windows`, `aarch64-linux`.

The compiler automatically links used C standard library symbols on all
targets (libc/libm, UCRT/MSVCRT/NTDLL) and Windows APIs on Windows targets
(via the vendored winmd index); no `--lib` is required for those. Custom
libraries still use `--lib` and take precedence over CIB providers.

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
  trampoline on SysV x64, Win64, Win32 and AArch64; the dispatcher re-enters
  the VM without unwinding the outer frame (see `examples/ffi_qsort.c`,
  `examples/ffi_callback*.c`)
- mixed-class register aggregates of two eightbytes (e.g. `{ i64, double }`
  returned in RAX + XMM0; see `examples/ffi_mixedstruct.c`)
- float32/double arithmetic: `fadd`/`fsub`/`fmul`/`fdiv`, `fcmp`,
  `fpext`/`fptrunc`, `sitofp`/`fptosi` (see `examples/math.c`,
  `examples/float_math.c`, `examples/ffi_float.c`)
- bitfields via clang's integer shift/mask lowering (see
  `examples/bitfields.c`)
- exact `long double` internally: x86 `f80` on x86 targets and IEEE `f128` on
  AArch64; arithmetic/comparison/conversion and FFI/varargs paths
  (`examples/longdouble.c`, `examples/ffi_longdouble.c`). Windows CRT `%Lf`
  behavior matches the native MinGW runtime.
- internal function pointers, indirect calls, `phi`, VLA, packed structs,
  global pointer/function-pointer relocations, HFA 3/4 and stack HFA

Explicitly outside the current C/ABI subset: external data symbols
(`stdout`/`errno`-style), vector types, complex/empty-struct aggregate global
initializers, Win64 `__vectorcall`/COM, Win32 `fastcall`/`thiscall`, SysV
`i128`/vector arguments, and HFA callbacks with more than two return vectors.
Windows CRT `long double` printf output matches the native MinGW runtime
(which itself does not implement `%Lf` on the test host).

## Binary formats

- `CIVM`: bytecode module (header, function table, code). VM linear memory is
  initialized by code emitted at the start of `main` for globals/strings.
- `CIPL` v3: FFI plan table (magic/version/ABI, named `CallPlan`s, arg/ret locs,
  stack/sret/sse/ret_size).
- `CIPKG` v2: 25-byte header + `CIVM` + `CIPL` + `CIPM` target metadata +
  `CIPI` import table. Legacy v1 packages remain loadable.
- `CIPM`: arch/OS/ABI/pointer width/endian/features/triple/min-runtime/link-db.
- `CIPI`: plan index → provider library, real symbol/alias, ordinal, callconv,
  architecture mask and minimum OS.

Detailed byte layout, opcode table, CIPL/CIPM/CIPI fields and an annotated
`hello.cib` are in [docs/cib.md](./docs/cib.md).

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
memory for stack/global data. For v2 packages it resolves native symbols
through CIPI providers (with `--lib` as a user override); unlisted custom
symbols fall back to the process, loaded `--lib` libraries and the platform C
runtime. Static callback trampolines are available for SysV x64, Win64, Win32
and AArch64. `--safe`
disables native calls and restricts memory operations to the VM linear memory
for bytecode fuzzing; `--load-only` validates a package without executing it.

## Repository layout

```text
compiler/              Python package (build-time compiler)
  src/cinterp/
    llvm_ir/lower.py   LLVM IR parser/lowerer (CIVM + plans)
    ffi/plan.py        CallPlan model, per-ABI plan builders, CIPL serializer
    link/              CIPM target metadata, CIPI serializer, cstdapi/winmd databases
    codegen/           CIPKG writer
    cli.py             cinterp compile
docs/cib.md            binary package format reference
runtime/               Zig VM/runtime (shipped)
  src/vm.zig           VM, linear memory, C ABI, callback dispatcher
  src/ffi/platform.zig compile-time ABI/frame/marshal/invoke selection
  src/ffi/native.zig   dlopen/LoadLibrary symbol resolution
  src/ffi/link_loader.zig  CIPM/CIPI parser and target/import validation
  src/ffi/asm/         SysV, Win64, Win32, AArch64 engines
  src/main.zig         cinterp-run CLI
examples/              hello, arrays, structs, puts/printf/snprintf, malloc/free,
                       MEMORY/register/mixed struct FFI, qsort callback, math,
                       float32 FFI, bitfields
scripts/test.sh        integration suite
spike/                 validated ABI/VM/callback feasibility spikes (gitignored)
dev.md                 architecture, decisions, ABI details, boundaries
```

See `dev.md` for architecture, implementation decisions, ABI details, validation evidence and known boundaries.
