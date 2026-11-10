//! Shared ABI plan types and construction.
//!
//! `lower_ast.zig` renders typed IR types back to their canonical spelling and
//! builds every call plan through `buildPlanForAbi`, so the `Loc` kinds, plan
//! ordering and every size/offset in a CIPL record come from one place. The
//! types here are also the compiler's serialization contract: `main.zig` writes
//! `CompileResult` into CIVM/CIPL/CIPI.
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
    /// The plan was declared through CI_NATIVE_PLAN; indirect calls may
    /// target an arbitrary non-null native address.
    native: bool = false,
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
    /// Static data image followed by interned scalar constants. It is copied
    /// into VM linear memory at run start and referenced by ADDR_CONST /
    /// LOAD_CONST_POOL offsets.
    const_data: []const u8 = &.{},
    /// VM memory offset where CIPC data is installed.
    data_base: u32 = 0,
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
        // Win32 returns floating point values in st0 (kind 8); the other
        // targets use xmm0/v0, which the runtime models as kind 6.
        if (abi == 3) return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 8, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 6, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
    }
    return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 4, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
}

/// Win64 (MS x64) argument classes. `memory` means the value is passed or
/// returned by reference: clang lowers every >8-byte aggregate, `long double`
/// and 128-bit vector parameter to an explicit pointer / `sret` in the IR, so
/// `buildWin64Plan` should never have to place a `memory` spelling itself.
const Win64Class = enum { integer, sse, memory };

const Win64Type = struct { class: Win64Class, size: u16 };

/// Classify one rendered IR type spelling the way the MS x64 ABI does.
///
/// Scalars of 8 bytes or less are `integer` (GPR) or `sse` (XMM); aggregates of
/// 8 bytes or less are `sse` when they hold only floats and `integer` otherwise
/// (an 8-byte struct is packed into a single register); anything larger is
/// `memory`, i.e. passed by reference and returned through `sret`.
fn win64Classify(allocator: Allocator, ty: []const u8) !Win64Type {
    const t = std.mem.trim(u8, ty, " ");
    if (std.mem.eql(u8, t, "void")) return .{ .class = .integer, .size = 0 };
    if (std.mem.eql(u8, t, "ptr")) return .{ .class = .integer, .size = 8 };
    if (std.mem.eql(u8, t, "float")) return .{ .class = .sse, .size = 4 };
    if (std.mem.eql(u8, t, "double")) return .{ .class = .sse, .size = 8 };
    if (std.mem.eql(u8, t, "x86_fp80") or std.mem.eql(u8, t, "fp128")) return .{ .class = .memory, .size = 16 };
    if (t.len >= 2 and t[0] == '<' and t[t.len - 1] == '>') {
        // Vectors are passed by reference unless they fit in one XMM register.
        const inner = try typeInfo(t);
        return .{ .class = if (inner.size <= 8) .sse else .memory, .size = inner.size };
    }
    if (t.len >= 2 and t[0] == '[' and t[t.len - 1] == ']') {
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadType;
        const count = std.fmt.parseInt(u16, std.mem.trim(u8, inner[0..x], " "), 10) catch return error.BadType;
        const elem = try win64Classify(allocator, std.mem.trim(u8, inner[x + 3 ..], " "));
        if (elem.class == .memory) return error.BadType;
        const size: u16 = count * elem.size;
        if (size > 8) return .{ .class = .memory, .size = size };
        return .{ .class = elem.class, .size = size };
    }
    if (t.len >= 2 and t[0] == '{' and t[t.len - 1] == '}') {
        const fields = try splitTop(allocator, t[1 .. t.len - 1], ',');
        var offset: u32 = 0;
        var max_align: u32 = 1;
        var all_float = true;
        for (fields) |field| {
            const info = try win64Classify(allocator, field);
            if (info.class == .memory) return error.BadType;
            if (info.class != .sse) all_float = false;
            offset += info.size;
            max_align = @max(max_align, @min(info.size, 8));
        }
        const size: u16 = @intCast(alignUp(offset, max_align));
        if (size > 8) return .{ .class = .memory, .size = size };
        return .{ .class = if (all_float) .sse else .integer, .size = size };
    }
    if (t.len > 1 and t[0] == 'i') {
        const bits = std.fmt.parseInt(u32, t[1..], 10) catch return error.BadType;
        const size: u16 = @intCast(@max(1, (bits + 7) / 8));
        if (size > 8) return .{ .class = .memory, .size = size };
        return .{ .class = .integer, .size = size };
    }
    return error.BadType;
}

/// MS x64 return classification: `rax` for integer-class values (including
/// 8-byte integer aggregates) and `xmm0` for float/double values (including
/// 8-byte float aggregates). Larger values come back through a hidden `sret`
/// pointer, which the caller sees as an explicit argument, so a `memory`
/// spelling without one cannot be marshalled.
fn planReturnWin64(allocator: Allocator, ret_ty: []const u8) !RetInfo {
    if (std.mem.eql(u8, ret_ty, "void")) return .{ .locs = &.{}, .size = 0 };
    const info = win64Classify(allocator, ret_ty) catch return error.UnsupportedFfi;
    if (info.class == .memory) return error.UnsupportedFfi;
    const kind: u8 = if (info.class == .sse) 6 else 4;
    return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = kind, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
}

fn buildWin64Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    _ = ptr_size;
    // The MS x64 ABI assigns registers by *argument slot*, not by counting
    // preceding arguments of the same class: slot `n` uses GPR[n] for
    // integer-class values and XMM[n] for float-class values. `f(int a, double
    // b)` therefore passes `a` in RCX and `b` in XMM1, and a hidden sret
    // pointer consumes slot 0, shifting both files. Arguments past slot 3 go
    // to the stack, and a value moves to the stack only when its own slot is
    // out of range.
    //
    // Variadic calls (`printf`) additionally duplicate every floating-point
    // argument in the integer register for the same slot: the callee's
    // `va_arg` reads the GP home area for `int`/`double` alike (MS x64
    // variable-argument convention). Stack-passed values are not duplicated;
    // `va_arg` reads those from the single stack slot.
    var slot: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var sse_count: u8 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = 0, .size = 8, .offset = arg_offset }}), .size = 8, .alignment = 8 });
            slot += 1;
            arg_offset += 8;
            continue;
        }
        // `byval` is passed by reference on Win64: the callee receives the
        // pointer the caller prepared, which is an integer-class value.
        const info: Win64Type = if (i < byval_sizes.len and byval_sizes[i] > 0)
            .{ .class = .integer, .size = 8 }
        else
            win64Classify(allocator, ty) catch return error.UnsupportedFfi;
        if (info.class == .memory) return error.UnsupportedFfi;
        if (slot < 4) {
            const kind: u8 = if (info.class == .sse) 1 else 0;
            if (kind == 1) sse_count += 1;
            if (kind == 1 and is_varargs) {
                // Keep the XMM home and add the integer-register duplicate.
                const locs = try allocator.alloc(Loc, 2);
                locs[0] = .{ .kind = 1, .index = slot, .size = info.size, .offset = arg_offset };
                locs[1] = .{ .kind = 0, .index = slot, .size = info.size, .offset = arg_offset };
                try args.append(.{ .locs = locs, .size = info.size, .alignment = @max(1, info.size) });
            } else {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = kind, .index = slot, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
            }
        } else {
            stack_size = std.mem.alignForward(u16, stack_size, 8);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
            stack_size += 8;
        }
        slot += 1;
        arg_offset += 8;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnWin64(allocator, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 8), .sret = sret_idx != null, .sse_count = sse_count, .ret_size = r.size };
}

