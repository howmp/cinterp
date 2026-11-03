# Zig compiler frontend

`cinterp-cc` is the only build-time compiler. The compiler lives in
`compiler/` (there is no `compiler-zig/` tree) and is a single Zig program: it
invokes the `zig cc` C frontend, parses the resulting LLVM IR text with a typed
lexer/parser/AST plus a subset verifier, and emits CIVM bytecode, CIPL plans
and CIPKG v2 packages.

There is **one** IR frontend — the typed AST under `compiler/src/ir/`:

```text
compiler/src/ir/lexer.zig    spans/tokens (no-copy)
compiler/src/ir/ast.zig      typed Module/Function/BasicBlock/Instruction AST
compiler/src/ir/parser.zig   IR text -> AST
compiler/src/ir/verify.zig   target/datalayout allowlist checks
compiler/src/lower_ast.zig   AST -> CIVM + CIPL + external symbols
compiler/src/abi.zig         CIPL call plans (SysV/Win64/Win32/AAPCS64)
compiler/src/ir/tests.zig    parser fixtures and malformed-input tests
compiler/src/ir/dump.zig     `zig build ir-dump -- file.ll` (debug aid, not installed)
```

The former string/text lowerer (a separate `lower.zig` implementation inside
`compiler/src/`, now deleted) and the original Python compiler have both been
removed, and nothing in `compiler/src/main.zig` selects a parser at run time:
there is no `--ir-parser` flag, no `legacy` parser mode and no
`make parser-parity` target. `compiler/src/lower_ast.zig` is the only lowering
implementation.

## Requirements

- Zig 0.13 (bundled clang/LLVM 18). Zig is required at build time and at
  `cinterp-cc compile` time (it is the C frontend), but not to *run* a `.cib`.
- No libclang, libLLVM, external clang, or Python dependency is required to
  compile C with `cinterp-cc`.

## Flags passed to `zig cc`

```text
-S -emit-llvm -O0 -g0 -fno-discard-value-names
-fno-sanitize=all -fno-stack-protector -ffine-grained-bitfield-accesses
```

Windows targets add `-fms-extensions -fdeclspec`; a `--target=` is passed for
every target other than a native x86-64 Linux host
(`compiler/src/main.zig`, `runZigCc`).

`-fno-sanitize=all` is required because Zig's Debug `-O0` would otherwise emit
`llvm.sadd.with.overflow` / `llvm.ubsantrap` intrinsics that are not part of the
CIVM lowering contract. `-fno-stack-protector` removes compiler-inserted stack
checks that have no runtime counterpart. `-fno-discard-value-names` keeps local
names readable in the IR and in `--dump-ast` output.

## Command line

```text
cinterp-cc compile <source.c> [-o out.cib] [--target T] [--cc-path zig] [--keep-ir]
                    [--dump] [--dump-ast] [--dump-imports]
                    [--cib-version 1|2] [--no-auto-link]
cinterp-cc --version
```

| flag | behaviour |
| --- | --- |
| `-o`, `--output PATH` | output package; default is the source path with its last extension replaced by `.cib` |
| `--target T` | `x86_64-linux` (default), `x86_64-windows`, `i686-windows`, `aarch64-linux`; anything else exits 2 |
| `--cc-path PATH` | C frontend executable (default `zig`) |
| `--cc NAME` | C compiler selector; only `zig` is implemented, any other value exits 2 |
| `--keep-ir` | keep the temporary `<out>.<random>.ll` next to the output |
| `--dump` | print per-function sizes and every plan (`args= ret= stack= conv=`) to stdout |
| `--dump-ast` | print the parsed module summary and per-function block/instruction counts to stderr |
| `--dump-imports` | print the CIPI table (plan index, symbol, providers) |
| `--cib-version 1\|2` | package version to write (default 2) |
| `--no-auto-link` | skip the generated CIPI provider entries |

`--dump-ast` is the in-compiler structural dump
(`lower_ast.dumpModule`): it reports type-def/global/declare/function counts
plus `blocks`/`instructions` per function. `zig build ir-dump -- file.ll` runs
the same parse phase standalone and prints a per-instruction dump.

## IR pipeline

```text
LLVM IR text
  -> ir/lexer.zig        spans/tokens (no-copy)
  -> ir/parser.zig       typed Module/Function/BasicBlock/Instruction AST
  -> ir/verify.zig       subset allowlist + target/datalayout checks
  -> lower_ast.zig       CIVM functions
  -> abi.zig             CIPL call plans (SysV/Win64/Win32/AAPCS64)
```

The parser only accepts the instruction/type/intrinsic subset consumed by the
lowerer. Instructions it does not implement produce a `line:column` diagnostic
instead of a panic or a silent zero, and the lowerer rejects a few accepted
forms (`frem`, `asm` calls). The exact allowlist, including the constructs that
are accepted but only partly modelled, is in [`ir-subset.md`](ir-subset.md).
Target triple/OS/pointer-width and little-endian consistency are checked before
lowering.

## Codegen contracts

