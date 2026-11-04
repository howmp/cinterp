const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const link_loader = @import("link_loader.zig");

pub const Kind = enum(u8) { sysv = 1, win64 = 2, win32 = 3, aapcs64 = 4 };

pub const abi_kind: Kind = if (builtin.os.tag == .windows)
    (if (builtin.cpu.arch == .x86_64)
        .win64
    else if (builtin.cpu.arch == .x86)
        .win32
    else
        @compileError("unsupported Windows architecture"))
else if (builtin.cpu.arch == .x86_64)
    .sysv
else if (builtin.cpu.arch == .aarch64)
    .aapcs64
else
    @compileError("unsupported architecture");

pub const abi_id: u8 = @intFromEnum(abi_kind);
pub const callback_supported = true;
pub const os_id: u8 = switch (builtin.os.tag) {
    .linux => 1,
    .windows => 2,
    else => 0,
};
pub const os_supported = builtin.os.tag == .linux or builtin.os.tag == .windows;
pub const libc_supported = builtin.os.tag != .linux or builtin.abi != .musl;
pub const arch_id: u8 = switch (builtin.cpu.arch) {
    .x86_64 => 1,
    .x86 => 2,
    .aarch64 => 3,
    else => 0,
};
pub const ptr_bits: u8 = @bitSizeOf(usize);
pub const runtime_version: u16 = 1;
pub const runtime_features: u64 = (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) |
    (if (builtin.cpu.arch == .aarch64) @as(u64, 1 << 1) else @as(u64, 1 << 0));

pub fn validateTarget(target: link_loader.TargetInfo) !void {
    if (!os_supported) return error.UnsupportedOs;
    if (target.arch != arch_id or target.os != os_id or target.abi != abi_id or
        target.ptr_bits != ptr_bits or target.endian != 1)
        return error.TargetMismatch;
    if ((target.features & ~runtime_features) != 0) return error.UnsupportedFeature;
    if (target.min_runtime > runtime_version) return error.RuntimeTooOld;
}

pub const SysVFrame = extern struct {
    gpr: [6]u64,
    xmm: [8][2]u64,
    sse_count: u8,
    _pad: [7]u8,
    stack: [*]u8,
    stack_size: usize,
    sret: ?*anyopaque,
    ret_rax: u64,
    ret_rdx: u64,
    ret_xmm0: [2]u64,
    ret_xmm1: [2]u64,
    ret_x87: u8,
    _pad2: [7]u8,
    ret_st0: [16]u8,
};

pub const Win64Frame = extern struct {
    gpr: [4]u64,
    xmm: [4][2]u64,
    sse_count: u8,
    _pad: [7]u8,
    stack: [*]u8,
    stack_size: usize,
    sret: ?*anyopaque,
    ret_rax: u64,
    ret_rdx: u64,
    ret_xmm0: [2]u64,
    ret_xmm1: [2]u64,
};

pub const Win32Frame = extern struct {
    eax: u32,
    edx: u32,
    st0: f64,
    stack: [*]u8,
    stack_size: u32,
    conv: u32,
    ret_x87: u8,
    _pad: [3]u8,
    ret_st0_f80: [16]u8,
};

pub const Arm64Frame = extern struct {
    gpr: [8]u64,
    vec: [8][2]u64,
    sret: u64,
    stack: [*]u8,
    stack_size: usize,
    ret_x0: u64,
    ret_x1: u64,
    _pad: u64,
    ret_v0: [2]u64,
    ret_v1: [2]u64,
    ret_v2: [2]u64,
    ret_v3: [2]u64,
};

pub const Frame = switch (abi_kind) {
    .sysv => SysVFrame,
    .win64 => Win64Frame,
    .win32 => Win32Frame,
    .aapcs64 => Arm64Frame,
};

pub const SysVCbFrame = extern struct {
    slot: u64,
    gpr: [6]u64,
    xmm: [8][2]u64,
    stack_args: [*]u8,
    ret_rax: u64,
    ret_rdx: u64,
    ret_xmm0: [2]u64,
    ret_xmm1: [2]u64,
    ret_st0: [16]u8,
    ret_x87: u8,
    _ret_pad: [7]u8,
};

pub const Win64CbFrame = extern struct {
    slot: u64,
    gpr: [4]u64,
    xmm: [4][2]u64,
    stack_args: [*]u8,
    ret_rax: u64,
    ret_rdx: u64,
    ret_xmm0: [2]u64,
    ret_xmm1: [2]u64,
    saved_xmm6_15: [10][2]u64,
};

pub const Win32CbFrame = extern struct {
    slot: u32,
    stack_args: [*]u8,
    ret_eax: u32,
    ret_edx: u32,
    ret_st0: f64,
    ret_x87: u8,
    _pad0: [3]u8,
    /// Argument bytes the trampoline adds to ESP after `leave`: the stack
    /// image size for a `__stdcall` callback (the callee pops them) and 0 for
    /// `__cdecl` (the caller does). `ci_callback_dispatch` fills this in before
    /// running the VM function; `callbacks_x86_win32.S` reads offset 28 as a
    /// dword so the trampoline can use a memory operand for the stack adjust.
    cleanup: u32,
    ret_st0_f80: [16]u8,
    /// Original ECX/EDX at trampoline entry, for `__fastcall`/`__thiscall`
    /// callbacks (thiscall uses only ECX).
    fast_ecx: u32,
    fast_edx: u32,
};

pub const Arm64CbFrame = extern struct {
    slot: u64,
    gpr: [8]u64,
    _pad0: u64,
    vec: [8][2]u64,
    stack_args: [*]u8,
    ret_x0: u64,
    ret_x1: u64,
    _pad1: u64,
    ret_v0: [2]u64,
    ret_v1: [2]u64,
    saved_v8_15: [8]u64,
    ret_v2: [2]u64,
    ret_v3: [2]u64,
    sret: u64,
    _pad2: u64,
};

pub const CallbackFrame = switch (abi_kind) {
    .sysv => SysVCbFrame,
    .win64 => Win64CbFrame,
    .win32 => Win32CbFrame,
    .aapcs64 => Arm64CbFrame,
};

comptime {
    switch (abi_kind) {
        .sysv => {
            if (@sizeOf(SysVCbFrame) != 264) @compileError("bad sysv cb size");
        },
        .win64 => {
            if (@sizeOf(Win64CbFrame) != 320) @compileError("bad win64 cb size");
            if (@offsetOf(Win64CbFrame, "saved_xmm6_15") != 160) @compileError("bad win64 cb saved");
        },
        .win32 => {
            if (@sizeOf(Win32CbFrame) != 56) @compileError("bad win32 cb size");
            if (@offsetOf(Win32CbFrame, "ret_st0") != 16) @compileError("bad win32 cb st0");
            // `callbacks_x86_win32.S` hardcodes CB_CLEANUP = 28.
            if (@offsetOf(Win32CbFrame, "cleanup") != 28) @compileError("bad win32 cb cleanup");
            if (@offsetOf(Win32CbFrame, "ret_st0_f80") != 32) @compileError("bad win32 cb st0 f80");
            if (@offsetOf(Win32CbFrame, "fast_ecx") != 48) @compileError("bad win32 cb ecx");
            if (@offsetOf(Win32CbFrame, "fast_edx") != 52) @compileError("bad win32 cb edx");
        },
        .aapcs64 => {
            if (@sizeOf(Arm64CbFrame) != 384) @compileError("bad arm64 cb size");
            if (@offsetOf(Arm64CbFrame, "vec") != 80) @compileError("bad arm64 cb vec");
            if (@offsetOf(Arm64CbFrame, "ret_v0") != 240) @compileError("bad arm64 cb v0");
            if (@offsetOf(Arm64CbFrame, "sret") != 368) @compileError("bad arm64 cb sret");
        },
    }
}

extern fn ci_abi_call_sysv64(frame: *SysVFrame, target: *const anyopaque) callconv(.C) void;
extern fn ci_win64_call(frame: *Win64Frame, target: *const anyopaque) callconv(.C) void;
extern fn ci_win32_call(frame: *Win32Frame, target: *const anyopaque, conv: u32) callconv(.C) void;
extern fn ci_arm64_call(frame: *Arm64Frame, target: *const anyopaque) callconv(.C) void;

