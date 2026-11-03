const std = @import("std");
const vm = @import("vm.zig");
const abi = @import("ffi/abi.zig");
const platform = @import("ffi/platform.zig");

/// Serializes bytecode and CIVM/CIPL fields so a test can spell its program out
/// instruction by instruction.
const Asm = struct {
    buf: []u8,
    pos: usize = 0,

    fn u8v(self: *Asm, v: u8) void {
        self.buf[self.pos] = v;
        self.pos += 1;
    }

    fn u16v(self: *Asm, v: u16) void {
        putU16(self.buf, &self.pos, v);
    }

    fn u32v(self: *Asm, v: u32) void {
        putU32(self.buf, &self.pos, v);
    }

    fn i64v(self: *Asm, v: i64) void {
        putU64(self.buf, &self.pos, @bitCast(v));
    }

    fn bytes(self: *Asm, v: []const u8) void {
        @memcpy(self.buf[self.pos..][0..v.len], v);
        self.pos += v.len;
    }

    fn code(self: *const Asm) []const u8 {
        return self.buf[0..self.pos];
    }
};

const FunctionSpec = struct {
    name: []const u8,
    params: u16,
    locals: u16,
    code: []const u8,
};

fn buildModule(buf: []u8, funcs: []const FunctionSpec) []const u8 {
    var a = Asm{ .buf = buf };
    a.bytes("CIVM");
    a.u8v(1);
    a.u8v(1);
    a.u16v(@intCast(funcs.len));
    a.u16v(0);
    for (funcs) |f| {
        a.u8v(@intCast(f.name.len));
        a.bytes(f.name);
        a.u16v(f.params);
        a.u16v(f.locals);
        a.u32v(@intCast(f.code.len));
        a.bytes(f.code);
    }
    return a.code();
}

/// One `void cb(void)` plan so `OP_CREATE_CALLBACK` has plan metadata to bind.
fn buildPlans(buf: []u8) []const u8 {
    var a = Asm{ .buf = buf };
    a.bytes("CIPL");
    a.u8v(3);
    a.u8v(platform.abi_id);
    a.u16v(1);
    a.u16v(0);
    a.u8v("cb".len);
    a.bytes("cb");
    a.u16v(0);
    a.u16v(1);
    a.u16v(0);
    a.u8v(0);
    a.u8v(0);
    a.u8v(0);
    a.u16v(8);
    a.u8v(@intFromEnum(abi.LocKind.rax));
    a.u16v(0);
    a.u16v(8);
    a.u16v(0);
    return a.code();
}

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

test "typed variadic extras past the value stack are rejected" {
    var main_code: [32]u8 = undefined;
    var main = Asm{ .buf = &main_code };
    main.u8v(vm.OP_LOAD_CONST_I64);
    main.i64v(1);
    main.u8v(vm.OP_CALL_VARIADIC_TYPED);
    main.u16v(1); // callee
    main.u16v(1); // argument count
    main.u8v(0); // one integer extra
    main.u8v(vm.OP_RET_VOID);

    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = main.code() },
        .{ .name = "v", .params = 0, .locals = 65535, .code = &.{vm.OP_RET_VOID} },
    };
    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));
    try std.testing.expectError(error.StackOverflow, machine.runEntry("main"));
}

test "untyped variadic extras past the value stack are rejected" {
    var main_code: [32]u8 = undefined;
    var main = Asm{ .buf = &main_code };
    main.u8v(vm.OP_LOAD_CONST_I64);
    main.i64v(1);
    main.u8v(vm.OP_CALL_VARIADIC);
    main.u16v(1); // callee
    main.u16v(1); // argument count
    main.u8v(vm.OP_RET_VOID);

    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = main.code() },
        .{ .name = "v", .params = 0, .locals = 65535, .code = &.{vm.OP_RET_VOID} },
    };
    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));
    try std.testing.expectError(error.StackOverflow, machine.runEntry("main"));
}

test "setjmp rejects a slot outside the current frame" {
    var main_code: [32]u8 = undefined;
    var main = Asm{ .buf = &main_code };
    main.u8v(vm.OP_LOAD_CONST_I64);
    main.i64v(0x2000);
    main.u8v(vm.OP_SETJMP);
    main.u16v(2); // slot 2 with local_count 2
    main.u8v(vm.OP_RET_VOID);

    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 2, .code = main.code() },
    };
    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));
    try std.testing.expectError(error.BadLocal, machine.runEntry("main"));
}

