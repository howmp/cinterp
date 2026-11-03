# LLVM IR subset contract

`cinterp-cc` consumes LLVM IR **text** emitted by `zig cc -S -emit-llvm -O0`
(Zig 0.13 → clang 18.1.x). The typed parser/verifier accepts only the subset the
CIVM lowerer implements; anything else is a compile-time diagnostic, not a
silent fallback. The typed AST is the only IR frontend; the former string
parser has been removed.

## Module

- `source_filename`, `target datalayout`, `target triple`
- numbered/named type definitions
- globals: `global`, `constant`, `private`, `internal`, `external`,
  `thread_local`, `alias`/`ifunc` as opaque records
- function declarations and definitions, attribute groups, metadata records
  (metadata is retained only for diagnostics/opaque records)
- comdats, module flags and uselists are opaque records

## Types

`void`, `iN`, `half`, `bfloat`, `float`, `double`, `x86_fp80`, `fp128`,
`ppc_fp128`, `ptr` (opaque/addrspace), arrays, vectors, literal and named
structs (packed/unpacked), function types. The lowerer materializes the subset
needed by C pipelines: scalars, pointers, arrays, structs, f32/f64/f80/f128.

## Values and constants

Locals, globals, integer/float literals (decimal, hex, `0xK`/`0xL`),
`null`, `undef`, `poison`, `zeroinitializer`, C strings, aggregate constants,
and constant expressions: GEP, `ptrtoint`, `inttoptr`, `bitcast`, integer
binary ops, trunc/zext/sext, icmp/fcmp. Multi-index GEP constant expressions
preserve every index; f128 literals are normalized to the canonical byte order.

## Instructions

`alloca`, `load`, `store`, `getelementptr`, `phi`, `br`, `switch`, `ret`,
`unreachable`, `select`, `extractvalue`, direct/indirect/tail `call`,
`icmp`, `fcmp`, integer/floating binary ops, `fneg`, `trunc`, `zext`, `sext`,
`fptosi`, `fptoui`, `sitofp`, `uitofp`, `fpext`, `fptrunc`, `bitcast`,
`inttoptr`, `ptrtoint`.

Supported `llvm.*` intrinsics are the ones implemented by the lowerer:
`memcpy`, `memset`, `dbg.*`, `lifetime.*`, `va_start/va_copy/va_end`,
`stacksave/stackrestore`, `frameaddress`, `ptrmask`, `is.fpclass`,
`fmuladd`, `fabs`, `sqrt`, rounding, `sin/cos/exp2/log2/pow`, `fmin/fmax`,
`copysign`, `fma`.

Explicitly unsupported (compile-time error): vectors in executable values,
`insertvalue`, `extractelement`, `insertelement`, `shufflevector`, `freeze`,
`va_arg` as an instruction, atomics/`atomicrmw`/`cmpxchg`, `fence`, `invoke`,
`resume`, `landingpad`, `indirectbr`, `callbr` bodies, and unknown intrinsics.

## Verification

`src/ir/verify.zig` checks that the module triple's architecture/OS/pointer
width matches `--target`, and that the module is little-endian. The parser
reports `line:column` for unsupported/ill-formed IR. Runtime/CI gates:

```bash
cd compiler-zig && zig build test
make test-suites-full
make test-suites-cross
```