extern const ci_cb_sysv_table: [256]*const anyopaque;

fn readU64(args: *const [4096]u8, off: usize) u64 {
    return @as(*align(1) const u64, @ptrCast(&args[off])).*;
}

fn configureSysV(frame: *SysVFrame, plan: abi.CallPlan, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.sse_count = plan.sse_count;
    frame.ret_x87 = 0;
    for (plan.ret_locs) |loc| {
        if (loc.kind == .st0) frame.ret_x87 = 1;
    }
    if (plan.sret) frame.sret = sret_ptr.?;
}

fn configureWin64(frame: *Win64Frame, plan: abi.CallPlan, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.sse_count = plan.sse_count;
    if (plan.sret) frame.sret = sret_ptr.?;
}

/// i686 `__fastcall` takes its first two 4-byte scalar arguments in ECX and
/// EDX; aggregates, wider values and the hidden sret pointer stay on the stack,
/// which the callee pops. Returns the register slot for `arg`, or null when the
/// argument belongs to the stack.
pub fn win32FastSlot(arg: abi.ArgPlan, gpr: *u8) ?u8 {
    if (gpr.* >= 2 or arg.is_struct or arg.size != 4 or arg.locs.len != 1) return null;
    const slot = gpr.*;
    gpr.* += 1;
    return slot;
}

/// `__thiscall` has one register argument (the `this`/first 4-byte scalar) in
/// ECX; the rest go on the stack and are popped by the callee.
pub fn win32ThisSlot(arg: abi.ArgPlan, used: *bool) bool {
    if (used.* or arg.is_struct or arg.size != 4 or arg.locs.len != 1) return false;
    used.* = true;
    return true;
}

const Win32FastLayout = struct {
    stack_size: u32 = 0,
    sret_offset: u32 = 0,
};

const Win32ThisLayout = struct {
    stack_size: u32 = 0,
    sret_offset: u32 = 0,
};

/// Bytes `arg` occupies in the outgoing stack area, on a 4-byte grid.
pub fn win32StackBytes(arg: abi.ArgPlan) u32 {
    var total: u32 = 0;
    for (arg.locs) |loc| total += loc.size;
    return std.mem.alignForward(u32, total, 4);
}

/// The outgoing argument area `__fastcall` needs: everything `win32FastSlot`
/// leaves out, laid out in argument order on a 4-byte grid.
fn win32FastLayout(plan: abi.CallPlan) Win32FastLayout {
    var layout = Win32FastLayout{};
    var gpr: u8 = 0;
    for (plan.args) |arg| {
        const loc = arg.locs[0];
        if (loc.kind == .sret) {
            layout.sret_offset = layout.stack_size;
            layout.stack_size += 4;
            continue;
        }
        if (win32FastSlot(arg, &gpr) != null) continue;
        layout.stack_size += win32StackBytes(arg);
    }
    return layout;
}

fn win32ThisLayout(plan: abi.CallPlan) Win32ThisLayout {
    var layout = Win32ThisLayout{};
    var used = false;
    for (plan.args) |arg| {
        const loc = arg.locs[0];
        if (loc.kind == .sret) {
            layout.sret_offset = layout.stack_size;
            layout.stack_size += 4;
            continue;
        }
        if (win32ThisSlot(arg, &used)) continue;
        layout.stack_size += win32StackBytes(arg);
    }
    return layout;
}

fn configureWin32(frame: *Win32Frame, plan: abi.CallPlan, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = switch (plan.conv) {
        2 => win32FastLayout(plan).stack_size,
        3 => win32ThisLayout(plan).stack_size,
        else => plan.stack_size,
    };
    frame.conv = plan.conv;
    frame.ret_x87 = 0;
    for (plan.ret_locs) |loc| {
        // i686 returns every floating point value in ST0. A narrow loc
        // (`float`/`double`, <= 8 bytes) carries an f64 image in the frame,
        // while `long double` keeps its 10-byte x87 image, so the asm stub has
        // to know which form the plan expects.
        switch (loc.kind) {
            .xmm0 => frame.ret_x87 = 1,
            .st0 => frame.ret_x87 = if (loc.size > 8) 2 else 1,
            else => {},
        }
    }
    if (plan.sret) {
        // The hidden return pointer is an ordinary stack argument on i686; the
        // `sret` loc's `index` is its offset in the outgoing argument area
        // (`__fastcall`/`__thiscall` re-lay the area, so its slot moves with it).
        const ptr: u32 = @truncate(@intFromPtr(sret_ptr.?));
        for (plan.args) |arg| {
            for (arg.locs) |loc| {
                if (loc.kind != .sret) continue;
                const idx: usize = switch (plan.conv) {
                    2 => win32FastLayout(plan).sret_offset,
                    3 => win32ThisLayout(plan).sret_offset,
                    else => @intCast(loc.index),
                };
                @as(*align(1) u32, @ptrCast(&stack_buf[idx])).* = ptr;
            }
        }
    }
}

fn configureArm64(frame: *Arm64Frame, plan: abi.CallPlan, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    if (plan.sret) frame.sret = @intFromPtr(sret_ptr.?);
}

pub fn configure(frame: *Frame, plan: abi.CallPlan, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    switch (abi_kind) {
        .sysv => configureSysV(@ptrCast(frame), plan, stack_buf, sret_ptr),
        .win64 => configureWin64(@ptrCast(frame), plan, stack_buf, sret_ptr),
        .win32 => configureWin32(@ptrCast(frame), plan, stack_buf, sret_ptr),
        .aapcs64 => configureArm64(@ptrCast(frame), plan, stack_buf, sret_ptr),
    }
}

fn marshalSysV(frame: *SysVFrame, plan: abi.CallPlan, args: *const [4096]u8, stack_buf: *[4096]u8) void {
    for (plan.args) |arg| {
        for (arg.locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            switch (loc.kind) {
                .gpr => frame.gpr[@intCast(loc.index)] = readU64(args, off),
                .xmm => {
                    const dst = std.mem.asBytes(&frame.xmm[@intCast(loc.index)]);
                    @memcpy(dst[0..n], args[off..][0..n]);
                },
                .stack => {
                    const idx: usize = @intCast(loc.index);
                    @memcpy(stack_buf[idx..][0..n], args[off..][0..n]);
                },
                .sret => frame.gpr[0] = @intFromPtr(frame.sret.?),
                else => unreachable,
            }
        }
    }
}

fn marshalWin64(frame: *Win64Frame, plan: abi.CallPlan, args: *const [4096]u8, stack_buf: *[4096]u8) void {
    for (plan.args) |arg| {
        for (arg.locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            switch (loc.kind) {
                .gpr => frame.gpr[@intCast(loc.index)] = readU64(args, off),
                .xmm => {
                    const dst = std.mem.asBytes(&frame.xmm[@intCast(loc.index)]);
                    @memcpy(dst[0..n], args[off..][0..n]);
                },
                .stack => {
                    const idx: usize = @intCast(loc.index);
                    @memcpy(stack_buf[idx..][0..n], args[off..][0..n]);
                },
                .sret => {
                    frame.gpr[0] = @intFromPtr(frame.sret.?);
                },
                else => unreachable,
            }
        }
    }
}

fn marshalWin32(frame: *Win32Frame, plan: abi.CallPlan, args: *const [4096]u8, stack_buf: *[4096]u8) void {
    if (plan.conv == 2) return marshalWin32Fast(frame, plan, args, stack_buf);
    if (plan.conv == 3) return marshalWin32This(frame, plan, args, stack_buf);
    for (plan.args) |arg| {
        for (arg.locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            switch (loc.kind) {
                .gpr => {
                    const value = readU64(args, off);
                    if (loc.index == 0) frame.eax = @truncate(value) else frame.edx = @truncate(value);
                },
                .stack => {
                    const idx: usize = @intCast(loc.index);
                    @memcpy(stack_buf[idx..][0..n], args[off..][0..n]);
                },
                .sret => {
                    // `configureWin32` already stored the caller's pointer at
                    // the stack slot; the arg block never holds it.
                },
                else => unreachable,
            }
        }
    }
}