fn buildWin32Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16) !Plan {
    // i686 passes every argument on the stack for cdecl as well as for
    // variadic calls, so `is_varargs` does not change the layout. (Variadic
    // `__stdcall` is not a valid C combination.)
    _ = is_varargs;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            // On i686 the hidden return pointer is the first stack argument;
            // `sret` locs carry the stack offset in `index` so the runtime can
            // place the caller's pointer there.
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
        if (std.mem.eql(u8, ty, "x86_fp80")) {
            // i686 keeps `long double` in x87 form: 10 value bytes in a 12-byte
            // stack slot. The value does not fit a 64-bit argument word, so the
            // caller pushes a pointer to it and the block copies the bytes.
            stack_size = std.mem.alignForward(u16, stack_size, 4);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = 12, .offset = arg_offset }}), .size = 12, .alignment = 4, .is_struct = true });
            stack_size += 12;
            arg_offset += 12;
            continue;
        }
        const info: TypeInfo = if (std.mem.eql(u8, ty, "ptr")) .{ .kind = 0, .size = 4 } else try typeInfo(ty);
        // i686 packs every scalar argument on a 4-byte boundary: a `double`
        // that follows a 4-byte value starts at offset 4, not 8 (clang reads
        // it there), so there is no 8-byte alignment step for 8-byte scalars.
        try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
        stack_size += std.mem.alignForward(u16, info.size, 4);
        arg_offset += info.size;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnScalar(allocator, 3, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 4), .sret = sret_idx != null, .ret_size = r.size };
}

// ------------------------------------------------------------ AAPCS64 (Arm64)

/// AArch64 layout of one rendered IR type spelling. The target is always LP64,
/// so pointers are 8 bytes. Integers occupy their storage size rounded up to
/// their natural alignment, arrays use an aligned element stride, and structs
/// align every field (packed `<{ ... }>` records stay byte-aligned). This is
/// the layout AAPCS64 classification needs; it never feeds the memory image.
const Aapcs64Layout = struct { size: u16, alignment: u16 };

fn aapcs64IntAlignment(size: u16) u16 {
    if (size <= 1) return 1;
    if (size <= 2) return 2;
    if (size <= 4) return 4;
    if (size <= 8) return 8;
    return 16;
}

fn aapcs64Layout(allocator: Allocator, ty: []const u8) !Aapcs64Layout {
    const t = std.mem.trim(u8, ty, " ");
    if (std.mem.eql(u8, t, "void")) return .{ .size = 0, .alignment = 1 };
    if (std.mem.eql(u8, t, "ptr")) return .{ .size = 8, .alignment = 8 };
    if (std.mem.eql(u8, t, "half") or std.mem.eql(u8, t, "bfloat")) return .{ .size = 2, .alignment = 2 };
    if (std.mem.eql(u8, t, "float")) return .{ .size = 4, .alignment = 4 };
    if (std.mem.eql(u8, t, "double")) return .{ .size = 8, .alignment = 8 };
    if (std.mem.eql(u8, t, "x86_fp80") or std.mem.eql(u8, t, "fp128") or std.mem.eql(u8, t, "ppc_fp128")) {
        return .{ .size = 16, .alignment = 16 };
    }
    if (t.len >= 3 and std.mem.startsWith(u8, t, "<{") and std.mem.endsWith(u8, t, "}>")) {
        const fields = try splitTop(allocator, t[2 .. t.len - 2], ',');
        var size: u32 = 0;
        for (fields) |field| size += (try aapcs64Layout(allocator, field)).size;
        if (size > std.math.maxInt(u16)) return error.BadType;
        return .{ .size = @intCast(size), .alignment = 1 };
    }
    if (t.len >= 2 and t[0] == '<' and t[t.len - 1] == '>') {
        // Short vectors are packed and live in one SIMD register.
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadType;
        const count = std.fmt.parseInt(u32, std.mem.trim(u8, inner[0..x], " "), 10) catch return error.BadType;
        const elem = try aapcs64Layout(allocator, std.mem.trim(u8, inner[x + 3 ..], " "));
        const size: u32 = count * elem.size;
        if (size > std.math.maxInt(u16)) return error.BadType;
        return .{ .size = @intCast(size), .alignment = if (size > 8) 16 else 8 };
    }
    if (t.len >= 2 and t[0] == '[' and t[t.len - 1] == ']') {
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadType;
        const count = std.fmt.parseInt(u32, std.mem.trim(u8, inner[0..x], " "), 10) catch return error.BadType;
        const elem = try aapcs64Layout(allocator, std.mem.trim(u8, inner[x + 3 ..], " "));
        const total: u32 = count * alignUp(elem.size, elem.alignment);
        if (total > std.math.maxInt(u16)) return error.BadType;
        return .{ .size = @intCast(total), .alignment = elem.alignment };
    }
    if (t.len >= 2 and t[0] == '{' and t[t.len - 1] == '}') {
        const fields = try splitTop(allocator, t[1 .. t.len - 1], ',');
        var offset: u32 = 0;
        var max_align: u32 = 1;
        for (fields) |field| {
            const f = try aapcs64Layout(allocator, field);
            offset = alignUp(offset, f.alignment) + f.size;
            max_align = @max(max_align, f.alignment);
        }
        const size: u32 = alignUp(offset, max_align);
        if (size > std.math.maxInt(u16)) return error.BadType;
        return .{ .size = @intCast(size), .alignment = @intCast(max_align) };
    }
    if (t.len > 1 and t[0] == 'i') {
        const bits = std.fmt.parseInt(u32, t[1..], 10) catch return error.BadType;
        const size: u16 = @intCast(@max(1, (bits + 7) / 8));
        return .{ .size = size, .alignment = aapcs64IntAlignment(size) };
    }
    // A named type that was not expanded before plan construction, or a
    // spelling this classifier does not know (e.g. `metadata`).
    return error.BadType;
}

/// Homogeneous Floating-point Aggregate: 1-4 members of the same float/double
/// type with no padding inside the aggregate. AAPCS64 classifies arrays and
/// structs recursively, so `[2 x double]`, `{ double, double }` and
/// `{ { double, double }, { double, double } }` all describe D4-shaped HFAs.
const Hfa = struct { kind: u8, count: u8, size: u16 };

