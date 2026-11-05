const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const abi = @import("ffi/abi.zig");
const plan_loader = @import("ffi/plan_loader.zig");
const platform = @import("ffi/platform.zig");
const native = @import("ffi/native.zig");
const link_loader = @import("ffi/link_loader.zig");

const debug_errors = builtin.mode == .Debug;

pub const MAX_FUNCS: usize = 512;
pub const MAX_NAME: usize = 128;
pub const MAX_STACK: usize = 8192;
pub const MAX_FRAMES: usize = 512;
pub const MAX_MODULE: usize = 2097152;
pub const DEFAULT_MEMORY: usize = 1024 * 1024;
pub const MAX_MEMORY: usize = 16 * 1024 * 1024;

pub const OP_RET: u8 = 0x01;
pub const OP_RET_VOID: u8 = 0x02;
pub const OP_LOAD_CONST_I64: u8 = 0x10;
pub const OP_ADD: u8 = 0x11;
pub const OP_SUB: u8 = 0x12;
pub const OP_MUL: u8 = 0x13;
pub const OP_DUP: u8 = 0x14;
pub const OP_POP: u8 = 0x15;
pub const OP_SWAP: u8 = 0x16;
pub const OP_XOR: u8 = 0x17;
pub const OP_DIV_S: u8 = 0x18;
pub const OP_DIV_U: u8 = 0x19;
pub const OP_REM_S: u8 = 0x1A;
pub const OP_REM_U: u8 = 0x1B;
pub const OP_AND: u8 = 0x1C;
pub const OP_OR: u8 = 0x1D;
pub const OP_SHL: u8 = 0x1E;
pub const OP_SHR_S: u8 = 0x1F;
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
pub const OP_FCMP32: u8 = 0x38;
pub const OP_FPEXT: u8 = 0x39;
pub const OP_FPTRUNC: u8 = 0x3A;
pub const OP_FPTOSI32: u8 = 0x3B;
pub const OP_SITOFP32: u8 = 0x3C;
pub const OP_CMP_LT_U: u8 = 0x35;
pub const OP_LOAD_LOCAL: u8 = 0x20;
pub const OP_STORE_LOCAL: u8 = 0x21;
pub const OP_JMP: u8 = 0x30;
pub const OP_JZ: u8 = 0x31;
pub const OP_JNZ: u8 = 0x32;
pub const OP_CMP_EQ: u8 = 0x33;
pub const OP_CMP_LT: u8 = 0x34;
pub const OP_CALL: u8 = 0x40;
pub const OP_FUNC_ADDR: u8 = 0x41;
pub const OP_CALL_INDIRECT: u8 = 0x42;
pub const OP_ALLOCA: u8 = 0x60;
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
/// `OP_CALLBACK_ACQUIRE u16 plan_index, u16 func_index`: bind `func_index` to
/// the native callback plan `plan_index` in a free process-wide trampoline slot
/// and push the trampoline address (0 when every slot is live or retired).
/// Emitted for `ci_callback_acquire` from the force-included
/// `cinterp_callbacks.h`. Unlike `OP_CREATE_CALLBACK` it reserves no
/// compile-time local slot: the CIB decides when to give the slot back with
/// `OP_CALLBACK_RELEASE`, which is what lets one VM create more than 256
/// callbacks over its lifetime.
pub const OP_CALLBACK_ACQUIRE: u8 = 0xA3;
/// `OP_CALLBACK_RELEASE`: pop the trampoline address `OP_CALLBACK_ACQUIRE`
/// produced, release the slot this VM owns for it and push the status:
/// `CI_OK` (0), `CI_E_BUSY` while a dispatch is still inside the callback, or
/// `CI_E_INVALID_ARGUMENT` when this VM owns no slot for the address (already
/// released, never a trampoline, or another VM's). Emitted for
/// `ci_callback_release`; the C contract is that the pointer is dead after a
/// successful release, so the reused slot cannot be reached through it.
pub const OP_CALLBACK_RELEASE: u8 = 0xA4;

fn floatToI64Safe(x: anytype) !i64 {
    const xf: f64 = @floatCast(x);
    if (!std.math.isFinite(xf) or xf < -9223372036854775808.0 or xf >= 9223372036854775808.0)
        return error.InvalidArgument;
    return @intFromFloat(x);
}

fn floatToU64Safe(x: anytype) !u64 {
    const xf: f64 = @floatCast(x);
    if (!std.math.isFinite(xf) or xf <= -1.0 or xf >= 18446744073709551616.0)
        return error.InvalidArgument;
    return @intFromFloat(x);
}

fn fpClass(bits: u128, width: u8) u16 {
    var sign: u1 = 0;
    var exp: u128 = 0;
    var frac: u128 = 0;
    if (width == 32) {
        const b: u32 = @truncate(bits);
        sign = @truncate(b >> 31);
        exp = @as(u128, b >> 23) & 0xff;
        frac = @as(u128, b & 0x7fffff);
    } else if (width == 64) {
        const b: u64 = @truncate(bits);
        sign = @truncate(b >> 63);
        exp = @as(u128, b >> 52) & 0x7ff;
        frac = @as(u128, b & 0xfffffffffffff);
    } else if (width == 80) {
        const b: u80 = @truncate(bits);
        sign = @truncate(b >> 79);
        exp = @as(u128, b >> 64) & 0x7fff;
        frac = @as(u128, b & 0xffffffffffffffff);
    } else {
        const b: u128 = bits;
        sign = @truncate(b >> 127);
        exp = (b >> 112) & 0x7fff;
        frac = b & ((@as(u128, 1) << 112) - 1);
    }
    if (exp == 0 and frac == 0) return @as(u16, 1) << (if (sign == 1) 9 else 8);
    if (exp == 0) return @as(u16, 1) << (if (sign == 1) 7 else 6);
    if (exp == ((@as(u128, 1) << (if (width == 32) @as(u7, 8) else if (width == 64) @as(u7, 11) else if (width == 80) @as(u7, 15) else @as(u7, 15))) - 1)) {
        if (frac != 0) {
            const quiet_bit: u128 = @as(u128, 1) << (if (width == 32) @as(u7, 22) else if (width == 64) @as(u7, 51) else if (width == 80) @as(u7, 63) else @as(u7, 111));
            return @as(u16, 1) << (if ((frac & quiet_bit) != 0) @as(u4, 0) else @as(u4, 1));
        }
        return @as(u16, 1) << (if (sign == 1) 3 else 2);
    }
    return @as(u16, 1) << (if (sign == 1) 5 else 4);
}

fn fpClassValue(v: Value, kind: u8) u16 {
    return switch (kind) {
        0 => fpClass(@as(u128, @as(u32, @truncate(v.u))), 32),
        1 => fpClass(@as(u128, v.u), 64),
        2 => blk: {
            const p: *align(1) const u80 = @ptrFromInt(addressFromBits(v.i));
            break :blk fpClass(@as(u128, p.*), 80);
        },
        3 => blk: {
            const p: *align(1) const u128 = @ptrFromInt(addressFromBits(v.i));
            break :blk fpClass(p.*, 128);
        },
        else => 0,
    };
}

fn readU32At(bytes: []const u8, off: usize) u32 {
    return @as(u32, bytes[off]) |
        (@as(u32, bytes[off + 1]) << 8) |
        (@as(u32, bytes[off + 2]) << 16) |
        (@as(u32, bytes[off + 3]) << 24);
}

pub const Value = extern union {
    i: i64,
    u: u64,
};

pub const Function = struct {
    name: []const u8,
    param_count: u16,
    local_count: u16,
    code: []const u8,
};

pub const Frame = struct {
    return_ip: usize,
    base: usize,
    func: usize,
    mem_mark: usize,
    va_base: usize,
    va_named: usize,
    va_count: usize,
    va_types: [64]u8 = [_]u8{0} ** 64,
    va_sizes: [64]u16 = [_]u16{0} ** 64,
    va_type_count: u8 = 0,
};

const JumpEntry = struct {
    buf: u64 = 0,
    ip: usize = 0,
    base: usize = 0,
    func: usize = 0,
    sp: usize = 0,
    frames: usize = 0,
    mem_top: usize = 0,
    slot: u16 = 0,
    valid: bool = false,
};

const CallbackEntry = struct {
    func: usize,
    plan: abi.CallPlan,
};

/// Per-VM execution state: who may run this VM, and whether it is going away.
///
/// `VM` is copied by value by `checkpoint`/`rollback` (a transactional load
/// works on a snapshot) and zeroed wholesale by `initMachine`, so the lock
/// cannot live inside the struct: a copied `std.Thread.Mutex` would be a second
/// lock over the same state, and the `initMachine` memset would silently forget
/// a held lock. `VM.run_state` is therefore a heap pointer that every copy of
/// the VM shares.
pub const RunState = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    /// Thread holding the exclusive execution right, or null when the VM is
    /// idle.
    owner: ?std.Thread.Id = null,
    /// Number of execution contexts the owner holds. Nested runs are rejected
    /// rather than stacked, so this is 0 or 1; it is tracked anyway so a
    /// deferred destroy only fires on the outermost run.
    depth: u32 = 0,
    /// Set once destruction started: no new run or load may begin, so a
    /// destroy cannot race a fresh execution.
    closing: bool = false,
    /// `ci_vm_destroy` was called by the thread that is running this VM (for
    /// example from a callback). Freeing it there would corrupt the frame that
    /// is still executing, so the outermost run destroys the VM on its way out.
    destroy_pending: bool = false,

    pub const EnterError = error{ Busy, NestedRun, VmDestroyed };

    /// `.idle` means the caller won the right to free the VM. `.closing` means
    /// another thread already took it (so the caller must not free it).
    pub const CloseResult = enum { idle, busy, deferred, closing };

    /// True while any thread is executing this VM. Used by `ci_vm_busy`.
    pub fn isBusy(self: *RunState) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.owner != null;
    }

    /// Take the exclusive execution right for the calling thread.
    ///
    /// Another thread gets `error.Busy`. The owning thread itself gets
    /// `error.NestedRun`: re-entering `ci_vm_run` from a callback would clear
    /// the value stack and memory of the run that called it. A VM that is
    /// already being destroyed gets `error.VmDestroyed`.
    pub fn enter(self: *RunState) EnterError!void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.closing) return error.VmDestroyed;
        if (self.owner) |owner| {
            if (owner == std.Thread.getCurrentId()) return error.NestedRun;
            return error.Busy;
        }
        self.owner = std.Thread.getCurrentId();
        self.depth = 1;
    }

    /// Release the execution right taken by `enter`. Returns true when a
    /// destroy requested from inside this run has to be completed by the
    /// caller, which must not touch the VM after that.
    pub fn leave(self: *RunState) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.depth > 0) self.depth -= 1;
        self.owner = null;
        self.cond.broadcast();
        return self.destroy_pending and self.depth == 0;
    }

    /// Mark the VM as closing because a destroy was requested by the thread
    /// that is currently running it; the outermost run frees it.
    pub fn requestDeferredDestroy(self: *RunState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closing = true;
        self.destroy_pending = true;
    }

    /// Close the VM for destruction without waiting. `.deferred` means the
    /// calling thread owns the VM right now, so the destroy must happen when
    /// that run returns; the caller decides whether to defer it.
    pub fn tryClose(self: *RunState) CloseResult {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.owner) |owner| {
            if (owner == std.Thread.getCurrentId()) return .deferred;
            return .busy;
        }
        if (self.closing) return .closing;
        self.closing = true;
        return .idle;
    }

    /// Close the VM for destruction, waiting for another thread's run to
    /// finish. Never blocks when the calling thread owns the VM.
    pub fn closeAndWait(self: *RunState) CloseResult {
        self.mutex.lock();
        if (self.closing) {
            // Another thread is already destroying this VM; it will free it.
            self.mutex.unlock();
            return .closing;
        }
        if (self.owner) |owner| {
            if (owner == std.Thread.getCurrentId()) {
                self.mutex.unlock();
                return .deferred;
            }
            self.closing = true;
            while (self.owner != null) self.cond.wait(&self.mutex);
            self.mutex.unlock();
            return .idle;
        }
        self.closing = true;
        self.mutex.unlock();
        return .idle;
    }
};

// Callback trampolines have a fixed slot in assembly. Slots are allocated
// process-wide but entries and VM ownership are per-VM. Two lifetimes share the
// 256 slots:
//
//   * automatic slots (`OP_CREATE_CALLBACK`, the compiler's `@cb` path) stay
//     bound to their VM until it is destroyed or its plans are replaced, and
//     are then retired for good so a retained host function pointer can never
//     dispatch into a recycled VM;
//   * explicit slots (`OP_CALLBACK_ACQUIRE`/`OP_CALLBACK_RELEASE`, the
//     `ci_callback_acquire`/`ci_callback_release` macros) go back to the free
//     set when the CIB releases them, so a repeated run does not exhaust the
//     pool. The C contract covers the reuse: a pointer passed to release must
//     not be called again, and an unreleased slot is retired with its VM.
var callback_owners: [256]?*VM = [_]?*VM{null} ** 256;
var callback_retired: [256]bool = [_]bool{false} ** 256;
/// Number of `ci_callback_dispatch` calls currently inside (or failing fast
/// for) each slot. A slot cannot be released or reused while this is non-zero:
/// the dispatch reads the plan metadata the release would invalidate.
var callback_slot_active: [256]u32 = [_]u32{0} ** 256;
var callback_mutex: std.Thread.Mutex = .{};
var callback_cond: std.Thread.Condition = .{};

fn f32FromValue(v: Value) f32 {
    const bits: u32 = @truncate(@as(u64, @bitCast(v.i)));
    return @bitCast(bits);
}

fn compareF128(a: f128, b: f128, pred: u8) bool {
    const unordered = std.math.isNan(a) or std.math.isNan(b);
    return switch (pred) {
        0 => !unordered and a == b,
        1 => !unordered and a != b,
        2 => !unordered and a < b,
        3 => !unordered and a <= b,
        4 => !unordered and a > b,
        5 => !unordered and a >= b,
        6 => !unordered,
        7 => unordered,
        8 => unordered or a == b,
        9 => unordered or a > b,
        10 => unordered or a >= b,
        11 => unordered or a < b,
        12 => unordered or a <= b,
        13 => unordered or a != b,
        else => false,
    };
}

fn compareF80(a: f80, b: f80, pred: u8) bool {
    const unordered = std.math.isNan(a) or std.math.isNan(b);
    return switch (pred) {
        0 => !unordered and a == b,
        1 => !unordered and a != b,
        2 => !unordered and a < b,
        3 => !unordered and a <= b,
        4 => !unordered and a > b,
        5 => !unordered and a >= b,
        6 => !unordered,
        7 => unordered,
        8 => unordered or a == b,
        9 => unordered or a > b,
        10 => unordered or a >= b,
        11 => unordered or a < b,
        12 => unordered or a <= b,
        13 => unordered or a != b,
        else => false,
    };
}

fn compareFloats(a: f64, b: f64, pred: u8) bool {
    const unordered = std.math.isNan(a) or std.math.isNan(b);
    return switch (pred) {
        0 => !unordered and a == b,
        1 => !unordered and a != b,
        2 => !unordered and a < b,
        3 => !unordered and a <= b,
        4 => !unordered and a > b,
        5 => !unordered and a >= b,
        6 => !unordered,
        7 => unordered,
        8 => unordered or a == b,
        9 => unordered or a > b,
        10 => unordered or a >= b,
        11 => unordered or a < b,
        12 => unordered or a <= b,
        13 => unordered or a != b,
        else => false,
    };
}

/// Upper bound on the spellings `symbolCandidates` can produce for one name.
pub const MAX_SYMBOL_CANDIDATES: usize = 4;

/// Fill `out` with the spellings to try for a native external symbol, in
/// priority order, and return how many were written.
///
/// Every candidate is a suffix of `name` (or `name` itself), so the caller can
/// null-terminate the slices as they are without allocating.
///
/// Win32 stdcall/fastcall names reach the runtime in the spelling the IR
/// frontend printed: the LLVM asm name keeps the textual `\01` marker
/// (`\01_c_std_add3@12`, `\01@fast_add@12`), and MinGW's PE export table then
/// drops the stdcall leading underscore while keeping the `@N` byte count
/// (`c_std_add3@12`, `@fast_add@12`). Lookup therefore retries the name without
/// the escape marker and without the leading underscore; the `@N` suffix is
/// preserved because it is part of the export name. `decorated` enables the
/// Win32 escape stripping; the leading-underscore retry applies on every
/// platform so `_snprintf`/`snprintf` style aliases stay reachable.
pub fn symbolCandidates(name: []const u8, decorated: bool, out: *[MAX_SYMBOL_CANDIDATES][]const u8) usize {
    var count = addCandidate(out, 0, name);
    var bare = name;
    if (decorated) {
        const undecorated = stripSymbolEscape(name);
        if (undecorated.len != name.len) {
            bare = undecorated;
            count = addCandidate(out, count, undecorated);
        }
    }
    if (bare.len > 1 and bare[0] == '_') count = addCandidate(out, count, bare[1..]);
    return count;
}