/// `__fastcall` marshalling: `win32FastSlot` arguments load ECX/EDX and the
/// rest fill the outgoing stack area `win32FastLayout` sized, in argument order.
fn marshalWin32Fast(frame: *Win32Frame, plan: abi.CallPlan, args: *const [4096]u8, stack_buf: *[4096]u8) void {
    var stack_off: usize = 0;
    var gpr: u8 = 0;
    for (plan.args) |arg| {
        if (arg.locs[0].kind == .sret) {
            // `configureWin32` already stored the caller's pointer at the slot.
            stack_off += 4;
            continue;
        }
        if (win32FastSlot(arg, &gpr)) |slot| {
            const off: usize = @intCast(arg.locs[0].offset);
            const n: usize = @intCast(arg.locs[0].size);
            var word: [4]u8 = [_]u8{0} ** 4;
            @memcpy(word[0..@min(n, 4)], args[off..][0..@min(n, 4)]);
            const value = std.mem.readInt(u32, &word, .little);
            if (slot == 0) frame.eax = value else frame.edx = value;
            continue;
        }
        for (arg.locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            @memcpy(stack_buf[stack_off..][0..n], args[off..][0..n]);
            stack_off += n;
        }
        stack_off = std.mem.alignForward(usize, stack_off, 4);
    }
}

/// `__thiscall` marshalling: the first 4-byte scalar (the `this`/first arg)
/// goes in ECX (`frame.eax`, which the asm loads into ECX for conv=3); the rest
/// fill the callee-popped stack area. Sret stays on the stack.
fn marshalWin32This(frame: *Win32Frame, plan: abi.CallPlan, args: *const [4096]u8, stack_buf: *[4096]u8) void {
    var stack_off: usize = 0;
    var used = false;
    for (plan.args) |arg| {
        if (arg.locs[0].kind == .sret) {
            stack_off += 4;
            continue;
        }
        if (win32ThisSlot(arg, &used)) {
            const off: usize = @intCast(arg.locs[0].offset);
            const n: usize = @intCast(arg.locs[0].size);
            var word: [4]u8 = [_]u8{0} ** 4;
            @memcpy(word[0..@min(n, 4)], args[off..][0..@min(n, 4)]);
            frame.eax = std.mem.readInt(u32, &word, .little);
            continue;
        }
        for (arg.locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            @memcpy(stack_buf[stack_off..][0..n], args[off..][0..n]);
            stack_off += n;
        }
        stack_off = std.mem.alignForward(usize, stack_off, 4);
    }
}

fn marshalArm64(frame: *Arm64Frame, plan: abi.CallPlan, args: *const [4096]u8, stack_buf: *[4096]u8) void {
    for (plan.args) |arg| {
        for (arg.locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            switch (loc.kind) {
                .gpr => frame.gpr[@intCast(loc.index)] = readU64(args, off),
                .xmm => {
                    const dst = std.mem.asBytes(&frame.vec[@intCast(loc.index)]);
                    @memcpy(dst[0..n], args[off..][0..n]);
                },
                .stack => {
                    const idx: usize = @intCast(loc.index);
                    @memcpy(stack_buf[idx..][0..n], args[off..][0..n]);
                },
                .sret => {},
                else => unreachable,
            }
        }
    }
}

pub fn marshal(frame: *Frame, plan: abi.CallPlan, args: *const [4096]u8, stack_buf: *[4096]u8) void {
    switch (abi_kind) {
        .sysv => marshalSysV(@ptrCast(frame), plan, args, stack_buf),
        .win64 => marshalWin64(@ptrCast(frame), plan, args, stack_buf),
        .win32 => marshalWin32(@ptrCast(frame), plan, args, stack_buf),
        .aapcs64 => marshalArm64(@ptrCast(frame), plan, args, stack_buf),
    }
}

fn readRetSysV(frame: *const SysVFrame, plan: abi.CallPlan, ret: *[4096]u8) void {
    for (plan.ret_locs) |loc| {
        const off: usize = @intCast(loc.offset);
        const n: usize = @intCast(loc.size);
        switch (loc.kind) {
            .rax => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_rax)[0..n]),
            .rdx => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_rdx)[0..n]),
            .xmm0 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_xmm0)[0..n]),
            .xmm1 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_xmm1)[0..n]),
            .st0 => @memcpy(ret[off..][0..n], frame.ret_st0[0..n]),
            else => unreachable,
        }
    }
}

fn readRetWin64(frame: *const Win64Frame, plan: abi.CallPlan, ret: *[4096]u8) void {
    for (plan.ret_locs) |loc| {
        const off: usize = @intCast(loc.offset);
        const n: usize = @intCast(loc.size);
        switch (loc.kind) {
            .rax => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_rax)[0..n]),
            .rdx => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_rdx)[0..n]),
            .xmm0 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_xmm0)[0..n]),
            .xmm1 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_xmm1)[0..n]),
            else => unreachable,
        }
    }
}

fn readRetWin32(frame: *const Win32Frame, plan: abi.CallPlan, ret: *[4096]u8) void {
    for (plan.ret_locs) |loc| {
        const off: usize = @intCast(loc.offset);
        const n: usize = @intCast(loc.size);
        switch (loc.kind) {
            .rax => {
                if (n == 8) {
                    @memcpy(ret[off..][0..4], std.mem.asBytes(&frame.eax)[0..4]);
                    @memcpy(ret[off + 4 ..][0..4], std.mem.asBytes(&frame.edx)[0..4]);
                } else {
                    @memcpy(ret[off..][0..@min(n, 4)], std.mem.asBytes(&frame.eax)[0..@min(n, 4)]);
                }
            },
            .rdx => @memcpy(ret[off..][0..@min(n, 4)], std.mem.asBytes(&frame.edx)[0..@min(n, 4)]),
            .xmm0 => {
                if (n == 4) {
                    const f: f32 = @floatCast(frame.st0);
                    @memcpy(ret[off..][0..4], std.mem.asBytes(&f)[0..4]);
                } else {
                    @memcpy(ret[off..][0..@min(n, 8)], std.mem.asBytes(&frame.st0)[0..@min(n, 8)]);
                }
            },
            .st0 => {
                // `float`/`double` results arrive as an f64 image in `st0`
                // (see `configureWin32`); `long double` keeps the raw x87
                // image the asm stub stored.
                if (n == 4) {
                    const f: f32 = @floatCast(frame.st0);
                    @memcpy(ret[off..][0..4], std.mem.asBytes(&f)[0..4]);
                } else if (n <= 8) {
                    @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.st0)[0..n]);
                } else {
                    @memcpy(ret[off..][0..n], frame.ret_st0_f80[0..n]);
                }
            },
            else => {},
        }
    }
}

fn readRetArm64(frame: *const Arm64Frame, plan: abi.CallPlan, ret: *[4096]u8) void {
    for (plan.ret_locs) |loc| {
        const off: usize = @intCast(loc.offset);
        const n: usize = @intCast(loc.size);
        switch (loc.kind) {
            .rax => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_x0)[0..n]),
            .rdx => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_x1)[0..n]),
            .xmm0 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_v0)[0..n]),
            .xmm1 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_v1)[0..n]),
            .xmm2 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_v2)[0..n]),
            .xmm3 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_v3)[0..n]),
            else => unreachable,
        }
    }
}

pub fn readRet(frame: *const Frame, plan: abi.CallPlan, ret: *[4096]u8) void {
    switch (abi_kind) {
        .sysv => readRetSysV(@ptrCast(frame), plan, ret),
        .win64 => readRetWin64(@ptrCast(frame), plan, ret),
        .win32 => readRetWin32(@ptrCast(frame), plan, ret),
        .aapcs64 => readRetArm64(@ptrCast(frame), plan, ret),
    }
}

fn invokeSysV(frame: *SysVFrame, target: *const anyopaque) void {
    ci_abi_call_sysv64(frame, target);
}

fn invokeWin64(frame: *Win64Frame, target: *const anyopaque) void {
    ci_win64_call(frame, target);
}

