# cinterp — small C bytecode interpreter with direct C FFI

`cinterp` compiles C at build time into a compact stack bytecode module plus
compile-time FFI plans, then executes it in a small Zig VM. Native calls go
through a fixed assembly ABI engine; there is no libffi, no `@call` stub matrix,
and no runtime code generation / executable memory.

- **Compiler** (Zig, build-time): invokes `zig cc -S -emit-llvm -O0`, parses
  the LLVM IR text once into a typed AST with a subset verifier, then lowers it
  into CIVM bytecode, the FFI `CallPlan` table (`src/abi.zig`) and a `CIPKG` v2
  package with target metadata (`CIPM`) and external-symbol link metadata
  (`CIPI`). The AST is the only IR frontend; the former string parser and the
  original Python compiler have been removed. Python is used only by the test,
  fuzz and benchmark harnesses; the external-symbol link metadata is generated
  at build time from the installed Zig toolchain (see below).
- **Runtime** (Zig 0.13): stack VM with linear memory, C ABI (`ci_vm_*`),
  compile-time ABI selection, fixed assembly engines for SysV x86-64,
  Win64, Win32 cdecl/stdcall/fastcall and AArch64 AAPCS64, native symbol
  resolution (`dlopen`/`dlsym` on Unix, `LoadLibraryA`/`GetProcAddress` on
  Windows), automatic provider loading from `CIPI`, and static callback pools on
  every ABI.
- **Targets**: Linux x64, Windows x64, Windows x86, Linux AArch64. Build with
  `--target` on the compiler and `-Dtarget` on the runtime.

## Quick start

Requirements: Zig 0.13 (runtime and `zig cc` frontend), plus Python 3.10+ only
for the test/fuzz/benchmark harnesses.

```bash
# build the Zig compiler and release runtime
make compiler runtime

# compile and run a C file
./build/cinterp-cc compile examples/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
# result: 42

./build/cinterp-cc compile examples/ffi_printf.c -o build/printf.cib
./runtime/zig-out/bin/cinterp-run build/printf.cib
# 7 2.5
# result: 0

# struct byval + sret FFI through a user shared library
cc -shared -fPIC -O0 examples/ffi_structs_helper.c -o build/libstruct_helpers.so
./build/cinterp-cc compile examples/ffi_structs.c -o build/ffi_structs.cib
./runtime/zig-out/bin/cinterp-run --lib build/libstruct_helpers.so build/ffi_structs.cib
# result: 28

# inspect target/import metadata
./runtime/zig-out/bin/cinterp-run --dump-target --dump-imports --load-only build/printf.cib

# versions
./build/cinterp-cc --version
./runtime/zig-out/bin/cinterp-run --version

# cross-target packages (build the runtime with the matching -Dtarget)
./build/cinterp-cc compile examples/hello.c \
  --target x86_64-windows -o build/hello-win64.cib
cd runtime && zig build -Dtarget=x86_64-windows-gnu && cd ..
# make cross-test        # Win64/Win32 (Wine or native Windows) + ARM64 (qemu)
# optional remote runner: HOST=user@windows-box REMOTE='C:/tmp/cinterp/' make cross-test

# local C subset suite: 17 cases in tests/csuite
make c-testsuite

# upstream c-testsuite supported set (see "C test suites" for the skip list)
git clone --depth 1 https://github.com/c-testsuite/c-testsuite /tmp/c-testsuite
python3 scripts/c_testsuite_upstream.py --dir /tmp/c-testsuite/tests/single-exec

# full local test suite (runtime + compiler unit tests, examples, error paths)
make test

# plan evidence from the structured build reports, and version consistency
make evidence
make check-version

# release-size check (runtime < 128K, qsort package < 4K)
make release-check

# fuzz: loader, execution, structured bytecode, FFI, sanitizer, and cross-ABI
make fuzz
make fuzz-exec
make fuzz-bytecode
make fuzz-ffi-exec
make fuzz-capi-asan
make fuzz-sanitizer
make fuzz-cross

# native-vs-cinterp differential check
make differential

# benchmarks and per-target size budgets
make bench
make size-cross

# release tarballs (LICENSE, SBOM, split debug, pkg-config/CMake/Rust bindings),
# SHA256SUMS and optional GPG signature
make release-artifacts
```

