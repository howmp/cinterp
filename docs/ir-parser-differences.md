# AST vs legacy IR frontend differences

`make parser-parity` compiles `examples/`, `tests/csuite/`, the former
metadata cases, and the fetched allowlist with both frontends. Current result:

```text
parser-parity: identical=62 known-diff=10 skipped=1 unexpected=0 stale=0
```

`skipped=1` is `examples/winapi.c`, which does not compile for the Linux target
under either frontend. `stale=0` means every allowlist entry still differs; an
allowlisted source that becomes byte-identical fails the gate so the exception
cannot rot.

## Allowlist policy

The allowlist contains only cases where the AST output is correct and the
legacy text parser is wrong. Matching legacy in these cases would mean
reproducing a legacy parsing bug, so the difference is kept, documented, and
covered by a targeted unit test instead. The script also records which CIB
sections, functions and imports each entry may change; a new section, function
or symbol fails as `WRONG DIFF SHAPE`.

The parity script (`scripts/ir_parser_parity.py`) is the authoritative list.

## Remaining differences (10)

### 1. Global `inttoptr` constant image (2 cases)

- `gcc-torture/execute/20021010-2` (`@global_vramPtr = global ptr inttoptr (i64 40960 to ptr)`)
- `llvm-regression-c/2003-06-16-InvalidInitializer` (`@Ptr = global ptr inttoptr (i64 8 to ptr)`)

Cause: the legacy `parseConstant` pointer branch locates `i64` in
`inttoptr (i64 N to ptr)` and then slices the remainder starting with a leading
space, so it parses an empty integer and leaves the data image zero. The AST
constant writer stores the encoded pointer value (`40960` / `8`).

Expected AST behavior: the data image contains the little-endian
pointer-sized value from the `inttoptr` constant. Expected legacy behavior:
the same object is zeroed.

Tests: `global inttoptr initializer is materialized` in
`compiler-zig/src/lower_ast.zig`.

### 2. `external constant` declarations (6 cases)

- `gcc-torture/compile/20030708-1` (`@a = external constant [0 x i8]`)
- `gcc-torture/compile/20031124-1` (`@stop = external constant [0 x i8]`)
- `gcc-torture/compile/20040708-1` (three external mutex-method tables)
- `gcc-torture/compile/20110913-1` (`@__exp_deltatable`)
- `gcc-torture/compile/980816-1` (`@XtStrings`)
- `gcc-torture/compile/pr39983` (`@a = external constant [1 x i32]`)

Cause: legacy `parseGlobals` only records `external global` and
`external thread_local` declarations in the external-symbol table. An
`external constant` is dropped, so any code that takes its address lowers to
constant `0` and the symbol never reaches CIPI. The AST adds external constant
declarations to `external_data` and lowers references with `OP_ADDR_EXTERN`.

Expected AST behavior: the symbol is a data import (`CIPI` kind 1) and
references use the imported address. Expected legacy behavior: address `0`,
no import. No executable behavior changes for the suite because these are
compile-only inputs; the generated code is still the correct representation.

Tests: `external constant declarations are imported and addressed` in
`compiler-zig/src/lower_ast.zig`.

### 3. Global initializer mentioning another global (1 case)

- `gcc-torture/compile/pr19853`:
  `@test.const_test = internal constant %struct.test { ptr @global_int }`.

Cause: legacy `parseGlobals` searches the text after `=` for the word
`global` before `constant`. It matches the `global` inside the initializer's
`@global_int`, mis-parses the type and drops the whole `@test.const_test`
object. The AST parses the declared type (`%struct.test`) and allocates the
object.

Expected AST layout: `@test.const_test` at 0, `@global_int` at 8, `@flag` at
12, `@global_test` at 16 (24-byte image), with a relocation at offset 0 to
`@global_int`. Expected legacy layout: the constant object is absent, so
`@flag` sits at 4.

Tests: `initializer mentioning a global name keeps the global allocated` in
`compiler-zig/src/lower_ast.zig`.

### 4. Callee name ending in `null` (1 case)

- `gcc-torture/execute/pr49886`:
  `%call = call ptr @getnull()` followed by
  `call void @foo(ptr @gi, ptr %call)`.

Cause: legacy `lowerCall` returns early when the instruction text ends with
`null()`. That was meant for a bare `call void null()` but also matches
`@getnull()`, so the call and its stored result disappear; the later call reads
the uninitialized stack slot. The AST compares the parsed callee token, so
`@getnull` is a normal call and only a bare `null` callee is dropped.

Expected AST behavior: `CALL @getnull`, store the result, then
`CALL @foo` with that result. Expected legacy behavior: only the `@foo` call.

Tests: `call result is kept when the callee name ends in null` in
`compiler-zig/src/lower_ast.zig`.

## Removed from the allowlist

`gcc-torture/execute/pr78791` and
`llvm-regression-c/.../execute/20101011-1` used to differ because the AST
skipped `@llvm.compiler.used` while legacy allocated 8 bytes of zeroed data
(and a larger `SET_MEM_TOP`). LLVM linker metadata globals are not program
objects and must not reserve VM storage. `lower.zig` now skips
`@llvm.*`/`@.llvm.*` globals the same way `lower_ast.buildGlobals` does, so both
frontends emit byte-identical CIBs. The two sources remain in the parity corpus
(not the allowlist) so a regression is reported as `UNEXPECTED`/`STALE`.

Test: `llvm metadata globals do not reserve VM storage in either frontend` in
`compiler-zig/src/lower_ast.zig`.

## Gates

```bash
make parser-parity                 # 62 identical / 10 known / 0 unexpected / 0 stale
cd compiler-zig && zig build test  # targeted AST-vs-legacy tests
make test-suites                   # standard, default AST frontend
make test-suites-full              # full, default AST frontend
```

The legacy parser remains available with `--ir-parser=legacy` for byte-level
comparison and rollback. Do not "fix" a parity failure by making the AST copy
the legacy behavior above; add a correctness test and a documented allowlist
entry instead.