/// Drop the Win32 decoration prefix the IR frontend prints: the textual `\01`
/// escape (the frontend escapes control bytes as `\XX`) and any raw control
/// byte. Returns a suffix of `name`; nothing is copied.
fn stripSymbolEscape(name: []const u8) []const u8 {
    var value = name;
    if (value.len >= 3 and value[0] == '\\' and std.ascii.isHex(value[1]) and std.ascii.isHex(value[2]))
        value = value[3..];
    while (value.len > 0 and (value[0] == 1 or value[0] == 0x1f)) value = value[1..];
    return value;
}

fn isByteCount(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |char| {
        if (!std.ascii.isDigit(char)) return false;
    }
    return true;
}

/// i686 Windows calling convention carried by a decorated external name:
/// 2 = fastcall (`@name@N`), 1 = stdcall (`_name@N`, or the MinGW export
/// spelling `name@N`), 0 = cdecl/unknown.
///
/// The COFF decoration is the only ABI marker an i686 import carries, and the
/// compiler fills `CallPlan.conv` only for symbols it indexes from the MinGW
/// `.def` tables, so the runtime recovers the convention from the name rather
/// than special-casing individual symbols.
pub fn win32ConvFromName(name: []const u8) u8 {
    const bare = stripSymbolEscape(name);
    const at = std.mem.lastIndexOfScalar(u8, bare, '@') orelse return 0;
    if (at == 0 or !isByteCount(bare[at + 1 ..])) return 0;
    return if (bare[0] == '@') 2 else 1;
}

fn addCandidate(out: *[MAX_SYMBOL_CANDIDATES][]const u8, count: usize, value: []const u8) usize {
    if (value.len == 0 or count == out.len) return count;
    for (out[0..count]) |existing| {
        if (existing.ptr == value.ptr and existing.len == value.len) return count;
    }
    out[count] = value;
    return count + 1;
}