Build profiles:

- `-Doptimize=Debug` / `-Doptimize=ReleaseSafe`: full diagnostics, unwind tables,
  frame pointers and panic stack traces.
- `-Doptimize=ReleaseSmall` (default `make runtime`): strips unwind tables,
  frame pointers, panic tracing and symbols; ELF release artifacts additionally
  drop `.eh_frame`/`.eh_frame_hdr`. Concise error codes and CLI messages remain.
- Current sizes: Debug ≈ 8.8 MiB, ReleaseSmall 102,336 B ≈ 100 KiB (Linux x64).

`make test` runs runtime and compiler unit tests, all end-to-end examples,
the C embedding API (static and shared), and negative paths (missing input,
corrupt/truncated packages, unknown symbol, target mismatch). `make c-testsuite`
runs the local 17-case C subset in `tests/csuite` via `scripts/c_testsuite.sh`;
set `C_TESTSUITE_DIR` to point it at another directory with `// expect:` markers.

## Release tarballs

`make release-artifacts` writes four target tarballs into `build/release/` plus
per-target SPDX SBOMs and `SHA256SUMS` (GPG-signed when `CINTERP_GPG_KEY` is
set):

| Tarball | Contents |
| --- | --- |
| `cinterp-<version>-sysv-x86_64` | compiler + runtime, Linux x86-64 (`bin/cinterp-cc`, `bin/cinterp`) |
| `cinterp-<version>-win64-x86_64` | runtime only, Windows x64 |
| `cinterp-<version>-win32-x86` | runtime only, Windows x86 |
| `cinterp-<version>-arm64` | runtime only, Linux AArch64 |

Only the Linux x86-64 tarball ships `bin/cinterp-cc`; the other three ship the
runtime, header, pkg-config/CMake metadata and the Rust binding. Each tarball's
`README.md` is rendered from [`packaging/README.release.md.in`](packaging/README.release.md.in)
and describes exactly that target's layout. `THIRD_PARTY_NOTICES.md` (MinGW-w64
`.def` and glibc `abilists` attribution for the generated symbol indexes) ships
only with the compiler tarball; runtime-only tarballs carry no derived data.

## C test suites

Upstream suites are pinned by commit and fetched into `build/suites/` (not
vendored). The unified runner reads `tests/manifests/*.json`, records explicit
skips and writes `build/test-suites-*.json`.

```bash
python3 scripts/fetch_suites.py --all --support
make test-suites-smoke      # fast local subset (csuite, 17/17)
make test-suites            # c-testsuite + TCC + chibicc + libc-test
make test-suites-full       # adds GCC torture, CompCert, LLVM subsets
make test-suites-cross      # csuite + upstream smoke on Win64/Win32/ARM64
make generate-diff          # YARPGen differential smoke
make test-winapi            # Windows API imports; needs Wine + cross runtimes
```

Current native baseline (`build/test-suites-full.json`): **4319 passed / 202
explicitly skipped** out of 4521 manifest cases, with a further 1034
deliberately excluded non-target cases. The standard tier
(`build/test-suites.json`) is **396 passed / 99 skipped** out of 495.

About 55% of the passing cases are **compile-only** (gcc-torture-compile 1408 +
llvm-regression-c 934 + compcert-compile 30 = 2372): they check that the
compiler accepts the source and emits a package, not that the program's output
matches native execution. The executable baseline is the remaining 1862
passing cases (4319 − 2457 compile-mode passes). Four compile-only stress
cases now skip with an explicit `compiler limit:` reason because the package
would exceed the runtime's 512-import, 64-argument or 2 MiB module limits. Skip files record unsupported features and known failures; they
are never auto-updated by CI. See
[`tests/manifests/README.md`](tests/manifests/README.md).

