const std = @import("std");
const builtin = @import("builtin");
const abi = @import("ffi/abi.zig");
const plan_loader = @import("ffi/plan_loader.zig");
const platform = @import("ffi/platform.zig");
const native = @import("ffi/native.zig");

pub const MAX_FUNCS: usize = 8;
pub const MAX_NAME: usize = 32;
pub const MAX_STACK: usize = 1024;
pub const MAX_FRAMES: usize = 64;
pub const MAX_MODULE: usize = 4096;

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
};

const CallbackEntry = struct {
    func: usize,
    plan: abi.CallPlan,
};

var callback_entries: [256]?CallbackEntry = [_]?CallbackEntry{null} ** 256;
var callback_vm: ?*VM = null;

fn f32FromValue(v: Value) f32 {
    const bits: u32 = @truncate(@as(u64, @bitCast(v.i)));
    return @bitCast(bits);
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
        else => false,
    };
}

pub const VM = struct {
    module_buf: [MAX_MODULE]u8 = undefined,
    module_len: usize = 0,
    functions: [MAX_FUNCS]Function = undefined,
    func_count: usize = 0,
    values: [MAX_STACK]Value = undefined,
    sp: usize = 0,
    mem: [65536]u8 = undefined,
    mem_top: usize = 0,
    plan_store: ?*plan_loader.Store = null,
    libc_handle: ?*anyopaque = null,
    libraries: [8]?*anyopaque = [_]?*anyopaque{null} ** 8,
    library_count: usize = 0,
    symbol_buf: [256]u8 = undefined,
    ret_buf: [256]u8 = undefined,
    frames: [MAX_FRAMES]Frame = undefined,
    frame_count: usize = 0,
    result: i64 = 0,
    last_error: [128]u8 = undefined,

    pub fn setError(self: *VM, msg: []const u8) void {
        const n = @min(msg.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..n], msg[0..n]);
        self.last_error[n] = 0;
    }

    pub fn loadPlans(self: *VM, bytes: []const u8) !void {
        const new_store = try plan_loader.decode(std.heap.page_allocator, bytes);
        if (new_store.abi_id != platform.abi_id) {
            std.heap.page_allocator.destroy(new_store);
            return error.BadAbi;
        }
        if (self.plan_store) |old| std.heap.page_allocator.destroy(old);
        self.plan_store = new_store;
    }

    fn freePlans(self: *VM) void {
        if (self.plan_store) |old| {
            std.heap.page_allocator.destroy(old);
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

    pub fn loadPackage(self: *VM, bytes: []const u8) !void {
        if (bytes.len < 15) return error.BadPackage;
        if (!std.mem.eql(u8, bytes[0..5], "CIPKG")) return error.BadPackageMagic;
        if (bytes[5] != 1) return error.BadPackageVersion;
        const module_len = @as(u32, bytes[7]) |
            (@as(u32, bytes[8]) << 8) |
            (@as(u32, bytes[9]) << 16) |
            (@as(u32, bytes[10]) << 24);
        const plan_len = @as(u32, bytes[11]) |
            (@as(u32, bytes[12]) << 8) |
            (@as(u32, bytes[13]) << 16) |
            (@as(u32, bytes[14]) << 24);
        const m: usize = module_len;
        const p: usize = plan_len;
        if (15 + m + p != bytes.len) return error.BadPackageSize;
        try self.loadModuleBytes(bytes[15 .. 15 + m]);
        try self.loadPlans(bytes[15 + m .. 15 + m + p]);
    }

    fn searchSymbol(self: *VM, cname: [*:0]const u8) ?*const anyopaque {
        if (native.symbol(null, cname)) |sym| return sym;
        var li: usize = self.library_count;
        while (li > 0) {
            li -= 1;
            if (self.libraries[li]) |handle| {
                if (native.symbol(handle, cname)) |sym| return sym;
            }
        }
        if (self.libc_handle == null) {
            self.libc_handle = native.defaultC();
        }
        if (self.libc_handle) |handle| {
            if (native.symbol(handle, cname)) |sym| return sym;
        }
        return null;
    }

    fn resolveNative(self: *VM, name: []const u8) !*const anyopaque {
        if (name.len >= self.symbol_buf.len) return error.SymbolTooLong;
        @memcpy(self.symbol_buf[0..name.len], name);
        self.symbol_buf[name.len] = 0;
        const cname: [*:0]const u8 = @ptrCast(&self.symbol_buf[0]);
        if (self.searchSymbol(cname)) |sym| return sym;
        if (native.alias(name)) |alt| {
            const alias_name = std.mem.span(alt);
            if (alias_name.len < self.symbol_buf.len) {
                @memcpy(self.symbol_buf[0..alias_name.len], alias_name);
                self.symbol_buf[alias_name.len] = 0;
                const acname: [*:0]const u8 = @ptrCast(&self.symbol_buf[0]);
                if (self.searchSymbol(acname)) |sym| return sym;
            }
        }
        return error.SymbolNotFound;
    }

    fn invokeFfi(self: *VM, plan: abi.CallPlan, target: *const anyopaque) !void {
        try platform.validate(plan);
        var arg_block: [256]u8 = [_]u8{0} ** 256;
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

        var stack_buf: [256]u8 align(16) = [_]u8{0} ** 256;
        var frame: platform.Frame = std.mem.zeroes(platform.Frame);
        if (plan.sret and sret_ptr == null) {
            const rs: usize = @intCast(plan.ret_size);
            if (rs > self.ret_buf.len) return error.ReturnTooLarge;
        }
        platform.configure(&frame, plan, &self.ret_buf, &stack_buf, sret_ptr);
        platform.marshal(&frame, plan, &arg_block, &stack_buf);
        platform.invoke(&frame, target);

        var ret_block: [256]u8 = [_]u8{0} ** 256;
        platform.readRet(&frame, plan, &ret_block);

        if (plan.sret) {
            // sret calls in C are void; the callee wrote through the caller's pointer.
        } else if (plan.ret_locs.len == 1) {
            const loc = plan.ret_locs[0];
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            var bits: u64 = 0;
            @memcpy(std.mem.asBytes(&bits)[0..n], ret_block[off..][0..n]);
            try self.push(.{ .i = @bitCast(bits) });
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

    pub fn loadModuleBytes(self: *VM, bytes: []const u8) !void {
        if (bytes.len > self.module_buf.len) return error.ModuleTooLarge;
        @memcpy(self.module_buf[0..bytes.len], bytes);
        self.module_len = bytes.len;
        try self.parseModule();
    }

    fn parseModule(self: *VM) !void {
        var r = Reader{ .data = self.module_buf[0..self.module_len] };
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
        var fi: usize = 0;
        while (fi < self.func_count) : (fi += 1) {
            if (std.mem.eql(u8, self.functions[fi].name, name)) break;
        }
        if (fi == self.func_count) return error.EntryNotFound;

        for (0..MAX_STACK) |i| self.values[i] = .{ .i = 0 };
        self.sp = 0;
        self.mem_top = 0;
        @memset(&self.mem, 0);
        self.frame_count = 0;
        self.result = 0;

        const entry_fn = self.functions[fi];
        const entry_locals: usize = entry_fn.local_count;
        self.sp = entry_locals;
        if (self.sp > MAX_STACK) return error.StackOverflow;

        return self.executeLoop(fi, 0, 0);
    }

    pub fn runCallback(self: *VM, func_index: usize, args: []const Value) !i64 {
        if (func_index >= self.func_count) return error.BadFunction;
        const f = self.functions[func_index];
        if (args.len != f.param_count) return error.BadArgCount;
        const saved_sp = self.sp;
        const saved_frames = self.frame_count;
        const saved_result = self.result;
        const base = saved_sp;
        const locals: usize = f.local_count;
        if (base + locals > MAX_STACK) return error.StackOverflow;
        for (args, 0..) |v, i| self.values[base + i] = v;
        var i: usize = args.len;
        while (i < locals) : (i += 1) self.values[base + i] = .{ .i = 0 };
        self.sp = base + locals;
        const result = self.executeLoop(func_index, base, saved_frames) catch |err| {
            self.sp = saved_sp;
            self.frame_count = saved_frames;
            self.result = saved_result;
            return err;
        };
        self.sp = saved_sp;
        self.frame_count = saved_frames;
        self.result = saved_result;
        return result;
    }

    fn executeLoop(self: *VM, start_fi: usize, start_base: usize, stop_frames: usize) !i64 {
        var base: usize = start_base;
        var current: usize = start_fi;
        var ip: usize = 0;

        while (true) {
            const f = self.functions[current];
            const code = f.code;
            if (ip >= code.len) return error.TruncatedCode;
            const op = code[ip];
            ip += 1;

            switch (op) {
                OP_RET, OP_RET_VOID => {
                    const v: Value = if (op == OP_RET) try self.pop() else .{ .i = 0 };
                    if (self.frame_count == stop_frames) {
                        self.result = v.i;
                        return v.i;
                    }
                    const fr = self.frames[self.frame_count - 1];
                    self.frame_count -= 1;
                    self.sp = base;
                    try self.push(v);
                    base = fr.base;
                    current = fr.func;
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
                    try self.push(.{ .i = @intFromFloat(fval) });
                },
                OP_SITOFP => {
                    const v = try self.pop();
                    const fval: f64 = @floatFromInt(v.i);
                    try self.push(.{ .i = @bitCast(fval) });
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
                    try self.push(.{ .i = @intFromFloat(fval) });
                },
                OP_SITOFP32 => {
                    const v = try self.pop();
                    const fval: f32 = @floatFromInt(v.i);
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
                    if (slot >= callback_entries.len) return error.BadCallbackSlot;
                    const fidx: usize = func;
                    if (fidx >= self.func_count) return error.BadFunction;
                    const store = self.plan_store orelse return error.NoPlans;
                    const pidx: usize = plan_idx;
                    const p = store.planAt(pidx) orelse return error.BadPlan;
                    callback_entries[slot] = .{
                        .func = fidx,
                        .plan = store.callPlan(p),
                    };
                    callback_vm = self;
                    const addr = platform.callbackTable(slot) orelse return error.UnsupportedCallback;
                    const addr64: u64 = @intCast(@intFromPtr(addr));
                    try self.push(.{ .i = @bitCast(addr64) });
                },
                OP_CALL_NATIVE, OP_CALL_VARARG => {
                    const idx = try readU16(code, &ip);
                    const store = self.plan_store orelse return error.NoPlans;
                    const i: usize = idx;
                    const p = store.planAt(i) orelse return error.BadPlan;
                    const plan = store.callPlan(p);
                    const n: usize = p.name_len;
                    const target = try self.resolveNative(p.name[0..n]);
                    try self.invokeFfi(plan, target);
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
                OP_LOAD_MEM => {
                    const size = try readU8(code, &ip);
                    const v = try self.pop();
                    const addr: usize = addressFromBits(v.i);
                    switch (size) {
                        1 => {
                            const p: *align(1) const u8 = @ptrFromInt(addr);
                            const x: i8 = @bitCast(p.*);
                            try self.push(.{ .i = x });
                        },
                        2 => {
                            const p: *align(1) const u16 = @ptrFromInt(addr);
                            const x: i16 = @bitCast(p.*);
                            try self.push(.{ .i = x });
                        },
                        4 => {
                            const p: *align(1) const u32 = @ptrFromInt(addr);
                            const x: i32 = @bitCast(p.*);
                            try self.push(.{ .i = x });
                        },
                        8 => {
                            const p: *align(1) const i64 = @ptrFromInt(addr);
                            try self.push(.{ .i = p.* });
                        },
                        else => return error.BadMemorySize,
                    }
                },
                OP_STORE_MEM => {
                    const size = try readU8(code, &ip);
                    const av = try self.pop();
                    const vv = try self.pop();
                    const addr: usize = addressFromBits(av.i);
                    const bits: u64 = @bitCast(vv.i);
                    switch (size) {
                        1 => @as(*align(1) u8, @ptrFromInt(addr)).* = @truncate(bits),
                        2 => @as(*align(1) u16, @ptrFromInt(addr)).* = @truncate(bits),
                        4 => @as(*align(1) u32, @ptrFromInt(addr)).* = @truncate(bits),
                        8 => @as(*align(1) u64, @ptrFromInt(addr)).* = bits,
                        else => return error.BadMemorySize,
                    }
                },
                OP_MEMCPY => {
                    const len_v = try self.pop();
                    const src_v = try self.pop();
                    const dst_v = try self.pop();
                    if (len_v.i < 0) return error.BadMemorySize;
                    const len: usize = @intCast(len_v.i);
                    const dst: [*]u8 = @ptrFromInt(addressFromBits(dst_v.i));
                    const src: [*]const u8 = @ptrFromInt(addressFromBits(src_v.i));
                    @memcpy(dst[0..len], src[0..len]);
                },
                OP_MEMSET => {
                    const len_v = try self.pop();
                    const val_v = try self.pop();
                    const dst_v = try self.pop();
                    if (len_v.i < 0) return error.BadMemorySize;
                    const len: usize = @intCast(len_v.i);
                    const dst: [*]u8 = @ptrFromInt(addressFromBits(dst_v.i));
                    const byte: u8 = @truncate(@as(u64, @bitCast(val_v.i)));
                    @memset(dst[0..len], byte);
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
                    };
                    self.frame_count += 1;
                    base = callee_base;
                    current = fidx;
                    self.sp = callee_base + locals;
                    if (self.sp > MAX_STACK) return error.StackOverflow;
                    var li: usize = params;
                    while (li < locals) : (li += 1) {
                        self.values[callee_base + li] = .{ .i = 0 };
                    }
                    ip = 0;
                },
                else => return error.BadOpcode,
            }
        }
    }

    fn push(self: *VM, v: Value) !void {
        if (self.sp >= MAX_STACK) return error.StackOverflow;
        self.values[self.sp] = v;
        self.sp += 1;
    }

    fn pushF32(self: *VM, f: f32) !void {
        const bits: u32 = @bitCast(f);
        try self.push(.{ .i = @intCast(bits) });
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

fn readU64Ptr(ptr: [*]const u8) u64 {
    return @as(*align(1) const u64, @ptrCast(ptr)).*;
}

pub export fn ci_callback_dispatch(slot: u64, frame: *platform.CallbackFrame) callconv(.C) void {
    const s: usize = @intCast(slot);
    if (s >= callback_entries.len) return;
    const entry = callback_entries[s] orelse return;
    const machine = callback_vm orelse return;
    platform.validate(entry.plan) catch return;
    const n: usize = entry.plan.args.len;
    if (n > 8) return;
    var values: [8]Value = undefined;
    for (entry.plan.args, 0..) |arg, i| {
        values[i] = if (arg.is_struct)
            .{ .u = platform.callbackStructPtr(frame, arg.locs[0]) }
        else
            .{ .u = platform.callbackReadArg(frame, arg.locs[0]) };
    }
    const result = machine.runCallback(entry.func, values[0..n]) catch return;
    if (entry.plan.ret_locs.len == 0) return;
    platform.callbackWriteRet(frame, entry.plan.ret_locs[0], @bitCast(result));
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

pub export fn ci_vm_create(stack_size: usize) ?*VM {
    _ = stack_size;
    const machine = std.heap.page_allocator.create(VM) catch return null;
    machine.* = .{};
    machine.setError("");
    return machine;
}

pub export fn ci_vm_destroy(machine: ?*VM) void {
    if (machine) |m| {
        m.freePlans();
        std.heap.page_allocator.destroy(m);
    }
}

pub export fn ci_vm_load_module(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return -1;
    m.loadModuleBytes(data[0..size]) catch |err| {
        m.setError(@errorName(err));
        return -1;
    };
    return 0;
}

pub export fn ci_vm_load_plans(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return -1;
    m.loadPlans(data[0..size]) catch |err| {
        m.setError(@errorName(err));
        return -1;
    };
    return 0;
}

pub export fn ci_vm_load_package(machine: ?*VM, data: [*]const u8, size: usize) c_int {
    const m = machine orelse return -1;
    m.loadPackage(data[0..size]) catch |err| {
        m.setError(@errorName(err));
        return -1;
    };
    return 0;
}

pub export fn ci_vm_load_library(machine: ?*VM, path: [*:0]const u8) c_int {
    const m = machine orelse return -1;
    m.loadLibrary(std.mem.span(path)) catch |err| {
        m.setError(@errorName(err));
        return -1;
    };
    return 0;
}

pub export fn ci_vm_run(machine: ?*VM, entry: [*:0]const u8) c_int {
    const m = machine orelse return -1;
    const result = m.runEntry(std.mem.span(entry)) catch |err| {
        m.setError(@errorName(err));
        return -1;
    };
    m.result = result;
    return @intCast(result);
}

pub export fn ci_vm_last_error(machine: ?*VM) [*:0]const u8 {
    const m = machine orelse return "";
    return @ptrCast(&m.last_error[0]);
}