test "longjmp rejects a slot the current frame does not have" {
    var setjmp_code: [32]u8 = undefined;
    var setjmp = Asm{ .buf = &setjmp_code };
    setjmp.u8v(vm.OP_LOAD_CONST_I64);
    setjmp.i64v(0x2000);
    setjmp.u8v(vm.OP_SETJMP);
    setjmp.u16v(1);
    setjmp.u8v(vm.OP_RET_VOID);

    var longjmp_code: [32]u8 = undefined;
    var longjmp = Asm{ .buf = &longjmp_code };
    longjmp.u8v(vm.OP_LOAD_CONST_I64);
    longjmp.i64v(0x2000);
    longjmp.u8v(vm.OP_LOAD_CONST_I64);
    longjmp.i64v(1);
    longjmp.u8v(vm.OP_LONGJMP);
    longjmp.u8v(vm.OP_RET_VOID);

    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);

    const with_slot = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 2, .code = setjmp.code() },
    };
    try machine.loadModuleBytes(buildModule(&module_buf, &with_slot));
    try std.testing.expectEqual(@as(i64, 0), try machine.runEntry("main"));

    // Reloading a module with a shorter frame keeps the jump entry alive; its
    // recorded slot no longer exists and must be rejected instead of written.
    const without_slot = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = longjmp.code() },
    };
    try machine.loadModuleBytes(buildModule(&module_buf, &without_slot));
    try std.testing.expectError(error.BadLongjmp, machine.runEntry("main"));
}

test "error names map to their documented CI_E category" {
    try std.testing.expectEqual(vm.CI_E_INVALID_ARGUMENT, vm.errorCode(error.TooManyArgs));
    try std.testing.expectEqual(vm.CI_E_OUT_OF_MEMORY, vm.errorCode(error.OutOfMemory));
    try std.testing.expectEqual(vm.CI_E_BAD_PACKAGE, vm.errorCode(error.BadPackageMagic));
    try std.testing.expectEqual(vm.CI_E_BAD_PACKAGE, vm.errorCode(error.BadImportMagic));
    try std.testing.expectEqual(vm.CI_E_BAD_PACKAGE, vm.errorCode(error.BadImportVersion));
    try std.testing.expectEqual(vm.CI_E_BAD_PACKAGE, vm.errorCode(error.TooManyImports));
    try std.testing.expectEqual(vm.CI_E_BAD_PACKAGE, vm.errorCode(error.TooManyProviders));
    try std.testing.expectEqual(vm.CI_E_TARGET, vm.errorCode(error.BadTargetMagic));
    try std.testing.expectEqual(vm.CI_E_TARGET, vm.errorCode(error.BadTargetVersion));
    try std.testing.expectEqual(vm.CI_E_TARGET, vm.errorCode(error.BadTargetHeader));
    try std.testing.expectEqual(vm.CI_E_TARGET, vm.errorCode(error.TargetMismatch));
    try std.testing.expectEqual(vm.CI_E_PLANS, vm.errorCode(error.TooManyPlans));
    try std.testing.expectEqual(vm.CI_E_PLANS, vm.errorCode(error.TooManyLocs));
    try std.testing.expectEqual(vm.CI_E_PLANS, vm.errorCode(error.BadLocKind));
    try std.testing.expectEqual(vm.CI_E_LINK, vm.errorCode(error.TooManyNativeTargets));
    try std.testing.expectEqual(vm.CI_E_ENTRY, vm.errorCode(error.EntryNotFound));
    try std.testing.expectEqual(vm.CI_E_RESOURCE, vm.errorCode(error.StackOverflow));
    try std.testing.expectEqual(vm.CI_E_RUNTIME, vm.errorCode(error.StackUnderflow));
    try std.testing.expectEqual(vm.CI_E_RUNTIME, vm.errorCode(error.TooManyJumps));
    try std.testing.expectEqual(vm.CI_E_RUNTIME, vm.errorCode(error.BadLongjmp));
    try std.testing.expectEqual(vm.CI_E_RUNTIME, vm.errorCode(error.UnsupportedVaList));
    try std.testing.expectEqual(vm.CI_E_RUNTIME, vm.errorCode(error.UnsupportedCallback));
    try std.testing.expectEqual(vm.CI_E_DESTROYED, vm.errorCode(error.VmDestroyed));
    // Anything the interpreter does not classify keeps the generic status.
    try std.testing.expectEqual(vm.CI_ERROR, vm.errorCode(error.Unexpected));
}

