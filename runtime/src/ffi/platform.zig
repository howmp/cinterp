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
pub const os_id: u8 = if (builtin.os.tag == .windows) 2 else 1;
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
    _pad: [7]u8,
    ret_st0_f80: [16]u8,
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
            if (@sizeOf(Win32CbFrame) != 48) @compileError("bad win32 cb size");
            if (@offsetOf(Win32CbFrame, "ret_st0") != 16) @compileError("bad win32 cb st0");
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

fn configureSysV(frame: *SysVFrame, plan: abi.CallPlan, ret_buf: *[4096]u8, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.sse_count = plan.sse_count;
    frame.ret_x87 = 0;
    for (plan.ret_locs) |loc| {
        if (loc.kind == .st0) frame.ret_x87 = 1;
    }
    if (plan.sret) frame.sret = sret_ptr orelse @ptrCast(ret_buf);
}

fn configureWin64(frame: *Win64Frame, plan: abi.CallPlan, ret_buf: *[4096]u8, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.sse_count = plan.sse_count;
    if (plan.sret) frame.sret = sret_ptr orelse @ptrCast(ret_buf);
}

fn configureWin32(frame: *Win32Frame, plan: abi.CallPlan, ret_buf: *[4096]u8, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    _ = ret_buf;
    _ = sret_ptr;
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.conv = plan.conv;
    frame.ret_x87 = 0;
    for (plan.ret_locs) |loc| {
        if (loc.kind == .xmm0) frame.ret_x87 = 1;
        if (loc.kind == .st0) frame.ret_x87 = 2;
    }
}

fn configureArm64(frame: *Arm64Frame, plan: abi.CallPlan, ret_buf: *[4096]u8, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    if (plan.sret) frame.sret = if (sret_ptr) |p| @intFromPtr(p) else @intFromPtr(ret_buf);
}

pub fn configure(frame: *Frame, plan: abi.CallPlan, ret_buf: *[4096]u8, stack_buf: *[4096]u8, sret_ptr: ?*anyopaque) void {
    switch (abi_kind) {
        .sysv => configureSysV(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
        .win64 => configureWin64(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
        .win32 => configureWin32(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
        .aapcs64 => configureArm64(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
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
                    const idx: usize = @intCast(loc.index);
                    const ptr = readU64(args, off);
                    @as(*align(1) u32, @ptrCast(&stack_buf[idx])).* = @truncate(ptr);
                },
                else => unreachable,
            }
        }
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
            .st0 => @memcpy(ret[off..][0..n], frame.ret_st0_f80[0..n]),
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

fn validateCommon(plan: abi.CallPlan, gpr_max: u16, xmm_max: u16, stack_only: bool) !void {
    if (plan.args.len > 16) return error.BadPlan;
    if (plan.ret_locs.len > 8) return error.BadPlan;
    if (plan.stack_size > 4096) return error.BadPlan;
    if (plan.ret_size > 4096) return error.BadPlan;
    if (plan.sse_count > 8) return error.BadPlan;

    for (plan.args) |arg| {
        if (arg.locs.len == 0) return error.BadPlan;
        if (arg.size > 4096) return error.BadPlan;
        for (arg.locs) |loc| {
            const off: usize = loc.offset;
            const n: usize = loc.size;
            if (off + n > 4096) return error.BadPlan;
            switch (loc.kind) {
                .gpr => {
                    if (stack_only or loc.index >= gpr_max or n > 8 or off + 8 > 256) return error.BadPlan;
                },
                .xmm => {
                    if (stack_only or loc.index >= xmm_max or n > 16) return error.BadPlan;
                },
                .stack => {
                    const idx: usize = loc.index;
                    if (idx + n > 4096) return error.BadPlan;
                },
                .sret => {},
                else => return error.BadPlan,
            }
        }
    }

    for (plan.ret_locs) |loc| {
        const off: usize = loc.offset;
        const n: usize = loc.size;
        if (off + n > 4096) return error.BadPlan;
        switch (loc.kind) {
            .rax, .rdx => {
                if (n > 8) return error.BadPlan;
            },
            .xmm0, .xmm1, .xmm2, .xmm3, .st0 => {
                if (n > 16) return error.BadPlan;
            },
            else => return error.BadPlan,
        }
    }
}

fn validateSysV(plan: abi.CallPlan) !void {
    try validateCommon(plan, 6, 8, false);
}

fn validateWin64(plan: abi.CallPlan) !void {
    try validateCommon(plan, 4, 4, false);
}

fn validateWin32(plan: abi.CallPlan) !void {
    try validateCommon(plan, 2, 0, false);
    for (plan.ret_locs) |loc| {
        switch (loc.kind) {
            .rax, .rdx => if (loc.size > 8) return error.BadPlan,
            .xmm0 => if (loc.size > 8) return error.BadPlan,
            .st0 => if (loc.size > 16) return error.BadPlan,
            else => return error.BadPlan,
        }
    }
}

fn validateArm64(plan: abi.CallPlan) !void {
    try validateCommon(plan, 8, 8, false);
}

pub fn validate(plan: abi.CallPlan) !void {
    switch (abi_kind) {
        .sysv => try validateSysV(plan),
        .win64 => try validateWin64(plan),
        .win32 => try validateWin32(plan),
        .aapcs64 => try validateArm64(plan),
    }
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
