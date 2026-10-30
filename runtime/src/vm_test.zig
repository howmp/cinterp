const std = @import("std");
const vm = @import("vm.zig");

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