- **Calling conventions.** `abi.convFromName` maps `x86_stdcallcc` → `conv=1`
  and `x86_fastcallcc` → `conv=2`; every other LLVM convention and a missing
  keyword map to `0` (the target default: cdecl / SysV / AAPCS64). The
  call-site keyword wins over the declaration's. Indirect calls take the `call`
  instruction's keyword (clang prints the convention there, not in the
  function-pointer type, so there is nothing else to consult). Callback plans
  use the defining function's signature convention, so a Win32 `__stdcall`
  callback gets `conv=1`. The runtime rejects Win32 `__fastcall` callbacks
  (`conv=2`) and `__stdcall` callbacks whose stack argument area exceeds 255
  bytes with `UnsupportedCallback` (`runtime/src/ffi/platform.zig`,
  `win32CallbackSupported`). `main.zig` finally overrides `conv` for known
  WinAPI exports from the generated MinGW import table.
- **Plan deduplication.** Plans are interned by full serialized content
  (`lower_ast.plansEqual`: name, argument/return locations, `stack_size`,
  `sret`, `sse_count`, `ret_size`, `conv`). Identical signatures of the same
  symbol share one plan; different symbols or different ABI layouts never
  merge. This keeps `MAX_PLANS` pressure down for large modules.
- **Limits are enforced before serialization.** `main.validateLimits` runs on
  the complete `CompileResult` and CIPI table before any bytes are written and
  fails with `compiler limit: ...` instead of emitting a package the runtime
  loaders would reject or truncate: ≤512 functions, ≤1024 plans, ≤64 args and
  ≤8 locations per plan, ≤128-byte function/plan names, ≤512 imports, ≤8
  providers per import, ≤64-byte import/provider/symbol names, ≤32-byte
  provider versions, ≤2 MiB CIVM module.

## External symbol resolution (build-time indexes)

`cinterp-cc` does not ship a checked-in link database. `compiler/build.zig`
builds `compiler/tools/gen_link_index.zig` as a host tool and runs it twice; the
outputs are a compact binary table plus a wrapper module that `@embedFile`s it,
injected as the `win_defs_generated` / `libc_defs_generated` anonymous imports.

- Windows (`compiler/src/win_defs.zig`): `<zig lib>/libc/mingw/{lib32,lib64,lib-common}/*.def`
  plus the `*.def.in` templates preprocessed with `zig cc -E`, giving DLL,
  exported symbol, `arch_mask` and call convention. Windows API names
  (including Win32 stdcall decoration such as `\01_GetTickCount64@0`) resolve
  to `kernel32.dll`/`user32.dll`/`api-ms-win-*`, with concrete DLLs preferred
  over API sets. `make test-winapi` compiles `examples/winapi.c` for
  Win64/Win32 and runs it under Wine; it exits non-zero when no target can
  actually be executed (use `python3 scripts/test_winapi.py --allow-skip` for a
  local no-op run).
- Linux (`compiler/src/libc_defs.zig`): `<zig lib>/libc/glibc/abilists`
  restricted to `x86_64-linux-gnu` and `aarch64-linux-gnu`, giving the exporting
  soname (`libc.so.6`, `libm.so.6`, `libpthread.so.0`, ...).
- Symbols the indexes do not describe are left out of CIPI and resolved by the
  runtime fallback (process symbols, `--lib`, default CRT libraries).
  `compiler/src/data/link_wrappers.json` is the only remaining checked-in link
  metadata and only holds same-signature aliases (`snprintf -> _snprintf`).

`zig build gen-link-index` regenerates both tables on their own (it prints
entry/library/blob sizes) without building the rest of the compiler.

## Build and use

```bash
make compiler                                     # builds compiler/zig-out/bin/cinterp-cc
                                                  # and copies it to build/cinterp-cc
./build/cinterp-cc compile examples/hello.c -o build/hello.cib
./runtime/zig-out/bin/cinterp-run build/hello.cib
```

For cross targets use `--target`:

```bash
./build/cinterp-cc compile --target aarch64-linux examples/hello.c -o build/hello-arm64.cib
./build/cinterp-cc compile --target x86_64-windows examples/hello.c -o build/hello-win64.cib
./build/cinterp-cc compile --target i686-windows examples/hello.c -o build/hello-win32.cib
```

## Testing

Python is used only by the test, fuzz and benchmark harnesses. The compiler
itself has no Python dependency, and its external-symbol tables are generated
from the Zig toolchain by `zig build` (or `zig build gen-link-index`).

- `make test` builds the compiler and runs `scripts/test.sh`: runtime unit
  tests, `cd compiler && zig build test`, and the end-to-end integration cases.
- `make compiler-test` runs only `cd compiler && zig build test` (main, abi,
  ir, lower_ast, imports, link_index, link_wrappers, win_defs, libc_defs).
- There is no `make parser-parity` target any more: lowerer regressions are
  covered by the golden CIVM/CIPL comparisons described in
  [`ir-parser-differences.md`](ir-parser-differences.md).

Release tarballs (`make release-artifacts`): only
`cinterp-<VERSION>-sysv-x86_64` (Linux x86-64) ships the compiler —
`bin/cinterp-cc` plus the `bin/cinterp` wrapper script that execs it. The
`win64-x86_64`, `win32-x86` and `arm64` tarballs are runtime-only. See
`packaging/README.release.md.in`.
