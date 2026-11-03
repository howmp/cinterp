//! Shared ABI plan types and construction.
//!
//! `lower_ast.zig` renders typed IR types back to their canonical spelling and
//! builds every call plan through `buildPlanForAbi`, so the `Loc` kinds, plan
//! ordering and every size/offset in a CIPL record come from one place. The
//! types here are also the compiler's serialization contract: `main.zig` writes
//! `CompileResult` into CIVM/CIPL/CIPM/CIPI.
//!
//! Plan construction is a pure function of the ABI id, the rendered parameter
//! and return type spellings, `sret`/byval placement and the pointer width.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Loc = struct {
    kind: u8,
    index: u16 = 0,
    size: u16 = 0,
    offset: u16 = 0,
};

const RetInfo = struct { locs: []Loc, size: u16 };
const TypeInfo = struct { kind: u8, size: u16 };

pub const ArgPlan = struct {
    locs: []Loc,
    size: u16,
    alignment: u16 = 8,
    is_struct: bool = false,
};

pub const Plan = struct {
    name: []const u8,
    args: []ArgPlan,
    ret_locs: []Loc,
    stack_size: u16 = 0,
    sret: bool = false,
    sse_count: u8 = 0,
    ret_size: u16 = 0,
    conv: u8 = 0,
};

pub const Function = struct {
    name: []const u8,
    ret: []const u8,
    param_count: u16,
    param_names: [][]const u8,
    param_types: [][]const u8,
    param_attrs: [][]const u8,
    is_varargs: bool = false,
    local_count: u16,
    code: std.ArrayList(u8),
};

pub const CompileResult = struct {
    functions: []Function,
    plans: []Plan,
    external_data: [][]const u8,
};

fn alignUp(n: u32, a: u32) u32 {
    if (a <= 1) return n;
    return (n + a - 1) / a * a;
}

/// Split `s` on `sep`, ignoring separators inside `()`, `[]`, `{}` and `<>`.
fn splitTop(allocator: Allocator, s: []const u8, sep: u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(allocator);
    var start: usize = 0;
    var depth: i32 = 0;
    var i: usize = 0;
    while (i <= s.len) : (i += 1) {
        const ch: u8 = if (i < s.len) s[i] else sep;
        switch (ch) {
            '(', '[', '{', '<' => depth += 1,
            ')', ']', '}', '>' => depth -= 1,
            else => {},
        }
        if (ch == sep and depth == 0) {
            const part = std.mem.trim(u8, s[start..i], " \t\r\n");
            if (part.len > 0) try out.append(part);
            start = i + 1;
        }
    }
    return out.toOwnedSlice();
}

fn typeInfo(ty: []const u8) !TypeInfo {
    const t = std.mem.trim(u8, ty, " ");
    if (std.mem.eql(u8, t, "void")) return .{ .kind = 0, .size = 0 };
    if (std.mem.eql(u8, t, "fp128")) return .{ .kind = 1, .size = 16 };
    if (std.mem.eql(u8, t, "float")) return .{ .kind = 1, .size = 4 };
    if (std.mem.eql(u8, t, "double")) return .{ .kind = 1, .size = 8 };
    if (std.mem.eql(u8, t, "ptr")) return .{ .kind = 0, .size = 8 };
    if (t.len >= 2 and t[0] == '<' and t[t.len - 1] == '>') {
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadType;
        const count = std.fmt.parseInt(u16, std.mem.trim(u8, inner[0..x], " "), 10) catch return error.BadType;
        const elem = std.mem.trim(u8, inner[x + 3 ..], " ");
        const es: u16 = if (std.mem.eql(u8, elem, "float")) 4 else if (std.mem.eql(u8, elem, "double")) 8 else if (elem.len > 1 and elem[0] == 'i') @intCast(@max(1, ((std.fmt.parseInt(u16, elem[1..], 10) catch 8) + 7) / 8)) else return error.BadType;
        return .{ .kind = 1, .size = count * es };
    }
    if (t.len > 1 and t[0] == 'i') {
        const bits = std.fmt.parseInt(u32, t[1..], 10) catch return error.BadType;
        return .{ .kind = 0, .size = @intCast(@max(1, (bits + 7) / 8)) };
    }
    return error.BadType;
}

