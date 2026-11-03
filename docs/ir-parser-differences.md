# IR frontend correctness notes (former AST/string-parser differences)

The Zig compiler used to have two IR frontends: the original text-lowering path
in `src/lower.zig` and the typed AST path in `src/ir/` + `src/lower_ast.zig`.
The AST became the default, and the string parser has now been removed:
`--ir-parser=legacy|ast` and `make parser-parity` no longer exist. There is one
frontend (`src/ir/parser.zig` → `src/lower_ast.zig`, with ABI plans in
`src/abi.zig`).

While both frontends existed, `scripts/ir_parser_parity.py` compared them over
`examples/`, `tests/csuite/` and the fetched gcc-torture/llvm-regression corpus.
62 sources were byte-identical and 10 differed. In every one of those 10 cases
the AST was correct and the string parser had a parsing bug; matching the string
parser would have meant reproducing the bug. `src/lower.zig` was therefore
removed without copying those behaviours.

The 10 former cases are still covered as AST correctness tests in
`compiler/src/lower_ast.zig`, with expected `CompileResult` goldens under
`compiler/src/testdata/lower_ast/golden/`. A regression now shows up as a
failing golden or property assertion rather than as a parity diff.

## 1. Global `inttoptr` constant image (2 cases)

- `gcc-torture/execute/20021010-2` (`@global_vramPtr = global ptr inttoptr (i64 40960 to ptr)`)
- `llvm-regression-c/2003-06-16-InvalidInitializer` (`@Ptr = global ptr inttoptr (i64 8 to ptr)`)

Cause: the string parser's `parseConstant` pointer branch located `i64` in
`inttoptr (i64 N to ptr)` and then sliced the remainder starting with a leading
space, so it parsed an empty integer and left the data image zero.

AST behavior: the data image contains the little-endian pointer-sized value from
the `inttoptr` constant (`40960` / `8`).

Tests: `global inttoptr initializer is materialized` in
`compiler/src/lower_ast.zig` (data image bytes plus golden
`inttoptr_global.golden`).

## 2. `external constant` declarations (6 cases)

- `gcc-torture/compile/20030708-1` (`@a = external constant [0 x i8]`)
- `gcc-torture/compile/20031124-1` (`@stop = external constant [0 x i8]`)
- `gcc-torture/compile/20040708-1` (three external mutex-method tables)
- `gcc-torture/compile/20110913-1` (`@__exp_deltatable`)
- `gcc-torture/compile/980816-1` (`@XtStrings`)
- `gcc-torture/compile/pr39983` (`@a = external constant [1 x i32]`)

Cause: the string parser only recorded `external global` and
`external thread_local` declarations in the external-symbol table. An
`external constant` was dropped, so code taking its address lowered to constant
`0` and the symbol never reached CIPI.

AST behavior: external constant declarations are added to `external_data` and
references lower with `OP_ADDR_EXTERN`, i.e. the symbol is a data import
(`CIPI` kind 1) and references use the imported address. These inputs are
compile-only, so executable behavior is unchanged; the generated code is the
correct representation.

Tests: `external constant declarations are imported and addressed` in
`compiler/src/lower_ast.zig` (external-symbol list, `OP_ADDR_EXTERN`, golden
`external_constant.golden`).

## 3. Global initializer mentioning another global (1 case)

- `gcc-torture/compile/pr19853`:
  `@test.const_test = internal constant %struct.test { ptr @global_int }`.

Cause: the string parser searched the text after `=` for the word `global`
before `constant`. It matched the `global` inside the initializer's
`@global_int`, mis-parsed the type and dropped the whole `@test.const_test`
object.

AST layout: `@test.const_test` at 0, `@global_int` at 8, `@flag` at 12,
`@global_test` at 16 (24-byte image), with a relocation at offset 0 to
`@global_int`.

Tests: `initializer mentioning a global name keeps the global allocated` in
`compiler/src/lower_ast.zig` (layout, relocation, `OP_ADDR_CONST 12`, golden
`global_name_in_initializer.golden`).

## 4. Callee name ending in `null` (1 case)

- `gcc-torture/execute/pr49886`:
  `%call = call ptr @getnull()` followed by
  `call void @foo(ptr @gi, ptr %call)`.

Cause: the string parser's `lowerCall` returned early when the instruction text
ended with `null()`. That was meant for a bare `call void null()` but also
matched `@getnull()`, so the call and its stored result disappeared; the later
call then read an uninitialized stack slot.

AST behavior: the parsed callee token is compared, so `@getnull` is a normal
call and only a bare `null` callee is dropped. `CALL @getnull`, the result store
and `CALL @foo` with that result are all emitted.

Tests: `call result is kept when the callee name ends in null` and
`null callee calls lower to no instructions` in `compiler/src/lower_ast.zig`
(goldens `null_suffix_callee.golden`, `null_callee.golden`,
`null_callee_args.golden`).

## LLVM linker metadata globals (formerly different, never allowlisted)

`gcc-torture/execute/pr78791` and
`llvm-regression-c/.../execute/20101011-1` used to differ because the AST
skipped `@llvm.compiler.used` while the string parser allocated 8 bytes of
zeroed data (and a larger `SET_MEM_TOP`). LLVM linker metadata globals are not
program objects and must not reserve VM storage, so the string parser was fixed
to skip `@llvm.*`/`@.llvm.*` globals too before it was removed.

Test: `llvm metadata globals do not reserve VM storage` in
`compiler/src/lower_ast.zig` (data-image length plus golden
`metadata_global.golden`).

## Tests and gates

```bash
cd compiler && zig build test   # unit tests incl. golden CIVM/CIPL comparisons
make test-suites                    # standard suite, AST frontend
make test-suites-full               # full suite, AST frontend
make c-testsuite                    # four-target csuite
make test-winapi                    # Windows API imports under Wine
```

Golden files are the canonical text image of every `CompileResult` field that
reaches CIVM/CIPL/CIPI. Regenerate them only for an intentional codegen change,
and review the diff:

```bash
cd compiler && CINTERP_WRITE_GOLDEN=1 \
  zig test src/lower_ast.zig --test-filter "write golden files"
```

Do not "fix" a failing golden by reintroducing one of the string-parser bugs
above; add a correctness test and update this document instead.
