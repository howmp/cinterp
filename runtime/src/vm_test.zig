const std = @import("std");
const vm = @import("vm.zig");
const abi = @import("ffi/abi.zig");
const platform = @import("ffi/platform.zig");

fn putU16(buf: []u8, p: *usize, v: u16) void {
    buf[p.*] = @truncate(v);
    buf[p.* + 1] = @truncate(v >> 8);
    p.* += 2;
}

fn putU32(buf: []u8, p: *usize, v: u32) void {
    buf[p.*] = @truncate(v);
    buf[p.* + 1] = @truncate(v >> 8);
    buf[p.* + 2] = @truncate(v >> 16);
    buf[p.* + 3] = @truncate(v >> 24);
    p.* += 4;
}

fn putU64(buf: []u8, p: *usize, v: u64) void {
    var x = v;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        buf[p.* + i] = @truncate(x);
        x >>= 8;
    }
    p.* += 8;
}

fn targetMeta(arch: u8, os: u8, abi_id: u8, ptr_bits: u8) [29]u8 {
    var meta: [29]u8 = undefined;
    var p: usize = 0;
    @memcpy(meta[0..4], "CIPM");
    p = 4;
    meta[p] = 1;
    p += 1;
    putU16(&meta, &p, 29);
    meta[p] = arch;
    p += 1;
    meta[p] = os;
    p += 1;
    meta[p] = abi_id;
    p += 1;
    meta[p] = ptr_bits;
    p += 1;
    meta[p] = 1;
    p += 1;
    meta[p] = 0;
    p += 1;
    putU64(&meta, &p, 0);
    putU16(&meta, &p, 1);
    putU16(&meta, &p, 0);
    putU16(&meta, &p, 0);
    putU16(&meta, &p, 0);
    return meta;
}

test "CIVM module returns 42" {
    var module: [128]u8 = undefined;
    var p: usize = 0;
    @memcpy(module[0..4], "CIVM");
    p = 4;
    module[p] = 1;
    p += 1;
    module[p] = 1;
    p += 1;
    putU16(&module, &p, 1);
    putU16(&module, &p, 0);

    module[p] = 4;
    p += 1;
    @memcpy(module[p .. p + 4], "main");
    p += 4;
    putU16(&module, &p, 0);
    putU16(&module, &p, 0);
    putU32(&module, &p, 10);

    module[p] = vm.OP_LOAD_CONST_I64;
    p += 1;
    var v: u64 = 42;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        module[p + i] = @truncate(v);
        v >>= 8;
    }
    p += 8;
    module[p] = vm.OP_RET;
    p += 1;

    var machine = vm.VM{};
    try machine.loadModuleBytes(module[0..p]);
    try std.testing.expectEqual(@as(i64, 42), try machine.runEntry("main"));
}

test "bad package" {
    var machine = vm.VM{};
    try std.testing.expectError(error.BadPackage, machine.loadPackage("x"));
}

test "v2 target metadata rejects another architecture" {
    var package: [128]u8 = undefined;
    var p: usize = 0;
    @memcpy(package[0..5], "CIPKG");
    p = 5;
    package[p] = 2;
    p += 1;
    package[p] = 1;
    p += 1;
    putU16(&package, &p, 25);
    putU32(&package, &p, 0);
    putU32(&package, &p, 0);
    putU32(&package, &p, 29);
    putU32(&package, &p, 0);
    const meta = targetMeta(if (platform.arch_id == 1) 2 else 1, platform.os_id, platform.abi_id, platform.ptr_bits);
    @memcpy(package[p .. p + 29], &meta);
    p += 29;
    var machine = vm.VM{};
    try std.testing.expectError(error.TargetMismatch, machine.loadPackage(package[0..p]));
}

test "plan validation rejects bad ABI locations" {
    const ret = [_]abi.Loc{.{ .kind = .rax, .index = 0, .size = 8, .offset = 0 }};
    var arg_locs = [_]abi.Loc{.{ .kind = .gpr, .index = 0, .size = 8, .offset = 0 }};
    var args = [_]abi.ArgPlan{.{ .locs = &arg_locs, .size = 8, .alignment = 8 }};
    const plan = abi.CallPlan{ .args = &args, .ret_locs = &ret };

    try platform.validate(plan);
    arg_locs[0].index = 6;
    try std.testing.expectError(error.BadPlan, platform.validate(plan));
    arg_locs[0].index = 0;
    arg_locs[0].offset = 250;
    try std.testing.expectError(error.BadPlan, platform.validate(plan));
}

test "Win32 decorated names retry the PE export spelling" {
    var out: [vm.MAX_SYMBOL_CANDIDATES][]const u8 = undefined;

    // stdcall: the PE export keeps `@N` but drops the stdcall leading underscore.
    var count = vm.symbolCandidates("\\01_c_std_add3@12", true, &out);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqualStrings("\\01_c_std_add3@12", out[0]);
    try std.testing.expectEqualStrings("_c_std_add3@12", out[1]);
    try std.testing.expectEqualStrings("c_std_add3@12", out[2]);

    // fastcall: the export is the asm name without the escape.
    count = vm.symbolCandidates("\\01@fast_add@12", true, &out);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("@fast_add@12", out[1]);

    // A raw control byte, for a frontend that does not escape it.
    count = vm.symbolCandidates("\x01_fast@8", true, &out);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqualStrings("_fast@8", out[1]);
    try std.testing.expectEqualStrings("fast@8", out[2]);

    // Plain and underscored names keep working everywhere.
    count = vm.symbolCandidates("printf", true, &out);
    try std.testing.expectEqual(@as(usize, 1), count);
    count = vm.symbolCandidates("_exit", false, &out);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("_exit", out[0]);
    try std.testing.expectEqualStrings("exit", out[1]);

    // Outside Windows the escape is part of the name: only the underscore retry applies.
    count = vm.symbolCandidates("\\01_c_std_add3@12", false, &out);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("\\01_c_std_add3@12", out[0]);
}

test "Win32 decoration selects the i686 calling convention" {
    try std.testing.expectEqual(@as(u8, 0), vm.win32ConvFromName("printf"));
    try std.testing.expectEqual(@as(u8, 1), vm.win32ConvFromName("\\01_c_std_add3@12"));
    try std.testing.expectEqual(@as(u8, 1), vm.win32ConvFromName("_c_std_add3@12"));
    try std.testing.expectEqual(@as(u8, 1), vm.win32ConvFromName("c_std_add3@12"));
    try std.testing.expectEqual(@as(u8, 2), vm.win32ConvFromName("\\01@fast_add@12"));
    try std.testing.expectEqual(@as(u8, 2), vm.win32ConvFromName("@fast_add@12"));
    // A `@` that is not a trailing byte count is not a decoration.
    try std.testing.expectEqual(@as(u8, 0), vm.win32ConvFromName("@fast_add"));
    try std.testing.expectEqual(@as(u8, 0), vm.win32ConvFromName("names@sys"));
}