fn invokeWin32(frame: *Win32Frame, target: *const anyopaque) void {
    ci_win32_call(frame, target, frame.conv);
}

fn invokeArm64(frame: *Arm64Frame, target: *const anyopaque) void {
    ci_arm64_call(frame, target);
}

pub fn invoke(frame: *Frame, target: *const anyopaque) void {
    switch (abi_kind) {
        .sysv => invokeSysV(@ptrCast(frame), target),
        .win64 => invokeWin64(@ptrCast(frame), target),
        .win32 => invokeWin32(@ptrCast(frame), target),
        .aapcs64 => invokeArm64(@ptrCast(frame), target),
    }
}

/// Size of the byte blocks `vm.invokeFfi` stages arguments, returns and the
/// outgoing stack image in. Every offset/size in a plan has to fit here.
pub const block_size: u16 = 4096;

/// Return register files one ABI can report. Restricting the kinds keeps the
/// `readRet*` switches below exhaustive: a plan can only name a loc kind the
/// matching reader has a case for, so the `unreachable` arms stay dead.
const RetKinds = struct {
    rax: bool = false,
    rdx: bool = false,
    xmm0: bool = false,
    xmm1: bool = false,
    xmm2: bool = false,
    xmm3: bool = false,
    st0: bool = false,

    fn accepts(self: RetKinds, kind: abi.LocKind) bool {
        return switch (kind) {
            .rax => self.rax,
            .rdx => self.rdx,
            .xmm0 => self.xmm0,
            .xmm1 => self.xmm1,
            .xmm2 => self.xmm2,
            .xmm3 => self.xmm3,
            .st0 => self.st0,
            else => false,
        };
    }
};

fn retKindsFor(kind: Kind) RetKinds {
    return switch (kind) {
        // SysV: RAX/RDX, XMM0/XMM1 and ST0 (`long double`).
        .sysv => .{ .rax = true, .rdx = true, .xmm0 = true, .xmm1 = true, .st0 = true },
        // MS x64: RAX/RDX and XMM0/XMM1; `long double` is memory class.
        .win64 => .{ .rax = true, .rdx = true, .xmm0 = true, .xmm1 = true },
        // i686: EAX/EDX and ST0 (every float returns there).
        .win32 => .{ .rax = true, .rdx = true, .xmm0 = true, .st0 = true },
        // AAPCS64: x0/x1 and v0-v3.
        .aapcs64 => .{ .rax = true, .rdx = true, .xmm0 = true, .xmm1 = true, .xmm2 = true, .xmm3 = true },
    };
}

/// Argument register file sizes of one ABI.
const RegLimits = struct { gpr_max: u16, xmm_max: u16 };

fn limitsFor(kind: Kind) RegLimits {
    return switch (kind) {
        .sysv => .{ .gpr_max = 6, .xmm_max = 8 },
        .win64 => .{ .gpr_max = 4, .xmm_max = 4 },
        .win32 => .{ .gpr_max = 2, .xmm_max = 0 },
        .aapcs64 => .{ .gpr_max = 8, .xmm_max = 8 },
    };
}

/// Validate `plan` as if it targeted `kind` instead of the host ABI. Kept free
/// of host state so the rules can be unit-tested for every ABI on any host.
fn validateFor(kind: Kind, plan: abi.CallPlan) !void {
    if (plan.args.len > 64) return error.BadPlan;
    if (plan.ret_locs.len > 8) return error.BadPlan;
    if (plan.stack_size > block_size) return error.BadPlan;
    if (plan.ret_size > block_size) return error.BadPlan;
    if (plan.sse_count > 8) return error.BadPlan;
    // Only i686 carries a calling convention in the plan: 0 = cdecl,
    // 1 = stdcall, 2 = fastcall. Every other ABI has a single C convention and
    // ignores the byte, so it stays unconstrained there.
    if (kind == .win32 and plan.conv > 3) return error.BadPlan;

    const limits = limitsFor(kind);
    var sret_locs: usize = 0;
    for (plan.args) |arg| {
        if (arg.locs.len == 0) return error.BadPlan;
        if (arg.size > block_size) return error.BadPlan;
        // `vm.invokeFfi` copies `arg.size` bytes (`is_struct`) or `loc.size`
        // bytes from the *first* loc's offset into its 4096-byte arg block.
        if (@as(u32, arg.locs[0].offset) + @as(u32, arg.size) > block_size) return error.BadPlan;
        for (arg.locs) |loc| {
            const off: u32 = loc.offset;
            const n: u32 = loc.size;
            if (off + n > block_size) return error.BadPlan;
            switch (loc.kind) {
                .gpr => {
                    if (loc.index >= limits.gpr_max or n > 8 or off + 8 > 256) return error.BadPlan;
                },
                .xmm => {
                    if (loc.index >= limits.xmm_max or n > 16) return error.BadPlan;
                },
                .stack => {
                    // The stack image is exactly `plan.stack_size` bytes and the
                    // asm/copy steps move it through a 4096-byte buffer, so a
                    // loc has to fit both.
                    if (@as(u32, loc.index) + n > plan.stack_size) return error.BadPlan;
                },
                .sret => {
                    if (!plan.sret) return error.BadPlan;
                    sret_locs += 1;
                    // On i686 the loc's `index` is the offset of the hidden
                    // pointer inside the outgoing argument area, which
                    // `configureWin32` writes a machine word through.
                    if (kind == .win32) {
                        const bytes: u32 = @max(n, 4);
                        if (@as(u32, loc.index) + bytes > plan.stack_size) return error.BadPlan;
                    }
                },
                else => return error.BadPlan,
            }
        }
    }
    // `plan.sret` promises a hidden return pointer; without a `.sret` loc no
    // argument carries it and the call would write to a random address.
    if (plan.sret and sret_locs == 0) return error.BadPlan;

    const allowed = retKindsFor(kind);
    for (plan.ret_locs) |loc| {
        const off: u32 = loc.offset;
        const n: u32 = loc.size;
        if (off + n > block_size) return error.BadPlan;
        if (!allowed.accepts(loc.kind)) return error.BadPlan;
        switch (loc.kind) {
            .rax, .rdx => if (n > 8) return error.BadPlan,
            .xmm0, .xmm1, .xmm2, .xmm3, .st0 => if (n > 16) return error.BadPlan,
            else => return error.BadPlan,
        }
    }
    if (plan.ret_locs.len > 0) {
        // `vm.invokeFfi` copies `ret_size` bytes out of the return block: from
        // the first loc's offset for a single loc, from offset 0 for several
        // (where `ret_size <= block_size` above is the only bound needed).
        if (@as(u32, plan.ret_locs[0].offset) + @as(u32, plan.ret_size) > block_size) return error.BadPlan;
    }
}

pub fn validate(plan: abi.CallPlan) !void {
    try validateFor(abi_kind, plan);
}

/// Whether an i686 callback for `plan` can be dispatched through the
/// `callbacks_x86_win32.S` trampolines. The trampoline saves ECX/EDX and the
/// stack argument area, so cdecl, stdcall, fastcall and thiscall callbacks are
/// all supported.
pub fn win32CallbackSupported(plan: abi.CallPlan) bool {
    return plan.conv <= 3;
}

/// Argument bytes the i686 callback trampoline adds to ESP after it returns:
/// the callee-pops stack image for `__stdcall`/`__fastcall`/`__thiscall`, 0 for
/// `__cdecl` (the caller pops). Register arguments do not live in this image.
pub fn win32CallbackCleanup(plan: abi.CallPlan) u32 {
    if (plan.conv == 1) return plan.stack_size;
    if (plan.conv == 2) return win32FastLayout(plan).stack_size;
    if (plan.conv == 3) return win32ThisLayout(plan).stack_size;
    return 0;
}

extern const ci_cb_table: [256]*const anyopaque;

fn readCallbackU64(ptr: [*]const u8) u64 {
    return @as(*align(1) const u64, @ptrCast(ptr)).*;
}