test "retired callback trampoline slots are not reused" {
    var main_code: [16]u8 = undefined;
    var main = Asm{ .buf = &main_code };
    main.u8v(vm.OP_CREATE_CALLBACK);
    main.u16v(0); // callback slot
    main.u16v(0); // function
    main.u16v(0); // plan
    main.u8v(vm.OP_POP);
    main.u8v(vm.OP_RET_VOID);

    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = main.code() },
    };
    var module_buf: [128]u8 = undefined;
    var plan_buf: [64]u8 = undefined;
    const module = buildModule(&module_buf, &funcs);
    const plans = buildPlans(&plan_buf);

    // The process-wide pool has 256 slots and retirement is permanent so a
    // stale host function pointer can never enter another VM.
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
        defer vm.ci_vm_destroy(machine);
        try machine.loadModuleBytes(module);
        try machine.loadPlans(plans);
        try std.testing.expectEqual(@as(i64, 0), try machine.runEntry("main"));
    }

    const overflow = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(overflow);
    try overflow.loadModuleBytes(module);
    try overflow.loadPlans(plans);
    try std.testing.expectError(error.TooManyCallbacks, overflow.runEntry("main"));
}

test "linear memory allocations stop at the argv area" {
    var set_top_code: [8]u8 = undefined;
    var set_top = Asm{ .buf = &set_top_code };
    set_top.u8v(vm.OP_SET_MEM_TOP);
    set_top.u32v(64 * 1024);
    set_top.u8v(vm.OP_RET_VOID);

    var restore_code: [16]u8 = undefined;
    var restore = Asm{ .buf = &restore_code };
    restore.u8v(vm.OP_LOAD_CONST_I64);
    restore.i64v(64 * 1024);
    restore.u8v(vm.OP_STACKRESTORE);
    restore.u8v(vm.OP_RET_VOID);

    var alloca_code: [8]u8 = undefined;
    var alloca = Asm{ .buf = &alloca_code };
    alloca.u8v(vm.OP_ALLOCA);
    alloca.u16v(0xFFFF);
    alloca.u8v(vm.OP_RET_VOID);

    var alloca_dyn_code: [16]u8 = undefined;
    var alloca_dyn = Asm{ .buf = &alloca_dyn_code };
    alloca_dyn.u8v(vm.OP_LOAD_CONST_I64);
    alloca_dyn.i64v(64 * 1024);
    alloca_dyn.u8v(vm.OP_ALLOCA_DYN);
    alloca_dyn.u8v(vm.OP_RET_VOID);

    var below_code: [64]u8 = undefined;
    var below = Asm{ .buf = &below_code };
    below.u8v(vm.OP_SET_MEM_TOP);
    below.u32v(64);
    below.u8v(vm.OP_ALLOCA);
    below.u16v(16);
    below.u8v(vm.OP_LOAD_CONST_I64);
    below.i64v(1024);
    below.u8v(vm.OP_ALLOCA_DYN);
    below.u8v(vm.OP_POP);
    below.u8v(vm.OP_LOAD_CONST_I64);
    below.i64v(42);
    below.u8v(vm.OP_RET);

    var config = vm.CiVmConfig{
        .struct_size = @sizeOf(vm.CiVmConfig),
        .flags = 0,
        .stack_size = 0,
        .memory_size = 64 * 1024,
    };
    var module_buf: [256]u8 = undefined;
    const machine = vm.ci_vm_create_ex(&config) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);

    const cases = [_]struct { code: []const u8, want: ?anyerror }{
        .{ .code = set_top.code(), .want = error.OutOfMemory },
        .{ .code = restore.code(), .want = error.OutOfMemory },
        .{ .code = alloca.code(), .want = error.OutOfMemory },
        .{ .code = alloca_dyn.code(), .want = error.OutOfMemory },
        .{ .code = below.code(), .want = null },
    };
    for (cases) |case| {
        const funcs = [_]FunctionSpec{
            .{ .name = "main", .params = 3, .locals = 3, .code = case.code },
        };
        try machine.loadModuleBytes(buildModule(&module_buf, &funcs));
        if (case.want) |want| {
            try std.testing.expectError(want, machine.runEntry("main"));
        } else {
            try std.testing.expectEqual(@as(i64, 42), try machine.runEntry("main"));
        }
    }
}
