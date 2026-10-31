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
