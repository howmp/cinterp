const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const abi = @import("ffi/abi.zig");
const plan_loader = @import("ffi/plan_loader.zig");
const platform = @import("ffi/platform.zig");
const native = @import("ffi/native.zig");
const link_loader = @import("ffi/link_loader.zig");

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

fn readU16At(bytes: []const u8, off: usize) u16 {
    return @as(u16, bytes[off]) | (@as(u16, bytes[off + 1]) << 8);
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

// Callback trampolines have a fixed slot in assembly. Slots are allocated
// process-wide but entries and VM ownership are per-VM; a slot is retired when
// its VM is destroyed so a retained host function pointer can never dispatch
// into a recycled VM.
var callback_owners: [256]?*VM = [_]?*VM{null} ** 256;
var callback_retired: [256]bool = [_]bool{false} ** 256;
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
    plan_store: ?*plan_loader.Store = null,
    target: ?link_loader.TargetInfo = null,
    imports: link_loader.Table = .{},
    import_handles: [link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS]?*anyopaque = [_]?*anyopaque{null} ** (link_loader.MAX_PROVIDERS * link_loader.MAX_IMPORTS),
    default_handles: [8]?*anyopaque = [_]?*anyopaque{null} ** 8,
    default_count: usize = 0,
    default_loaded: bool = false,
    libraries: [8]?*anyopaque = [_]?*anyopaque{null} ** 8,
    library_count: usize = 0,
    symbol_buf: [256]u8 = undefined,
    path_buf: [256]u8 = undefined,
    ret_buf: [4096]u8 align(16) = undefined,
    frames: [MAX_FRAMES]Frame = undefined,
    frame_count: usize = 0,
    jumps: [32]JumpEntry = [_]JumpEntry{.{}} ** 32,
    result: i64 = 0,
    stack_limit: usize = MAX_STACK,
    last_error: [128]u8 = undefined,
    last_error_code: c_int = 0,
    callback_entries: [256]?CallbackEntry = [_]?CallbackEntry{null} ** 256,
    callback_slots: [256]i16 = [_]i16{-1} ** 256,
    callback_active: usize = 0,
    callback_destroying: bool = false,
    native_targets: [256]usize = [_]usize{0} ** 256,
    native_target_count: usize = 0,

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
    }

    fn releaseCallbacks(self: *VM) void {
        callback_mutex.lock();
        defer callback_mutex.unlock();
        for (0..self.callback_slots.len) |slot| {
            const mapped = self.callback_slots[slot];
            if (mapped < 0) continue;
            const g: usize = @intCast(mapped);
            if (g < callback_owners.len and callback_owners[g] == self) {
                callback_owners[g] = null;
                callback_retired[g] = true;
            }
            self.callback_entries[g] = null;
            self.callback_slots[slot] = -1;
        }
    }

    fn freePlans(self: *VM) void {
        if (self.plan_store) |old| {
            self.releaseCallbacks();
            old.deinit(std.heap.page_allocator);
            self.plan_store = null;
        }
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
    }

    fn loadPackageInPlace(self: *VM, bytes: []const u8) !void {
        if (!platform.libc_supported) return error.UnsupportedLibc;
        if (bytes.len < 15) return error.BadPackage;
        if (!std.mem.eql(u8, bytes[0..5], "CIPKG")) return error.BadPackageMagic;
        const version = bytes[5];
        if (version == 1) {
            const module_len = readU32At(bytes, 7);
            const plan_len = readU32At(bytes, 11);
            const m: usize = module_len;
            const p: usize = plan_len;
            if (15 + m + p != bytes.len) return error.BadPackageSize;
            self.target = null;
            self.imports = .{};
            try self.loadModuleBytesInPlace(bytes[15 .. 15 + m]);
            try self.loadPlans(bytes[15 + m .. 15 + m + p]);
            return;
        }
        if (version != 2) return error.BadPackageVersion;
        if (bytes.len < 25) return error.BadPackage;
        const header_size = readU16At(bytes, 7);
        if (header_size != 25) return error.BadPackageHeader;
        const module_len = readU32At(bytes, 9);
        const plan_len = readU32At(bytes, 13);
        const meta_len = readU32At(bytes, 17);
        const import_len = readU32At(bytes, 21);
        const m: usize = module_len;
        const p: usize = plan_len;
        const mt: usize = meta_len;
        const im: usize = import_len;
        if (25 + m + p + mt + im != bytes.len) return error.BadPackageSize;
        const meta = bytes[25 + m + p .. 25 + m + p + mt];
        const target = try link_loader.decodeTarget(meta);
        try platform.validateTarget(target);
        const import_bytes = bytes[25 + m + p + mt .. 25 + m + p + mt + im];
        const imports = try link_loader.decodeImports(import_bytes);
        try self.loadModuleBytesInPlace(bytes[25 .. 25 + m]);
        try self.loadPlans(bytes[25 + m .. 25 + m + p]);
        try self.validateImports(&imports);
        self.target = target;
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
        self.target = scratch.target;
        self.imports = scratch.imports;

        scratch.module_buf = &.{};
        scratch.module_len = 0;
        scratch.func_count = 0;
        std.heap.page_allocator.destroy(scratch);
        if (old_module.len > 0) std.heap.page_allocator.free(old_module);
    }

    fn validateImports(self: *VM, imports: *const link_loader.Table) !void {
        const store = self.plan_store orelse return error.NoPlans;
        const total: usize = imports.count;
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
    /// handles: they keep v1 packages, `--no-auto-link` packages and symbols
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

    fn cachedProvider(self: *VM, plan_index: u16, provider_index: usize, name: []const u8) !?*anyopaque {
        const slot: usize = @as(usize, plan_index) * link_loader.MAX_PROVIDERS + provider_index;
        if (slot >= self.import_handles.len) return null;
        if (self.import_handles[slot]) |handle| return handle;
        if (name.len >= self.path_buf.len) return error.PathTooLong;
        @memcpy(self.path_buf[0..name.len], name);
        self.path_buf[name.len] = 0;
        const cpath: [*:0]const u8 = @ptrCast(&self.path_buf[0]);
        const handle = native.load(cpath) orelse return null;
        self.import_handles[slot] = handle;
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
            const handle = try self.cachedProvider(plan_index, pi, lib_name) orelse continue;
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
            const handle = try self.cachedProvider(@intCast(entry_index), pi, lib_name) orelse continue;
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

    fn recordNativeTarget(self: *VM, addr: usize) void {
        if (addr == 0) return;
        var i: usize = 0;
        while (i < self.native_target_count) : (i += 1) {
            if (self.native_targets[i] == addr) return;
        }
        if (self.native_target_count < self.native_targets.len) {
            self.native_targets[self.native_target_count] = addr;
            self.native_target_count += 1;
        }
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
        if (plan.sret and sret_ptr == null) {
            const rs: usize = @intCast(plan.ret_size);
            if (rs > self.ret_buf.len) return error.ReturnTooLarge;
        }
        platform.configure(&frame, plan, &self.ret_buf, &stack_buf, sret_ptr);
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
            // stay in `ret_buf` and are surfaced as a pointer the bytecode
            // loads from. Note `st0` is also the i686 return file for narrow
            // `float`/`double` values, which are plain words.
            if (n > 8) {
                const rs: usize = @intCast(plan.ret_size);
                if (rs > self.ret_buf.len) return error.ReturnTooLarge;
                @memcpy(self.ret_buf[0..rs], ret_block[off..][0..rs]);
                const addr: u64 = @intCast(@intFromPtr(&self.ret_buf));
                try self.push(.{ .i = @bitCast(addr) });
            } else {
                var bits: u64 = 0;
                @memcpy(std.mem.asBytes(&bits)[0..n], ret_block[off..][0..n]);
                try self.push(.{ .i = @bitCast(bits) });
            }
        } else if (plan.ret_locs.len > 1) {
            const rs: usize = @intCast(plan.ret_size);
            if (rs > self.ret_buf.len) return error.ReturnTooLarge;
            @memcpy(self.ret_buf[0..rs], ret_block[0..rs]);
            const ret_addr: u64 = @intCast(@intFromPtr(&self.ret_buf));
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

        for (0..self.values.len) |i| self.values[i] = .{ .i = 0 };
        self.sp = 0;
        self.mem_top = 0;
        @memset(self.mem, 0);
        self.frame_count = 0;
        self.result = 0;

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

                    callback_mutex.lock();
                    defer callback_mutex.unlock();
                    if (self.callback_destroying) return error.VmDestroyed;
                    var global_slot: usize = undefined;
                    const mapped = self.callback_slots[slot];
                    if (mapped >= 0) {
                        global_slot = @intCast(mapped);
                    } else {
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
                        .plan = store.callPlan(p),
                    };
                    callback_owners[global_slot] = self;
                    const addr = platform.callbackTable(global_slot) orelse return error.UnsupportedCallback;
                    const addr64: u64 = @intCast(@intFromPtr(addr));
                    try self.push(.{ .i = @bitCast(addr64) });
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
                    const target = try self.resolveNative(idx, name);
                    self.recordNativeTarget(@intFromPtr(target));
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
                    if (n > self.mem.len) return error.OutOfMemory;
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
                            if (pos + n > self.mem.len) return error.OutOfMemory;
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
                    self.recordNativeTarget(@intFromPtr(sym));
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
                    if (n > self.mem.len) return error.OutOfMemory;
                    self.mem_top = n;
                },
                OP_ALLOCA => {
                    const size = try readU16(code, &ip);
                    const start = (self.mem_top + 7) & ~@as(usize, 7);
                    const n: usize = size;
                    if (start + n > self.mem.len) return error.OutOfMemory;
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
                    if (start + n > self.mem.len) return error.OutOfMemory;
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
                    if (start + n > self.mem.len) return error.OutOfMemory;
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
                    if (start + n > self.mem.len) return error.OutOfMemory;
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
                    const src_base = callee_base + params;
                    const extra_base = callee_base + locals;
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
                    // The callee's locals start immediately after its named
                    // parameters. Move variadic extras past those locals so
                    // compiler temporaries cannot overwrite them.
                    const extra = arg_count - params;
                    const extra_base = callee_base + locals;
                    const src_base = callee_base + params;
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

    fn pushF80(self: *VM, value: f80) !void {
        const start = (self.mem_top + 15) & ~@as(usize, 15);
        if (start + 16 > self.mem.len) return error.OutOfMemory;
        const p: *align(1) f80 = @ptrCast(&self.mem[start]);
        p.* = value;
        self.mem_top = start + 16;
        const addr: u64 = @intCast(@intFromPtr(p));
        try self.push(.{ .i = @bitCast(addr) });
    }

    fn popF80(self: *VM) !f80 {
        const v = try self.pop();
        const addr = addressFromBits(v.i);

        return @as(*align(1) const f80, @ptrFromInt(addr)).*;
    }

    fn pushF128(self: *VM, value: f128) !void {
        const start = (self.mem_top + 15) & ~@as(usize, 15);
        if (start + 16 > self.mem.len) return error.OutOfMemory;
        const p: *align(1) f128 = @ptrCast(&self.mem[start]);
        p.* = value;
        self.mem_top = start + 16;
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

pub export fn ci_callback_dispatch(slot: u64, frame: *platform.CallbackFrame) callconv(.C) void {
    const s: usize = @intCast(slot);
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
    if (machine.callback_destroying) {
        callback_mutex.unlock();
        return;
    }
    machine.callback_active += 1;
    callback_mutex.unlock();
    defer {
        callback_mutex.lock();
        machine.callback_active -= 1;
        callback_cond.broadcast();
        callback_mutex.unlock();
    }

    platform.validate(entry.plan) catch return;
    const n: usize = entry.plan.args.len;
    if (n > 8) return;
    var scratch: [8192]u8 align(16) = undefined;
    var scratch_used: usize = 0;
    var values: [8]Value = undefined;
    for (entry.plan.args, 0..) |arg, i| {
        if (arg.is_struct) {
            if (arg.locs.len == 1 and arg.locs[0].kind == .stack) {
                values[i] = .{ .u = platform.callbackStructPtr(frame, arg.locs[0]) };
                continue;
            }
            const start = scratch_used;
            const size: usize = @intCast(arg.size);
            if (start + size > scratch.len) return;
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
    const result = machine.runCallback(entry.func, values[0..n]) catch return;
    if (entry.plan.sret or entry.plan.ret_locs.len == 0) return;
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

pub const CiVmConfig = extern struct {
    struct_size: u32,
    flags: u32,
    stack_size: usize,
    memory_size: usize,
};

fn errorCode(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => CI_E_OUT_OF_MEMORY,
        error.TooManyArgs, error.InvalidArgument => CI_E_INVALID_ARGUMENT,
        error.BadPackage,
        error.BadPackageMagic,
        error.BadPackageVersion,
        error.BadPackageHeader,
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
        => CI_E_BAD_PACKAGE,
        error.TargetMismatch,
        error.UnsupportedFeature,
        error.RuntimeTooOld,
        error.UnsupportedOs,
        error.UnsupportedLibc,
        => CI_E_TARGET,
        error.NoPlans,
        error.BadAbi,
        error.BadPlan,
        error.BadImportPlan,
        error.BadImportProvider,
        error.ImportArchMismatch,
        error.ImportUnavailable,
        => CI_E_PLANS,
        error.SymbolNotFound,
        error.LibraryNotFound,
        error.SymbolTooLong,
        error.PathTooLong,
        error.TooManyLibraries,
        => CI_E_LINK,
        error.EntryNotFound => CI_E_ENTRY,
        error.StackOverflow,
        error.FrameOverflow,
        error.ReturnTooLarge,
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
        error.TruncatedCode,
        error.BadMemorySize,
        error.NullStruct,
        => CI_E_RUNTIME,
        error.VmDestroyed => CI_E_DESTROYED,
        else => CI_ERROR,
    };
}

fn fail(m: *VM, err: anyerror) c_int {
    m.last_error_code = errorCode(err);
    m.setError(@errorName(err));
    return CI_ERROR;
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
    machine.values = std.heap.page_allocator.alloc(Value, limit) catch {
        std.heap.page_allocator.destroy(machine);
        return null;
    };
    machine.mem = std.heap.page_allocator.alignedAlloc(u8, 32, mem_size) catch {
        std.heap.page_allocator.free(machine.values);
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

pub export fn ci_vm_destroy(machine: ?*VM) void {
    const m = machine orelse return;
    callback_mutex.lock();
    m.callback_destroying = true;
    for (0..m.callback_slots.len) |slot| {
        const mapped = m.callback_slots[slot];
        if (mapped >= 0) {
            const g: usize = @intCast(mapped);
            if (g < callback_owners.len and callback_owners[g] == m) {
                callback_owners[g] = null;
                callback_retired[g] = true;
            }
            m.callback_slots[slot] = -1;
        }
    }
    while (m.callback_active > 0) callback_cond.wait(&callback_mutex);
    callback_mutex.unlock();
    m.freePlans();
    if (m.module_buf.len > 0) std.heap.page_allocator.free(m.module_buf);
    if (m.values.len > 0) std.heap.page_allocator.free(m.values);
    if (m.mem.len > 0) std.heap.page_allocator.free(m.mem);
    std.heap.page_allocator.destroy(m);
}

pub export fn ci_vm_load_module(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (size != 0 and @intFromPtr(data) == 0) return fail(m, error.InvalidArgument);
    m.loadModuleBytes(data[0..size]) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_load_plans(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (size != 0 and @intFromPtr(data) == 0) return fail(m, error.InvalidArgument);
    m.loadPlans(data[0..size]) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_load_package(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (size != 0 and @intFromPtr(data) == 0) return fail(m, error.InvalidArgument);
    m.loadPackage(data[0..size]) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_load_library(machine: ?*VM, path: [*:0]const u8) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (@intFromPtr(path) == 0) return fail(m, error.InvalidArgument);
    m.loadLibrary(std.mem.span(path)) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_run(machine: ?*VM, entry: [*:0]const u8) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    if (@intFromPtr(entry) == 0) return fail(m, error.InvalidArgument);
    m.result = m.runEntry(std.mem.span(entry)) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
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
    m.result = m.runEntryArgs(std.mem.span(entry), args_buf[0..n]) catch |err| return fail(m, err);
    m.clearError();
    return CI_OK;
}

pub export fn ci_vm_result(machine: ?*VM) i64 {
    const m = machine orelse return 0;
    return m.result;
}

pub export fn ci_vm_last_error(machine: ?*VM) [*:0]const u8 {
    const m = machine orelse return "";
    return @ptrCast(&m.last_error[0]);
}

pub export fn ci_vm_last_error_code(machine: ?*VM) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    return m.last_error_code;
}

pub export fn ci_vm_clear_error(machine: ?*VM) c_int {
    const m = machine orelse return CI_E_INVALID_ARGUMENT;
    m.clearError();
    return CI_OK;
}