Upstream c-testsuite: `tests/manifests/c-testsuite.json` has 220 single-exec
cases with two inline skips (`00204` vector types, `00216` complex aggregate
global initializers), i.e. **218 run / 218 pass / 2 skip**. The standalone
`scripts/c_testsuite_upstream.py` still defaults to the older
`tests/csuite/cinterp.skip` list, which also lists `00189` (external data
symbols), giving **217/217 with 3 skips**; `tests/manifests/c-testsuite.skip`
exists but is not referenced by any manifest. The two skip lists are not yet
unified — quote 218/2 for manifest runs and 217/3 only for the standalone
script until they are.

In the full report the `llvm-regression-c` duplicate support-file IDs have been
renamed with a `*-support` suffix, so the unique-case count stays 935 and the
baseline above is stable.

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

`scripts/check_plan_evidence.py` reads the structured artifacts
(`build/test-suites*.json`, `build/generate-diff-nightly.json`,
`build/release/*.tar.gz`, `SHA256SUMS`, cross runtimes) instead of grepping
text logs. `make evidence` produces the local subset and runs it; full, cross
and nightly reports are reported as "not provided" locally and completed from
CI artifacts.

Format reference: [`docs/cib.md`](docs/cib.md) covers CIPKG v2, CIPM, CIPI,
CIPL and the opcode table.

## Compiler

```bash
./build/cinterp-cc compile source.c -o out.cib \
  [--dump] [--dump-ast] [--dump-imports] [--keep-ir] [--target TARGET] \
  [--cc zig] [--cc-path PATH] [--cib-version 1|2] [--no-auto-link]
```