fn aapcs64Hfa(allocator: Allocator, ty: []const u8, depth: u32) !?Hfa {
    if (depth > 8) return null;
    const t = std.mem.trim(u8, ty, " ");
    if (std.mem.eql(u8, t, "float")) return .{ .kind = 1, .count = 1, .size = 4 };
    if (std.mem.eql(u8, t, "double")) return .{ .kind = 2, .count = 1, .size = 8 };
    if (t.len >= 2 and t[0] == '[' and t[t.len - 1] == ']') {
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return null;
        const count = std.fmt.parseInt(u32, std.mem.trim(u8, inner[0..x], " "), 10) catch return null;
        const elem = (try aapcs64Hfa(allocator, std.mem.trim(u8, inner[x + 3 ..], " "), depth + 1)) orelse return null;
        const total: u32 = count * elem.count;
        if (total > 4) return null;
        return .{ .kind = elem.kind, .count = @intCast(total), .size = @intCast(@as(u32, elem.size) * count) };
    }
    if (t.len >= 2 and t[0] == '{' and t[t.len - 1] == '}') {
        const fields = try splitTop(allocator, t[1 .. t.len - 1], ',');
        if (fields.len == 0) return null;
        var kind: u8 = 0;
        var count: u32 = 0;
        var offset: u32 = 0;
        for (fields) |field| {
            const f = (try aapcs64Hfa(allocator, field, depth + 1)) orelse return null;
            if (kind == 0) kind = f.kind else if (kind != f.kind) return null;
            const layout = try aapcs64Layout(allocator, field);
            // Any inter-field padding disqualifies the aggregate: `{ double,
            // float }` (padding before the float's align) is not an HFA.
            if (alignUp(offset, layout.alignment) != offset) return null;
            offset += f.size;
            count += f.count;
            if (count > 4) return null;
        }
        // Tail padding disqualifies it as well (`{ float, float, float }` is
        // 12 bytes with no tail padding and is an HFA; `{ float }` padded to 8
        // by an aligned outer context is not).
        if ((try aapcs64Layout(allocator, t)).size != offset) return null;
        return .{ .kind = kind, .count = @intCast(count), .size = @intCast(offset) };
    }
    return null;
}

const Aapcs64Kind = enum { void_, integer, fp, hfa, composite };

const Aapcs64Type = struct {
    kind: Aapcs64Kind,
    size: u16 = 0,
    alignment: u16 = 1,
    /// HFA element type: 1 = `float`, 2 = `double`.
    hfa_kind: u8 = 0,
    hfa_count: u8 = 1,
};

/// Classify one rendered IR type spelling the way AAPCS64 does.
///
/// * Scalars and pointers are `integer` (x0-x7) or `fp` (v0-v7) values.
/// * Aggregates that are homogeneous floating-point aggregates (1-4 member
///   arrays/structs of one float type) are `hfa` and consume that many
///   consecutive SIMD registers, or the stack when they do not fit.
/// * Every other aggregate is a `composite`: up to 16 bytes travel in
///   consecutive GPRs (whole value or not at all), wider ones on the stack
///   (and returned through `sret`).
fn aapcs64Classify(allocator: Allocator, ty: []const u8) !Aapcs64Type {
    const t = std.mem.trim(u8, ty, " ");
    if (std.mem.eql(u8, t, "void")) return .{ .kind = .void_ };
    if (std.mem.eql(u8, t, "ptr")) return .{ .kind = .integer, .size = 8, .alignment = 8 };
    if (std.mem.eql(u8, t, "half") or std.mem.eql(u8, t, "bfloat")) return .{ .kind = .fp, .size = 2, .alignment = 2 };
    if (std.mem.eql(u8, t, "float")) return .{ .kind = .fp, .size = 4, .alignment = 4 };
    if (std.mem.eql(u8, t, "double")) return .{ .kind = .fp, .size = 8, .alignment = 8 };
    if (std.mem.eql(u8, t, "x86_fp80") or std.mem.eql(u8, t, "fp128")) return .{ .kind = .fp, .size = 16, .alignment = 16 };
    const layout = try aapcs64Layout(allocator, t);
    const aggregate = (t.len >= 2 and t[0] == '[' and t[t.len - 1] == ']') or
        (t.len >= 2 and t[0] == '{' and t[t.len - 1] == '}') or
        (t.len >= 3 and std.mem.startsWith(u8, t, "<{") and std.mem.endsWith(u8, t, "}>"));
    if (aggregate) {
        if (try aapcs64Hfa(allocator, t, 0)) |hfa| {
            return .{
                .kind = .hfa,
                .size = hfa.size,
                .alignment = @max(@as(u16, 4), layout.alignment),
                .hfa_kind = hfa.kind,
                .hfa_count = hfa.count,
            };
        }
        return .{ .kind = .composite, .size = layout.size, .alignment = layout.alignment };
    }
    if (t.len >= 2 and t[0] == '<' and t[t.len - 1] == '>') {
        // Short vector: one SIMD register, value size as laid out.
        return .{ .kind = .fp, .size = layout.size, .alignment = layout.alignment };
    }
    if (t.len > 1 and t[0] == 'i') {
        // A 128-bit integer is passed like a 16-byte composite (x0/x1).
        if (layout.size > 8) return .{ .kind = .composite, .size = layout.size, .alignment = layout.alignment };
        return .{ .kind = .integer, .size = layout.size, .alignment = layout.alignment };
    }
    return error.BadType;
}

/// AAPCS64 return locations. Integer scalars return in x0, `float`/`double`
/// in v0, HFAs in v0-v3 (one register per element), and non-HFA composites of
/// at most 16 bytes in x0/x1. Wider composites come back through the `sret`
/// pointer (x8), which the IR spells as an explicit `sret` argument.
fn planReturnAapcs64(allocator: Allocator, ret_ty: []const u8) !RetInfo {
    const t = std.mem.trim(u8, ret_ty, " ");
    if (std.mem.eql(u8, t, "void")) return .{ .locs = &.{}, .size = 0 };
    if (std.mem.eql(u8, t, "x86_fp80") or std.mem.eql(u8, t, "fp128")) {
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 6, .index = 0, .size = 16, .offset = 0 }}), .size = 16 };
    }
    const info = aapcs64Classify(allocator, t) catch return error.UnsupportedFfi;
    switch (info.kind) {
        .void_ => return .{ .locs = &.{}, .size = 0 },
        .integer => return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 4, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size },
        .fp => return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 6, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size },
        .hfa => {
            const elem: u16 = if (info.hfa_kind == 1) 4 else 8;
            const count: usize = info.hfa_count;
            // Loc kinds for the four AAPCS64 SIMD return registers. `st0` sits
            // between `xmm1` and `xmm2` in the runtime's `LocKind` enum, so
            // v0-v3 are 6, 7, 9, 10 rather than 6..9.
            const kinds = [4]u8{ 6, 7, 9, 10 };
            const locs = try allocator.alloc(Loc, count);
            for (locs, 0..) |*loc, i| {
                loc.* = .{
                    .kind = kinds[i],
                    .index = @intCast(i),
                    .size = elem,
                    .offset = @intCast(i * elem),
                };
            }
            return .{ .locs = locs, .size = info.size };
        },
        .composite => {
            if (info.size > 16) return error.UnsupportedFfi;
            var locs = std.ArrayList(Loc).init(allocator);
            try locs.append(.{ .kind = 4, .index = 0, .size = @min(info.size, 8), .offset = 0 });
            if (info.size > 8) try locs.append(.{ .kind = 5, .index = 0, .size = info.size - 8, .offset = 8 });
            return .{ .locs = try locs.toOwnedSlice(), .size = info.size };
        },
    }
}

