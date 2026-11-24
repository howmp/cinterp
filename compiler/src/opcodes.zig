pub const OP_RET: u8 = 0x01;
pub const OP_RET_VOID: u8 = 0x02;
pub const OP_LOAD_CONST_I64: u8 = 0x10;
pub const OP_ADD: u8 = 0x11;
pub const OP_SUB: u8 = 0x12;
pub const OP_MUL: u8 = 0x13;
pub const OP_XOR: u8 = 0x17;
pub const OP_DIV_S: u8 = 0x18;
pub const OP_DIV_U: u8 = 0x19;
pub const OP_REM_S: u8 = 0x1A;
pub const OP_REM_U: u8 = 0x1B;
pub const OP_AND: u8 = 0x1C;
pub const OP_OR: u8 = 0x1D;
pub const OP_SHL: u8 = 0x1E;
pub const OP_SHR_S: u8 = 0x1F;
pub const OP_LOAD_LOCAL: u8 = 0x20;
pub const OP_STORE_LOCAL: u8 = 0x21;
pub const OP_SHR_U: u8 = 0x24;
pub const OP_FPTOSI: u8 = 0x25;
pub const OP_SITOFP: u8 = 0x26;
pub const OP_FADD: u8 = 0x27;
pub const OP_FSUB: u8 = 0x28;
pub const OP_FMUL: u8 = 0x29;
pub const OP_FDIV: u8 = 0x2A;
pub const OP_FCMP: u8 = 0x2B;
pub const OP_FADD32: u8 = 0x2C;
pub const OP_FSUB32: u8 = 0x2D;
pub const OP_FMUL32: u8 = 0x2E;
pub const OP_FDIV32: u8 = 0x2F;
pub const OP_JMP: u8 = 0x30;
pub const OP_JZ: u8 = 0x31;
pub const OP_JNZ: u8 = 0x32;
pub const OP_CMP_EQ: u8 = 0x33;
pub const OP_CMP_LT: u8 = 0x34;
pub const OP_CMP_LT_U: u8 = 0x35;
pub const OP_FCMP32: u8 = 0x38;
pub const OP_FPEXT: u8 = 0x39;
pub const OP_FPTRUNC: u8 = 0x3A;
pub const OP_FPTOSI32: u8 = 0x3B;
pub const OP_SITOFP32: u8 = 0x3C;
pub const OP_CALL: u8 = 0x40;
pub const OP_FUNC_ADDR: u8 = 0x41;
pub const OP_CALL_INDIRECT: u8 = 0x42;
pub const OP_ALLOCA: u8 = 0x60;
pub const OP_DUP: u8 = 0x14;
pub const OP_SWAP: u8 = 0x16;
pub const OP_LOAD_MEM: u8 = 0x61;
pub const OP_STORE_MEM: u8 = 0x62;
pub const OP_MEMCPY: u8 = 0x63;
pub const OP_MEMSET: u8 = 0x64;
pub const OP_ADDR_CONST: u8 = 0x65;
pub const OP_SET_MEM_TOP: u8 = 0x66;
pub const OP_CALL_NATIVE: u8 = 0x70;
pub const OP_CALL_VARARG: u8 = 0x71;
pub const OP_CREATE_CALLBACK: u8 = 0x72;
pub const OP_F80_CONST: u8 = 0x73;
pub const OP_F80_ADD: u8 = 0x74;
pub const OP_F80_SUB: u8 = 0x75;
pub const OP_F80_MUL: u8 = 0x76;
pub const OP_F80_DIV: u8 = 0x77;
pub const OP_F80_CMP: u8 = 0x78;
pub const OP_F80_FROM_F64: u8 = 0x79;
pub const OP_F80_TO_F64: u8 = 0x7A;
pub const OP_F80_FROM_I64: u8 = 0x7B;
pub const OP_F80_TO_I64: u8 = 0x7C;
pub const OP_F80_FROM_F32: u8 = 0x7D;
pub const OP_F80_TO_F32: u8 = 0x7E;
pub const OP_F80_NEG: u8 = 0x7F;
pub const OP_F128_CONST: u8 = 0x80;
pub const OP_F128_ADD: u8 = 0x81;
pub const OP_F128_SUB: u8 = 0x82;
pub const OP_F128_MUL: u8 = 0x83;
pub const OP_F128_DIV: u8 = 0x84;
pub const OP_F128_CMP: u8 = 0x85;
pub const OP_F128_NEG: u8 = 0x86;
pub const OP_F128_FROM_F64: u8 = 0x87;
pub const OP_F128_TO_F64: u8 = 0x88;
pub const OP_F128_FROM_I64: u8 = 0x89;
pub const OP_F128_TO_I64: u8 = 0x8A;
pub const OP_F128_FROM_F32: u8 = 0x8B;
pub const OP_F128_TO_F32: u8 = 0x8C;
pub const OP_ALLOCA_DYN: u8 = 0x8D;
pub const OP_FPTOUI: u8 = 0x8E;
pub const OP_UITOFP: u8 = 0x8F;
pub const OP_FPTOUI32: u8 = 0x90;
pub const OP_UITOFP32: u8 = 0x91;
pub const OP_F80_TO_U64: u8 = 0x92;
pub const OP_F80_FROM_U64: u8 = 0x93;
pub const OP_F128_TO_U64: u8 = 0x94;
pub const OP_F128_FROM_U64: u8 = 0x95;
pub const OP_ADDR_EXTERN: u8 = 0x96;
pub const OP_SETJMP: u8 = 0x97;
pub const OP_LONGJMP: u8 = 0x98;
pub const OP_CALL_VARIADIC: u8 = 0x99;
pub const OP_VA_START: u8 = 0x9A;
pub const OP_VA_COPY: u8 = 0x9B;
pub const OP_CALL_INDIRECT_NATIVE: u8 = 0x9C;
pub const OP_STACKSAVE: u8 = 0x9D;
pub const OP_STACKRESTORE: u8 = 0x9E;
pub const OP_ALLOCA_ALIGNED: u8 = 0x9F;
pub const OP_ALLOCA_DYN_ALIGN: u8 = 0xA0;
pub const OP_CALL_VARIADIC_TYPED: u8 = 0xA1;
pub const OP_FPCLASS: u8 = 0xA2;
/// `OP_CALLBACK_ACQUIRE u16 plan_index, u16 func_index`: register `func_index`
/// as a native callback with `plan_index` and push the trampoline address
/// (NULL when the runtime pool is exhausted). Emitted for the compiler builtin
/// `__ci_callback_acquire` from the force-included `data/cinterp_callbacks.h`.
pub const OP_CALLBACK_ACQUIRE: u8 = 0xA3;
/// `OP_CALLBACK_RELEASE`: pop a trampoline address pushed by
/// `OP_CALLBACK_ACQUIRE`, release its slot and push the status
/// (0 = released, negative = unknown/already released/still executing).
/// Emitted for the compiler builtin `__ci_callback_release`.
pub const OP_CALLBACK_RELEASE: u8 = 0xA4;
/// `LOAD_CONST_POOL u32 offset`: push eight bytes from the CIPC data blob.
pub const OP_LOAD_CONST_POOL: u8 = 0xA5;
/// `NORMALIZE u8 param`: reduce the top of stack to an 8/16/32-bit integer.
/// `param & 3` selects the width (0/1/2 = 8/16/32 bits) and bit 7 selects sign
/// extension; without it the value is zero-extended.
pub const OP_NORMALIZE: u8 = 0xA6;
/// `FMA`: pop `c`, `b`, `a` and push the fused `a*b + c` (double). Emitted for
/// `llvm.fmuladd.f64`, which otherwise became one native libm call per use.
pub const OP_FMA: u8 = 0xA7;
/// `FMA32`: single-precision `llvm.fmuladd.f32`.
pub const OP_FMA32: u8 = 0xA8;
