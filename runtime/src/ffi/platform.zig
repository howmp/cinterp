const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");

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
pub const callback_supported = abi_kind == .sysv;

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
};

pub const Frame = switch (abi_kind) {
    .sysv => SysVFrame,
    .win64 => Win64Frame,
    .win32 => Win32Frame,
    .aapcs64 => Arm64Frame,
};

extern fn ci_abi_call_sysv64(frame: *SysVFrame, target: *const anyopaque) callconv(.C) void;
extern fn ci_win64_call(frame: *Win64Frame, target: *const anyopaque) callconv(.C) void;
extern fn ci_win32_call(frame: *Win32Frame, target: *const anyopaque, conv: u32) callconv(.C) void;
extern fn ci_arm64_call(frame: *Arm64Frame, target: *const anyopaque) callconv(.C) void;

extern const ci_cb_sysv_table: [256]*const anyopaque;

fn readU64(args: *const [256]u8, off: usize) u64 {
    return @as(*align(1) const u64, @ptrCast(&args[off])).*;
}

fn configureSysV(frame: *SysVFrame, plan: abi.CallPlan, ret_buf: *[256]u8, stack_buf: *[256]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.sse_count = plan.sse_count;
    if (plan.sret) frame.sret = sret_ptr orelse @ptrCast(ret_buf);
}

fn configureWin64(frame: *Win64Frame, plan: abi.CallPlan, ret_buf: *[256]u8, stack_buf: *[256]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.sse_count = plan.sse_count;
    if (plan.sret) frame.sret = sret_ptr orelse @ptrCast(ret_buf);
}

fn configureWin32(frame: *Win32Frame, plan: abi.CallPlan, ret_buf: *[256]u8, stack_buf: *[256]u8, sret_ptr: ?*anyopaque) void {
    _ = ret_buf;
    _ = sret_ptr;
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    frame.conv = 0;
    var ret_x87 = false;
    for (plan.ret_locs) |loc| {
        if (loc.kind == .xmm0) ret_x87 = true;
    }
    frame.ret_x87 = if (ret_x87) 1 else 0;
}

fn configureArm64(frame: *Arm64Frame, plan: abi.CallPlan, ret_buf: *[256]u8, stack_buf: *[256]u8, sret_ptr: ?*anyopaque) void {
    frame.stack = stack_buf;
    frame.stack_size = plan.stack_size;
    if (plan.sret) frame.sret = if (sret_ptr) |p| @intFromPtr(p) else @intFromPtr(ret_buf);
}

pub fn configure(frame: *Frame, plan: abi.CallPlan, ret_buf: *[256]u8, stack_buf: *[256]u8, sret_ptr: ?*anyopaque) void {
    switch (abi_kind) {
        .sysv => configureSysV(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
        .win64 => configureWin64(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
        .win32 => configureWin32(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
        .aapcs64 => configureArm64(@ptrCast(frame), plan, ret_buf, stack_buf, sret_ptr),
    }
}

fn marshalSysV(frame: *SysVFrame, plan: abi.CallPlan, args: *const [256]u8, stack_buf: *[256]u8) void {
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

fn marshalWin64(frame: *Win64Frame, plan: abi.CallPlan, args: *const [256]u8, stack_buf: *[256]u8) void {
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

fn marshalWin32(frame: *Win32Frame, plan: abi.CallPlan, args: *const [256]u8, stack_buf: *[256]u8) void {
    _ = frame;
    for (plan.args) |arg| {
        for (arg.locs) |loc| {
            const off: usize = @intCast(loc.offset);
            const n: usize = @intCast(loc.size);
            switch (loc.kind) {
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

fn marshalArm64(frame: *Arm64Frame, plan: abi.CallPlan, args: *const [256]u8, stack_buf: *[256]u8) void {
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

pub fn marshal(frame: *Frame, plan: abi.CallPlan, args: *const [256]u8, stack_buf: *[256]u8) void {
    switch (abi_kind) {
        .sysv => marshalSysV(@ptrCast(frame), plan, args, stack_buf),
        .win64 => marshalWin64(@ptrCast(frame), plan, args, stack_buf),
        .win32 => marshalWin32(@ptrCast(frame), plan, args, stack_buf),
        .aapcs64 => marshalArm64(@ptrCast(frame), plan, args, stack_buf),
    }
}

fn readRetSysV(frame: *const SysVFrame, plan: abi.CallPlan, ret: *[256]u8) void {
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

fn readRetWin64(frame: *const Win64Frame, plan: abi.CallPlan, ret: *[256]u8) void {
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

fn readRetWin32(frame: *const Win32Frame, plan: abi.CallPlan, ret: *[256]u8) void {
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
            else => {},
        }
    }
}

fn readRetArm64(frame: *const Arm64Frame, plan: abi.CallPlan, ret: *[256]u8) void {
    for (plan.ret_locs) |loc| {
        const off: usize = @intCast(loc.offset);
        const n: usize = @intCast(loc.size);
        switch (loc.kind) {
            .rax => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_x0)[0..n]),
            .rdx => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_x1)[0..n]),
            .xmm0 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_v0)[0..n]),
            .xmm1 => @memcpy(ret[off..][0..n], std.mem.asBytes(&frame.ret_v1)[0..n]),
            else => unreachable,
        }
    }
}

pub fn readRet(frame: *const Frame, plan: abi.CallPlan, ret: *[256]u8) void {
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
    ci_win32_call(frame, target, 0);
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
    if (plan.stack_size > 256) return error.BadPlan;
    if (plan.ret_size > 256) return error.BadPlan;
    if (plan.sse_count > 8) return error.BadPlan;

    for (plan.args) |arg| {
        if (arg.locs.len == 0) return error.BadPlan;
        if (arg.size > 256) return error.BadPlan;
        for (arg.locs) |loc| {
            const off: usize = loc.offset;
            const n: usize = loc.size;
            if (off + n > 256) return error.BadPlan;
            switch (loc.kind) {
                .gpr => {
                    if (stack_only or loc.index >= gpr_max or n > 8 or off + 8 > 256) return error.BadPlan;
                },
                .xmm => {
                    if (stack_only or loc.index >= xmm_max or n > 16) return error.BadPlan;
                },
                .stack => {
                    const idx: usize = loc.index;
                    if (idx + n > 256) return error.BadPlan;
                },
                .sret => {},
                else => return error.BadPlan,
            }
        }
    }

    for (plan.ret_locs) |loc| {
        const off: usize = loc.offset;
        const n: usize = loc.size;
        if (off + n > 256) return error.BadPlan;
        switch (loc.kind) {
            .rax, .rdx => {
                if (n > 8) return error.BadPlan;
            },
            .xmm0, .xmm1 => {
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
    try validateCommon(plan, 0, 0, true);
    for (plan.ret_locs) |loc| {
        switch (loc.kind) {
            .rax, .rdx => if (loc.size > 8) return error.BadPlan,
            .xmm0 => if (loc.size > 8) return error.BadPlan,
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

pub fn callbackTable(slot: usize) ?*const anyopaque {
    if (comptime abi_kind != .sysv) return null;
    if (slot >= 256) return null;
    return ci_cb_sysv_table[slot];
}