fn callbackReadSysV(frame: *SysVCbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .gpr => frame.gpr[@intCast(loc.index)],
        .xmm => frame.xmm[@intCast(loc.index)][0],
        .stack => readCallbackU64(frame.stack_args + @as(usize, loc.index)),
        .sret => frame.gpr[0],
        else => 0,
    };
}

fn callbackReadWin64(frame: *Win64CbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .gpr => frame.gpr[@intCast(loc.index)],
        .xmm => frame.xmm[@intCast(loc.index)][0],
        .stack => readCallbackU64(frame.stack_args + @as(usize, loc.index)),
        .sret => frame.gpr[0],
        else => 0,
    };
}

fn callbackReadWin32(frame: *Win32CbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .stack => readCallbackU64(frame.stack_args + @as(usize, loc.index)),
        .sret => readCallbackU64(frame.stack_args),
        else => 0,
    };
}

/// Read one of the register arguments captured by the i686 trampoline (ECX/EDX
/// for `__fastcall`, ECX/slot 0 for `__thiscall`).
pub fn callbackReadFastReg(frame: *CallbackFrame, slot: u8) u64 {
    const f: *const Win32CbFrame = @ptrCast(frame);
    return switch (slot) {
        0 => f.fast_ecx,
        1 => f.fast_edx,
        else => 0,
    };
}

/// Read a scalar from the fastcall stack argument area (zero-extended), or
/// return the address of a by-value aggregate at that offset.
pub fn callbackReadFastStackValue(frame: *CallbackFrame, offset: usize, size: usize) u64 {
    const f: *const Win32CbFrame = @ptrCast(frame);
    var bits: u64 = 0;
    const n = @min(size, 8);
    @memcpy(std.mem.asBytes(&bits)[0..n], f.stack_args[offset..][0..n]);
    return bits;
}

pub fn callbackReadFastStructPtr(frame: *CallbackFrame, offset: usize) u64 {
    const f: *const Win32CbFrame = @ptrCast(frame);
    return @intCast(@intFromPtr(f.stack_args + offset));
}

fn callbackReadArm64(frame: *Arm64CbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .gpr => frame.gpr[@intCast(loc.index)],
        .xmm => frame.vec[@intCast(loc.index)][0],
        .stack => readCallbackU64(frame.stack_args + @as(usize, loc.index)),
        .sret => frame.sret,
        else => 0,
    };
}

pub fn callbackReadBytes(frame: *CallbackFrame, loc: abi.Loc, dst: []u8, n: usize) void {
    const count = @min(n, @as(usize, loc.size));
    switch (abi_kind) {
        .sysv => {
            const f: *SysVCbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .gpr => @memcpy(dst[0..count], std.mem.asBytes(&f.gpr[@intCast(loc.index)])[0..count]),
                .xmm => @memcpy(dst[0..count], std.mem.asBytes(&f.xmm[@intCast(loc.index)])[0..count]),
                .stack => @memcpy(dst[0..count], f.stack_args[@intCast(loc.index)..][0..count]),
                .sret => @memcpy(dst[0..@min(count, 8)], std.mem.asBytes(&f.gpr[0])[0..@min(count, 8)]),
                else => {},
            }
        },
        .win64 => {
            const f: *Win64CbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .gpr => @memcpy(dst[0..count], std.mem.asBytes(&f.gpr[@intCast(loc.index)])[0..count]),
                .xmm => @memcpy(dst[0..count], std.mem.asBytes(&f.xmm[@intCast(loc.index)])[0..count]),
                .stack => @memcpy(dst[0..count], f.stack_args[@intCast(loc.index)..][0..count]),
                .sret => @memcpy(dst[0..@min(count, 8)], std.mem.asBytes(&f.gpr[0])[0..@min(count, 8)]),
                else => {},
            }
        },
        .win32 => {
            const f: *Win32CbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .stack => @memcpy(dst[0..count], f.stack_args[@intCast(loc.index)..][0..count]),
                .sret => @memcpy(dst[0..@min(count, 8)], f.stack_args[0..@min(count, 8)]),
                else => {},
            }
        },
        .aapcs64 => {
            const f: *Arm64CbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .gpr => @memcpy(dst[0..count], std.mem.asBytes(&f.gpr[@intCast(loc.index)])[0..count]),
                .xmm => @memcpy(dst[0..count], std.mem.asBytes(&f.vec[@intCast(loc.index)])[0..count]),
                .stack => @memcpy(dst[0..count], f.stack_args[@intCast(loc.index)..][0..count]),
                .sret => @memcpy(dst[0..@min(count, 8)], std.mem.asBytes(&f.sret)[0..@min(count, 8)]),
                else => {},
            }
        },
    }
}

pub fn callbackReadArg(frame: *CallbackFrame, loc: abi.Loc) u64 {
    return switch (abi_kind) {
        .sysv => callbackReadSysV(@ptrCast(frame), loc),
        .win64 => callbackReadWin64(@ptrCast(frame), loc),
        .win32 => callbackReadWin32(@ptrCast(frame), loc),
        .aapcs64 => callbackReadArm64(@ptrCast(frame), loc),
    };
}

fn callbackStructPtrSysV(frame: *SysVCbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .stack => @intCast(@intFromPtr(frame.stack_args + @as(usize, loc.index))),
        else => 0,
    };
}

fn callbackStructPtrWin64(frame: *Win64CbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .stack => @intCast(@intFromPtr(frame.stack_args + @as(usize, loc.index))),
        else => 0,
    };
}

fn callbackStructPtrWin32(frame: *Win32CbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .stack => @intCast(@intFromPtr(frame.stack_args + @as(usize, loc.index))),
        else => 0,
    };
}

fn callbackStructPtrArm64(frame: *Arm64CbFrame, loc: abi.Loc) u64 {
    return switch (loc.kind) {
        .stack => @intCast(@intFromPtr(frame.stack_args + @as(usize, loc.index))),
        else => 0,
    };
}

pub fn callbackStructPtr(frame: *CallbackFrame, loc: abi.Loc) u64 {
    return switch (abi_kind) {
        .sysv => callbackStructPtrSysV(@ptrCast(frame), loc),
        .win64 => callbackStructPtrWin64(@ptrCast(frame), loc),
        .win32 => callbackStructPtrWin32(@ptrCast(frame), loc),
        .aapcs64 => callbackStructPtrArm64(@ptrCast(frame), loc),
    };
}

fn callbackWriteSysV(frame: *SysVCbFrame, loc: abi.Loc, bits: u64) void {
    switch (loc.kind) {
        .rax => frame.ret_rax = bits,
        .rdx => frame.ret_rdx = bits,
        .xmm0 => frame.ret_xmm0[0] = bits,
        .xmm1 => frame.ret_xmm1[0] = bits,
        else => {},
    }
}

fn callbackWriteWin64(frame: *Win64CbFrame, loc: abi.Loc, bits: u64) void {
    switch (loc.kind) {
        .rax => frame.ret_rax = bits,
        .rdx => frame.ret_rdx = bits,
        .xmm0 => frame.ret_xmm0[0] = bits,
        .xmm1 => frame.ret_xmm1[0] = bits,
        else => {},
    }
}

fn callbackWriteWin32(frame: *Win32CbFrame, loc: abi.Loc, bits: u64) void {
    switch (loc.kind) {
        .rax => {
            frame.ret_eax = @truncate(bits);
            if (loc.size == 8) frame.ret_edx = @truncate(bits >> 32);
        },
        .rdx => frame.ret_edx = @truncate(bits),
        .xmm0 => {
            if (loc.size == 4) {
                const f: f32 = @bitCast(@as(u32, @truncate(bits)));
                frame.ret_st0 = @floatCast(f);
            } else {
                frame.ret_st0 = @bitCast(bits);
            }
            frame.ret_x87 = 1;
        },
        .st0 => {
            // Narrow `float`/`double` results travel back through ST0 exactly
            // like `xmm0`; a `long double` result is handed over as raw bytes
            // by `callbackWriteBytes` and keeps the 10-byte x87 image.
            if (loc.size <= 8) {
                if (loc.size == 4) {
                    const f: f32 = @bitCast(@as(u32, @truncate(bits)));
                    frame.ret_st0 = @floatCast(f);
                } else {
                    frame.ret_st0 = @bitCast(bits);
                }
                frame.ret_x87 = 1;
            }
        },
        else => {},
    }
}