/// Copy `info`'s bytes into the outgoing stack area at the next AAPCS64
/// natural-aligned slot (never less than the 8-byte NSAA grid).
fn appendAapcs64Stack(allocator: Allocator, args: *std.ArrayList(ArgPlan), stack_size: *u16, info: Aapcs64Type, arg_offset: u16) !void {
    const alignment: u16 = @max(8, info.alignment);
    stack_size.* = std.mem.alignForward(u16, stack_size.*, alignment);
    try args.append(.{
        .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size.*, .size = info.size, .offset = arg_offset }}),
        .size = info.size,
        .alignment = alignment,
        .is_struct = true,
    });
    stack_size.* += std.mem.alignForward(u16, info.size, 8);
}

fn buildAapcs64Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16) !Plan {
    // The base AAPCS64 (aarch64-linux, unlike Apple's ARM64 variant) passes
    // variadic arguments in the same registers/stack slots as named ones; the
    // callee's va_start homes x0-x7/v0-v7 itself. Placement therefore does not
    // depend on `is_varargs`.
    _ = is_varargs;
    // x0-x7 carry integer, pointer and composite arguments; v0-v7 carry
    // scalars and HFAs. There is no shared numbering: an `f(int, double)` uses
    // x0 and v0, and running out of one file only pushes that kind of argument
    // to the stack.
    var gpr: u16 = 0;
    var vec: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            // The indirect result pointer travels in x8 (`ci_arm64_call` loads
            // it from the frame), so it does not consume x0.
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
        const info = aapcs64Classify(allocator, ty) catch return error.UnsupportedFfi;
        switch (info.kind) {
            .void_ => {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 0, .index = 0, .size = 0, .offset = arg_offset }}), .size = 0 });
            },
            .integer, .fp => {
                const as_gpr = info.kind == .integer;
                const slot = if (as_gpr) gpr else vec;
                // Values wider than one word (fp128 `long double`, 128-bit
                // vectors) reach the VM as a pointer to their bytes, exactly
                // like an aggregate: `is_struct` tells it to copy the value
                // instead of popping a scalar.
                const by_ref = info.size > 8;
                if (slot < 8) {
                    try args.append(.{
                        .locs = try allocator.dupe(Loc, &.{.{ .kind = if (as_gpr) 0 else 1, .index = slot, .size = info.size, .offset = arg_offset }}),
                        .size = info.size,
                        .alignment = @max(1, info.size),
                        .is_struct = by_ref,
                    });
                    if (as_gpr) gpr += 1 else vec += 1;
                } else {
                    stack_size = std.mem.alignForward(u16, stack_size, 8);
                    try args.append(.{
                        .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}),
                        .size = info.size,
                        .alignment = 8,
                        .is_struct = by_ref,
                    });
                    stack_size += std.mem.alignForward(u16, info.size, 8);
                }
                arg_offset += std.mem.alignForward(u16, @max(info.size, 8), 8);
            },
            .hfa => {
                const elem: u16 = if (info.hfa_kind == 1) 4 else 8;
                const count: u16 = info.hfa_count;
                if (vec + count <= 8) {
                    const locs = try allocator.alloc(Loc, count);
                    for (locs, 0..) |*loc, j| {
                        loc.* = .{
                            .kind = 1,
                            .index = vec + @as(u16, @intCast(j)),
                            .size = elem,
                            .offset = arg_offset + @as(u16, @intCast(j)) * elem,
                        };
                    }
                    try args.append(.{
                        .locs = locs,
                        .size = info.size,
                        .alignment = @max(1, info.alignment),
                        .is_struct = true,
                    });
                    vec += count;
                } else {
                    // An HFA that does not fit is passed entirely on the
                    // stack: AAPCS64 never splits one between registers and
                    // memory.
                    try appendAapcs64Stack(allocator, &args, &stack_size, info, arg_offset);
                }
                arg_offset += std.mem.alignForward(u16, info.size, 8);
            },
            .composite => {
                const words: u16 = (info.size + 7) / 8;
                if (info.size <= 16 and gpr + words <= 8) {
                    const locs = try allocator.alloc(Loc, words);
                    for (locs, 0..) |*loc, j| {
                        const remaining = info.size - @as(u16, @intCast(j)) * 8;
                        loc.* = .{
                            .kind = 0,
                            .index = gpr + @as(u16, @intCast(j)),
                            .size = @min(8, remaining),
                            .offset = arg_offset + @as(u16, @intCast(j)) * 8,
                        };
                    }
                    try args.append(.{
                        .locs = locs,
                        .size = info.size,
                        .alignment = @max(1, info.alignment),
                        .is_struct = true,
                    });
                    gpr += words;
                } else {
                    try appendAapcs64Stack(allocator, &args, &stack_size, info, arg_offset);
                }
                arg_offset += std.mem.alignForward(u16, info.size, 8);
            },
        }
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnAapcs64(allocator, ret_ty);
    return .{
        .name = name,
        .args = try args.toOwnedSlice(),
        .ret_locs = r.locs,
        .stack_size = std.mem.alignForward(u16, stack_size, 8),
        .sret = sret_idx != null,
        .sse_count = @intCast(@min(vec, 8)),
        .ret_size = r.size,
    };
}