`--dump` prints functions and FFI plans (including each plan's `conv`);
`--dump-ast` prints the parsed typed AST; `--dump-imports` prints CIB provider
bindings; `--keep-ir` keeps the generated LLVM IR next to the package.
`--cc-path` selects the `zig` binary used as the C frontend and `--cc` currently
accepts `zig` only. `--cib-version 1` emits legacy packages without CIPM/CIPI.
`--no-auto-link` disables automatic C-standard-library/Windows-API binding.
Targets: `x86_64-linux` (default native), `x86_64-windows`, `i686-windows`,
`aarch64-linux`. Windows targets automatically use Zig's bundled MinGW headers
(`libc/include/any-windows-any`) when available; set `ZIG_LIB_DIR` to override.

The compiler models the calling convention in the plan: `x86_stdcallcc` maps to
`conv=1` and `x86_fastcallcc` to `conv=2` for native, indirect and callback
plans (the call-site convention wins; a declaration is the fallback). Known
Windows API imports still take the DLL/symbol/callconv recorded in
`win_defs`, which overrides the plan byte for i686 stdcall exports.

Identical plans are deduplicated by full content (name, args/locs, return
locs, stack/sret/sse/ret size and conv), so repeated calls to one signature
share one CIPL entry. Before serializing, the compiler checks every runtime
limit and fails with `compiler limit: ...` instead of emitting a package the
loader will reject: 512 functions, 1024 plans, 64 args per plan, 8 locations
per argument/return, 128-byte function/plan names, 512 imports, 8 providers per
import, 64-byte import/provider/symbol names, 32-byte provider version, and a
2 MiB CIVM module.

The compiler automatically links used C standard library symbols and Windows
APIs; no `--lib` is required for those. The symbol -> provider tables are
generated at build time from the installed Zig toolchain, so there is no
checked-in link database and no `--link-db` option (it was removed):

- **Linux** (`compiler/src/libc_defs.zig`): Zig's bundled glibc `abilists`
  give the exporting soname (`printf` -> `libc.so.6`, `sin` -> `libm.so.6`,
  `pthread_create` -> `libc.so.6`/`libpthread.so.0`).
- **Windows** (`compiler/src/win_defs.zig`): Zig's bundled MinGW `.def`
  files give the DLL, x86 stdcall decoration and call convention
  (`GetTickCount64` -> `kernel32.dll`, `GetSystemMetrics` -> `user32.dll`,
  `MessageBoxA@16` -> `user32.dll` with `conv=1`).
- **Runtime fallback**: symbols the indexes do not describe (UCRT `printf`,
  custom libraries) are resolved at run time from the process, `--lib`
  libraries and the default C runtime (`libc.so.6`/`libm.so.6`/... on Linux,
  `msvcrt.dll`/`ucrtbase.dll`/`ntdll.dll` on Windows).

Because the Windows index no longer carries a minimum-OS field, new packages
declare `min_os=0`; calling an API that is missing on an older Windows fails at
run time instead of load time. Custom libraries still use `--lib` and take
precedence over CIB providers. Only one CIB is executed at a time; CIB-to-CIB
linking is explicitly unsupported.

The compiler currently supports:

- scalar `i1/i8/i16/i32/i64`, integer arithmetic/div/rem/bitwise/shift
- signed/unsigned comparisons, trunc/zext/sext, switch/goto
- alloca/load/store over a linear memory, arrays, structs, pointer parameters,
  GEP, union aliasing, `memcpy`/`memset`, globals and string literals
- external scalar/pointer/varargs calls (FFI plans), e.g. `puts`, `printf`,
  `malloc`, `free`, `snprintf`
- external data symbols through basic CIPI data providers and the runtime
  fallback (`stdout`, `errno`, `environ`, `stdin`, `tzname`, `opt*`, and the
  Windows UCRT `_errno`/`__acrt_iob_func`/`__p__environ` helpers)
- C varargs functions (`va_start`/`va_arg`/`va_end`/`va_copy`) across the four
  ABIs, including copies of `long double` and aggregate arguments
- `main(argc, argv, envp)` with `cinterp-run package -- arg...`
- VM-level `setjmp`/`longjmp` (including Windows `_setjmp3`/`__intrinsic_setjmpex`)
- external MEMORY structs by value (`byval`) and struct returns through `sret`
  (see `examples/ffi_structs.c` + `--lib`)
- register-class small structs: coerced 8-byte (S8) and 16-byte double-HFA
  aggregate returns (D16), including `extractvalue` and `fptosi` (see
  `examples/ffi_regstruct.c`)
- callbacks: a VM function passed as a C function pointer becomes a static
  trampoline on SysV x64, Win64, Win32 (cdecl and stdcall) and AArch64; the
  dispatcher re-enters the VM without unwinding the outer frame (see
  `examples/ffi_qsort.c`, `examples/ffi_callback*.c`,
  `examples/ffi_callback_stdcall.c`)
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
  (`examples/ffi_hfa.c`, `examples/ffi_hfa_stack.c`)
- Win32 `__fastcall` native/indirect calls (ECX/EDX + stack, see
  `examples/ffi_fastcall.c`) and Win32 `__stdcall` calls/callbacks

Explicitly outside the current C/ABI subset: vector types, `_Complex` and
complex/empty-struct aggregate global initializers, Win64 `__vectorcall`/COM,
Win32 `thiscall`, Win32 `__fastcall` callbacks, SysV `i128`/vector arguments,
inline assembly, `_Atomic`/`_Thread_local`, and CIB-to-CIB linking. Windows CRT
`long double` printf output matches the native MinGW runtime (which itself does
not implement `%Lf` on the test host). GCC builtins, external inline/weak
address semantics, and growable linear memory are also out of scope.

## Binary formats

- `CIVM`: bytecode module (header, function table, code). VM linear memory is
  initialized by code emitted at the start of `main` for globals/strings.
- `CIPL` v3: FFI plan table (magic/version/ABI, named `CallPlan`s, arg/ret locs,
  stack/sret/sse/ret_size/conv).
- `CIPKG` v2: 25-byte header + `CIVM` + `CIPL` + `CIPM` target metadata +
  `CIPI` import table. Legacy v1 packages remain loadable.
- `CIPM`: arch/OS/ABI/pointer width/endian/features/triple/min-runtime plus the
  `link_db` provenance string naming the build-time symbol index
  (`mingw-defs@<zig version>` / `glibc-abilists@<zig version>`).
- `CIPI`: plan index → provider library, real symbol/alias, ordinal, callconv,
  architecture mask and minimum OS.

Detailed byte layout, opcode table, CIPL/CIPM/CIPI fields and an annotated
`hello.cib` are in [docs/cib.md](./docs/cib.md).

## Runtime

```bash
./runtime/zig-out/bin/cinterp-run <package.cib> [entry] [-- arg...]
```

`cinterp-run` exits 0 on success, 1 for a load/run failure and 2 for usage or
I/O errors; the C `main` return value is printed as `result: N` and does not
become the process exit code.

The runtime also ships an embedding library:

```bash
cd runtime && zig build -Doptimize=ReleaseSmall
# zig-out/include/cinterp.h
# zig-out/lib/libcinterp.a, libcinterp.so[.0]
# zig-out/bin/cinterp.dll and lib/cinterp_static.lib on Windows
```

```c
#include <cinterp.h>

ci_vm *vm = ci_vm_create(0);
int rc = ci_vm_load_package(vm, cib_bytes, cib_size);
if (rc == CI_OK) rc = ci_vm_run_args(vm, "main", argc, argv);
int64_t value = ci_vm_result(vm);
ci_vm_destroy(vm);
```

The C ABI version is `CI_ABI_VERSION = 2`; `ci_abi_version()` returns it and
`ci_version()` returns the runtime version string. `ci_vm_run`/`ci_vm_run_args`
return a status, not the C `main` result: `CI_OK` or a **negative,
category-specific `CI_E_*` code** (`CI_E_INVALID_ARGUMENT`, `CI_E_BAD_PACKAGE`,
`CI_E_TARGET`, `CI_E_PLANS`, `CI_E_LINK`, `CI_E_ENTRY`, `CI_E_RESOURCE`,
`CI_E_RUNTIME`, `CI_E_OUT_OF_MEMORY`, `CI_E_DESTROYED`). `CI_ERROR` (-1) is
returned only when a failure cannot be classified. The same category is
available from `ci_vm_last_error_code()`, with text from `ci_vm_last_error()`;
`ci_vm_clear_error()` resets both and returns `CI_OK`. `CI_E_DESTROYED` is
distinct from other runtime errors. Loaders are transactional.

`ci_vm_create(stack_size)` takes a value-stack slot bound: `0` selects the
default 8192 slots (also the maximum). `ci_vm_create_ex` additionally takes
`memory_size` (`0` = 1 MiB default, maximum 16 MiB) plus a reserved `flags`
field that must be 0; older callers whose `struct_size` stops after
`stack_size` are still accepted. Packages still need to be compiled with
`cinterp` at build time; the runtime does not need clang.

A default VM allocates a VM record of roughly 0.9 MiB (dominated by the fixed
512-entry CIPI import table and 512 frame records), an 8192-slot value stack
(64 KiB) and the 1 MiB default linear memory — about 2 MiB in total. Module
buffers and FFI plan stores are allocated per loaded package instead of a fixed
6.5 MiB plan table. `memory_size` can be lowered for small packages. Separate
VM instances do not share interpreter state.

The VM is single-threaded per instance and reentrant at the host callback
boundary. Callback trampolines live in a process-wide pool of 256 fixed slots.
A slot is retired permanently when its owning VM is destroyed or its plans are
reloaded and is **never reused** (a host may still hold the function pointer),
so the pool is a one-time budget of 256 callback registrations per process;
later `CREATE_CALLBACK` operations fail with `TooManyCallbacks`
(`CI_E_RUNTIME`).

For v2 packages the runtime resolves native symbols through CIPI providers
(with `--lib` as a user override); unlisted custom symbols fall back to the
process, loaded `--lib` libraries and the platform C runtime. A resolved
target is cached per plan index on the first call, and the provider/target
caches are cleared when a package or plan table is replaced (explicit `--lib`
handles survive a package swap). More than 256 distinct native targets in one
VM returns `TooManyNativeTargets` (`CI_E_LINK`). Library handles are never
unloaded: `--lib` and provider libraries stay mapped until the process exits.
Static callback trampolines are available for SysV x64, Win64, Win32 and
AArch64.

The runtime executes trusted CIB packages and does not provide an in-process
sandbox; `--load-only` validates a package without executing it. Unsupported
runtimes (macOS/unknown OS and musl) reject packages at load time with
`UnsupportedOs`/`UnsupportedLibc`.

## Repository layout

```text
compiler/          Zig compiler (build-time)
  src/main.zig         cinterp-cc CLI, CIPKG/CIPM/CIPI writer, limit checks
  src/opcodes.zig      CIVM opcode definitions (single source)
  src/ir/              typed LLVM IR lexer/parser/AST/verifier/dump
  src/lower_ast.zig    AST -> CIVM lowering, plan interning
  src/abi.zig          CallPlan model and per-ABI plan builders
  src/imports.zig      structured CIPI table and serializer
  src/link_index.zig   binary format of the generated symbol indexes
  src/win_defs.zig     Windows providers from Zig's bundled MinGW .def files
  src/libc_defs.zig    Linux providers from Zig's bundled glibc abilists
  src/link_wrappers.zig  target link-ABI aliases (snprintf -> _snprintf)
  src/data/link_wrappers.json  the only checked-in link metadata
  tools/gen_link_index.zig     build-time generator for win_defs/libc_defs
docs/                  format, embedding, compatibility, IR subset, Zig frontend
runtime/               Zig VM/runtime (shipped)
  src/vm.zig           VM, linear memory, C ABI, callback dispatcher
  src/vm_test.zig      runtime unit tests
  src/main.zig         cinterp-run CLI
  src/ffi/abi.zig      plan/loc types shared with the loader and asm engines
  src/ffi/plan_loader.zig  CIPL decoder and plan store
  src/ffi/platform.zig compile-time ABI/frame/marshal/invoke selection
  src/ffi/native.zig   dlopen/LoadLibrary symbol resolution
  src/ffi/link_loader.zig  CIPM/CIPI parser and target/import validation
  src/ffi/asm/         SysV, Win64, Win32, AArch64 engines and trampolines
  include/cinterp.h    public C ABI header
  tests/               C API smoke/argv/fuzz hosts
examples/              hello, arrays, structs, puts/printf/snprintf, malloc/free,
                       MEMORY/register/mixed/HFA struct FFI, qsort/callback,
                       fastcall/stdcall, math, float32 FFI, bitfields, long double
scripts/               Python test/fuzz/benchmark/release harnesses
packaging/             pkg-config, CMake, Rust binding, release README template
tests/                 local csuite, manifests and generator known failures
spike/                 validated ABI/VM/callback feasibility spikes (gitignored)
```

## Documentation

- [docs/README.md](docs/README.md) — documentation index
- [docs/cib.md](docs/cib.md) — CIB package format, link metadata, status codes
- [docs/embedding.md](docs/embedding.md) — embedding the runtime in a C host
- [docs/compatibility.md](docs/compatibility.md) — ABI, SONAME and versioning policy
- [docs/ir-subset.md](docs/ir-subset.md) — accepted LLVM IR subset
- [docs/ir-parser-differences.md](docs/ir-parser-differences.md) — former string
  parser differences (kept as AST correctness tests)
- [docs/zig-frontend.md](docs/zig-frontend.md) — Zig/`zig cc` frontend contract
- [tests/manifests/README.md](tests/manifests/README.md) — suite manifests and skip policy

See `dev.md` for architecture, implementation decisions, ABI details, validation
evidence and known boundaries.