pub const VM = struct {
    module_buf: []u8 = &.{},
    module_len: usize = 0,
    functions: [MAX_FUNCS]Function = undefined,
    func_count: usize = 0,
    values: []Value = &.{},
    sp: usize = 0,
    mem: []u8 = &.{},
    mem_top: usize = 0,
    /// First byte of the argv/envp area `buildArgArea` carved out of `mem`;
    /// zero means no area is reserved and the whole region is allocatable.
    arg_area_start: usize = 0,
    plan_store: ?*plan_loader.Store = null,
    imports: link_loader.Table = .{},
    import_handles: [link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS]?*anyopaque = [_]?*anyopaque{null} ** (link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS),
    /// Data imports and function imports use different index spaces. Keep
    /// separate handle caches so data entry 0 and plan 0 cannot share a slot.
    data_import_handles: [link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS]?*anyopaque = [_]?*anyopaque{null} ** (link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS),
    default_handles: [8]?*anyopaque = [_]?*anyopaque{null} ** 8,
    default_count: usize = 0,
    default_loaded: bool = false,
    libraries: [8]?*anyopaque = [_]?*anyopaque{null} ** 8,
    library_count: usize = 0,
    symbol_buf: [256]u8 = undefined,
    path_buf: [256]u8 = undefined,
    frames: [MAX_FRAMES]Frame = undefined,
    frame_count: usize = 0,
    jumps: [32]JumpEntry = [_]JumpEntry{.{}} ** 32,
    /// Last successful run result. A failed run leaves it untouched.
    result: i64 = 0,
    stack_limit: usize = MAX_STACK,
    last_error: [128]u8 = undefined,
    last_error_code: c_int = 0,
    /// Execution lock state. Null for stack-allocated test VMs and for the
    /// scratch VM a transactional `loadPackage` validates in: those are never
    /// shared between threads, so they need no locking.
    run_state: ?*RunState = null,
    callback_entries: [256]?CallbackEntry = [_]?CallbackEntry{null} ** 256,
    callback_slots: [256]i16 = [_]i16{-1} ** 256,
    callback_active: usize = 0,
    callback_destroying: bool = false,
    /// Last failed `ci_callback_dispatch` for this VM as a `CI_E_*` category
    /// (0 = none). Written under `callback_mutex`, reported by
    /// `ci_vm_callback_error` and cleared by `ci_vm_clear_error`, so a host
    /// whose native library swallows the callback result can still see that a
    /// dispatch was skipped.
    callback_error: c_int = 0,
    native_targets: [256]usize = [_]usize{0} ** 256,
    native_target_count: usize = 0,
    native_plan_cache: [plan_loader.MAX_PLANS]?*const anyopaque = [_]?*const anyopaque{null} ** plan_loader.MAX_PLANS,

    /// Upper bound for allocations in linear memory. Once the argv/envp area is
    /// built it sits at the top of `mem` and must not be overwritten.
    fn memLimit(self: *const VM) usize {
        return if (self.arg_area_start != 0) self.arg_area_start else self.mem.len;
    }

    fn clearNativeCache(self: *VM) void {
        for (&self.native_plan_cache) |*cached| cached.* = null;
    }

    fn resetResolverCaches(self: *VM) void {
        self.import_handles = [_]?*anyopaque{null} ** (link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS);
        self.data_import_handles = [_]?*anyopaque{null} ** (link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS);
        self.native_target_count = 0;
        self.clearNativeCache();
    }

    pub fn setError(self: *VM, msg: []const u8) void {
        const n = @min(msg.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..n], msg[0..n]);
        self.last_error[n] = 0;
    }

    pub fn clearError(self: *VM) void {
        self.last_error[0] = 0;
        self.last_error_code = 0;
    }

    fn checkpoint(self: *VM) !*VM {
        const backup = try std.heap.page_allocator.create(VM);
        backup.* = self.*;
        return backup;
    }

    fn rollback(self: *VM, backup: *VM) void {
        if (self.plan_store) |current| {
            if (current != backup.plan_store) current.deinit(std.heap.page_allocator);
        }
        self.* = backup.*;
        std.heap.page_allocator.destroy(backup);
    }

    fn commitCheckpoint(backup: *VM) void {
        std.heap.page_allocator.destroy(backup);
    }

    pub fn loadPlans(self: *VM, bytes: []const u8) !void {
        const new_store = try plan_loader.decode(std.heap.page_allocator, bytes);
        if (new_store.abi_id != platform.abi_id) {
            new_store.deinit(std.heap.page_allocator);
            return error.BadAbi;
        }
        if (self.plan_store) |old| {
            // Callback plans point into the old store. Retire their trampolines
            // before freeing it so a retained host callback cannot dispatch
            // through dangling plan metadata.
            self.releaseCallbacks();
            old.deinit(std.heap.page_allocator);
        }
        self.plan_store = new_store;
        // Provider handles and resolved targets belong to the replaced plans.
        self.resetResolverCaches();
    }

    /// Retire every trampoline slot this VM still owns, whether it came from an
    /// automatic `OP_CREATE_CALLBACK` or an explicit `OP_CALLBACK_ACQUIRE`.
    ///
    /// The scan is over the process-wide slots, not over `callback_slots`:
    /// explicitly acquired slots have no compile-time local index, so an
    /// unreleased one would otherwise never be retired and its trampoline could
    /// later dispatch into a recycled VM. Slots the CIB released are owned by
    /// nobody and are deliberately left reusable.
    fn releaseCallbacks(self: *VM) void {
        callback_mutex.lock();
        // A dispatch can hold no execution right while it fails fast, but it
        // keeps `callback_active` raised while it reads the plan metadata this
        // function is about to invalidate (the caller frees `plan_store`
        // afterwards). Dispatches never wait for the execution right, so this
        // bounded wait cannot deadlock.
        while (self.callback_active > 0) callback_cond.wait(&callback_mutex);
        for (0..callback_owners.len) |g| {
            if (callback_owners[g] == self) {
                callback_owners[g] = null;
                callback_retired[g] = true;
            }
            self.callback_entries[g] = null;
        }
        for (0..self.callback_slots.len) |slot| self.callback_slots[slot] = -1;
        callback_mutex.unlock();
    }

    /// `OP_CALLBACK_ACQUIRE`: take a free process-wide trampoline slot for
    /// `func_index` and `plan_index`, remember it on this VM and return the
    /// trampoline address, or 0 when the pool has no free slot left.
    ///
    /// A failed plan validation is an error (the program is malformed), while
    /// an exhausted pool is the documented null return the CIB checks for.
    fn acquireCallback(self: *VM, plan_index: u16, func_index: u16) !i64 {
        const fidx: usize = func_index;
        if (fidx >= self.func_count) return error.BadFunction;
        const store = self.plan_store orelse return error.NoPlans;
        const p = store.planAt(plan_index) orelse return error.BadPlan;
        // Reject a plan the platform cannot marshal now, instead of silently
        // dropping the callback when native code invokes it.
        const plan = store.callPlan(p);
        try platform.validate(plan);
        if (platform.abi_kind == .win32 and !platform.win32CallbackSupported(plan))
            return error.UnsupportedCallback;

        callback_mutex.lock();
        defer callback_mutex.unlock();
        if (self.callback_destroying) return 0;
        for (0..callback_owners.len) |g| {
            if (callback_retired[g] or callback_owners[g] != null) continue;
            const addr = platform.callbackTable(g) orelse continue;
            self.callback_entries[g] = .{ .func = fidx, .plan = plan };
            callback_owners[g] = self;
            const addr64: u64 = @intCast(@intFromPtr(addr));
            return @bitCast(addr64);
        }
        return 0;
    }

    /// `OP_CALLBACK_RELEASE`: give back the trampoline slot this VM owns for
    /// `addr`. Returns `CI_OK`, `CI_E_BUSY` while a dispatch is still inside
    /// the callback (the caller retries once it returns; blocking here could
    /// deadlock with the running thread), or `CI_E_INVALID_ARGUMENT` when this
    /// VM owns no slot for `addr`.
    fn releaseCallback(self: *VM, addr: usize) i64 {
        var status: i64 = CI_E_INVALID_ARGUMENT;
        callback_mutex.lock();
        defer callback_mutex.unlock();
        for (0..callback_owners.len) |g| {
            if (callback_owners[g] != self) continue;
            if (self.callback_entries[g] == null) continue;
            const table = platform.callbackTable(g) orelse continue;
            if (@intFromPtr(table) != addr) continue;
            if (callback_slot_active[g] > 0) {
                status = CI_E_BUSY;
                break;
            }
            callback_owners[g] = null;
            // Not retired: the next acquire may reuse the slot, and the C
            // contract says the old pointer is dead after this release.
            callback_retired[g] = false;
            self.callback_entries[g] = null;
            // An automatic slot can be released too when its trampoline leaked
            // out of `@cb`. Drop any local mapping so the next
            // `OP_CREATE_CALLBACK` allocates a fresh slot instead of finding
            // this one unowned.
            for (0..self.callback_slots.len) |local| {
                if (self.callback_slots[local] == @as(i16, @intCast(g)))
                    self.callback_slots[local] = -1;
            }
            status = CI_OK;
            break;
        }
        return status;
    }

    fn freePlans(self: *VM) void {
        if (self.plan_store) |old| {
            self.releaseCallbacks();
            old.deinit(std.heap.page_allocator);
            self.plan_store = null;
        }
        self.resetResolverCaches();
    }

    pub fn loadLibrary(self: *VM, path: []const u8) !void {
        if (path.len >= self.symbol_buf.len) return error.PathTooLong;
        if (self.library_count >= self.libraries.len) return error.TooManyLibraries;
        @memcpy(self.symbol_buf[0..path.len], path);
        self.symbol_buf[path.len] = 0;
        const cpath: [*:0]const u8 = @ptrCast(&self.symbol_buf[0]);
        const handle = native.load(cpath) orelse return error.LibraryNotFound;
        self.libraries[self.library_count] = handle;
        self.library_count += 1;
        // A new `--lib` handle takes precedence over resolved targets.
        self.clearNativeCache();
    }

    fn loadPackageInPlace(self: *VM, bytes: []const u8) !void {
        if (!platform.libc_supported) return error.UnsupportedLibc;
        if (bytes.len < 18) return error.BadPackage;
        if (!std.mem.eql(u8, bytes[0..5], "CIPKG")) return error.BadPackageMagic;
        if (bytes[5] != 3) return error.BadPackageVersion;
        const module_len = readU32At(bytes, 6);
        const plan_len = readU32At(bytes, 10);
        const import_len = readU32At(bytes, 14);
        const m: usize = module_len;
        const p: usize = plan_len;
        const im: usize = import_len;
        if (18 + m + p + im != bytes.len) return error.BadPackageSize;
        const import_bytes = bytes[18 + m + p ..];
        const imports = try link_loader.decodeImports(import_bytes);
        try self.loadModuleBytesInPlace(bytes[18 .. 18 + m]);
        if (p != 0) try self.loadPlans(bytes[18 + m .. 18 + m + p]);
        try self.validateImports(&imports);
        self.imports = imports;
    }

    pub fn loadPackage(self: *VM, bytes: []const u8) !void {
        // Validate the complete package in a scratch VM before touching this
        // VM. The scratch VM owns the new plan store and module buffer; only a
        // validated package is transferred.
        const scratch = try std.heap.page_allocator.create(VM);
        initMachine(scratch);
        scratch.loadPackageInPlace(bytes) catch |err| {
            scratch.freePlans();
            scratch.freeModule();
            std.heap.page_allocator.destroy(scratch);
            return err;
        };

        self.freePlans();
        const old_module = self.module_buf;

        self.module_buf = scratch.module_buf;
        self.module_len = scratch.module_len;
        @memcpy(self.functions[0..scratch.func_count], scratch.functions[0..scratch.func_count]);
        self.func_count = scratch.func_count;
        self.plan_store = scratch.plan_store;
        scratch.plan_store = null;
        self.imports = scratch.imports;
        // Explicit `--lib` handles outlive a package swap; per-plan provider
        // handles and resolved native targets do not, because they are keyed by
        // the replaced plan indexes.
        self.resetResolverCaches();

        scratch.module_buf = &.{};
        scratch.module_len = 0;
        scratch.func_count = 0;
        std.heap.page_allocator.destroy(scratch);
        if (old_module.len > 0) std.heap.page_allocator.free(old_module);
    }

    fn validateImports(self: *VM, imports: *const link_loader.Table) !void {
        if (imports.count == 0) return;
        const total: usize = imports.count;
        if (self.plan_store == null) {
            // A package with no FFI plans can still carry external-data
            // entries for OP_ADDR_EXTERN.
            var data_i: usize = 0;
            while (data_i < total) : (data_i += 1) {
                if (imports.entries[data_i].plan_index != 0xffff)
                    return error.BadImportPlan;
            }
            return;
        }
        const store = self.plan_store.?;
        var i: usize = 0;
        while (i < total) : (i += 1) {
            const entry = &imports.entries[i];
            if (entry.plan_index != 0xffff and entry.plan_index >= store.count)
                return error.BadImportPlan;
            if (entry.provider_count == 0 and (entry.flags & 1) != 0)
                return error.BadImportProvider;
            if (entry.arch_mask != 0) {
                const bit: u8 = switch (platform.arch_id) {
                    1 => 1,
                    2 => 2,
                    3 => 4,
                    else => 0,
                };
                if ((entry.arch_mask & bit) == 0) return error.ImportArchMismatch;
            }
            if (entry.min_os != 0 and platform.os_id == 2) {
                const current = native.windowsVersion();
                if (current != 0 and current < entry.min_os) return error.ImportUnavailable;
            }
        }
    }

    /// Lazily load the platform's default C/CRT libraries once per VM. These
    /// are the last search tier after the process namespace and `--lib`
    /// handles: they keep `--no-auto-link` packages and symbols
    /// missing from the build-time indexes working.
    fn defaultHandles(self: *VM) []?*anyopaque {
        if (!self.default_loaded) {
            self.default_loaded = true;
            for (native.defaultLibraries()) |name| {
                if (self.default_count >= self.default_handles.len) break;
                self.default_handles[self.default_count] = native.load(name);
                self.default_count += 1;
            }
        }
        return self.default_handles[0..self.default_count];
    }

    /// Search tiers in order: process namespace, explicit `--lib` handles,
    /// platform default libraries. `.libraries` stops after the `--lib`
    /// handles, for callers where they are the user's override.
    const SearchTier = enum { libraries, all };

    fn searchSymbolAt(self: *VM, cname: [*:0]const u8, tier: SearchTier) ?*const anyopaque {
        if (tier == .all) {
            if (native.symbol(null, cname)) |sym| return sym;
        }
        var li: usize = self.library_count;
        while (li > 0) {
            li -= 1;
            if (self.libraries[li]) |handle| {
                if (native.symbol(handle, cname)) |sym| return sym;
            }
        }
        if (tier == .all) {
            for (self.defaultHandles()) |maybe_handle| {
                if (maybe_handle) |handle| {
                    if (native.symbol(handle, cname)) |sym| return sym;
                }
            }
        }
        return null;
    }

    /// Resolve `name` against the requested tiers, retrying the spellings
    /// `symbolCandidates` derives (Win32 stdcall/fastcall exports, the stdcall
    /// leading underscore). Keeping one entry point makes the fallback apply to
    /// `--lib` handles, the process namespace and the default libraries alike.
    /// `name` must not point into `symbol_buf`, which holds the candidates.
    fn searchSymbol(self: *VM, name: []const u8, tier: SearchTier) ?*const anyopaque {
        var candidates: [MAX_SYMBOL_CANDIDATES][]const u8 = undefined;
        const count = symbolCandidates(name, platform.os_id == 2, &candidates);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const candidate = candidates[i];
            if (candidate.len >= self.symbol_buf.len) continue;
            @memcpy(self.symbol_buf[0..candidate.len], candidate);
            self.symbol_buf[candidate.len] = 0;
            const cname: [*:0]const u8 = @ptrCast(&self.symbol_buf[0]);
            if (self.searchSymbolAt(cname, tier)) |sym| return sym;
        }
        return null;
    }

    fn cachedProvider(self: *VM, cache: []?*anyopaque, slot: usize, name: []const u8) !?*anyopaque {
        if (slot >= cache.len) return null;
        if (cache[slot]) |handle| return handle;
        if (name.len >= self.path_buf.len) return error.PathTooLong;
        @memcpy(self.path_buf[0..name.len], name);
        self.path_buf[name.len] = 0;
        const cpath: [*:0]const u8 = @ptrCast(&self.path_buf[0]);
        const handle = native.load(cpath) orelse return null;
        cache[slot] = handle;
        return handle;
    }

    fn loadImported(self: *VM, plan_index: u16, entry_index: usize, entry: *const link_loader.ImportEntry) !?*const anyopaque {
        _ = entry_index;
        var pi: usize = 0;
        const count: usize = entry.provider_count;
        while (pi < count) : (pi += 1) {
            const provider = &entry.providers[pi];
            if (provider.kind != 0 and provider.kind != 1) continue;
            const lib_name = provider.name[0..provider.name_len];
            if (lib_name.len == 0 or std.mem.indexOfAny(u8, lib_name, "/\\:") != null) continue;
            const slot = @as(usize, plan_index) * link_loader.MAX_PROVIDERS + pi;
            const handle = try self.cachedProvider(&self.import_handles, slot, lib_name) orelse continue;
            if (provider.ordinal != 0) {
                if (native.symbolOrdinal(handle, provider.ordinal)) |sym| return sym;
                continue;
            }
            const sym_name = provider.symbol[0..provider.symbol_len];
            if (sym_name.len >= self.symbol_buf.len) return error.SymbolTooLong;
            @memcpy(self.symbol_buf[0..sym_name.len], sym_name);
            self.symbol_buf[sym_name.len] = 0;
            const cname: [*:0]const u8 = @ptrCast(&self.symbol_buf[0]);
            if (native.symbol(handle, cname)) |sym| return sym;
        }
        return null;
    }

    fn loadImportedData(self: *VM, entry_index: usize, entry: *const link_loader.ImportEntry) !?*const anyopaque {
        const name = entry.name[0..entry.name_len];
        // Explicit --lib libraries first, including the decorated spellings.
        if (self.searchSymbol(name, .libraries)) |sym| return sym;
        var pi: usize = 0;
        while (pi < entry.provider_count) : (pi += 1) {
            const provider = &entry.providers[pi];
            if (provider.kind != 0 and provider.kind != 1) continue;
            const lib_name = provider.name[0..provider.name_len];
            if (lib_name.len == 0 or std.mem.indexOfAny(u8, lib_name, "/\\:") != null) continue;
            const slot = entry_index * link_loader.MAX_PROVIDERS + pi;
            const handle = try self.cachedProvider(&self.data_import_handles, slot, lib_name) orelse continue;
            const sym_name = provider.symbol[0..provider.symbol_len];
            if (sym_name.len >= self.symbol_buf.len) return error.SymbolTooLong;
            @memcpy(self.symbol_buf[0..sym_name.len], sym_name);
            self.symbol_buf[sym_name.len] = 0;
            const cname: [*:0]const u8 = @ptrCast(&self.symbol_buf[0]);
            if (native.symbol(handle, cname)) |sym| return sym;
        }
        // Fallback: process/global namespace and CRT.
        if (self.searchSymbol(name, .all)) |sym| return sym;
        return null;
    }

    fn resolveData(self: *VM, entry_index: usize) !*const anyopaque {
        const entry = self.imports.at(entry_index) orelse return error.BadImportPlan;
        if (entry.kind != 1) return error.BadImportPlan;
        if (try self.loadImportedData(entry_index, entry)) |sym| return sym;
        return error.SymbolNotFound;
    }

    fn recordNativeTarget(self: *VM, addr: usize) !void {
        if (addr == 0) return;
        var i: usize = 0;
        while (i < self.native_target_count) : (i += 1) {
            if (self.native_targets[i] == addr) return;
        }
        if (self.native_target_count >= self.native_targets.len) return error.TooManyNativeTargets;
        self.native_targets[self.native_target_count] = addr;
        self.native_target_count += 1;
    }

    fn isNativeTarget(self: *const VM, addr: usize) bool {
        var i: usize = 0;
        while (i < self.native_target_count) : (i += 1) {
            if (self.native_targets[i] == addr) return true;
        }
        return false;
    }

    fn resolveNative(self: *VM, plan_index: u16, name: []const u8) !*const anyopaque {
        if (name.len >= self.symbol_buf.len) return error.SymbolTooLong;

        if (self.imports.indexOfPlan(plan_index)) |entry_index| {
            const entry = &self.imports.entries[entry_index];
            // Explicit --lib libraries are the user's override and win over CIB providers.
            if ((entry.flags & 0x8) != 0) {
                if (self.searchSymbol(name, .libraries)) |sym| return sym;
            }
            if (try self.loadImported(plan_index, entry_index, entry)) |sym| return sym;
            if ((entry.flags & 0x4) == 0) return error.SymbolNotFound;
        }

        if (self.searchSymbol(name, .all)) |sym| return sym;
        return error.SymbolNotFound;
    }

    /// Resolve a plan's native symbol, remembering the target per plan index so
    /// repeated `CALL_NATIVE` in a loop skips symbol lookup. The cache is
    /// dropped whenever the plans or the `--lib` handles change.
    fn resolvedNative(self: *VM, plan_index: u16, name: []const u8) !*const anyopaque {
        const slot: usize = plan_index;
        if (slot >= self.native_plan_cache.len) return self.resolveNative(plan_index, name);
        if (self.native_plan_cache[slot]) |cached| return cached;
        const target = try self.resolveNative(plan_index, name);
        self.native_plan_cache[slot] = target;
        return target;
    }

    fn invokeFfi(self: *VM, plan: abi.CallPlan, target: *const anyopaque) !void {
        try platform.validate(plan);
        var arg_block: [4096]u8 align(16) = [_]u8{0} ** 4096;
        var sret_ptr: ?*anyopaque = null;

        var i: usize = plan.args.len;
        while (i > 0) {
            i -= 1;
            const arg = plan.args[i];
            const loc = arg.locs[0];
            if (loc.kind == .sret) {
                const v = try self.pop();
                sret_ptr = @ptrCast(pointerFromU64(v.u));
                continue;
            }
            const off: usize = @intCast(loc.offset);
            if (arg.is_struct) {
                const v = try self.pop();
                if (v.u == 0) return error.NullStruct;
                const src: [*]const u8 = @ptrCast(pointerFromU64(v.u));
                const n: usize = @intCast(arg.size);
                @memcpy(arg_block[off..][0..n], src[0..n]);
            } else {
                const v = try self.pop();
                const n: usize = @intCast(loc.size);
                const bits: u64 = v.u;
                @memcpy(arg_block[off..][0..n], std.mem.asBytes(&bits)[0..n]);
            }
        }

        var stack_buf: [4096]u8 align(16) = [_]u8{0} ** 4096;
        var frame: platform.Frame = std.mem.zeroes(platform.Frame);
        var sret_dest = sret_ptr;
        if (plan.sret and sret_dest == null) {
            const rs: usize = @intCast(plan.ret_size);
            if (rs > platform.block_size) return error.ReturnTooLarge;
            const block = try self.allocTemp(rs, 16);
            sret_dest = @ptrCast(block.ptr);
        }
        platform.configure(&frame, plan, &stack_buf, sret_dest);
        platform.marshal(&frame, plan, &arg_block, &stack_buf);
        platform.invoke(&frame, target);

        var ret_block: [4096]u8 align(16) = [_]u8{0} ** 4096;
        platform.readRet(&frame, plan, &ret_block);

        if (plan.sret) {
            // sret calls in C are void; the callee wrote through the caller's pointer.
        } else if (plan.ret_locs.len == 1) {
            const loc = plan.ret_locs[0];
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            // A result that fits in one machine word travels as the value
            // itself; wide results (an `st0`/`long double` return, aggregates)
            // are copied into a caller-frame temporary and surfaced as a
            // pointer the bytecode loads from. Note `st0` is also the i686
            // return file for narrow `float`/`double` values, which are plain
            // words.
            if (n > 8) {
                const rs: usize = @intCast(plan.ret_size);
                if (rs > platform.block_size) return error.ReturnTooLarge;
                const block = try self.allocTemp(rs, 16);
                @memcpy(block[0..rs], ret_block[off..][0..rs]);
                const addr: u64 = @intCast(@intFromPtr(block.ptr));
                try self.push(.{ .i = @bitCast(addr) });
            } else {
                var bits: u64 = 0;
                @memcpy(std.mem.asBytes(&bits)[0..n], ret_block[off..][0..n]);
                try self.push(.{ .i = @bitCast(bits) });
            }
        } else if (plan.ret_locs.len > 1) {
            const rs: usize = @intCast(plan.ret_size);
            if (rs > platform.block_size) return error.ReturnTooLarge;
            const block = try self.allocTemp(rs, 16);
            @memcpy(block[0..rs], ret_block[0..rs]);
            const ret_addr: u64 = @intCast(@intFromPtr(block.ptr));
            try self.push(.{ .i = @bitCast(ret_addr) });
        } else {
            try self.push(.{ .i = 0 });
        }
    }

    fn loadModuleBytesInPlace(self: *VM, bytes: []const u8) !void {
        if (bytes.len > MAX_MODULE) return error.ModuleTooLarge;
        const buf = try std.heap.page_allocator.alloc(u8, bytes.len);
        errdefer std.heap.page_allocator.free(buf);
        @memcpy(buf, bytes);
        try self.parseModuleBytes(buf);
        const old = self.module_buf;
        self.module_buf = buf;
        self.module_len = bytes.len;
        if (old.len > 0) std.heap.page_allocator.free(old);
    }

    fn freeModule(self: *VM) void {
        if (self.module_buf.len > 0) {
            std.heap.page_allocator.free(self.module_buf);
            self.module_buf = &.{};
        }
        self.module_len = 0;
        self.func_count = 0;
    }

    fn ensureRuntimeBuffers(self: *VM) !void {
        if (self.values.len == 0) {
            const limit = if (self.stack_limit == 0) MAX_STACK else self.stack_limit;
            self.values = try std.heap.page_allocator.alloc(Value, limit);
            self.stack_limit = limit;
        }
        if (self.mem.len == 0) {
            self.mem = try std.heap.page_allocator.alignedAlloc(u8, 32, DEFAULT_MEMORY);
        }
    }

    pub fn loadModuleBytes(self: *VM, bytes: []const u8) !void {
        const backup = try self.checkpoint();
        self.loadModuleBytesInPlace(bytes) catch |err| {
            self.rollback(backup);
            return err;
        };
        commitCheckpoint(backup);
    }

    fn parseModuleBytes(self: *VM, data: []const u8) !void {
        var r = Reader{ .data = data };
        const magic = try r.take(4);
        if (!std.mem.eql(u8, magic, "CIVM")) return error.BadMagic;
        const version = try r.readU8();
        if (version != 1) return error.BadVersion;
        const arch = try r.readU8();
        if (arch != 1) return error.BadArch;
        const count = try r.readU16();
        _ = try r.readU16();
        const n: usize = count;
        if (n > MAX_FUNCS) return error.TooManyFunctions;
        self.func_count = n;

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const name_len = try r.readU8();
            const nl: usize = name_len;
            if (nl > MAX_NAME) return error.NameTooLong;
            const name = try r.take(nl);
            const params = try r.readU16();
            const locals = try r.readU16();
            const code_len = try r.readU32();
            if (locals < params) return error.BadLocals;
            const code = try r.take(code_len);
            self.functions[i] = .{
                .name = name,
                .param_count = params,
                .local_count = locals,
                .code = code,
            };
        }
        if (r.pos != r.data.len) return error.TrailingBytes;
    }

    pub fn runEntry(self: *VM, name: []const u8) !i64 {
        const default_args = [_][]const u8{"cinterp"};
        return self.runEntryArgs(name, &default_args);
    }

    pub fn runEntryArgs(self: *VM, name: []const u8, cargs: []const []const u8) !i64 {
        try self.ensureRuntimeBuffers();
        var fi: usize = 0;
        while (fi < self.func_count) : (fi += 1) {
            if (std.mem.eql(u8, self.functions[fi].name, name)) break;
        }
        if (fi == self.func_count) return error.EntryNotFound;

        // Every run starts from a fresh image. `result` is deliberately not
        // reset here: `ci_vm_result` reports the last *successful* run, so a
        // run that fails must leave the previous value in place.
        self.resetRunImage();

        const entry_fn = self.functions[fi];
        const entry_locals: usize = entry_fn.local_count;
        self.sp = entry_locals;
        if (self.sp > self.stack_limit) return error.StackOverflow;

        const argc, const argv_addr, const envp_addr = try self.buildArgArea(cargs);
        if (entry_fn.param_count > 0) self.values[0] = .{ .u = @intCast(argc) };
        if (entry_fn.param_count > 1) self.values[1] = .{ .u = argv_addr };
        if (entry_fn.param_count > 2) self.values[2] = .{ .u = envp_addr };

        return self.executeLoop(fi, 0, 0);
    }

    /// Drop everything that must not survive from one run into the next: the
    /// value stack, linear memory and the alloca bump pointer are cleared,
    /// `setjmp` targets recorded by an earlier run are forgotten (a `longjmp`
    /// must never resume into code that is no longer running), and resolved
    /// native targets are re-registered per run. The native *plan* cache is
    /// kept, because a plan index still names the same symbol.
    fn resetRunImage(self: *VM) void {
        for (0..self.values.len) |i| self.values[i] = .{ .i = 0 };
        self.sp = 0;
        self.mem_top = 0;
        self.arg_area_start = 0;
        @memset(self.mem, 0);
        self.frame_count = 0;
        for (&self.jumps) |*entry| entry.* = .{};
        self.native_target_count = 0;
    }

    fn buildArgArea(self: *VM, cargs: []const []const u8) !struct { usize, u64, u64 } {
        const ptr_size = @sizeOf(usize);
        const max_ptrs = 256;
        if (cargs.len > max_ptrs) return error.TooManyArgs;
        var env = std.process.getEnvMap(std.heap.page_allocator) catch return error.OutOfMemory;
        defer env.deinit();
        const arg_count = cargs.len;
        if (env.count() > max_ptrs - arg_count) return error.TooManyArgs;
        var strings_len: usize = 0;
        for (cargs) |arg| strings_len += arg.len + 1;
        var env_iter_count = env.iterator();
        while (env_iter_count.next()) |entry| {
            strings_len += entry.key_ptr.*.len + 1 + entry.value_ptr.*.len + 1;
        }
        const arg_ptrs_size = (arg_count + 1) * ptr_size;
        const env_ptrs_size = (env.count() + 1) * ptr_size;
        const total = strings_len + arg_ptrs_size + env_ptrs_size + 16;
        if (total >= self.mem.len) return error.OutOfMemory;
        const area = self.mem.len - total;
        self.arg_area_start = area;
        var pos: usize = area;
        var arg_ptrs: [max_ptrs]usize = undefined;
        for (cargs, 0..) |arg, idx| {
            arg_ptrs[idx] = @intFromPtr(&self.mem[pos]);
            @memcpy(self.mem[pos .. pos + arg.len], arg);
            self.mem[pos + arg.len] = 0;
            pos += arg.len + 1;
        }
        var env_ptrs: [max_ptrs]usize = undefined;
        var env_iter = env.iterator();
        var env_count: usize = 0;
        while (env_iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            env_ptrs[env_count] = @intFromPtr(&self.mem[pos]);
            @memcpy(self.mem[pos .. pos + key.len], key);
            pos += key.len;
            self.mem[pos] = '=';
            pos += 1;
            @memcpy(self.mem[pos .. pos + value.len], value);
            pos += value.len;
            self.mem[pos] = 0;
            pos += 1;
            env_count += 1;
        }
        pos = (pos + ptr_size - 1) & ~@as(usize, ptr_size - 1);
        const argv_off = pos;
        for (arg_ptrs[0..arg_count]) |p| {
            var ptr: usize = p;
            @memcpy(self.mem[pos .. pos + ptr_size], std.mem.asBytes(&ptr));
            pos += ptr_size;
        }
        var zero: usize = 0;
        @memcpy(self.mem[pos .. pos + ptr_size], std.mem.asBytes(&zero));
        pos += ptr_size;
        const envp_off = pos;
        for (env_ptrs[0..env_count]) |p| {
            var ptr: usize = p;
            @memcpy(self.mem[pos .. pos + ptr_size], std.mem.asBytes(&ptr));
            pos += ptr_size;
        }
        @memcpy(self.mem[pos .. pos + ptr_size], std.mem.asBytes(&zero));
        return .{
            arg_count,
            @intFromPtr(&self.mem[argv_off]),
            @intFromPtr(&self.mem[envp_off]),
        };
    }

    pub fn runCallback(self: *VM, func_index: usize, args: []const Value) !i64 {
        if (func_index >= self.func_count) return error.BadFunction;
        const f = self.functions[func_index];
        if (args.len != f.param_count) return error.BadArgCount;
        const saved_sp = self.sp;
        const saved_frames = self.frame_count;
        const saved_result = self.result;
        const saved_mem_top = self.mem_top;
        const base = saved_sp;
        const locals: usize = f.local_count;
        if (base + locals > self.stack_limit) return error.StackOverflow;
        for (args, 0..) |v, i| self.values[base + i] = v;
        var i: usize = args.len;
        while (i < locals) : (i += 1) self.values[base + i] = .{ .i = 0 };
        self.sp = base + locals;
        const result = self.executeLoop(func_index, base, saved_frames) catch |err| {
            self.sp = saved_sp;
            self.frame_count = saved_frames;
            self.result = saved_result;
            self.mem_top = saved_mem_top;
            return err;
        };
        self.sp = saved_sp;
        self.frame_count = saved_frames;
        self.result = saved_result;
        self.mem_top = saved_mem_top;
        return result;
    }

    fn executeLoop(self: *VM, start_fi: usize, start_base: usize, stop_frames: usize) !i64 {
        var base: usize = start_base;
        var current: usize = start_fi;
        var ip: usize = 0;
        var va_base: usize = 0;
        var va_named: usize = 0;
        var va_count: usize = 0;
        var va_types: [64]u8 = [_]u8{0} ** 64;
        var va_sizes: [64]u16 = [_]u16{0} ** 64;
        var va_type_count: u8 = 0;

        while (true) {
            const f = self.functions[current];
            const code = f.code;
            if (ip >= code.len) return error.TruncatedCode;
            const op = code[ip];
            ip += 1;

            switch (op) {
                OP_RET, OP_RET_VOID => {
                    const is_void = op == OP_RET_VOID;
                    const v: Value = if (is_void) .{ .i = 0 } else try self.pop();
                    if (self.frame_count == stop_frames) {
                        self.result = v.i;
                        return v.i;
                    }
                    const fr = self.frames[self.frame_count - 1];
                    self.frame_count -= 1;
                    self.mem_top = fr.mem_mark;
                    self.sp = base;
                    if (!is_void) try self.push(v);
                    base = fr.base;
                    current = fr.func;
                    va_base = fr.va_base;
                    va_named = fr.va_named;
                    va_count = fr.va_count;
                    va_types = fr.va_types;
                    va_sizes = fr.va_sizes;
                    va_type_count = fr.va_type_count;
                    ip = fr.return_ip;
                },
                OP_LOAD_CONST_I64 => {
                    const v = try readI64(code, &ip);
                    try self.push(.{ .i = v });
                },
                OP_ADD => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = a.i +% b.i });
                },
                OP_SUB => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = a.i -% b.i });
                },
                OP_MUL => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = a.i *% b.i });
                },
                OP_DUP => {
                    const a = try self.pop();
                    try self.push(a);
                    try self.push(a);
                },
                OP_POP => {
                    _ = try self.pop();
                },
                OP_SWAP => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(b);
                    try self.push(a);
                },
                OP_XOR => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = a.i ^ b.i });
                },
                OP_DIV_S => {
                    const b = try self.pop();
                    const a = try self.pop();
                    if (b.i == 0) return error.DivisionByZero;
                    try self.push(.{ .i = @divTrunc(a.i, b.i) });
                },
                OP_DIV_U => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const bu: u64 = @bitCast(b.i);
                    if (bu == 0) return error.DivisionByZero;
                    const au: u64 = @bitCast(a.i);
                    try self.push(.{ .i = @bitCast(au / bu) });
                },
                OP_REM_S => {
                    const b = try self.pop();
                    const a = try self.pop();
                    if (b.i == 0) return error.DivisionByZero;
                    try self.push(.{ .i = @rem(a.i, b.i) });
                },
                OP_REM_U => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const bu: u64 = @bitCast(b.i);
                    if (bu == 0) return error.DivisionByZero;
                    const au: u64 = @bitCast(a.i);
                    try self.push(.{ .i = @bitCast(au % bu) });
                },
                OP_AND => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = a.i & b.i });
                },
                OP_OR => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = a.i | b.i });
                },
                OP_SHL => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const sh: u6 = @intCast(@as(u64, @bitCast(b.i)) & 63);
                    try self.push(.{ .i = @bitCast(@as(u64, @bitCast(a.i)) << sh) });
                },
                OP_SHR_S => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const sh: u6 = @intCast(@as(u64, @bitCast(b.i)) & 63);
                    try self.push(.{ .i = a.i >> sh });
                },
                OP_SHR_U => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const sh: u6 = @intCast(@as(u64, @bitCast(b.i)) & 63);
                    try self.push(.{ .i = @bitCast(@as(u64, @bitCast(a.i)) >> sh) });
                },
                OP_FPTOSI => {
                    const v = try self.pop();
                    const fval: f64 = @bitCast(v.i);
                    try self.push(.{ .i = try floatToI64Safe(fval) });
                },
                OP_SITOFP => {
                    const v = try self.pop();
                    const fval: f64 = @floatFromInt(v.i);
                    try self.push(.{ .i = @bitCast(fval) });
                },
                OP_FPTOUI => {
                    const v = try self.pop();
                    const fval: f64 = @bitCast(v.i);
                    try self.push(.{ .i = @bitCast(try floatToU64Safe(fval)) });
                },
                OP_UITOFP => {
                    const v = try self.pop();
                    const uval: u64 = @bitCast(v.i);
                    const fval: f64 = @floatFromInt(uval);
                    try self.push(.{ .i = @bitCast(fval) });
                },
                OP_F80_CONST => {
                    var bits: u80 = 0;
                    var i: u8 = 0;
                    while (i < 10) : (i += 1) {
                        bits |= @as(u80, try readU8(code, &ip)) << @intCast(8 * @as(u7, @intCast(i)));
                    }
                    try self.pushF80(@bitCast(bits));
                },
                OP_F80_ADD => {
                    const b = try self.popF80();
                    const a = try self.popF80();
                    try self.pushF80(a + b);
                },
                OP_F80_SUB => {
                    const b = try self.popF80();
                    const a = try self.popF80();
                    try self.pushF80(a - b);
                },
                OP_F80_MUL => {
                    const b = try self.popF80();
                    const a = try self.popF80();
                    try self.pushF80(a * b);
                },
                OP_F80_DIV => {
                    const b = try self.popF80();
                    const a = try self.popF80();
                    try self.pushF80(a / b);
                },
                OP_F80_CMP => {
                    const pred = try readU8(code, &ip);
                    const b = try self.popF80();
                    const a = try self.popF80();
                    try self.push(.{ .i = if (compareF80(a, b, pred)) 1 else 0 });
                },
                OP_F80_FROM_F64 => {
                    const v = try self.pop();
                    const fval: f64 = @bitCast(v.i);
                    try self.pushF80(@floatCast(fval));
                },
                OP_F80_TO_F64 => {
                    const v = try self.popF80();
                    try self.push(.{ .i = @bitCast(@as(f64, @floatCast(v))) });
                },
                OP_F80_FROM_I64 => {
                    const v = try self.pop();
                    try self.pushF80(@floatFromInt(v.i));
                },
                OP_F80_TO_I64 => {
                    const v = try self.popF80();
                    try self.push(.{ .i = try floatToI64Safe(v) });
                },
                OP_F80_TO_U64 => {
                    const v = try self.popF80();
                    try self.push(.{ .i = @bitCast(try floatToU64Safe(v)) });
                },
                OP_F80_FROM_U64 => {
                    const v = try self.pop();
                    try self.pushF80(@floatFromInt(@as(u64, @bitCast(v.i))));
                },
                OP_F80_FROM_F32 => {
                    const v = try self.pop();
                    const bits: u32 = @truncate(@as(u64, @bitCast(v.i)));
                    const fval: f32 = @bitCast(bits);
                    try self.pushF80(@floatCast(fval));
                },
                OP_F80_TO_F32 => {
                    const v = try self.popF80();
                    const fval: f32 = @floatCast(v);
                    try self.pushF32(fval);
                },
                OP_F80_NEG => {
                    const v = try self.popF80();
                    try self.pushF80(-v);
                },
                OP_F128_CONST => {
                    var bits: u128 = 0;
                    var i: u8 = 0;
                    while (i < 16) : (i += 1) {
                        bits |= @as(u128, try readU8(code, &ip)) << @intCast(8 * @as(u8, i));
                    }
                    try self.pushF128(@bitCast(bits));
                },
                OP_F128_ADD => {
                    const b = try self.popF128();
                    const a = try self.popF128();
                    try self.pushF128(a + b);
                },
                OP_F128_SUB => {
                    const b = try self.popF128();
                    const a = try self.popF128();
                    try self.pushF128(a - b);
                },
                OP_F128_MUL => {
                    const b = try self.popF128();
                    const a = try self.popF128();
                    try self.pushF128(a * b);
                },
                OP_F128_DIV => {
                    const b = try self.popF128();
                    const a = try self.popF128();
                    try self.pushF128(a / b);
                },
                OP_F128_CMP => {
                    const pred = try readU8(code, &ip);
                    const b = try self.popF128();
                    const a = try self.popF128();
                    try self.push(.{ .i = if (compareF128(a, b, pred)) 1 else 0 });
                },
                OP_F128_NEG => {
                    const v = try self.popF128();
                    try self.pushF128(-v);
                },
                OP_F128_FROM_F64 => {
                    const v = try self.pop();
                    const fval: f64 = @bitCast(v.i);
                    try self.pushF128(@floatCast(fval));
                },
                OP_F128_TO_F64 => {
                    const v = try self.popF128();
                    try self.push(.{ .i = @bitCast(@as(f64, @floatCast(v))) });
                },
                OP_F128_FROM_I64 => {
                    const v = try self.pop();
                    try self.pushF128(@floatFromInt(v.i));
                },
                OP_F128_TO_I64 => {
                    const v = try self.popF128();
                    try self.push(.{ .i = try floatToI64Safe(v) });
                },
                OP_F128_TO_U64 => {
                    const v = try self.popF128();
                    try self.push(.{ .i = @bitCast(try floatToU64Safe(v)) });
                },
                OP_F128_FROM_U64 => {
                    const v = try self.pop();
                    try self.pushF128(@floatFromInt(@as(u64, @bitCast(v.i))));
                },
                OP_F128_FROM_F32 => {
                    const v = try self.pop();
                    const bits: u32 = @truncate(@as(u64, @bitCast(v.i)));
                    const fval: f32 = @bitCast(bits);
                    try self.pushF128(@floatCast(fval));
                },
                OP_F128_TO_F32 => {
                    const v = try self.popF128();
                    try self.pushF32(@floatCast(v));
                },
                OP_FADD => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const fa: f64 = @bitCast(a.i);
                    const fb: f64 = @bitCast(b.i);
                    try self.push(.{ .i = @bitCast(fa + fb) });
                },
                OP_FSUB => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const fa: f64 = @bitCast(a.i);
                    const fb: f64 = @bitCast(b.i);
                    try self.push(.{ .i = @bitCast(fa - fb) });
                },
                OP_FMUL => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const fa: f64 = @bitCast(a.i);
                    const fb: f64 = @bitCast(b.i);
                    try self.push(.{ .i = @bitCast(fa * fb) });
                },
                OP_FDIV => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const fa: f64 = @bitCast(a.i);
                    const fb: f64 = @bitCast(b.i);
                    try self.push(.{ .i = @bitCast(fa / fb) });
                },
                OP_FCMP => {
                    const pred = try readU8(code, &ip);
                    const b = try self.pop();
                    const a = try self.pop();
                    const fa: f64 = @bitCast(a.i);
                    const fb: f64 = @bitCast(b.i);
                    try self.push(.{ .i = if (compareFloats(fa, fb, pred)) 1 else 0 });
                },
                OP_FADD32 => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.pushF32(f32FromValue(a) + f32FromValue(b));
                },
                OP_FSUB32 => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.pushF32(f32FromValue(a) - f32FromValue(b));
                },
                OP_FMUL32 => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.pushF32(f32FromValue(a) * f32FromValue(b));
                },
                OP_FDIV32 => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.pushF32(f32FromValue(a) / f32FromValue(b));
                },
                OP_FCMP32 => {
                    const pred = try readU8(code, &ip);
                    const b = try self.pop();
                    const a = try self.pop();
                    const fa: f64 = f32FromValue(a);
                    const fb: f64 = f32FromValue(b);
                    try self.push(.{ .i = if (compareFloats(fa, fb, pred)) 1 else 0 });
                },
                OP_FPEXT => {
                    const v = try self.pop();
                    const fval: f64 = f32FromValue(v);
                    try self.push(.{ .i = @bitCast(fval) });
                },
                OP_FPTRUNC => {
                    const v = try self.pop();
                    const fval: f64 = @bitCast(v.i);
                    try self.pushF32(@floatCast(fval));
                },
                OP_FPTOSI32 => {
                    const v = try self.pop();
                    const fval = f32FromValue(v);
                    try self.push(.{ .i = try floatToI64Safe(fval) });
                },
                OP_SITOFP32 => {
                    const v = try self.pop();
                    const fval: f32 = @floatFromInt(v.i);
                    try self.pushF32(fval);
                },
                OP_FPTOUI32 => {
                    const v = try self.pop();
                    const fval = f32FromValue(v);
                    try self.push(.{ .i = @bitCast(try floatToU64Safe(fval)) });
                },
                OP_UITOFP32 => {
                    const v = try self.pop();
                    const uval: u64 = @bitCast(v.i);
                    const fval: f32 = @floatFromInt(uval);
                    try self.pushF32(fval);
                },
                OP_LOAD_LOCAL => {
                    const idx = try readU16(code, &ip);
                    const slot: usize = idx;
                    const local_count: usize = f.local_count;
                    if (slot >= local_count) return error.BadLocal;
                    try self.push(self.values[base + slot]);
                },
                OP_STORE_LOCAL => {
                    const idx = try readU16(code, &ip);
                    const slot: usize = idx;
                    const local_count: usize = f.local_count;
                    if (slot >= local_count) return error.BadLocal;
                    const v = try self.pop();
                    self.values[base + slot] = v;
                },
                OP_CMP_EQ => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = if (a.i == b.i) 1 else 0 });
                },
                OP_CMP_LT => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .i = if (a.i < b.i) 1 else 0 });
                },
                OP_CMP_LT_U => {
                    const b = try self.pop();
                    const a = try self.pop();
                    const au: u64 = @bitCast(a.i);
                    const bu: u64 = @bitCast(b.i);
                    try self.push(.{ .i = if (au < bu) 1 else 0 });
                },
                OP_JMP => {
                    const target: usize = try readU32(code, &ip);
                    if (target > code.len) return error.BadJump;
                    ip = target;
                },
                OP_JZ => {
                    const target: usize = try readU32(code, &ip);
                    if (target > code.len) return error.BadJump;
                    const cond = try self.pop();
                    if (cond.i == 0) ip = target;
                },
                OP_JNZ => {
                    const target: usize = try readU32(code, &ip);
                    if (target > code.len) return error.BadJump;
                    const cond = try self.pop();
                    if (cond.i != 0) ip = target;
                },
                OP_CREATE_CALLBACK => {
                    const slot = try readU16(code, &ip);
                    const func = try readU16(code, &ip);
                    const plan_idx = try readU16(code, &ip);
                    if (slot >= self.callback_entries.len) return error.BadCallbackSlot;
                    const fidx: usize = func;
                    if (fidx >= self.func_count) return error.BadFunction;
                    const store = self.plan_store orelse return error.NoPlans;
                    const pidx: usize = plan_idx;
                    const p = store.planAt(pidx) orelse return error.BadPlan;
                    // Reject a plan the platform cannot marshal now, instead
                    // of silently dropping the callback when it is invoked.
                    const plan = store.callPlan(p);
                    try platform.validate(plan);
                    // Win32 callback dispatch supports cdecl, stdcall, fastcall
                    // and thiscall; reject only plans the platform cannot
                    // marshal (unknown convention/ABI shape).
                    if (platform.abi_kind == .win32 and !platform.win32CallbackSupported(plan))
                        return error.UnsupportedCallback;

                    callback_mutex.lock();
                    defer callback_mutex.unlock();
                    if (self.callback_destroying) return error.VmDestroyed;
                    var global_slot: usize = undefined;
                    const mapped = self.callback_slots[slot];
                    if (mapped >= 0) {
                        global_slot = @intCast(mapped);
                    } else {
                        // Retired trampolines stay retired: a host may still
                        // hold a function pointer from a destroyed VM, and
                        // reusing its slot would redirect that pointer into a
                        // different VM. The pool is therefore a one-way,
                        // process-wide budget of 256 callback registrations.
                        var g: usize = 0;
                        var found = false;
                        while (g < callback_owners.len) : (g += 1) {
                            if (!callback_retired[g] and callback_owners[g] == null) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) return error.TooManyCallbacks;
                        global_slot = g;
                        self.callback_slots[slot] = @intCast(g);
                    }
                    self.callback_entries[global_slot] = .{
                        .func = fidx,
                        .plan = plan,
                    };
                    callback_owners[global_slot] = self;
                    const addr = platform.callbackTable(global_slot) orelse return error.UnsupportedCallback;
                    const addr64: u64 = @intCast(@intFromPtr(addr));
                    try self.push(.{ .i = @bitCast(addr64) });
                },
                OP_CALLBACK_ACQUIRE => {
                    const plan_index = try readU16(code, &ip);
                    const func = try readU16(code, &ip);
                    try self.push(.{ .i = try self.acquireCallback(plan_index, func) });
                },
                OP_CALLBACK_RELEASE => {
                    const v = try self.pop();
                    try self.push(.{ .i = self.releaseCallback(addressFromBits(v.i)) });
                },
                OP_CALL_NATIVE, OP_CALL_VARARG => {
                    const idx = try readU16(code, &ip);
                    const store = self.plan_store orelse return error.NoPlans;
                    const i: usize = idx;
                    const p = store.planAt(i) orelse return error.BadPlan;
                    var plan = store.callPlan(p);
                    const n: usize = p.name_len;
                    const name = p.name[0..n];
                    // i686 carries its calling convention in the export
                    // decoration (`_name@N`, `@name@N`); the plan only knows it
                    // for symbols the compiler indexes from the MinGW `.def`s.
                    // Varargs calls stay cdecl: stdcall/fastcall cannot describe
                    // a callee that does not know the argument count.
                    if (plan.conv == 0 and op == OP_CALL_NATIVE and platform.abi_kind == .win32)
                        plan.conv = win32ConvFromName(name);
                    const target = try self.resolvedNative(idx, name);
                    try self.recordNativeTarget(@intFromPtr(target));
                    try self.invokeFfi(plan, target);
                },
                OP_FPCLASS => {
                    const kind = try readU8(code, &ip);
                    const mask = try self.pop();
                    const value = try self.pop();
                    const cls = fpClassValue(value, kind);
                    try self.push(.{ .i = if ((cls & @as(u16, @truncate(mask.u))) != 0) 1 else 0 });
                },
                OP_STACKSAVE => {
                    try self.push(.{ .i = @intCast(self.mem_top) });
                },
                OP_STACKRESTORE => {
                    const v = try self.pop();
                    if (v.i < 0) return error.BadMemorySize;
                    const n: usize = @intCast(v.i);
                    if (n > self.memLimit()) return error.OutOfMemory;
                    self.mem_top = n;
                },
                OP_VA_START => {
                    const pv = try self.pop();
                    const extra = if (va_count > va_named) va_count - va_named else 0;
                    const slot_size: usize = if (platform.abi_id == 3) 4 else 8;
                    var overflow: u64 = 0;
                    if (extra > 0) {
                        const start = (self.mem_top + 15) & ~@as(usize, 15);
                        var pos = start;
                        var i: usize = 0;
                        while (i < extra) : (i += 1) {
                            const tc = if (i < va_type_count) va_types[i] else 0;
                            const v = self.values[va_base + va_named + i];
                            var n: usize = slot_size;
                            var step: usize = slot_size;
                            var alignment: usize = slot_size;
                            var ptr: ?usize = null;
                            if (tc == 1 or tc == 2) {
                                n = 16;
                                step = 16;
                                alignment = 16;
                                ptr = addressFromBits(v.i);
                            } else if (tc == 3) {
                                n = if (i < va_sizes.len) va_sizes[i] else 0;
                                if (n == 0) n = 8;
                                step = (n + 7) & ~@as(usize, 7);
                                alignment = 8;
                                ptr = addressFromBits(v.i);
                            }
                            pos = (pos + alignment - 1) & ~(alignment - 1);
                            if (pos + n > self.memLimit()) return error.OutOfMemory;
                            if (ptr) |src| {
                                if (src + n > @intFromPtr(&self.mem[0]) + self.mem.len) return error.BadAddress;
                                @memcpy(self.mem[pos .. pos + n], self.mem[src - @intFromPtr(&self.mem[0]) ..][0..n]);
                            } else {
                                @memcpy(self.mem[pos .. pos + n], std.mem.asBytes(&v.i)[0..n]);
                            }
                            pos += step;
                        }
                        self.mem_top = pos;
                        overflow = @intFromPtr(&self.mem[start]);
                    }
                    const p = pv.u;
                    switch (platform.abi_id) {
                        1 => {
                            const q: *align(1) [24]u8 = @ptrFromInt(addressFromBits(pv.i));
                            @memcpy(q[0..4], std.mem.asBytes(&@as(u32, 48)));
                            @memcpy(q[4..8], std.mem.asBytes(&@as(u32, 304)));
                            @memcpy(q[8..16], std.mem.asBytes(&overflow));
                            @memcpy(q[16..24], std.mem.asBytes(&@as(u64, 0)));
                        },
                        2 => {
                            const q: *align(1) u64 = @ptrFromInt(addressFromBits(pv.i));
                            q.* = overflow;
                        },
                        3 => {
                            const q: *align(1) u32 = @ptrFromInt(addressFromBits(pv.i));
                            q.* = @truncate(overflow);
                        },
                        4 => {
                            // AAPCS64: stack, gr_top, vr_top, gr_offs, vr_offs.
                            const q: *align(1) [32]u8 = @ptrFromInt(addressFromBits(pv.i));
                            @memcpy(q[0..8], std.mem.asBytes(&overflow));
                            @memcpy(q[8..16], std.mem.asBytes(&@as(u64, 0)));
                            @memcpy(q[16..24], std.mem.asBytes(&@as(u64, 0)));
                            @memcpy(q[24..28], std.mem.asBytes(&@as(u32, 0)));
                            @memcpy(q[28..32], std.mem.asBytes(&@as(u32, 0)));
                        },
                        else => return error.UnsupportedVaList,
                    }
                    _ = p;
                },
                OP_VA_COPY => {
                    const src = try self.pop();
                    const dst = try self.pop();
                    const n: usize = switch (platform.abi_id) {
                        1 => 24,
                        2 => 8,
                        3 => 4,
                        4 => 32,
                        else => return error.UnsupportedVaList,
                    };
                    const d: *align(1) [32]u8 = @ptrFromInt(addressFromBits(dst.i));
                    const s_: *align(1) const [32]u8 = @ptrFromInt(addressFromBits(src.i));
                    @memcpy(d[0..n], s_[0..n]);
                },
                OP_SETJMP => {
                    const slot = try readU16(code, &ip);
                    const local_count: usize = f.local_count;
                    if (slot >= local_count) return error.BadLocal;
                    const buf = try self.pop();
                    var found: ?*JumpEntry = null;
                    var free_slot: ?*JumpEntry = null;
                    var ji: usize = 0;
                    while (ji < self.jumps.len) : (ji += 1) {
                        if (self.jumps[ji].valid and self.jumps[ji].buf == buf.u) {
                            found = &self.jumps[ji];
                            break;
                        }
                        if (!self.jumps[ji].valid and free_slot == null) free_slot = &self.jumps[ji];
                    }
                    if (found == null) found = free_slot;
                    if (found == null) return error.TooManyJumps;
                    const e = found.?;
                    e.* = .{
                        .buf = buf.u,
                        .ip = ip,
                        .base = base,
                        .func = current,
                        .sp = self.sp,
                        .frames = self.frame_count,
                        .mem_top = self.mem_top,
                        .slot = slot,
                        .valid = true,
                    };
                    self.values[base + slot] = .{ .i = 0 };
                },
                OP_LONGJMP => {
                    const value = try self.pop();
                    const buf = try self.pop();
                    var ji: usize = 0;
                    while (ji < self.jumps.len) : (ji += 1) {
                        const e = &self.jumps[ji];
                        if (e.valid and e.buf == buf.u) {
                            if (e.func >= self.func_count) return error.BadLongjmp;
                            if (e.slot >= self.functions[e.func].local_count) return error.BadLongjmp;
                            ip = e.ip;
                            base = e.base;
                            current = e.func;
                            self.sp = e.sp;
                            self.frame_count = e.frames;
                            self.mem_top = e.mem_top;
                            self.values[base + e.slot] = .{ .i = if (value.i == 0) 1 else value.i };
                            break;
                        }
                    } else return error.BadLongjmp;
                },
                OP_ADDR_EXTERN => {
                    const idx = try readU16(code, &ip);
                    const sym = try self.resolveData(idx);
                    try self.recordNativeTarget(@intFromPtr(sym));
                    const addr: u64 = @intFromPtr(sym);
                    try self.push(.{ .i = @bitCast(addr) });
                },
                OP_ADDR_CONST => {
                    const off = try readU32(code, &ip);
                    const o: usize = off;
                    if (o > self.mem.len) return error.BadAddress;
                    const addr: u64 = @intFromPtr(&self.mem[o]);
                    try self.push(.{ .i = @bitCast(addr) });
                },
                OP_SET_MEM_TOP => {
                    const size = try readU32(code, &ip);
                    const n: usize = size;
                    if (n > self.memLimit()) return error.OutOfMemory;
                    self.mem_top = n;
                },
                OP_ALLOCA => {
                    const size = try readU16(code, &ip);
                    const start = (self.mem_top + 7) & ~@as(usize, 7);
                    const n: usize = size;
                    if (start + n > self.memLimit()) return error.OutOfMemory;
                    @memset(self.mem[start .. start + n], 0);
                    self.mem_top = start + n;
                    const addr: u64 = @intCast(@intFromPtr(&self.mem[start]));
                    try self.push(.{ .i = @bitCast(addr) });
                },
                OP_ALLOCA_ALIGNED => {
                    const size = try readU16(code, &ip);
                    const align_raw = try readU8(code, &ip);
                    const alignment: usize = if (align_raw == 0) 8 else align_raw;
                    const start = (self.mem_top + alignment - 1) & ~(alignment - 1);
                    const n: usize = size;
                    if (start + n > self.memLimit()) return error.OutOfMemory;
                    @memset(self.mem[start .. start + n], 0);
                    self.mem_top = start + n;
                    const addr: u64 = @intCast(@intFromPtr(&self.mem[start]));
                    try self.push(.{ .i = @bitCast(addr) });
                },
                OP_ALLOCA_DYN => {
                    const sv = try self.pop();
                    if (sv.i < 0) return error.BadMemorySize;
                    const n: usize = @intCast(sv.i);
                    const start = (self.mem_top + 7) & ~@as(usize, 7);
                    if (start + n > self.memLimit()) return error.OutOfMemory;
                    @memset(self.mem[start .. start + n], 0);
                    self.mem_top = start + n;
                    const addr: u64 = @intCast(@intFromPtr(&self.mem[start]));
                    try self.push(.{ .i = @bitCast(addr) });
                },
                OP_ALLOCA_DYN_ALIGN => {
                    const align_raw = try readU8(code, &ip);
                    const alignment: usize = if (align_raw == 0) 8 else align_raw;
                    const sv = try self.pop();
                    if (sv.i < 0) return error.BadMemorySize;
                    const n: usize = @intCast(sv.i);
                    const start = (self.mem_top + alignment - 1) & ~(alignment - 1);
                    if (start + n > self.memLimit()) return error.OutOfMemory;
                    @memset(self.mem[start .. start + n], 0);
                    self.mem_top = start + n;
                    const addr: u64 = @intCast(@intFromPtr(&self.mem[start]));
                    try self.push(.{ .i = @bitCast(addr) });
                },
                OP_LOAD_MEM => {
                    const size = try readU8(code, &ip);
                    const n: usize = size;
                    if (n == 0 or n > 8) return error.BadMemorySize;
                    const v = try self.pop();
                    const addr: usize = addressFromBits(v.i);
                    if (!validMemoryRange(addr, n)) return error.BadAddress;

                    var bits: u64 = 0;
                    var i: usize = 0;
                    while (i < n) : (i += 1) {
                        const p: *align(1) const u8 = @ptrFromInt(addr + i);
                        bits |= @as(u64, p.*) << @intCast(8 * i);
                    }
                    if (n < 8) {
                        const sign_bit: u64 = @as(u64, 1) << @intCast(8 * n - 1);
                        if ((bits & sign_bit) != 0) {
                            const mask: u64 = ~((@as(u64, 1) << @intCast(8 * n)) - 1);
                            bits |= mask;
                        }
                    }
                    try self.push(.{ .i = @bitCast(bits) });
                },
                OP_STORE_MEM => {
                    const size = try readU8(code, &ip);
                    const n: usize = size;
                    if (n == 0 or n > 8) return error.BadMemorySize;
                    const av = try self.pop();
                    const vv = try self.pop();
                    const addr: usize = addressFromBits(av.i);
                    if (!validMemoryRange(addr, n)) return error.BadAddress;

                    const bits: u64 = @bitCast(vv.i);
                    var i: usize = 0;
                    while (i < n) : (i += 1) {
                        const p: *align(1) u8 = @ptrFromInt(addr + i);
                        p.* = @truncate(bits >> @intCast(8 * i));
                    }
                },
                OP_MEMCPY => {
                    const len_v = try self.pop();
                    const src_v = try self.pop();
                    const dst_v = try self.pop();
                    if (len_v.i < 0) return error.BadMemorySize;
                    const len: usize = @intCast(len_v.i);
                    const dst_addr = addressFromBits(dst_v.i);
                    const src_addr = addressFromBits(src_v.i);
                    if (len > 0 and (!validMemoryRange(dst_addr, len) or
                        !validMemoryRange(src_addr, len)))
                        return error.BadAddress;
                    const dst: [*]u8 = @ptrFromInt(dst_addr);
                    const src: [*]const u8 = @ptrFromInt(src_addr);

                    if (@intFromPtr(dst) < @intFromPtr(src)) {
                        std.mem.copyForwards(u8, dst[0..len], src[0..len]);
                    } else if (@intFromPtr(dst) > @intFromPtr(src)) {
                        std.mem.copyBackwards(u8, dst[0..len], src[0..len]);
                    }
                },
                OP_MEMSET => {
                    const len_v = try self.pop();
                    const val_v = try self.pop();
                    const dst_v = try self.pop();
                    if (len_v.i < 0) return error.BadMemorySize;
                    const len: usize = @intCast(len_v.i);
                    const dst_addr = addressFromBits(dst_v.i);
                    if (len > 0 and !validMemoryRange(dst_addr, len)) return error.BadAddress;
                    const dst: [*]u8 = @ptrFromInt(dst_addr);
                    const byte: u8 = @truncate(@as(u64, @bitCast(val_v.i)));

                    @memset(dst[0..len], byte);
                },
                OP_CALL_VARIADIC_TYPED => {
                    const fn_idx = try readU16(code, &ip);
                    const total = try readU16(code, &ip);
                    const fidx: usize = fn_idx;
                    if (fidx >= self.func_count) return error.BadFunction;
                    const callee = self.functions[fidx];
                    const params: usize = callee.param_count;
                    const locals: usize = callee.local_count;
                    const arg_count: usize = total;
                    if (arg_count < params or self.sp < arg_count) return error.StackUnderflow;
                    if (self.frame_count >= MAX_FRAMES) return error.FrameOverflow;
                    const extra = arg_count - params;
                    if (extra > 64) return error.TooManyArgs;
                    var types: [64]u8 = [_]u8{0} ** 64;
                    var sizes: [64]u16 = [_]u16{0} ** 64;
                    var ti: usize = 0;
                    while (ti < extra) : (ti += 1) {
                        const type_code = try readU8(code, &ip);
                        types[ti] = type_code;
                        if (type_code == 3) sizes[ti] = try readU16(code, &ip);
                    }
                    const callee_base = self.sp - arg_count;
                    const src_base = callee_base + params;
                    const extra_base = callee_base + locals;
                    // Both the extras and their new home must stay inside the
                    // value stack before anything is copied.
                    if (extra_base + extra > self.stack_limit) return error.StackOverflow;
                    if (src_base + extra > self.stack_limit) return error.StackOverflow;
                    self.frames[self.frame_count] = .{
                        .return_ip = ip,
                        .base = base,
                        .func = current,
                        .mem_mark = self.mem_top,
                        .va_base = va_base,
                        .va_named = va_named,
                        .va_count = va_count,
                        .va_types = va_types,
                        .va_sizes = va_sizes,
                        .va_type_count = va_type_count,
                    };
                    self.frame_count += 1;
                    base = callee_base;
                    current = fidx;
                    if (extra_base > src_base and extra_base < src_base + extra) {
                        var ei: usize = extra;
                        while (ei > 0) {
                            ei -= 1;
                            self.values[extra_base + ei] = self.values[src_base + ei];
                        }
                    } else {
                        var ei: usize = 0;
                        while (ei < extra) : (ei += 1) {
                            self.values[extra_base + ei] = self.values[src_base + ei];
                        }
                    }
                    va_base = extra_base;
                    va_named = 0;
                    va_count = extra;
                    va_types = types;
                    va_sizes = sizes;
                    va_type_count = @intCast(extra);
                    self.sp = extra_base + extra;
                    if (self.sp > self.stack_limit) return error.StackOverflow;
                    ip = 0;
                },
                OP_CALL_VARIADIC => {
                    const fn_idx = try readU16(code, &ip);
                    const total = try readU16(code, &ip);
                    const fidx: usize = fn_idx;
                    if (fidx >= self.func_count) return error.BadFunction;
                    const callee = self.functions[fidx];
                    const params: usize = callee.param_count;
                    const locals: usize = callee.local_count;
                    const arg_count: usize = total;
                    if (arg_count < params or self.sp < arg_count) return error.StackUnderflow;
                    if (self.frame_count >= MAX_FRAMES) return error.FrameOverflow;
                    const callee_base = self.sp - arg_count;
                    // The callee's locals start immediately after its named
                    // parameters. Move variadic extras past those locals so
                    // compiler temporaries cannot overwrite them.
                    const extra = arg_count - params;
                    const extra_base = callee_base + locals;
                    const src_base = callee_base + params;
                    if (extra_base + extra > self.stack_limit) return error.StackOverflow;
                    if (src_base + extra > self.stack_limit) return error.StackOverflow;
                    self.frames[self.frame_count] = .{
                        .return_ip = ip,
                        .base = base,
                        .func = current,
                        .mem_mark = self.mem_top,
                        .va_base = va_base,
                        .va_named = va_named,
                        .va_count = va_count,
                        .va_types = va_types,
                        .va_sizes = va_sizes,
                        .va_type_count = va_type_count,
                    };
                    self.frame_count += 1;
                    base = callee_base;
                    current = fidx;
                    if (extra_base > src_base and extra_base < src_base + extra) {
                        var ei: usize = extra;
                        while (ei > 0) {
                            ei -= 1;
                            self.values[extra_base + ei] = self.values[src_base + ei];
                        }
                    } else {
                        var ei: usize = 0;
                        while (ei < extra) : (ei += 1) {
                            self.values[extra_base + ei] = self.values[src_base + ei];
                        }
                    }
                    va_base = extra_base;
                    va_named = 0;
                    va_count = extra;
                    va_types = [_]u8{0} ** 64;
                    va_sizes = [_]u16{0} ** 64;
                    va_type_count = 0;
                    self.sp = extra_base + extra;
                    if (self.sp > self.stack_limit) return error.StackOverflow;
                    ip = 0;
                },
                OP_CALL => {
                    const fn_idx = try readU16(code, &ip);
                    const fidx: usize = fn_idx;
                    if (fidx >= self.func_count) return error.BadFunction;
                    const callee = self.functions[fidx];
                    const params: usize = callee.param_count;
                    const locals: usize = callee.local_count;
                    if (self.sp < params) return error.StackUnderflow;
                    if (self.frame_count >= MAX_FRAMES) return error.FrameOverflow;
                    const callee_base = self.sp - params;
                    self.frames[self.frame_count] = .{
                        .return_ip = ip,
                        .base = base,
                        .func = current,
                        .mem_mark = self.mem_top,
                        .va_base = va_base,
                        .va_named = va_named,
                        .va_count = va_count,
                        .va_types = va_types,
                        .va_sizes = va_sizes,
                        .va_type_count = va_type_count,
                    };
                    self.frame_count += 1;
                    base = callee_base;
                    current = fidx;
                    va_base = 0;
                    va_named = 0;
                    va_count = 0;
                    va_type_count = 0;
                    self.sp = callee_base + locals;
                    if (self.sp > self.stack_limit) return error.StackOverflow;
                    var li: usize = params;
                    while (li < locals) : (li += 1) {
                        self.values[callee_base + li] = .{ .i = 0 };
                    }
                    ip = 0;
                },
                OP_FUNC_ADDR => {
                    const fn_idx = try readU16(code, &ip);
                    const fidx: usize = fn_idx;
                    if (fidx >= self.func_count) return error.BadFunction;
                    try self.push(.{ .i = @intCast(fidx + 1) });
                },
                OP_CALL_INDIRECT_NATIVE => {
                    const plan_idx = try readU16(code, &ip);
                    const tag = try self.pop();
                    if (tag.i > 0 and tag.i <= self.func_count) {
                        const fidx: usize = @intCast(tag.i - 1);
                        const callee = self.functions[fidx];
                        const params: usize = callee.param_count;
                        const locals: usize = callee.local_count;
                        if (self.sp < params) return error.StackUnderflow;
                        if (self.frame_count >= MAX_FRAMES) return error.FrameOverflow;
                        const callee_base = self.sp - params;
                        self.frames[self.frame_count] = .{
                            .return_ip = ip,
                            .base = base,
                            .func = current,
                            .mem_mark = self.mem_top,
                            .va_base = va_base,
                            .va_named = va_named,
                            .va_count = va_count,
                        };
                        self.frame_count += 1;
                        base = callee_base;
                        current = fidx;
                        va_base = 0;
                        va_named = 0;
                        va_count = 0;
                        self.sp = callee_base + locals;
                        if (self.sp > self.stack_limit) return error.StackOverflow;
                        var li: usize = params;
                        while (li < locals) : (li += 1) {
                            self.values[callee_base + li] = .{ .i = 0 };
                        }
                        ip = 0;
                    } else {
                        const store = self.plan_store orelse return error.NoPlans;
                        const p = store.planAt(plan_idx) orelse return error.BadPlan;
                        const plan = store.callPlan(p);
                        const target_addr = addressFromBits(tag.i);
                        if (!self.isNativeTarget(target_addr)) return error.BadAddress;
                        const target: *const anyopaque = @ptrFromInt(target_addr);
                        try self.invokeFfi(plan, target);
                    }
                },
                OP_CALL_INDIRECT => {
                    const tag = try self.pop();
                    if (tag.i <= 0) return error.BadFunction;
                    const fidx: usize = @intCast(tag.i - 1);
                    if (fidx >= self.func_count) return error.BadFunction;
                    const callee = self.functions[fidx];
                    const params: usize = callee.param_count;
                    const locals: usize = callee.local_count;
                    if (self.sp < params) return error.StackUnderflow;
                    if (self.frame_count >= MAX_FRAMES) return error.FrameOverflow;
                    const callee_base = self.sp - params;
                    self.frames[self.frame_count] = .{
                        .return_ip = ip,
                        .base = base,
                        .func = current,
                        .mem_mark = self.mem_top,
                        .va_base = va_base,
                        .va_named = va_named,
                        .va_count = va_count,
                        .va_types = va_types,
                        .va_sizes = va_sizes,
                        .va_type_count = va_type_count,
                    };
                    self.frame_count += 1;
                    base = callee_base;
                    current = fidx;
                    va_base = 0;
                    va_named = 0;
                    va_count = 0;
                    va_type_count = 0;
                    self.sp = callee_base + locals;
                    if (self.sp > self.stack_limit) return error.StackOverflow;
                    var li: usize = params;
                    while (li < locals) : (li += 1) {
                        self.values[callee_base + li] = .{ .i = 0 };
                    }
                    ip = 0;
                },
                else => {
                    std.debug.print("bad opcode 0x{x} func={d} ip={d}\n", .{ op, current, ip });
                    return error.BadOpcode;
                },
            }
        }
    }

    fn push(self: *VM, v: Value) !void {
        if (self.sp >= self.stack_limit) return error.StackOverflow;
        self.values[self.sp] = v;
        self.sp += 1;
    }

    fn pushF32(self: *VM, f: f32) !void {
        const bits: u32 = @bitCast(f);
        try self.push(.{ .i = @intCast(bits) });
    }

    fn allocTemp(self: *VM, size: usize, alignment: usize) ![]u8 {
        const start = std.mem.alignForward(usize, self.mem_top, alignment);
        const limit = self.memLimit();
        if (start > limit or size > limit - start) return error.OutOfMemory;
        @memset(self.mem[start..][0..size], 0);
        self.mem_top = start + size;
        return self.mem[start..][0..size];
    }

    fn pushF80(self: *VM, value: f80) !void {
        const block = try self.allocTemp(16, 16);
        const p: *align(1) f80 = @ptrCast(block.ptr);
        p.* = value;
        const addr: u64 = @intCast(@intFromPtr(p));
        try self.push(.{ .i = @bitCast(addr) });
    }

    fn popF80(self: *VM) !f80 {
        const v = try self.pop();
        const addr = addressFromBits(v.i);

        return @as(*align(1) const f80, @ptrFromInt(addr)).*;
    }

    fn pushF128(self: *VM, value: f128) !void {
        const block = try self.allocTemp(16, 16);
        const p: *align(1) f128 = @ptrCast(block.ptr);
        p.* = value;
        const addr: u64 = @intCast(@intFromPtr(p));
        try self.push(.{ .i = @bitCast(addr) });
    }

    fn popF128(self: *VM) !f128 {
        const v = try self.pop();
        const addr = addressFromBits(v.i);

        return @as(*align(1) const f128, @ptrFromInt(addr)).*;
    }

    fn pop(self: *VM) !Value {
        if (self.sp == 0) return error.StackUnderflow;
        self.sp -= 1;
        return self.values[self.sp];
    }
};