/// Build an ABI call plan from raw type spellings.
///
/// `lower_ast.zig` renders typed IR types back to their canonical spelling and
/// calls this so the `Loc` kinds, plan ordering and every size/offset in a CIPL
/// record come from one place. Keep the behaviour unchanged.
///
/// `is_varargs` only changes the layout where the target ABI does: Win64
/// duplicates floating-point register arguments into the integer file. SysV,
/// Win32 (all-stack) and AAPCS64 (register files are homed by the callee)
/// ignore it.
///
/// `abi`: 1 = SysV x86-64, 2 = Win64, 3 = Win32, 4 = AArch64 AAPCS64.
pub fn buildPlanForAbi(allocator: Allocator, abi: u8, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    return switch (abi) {
        1 => buildSysvPlan(allocator, name, ret_ty, arg_types, is_varargs, sret_idx, sret_size, byval_sizes, ptr_size),
        2 => buildWin64Plan(allocator, name, ret_ty, arg_types, is_varargs, sret_idx, sret_size, byval_sizes, ptr_size),
        3 => buildWin32Plan(allocator, name, ret_ty, arg_types, is_varargs, sret_idx, sret_size, byval_sizes),
        4 => buildAapcs64Plan(allocator, name, ret_ty, arg_types, is_varargs, sret_idx, sret_size, byval_sizes),
        else => error.UnsupportedFfi,
    };
}

/// Map an LLVM calling-convention keyword onto the CIPL `conv` byte:
///
///   0 = the target's default C convention (cdecl / SysV / AAPCS64),
///   1 = `x86_stdcallcc`,
///   2 = `x86_fastcallcc`,
///   3 = `x86_thiscallcc`.
///
/// Every other LLVM convention (`fastcc`, `coldcc`, zeroext, ...) has no
/// runtime model and maps to 0. `null` (no keyword on the call/signature) is
/// also 0. `main.zig` may overwrite the result with the WinAPI table for known
/// Windows exports.
pub fn convFromName(cc: ?[]const u8) u8 {
    const name = cc orelse return 0;
    if (std.mem.eql(u8, name, "x86_stdcallcc")) return 1;
    if (std.mem.eql(u8, name, "x86_fastcallcc")) return 2;
    if (std.mem.eql(u8, name, "x86_thiscallcc")) return 3;
    return 0;
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

test "Win64 register slots follow the argument position, not the class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `f(int a, double b, int c, double d)` is RCX, XMM1, R8, XMM3 on Win64:
    // slot `n` owns GPR[n]/XMM[n], so a double after one integer starts at
    // XMM1 instead of XMM0.
    const mixed = [_][]const u8{ "i32", "double", "i32", "double" };
    const plan = try buildPlanForAbi(allocator, 2, "g1", "double", &mixed, false, null, 0, &.{}, 8);
    try std.testing.expectEqual(@as(u8, 0), plan.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), plan.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), plan.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 1), plan.args[1].locs[0].index);
    try std.testing.expectEqual(@as(u8, 0), plan.args[2].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 2), plan.args[2].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), plan.args[3].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 3), plan.args[3].locs[0].index);
    try std.testing.expectEqual(@as(u8, 2), plan.sse_count);
    try std.testing.expectEqual(@as(u16, 0), plan.stack_size);

    // Past slot 3 every argument goes to the stack in order, whether it is an
    // integer or a float (`c_mix10` from examples/ffi/ffi_edges.c).
    const mix10 = [_][]const u8{ "i64", "double", "i64", "double", "i64", "double", "i64", "double", "i64", "double" };
    const wide = try buildPlanForAbi(allocator, 2, "c_mix10", "i64", &mix10, false, null, 0, &.{}, 8);
    try std.testing.expectEqual(@as(usize, 10), wide.args.len);
    try std.testing.expectEqual(@as(u16, 3), wide.args[3].locs[0].index);
    for ([_]usize{ 4, 5, 6, 7, 8, 9 }) |i| {
        try std.testing.expectEqual(@as(u8, 2), wide.args[i].locs[0].kind);
        try std.testing.expectEqual(@as(u16, @intCast((i - 4) * 8)), wide.args[i].locs[0].index);
    }
    try std.testing.expectEqual(@as(u16, 48), wide.stack_size);
}

test "Win64 D16 (16-byte aggregate) is memory: sret return and by-ref argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `D16 c_make_d16(double a, double b)` lowers to
    // `void @c_make_d16(ptr sret(%struct.D16), double, double)`.
    // The sret pointer takes slot 0 (RCX), so the doubles are slot 1 and 2.
    const make = try buildPlanForAbi(allocator, 2, "c_make_d16", "void", &.{ "ptr", "double", "double" }, false, 0, 16, &.{ 0, 0, 0 }, 8);
    try std.testing.expect(make.sret);
    try std.testing.expectEqual(@as(u16, 16), make.ret_size);
    try std.testing.expectEqual(@as(usize, 0), make.ret_locs.len);
    try std.testing.expectEqual(@as(u8, 3), make.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u8, 1), make.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 1), make.args[1].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), make.args[2].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 2), make.args[2].locs[0].index);

    // `double c_take_d16(D16 s)` lowers to `double @c_take_d16(ptr`: the
    // aggregate is passed by reference in RCX and the result returns in XMM0.
    const take = try buildPlanForAbi(allocator, 2, "c_take_d16", "double", &.{"ptr"}, false, null, 0, &.{0}, 8);
    try std.testing.expect(!take.sret);
    try std.testing.expectEqual(@as(u8, 0), take.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), take.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u8, 6), take.ret_locs[0].kind);

    // A D16 spelling that reaches the plan directly is memory class and cannot
    // be passed without the caller's pointer, so it stays unsupported.
    try std.testing.expectError(error.UnsupportedFfi, buildPlanForAbi(allocator, 2, "f", "double", &.{"{ double, double }"}, false, null, 0, &.{0}, 8));
    try std.testing.expectError(error.UnsupportedFfi, buildPlanForAbi(allocator, 2, "f", "{ double, double }", &.{}, false, null, 0, &.{}, 8));
}

test "Win64 S8 (8-byte aggregate) stays in one integer register" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `S8 c_make_s8(int a, int b)` returns in RAX and takes RCX/RDX.
    const make = try buildPlanForAbi(allocator, 2, "c_make_s8", "i64", &.{ "i32", "i32" }, false, null, 0, &.{ 0, 0 }, 8);
    try std.testing.expect(!make.sret);
    try std.testing.expectEqual(@as(u16, 8), make.ret_size);
    try std.testing.expectEqual(@as(u8, 4), make.ret_locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), make.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u16, 1), make.args[1].locs[0].index);

    // `long c_take_s8(S8 s)` lowers to `i32 @c_take_s8(i64)`: the whole struct
    // travels in RCX.
    const take = try buildPlanForAbi(allocator, 2, "c_take_s8", "i32", &.{"i64"}, false, null, 0, &.{0}, 8);
    try std.testing.expectEqual(@as(u8, 0), take.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 8), take.args[0].locs[0].size);
    try std.testing.expectEqual(@as(u8, 4), take.ret_locs[0].kind);

    // The literal spellings classify the same way: `{ int, int }` is an
    // integer-class 8-byte value, `{ float, float }` is a packed XMM value.
    const int_agg = try win64Classify(allocator, "{ i32, i32 }");
    try std.testing.expectEqual(Win64Class.integer, int_agg.class);
    try std.testing.expectEqual(@as(u16, 8), int_agg.size);
    const float_agg = try win64Classify(allocator, "{ float, float }");
    try std.testing.expectEqual(Win64Class.sse, float_agg.class);
    try std.testing.expectEqual(@as(u16, 8), float_agg.size);
    const agg_plan = try buildPlanForAbi(allocator, 2, "f", "{ i32, i32 }", &.{"{ i32, i32 }"}, false, null, 0, &.{0}, 8);
    try std.testing.expectEqual(@as(u8, 0), agg_plan.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u8, 4), agg_plan.ret_locs[0].kind);
}