fn callbackWriteArm64(frame: *Arm64CbFrame, loc: abi.Loc, bits: u64) void {
    switch (loc.kind) {
        .rax => frame.ret_x0 = bits,
        .rdx => frame.ret_x1 = bits,
        .xmm0 => frame.ret_v0[0] = bits,
        .xmm1 => frame.ret_v1[0] = bits,
        else => {},
    }
}

pub fn callbackWriteBytes(frame: *CallbackFrame, loc: abi.Loc, src: []const u8, n: usize) void {
    const count = @min(n, @as(usize, loc.size));
    switch (abi_kind) {
        .sysv => {
            const f: *SysVCbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .rax => @memcpy(std.mem.asBytes(&f.ret_rax)[0..count], src[0..count]),
                .rdx => @memcpy(std.mem.asBytes(&f.ret_rdx)[0..count], src[0..count]),
                .xmm0 => @memcpy(std.mem.asBytes(&f.ret_xmm0)[0..count], src[0..count]),
                .xmm1 => @memcpy(std.mem.asBytes(&f.ret_xmm1)[0..count], src[0..count]),
                .st0 => {
                    @memcpy(f.ret_st0[0..count], src[0..count]);
                    f.ret_x87 = 1;
                },
                else => {},
            }
        },
        .win64 => {
            const f: *Win64CbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .rax => @memcpy(std.mem.asBytes(&f.ret_rax)[0..count], src[0..count]),
                .rdx => @memcpy(std.mem.asBytes(&f.ret_rdx)[0..count], src[0..count]),
                .xmm0 => @memcpy(std.mem.asBytes(&f.ret_xmm0)[0..count], src[0..count]),
                .xmm1 => @memcpy(std.mem.asBytes(&f.ret_xmm1)[0..count], src[0..count]),
                else => {},
            }
        },
        .win32 => {
            const f: *Win32CbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .rax => @memcpy(std.mem.asBytes(&f.ret_eax)[0..@min(count, 4)], src[0..@min(count, 4)]),
                .rdx => @memcpy(std.mem.asBytes(&f.ret_edx)[0..@min(count, 4)], src[0..@min(count, 4)]),
                .xmm0, .st0 => {
                    @memcpy(f.ret_st0_f80[0..count], src[0..count]);
                    f.ret_x87 = 2;
                },
                else => {},
            }
        },
        .aapcs64 => {
            const f: *Arm64CbFrame = @ptrCast(frame);
            switch (loc.kind) {
                .rax => @memcpy(std.mem.asBytes(&f.ret_x0)[0..count], src[0..count]),
                .rdx => @memcpy(std.mem.asBytes(&f.ret_x1)[0..count], src[0..count]),
                .xmm0 => @memcpy(std.mem.asBytes(&f.ret_v0)[0..count], src[0..count]),
                .xmm1 => @memcpy(std.mem.asBytes(&f.ret_v1)[0..count], src[0..count]),
                .xmm2 => @memcpy(std.mem.asBytes(&f.ret_v2)[0..count], src[0..count]),
                .xmm3 => @memcpy(std.mem.asBytes(&f.ret_v3)[0..count], src[0..count]),
                else => {},
            }
        },
    }
}

pub fn callbackWriteRet(frame: *CallbackFrame, loc: abi.Loc, bits: u64) void {
    switch (abi_kind) {
        .sysv => callbackWriteSysV(@ptrCast(frame), loc, bits),
        .win64 => callbackWriteWin64(@ptrCast(frame), loc, bits),
        .win32 => callbackWriteWin32(@ptrCast(frame), loc, bits),
        .aapcs64 => callbackWriteArm64(@ptrCast(frame), loc, bits),
    }
}

pub fn callbackTable(slot: usize) ?*const anyopaque {
    if (slot >= 256) return null;
    return ci_cb_table[slot];
}

// ----------------------------------------------------------------------- tests
//
// The rules are exercised through `validateFor`, which takes the ABI as an
// argument, so every case runs on any host instead of only on the ABI the test
// binary was built for.

const empty_args = [_]abi.ArgPlan{};

test "plan validation bounds the argument staging block" {
    // A byval aggregate copies `arg.size` bytes from the first loc's offset, so
    // the loc can still sit inside the block while the copy overruns it.
    var locs = [_]abi.Loc{.{ .kind = .stack, .index = 0, .size = 4, .offset = 4092 }};
    var args = [_]abi.ArgPlan{.{ .locs = &locs, .size = 8, .alignment = 4, .is_struct = true }};
    const over = abi.CallPlan{ .args = &args, .ret_locs = &.{}, .stack_size = 4 };
    try std.testing.expectError(error.BadPlan, validateFor(.win32, over)); // 4092 + 8

    args[0].size = 4;
    try validateFor(.win32, over); // exactly 4096

    // The per-loc copy of a scalar argument is bounded as well.
    var scalar = [_]abi.Loc{.{ .kind = .stack, .index = 0, .size = 8, .offset = 4092 }};
    var scalar_args = [_]abi.ArgPlan{.{ .locs = &scalar, .size = 8, .alignment = 4 }};
    const scalar_plan = abi.CallPlan{ .args = &scalar_args, .ret_locs = &.{}, .stack_size = 8 };
    try std.testing.expectError(error.BadPlan, validateFor(.win32, scalar_plan));
    scalar[0].offset = 4088;
    try validateFor(.win32, scalar_plan);
}

test "plan validation bounds the return staging block by offset+ret_size" {
    var ret = [_]abi.Loc{.{ .kind = .rax, .size = 8, .offset = 4088 }};
    const plan = abi.CallPlan{ .args = &empty_args, .ret_locs = &ret, .ret_size = 16 };
    // The loc itself fits (4088 + 8 == 4096); the `ret_size` copy does not.
    try std.testing.expectError(error.BadPlan, validateFor(.sysv, plan));
    ret[0].offset = 4080;
    try validateFor(.sysv, plan); // 4080 + 16 == 4096

    // Several locs are copied from offset 0, so `ret_size` alone bounds them.
    var multi = [_]abi.Loc{
        .{ .kind = .rax, .size = 8, .offset = 0 },
        .{ .kind = .rdx, .size = 8, .offset = 8 },
    };
    const multi_plan = abi.CallPlan{ .args = &empty_args, .ret_locs = &multi, .ret_size = 4096 };
    try validateFor(.sysv, multi_plan);
    var too_big = multi_plan;
    too_big.ret_size = 4097;
    try std.testing.expectError(error.BadPlan, validateFor(.sysv, too_big));
}

test "plan validation restricts return loc kinds to the ABI" {
    var st0 = [_]abi.Loc{.{ .kind = .st0, .size = 16, .offset = 0 }};
    const long_double = abi.CallPlan{ .args = &empty_args, .ret_locs = &st0, .ret_size = 16 };
    try validateFor(.sysv, long_double);
    try validateFor(.win32, long_double);
    // Win64 classifies `long double` as memory and returns it through sret, and
    // AAPCS64 uses v0/v1 instead of the x87 file.
    try std.testing.expectError(error.BadPlan, validateFor(.win64, long_double));
    try std.testing.expectError(error.BadPlan, validateFor(.aapcs64, long_double));

    var xmm3 = [_]abi.Loc{.{ .kind = .xmm3, .size = 8, .offset = 0 }};
    const hfa = abi.CallPlan{ .args = &empty_args, .ret_locs = &xmm3, .ret_size = 8 };
    try validateFor(.aapcs64, hfa);
    try std.testing.expectError(error.BadPlan, validateFor(.sysv, hfa));
    try std.testing.expectError(error.BadPlan, validateFor(.win64, hfa));
    try std.testing.expectError(error.BadPlan, validateFor(.win32, hfa));

    var xmm1 = [_]abi.Loc{.{ .kind = .xmm1, .size = 8, .offset = 0 }};
    const pair = abi.CallPlan{ .args = &empty_args, .ret_locs = &xmm1, .ret_size = 8 };
    try validateFor(.sysv, pair);
    try validateFor(.win64, pair);
    try std.testing.expectError(error.BadPlan, validateFor(.win32, pair));

    // Argument-friendly kinds are never valid returns.
    var gpr = [_]abi.Loc{.{ .kind = .gpr, .size = 8, .offset = 0 }};
    const as_ret = abi.CallPlan{ .args = &empty_args, .ret_locs = &gpr, .ret_size = 8 };
    for ([_]Kind{ .sysv, .win64, .win32, .aapcs64 }) |kind| {
        try std.testing.expectError(error.BadPlan, validateFor(kind, as_ret));
    }
}