fn readU64(buf: *const [256]u8, off: usize) u64 {
    return @as(*align(1) const u64, @ptrCast(&buf[off])).*;
}

fn pointerFromU64(v: u64) *anyopaque {
    return @ptrFromInt(@as(usize, @intCast(v)));
}

fn addressFromBits(v: i64) usize {
    return @intCast(@as(u64, @bitCast(v)));
}

inline fn validMemoryRange(addr: usize, len: usize) bool {
    if (addr == 0) return false;
    return len <= std.math.maxInt(usize) - addr;
}

fn readU64Ptr(ptr: [*]const u8) u64 {
    return @as(*align(1) const u64, @ptrCast(ptr)).*;
}

/// Zero image used to give a skipped dispatch deterministic return values.
var callback_zero_image = [_]u8{0} ** 4096;

/// Write zero return values into `frame` for `plan`, so a host that ignores
/// `ci_vm_callback_error` gets a deterministic result instead of whatever the
/// trampoline frame still held. The plan's return locations name the integer
/// and vector return registers of the SysV, Win64, Win32 and AAPCS64 frames, so
/// this covers the ABI's return registers plus the aggregate image of a
/// multi-location return.
fn zeroCallbackReturns(frame: *platform.CallbackFrame, plan: abi.CallPlan) void {
    // An sret callback returned through the caller's buffer and has no
    // register result; a void callback has nothing to write.
    if (plan.sret or plan.ret_locs.len == 0) return;
    if (plan.ret_size > 8) {
        const size: usize = @min(@as(usize, plan.ret_size), callback_zero_image.len);
        for (plan.ret_locs) |loc| {
            const off: usize = @intCast(loc.offset);
            if (off >= size) continue;
            const count = @min(@as(usize, loc.size), size - off);
            if (count == 0) continue;
            platform.callbackWriteBytes(frame, loc, callback_zero_image[0..count], count);
        }
        return;
    }
    if (plan.ret_locs.len > 1) {
        for (plan.ret_locs) |loc| {
            const off: usize = @intCast(loc.offset);
            if (off >= 8) continue;
            const count = @min(@as(usize, loc.size), 8 - off);
            platform.callbackWriteBytes(frame, loc, callback_zero_image[0..count], count);
        }
        return;
    }
    platform.callbackWriteRet(frame, plan.ret_locs[0], 0);
}