fn planReturnScalar(allocator: Allocator, abi: u8, ret_ty: []const u8) !RetInfo {
    if (std.mem.eql(u8, ret_ty, "void")) return .{ .locs = &.{}, .size = 0 };
    if (std.mem.eql(u8, ret_ty, "x86_fp80")) {
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 8, .index = 0, .size = 16, .offset = 0 }}), .size = 16 };
    }
    const info = typeInfo(ret_ty) catch return error.UnsupportedFfi;
    if (info.kind == 1) {
        // Win32 returns floating point values in st0; the other targets use xmm0/v0.
        if (abi == 3) return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 8, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 6, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
    }
    return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 4, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
}

fn buildWin64Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    _ = ptr_size;
    var gpr: u16 = if (sret_idx != null) 1 else 0;
    var xmm: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var sse_count: u8 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = 0, .size = 8, .offset = arg_offset }}), .size = 8, .alignment = 8 });
            arg_offset += 8;
            continue;
        }
        if (i < byval_sizes.len and byval_sizes[i] > 0) {
            const sz = byval_sizes[i];
            stack_size = std.mem.alignForward(u16, stack_size, 8);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = sz, .offset = arg_offset }}), .size = sz, .alignment = 8, .is_struct = true });
            stack_size += std.mem.alignForward(u16, sz, 8);
            arg_offset += sz;
            continue;
        }
        const info = typeInfo(ty) catch return error.UnsupportedFfi;
        if (info.kind == 0) {
            if (gpr < 4) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 0, .index = gpr, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                gpr += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
            }
        } else {
            if (xmm < 4) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 1, .index = xmm, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                xmm += 1;
                sse_count += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
                sse_count += 1;
            }
        }
        arg_offset += 8;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnScalar(allocator, 2, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 8), .sret = sret_idx != null, .sse_count = sse_count, .ret_size = r.size };
}

fn buildWin32Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16) !Plan {
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = stack_size, .size = 4, .offset = arg_offset }}), .size = 4, .alignment = 4 });
            stack_size += 4;
            arg_offset += 4;
            continue;
        }
        if (i < byval_sizes.len and byval_sizes[i] > 0) {
            const sz = byval_sizes[i];
            stack_size = std.mem.alignForward(u16, stack_size, 4);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = sz, .offset = arg_offset }}), .size = sz, .alignment = 4, .is_struct = true });
            stack_size += std.mem.alignForward(u16, sz, 4);
            arg_offset += sz;
            continue;
        }
        const info: TypeInfo = if (std.mem.eql(u8, ty, "ptr")) .{ .kind = 0, .size = 4 } else try typeInfo(ty);
        if (info.kind == 1 and info.size == 8) stack_size = std.mem.alignForward(u16, stack_size, 8);
        try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
        stack_size += std.mem.alignForward(u16, info.size, 4);
        arg_offset += info.size;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnScalar(allocator, 3, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 4), .sret = sret_idx != null, .ret_size = r.size };
}

fn buildAapcs64Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16) !Plan {
    var gpr: u16 = if (sret_idx != null) 1 else 0;
    var xmm: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var sse_count: u8 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = 0, .size = 8, .offset = arg_offset }}), .size = 8, .alignment = 8 });
            arg_offset += 8;
            continue;
        }
        if (i < byval_sizes.len and byval_sizes[i] > 0) {
            const sz = byval_sizes[i];
            stack_size = std.mem.alignForward(u16, stack_size, 8);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = sz, .offset = arg_offset }}), .size = sz, .alignment = 8, .is_struct = true });
            stack_size += std.mem.alignForward(u16, sz, 8);
            arg_offset += sz;
            continue;
        }
        const info = typeInfo(ty) catch return error.UnsupportedFfi;
        if (info.kind == 0) {
            if (gpr < 8) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 0, .index = gpr, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                gpr += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
            }
        } else {
            if (xmm < 8) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 1, .index = xmm, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                xmm += 1;
                sse_count += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
                sse_count += 1;
            }
        }
        arg_offset += 8;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnScalar(allocator, 4, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 8), .sret = sret_idx != null, .sse_count = sse_count, .ret_size = r.size };
}