test "plan validation ties .sret locs to plan.sret" {
    var locs = [_]abi.Loc{.{ .kind = .sret, .size = 8, .offset = 0 }};
    var args = [_]abi.ArgPlan{.{ .locs = &locs, .size = 8, .alignment = 8 }};

    // A `.sret` loc without `plan.sret` would send the hidden pointer nowhere.
    const stray = abi.CallPlan{ .args = &args, .ret_locs = &.{}, .ret_size = 16 };
    try std.testing.expectError(error.BadPlan, validateFor(.sysv, stray));

    const with_sret = abi.CallPlan{ .args = &args, .ret_locs = &.{}, .sret = true, .ret_size = 16 };
    try validateFor(.sysv, with_sret);
    try validateFor(.win64, with_sret);
    try validateFor(.aapcs64, with_sret);

    // Conversely `sret = true` needs a loc that carries the pointer.
    var plain = [_]abi.Loc{.{ .kind = .gpr, .size = 8, .offset = 0 }};
    var plain_args = [_]abi.ArgPlan{.{ .locs = &plain, .size = 8, .alignment = 8 }};
    const missing = abi.CallPlan{ .args = &plain_args, .ret_locs = &.{}, .sret = true, .ret_size = 16 };
    try std.testing.expectError(error.BadPlan, validateFor(.sysv, missing));
    try std.testing.expectError(error.BadPlan, validateFor(.aapcs64, missing));
}

test "plan validation bounds stack locs by plan.stack_size" {
    var locs = [_]abi.Loc{.{ .kind = .stack, .index = 4, .size = 8, .offset = 0 }};
    var args = [_]abi.ArgPlan{.{ .locs = &locs, .size = 8, .alignment = 4 }};
    const plan = abi.CallPlan{ .args = &args, .ret_locs = &.{}, .stack_size = 8 };
    // 4 + 8 overruns the 8-byte outgoing area even though it is far below 4096.
    try std.testing.expectError(error.BadPlan, validateFor(.win32, plan));
    try std.testing.expectError(error.BadPlan, validateFor(.sysv, plan));
    var larger = plan;
    larger.stack_size = 12;
    try validateFor(.win32, larger);
    try validateFor(.sysv, larger);

    // The i686 `.sret` loc addresses the same area with a machine word.
    var sret_locs = [_]abi.Loc{.{ .kind = .sret, .index = 8, .size = 4, .offset = 0 }};
    var sret_args = [_]abi.ArgPlan{.{ .locs = &sret_locs, .size = 4, .alignment = 4 }};
    const bad_sret = abi.CallPlan{ .args = &sret_args, .ret_locs = &.{}, .stack_size = 8, .sret = true, .ret_size = 16 };
    try std.testing.expectError(error.BadPlan, validateFor(.win32, bad_sret));
    sret_locs[0].index = 4;
    try validateFor(.win32, bad_sret);
}

test "plan validation restricts the Win32 calling convention byte" {
    for ([_]u8{ 0, 1, 2, 3 }) |conv| {
        try validateFor(.win32, .{ .args = &empty_args, .ret_locs = &.{}, .conv = conv });
    }
    try std.testing.expectError(error.BadPlan, validateFor(.win32, .{ .args = &empty_args, .ret_locs = &.{}, .conv = 4 }));
    // The byte is a Win32 decoration mapping only; other ABIs ignore it.
    try validateFor(.sysv, .{ .args = &empty_args, .ret_locs = &.{}, .conv = 4 });
}

test "plan validation keeps a plain integer call valid on every ABI" {
    var arg_locs = [_]abi.Loc{.{ .kind = .stack, .index = 0, .size = 4, .offset = 0 }};
    var args = [_]abi.ArgPlan{.{ .locs = &arg_locs, .size = 4, .alignment = 4 }};
    var ret = [_]abi.Loc{.{ .kind = .rax, .size = 4, .offset = 0 }};
    const plan = abi.CallPlan{ .args = &args, .ret_locs = &ret, .stack_size = 4, .ret_size = 4 };
    for ([_]Kind{ .sysv, .win64, .win32, .aapcs64 }) |kind| try validateFor(kind, plan);

    // Register arguments respect each ABI's file size.
    var gpr_locs = [_]abi.Loc{.{ .kind = .gpr, .index = 4, .size = 8, .offset = 0 }};
    var gpr_args = [_]abi.ArgPlan{.{ .locs = &gpr_locs, .size = 8, .alignment = 8 }};
    const gpr_plan = abi.CallPlan{ .args = &gpr_args, .ret_locs = &.{} };
    try std.testing.expectError(error.BadPlan, validateFor(.win64, gpr_plan));
    try validateFor(.sysv, gpr_plan);
    try validateFor(.aapcs64, gpr_plan);
}

test "Win32 fastcall and thiscall register slot selection" {
    const loc4 = [_]abi.Loc{.{ .kind = .stack, .size = 4, .offset = 0 }};
    const arg4 = [_]abi.ArgPlan{.{ .locs = &loc4, .size = 4, .alignment = 4 }};
    var gpr: u8 = 0;
    try std.testing.expectEqual(@as(?u8, 0), win32FastSlot(arg4[0], &gpr));
    try std.testing.expectEqual(@as(?u8, 1), win32FastSlot(arg4[0], &gpr));
    try std.testing.expectEqual(@as(?u8, null), win32FastSlot(arg4[0], &gpr));

    var struct_arg = arg4[0];
    struct_arg.is_struct = true;
    gpr = 0;
    try std.testing.expectEqual(@as(?u8, null), win32FastSlot(struct_arg, &gpr));
    try std.testing.expectEqual(@as(u8, 0), gpr);

    const loc8 = [_]abi.Loc{.{ .kind = .stack, .size = 8, .offset = 0 }};
    const arg8 = [_]abi.ArgPlan{.{ .locs = &loc8, .size = 8, .alignment = 8 }};
    try std.testing.expectEqual(@as(?u8, null), win32FastSlot(arg8[0], &gpr));

    const two_locs = [_]abi.Loc{
        .{ .kind = .stack, .size = 4, .offset = 0 },
        .{ .kind = .stack, .size = 4, .offset = 4 },
    };
    const multi = [_]abi.ArgPlan{.{ .locs = &two_locs, .size = 8, .alignment = 4 }};
    try std.testing.expectEqual(@as(?u8, null), win32FastSlot(multi[0], &gpr));

    var used = false;
    try std.testing.expect(win32ThisSlot(arg4[0], &used));
    try std.testing.expect(!win32ThisSlot(arg4[0], &used));
    used = false;
    try std.testing.expect(!win32ThisSlot(struct_arg, &used));
    try std.testing.expect(!win32ThisSlot(arg8[0], &used));
    try std.testing.expect(!win32ThisSlot(multi[0], &used));
    try std.testing.expect(!used);
}