/// Marshal the captured trampoline frame, run the CIB function and write its
/// result back into the frame. Returns false when the dispatch could not run
/// (an unusable plan or a failing CIB function), so the caller can store
/// deterministic zero return values instead of leaving the frame's old content.
fn dispatchCallbackEntry(machine: *VM, entry: CallbackEntry, frame: *platform.CallbackFrame) bool {
    platform.validate(entry.plan) catch return false;
    const n: usize = entry.plan.args.len;
    var scratch: [8192]u8 align(16) = undefined;
    var scratch_used: usize = 0;
    var values: [plan_loader.MAX_ARGS]Value = undefined;
    if (n > values.len) return false;
    const fast_win32 = platform.abi_kind == .win32 and entry.plan.conv == 2;
    const this_win32 = platform.abi_kind == .win32 and entry.plan.conv == 3;
    var fast_gpr: u8 = 0;
    var fast_stack_off: usize = 0;
    var this_used = false;
    var this_stack_off: usize = 0;
    for (entry.plan.args, 0..) |arg, i| {
        if (fast_win32) {
            const loc = arg.locs[0];
            if (loc.kind == .sret) {
                values[i] = .{ .u = platform.callbackReadFastStackValue(frame, fast_stack_off, 4) };
                fast_stack_off += 4;
                continue;
            }
            if (platform.win32FastSlot(arg, &fast_gpr)) |slot| {
                values[i] = .{ .u = platform.callbackReadFastReg(frame, slot) };
                continue;
            }
            if (arg.is_struct or arg.locs.len > 1) {
                values[i] = .{ .u = platform.callbackReadFastStructPtr(frame, fast_stack_off) };
            } else {
                values[i] = .{ .u = platform.callbackReadFastStackValue(frame, fast_stack_off, loc.size) };
            }
            fast_stack_off += platform.win32StackBytes(arg);
            continue;
        }
        if (this_win32) {
            const loc = arg.locs[0];
            if (loc.kind == .sret) {
                values[i] = .{ .u = platform.callbackReadFastStackValue(frame, this_stack_off, 4) };
                this_stack_off += 4;
                continue;
            }
            if (platform.win32ThisSlot(arg, &this_used)) {
                values[i] = .{ .u = platform.callbackReadFastReg(frame, 0) };
                continue;
            }
            if (arg.is_struct or arg.locs.len > 1) {
                values[i] = .{ .u = platform.callbackReadFastStructPtr(frame, this_stack_off) };
            } else {
                values[i] = .{ .u = platform.callbackReadFastStackValue(frame, this_stack_off, loc.size) };
            }
            this_stack_off += platform.win32StackBytes(arg);
            continue;
        }
        if (arg.is_struct) {
            if (arg.locs.len == 1 and arg.locs[0].kind == .stack) {
                values[i] = .{ .u = platform.callbackStructPtr(frame, arg.locs[0]) };
                continue;
            }
            const start = scratch_used;
            const size: usize = @intCast(arg.size);
            if (start + size > scratch.len) return false;
            @memset(scratch[start .. start + size], 0);
            const first_off: usize = @intCast(arg.locs[0].offset);
            for (arg.locs) |loc| {
                const off: usize = @intCast(loc.offset);
                if (off < first_off) continue;
                const dst_off = off - first_off;
                if (dst_off >= size) continue;
                const count = @min(@as(usize, loc.size), size - dst_off);
                platform.callbackReadBytes(frame, loc, scratch[start + dst_off .. start + dst_off + count], count);
            }
            const addr: u64 = @intCast(@intFromPtr(&scratch[start]));
            values[i] = .{ .u = addr };
            scratch_used += (size + 15) & ~@as(usize, 15);
        } else {
            values[i] = .{ .u = platform.callbackReadArg(frame, arg.locs[0]) };
        }
    }
    const result = machine.runCallback(entry.func, values[0..n]) catch return false;
    if (entry.plan.sret or entry.plan.ret_locs.len == 0) return true;
    const result_bits: u64 = @bitCast(result);
    if (entry.plan.ret_size > 8) {
        const src: [*]const u8 = @ptrFromInt(addressFromBits(result));
        for (entry.plan.ret_locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const count = @min(@as(usize, loc.size), @as(usize, entry.plan.ret_size) - @min(off, @as(usize, entry.plan.ret_size)));
            if (count == 0) continue;
            platform.callbackWriteBytes(frame, loc, src[off..][0..count], count);
        }
    } else if (entry.plan.ret_locs.len > 1) {
        const bytes = std.mem.asBytes(&result_bits);
        for (entry.plan.ret_locs) |loc| {
            const off: usize = @intCast(loc.offset);
            if (off >= bytes.len) continue;
            const count = @min(@as(usize, loc.size), bytes.len - off);
            platform.callbackWriteBytes(frame, loc, bytes[off..][0..count], count);
        }
    } else {
        platform.callbackWriteRet(frame, entry.plan.ret_locs[0], result_bits);
    }
    return true;
}

