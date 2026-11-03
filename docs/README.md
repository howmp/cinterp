# Documentation index

Reference material for the `cinterp` compiler (`compiler/`) and runtime
(`runtime/`). The code is the source of truth; these pages describe the
contracts the code implements and the commands that verify them.

| document | what it covers |
| --- | --- |
| [`cib.md`](cib.md) | `.cib` package format: `CIPKG` v2/v1 container, `CIVM` bytecode, `CIPL` call plans, `CIPM` target header, `CIPI` link metadata, and runtime status codes |
| [`embedding.md`](embedding.md) | embedding `libcinterp` in a C host: build/install, the `ci_vm_*` C ABI, error lifecycle, callback and memory-limit notes |
| [`compatibility.md`](compatibility.md) | versioning and compatibility contract: single `VERSION` source, component versions, N−1 read guarantee, C ABI version, compiler/runtime pairing, deprecation policy |
| [`ir-subset.md`](ir-subset.md) | the LLVM IR subset `cinterp-cc` accepts: module forms, types, constants, instructions, supported `llvm.*` intrinsics, and what is rejected with a diagnostic |
| [`zig-frontend.md`](zig-frontend.md) | the Zig frontend: how `cinterp-cc` drives `zig cc`, the `compiler/src/ir` → `lower_ast.zig` pipeline, CLI flags, calling-convention/plan-dedup/limit contracts, external-symbol tables, release tarball contents |
| [`ir-parser-differences.md`](ir-parser-differences.md) | IR frontend regression coverage (parser tests, lowering goldens) plus clearly marked historical notes on the retired string parser's bugs |

`cib.md` and `compatibility.md` are written in Chinese; the other pages are in
English.

See also the repository [`README.md`](../README.md) (build, usage, support
matrix) and [`dev.md`](../dev.md) (developer guide).