test "Win64 M { long, double } (16-byte mixed aggregate) is memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `M c_make_m(long a, double b)` -> `void @c_make_m(ptr sret, i32, double)`:
    // sret owns slot 0, `a` slot 1 (RDX), `b` slot 2 (XMM2).
    const make = try buildPlanForAbi(allocator, 2, "c_make_m", "void", &.{ "ptr", "i32", "double" }, false, 0, 16, &.{ 0, 0, 0 }, 8);
    try std.testing.expect(make.sret);
    try std.testing.expectEqual(@as(u16, 16), make.ret_size);
    try std.testing.expectEqual(@as(u8, 0), make.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 1), make.args[1].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), make.args[2].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 2), make.args[2].locs[0].index);

    // `double c_take_m(M m)` -> `double @c_take_m(ptr)`.
    const take = try buildPlanForAbi(allocator, 2, "c_take_m", "double", &.{"ptr"}, false, null, 0, &.{0}, 8);
    try std.testing.expectEqual(@as(u8, 0), take.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u8, 6), take.ret_locs[0].kind);

    // The spelled aggregate is 16 bytes, hence memory class on both sides.
    const m = try win64Classify(allocator, "{ i64, double }");
    try std.testing.expectEqual(Win64Class.memory, m.class);
    try std.testing.expectEqual(@as(u16, 16), m.size);
    try std.testing.expectError(error.UnsupportedFfi, buildPlanForAbi(allocator, 2, "f", "{ i64, double }", &.{}, false, null, 0, &.{}, 8));
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

test "AAPCS64 D16 (two doubles) is an HFA in v0/v1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `D16 c_make_d16(double, double)` keeps its `%struct.D16` result in the
    // IR; lower_ast expands that name to `{ double, double }` before building
    // the plan. The result is an HFA: v0 and v1.
    const make = try buildPlanForAbi(allocator, 4, "c_make_d16", "{ double, double }", &.{ "double", "double" }, false, null, 0, &.{ 0, 0 }, 8);
    try std.testing.expectEqual(@as(usize, 2), make.ret_locs.len);
    try std.testing.expectEqual(@as(u8, 6), make.ret_locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), make.ret_locs[0].index);
    try std.testing.expectEqual(@as(u16, 8), make.ret_locs[0].size);
    try std.testing.expectEqual(@as(u16, 0), make.ret_locs[0].offset);
    try std.testing.expectEqual(@as(u8, 7), make.ret_locs[1].kind);
    try std.testing.expectEqual(@as(u16, 1), make.ret_locs[1].index);
    try std.testing.expectEqual(@as(u16, 8), make.ret_locs[1].offset);
    try std.testing.expectEqual(@as(u16, 16), make.ret_size);
    // The two scalar doubles take v0 and v1 as well.
    try std.testing.expectEqual(@as(u8, 1), make.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u8, 1), make.args[1].locs[0].kind);

    // `double c_take_d16(D16)` lowers to `double @c_take_d16([2 x double])`
    // on AArch64: the argument arrives in v0/v1.
    const take = try buildPlanForAbi(allocator, 4, "c_take_d16", "double", &.{"[2 x double]"}, false, null, 0, &.{0}, 8);
    try std.testing.expectEqual(@as(usize, 1), take.args.len);
    try std.testing.expect(take.args[0].is_struct);
    try std.testing.expectEqual(@as(u16, 16), take.args[0].size);
    try std.testing.expectEqual(@as(usize, 2), take.args[0].locs.len);
    try std.testing.expectEqual(@as(u8, 1), take.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), take.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u16, 0), take.args[0].locs[0].offset);
    try std.testing.expectEqual(@as(u16, 1), take.args[0].locs[1].index);
    try std.testing.expectEqual(@as(u16, 8), take.args[0].locs[1].offset);
    try std.testing.expectEqual(@as(u8, 6), take.ret_locs[0].kind);

    // A named spelling is not something the plan builder expands by itself;
    // lower_ast resolves it (the runtime has no type table).
    try std.testing.expectError(error.UnsupportedFfi, buildPlanForAbi(allocator, 4, "f", "%struct.D16", &.{}, false, null, 0, &.{}, 8));
}

test "AAPCS64 D4 (four doubles) covers v0-v3 in both directions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `D4 c_hfa4_ret(void)` returns four doubles in v0-v3. `st0` sits between
    // `xmm1` and `xmm2` in the runtime's LocKind enum, so the kinds are
    // 6, 7, 9, 10.
    const ret = try buildPlanForAbi(allocator, 4, "c_hfa4_ret", "{ double, double, double, double }", &.{}, false, null, 0, &.{}, 8);
    try std.testing.expectEqual(@as(usize, 4), ret.ret_locs.len);
    const ret_kinds = [4]u8{ 6, 7, 9, 10 };
    for (ret.ret_locs, 0..) |loc, i| {
        try std.testing.expectEqual(ret_kinds[i], loc.kind);
        try std.testing.expectEqual(@as(u16, @intCast(i)), loc.index);
        try std.testing.expectEqual(@as(u16, 8), loc.size);
        try std.testing.expectEqual(@as(u16, @intCast(i * 8)), loc.offset);
    }
    try std.testing.expectEqual(@as(u16, 32), ret.ret_size);

    // `double c_hfa4(D4)` lowers to `[4 x double]`: v0-v3.
    const arg = try buildPlanForAbi(allocator, 4, "c_hfa4", "double", &.{"[4 x double]"}, false, null, 0, &.{0}, 8);
    try std.testing.expectEqual(@as(usize, 4), arg.args[0].locs.len);
    for (arg.args[0].locs, 0..) |loc, i| {
        try std.testing.expectEqual(@as(u8, 1), loc.kind);
        try std.testing.expectEqual(@as(u16, @intCast(i)), loc.index);
        try std.testing.expectEqual(@as(u16, @intCast(i * 8)), loc.offset);
    }
    try std.testing.expectEqual(@as(u16, 32), arg.args[0].size);
    try std.testing.expectEqual(@as(u16, 0), arg.stack_size);

    // A float HFA uses one 4-byte slot per register instead of 8.
    const f4 = try buildPlanForAbi(allocator, 4, "c_f4", "float", &.{"[4 x float]"}, false, null, 0, &.{0}, 8);
    try std.testing.expectEqual(@as(u16, 12), f4.args[0].locs[3].offset);
    try std.testing.expectEqual(@as(u16, 4), f4.args[0].locs[3].size);

    // `D4` is homogeneous and padding-free; `{ double, float }` is neither.
    try std.testing.expect((try aapcs64Hfa(allocator, "{ double, float }", 0)) == null);
    try std.testing.expect((try aapcs64Hfa(allocator, "{ float, float, float, float, float }", 0)) == null);
    try std.testing.expect((try aapcs64Hfa(allocator, "{ { double, double }, { double, double } }", 0)) != null);
}