/// Record the category of a dispatch that was skipped, for
/// `ci_vm_callback_error`. Protected by the pool lock because the dispatch may
/// run on a foreign thread while the owning thread reads the VM.
fn recordCallbackError(machine: *VM, code: c_int) void {
    callback_mutex.lock();
    defer callback_mutex.unlock();
    machine.callback_error = code;
}

/// Drop the dispatch counts for `slot` and, when this dispatch was the
/// outermost execution context of a VM whose destroy was requested from inside
/// the callback, free the VM last: `machine` must not be touched after that.
fn finishCallbackDispatch(machine: *VM, slot: usize, destroy_after: bool) void {
    callback_mutex.lock();
    if (callback_slot_active[slot] > 0) callback_slot_active[slot] -= 1;
    if (machine.callback_active > 0) machine.callback_active -= 1;
    callback_cond.broadcast();
    callback_mutex.unlock();
    if (destroy_after) destroyVm(machine);
}

/// Assembly trampoline entry: native code called through `slot` and captured
/// its arguments in `frame`.
///
/// Threading rules, using the VM's execution lock (`RunState`):
///   * the thread that already runs the VM (a callback calling a native
///     function that calls back in) re-enters `runCallback` as before;
///   * an idle VM takes its execution right for the duration of the dispatch,
///     so the callback cannot race a `ci_vm_run` on another thread;
///   * a VM that another thread is running fails fast: the callback is
///     skipped, its return value is zeroed and `ci_vm_callback_error` reports
///     `CI_E_BUSY`. Waiting here could deadlock, because the run thread may be
///     waiting for this very callback to return.
pub export fn ci_callback_dispatch(slot: u64, frame: *platform.CallbackFrame) callconv(.C) void {
    const s: usize = @intCast(slot);
    // The i686 trampoline rewrites ESP from `frame.cleanup` once this returns,
    // so clear it before anything can bail out: every early return below then
    // balances the stack exactly like a `__cdecl` call.
    switch (platform.abi_kind) {
        .win32 => {
            const wframe: *platform.Win32CbFrame = @ptrCast(frame);
            wframe.cleanup = 0;
        },
        else => {},
    }

    callback_mutex.lock();
    if (s >= callback_owners.len) {
        callback_mutex.unlock();
        return;
    }
    const machine = callback_owners[s] orelse {
        callback_mutex.unlock();
        return;
    };
    const entry = machine.callback_entries[s] orelse {
        callback_mutex.unlock();
        return;
    };
    // An i686 `__stdcall` callback pops its own argument bytes; the trampoline
    // can only learn how many from the plan, so hand it `plan.stack_size` (0
    // for `__cdecl`, where the caller pops). This is done before any path that
    // can return early, so a skipped or rejected callback still returns with
    // the stack balanced for the function the host actually called through.
    // Other ABI frames have no cleanup field and are left untouched.
    switch (platform.abi_kind) {
        .win32 => {
            const wframe: *platform.Win32CbFrame = @ptrCast(frame);
            wframe.cleanup = platform.win32CallbackCleanup(entry.plan);
        },
        else => {},
    }
    if (machine.callback_destroying) {
        // Still under the pool lock: the destroy path cannot free the plan
        // store that `entry.plan`'s return locations point into.
        zeroCallbackReturns(frame, entry.plan);
        callback_mutex.unlock();
        return;
    }
    machine.callback_active += 1;
    callback_slot_active[s] += 1;
    callback_mutex.unlock();

    // Until `finishCallbackDispatch` the VM cannot be freed (`callback_active`
    // is raised and `destroyVm` waits for it), so every path below can touch
    // `machine`.
    var entered = false;
    if (machine.run_state) |state| {
        if (state.enter()) |_| {
            entered = true;
        } else |err| switch (err) {
            // The calling thread already runs this VM: the existing
            // saved/restored callback frame is exactly the reentrant path, and
            // the execution right is already held.
            error.NestedRun => {},
            error.Busy => {
                recordCallbackError(machine, CI_E_BUSY);
                zeroCallbackReturns(frame, entry.plan);
                finishCallbackDispatch(machine, s, false);
                return;
            },
            error.VmDestroyed => {
                recordCallbackError(machine, CI_E_DESTROYED);
                zeroCallbackReturns(frame, entry.plan);
                finishCallbackDispatch(machine, s, false);
                return;
            },
        }
    }

    // A dispatch that could not run (or whose CIB function failed) still leaves
    // deterministic zero return values instead of the frame's previous content.
    if (!dispatchCallbackEntry(machine, entry, frame))
        zeroCallbackReturns(frame, entry.plan);

    var destroy_after = false;
    if (entered) {
        // This dispatch is the outermost execution context, so a
        // `ci_vm_destroy` issued from inside the callback is completed here;
        // it could not free the VM while the frame below was still running.
        if (machine.run_state.?.leave()) destroy_after = true;
    }
    finishCallbackDispatch(machine, s, destroy_after);
}

