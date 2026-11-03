# IR frontend regression notes

**Current state.** There is exactly one IR frontend: the typed AST under
`compiler/src/ir/` (`lexer.zig` → `parser.zig` → `ast.zig`, checked by
`verify.zig`) feeding `compiler/src/lower_ast.zig`, with CIPL call plans from
`compiler/src/abi.zig`. `compiler/src/main.zig` always parses through it. There
is no `--ir-parser` flag, no `legacy` parser, no `scripts/ir_parser_parity.py`
and no `make parser-parity` target any more.

This document is therefore *not* a comparison of two frontends. It records
(a) how IR leading/lowering regressions are caught today, and (b) — clearly
marked as history in [§Historical](#historical-string-parser-bugs-kept-as-regression-notes)
— the parsing bugs that the retired string parser had and that the AST path was
written to avoid.

## How regressions are caught today

All of the following run under `cd compiler && zig build test`
(`make compiler-test`, also part of `make test`):

| suite | location | what it pins |
| --- | --- | --- |
| IR parser tests | `compiler/src/ir/tests.zig` (22 tests) | module/type/global parsing, instruction and constant-expression forms, calls/intrinsics/attributes, malformed and mutated input returns positioned errors instead of panicking |
| parser fixtures | `compiler/src/ir/testdata/` | `clang18_x86_64.ll` parsed end to end |
| verifier tests | `compiler/src/ir/verify.zig` | triple/arch/OS/pointer-width mismatches and non-little-endian datalayouts are rejected |
| lowering goldens | `compiler/src/lower_ast.zig` (`golden_cases`) | full `CompileResult` text image (CIVM bytecode + CIPL plans + external symbols) for every ABI |
| ABI plan tests | `compiler/src/abi.zig` | SysV/Win64/Win32/AAPCS64 plan shapes, varargs, `conv` mapping |
| limit tests | `compiler/src/main.zig` | `validateLimits` rejects record sizes the runtime would truncate |

Golden files live in `compiler/src/testdata/lower_ast/golden/*.golden` (17
files) and are the canonical text image of every `CompileResult` field that
reaches CIVM/CIPL/CIPI: `clang18`, `control_flow`, `external_constant`,
`f32_literals`, `ffi_callback`, `ffi_qsort`, `global_name_in_initializer`,
`globals`, `hello`, `intrinsics`, `inttoptr_global`, `metadata_global`, `misc`,
`null_callee`, `null_callee_args`, `null_suffix_callee`, `structs`.

A regression shows up as a failing unit test, a failing golden diff, or a
property assertion — there is no second implementation to diff against, so a
golden change must be reviewed as a codegen change:

```bash
cd compiler && zig build test                       # all parser + lowering checks
cd compiler && CINTERP_WRITE_GOLDEN=1 \
  zig test src/lower_ast.zig --test-filter "write golden files"
```

Regenerate goldens only for an intentional codegen change. Do not "fix" a
failing golden by reintroducing one of the historical parser bugs below; add a
correctness test and update this document instead.

## Historical: string-parser bugs (kept as regression notes)

The notes below describe the retired text lowerer, which the typed AST replaced
and which has since been deleted. The counts are the historical measurement from
the parity harness (`scripts/ir_parser_parity.py`, removed with the string
parser) over `examples/`, `tests/csuite/` and the fetched gcc-torture /
llvm-regression corpus: 62 sources byte-identical, 10 differing. In every one of
the 10 the AST was correct and the string parser had a parsing bug, so the
string parser was removed without copying those behaviours. Each bug now has a
positive AST regression test in `compiler/src/lower_ast.zig` plus a golden.

### 1. Global `inttoptr` constant image (2 cases)

- `gcc-torture/execute/20021010-2` (`@global_vramPtr = global ptr inttoptr (i64 40960 to ptr)`)
- `llvm-regression-c/2003-06-16-InvalidInitializer` (`@Ptr = global ptr inttoptr (i64 8 to ptr)`)

Cause (historical): the string parser's `parseConstant` pointer branch located
`i64` in `inttoptr (i64 N to ptr)` and then sliced the remainder starting with a
leading space, so it parsed an empty integer and left the data image zero.

Current behaviour: the data image contains the little-endian pointer-sized value
from the `inttoptr` constant (`40960` / `8`).

Test: `global inttoptr initializer is materialized` (data image bytes plus
golden `inttoptr_global.golden`).

### 2. `external constant` declarations (6 cases)

- `gcc-torture/compile/20030708-1` (`@a = external constant [0 x i8]`)
- `gcc-torture/compile/20031124-1` (`@stop = external constant [0 x i8]`)
- `gcc-torture/compile/20040708-1` (three external mutex-method tables)
- `gcc-torture/compile/20110913-1` (`@__exp_deltatable`)
- `gcc-torture/compile/980816-1` (`@XtStrings`)
- `gcc-torture/compile/pr39983` (`@a = external constant [1 x i32]`)

Cause (historical): the string parser only recorded `external global` and
`external thread_local` declarations in the external-symbol table. An
`external constant` was dropped, so code taking its address lowered to constant
`0` and the symbol never reached CIPI.

Current behaviour: external constant declarations are added to `external_data`
and references lower with `OP_ADDR_EXTERN`, i.e. the symbol is a data import
(`CIPI` kind 1) and references use the imported address. These inputs are
compile-only, so executable behaviour is unchanged; the generated code is the
correct representation.

Test: `external constant declarations are imported and addressed`
(external-symbol list, `OP_ADDR_EXTERN`, golden `external_constant.golden`).

### 3. Global initializer mentioning another global (1 case)

- `gcc-torture/compile/pr19853`:
  `@test.const_test = internal constant %struct.test { ptr @global_int }`.

Cause (historical): the string parser searched the text after `=` for the word
`global` before `constant`. It matched the `global` inside the initializer's
`@global_int`, mis-parsed the type and dropped the whole `@test.const_test`
object.

Current layout: `@test.const_test` at 0, `@global_int` at 8, `@flag` at 12,
`@global_test` at 16 (24-byte image), with a relocation at offset 0 to
`@global_int`.

Test: `initializer mentioning a global name keeps the global allocated`
(layout, relocation, `OP_ADDR_CONST 12`, golden
`global_name_in_initializer.golden`).

### 4. Callee name ending in `null` (1 case)

- `gcc-torture/execute/pr49886`:
  `%call = call ptr @getnull()` followed by
  `call void @foo(ptr @gi, ptr %call)`.

Cause (historical): the string parser's `lowerCall` returned early when the
instruction text ended with `null()`. That was meant for a bare
`call void null()` but also matched `@getnull()`, so the call and its stored
result disappeared; the later call then read an uninitialized stack slot.

Current behaviour: the parsed callee token is compared, so `@getnull` is a
normal call and only a bare `null` callee is dropped. `CALL @getnull`, the
result store and `CALL @foo` with that result are all emitted.

Tests: `call result is kept when the callee name ends in null` and
`null callee calls lower to no instructions` (goldens
`null_suffix_callee.golden`, `null_callee.golden`, `null_callee_args.golden`).

### 5. LLVM linker metadata globals (formerly different, never allowlisted)

`gcc-torture/execute/pr78791` and
`llvm-regression-c/.../execute/20101011-1` used to differ because the AST
skipped `@llvm.compiler.used` while the string parser allocated 8 bytes of
zeroed data (and a larger `SET_MEM_TOP`). LLVM linker metadata globals are not
program objects and must not reserve VM storage, so the string parser was fixed
to skip `@llvm.*`/`@.llvm.*` globals too before it was removed.

Current behaviour: metadata globals reserve no VM storage; this is a supported
invariant, not a divergence.

Test: `llvm metadata globals do not reserve VM storage` (data-image length plus
golden `metadata_global.golden`).

## Commands referenced above

```bash
cd compiler && zig build test   # parser, verifier, ABI and lowering tests
make test                       # runtime + compiler unit tests + integration
make test-suites-full           # full C suite through the AST frontend
make test-suites-cross          # csuite + upstream smoke on Win64/Win32/ARM64
make c-testsuite                # 17 local cases in tests/csuite (scripts/c_testsuite.sh), host target only
make test-winapi                # Windows API imports under Wine (fails when nothing can run)
```