test "AAPCS64 non-HFA 16-byte composite ([2 x i64]) uses x0/x1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `M c_make_m(long, double)` lowers to `[2 x i64] @c_make_m(i64, double)`:
    // M { long, double } is not homogeneous, so the result is an integer-class
    // pair in x0/x1 while the arguments still use x0 and v0.
    const make = try buildPlanForAbi(allocator, 4, "c_make_m", "[2 x i64]", &.{ "i64", "double" }, false, null, 0, &.{ 0, 0 }, 8);
    try std.testing.expectEqual(@as(usize, 2), make.ret_locs.len);
    try std.testing.expectEqual(@as(u8, 4), make.ret_locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), make.ret_locs[0].offset);
    try std.testing.expectEqual(@as(u8, 5), make.ret_locs[1].kind);
    try std.testing.expectEqual(@as(u16, 8), make.ret_locs[1].offset);
    try std.testing.expectEqual(@as(u16, 16), make.ret_size);
    try std.testing.expectEqual(@as(u8, 0), make.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), make.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), make.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), make.args[1].locs[0].index);

    // `double c_take_m(M)` takes the 16 bytes in x0/x1 as one aggregate.
    const take = try buildPlanForAbi(allocator, 4, "c_take_m", "double", &.{"[2 x i64]"}, false, null, 0, &.{0}, 8);
    try std.testing.expect(take.args[0].is_struct);
    try std.testing.expectEqual(@as(u16, 16), take.args[0].size);
    try std.testing.expectEqual(@as(usize, 2), take.args[0].locs.len);
    try std.testing.expectEqual(@as(u8, 0), take.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), take.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u16, 8), take.args[0].locs[0].size);
    try std.testing.expectEqual(@as(u8, 0), take.args[0].locs[1].kind);
    try std.testing.expectEqual(@as(u16, 1), take.args[0].locs[1].index);
    try std.testing.expectEqual(@as(u16, 8), take.args[0].locs[1].offset);

    // A 12-byte composite still uses two registers, the second only 4 bytes.
    const twelve = try buildPlanForAbi(allocator, 4, "c_twelve", "double", &.{"{ i32, i32, i32 }"}, false, null, 0, &.{0}, 8);
    try std.testing.expectEqual(@as(u16, 12), twelve.args[0].size);
    try std.testing.expectEqual(@as(u16, 8), twelve.args[0].locs[0].size);
    try std.testing.expectEqual(@as(u16, 4), twelve.args[0].locs[1].size);

    // Wider composites are memory class: an explicit byval/stack argument,
    // never a register pair.
    const wide = try buildPlanForAbi(allocator, 4, "c_wide", "double", &.{ "ptr", "i64" }, false, null, 0, &.{ 24, 0 }, 8);
    try std.testing.expectEqual(@as(u8, 2), wide.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 24), wide.args[0].size);
    try std.testing.expectEqual(@as(u16, 0), wide.args[1].locs[0].index);
    try std.testing.expectEqual(@as(u16, 24), wide.stack_size);

    try std.testing.expectError(error.UnsupportedFfi, buildPlanForAbi(allocator, 4, "f", "{ i64, i64, i64 }", &.{}, false, null, 0, &.{}, 8));
}

test "AAPCS64 HFA stack overflow passes whole arguments on the stack" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `double c_hfa9(D4 x9)` (examples/ffi/ffi_hfa_stack.c): the first two D4s
    // fill v0-v7, the remaining seven are passed wholly on the stack at
    // 0, 32, ..., 224.
    const nine = [_][]const u8{"[4 x double]"} ** 9;
    const zeros = [_]u16{0} ** 9;
    const plan = try buildPlanForAbi(allocator, 4, "c_hfa9", "double", &nine, false, null, 0, &zeros, 8);
    try std.testing.expectEqual(@as(usize, 9), plan.args.len);
    for ([_]usize{ 0, 1 }) |i| {
        try std.testing.expectEqual(@as(usize, 4), plan.args[i].locs.len);
        for (plan.args[i].locs, 0..) |loc, j| {
            try std.testing.expectEqual(@as(u8, 1), loc.kind);
            try std.testing.expectEqual(@as(u16, @intCast(i * 4 + j)), loc.index);
        }
    }
    for (2..9) |i| {
        try std.testing.expectEqual(@as(usize, 1), plan.args[i].locs.len);
        try std.testing.expectEqual(@as(u8, 2), plan.args[i].locs[0].kind);
        try std.testing.expectEqual(@as(u16, @intCast((i - 2) * 32)), plan.args[i].locs[0].index);
        try std.testing.expectEqual(@as(u16, 32), plan.args[i].locs[0].size);
        try std.testing.expect(plan.args[i].is_struct);
    }
    try std.testing.expectEqual(@as(u16, 224), plan.stack_size);

    // An HFA that does not fit the remaining vector registers moves entirely
    // to the stack: 5 doubles occupy v0-v4, so the following D4 cannot split
    // 3 registers + 1 memory slot.
    const mix = [_][]const u8{ "double", "double", "double", "double", "double", "[4 x double]" };
    const mix_plan = try buildPlanForAbi(allocator, 4, "c_mix_hfa", "double", &mix, false, null, 0, &[_]u16{ 0, 0, 0, 0, 0, 0 }, 8);
    try std.testing.expectEqual(@as(usize, 1), mix_plan.args[5].locs.len);
    try std.testing.expectEqual(@as(u8, 2), mix_plan.args[5].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), mix_plan.args[5].locs[0].index);
    try std.testing.expectEqual(@as(u16, 32), mix_plan.stack_size);

    // Likewise a composite needs both remaining GPRs or none.
    const gprs = [_][]const u8{ "i64", "i64", "i64", "i64", "i64", "i64", "i64", "[2 x i64]" };
    const gpr_plan = try buildPlanForAbi(allocator, 4, "c_gpr", "i64", &gprs, false, null, 0, &[_]u16{0} ** 8, 8);
    try std.testing.expectEqual(@as(u8, 2), gpr_plan.args[7].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), gpr_plan.args[7].locs[0].index);
    try std.testing.expectEqual(@as(u16, 16), gpr_plan.stack_size);
}