const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    fn take(self: *Reader, n: usize) ![]const u8 {
        if (self.pos + n > self.data.len) return error.Truncated;
        const out = self.data[self.pos .. self.pos + n];
        self.pos += n;
        return out;
    }

    fn readU8(self: *Reader) !u8 {
        const b = try self.take(1);
        return b[0];
    }

    fn readU16(self: *Reader) !u16 {
        const b = try self.take(2);
        return @as(u16, b[0]) | (@as(u16, b[1]) << 8);
    }

    fn readU32(self: *Reader) !u32 {
        const b = try self.take(4);
        return @as(u32, b[0]) |
            (@as(u32, b[1]) << 8) |
            (@as(u32, b[2]) << 16) |
            (@as(u32, b[3]) << 24);
    }
};

fn readU8(code: []const u8, ip: *usize) !u8 {
    if (ip.* + 1 > code.len) return error.TruncatedCode;
    const v = code[ip.*];
    ip.* += 1;
    return v;
}

fn readU16(code: []const u8, ip: *usize) !u16 {
    if (ip.* + 2 > code.len) return error.TruncatedCode;
    const v = @as(u16, code[ip.*]) | (@as(u16, code[ip.* + 1]) << 8);
    ip.* += 2;
    return v;
}

fn readU32(code: []const u8, ip: *usize) !u32 {
    if (ip.* + 4 > code.len) return error.TruncatedCode;
    const v = @as(u32, code[ip.*]) |
        (@as(u32, code[ip.* + 1]) << 8) |
        (@as(u32, code[ip.* + 2]) << 16) |
        (@as(u32, code[ip.* + 3]) << 24);
    ip.* += 4;
    return v;
}

fn readI64(code: []const u8, ip: *usize) !i64 {
    if (ip.* + 8 > code.len) return error.TruncatedCode;
    var bits: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        bits |= @as(u64, code[ip.* + i]) << @as(u6, @intCast(i * 8));
    }
    ip.* += 8;
    return @bitCast(bits);
}

pub const CI_ABI_VERSION: c_int = 2;
pub const CI_OK: c_int = 0;
pub const CI_ERROR: c_int = -1;
pub const CI_E_INVALID_ARGUMENT: c_int = -2;
pub const CI_E_OUT_OF_MEMORY: c_int = -3;
pub const CI_E_BAD_PACKAGE: c_int = -4;
pub const CI_E_TARGET: c_int = -5;
pub const CI_E_PLANS: c_int = -6;
pub const CI_E_LINK: c_int = -7;
pub const CI_E_ENTRY: c_int = -8;
pub const CI_E_RESOURCE: c_int = -9;
pub const CI_E_RUNTIME: c_int = -10;
pub const CI_E_DESTROYED: c_int = -11;
/// The VM is executing on another thread (or `CI_DESTROY_TRY`/unload found it
/// busy). Appended after `CI_E_DESTROYED`; existing values are unchanged.
pub const CI_E_BUSY: c_int = -12;

/// `ci_vm_destroy_ex` flag: fail with `CI_E_BUSY` instead of waiting for a
/// running thread. The default (flags == 0) waits for the VM to become idle.
pub const CI_DESTROY_TRY: c_uint = 1;

pub const CiVmConfig = extern struct {
    struct_size: u32,
    flags: u32,
    stack_size: usize,
    memory_size: usize,
};

/// Map a runtime error to its documented `CI_E_*` category. Every error the
/// bytecode interpreter, the package decoders and the platform layer can return
/// is classified here; only genuinely internal failures fall through to
/// `CI_ERROR`.
pub fn errorCode(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => CI_E_OUT_OF_MEMORY,
        error.TooManyArgs, error.InvalidArgument => CI_E_INVALID_ARGUMENT,
        error.BadPackage,
        error.BadPackageMagic,
        error.BadPackageVersion,
        error.BadPackageSize,
        error.BadMagic,
        error.BadVersion,
        error.BadArch,
        error.BadModule,
        error.BadLocals,
        error.TooManyFunctions,
        error.NameTooLong,
        error.ModuleTooLarge,
        error.Truncated,
        error.TrailingBytes,
        error.BadImportMagic,
        error.BadImportVersion,
        error.TooManyImports,
        error.TooManyProviders,
        => CI_E_BAD_PACKAGE,
        error.UnsupportedLibc => CI_E_TARGET,
        error.NoPlans,
        error.BadAbi,
        error.BadPlan,
        error.BadImportPlan,
        error.BadImportProvider,
        error.ImportArchMismatch,
        error.ImportUnavailable,
        error.TooManyPlans,
        error.TooManyLocs,
        error.BadLocKind,
        => CI_E_PLANS,
        error.SymbolNotFound,
        error.LibraryNotFound,
        error.SymbolTooLong,
        error.PathTooLong,
        error.TooManyLibraries,
        error.TooManyNativeTargets,
        => CI_E_LINK,
        error.EntryNotFound => CI_E_ENTRY,
        error.StackOverflow,
        error.FrameOverflow,
        error.ReturnTooLarge,
        error.ProcessFull,
        => CI_E_RESOURCE,
        error.BadAddress,
        error.BadOpcode,
        error.BadFunction,
        error.BadArgCount,
        error.BadJump,
        error.BadCallbackSlot,
        error.UnsupportedCallback,
        error.TooManyCallbacks,
        error.DivisionByZero,
        error.BadLocal,
        error.BadLongjmp,
        error.TooManyJumps,
        error.TruncatedCode,
        error.StackUnderflow,
        error.BadMemorySize,
        error.NullStruct,
        error.UnsupportedVaList,
        => CI_E_RUNTIME,
        // A second thread called into a VM that is already executing, or a
        // loader/`CI_DESTROY_TRY` found the VM busy.
        error.Busy => CI_E_BUSY,
        // The owning thread re-entered `ci_vm_run` (for example from a
        // callback); running it would clear the outer run's image.
        error.NestedRun => CI_E_RUNTIME,
        error.VmDestroyed => CI_E_DESTROYED,
        else => CI_ERROR,
    };
}

fn fail(m: *VM, err: anyerror) c_int {
    const code = errorCode(err);
    m.last_error_code = code;
    if (comptime debug_errors) {
        const name = @errorName(err);
        std.debug.print("cinterp: {s}\n", .{name});
        m.setError(name);
    } else {
        m.last_error[0] = 0;
    }
    return code;
}

pub export fn ci_abi_version() c_int {
    return CI_ABI_VERSION;
}

pub export fn ci_version() [*:0]const u8 {
    return build_options.version.ptr;
}

fn initMachine(machine: *VM) void {
    machine.* = undefined;
    @memset(std.mem.asBytes(machine), 0);
    for (0..machine.callback_slots.len) |i| machine.callback_slots[i] = -1;
}

fn createVm(stack_size: usize, memory_size: usize) ?*VM {
    const limit = if (stack_size == 0) MAX_STACK else stack_size;
    if (limit == 0 or limit > MAX_STACK) return null;
    const mem_size = if (memory_size == 0) DEFAULT_MEMORY else memory_size;
    if (mem_size > MAX_MEMORY) return null;
    const machine = std.heap.page_allocator.create(VM) catch return null;
    initMachine(machine);
    const state = std.heap.page_allocator.create(RunState) catch {
        std.heap.page_allocator.destroy(machine);
        return null;
    };
    state.* = .{};
    machine.run_state = state;
    machine.values = std.heap.page_allocator.alloc(Value, limit) catch {
        std.heap.page_allocator.destroy(state);
        std.heap.page_allocator.destroy(machine);
        return null;
    };
    machine.mem = std.heap.page_allocator.alignedAlloc(u8, 32, mem_size) catch {
        std.heap.page_allocator.free(machine.values);
        std.heap.page_allocator.destroy(state);
        std.heap.page_allocator.destroy(machine);
        return null;
    };
    machine.stack_limit = limit;
    machine.clearError();
    return machine;
}

pub export fn ci_vm_create(stack_size: usize) ?*VM {
    return createVm(stack_size, 0);
}

pub export fn ci_vm_create_ex(config: ?*const CiVmConfig) ?*VM {
    const cfg = config orelse return ci_vm_create(0);
    const minimum = @offsetOf(CiVmConfig, "stack_size") + @sizeOf(usize);
    if (cfg.struct_size < minimum) return null;
    if (cfg.flags != 0) return null;
    const memory_size = if (cfg.struct_size >= @sizeOf(CiVmConfig)) cfg.memory_size else 0;
    return createVm(cfg.stack_size, memory_size);
}

/// Free a VM whose execution right is closed and whose run thread (if any) has
/// finished. Callers must have gone through `RunState.tryClose`,
/// `RunState.closeAndWait` or `RunState.leave`.
fn destroyVm(m: *VM) void {
    callback_mutex.lock();
    m.callback_destroying = true;
    // Every trampoline slot this VM still owns is retired for good: a host that
    // kept a function pointer from this VM must never reach a later one. The
    // scan is over the process-wide slots instead of `callback_slots`, so an
    // explicitly acquired slot that was never released is retired too. Slots
    // the CIB released are owned by nobody and stay reusable.
    for (0..callback_owners.len) |g| {
        if (callback_owners[g] == m) {
            callback_owners[g] = null;
            callback_retired[g] = true;
        }
        m.callback_entries[g] = null;
    }
    for (0..m.callback_slots.len) |slot| m.callback_slots[slot] = -1;
    while (m.callback_active > 0) callback_cond.wait(&callback_mutex);
    callback_mutex.unlock();
    m.freePlans();
    if (m.module_buf.len > 0) std.heap.page_allocator.free(m.module_buf);
    if (m.values.len > 0) std.heap.page_allocator.free(m.values);
    if (m.mem.len > 0) std.heap.page_allocator.free(m.mem);
    if (m.run_state) |state| std.heap.page_allocator.destroy(state);
    std.heap.page_allocator.destroy(m);
}