test "Win32 fastcall and thiscall stack layouts" {
    var int_locs = [_]abi.Loc{
        .{ .kind = .stack, .size = 4, .offset = 0 },
        .{ .kind = .stack, .size = 4, .offset = 4 },
        .{ .kind = .stack, .size = 4, .offset = 8 },
        .{ .kind = .stack, .size = 4, .offset = 12 },
    };
    var int_args = [_]abi.ArgPlan{
        .{ .locs = int_locs[0..1], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[1..2], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[2..3], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[3..4], .size = 4, .alignment = 4 },
    };
    try std.testing.expectEqual(@as(u32, 4), win32FastLayout(.{ .args = int_args[0..3], .ret_locs = &.{} }).stack_size);
    try std.testing.expectEqual(@as(u32, 8), win32FastLayout(.{ .args = &int_args, .ret_locs = &.{} }).stack_size);
    try std.testing.expectEqual(@as(u32, 8), win32ThisLayout(.{ .args = int_args[0..3], .ret_locs = &.{} }).stack_size);

    var i64_loc = [_]abi.Loc{.{ .kind = .stack, .size = 8, .offset = 0 }};
    var mixed_args = [_]abi.ArgPlan{
        .{ .locs = int_locs[0..1], .size = 4, .alignment = 4 },
        .{ .locs = i64_loc[0..1], .size = 8, .alignment = 8 },
        .{ .locs = int_locs[1..2], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[2..3], .size = 4, .alignment = 4 },
    };
    try std.testing.expectEqual(@as(u32, 12), win32FastLayout(.{ .args = &mixed_args, .ret_locs = &.{} }).stack_size);

    var sret_loc = [_]abi.Loc{.{ .kind = .sret, .size = 4, .offset = 0 }};
    var sret_int_args = [_]abi.ArgPlan{
        .{ .locs = sret_loc[0..1], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[0..1], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[1..2], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[2..3], .size = 4, .alignment = 4 },
    };
    const fast_sret = win32FastLayout(.{ .args = &sret_int_args, .ret_locs = &.{} });
    try std.testing.expectEqual(@as(u32, 0), fast_sret.sret_offset);
    try std.testing.expectEqual(@as(u32, 8), fast_sret.stack_size);
    const this_sret = win32ThisLayout(.{ .args = &sret_int_args, .ret_locs = &.{} });
    try std.testing.expectEqual(@as(u32, 0), this_sret.sret_offset);
    try std.testing.expectEqual(@as(u32, 12), this_sret.stack_size);

    const byte_loc4 = [_]abi.Loc{.{ .kind = .stack, .size = 4, .offset = 0 }};
    const byte_arg4 = [_]abi.ArgPlan{.{ .locs = &byte_loc4, .size = 4, .alignment = 4 }};
    const byte_loc8 = [_]abi.Loc{.{ .kind = .stack, .size = 8, .offset = 0 }};
    const byte_arg8 = [_]abi.ArgPlan{.{ .locs = &byte_loc8, .size = 8, .alignment = 8 }};
    const byte_locs = [_]abi.Loc{
        .{ .kind = .stack, .size = 4, .offset = 0 },
        .{ .kind = .stack, .size = 4, .offset = 4 },
    };
    const byte_multi = [_]abi.ArgPlan{.{ .locs = &byte_locs, .size = 8, .alignment = 4 }};
    try std.testing.expectEqual(@as(u32, 4), win32StackBytes(byte_arg4[0]));
    try std.testing.expectEqual(@as(u32, 8), win32StackBytes(byte_arg8[0]));
    try std.testing.expectEqual(@as(u32, 8), win32StackBytes(byte_multi[0]));
}

test "Win32 configure and marshal use fastcall/thiscall layouts" {
    var locs = [_]abi.Loc{
        .{ .kind = .stack, .size = 4, .offset = 0 },
        .{ .kind = .stack, .size = 4, .offset = 4 },
        .{ .kind = .stack, .size = 4, .offset = 8 },
    };
    var args = [_]abi.ArgPlan{
        .{ .locs = locs[0..1], .size = 4, .alignment = 4 },
        .{ .locs = locs[1..2], .size = 4, .alignment = 4 },
        .{ .locs = locs[2..3], .size = 4, .alignment = 4 },
    };
    var arg_bytes = [_]u8{0} ** 4096;
    std.mem.writeInt(u32, arg_bytes[0..4], 11, .little);
    std.mem.writeInt(u32, arg_bytes[4..8], 22, .little);
    std.mem.writeInt(u32, arg_bytes[8..12], 33, .little);

    var stack_buf = [_]u8{0} ** 4096;
    var frame = std.mem.zeroes(Win32Frame);
    const fast_plan = abi.CallPlan{ .args = &args, .ret_locs = &.{}, .stack_size = 12, .conv = 2 };
    configureWin32(&frame, fast_plan, &stack_buf, null);
    try std.testing.expectEqual(@as(u32, 4), frame.stack_size);
    try std.testing.expectEqual(@as(u32, 2), frame.conv);
    marshalWin32Fast(&frame, fast_plan, &arg_bytes, &stack_buf);
    try std.testing.expectEqual(@as(u32, 11), frame.eax);
    try std.testing.expectEqual(@as(u32, 22), frame.edx);
    try std.testing.expectEqual(@as(u32, 33), std.mem.readInt(u32, stack_buf[0..4], .little));

    @memset(&stack_buf, 0);
    const this_plan = abi.CallPlan{ .args = &args, .ret_locs = &.{}, .stack_size = 12, .conv = 3 };
    configureWin32(&frame, this_plan, &stack_buf, null);
    try std.testing.expectEqual(@as(u32, 8), frame.stack_size);
    marshalWin32This(&frame, this_plan, &arg_bytes, &stack_buf);
    try std.testing.expectEqual(@as(u32, 11), frame.eax);
    try std.testing.expectEqual(@as(u32, 22), std.mem.readInt(u32, stack_buf[0..4], .little));
    try std.testing.expectEqual(@as(u32, 33), std.mem.readInt(u32, stack_buf[4..8], .little));
}

test "Win32 configure writes a relocated sret pointer" {
    var sret_loc = [_]abi.Loc{.{ .kind = .sret, .size = 4, .offset = 0 }};
    var int_loc = [_]abi.Loc{.{ .kind = .stack, .size = 4, .offset = 0 }};
    var args = [_]abi.ArgPlan{
        .{ .locs = sret_loc[0..1], .size = 4, .alignment = 4 },
        .{ .locs = int_loc[0..1], .size = 4, .alignment = 4 },
    };
    const plan = abi.CallPlan{ .args = &args, .ret_locs = &.{}, .stack_size = 8, .conv = 2, .sret = true, .ret_size = 16 };
    var stack_buf = [_]u8{0} ** 4096;
    var frame = std.mem.zeroes(Win32Frame);
    const ptr: *anyopaque = @ptrFromInt(0x1234);
    configureWin32(&frame, plan, &stack_buf, ptr);
    try std.testing.expectEqual(@as(u32, 0x1234), std.mem.readInt(u32, stack_buf[0..4], .little));
    try std.testing.expectEqual(@as(u32, 4), frame.stack_size);
}

test "Win32 callback support and cleanup" {
    var int_locs = [_]abi.Loc{
        .{ .kind = .stack, .size = 4, .offset = 0 },
        .{ .kind = .stack, .size = 4, .offset = 4 },
        .{ .kind = .stack, .size = 4, .offset = 8 },
    };
    var int_args = [_]abi.ArgPlan{
        .{ .locs = int_locs[0..1], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[1..2], .size = 4, .alignment = 4 },
        .{ .locs = int_locs[2..3], .size = 4, .alignment = 4 },
    };
    try std.testing.expect(win32CallbackSupported(.{ .args = &int_args, .ret_locs = &.{}, .conv = 0 }));
    try std.testing.expect(win32CallbackSupported(.{ .args = &int_args, .ret_locs = &.{}, .conv = 3 }));
    try std.testing.expect(!win32CallbackSupported(.{ .args = &int_args, .ret_locs = &.{}, .conv = 4 }));
    try std.testing.expectEqual(@as(u32, 0), win32CallbackCleanup(.{ .args = &int_args, .ret_locs = &.{}, .conv = 0 }));
    try std.testing.expectEqual(@as(u32, 12), win32CallbackCleanup(.{ .args = &int_args, .ret_locs = &.{}, .stack_size = 12, .conv = 1 }));
    try std.testing.expectEqual(@as(u32, 4), win32CallbackCleanup(.{ .args = &int_args, .ret_locs = &.{}, .conv = 2 }));
    try std.testing.expectEqual(@as(u32, 8), win32CallbackCleanup(.{ .args = &int_args, .ret_locs = &.{}, .conv = 3 }));
}