/// Build an ABI call plan from raw type spellings.
///
/// `lower_ast.zig` renders typed IR types back to their canonical spelling and
/// calls this so the `Loc` kinds, plan ordering and every size/offset in a CIPL
/// record come from one place. Keep the behaviour unchanged.
///
/// `abi`: 1 = SysV x86-64, 2 = Win64, 3 = Win32, 4 = AArch64 AAPCS64.
pub fn buildPlanForAbi(allocator: Allocator, abi: u8, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    return switch (abi) {
        1 => buildSysvPlan(allocator, name, ret_ty, arg_types, is_varargs, sret_idx, sret_size, byval_sizes, ptr_size),
        2 => buildWin64Plan(allocator, name, ret_ty, arg_types, sret_idx, sret_size, byval_sizes, ptr_size),
        3 => buildWin32Plan(allocator, name, ret_ty, arg_types, sret_idx, sret_size, byval_sizes),
        4 => buildAapcs64Plan(allocator, name, ret_ty, arg_types, sret_idx, sret_size, byval_sizes),
        else => error.UnsupportedFfi,
    };
}

fn returnLocs(allocator: Allocator, ret_ty: []const u8, ptr_size: u32) !struct { locs: []Loc, size: u16 } {
    _ = ptr_size;
    const ty = std.mem.trim(u8, ret_ty, " ");
    if (std.mem.eql(u8, ty, "x86_fp80")) {
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 8, .index = 0, .size = 16, .offset = 0 }}), .size = 16 };
    }
    if (ty.len >= 2 and ty[0] == '{' and ty[ty.len - 1] == '}') {
        const fields = try splitTop(allocator, ty[1 .. ty.len - 1], ',');
        var classes = [_]?u8{ null, null };
        var offset: u32 = 0;
        var max_align: u32 = 1;
        for (fields) |field| {
            const info = typeInfo(field) catch return error.UnsupportedFfi;
            if (info.kind == 0 and info.size == 0) return error.UnsupportedFfi;
            const idx = offset / 8;
            if (idx > 1) return error.UnsupportedFfi;
            if (classes[idx] != null and classes[idx].? != info.kind) {
                classes[idx] = 0;
            } else {
                classes[idx] = info.kind;
            }
            offset += info.size;
            max_align = @max(max_align, @min(info.size, 8));
        }
        const total: u16 = @intCast(alignUp(offset, max_align));
        var gpr: u16 = 0;
        var xmm: u16 = 0;
        var locs = std.ArrayList(Loc).init(allocator);
        for (classes, 0..) |cls_opt, idx| {
            const cls = cls_opt orelse continue;
            const remaining: u16 = if (total > idx * 8) total - @as(u16, @intCast(idx * 8)) else 0;
            const size: u16 = @min(8, remaining);
            if (cls == 0) {
                try locs.append(.{ .kind = if (gpr == 0) 4 else 5, .index = 0, .size = size, .offset = @intCast(idx * 8) });
                gpr += 1;
            } else {
                try locs.append(.{ .kind = if (xmm == 0) 6 else 7, .index = 0, .size = size, .offset = @intCast(idx * 8) });
                xmm += 1;
            }
        }
        return .{ .locs = try locs.toOwnedSlice(), .size = total };
    }
    const info = typeInfo(ty) catch return error.UnsupportedFfi;
    if (info.kind == 0 and info.size == 0) return .{ .locs = &.{}, .size = 0 };
    if (info.kind == 0) {
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 4, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
    }
    return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 6, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
}