test "AAPCS64 sret uses x8 and does not consume an argument GPR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `S24 c_make_s24(long)` -> `void @c_make_s24(ptr sret(%struct.S24), i64)`.
    // The callee reads `base` from x0; x8 holds the return pointer.
    const make = try buildPlanForAbi(allocator, 4, "c_make_s24", "void", &.{ "ptr", "i64" }, false, 0, 24, &.{ 0, 0 }, 8);
    try std.testing.expect(make.sret);
    try std.testing.expectEqual(@as(u16, 24), make.ret_size);
    try std.testing.expectEqual(@as(usize, 0), make.ret_locs.len);
    try std.testing.expectEqual(@as(u8, 3), make.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u8, 0), make.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), make.args[1].locs[0].index);

    // Wide composites that would need more than two GPRs are memory class on
    // the return side too (the IR supplies sret before this is reached).
    try std.testing.expectError(error.UnsupportedFfi, buildPlanForAbi(allocator, 4, "f", "{ i64, i64, double }", &.{}, false, null, 0, &.{}, 8));
}

test "convFromName maps stdcall/fastcall/thiscall and defaults everything else" {
    try std.testing.expectEqual(@as(u8, 0), convFromName(null));
    try std.testing.expectEqual(@as(u8, 1), convFromName("x86_stdcallcc"));
    try std.testing.expectEqual(@as(u8, 2), convFromName("x86_fastcallcc"));
    try std.testing.expectEqual(@as(u8, 3), convFromName("x86_thiscallcc"));
    try std.testing.expectEqual(@as(u8, 0), convFromName("ccc"));
    try std.testing.expectEqual(@as(u8, 0), convFromName("fastcc"));
    try std.testing.expectEqual(@as(u8, 0), convFromName("coldcc"));
    try std.testing.expectEqual(@as(u8, 0), convFromName(""));
}

test "Win64 variadic plan duplicates FP register arguments into GPRs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // printf("%f %f %f %f %f") with the format pointer: slots 0..5.
    // Slots 1-3 are in XMM1-3 and must also be homed in RDX/R8/R9; slots 4-5
    // are stack-only.
    const args = [_][]const u8{ "ptr", "double", "double", "double", "double", "double" };
    const zeros = [_]u16{0} ** 6;
    const varargs = try buildPlanForAbi(allocator, 2, "printf", "i32", &args, true, null, 0, &zeros, 8);

    try std.testing.expectEqual(@as(usize, 1), varargs.args[0].locs.len);
    try std.testing.expectEqual(@as(u8, 0), varargs.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), varargs.args[0].locs[0].index);
    for (1..4) |i| {
        const locs = varargs.args[i].locs;
        try std.testing.expectEqual(@as(usize, 2), locs.len);
        try std.testing.expectEqual(@as(u8, 1), locs[0].kind); // XMM
        try std.testing.expectEqual(@as(u8, 0), locs[1].kind); // GPR duplicate
        try std.testing.expectEqual(@as(u16, @intCast(i)), locs[0].index);
        try std.testing.expectEqual(@as(u16, @intCast(i)), locs[1].index);
        try std.testing.expectEqual(@as(u16, @intCast(i * 8)), locs[0].offset);
        try std.testing.expectEqual(locs[0].offset, locs[1].offset);
    }
    for (4..6) |i| {
        try std.testing.expectEqual(@as(usize, 1), varargs.args[i].locs.len);
        try std.testing.expectEqual(@as(u8, 2), varargs.args[i].locs[0].kind);
        try std.testing.expectEqual(@as(u16, @intCast((i - 4) * 8)), varargs.args[i].locs[0].index);
    }
    try std.testing.expectEqual(@as(u16, 16), varargs.stack_size);
    try std.testing.expectEqual(@as(u8, 3), varargs.sse_count);

    // The same signature without varargs keeps one loc per argument.
    const fixed = try buildPlanForAbi(allocator, 2, "f", "i32", &args, false, null, 0, &zeros, 8);
    for (fixed.args) |arg| try std.testing.expectEqual(@as(usize, 1), arg.locs.len);
    try std.testing.expectEqual(@as(u16, 16), fixed.stack_size);
}

test "Win32 variadic plan stays all-stack with cdecl packing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // printf("%f %d %f"): the pointer is 4 bytes, doubles are packed at a
    // 4-byte boundary (no 8-byte padding), matching clang i686 output.
    const args = [_][]const u8{ "ptr", "double", "i32", "double" };
    const plan = try buildPlanForAbi(allocator, 3, "printf", "i32", &args, true, null, 0, &[_]u16{0} ** 4, 4);
    const expect_index = [_]u16{ 0, 4, 12, 16 };
    const expect_size = [_]u16{ 4, 8, 4, 8 };
    for (plan.args, 0..) |arg, i| {
        try std.testing.expectEqual(@as(usize, 1), arg.locs.len);
        try std.testing.expectEqual(@as(u8, 2), arg.locs[0].kind);
        try std.testing.expectEqual(expect_index[i], arg.locs[0].index);
        try std.testing.expectEqual(expect_size[i], arg.locs[0].size);
    }
    try std.testing.expectEqual(@as(u16, 24), plan.stack_size);
}

test "AAPCS64 variadic plan keeps normal register placement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Base AAPCS64 (Linux): variadic arguments use x0-x7/v0-v7 like named
    // ones; the callee homes the registers for va_arg.
    const args = [_][]const u8{ "ptr", "double", "i64", "double" };
    const plan = try buildPlanForAbi(allocator, 4, "printf", "i32", &args, true, null, 0, &[_]u16{0} ** 4, 8);
    try std.testing.expectEqual(@as(u8, 0), plan.args[0].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), plan.args[0].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), plan.args[1].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 0), plan.args[1].locs[0].index);
    try std.testing.expectEqual(@as(u8, 0), plan.args[2].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 1), plan.args[2].locs[0].index);
    try std.testing.expectEqual(@as(u8, 1), plan.args[3].locs[0].kind);
    try std.testing.expectEqual(@as(u16, 1), plan.args[3].locs[0].index);
    try std.testing.expectEqual(@as(u16, 0), plan.stack_size);

    // Once v0-v7 are full, further doubles go to the stack; the GPR file is
    // independent.
    const ten = [_][]const u8{"double"} ** 10;
    const spill = try buildPlanForAbi(allocator, 4, "c_va_d10", "double", &ten, true, null, 0, &[_]u16{0} ** 10, 8);
    for (spill.args[0..8], 0..) |arg, i| {
        try std.testing.expectEqual(@as(u8, 1), arg.locs[0].kind);
        try std.testing.expectEqual(@as(u16, @intCast(i)), arg.locs[0].index);
    }
    for (spill.args[8..], 0..) |arg, i| {
        try std.testing.expectEqual(@as(u8, 2), arg.locs[0].kind);
        try std.testing.expectEqual(@as(u16, @intCast(i * 8)), arg.locs[0].index);
    }
    try std.testing.expectEqual(@as(u16, 16), spill.stack_size);
}
