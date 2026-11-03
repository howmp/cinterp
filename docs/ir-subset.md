# LLVM IR subset contract

`cinterp-cc` consumes LLVM IR **text** emitted by `zig cc -S -emit-llvm -O0`
(Zig 0.13 → clang 18.1.x). The typed parser/verifier accepts only the subset the
CIVM lowerer implements: instructions the parser does not implement become
`line:column` compile-time diagnostics rather than silent fallbacks (the few
partially-modelled exceptions are listed below). The typed AST
(`compiler/src/ir/{lexer,ast,parser,verify}.zig`) is the only IR frontend;
there is no `--ir-parser` option and no second/legacy parser.

## Module

- `source_filename`, `target datalayout`, `target triple`
- numbered/named type definitions, including `opaque` bodies
- globals: `global`, `constant`, `private`, `internal`, `external`,
  `thread_local`, `alias`/`ifunc` as opaque records
- function declarations and definitions, attribute groups, metadata records
  (metadata is retained only for diagnostics/opaque records)
- comdats, module flags and uselists are opaque records
- `@llvm.*` / `@.llvm.*` globals (`llvm.compiler.used`, `llvm.used`, ...) do not
  take VM storage

## Types

`void`, `iN`, `half`, `bfloat`, `float`, `double`, `x86_fp80`, `fp128`,
`ppc_fp128`, `ptr` (opaque, addrspace), arrays, vectors, literal and named
structs (packed/unpacked), function types. The lowerer materializes the subset
needed by C pipelines: scalars, pointers, arrays, structs, f32/f64/f80/f128.
`half`/`bfloat` are parsed and have a layout, but the C frontend does not emit
arithmetic on them.

## Values and constants

Locals, globals, integer/float literals (decimal, hex, `0xK`/`0xL`),
`null`, `undef`, `poison`, `zeroinitializer`, C strings, aggregate constants,
and constant expressions: GEP, `ptrtoint`, `inttoptr`, `bitcast`,
`addrspacecast`, integer binary ops, trunc/zext/sext, icmp/fcmp. Multi-index GEP
constant expressions preserve every index; f128 literals are normalized to the
canonical byte order.

## Instructions

`alloca`, `load`, `store`, `getelementptr`, `phi`, `br`, `switch`, `ret`,
`unreachable`, `select`, `extractvalue`, direct/indirect/tail `call`
(`call`, `tail`, `musttail`, `notail`), `icmp`, `fcmp`, integer/floating binary
ops (`add sub mul sdiv udiv srem urem and or xor shl lshr ashr fadd fsub fmul
fdiv`), `fneg`, `freeze`, `trunc`, `zext`, `sext`, `fptosi`, `fptoui`,
`sitofp`, `uitofp`, `fpext`, `fptrunc`, `bitcast`, `inttoptr`, `ptrtoint`,
`addrspacecast`.

`freeze` lowers as an identity (it stores the operand into the result slot).
`select`/`extractvalue`/`fneg` are implemented as instructions; they are only
rejected when they appear as a *constant expression* operand, which clang does
not produce for C.

Supported `llvm.*` intrinsics are the ones implemented by the lowerer:

| intrinsic | lowering |
| --- | --- |
| `llvm.memcpy.*`, `llvm.memset.*` | `OP_MEMCPY` / `OP_MEMSET` |
| `llvm.dbg.*`, `llvm.lifetime.*` | dropped (no debug info) |
| `llvm.va_start.p0`, `llvm.va_copy.p0`, `llvm.va_end.p0` | `OP_VA_START` / `OP_VA_COPY` / no-op |
| `llvm.stacksave`, `llvm.stackrestore` | `OP_STACKSAVE` / `OP_STACKRESTORE` |
| `llvm.frameaddress` | constant `0` |
| `llvm.ptrmask` | `and` |
| `llvm.is.fpclass` | `OP_FPCLASS` |
| `llvm.fmuladd.{f32,f64,f80,f128}` | `fmaf` / `fma` / `fmal` |
| `llvm.fabs`, `llvm.sqrt`, `round`, `ceil`, `floor`, `trunc`, `nearbyint`, `rint` | matching libm entry (`fabsf`/`fabs`/`fabsl`, ...) |
| `llvm.sin`, `llvm.cos`, `llvm.exp2`, `llvm.log2`, `llvm.pow`, `llvm.fmin`, `llvm.fmax` | matching libm entry |
| `llvm.copysign` | `copysignf` / `copysign` / `copysignl` |

Only `llvm.fmuladd` is mapped (to `fmaf`/`fma`/`fmal`). There is no `llvm.fma.*`
entry, so it would take the unknown-intrinsic path described below.

Rejected at parse time (compile-time error, `line:column` diagnostic):
`insertvalue`, `extractelement`, `insertelement`, `shufflevector`, `va_arg` as
an instruction, `atomicrmw`, `cmpxchg`, `fence`, `invoke`, `resume`,
`landingpad`, `indirectbr`, and any other mnemonic not listed above
(`compiler/src/ir/parser.zig`, `parseInstruction`).

Rejected later by the lowerer: `frem` (parsed, no CIVM opcode),
`asm`-callee calls (`error.UnsupportedInstruction`).

Accepted but partially modelled, so worth knowing:

- `callbr` parses and lowers as a plain `call`; its label list is parsed into
  `Call.callbr_targets` and then ignored, because the runtime has no indirect
  branch. clang does not emit `callbr` for C.
- Unknown `llvm.*` intrinsics are not special-cased: they keep their name, become
  an ordinary external call plan and fail at run time (unresolved symbol) rather
  than at compile time.
- GNU vector extensions are outside the subset. Vector-typed values are only
  moved as blobs (the store path copies them with `OP_MEMCPY`, like arrays and
  structs), and `getelementptr` accepts only the literal index `0` into a
  vector; vector arithmetic and the element/shuffle instructions are not
  implemented.
- Global `fp128`/`ppc_fp128`/`half`/`bfloat` scalar initializers and global
  vector initializers are left zeroed (a preserved compatibility quirk of the
  constant writer, not a correctness claim).

## Verification

`compiler/src/ir/verify.zig` checks that the module triple's architecture/OS and
the pointer width derived from it match `--target`, and that the datalayout is
little-endian (`e-...`). The parser reports `line:column` for unsupported or
ill-formed IR (`compiler/src/main.zig`, `lowerModule`).

Runtime/CI gates:

```bash
cd compiler && zig build test   # parser fixtures, verifier tests, lowering goldens
make test-suites-full           # full local suite (4319 passed / 202 skipped;
                                # 2372 of the passes are compile-only)
make test-suites-cross          # csuite + upstream smoke on Win64/Win32/ARM64
```

See [`ir-parser-differences.md`](ir-parser-differences.md) for the golden-file
regression scheme and the historical parser bug notes.