/// Destroy a VM. Kept source-compatible with ABI 2 callers: it waits for a
/// concurrent run to finish, and defers the free when the calling thread is
/// itself running the VM (a callback calling `ci_vm_destroy`), so it never
/// deadlocks and never frees a frame that is still executing.
pub export fn ci_vm_destroy(machine: ?*VM) void {
    _ = ci_vm_destroy_ex(machine, 0);
}

/// `flags` is 0 (wait for the VM to become idle, like `ci_vm_destroy`) or
/// `CI_DESTROY_TRY` (return `CI_E_BUSY` while it executes instead of waiting).
pub export fn ci_vm_destroy_ex(machine: ?*VM, flags: c_uint) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if ((flags & ~CI_DESTROY_TRY) != 0) return fail(m, error.InvalidArgument);
    const state = m.run_state orelse {
        // Stack/scratch VM without execution state: nothing can be running.
        destroyVm(m);
        return CI_OK;
    };
    if ((flags & CI_DESTROY_TRY) != 0) {
        switch (state.tryClose()) {
            .idle => {},
            .busy => return fail(m, error.Busy),
            // The caller is inside its own run; the outermost run frees it.
            .deferred => {
                state.requestDeferredDestroy();
                return CI_OK;
            },
            // Another thread is already destroying this VM.
            .closing => return fail(m, error.VmDestroyed),
        }
    } else {
        switch (state.closeAndWait()) {
            .idle => {},
            .deferred => {
                state.requestDeferredDestroy();
                return CI_OK;
            },
            .busy => unreachable,
            .closing => return fail(m, error.VmDestroyed),
        }
    }
    destroyVm(m);
    return CI_OK;
}

/// Free a VM whose destroy was deferred (requested from inside its own run).
/// `runVmGuarded` calls this after the outermost run releases the execution
/// right; it is public so tests can stand in for that frame.
pub fn finishDeferredDestroy(m: *VM) void {
    destroyVm(m);
}

/// 1 while the VM is executing on any thread, 0 otherwise.
pub export fn ci_vm_busy(machine: ?*const VM) c_int {
    const m = machine orelse return 0;
    const state = m.run_state orelse return 0;
    return if (state.isBusy()) 1 else 0;
}

/// Take the VM's execution right for a loader. Returns null on success, or the
/// `CI_E_*` status the loader must return: a load may not replace the module,
/// plans or plan cache while a run is using them, whichever thread asks.
fn beginVmMutation(m: *VM) ?c_int {
    const state = m.run_state orelse return null;
    state.enter() catch |err| return switch (err) {
        error.Busy, error.NestedRun => fail(m, error.Busy),
        error.VmDestroyed => fail(m, error.VmDestroyed),
    };
    return null;
}

fn endVmMutation(m: *VM) void {
    const state = m.run_state orelse return;
    // A deferred destroy cannot be requested while this thread only mutates
    // the VM (it owns no run frame), so the flag is only returned, not acted on.
    _ = state.leave();
}

pub export fn ci_vm_load_module(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (size != 0 and @intFromPtr(data) == 0) return fail(m, error.InvalidArgument);
    if (beginVmMutation(m)) |status| return status;
    defer endVmMutation(m);
    m.loadModuleBytes(data[0..size]) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_load_plans(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (size != 0 and @intFromPtr(data) == 0) return fail(m, error.InvalidArgument);
    if (beginVmMutation(m)) |status| return status;
    defer endVmMutation(m);
    m.loadPlans(data[0..size]) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_load_package(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (size != 0 and @intFromPtr(data) == 0) return fail(m, error.InvalidArgument);
    if (beginVmMutation(m)) |status| return status;
    defer endVmMutation(m);
    m.loadPackage(data[0..size]) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_load_library(machine: ?*VM, path: [*:0]const u8) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (@intFromPtr(path) == 0) return fail(m, error.InvalidArgument);
    if (beginVmMutation(m)) |status| return status;
    defer endVmMutation(m);
    m.loadLibrary(std.mem.span(path)) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

/// Body of one run. Split out so the guard around it stays in one place.
fn runVmBody(m: *VM, entry: []const u8, cargs: ?[]const []const u8) c_int {
    if (cargs) |args| {
        m.result = m.runEntryArgs(entry, args) catch |err| return fail(m, err);
    } else {
        m.result = m.runEntry(entry) catch |err| return fail(m, err);
    }
    m.clearError();
    return CI_OK;
}

/// Run one entry point under the VM's execution lock. A second thread gets
/// `CI_E_BUSY`, the owning thread gets `CI_E_RUNTIME`; different VMs have
/// different locks and never block each other.
fn runVmGuarded(m: *VM, entry: []const u8, cargs: ?[]const []const u8) c_int {
    const state = m.run_state orelse return runVmBody(m, entry, cargs);
    state.enter() catch |err| return fail(m, err);
    const status = runVmBody(m, entry, cargs);
    // A `ci_vm_destroy` issued from inside this run (a callback, or a native
    // function calling back into the host) is deferred to here: this frame is
    // the last one allowed to touch the VM.
    if (state.leave()) destroyVm(m);
    return status;
}

pub export fn ci_vm_run(machine: ?*VM, entry: [*:0]const u8) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (@intFromPtr(entry) == 0) return fail(m, error.InvalidArgument);
    return runVmGuarded(m, std.mem.span(entry), null);
}

pub export fn ci_vm_run_args(
    machine: ?*VM,
    entry: [*:0]const u8,
    argc: c_int,
    argv: ?[*]const ?[*:0]const u8,
) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (@intFromPtr(entry) == 0) return fail(m, error.InvalidArgument);
    if (argc < 0 or argc > 256) return fail(m, error.TooManyArgs);
    var args_buf: [256][]const u8 = undefined;
    const n: usize = @intCast(argc);
    if (n > 0) {
        const av = argv orelse return fail(m, error.TooManyArgs);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const item = av[i] orelse return fail(m, error.TooManyArgs);
            args_buf[i] = std.mem.span(item);
        }
    }
    return runVmGuarded(m, std.mem.span(entry), args_buf[0..n]);
}

pub export fn ci_vm_result(machine: ?*VM) i64 {
    const m = machine orelse return 0;
    return m.result;
}

pub export fn ci_vm_last_error(machine: ?*VM) [*:0]const u8 {
    const m = machine orelse return "";
    if (comptime !debug_errors) return "";
    return @ptrCast(&m.last_error[0]);
}

pub export fn ci_vm_last_error_code(machine: ?*VM) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    return m.last_error_code;
}

pub export fn ci_vm_clear_error(machine: ?*VM) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    m.clearError();
    // The dispatch error has its own channel so a host whose native library
    // swallowed the callback result can still observe a skipped callback; the
    // same call clears both.
    callback_mutex.lock();
    m.callback_error = 0;
    callback_mutex.unlock();
    return CI_OK;
}

/// Last failed callback dispatch for this VM as a `CI_E_*` category, or 0 when
/// none is recorded. A callback that native code invoked while another thread
/// was running the VM is skipped (fail-fast) and recorded as `CI_E_BUSY`; a VM
/// being destroyed records `CI_E_DESTROYED`. The value stays until
/// `ci_vm_clear_error`, so a host can inspect it after the run that triggered
/// the callback returned.
pub export fn ci_vm_callback_error(machine: ?*const VM) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    callback_mutex.lock();
    defer callback_mutex.unlock();
    return m.callback_error;
}

/// Snapshot of the process-wide trampoline pool.
///
/// `total` is always 256. `live` slots are bound to a VM, `reusable` slots are
/// free for the next acquire, and `retired` slots can never be used again
/// (their VM was destroyed or reloaded its plans while they were still bound).
/// Any output pointer may be null. This is additive to ABI 2: existing
/// functions, values and semantics are unchanged.
pub export fn ci_callback_pool_stats(
    total: ?*u32,
    live: ?*u32,
    reusable: ?*u32,
    retired: ?*u32,
) void {
    var live_count: u32 = 0;
    var reusable_count: u32 = 0;
    var retired_count: u32 = 0;
    callback_mutex.lock();
    for (0..callback_owners.len) |g| {
        if (callback_owners[g] != null) {
            live_count += 1;
        } else if (callback_retired[g]) {
            retired_count += 1;
        } else {
            reusable_count += 1;
        }
    }
    callback_mutex.unlock();
    if (total) |out| out.* = @intCast(callback_owners.len);
    if (live) |out| out.* = live_count;
    if (reusable) |out| out.* = reusable_count;
    if (retired) |out| out.* = retired_count;
}

/// Upper bound on the VMs one `ci_process` owns. The multi-CIB use case is a
/// handful of packages, so a fixed registry keeps loading allocation-free
/// apart from the VM itself.
pub const MAX_PROCESS_VMS: usize = 64;

/// A process-level registry of independently runnable VMs, one per loaded CIB.
///
/// The registry owns VM lifetimes only; run policy (which VM, how often, on
/// which thread) stays with the host. Each VM still holds exactly one package,
/// and `ci_vm_load_package` keeps its transactional replacement semantics.
pub const Process = struct {
    mutex: std.Thread.Mutex = .{},
    /// Normalized `ci_vm_config` every VM is created from.
    stack_size: usize = 0,
    memory_size: usize = 0,
    vms: [MAX_PROCESS_VMS]?*VM = [_]?*VM{null} ** MAX_PROCESS_VMS,
    /// Set while `ci_process_destroy` frees the registry, so a second destroy
    /// cannot free it twice. Cleared again if a busy VM postpones the destroy.
    closing: bool = false,
    last_error: [128]u8 = [_]u8{0} ** 128,
    last_error_code: c_int = 0,

    fn setError(self: *Process, msg: []const u8) void {
        const n = @min(msg.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..n], msg[0..n]);
        self.last_error[n] = 0;
    }

    fn clearError(self: *Process) void {
        self.last_error[0] = 0;
        self.last_error_code = 0;
    }
};

fn failProcess(p: *Process, err: anyerror) c_int {
    const code = errorCode(err);
    p.last_error_code = code;
    if (comptime debug_errors) {
        const name = @errorName(err);
        std.debug.print("cinterp: {s}\n", .{name});
        p.setError(name);
    } else {
        p.last_error[0] = 0;
    }
    return code;
}

pub export fn ci_process_create(config: ?*const CiVmConfig) ?*Process {
    var stack_size: usize = 0;
    var memory_size: usize = 0;
    if (config) |cfg| {
        const minimum = @offsetOf(CiVmConfig, "stack_size") + @sizeOf(usize);
        if (cfg.struct_size < minimum) return null;
        if (cfg.flags != 0) return null;
        stack_size = cfg.stack_size;
        if (cfg.struct_size >= @sizeOf(CiVmConfig)) memory_size = cfg.memory_size;
    }
    // Reject an impossible config here so loading a package later can only
    // fail on the package or on memory exhaustion.
    const limit = if (stack_size == 0) MAX_STACK else stack_size;
    if (limit == 0 or limit > MAX_STACK) return null;
    const mem_size = if (memory_size == 0) DEFAULT_MEMORY else memory_size;
    if (mem_size > MAX_MEMORY) return null;

    const p = std.heap.page_allocator.create(Process) catch return null;
    p.* = .{ .stack_size = stack_size, .memory_size = memory_size };
    return p;
}

/// Destroy every idle VM the process owns and free the registry.
///
/// A VM that is still executing on another thread is left untouched: the
/// process (and those VMs) stay alive, `ci_process_last_error` reports
/// `CI_E_BUSY`, and the host must join the run threads and call
/// `ci_process_destroy` again. Blocking here would mean waiting for an unknown
/// thread and could deadlock a host that joins its threads afterwards.
pub export fn ci_process_destroy(process: ?*Process) void {
    const p = process orelse return;
    p.mutex.lock();
    if (p.closing) {
        // Another thread is already destroying this registry.
        p.mutex.unlock();
        return;
    }
    p.closing = true;
    var busy: usize = 0;
    for (&p.vms) |*slot| {
        const m = slot.* orelse continue;
        if (m.run_state) |state| {
            if (state.tryClose() != .idle) {
                busy += 1;
                continue;
            }
        }
        slot.* = null;
        destroyVm(m);
    }
    if (busy != 0) {
        p.last_error_code = CI_E_BUSY;
        if (comptime debug_errors) {
            p.setError("ci_process_destroy: VM still running");
        } else {
            p.last_error[0] = 0;
        }
        // The registry stays alive so the error is observable and the host can
        // retry after joining its run threads.
        p.closing = false;
        p.mutex.unlock();
        return;
    }
    p.mutex.unlock();
    std.heap.page_allocator.destroy(p);
}

/// Load a package into a freshly created VM and hand it back as a borrowed
/// handle. The package bytes are copied; a failure leaves the registry
/// unchanged and records the error on the process.
pub export fn ci_process_load_package(
    process: ?*Process,
    data: [*]const u8,
    size: usize,
    out: ?*?*VM,
) c_int {
    const p = process orelse return CI_E_INVALID_ARGUMENT;
    const vm_out = out orelse return CI_E_INVALID_ARGUMENT;
    vm_out.* = null;
    p.mutex.lock();
    defer p.mutex.unlock();
    if (size != 0 and @intFromPtr(data) == 0) return failProcess(p, error.InvalidArgument);
    var slot: usize = 0;
    while (slot < p.vms.len and p.vms[slot] != null) : (slot += 1) {}
    if (slot == p.vms.len) return failProcess(p, error.ProcessFull);
    const m = createVm(p.stack_size, p.memory_size) orelse return failProcess(p, error.OutOfMemory);
    m.loadPackage(data[0..size]) catch |err| {
        destroyVm(m);
        return failProcess(p, err);
    };
    p.vms[slot] = m;
    vm_out.* = m;
    p.clearError();
    return CI_OK;
}

/// Unload a VM owned by the process. The VM must be idle; a running VM is
/// reported as `CI_E_BUSY` and stays registered.
pub export fn ci_process_unload_package(process: ?*Process, vm: ?*VM) c_int {
    const p = process orelse return CI_E_INVALID_ARGUMENT;
    const m = vm orelse return CI_E_INVALID_ARGUMENT;
    p.mutex.lock();
    defer p.mutex.unlock();
    var slot: usize = 0;
    while (slot < p.vms.len and p.vms[slot] != m) : (slot += 1) {}
    if (slot == p.vms.len) return failProcess(p, error.InvalidArgument);
    if (m.run_state) |state| {
        switch (state.tryClose()) {
            .idle => {},
            // Another thread runs it, or we are inside its own run.
            else => return failProcess(p, error.Busy),
        }
    }
    p.vms[slot] = null;
    destroyVm(m);
    p.clearError();
    return CI_OK;
}

pub export fn ci_process_last_error(process: ?*const Process) [*:0]const u8 {
    const p = process orelse return "";
    if (comptime !debug_errors) return "";
    return @ptrCast(&p.last_error[0]);
}

pub export fn ci_process_last_error_code(process: ?*const Process) c_int {
    const p = process orelse return CI_E_INVALID_ARGUMENT;
    return p.last_error_code;
}

// ---------------------------------------------------------------- test hooks
//
// The trampoline pool is process-wide and is never reset in production: a
// retired slot stays retired. Unit tests need a known starting state, and they
// need to hold a slot "in dispatch" without a real native call to check the
// release/active rules. These are plain `pub` functions, not `export`ed: they
// add nothing to the C ABI and are dropped from the library because nothing in
// it references them.

/// Unit-test hook: return every trampoline slot to the free set.
pub fn resetCallbackPoolForTest() void {
    callback_mutex.lock();
    defer callback_mutex.unlock();
    for (0..callback_owners.len) |g| {
        callback_owners[g] = null;
        callback_retired[g] = false;
        callback_slot_active[g] = 0;
    }
}

/// Unit-test hook: change the dispatch count of the slot `m` owns for `addr`,
/// as if a native dispatcher were inside that callback. Production code only
/// changes these counts from `ci_callback_dispatch`. Returns false when this VM
/// owns no slot for `addr`.
pub fn holdCallbackSlotForTest(m: *VM, addr: usize, delta: i32) bool {
    callback_mutex.lock();
    defer callback_mutex.unlock();
    for (0..callback_owners.len) |g| {
        if (callback_owners[g] != m) continue;
        const table = platform.callbackTable(g) orelse continue;
        if (@intFromPtr(table) != addr) continue;
        if (delta >= 0) {
            callback_slot_active[g] += @intCast(delta);
        } else {
            callback_slot_active[g] -= @min(callback_slot_active[g], @as(u32, @intCast(-delta)));
        }
        return true;
    }
    return false;
}