fn buildSysvPlan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    _ = is_varargs;
    var gpr: u16 = if (sret_idx != null) 1 else 0;
    var xmm: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var sse_count: u8 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, arg_index| {
        if (sret_idx != null and sret_idx.? == arg_index) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = 0, .size = 8, .offset = arg_offset }}), .size = 8, .alignment = 8, .is_struct = false });
            arg_offset += 8;
            continue;
        }
        if (std.mem.eql(u8, ty, "x86_fp80")) {
            stack_size = std.mem.alignForward(u16, stack_size, 16);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = 16, .offset = arg_offset }}), .size = 16, .alignment = 16, .is_struct = true });
            stack_size += 16;
            arg_offset += 16;
            continue;
        }
        if (arg_index < byval_sizes.len and byval_sizes[arg_index] > 0) {
            const size = byval_sizes[arg_index];
            arg_offset = std.mem.alignForward(u16, arg_offset, 8);
            stack_size = std.mem.alignForward(u16, stack_size, 8);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = size, .offset = arg_offset }}), .size = size, .alignment = 8, .is_struct = true });
            stack_size += std.mem.alignForward(u16, size, 8);
            arg_offset += size;
            continue;
        }
        const info = typeInfo(ty) catch {
            return error.UnsupportedFfi;
        };
        if (info.kind == 0) {
            if (gpr < 6) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 0, .index = gpr, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size), .is_struct = false });
                gpr += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8, .is_struct = false });
                stack_size += 8;
            }
        } else {
            if (xmm < 8) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 1, .index = xmm, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size), .is_struct = false });
                xmm += 1;
                sse_count += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8, .is_struct = false });
                stack_size += 8;
                sse_count += 1;
            }
        }
        arg_offset += 8;
    }
    var ret_locs: []Loc = &.{};
    var ret_size: u16 = 0;
    if (sret_idx != null) {
        ret_size = sret_size;
    } else {
        const r = try returnLocs(allocator, ret_ty, ptr_size);
        ret_locs = r.locs;
        ret_size = r.size;
    }
    return .{
        .name = name,
        .args = try args.toOwnedSlice(),
        .ret_locs = ret_locs,
        .stack_size = std.mem.alignForward(u16, stack_size, 8),
        .sret = sret_idx != null,
        .sse_count = sse_count,
        .ret_size = ret_size,
    };
}

// ----------------------------------------------------------------------- tests

test "splitTop keeps aggregate types intact" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parts = try splitTop(arena.allocator(), "i32 1, { i32, i32 } { i32 2, i32 3 }, i32 4", ',');
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("i32 1", parts[0]);
    try std.testing.expectEqualStrings("{ i32, i32 } { i32 2, i32 3 }", parts[1]);
    try std.testing.expectEqualStrings("i32 4", parts[2]);
}

test "SysV plan places integer, float, byval and sret arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = [_][]const u8{ "i32", "double", "{ i32, i32 }" };
    const byval = [_]u16{ 0, 0, 8 };
    const plan = try buildPlanForAbi(allocator, 1, "f", "i32", &args, false, null, 0, &byval, 8);
    try std.testing.expectEqual(@as(usize, 3), plan.args.len);
    // i32 -> rdi, double -> xmm0, byval struct -> stack at 0.
    try std.testing.expectEqual(@as(u8, 0), plan.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), plan.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), plan.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), plan.args[1].locs[0].index);
    try std.testing.expectEqual(@as(u8, 2), plan.args[2].locs[0].kind);
    try std.testing.expect(plan.args[2].is_struct);
    try std.testing.expectEqual(@as(u16, 8), plan.stack_size);
    try std.testing.expectEqual(@as(u8, 4), plan.ret_locs[0].kind);

    const sret_plan = try buildPlanForAbi(allocator, 1, "g", "void", &.{ "ptr", "i32" }, false, 0, 8, &.{ 0, 0 }, 8);
    try std.testing.expect(sret_plan.sret);
    try std.testing.expectEqual(@as(u8, 3), sret_plan.args[0].locs[0].kind);
    // sret consumes rdi, so the i32 argument moves to rsi.
    try std.testing.expectEqual(@as(u16, 1), sret_plan.args[1].locs[0].index);
    try std.testing.expectEqual(@as(u16, 8), sret_plan.ret_size);
}

test "Win32 and AAPCS64 plans use their own register files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = [_][]const u8{ "ptr", "double", "i32" };
    const win32 = try buildPlanForAbi(allocator, 3, "f", "double", &args, false, null, 0, &.{}, 4);
    // Win32 passes everything on the stack and returns doubles in st0.
    try std.testing.expectEqual(@as(u8, 2), win32.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 8), win32.args[1].locs[0].size);
    try std.testing.expectEqual(@as(u8, 8), win32.ret_locs[0].kind);

    const aapcs = try buildPlanForAbi(allocator, 4, "f", "i32", &args, false, null, 0, &.{}, 8);
    try std.testing.expectEqual(@as(u8, 0), aapcs.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u8, 1), aapcs.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u8, 4), aapcs.ret_locs[0].kind);
}
