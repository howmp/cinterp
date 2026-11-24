const std = @import("std");
const vm = @import("vm.zig");
const abi = @import("ffi/abi.zig");
const cipc = @import("ffi/cipc.zig");
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
    var entry: u16 = 0xFFFF;
    for (funcs, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "main")) entry = @intCast(i);
    }
    a.bytes("CIVM");
    a.u8v(2);
    a.u8v(1);
    a.u16v(@intCast(funcs.len));
    a.u16v(entry);
    for (funcs) |f| {
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
    a.u8v(platform.abi_id);
    a.u16v(1);
    a.u16v(0); // name_ref -> "cb"
    a.u8v(0); // args
    a.u8v(1); // rets
    a.u16v(0); // stack
    a.u8v(0); // flags
    a.u16v(8); // ret_size
    a.u8v(@intFromEnum(abi.LocKind.rax));
    a.u16v(0);
    a.u16v(8);
    a.u16v(0);
    return a.code();
}

/// An empty CIPL section: enough plan metadata for a package that makes no
/// native calls.
fn buildEmptyPlans(buf: []u8) []const u8 {
    var a = Asm{ .buf = buf };
    a.u8v(platform.abi_id);
    a.u16v(0);
    return a.code();
}

/// A minimal CIPC v2 header with no names/data. The 36-byte header is padded
/// to the 16-byte data alignment (48 bytes total).
fn buildCipc() [48]u8 {
    var bytes: [48]u8 = [_]u8{0} ** 48;
    @memcpy(bytes[0..4], "CIPC");
    bytes[4] = 2;
    return bytes;
}

/// A v4 trusted CIPKG package: 22-byte header, then module/plans/CIPC.
fn buildPackageWithCipc(buf: []u8, module: []const u8, plans: []const u8, cipc_bytes: []const u8) []const u8 {
    var a = Asm{ .buf = buf };
    a.bytes("CIPKG");
    a.u8v(4);
    a.u32v(@intCast(module.len));
    a.u32v(@intCast(plans.len));
    a.u32v(0);
    a.u32v(@intCast(cipc_bytes.len));
    a.bytes(module);
    a.bytes(plans);
    a.bytes(cipc_bytes);
    return a.code();
}

fn buildPackage(buf: []u8, module: []const u8, plans: []const u8) []const u8 {
    const cipc_bytes = buildCipc();
    return buildPackageWithCipc(buf, module, plans, &cipc_bytes);
}

fn buildCipcWithData(buf: []u8, data: []const u8, key_opt: ?[cipc.key_len]u8) []const u8 {
    var a = Asm{ .buf = buf };
    const key = key_opt orelse [_]u8{0} ** cipc.key_len;
    a.bytes("CIPC");
    a.u8v(2);
    a.u8v(if (key_opt != null) 1 else 0);
    a.u16v(0);
    a.u32v(0);
    a.u32v(@intCast(data.len));
    a.u32v(0);
    a.bytes(&key);
    while (a.pos % 16 != 0) a.u8v(0);
    if (key_opt) |k| {
        for (data, 0..) |byte, i| a.u8v(byte ^ k[i % k.len]);
    } else {
        a.bytes(data);
    }
    return a.code();
}

const PoolRun = struct {
    status: c_int,
    result: i64,
    fused: u64,
};

fn traceEnabled() bool {
    const mode = @import("builtin").mode;
    return mode == .Debug or mode == .ReleaseSafe;
}

/// `lhs; LOAD_CONST_POOL ref; op [param]; RET` so a test can exercise the
/// constant-load fusion path.
fn buildPoolAluProgram(buf: []u8, lhs: i64, ref: u32, op: u8, param: ?u8) []const u8 {
    var a = Asm{ .buf = buf };
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(lhs);
    a.u8v(vm.OP_LOAD_CONST_POOL);
    a.u32v(ref);
    a.u8v(op);
    if (param) |p| a.u8v(p);
    a.u8v(vm.OP_RET);
    return a.code();
}

fn runPoolProgram(code: []const u8, data: []const u8) !PoolRun {
    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = code },
    };
    var module_buf: [512]u8 = undefined;
    const module = buildModule(&module_buf, &funcs);
    var plans_buf: [32]u8 = undefined;
    const plans = buildEmptyPlans(&plans_buf);
    var cipc_buf: [256]u8 = undefined;
    const cipc_bytes = buildCipcWithData(&cipc_buf, data, null);
    var package_buf: [1024]u8 = undefined;
    const package = buildPackageWithCipc(&package_buf, module, plans, cipc_bytes);

    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    machine.setTrace(true);
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_load_package(machine, package.ptr, package.len));
    const status = vm.ci_vm_run(machine, "main");
    const result = vm.ci_vm_result(machine);
    const fused = if (comptime traceEnabled()) machine.trace.fused_const_alu else 0;
    return .{ .status = status, .result = result, .fused = fused };
}

fn expectFusedResult(code: []const u8, data: []const u8, expected: i64) !void {
    const run = try runPoolProgram(code, data);
    try std.testing.expectEqual(vm.CI_OK, run.status);
    try std.testing.expectEqual(expected, run.result);
    if (comptime traceEnabled()) try std.testing.expect(run.fused > 0);
}

fn expectPoolResult(code: []const u8, data: []const u8, expected: i64) !void {
    const run = try runPoolProgram(code, data);
    try std.testing.expectEqual(vm.CI_OK, run.status);
    try std.testing.expectEqual(expected, run.result);
}

fn expectPoolRuntimeError(code: []const u8, data: []const u8) !void {
    const run = try runPoolProgram(code, data);
    try std.testing.expectEqual(vm.CI_E_RUNTIME, run.status);
}

/// `main` with one local that counts down `iterations` and returns `result`.
/// Long counts are used to keep a VM busy while another thread probes it.
fn loopMain(buf: []u8, iterations: i64, result: i64) []const u8 {
    var a = Asm{ .buf = buf };
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(iterations);
    a.u8v(vm.OP_STORE_LOCAL);
    a.u16v(0);
    const loop = a.pos;
    a.u8v(vm.OP_LOAD_LOCAL);
    a.u16v(0);
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(1);
    a.u8v(vm.OP_SUB);
    a.u8v(vm.OP_STORE_LOCAL);
    a.u16v(0);
    a.u8v(vm.OP_LOAD_LOCAL);
    a.u16v(0);
    a.u8v(vm.OP_JNZ);
    a.u32v(@intCast(loop));
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(result);
    a.u8v(vm.OP_RET);
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

test "CIVM module returns 42" {
    var module: [128]u8 = undefined;
    var p: usize = 0;
    @memcpy(module[0..4], "CIVM");
    p = 4;
    module[p] = 2;
    p += 1;
    module[p] = 1;
    p += 1;
    putU16(&module, &p, 1);
    putU16(&module, &p, 0);

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

/// `int cb(void) { return 7; }` — the callback body the acquire/release tests
/// dispatch directly through `ci_callback_dispatch`.
const callback_body = [_]u8{
    vm.OP_LOAD_CONST_I64, 7, 0, 0, 0, 0, 0, 0, 0,
    vm.OP_RET,
};

/// `int release_one(unsigned long p) { return ci_callback_release(p); }` so a
/// test can drive `OP_CALLBACK_RELEASE` with an arbitrary trampoline address.
const callback_release_fn = [_]u8{
    vm.OP_LOAD_LOCAL,       0,         0,
    vm.OP_CALLBACK_RELEASE, vm.OP_RET,
};

/// `void *acquire(void) { return ci_callback_acquire(&cb); }`.
const callback_acquire_fn = [_]u8{
    vm.OP_CALLBACK_ACQUIRE, 0, 0, 1, 0,
    vm.OP_RET,
};

/// `main` that performs `iterations` acquire/release cycles and returns 42, or
/// the negative status of the first failed release (which is what an exhausted
/// pool looks like: the release of the NULL trampoline fails).
fn callbackCycleMain(buf: []u8, iterations: i64) []const u8 {
    var a = Asm{ .buf = buf };
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(iterations);
    a.u8v(vm.OP_STORE_LOCAL);
    a.u16v(0);
    const loop = a.pos;
    a.u8v(vm.OP_CALLBACK_ACQUIRE);
    a.u16v(0); // plan
    a.u16v(1); // cb
    a.u8v(vm.OP_CALLBACK_RELEASE);
    a.u8v(vm.OP_DUP);
    // JZ ok / RET are 5 + 1 bytes; keep the status to return on failure.
    const ok = loop + 5 + 1 + 1 + 5 + 1;
    a.u8v(vm.OP_JZ);
    a.u32v(@intCast(ok));
    a.u8v(vm.OP_RET); // failed: return the negative status
    a.u8v(vm.OP_POP); // ok: drop the zero status
    a.u8v(vm.OP_LOAD_LOCAL);
    a.u16v(0);
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(1);
    a.u8v(vm.OP_SUB);
    a.u8v(vm.OP_STORE_LOCAL);
    a.u16v(0);
    a.u8v(vm.OP_LOAD_LOCAL);
    a.u16v(0);
    a.u8v(vm.OP_JNZ);
    a.u32v(@intCast(loop));
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(42);
    a.u8v(vm.OP_RET);
    return a.code();
}

/// Module with `main` (caller supplied), the callback body `cb`, `release_one`
/// and `acquire`, all sharing one `void cb(void)` callback plan.
const CallbackFixture = struct {
    module_buf: [512]u8 = undefined,
    plan_buf: [64]u8 = undefined,
    module: []const u8 = &.{},
    plans: []const u8 = &.{},

    fn build(self: *CallbackFixture, main_code: []const u8, main_locals: u16) void {
        const funcs = [_]FunctionSpec{
            .{ .name = "main", .params = 0, .locals = main_locals, .code = main_code },
            .{ .name = "cb", .params = 0, .locals = 0, .code = &callback_body },
            .{ .name = "release_one", .params = 1, .locals = 1, .code = &callback_release_fn },
            .{ .name = "acquire", .params = 0, .locals = 0, .code = &callback_acquire_fn },
        };
        self.module = buildModule(&self.module_buf, &funcs);
        self.plans = buildPlans(&self.plan_buf);
    }

    fn load(self: *const CallbackFixture, machine: *vm.VM) !void {
        try machine.loadModuleBytes(self.module);
        try machine.loadPlans(self.plans, &.{"cb"});
    }
};

fn releaseOne(machine: *vm.VM, addr: i64) !i64 {
    return machine.runCallback(2, &.{.{ .i = addr }});
}

/// Global trampoline slot whose table address is `addr`.
fn callbackSlotOf(addr: usize) ?u64 {
    var slot: usize = 0;
    while (slot < 256) : (slot += 1) {
        const table = platform.callbackTable(slot) orelse continue;
        if (@intFromPtr(table) == addr) return @intCast(slot);
    }
    return null;
}

/// First integer return register of a callback frame, for the deterministic
/// zero-return check. The plan locations name this register on every ABI.
fn callbackIntRet(frame: *platform.CallbackFrame) u64 {
    return switch (platform.abi_kind) {
        .sysv => @as(*platform.SysVCbFrame, @ptrCast(frame)).ret_rax,
        .win64 => @as(*platform.Win64CbFrame, @ptrCast(frame)).ret_rax,
        .aapcs64 => @as(*platform.Arm64CbFrame, @ptrCast(frame)).ret_x0,
        .win32 => @as(*platform.Win32CbFrame, @ptrCast(frame)).ret_eax,
    };
}

fn setCallbackIntRet(frame: *platform.CallbackFrame, bits: u64) void {
    switch (platform.abi_kind) {
        .sysv => @as(*platform.SysVCbFrame, @ptrCast(frame)).ret_rax = bits,
        .win64 => @as(*platform.Win64CbFrame, @ptrCast(frame)).ret_rax = bits,
        .aapcs64 => @as(*platform.Arm64CbFrame, @ptrCast(frame)).ret_x0 = bits,
        .win32 => @as(*platform.Win32CbFrame, @ptrCast(frame)).ret_eax = @truncate(bits),
    }
}

test "explicit callback acquire/release reuses trampoline slots" {
    vm.resetCallbackPoolForTest();
    defer vm.resetCallbackPoolForTest();

    var main_buf: [128]u8 = undefined;
    var fixture = CallbackFixture{};
    fixture.build(callbackCycleMain(&main_buf, 300), 1);

    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try fixture.load(machine);

    // 300 acquire/release cycles in one run: without release returning the
    // slot to the free set the 257th acquire would push NULL and the release
    // would fail.
    try std.testing.expectEqual(@as(i64, 42), try machine.runEntry("main"));

    var total: u32 = 0;
    var live: u32 = 0;
    var reusable: u32 = 0;
    var retired: u32 = 0;
    vm.ci_callback_pool_stats(&total, &live, &reusable, &retired);
    try std.testing.expectEqual(@as(u32, 256), total);
    try std.testing.expectEqual(@as(u32, 0), live);
    try std.testing.expectEqual(@as(u32, 256), reusable);
    try std.testing.expectEqual(@as(u32, 0), retired);

    // A release puts the slot back where the next acquire finds it.
    const first = try machine.runEntryIndex(3, &.{});
    try std.testing.expect(first != 0);
    try std.testing.expectEqual(@as(i64, 0), try releaseOne(machine, first));
    const second = try machine.runEntryIndex(3, &.{});
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(i64, 0), try releaseOne(machine, second));
}

test "callback release reports busy while a dispatch is still active" {
    vm.resetCallbackPoolForTest();
    defer vm.resetCallbackPoolForTest();

    var fixture = CallbackFixture{};
    fixture.build(&callback_acquire_fn, 0);

    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try fixture.load(machine);

    const addr = try machine.runEntryIndex(3, &.{});
    try std.testing.expect(addr != 0);

    // Pretend a native dispatcher is inside the callback right now.
    try std.testing.expect(vm.holdCallbackSlotForTest(machine, @intCast(addr), 1));
    try std.testing.expectEqual(@as(i64, vm.CI_E_BUSY), try releaseOne(machine, addr));
    var live: u32 = 0;
    vm.ci_callback_pool_stats(null, &live, null, null);
    try std.testing.expectEqual(@as(u32, 1), live);

    // Retry once the dispatch finished.
    try std.testing.expect(vm.holdCallbackSlotForTest(machine, @intCast(addr), -1));
    try std.testing.expectEqual(@as(i64, vm.CI_OK), try releaseOne(machine, addr));
    // The pointer is dead after a successful release.
    try std.testing.expectEqual(@as(i64, vm.CI_E_INVALID_ARGUMENT), try releaseOne(machine, addr));
    vm.ci_callback_pool_stats(null, &live, null, null);
    try std.testing.expectEqual(@as(u32, 0), live);
}

test "unreleased callback slots are retired, released slots are not" {
    vm.resetCallbackPoolForTest();
    defer vm.resetCallbackPoolForTest();

    var cycle_buf: [128]u8 = undefined;
    var acquire_fixture = CallbackFixture{};
    acquire_fixture.build(&callback_acquire_fn, 0);
    var cycle_fixture = CallbackFixture{};
    cycle_fixture.build(callbackCycleMain(&cycle_buf, 1), 1);

    var total: u32 = 0;
    var live: u32 = 0;
    var reusable: u32 = 0;
    var retired: u32 = 0;

    // A VM that never releases its explicit slot retires it on destroy.
    {
        const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
        try acquire_fixture.load(machine);
        try std.testing.expect((try machine.runEntryIndex(3, &.{})) != 0);
        vm.ci_callback_pool_stats(&total, &live, &reusable, &retired);
        try std.testing.expectEqual(@as(u32, 1), live);
        vm.ci_vm_destroy(machine);
    }
    vm.ci_callback_pool_stats(&total, &live, &reusable, &retired);
    try std.testing.expectEqual(@as(u32, 0), live);
    try std.testing.expectEqual(@as(u32, 1), retired);
    try std.testing.expectEqual(@as(u32, 255), reusable);

    // A VM that releases its slot leaves the pool untouched.
    {
        const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
        try cycle_fixture.load(machine);
        try std.testing.expectEqual(@as(i64, 42), try machine.runEntry("main"));
        vm.ci_callback_pool_stats(&total, &live, &reusable, &retired);
        try std.testing.expectEqual(@as(u32, 0), live);
        try std.testing.expectEqual(@as(u32, 1), retired);
        try std.testing.expectEqual(@as(u32, 255), reusable);
        vm.ci_vm_destroy(machine);
    }
    vm.ci_callback_pool_stats(&total, &live, &reusable, &retired);
    try std.testing.expectEqual(@as(u32, 1), retired);
    try std.testing.expectEqual(@as(u32, 255), reusable);

    // Replacing the plans of a VM that still owns an explicit slot retires it:
    // the plan metadata a dispatch would read is freed with the store.
    {
        const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
        defer vm.ci_vm_destroy(machine);
        try acquire_fixture.load(machine);
        try std.testing.expect((try machine.runEntryIndex(3, &.{})) != 0);
        try machine.loadPlans(acquire_fixture.plans, &.{"cb"});
        vm.ci_callback_pool_stats(&total, &live, &reusable, &retired);
        try std.testing.expectEqual(@as(u32, 0), live);
        try std.testing.expectEqual(@as(u32, 2), retired);
        try std.testing.expectEqual(@as(u32, 254), reusable);
    }
}

test "a callback while another thread runs the VM fails fast; an idle VM runs it" {
    vm.resetCallbackPoolForTest();
    defer vm.resetCallbackPoolForTest();

    var fixture = CallbackFixture{};
    fixture.build(&callback_acquire_fn, 0);

    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try fixture.load(machine);

    const addr = try machine.runEntryIndex(3, &.{});
    try std.testing.expect(addr != 0);
    const slot = callbackSlotOf(@intCast(addr)).?;

    var frame: platform.CallbackFrame = std.mem.zeroes(platform.CallbackFrame);

    // Another thread holds the execution right: the dispatch is skipped with a
    // zeroed return value and CI_E_BUSY recorded instead of blocking.
    setCallbackIntRet(&frame, 0xdead_beef);
    var holder = ForeignOwner{ .state = machine.run_state.? };
    const thread = try std.Thread.spawn(.{}, ForeignOwner.hold, .{&holder});
    try waitForFlag(&holder.held);
    try std.testing.expectEqual(@as(c_int, 1), vm.ci_vm_busy(machine));
    vm.ci_callback_dispatch(slot, &frame);
    try std.testing.expectEqual(@as(u64, 0), callbackIntRet(&frame));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_callback_error(machine));
    holder.release.store(true, .seq_cst);
    thread.join();

    // ci_vm_clear_error clears the callback channel too.
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_clear_error(machine));
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_callback_error(machine));

    // Idle VM: the dispatch takes and releases the execution right and writes
    // the real result into the trampoline frame.
    vm.ci_callback_dispatch(slot, &frame);
    try std.testing.expectEqual(@as(u64, 7), callbackIntRet(&frame));
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_callback_error(machine));
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_busy(machine));

    // The thread that already runs the VM re-enters the callback.
    try machine.run_state.?.enter();
    setCallbackIntRet(&frame, 0);
    vm.ci_callback_dispatch(slot, &frame);
    try std.testing.expectEqual(@as(u64, 7), callbackIntRet(&frame));
    _ = machine.run_state.?.leave();
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_callback_error(machine));

    // A dispatch that races a destroy is skipped with zero return values too.
    machine.callback_destroying = true;
    setCallbackIntRet(&frame, 0xdead_beef);
    vm.ci_callback_dispatch(slot, &frame);
    try std.testing.expectEqual(@as(u64, 0), callbackIntRet(&frame));
    machine.callback_destroying = false;

    try std.testing.expectEqual(@as(i64, 0), try releaseOne(machine, addr));
}

test "retired callback trampoline slots are not reused" {
    vm.resetCallbackPoolForTest();
    defer vm.resetCallbackPoolForTest();

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
        try machine.loadPlans(plans, &.{"cb"});
        try std.testing.expectEqual(@as(i64, 0), try machine.runEntry("main"));
    }

    const overflow = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(overflow);
    try overflow.loadModuleBytes(module);
    try overflow.loadPlans(plans, &.{"cb"});
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

/// `main` that returns 42 only when linear memory starts out zeroed: it reads
/// the first word, writes a marker over it, and adds the old value to 42.
const fresh_image_main = [_]u8{
    vm.OP_ADDR_CONST,
    0,              0, 0,                 0, // &mem[0]
    vm.OP_LOAD_MEM, 8, vm.OP_STORE_LOCAL,
    0,                    0, // local 0 = *(i64*)mem
    vm.OP_LOAD_CONST_I64, 0x55,
    0,                    0,
    0,                    0,
    0,                    0,
    0,                    vm.OP_ADDR_CONST,
    0,                    0,
    0,                    0,
    vm.OP_STORE_MEM,
    8, // *(i64*)mem = 0x55
    vm.OP_LOAD_LOCAL,
    0,
    0,
    vm.OP_LOAD_CONST_I64,
    42,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    vm.OP_ADD,
    vm.OP_RET,
};

test "ADDR_CONST rejects an offset at the end of linear memory" {
    var code_buf: [8]u8 = undefined;
    var a = Asm{ .buf = &code_buf };
    a.u8v(vm.OP_ADDR_CONST);
    a.u32v(@intCast(vm.DEFAULT_MEMORY));
    a.u8v(vm.OP_RET);
    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = a.code() },
    };
    var module_buf: [128]u8 = undefined;
    var machine = vm.VM{};
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));
    try std.testing.expectError(error.BadAddress, machine.runEntry("main"));
}

test "repeated runs start from a fresh image" {
    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 2, .code = &fresh_image_main },
    };
    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));

    var run: usize = 0;
    while (run < 4) : (run += 1) {
        try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
        // 42 only if the previous run's marker was cleared.
        try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
        try std.testing.expectEqual(@as(u8, 0x55), machine.mem[0]);
        try std.testing.expectEqual(@as(usize, 0), machine.frame_count);
    }
}

test "a run start clears setjmp targets from the previous run" {
    // A jump buffer only needs to be a stable address, so linear memory works.
    var setjmp_code: [32]u8 = undefined;
    var setjmp_asm = Asm{ .buf = &setjmp_code };
    setjmp_asm.u8v(vm.OP_ADDR_CONST);
    setjmp_asm.u32v(0);
    setjmp_asm.u8v(vm.OP_SETJMP);
    setjmp_asm.u16v(1); // slot 1 of a 2-local frame
    setjmp_asm.u8v(vm.OP_RET_VOID);

    var longjmp_code: [32]u8 = undefined;
    var longjmp_asm = Asm{ .buf = &longjmp_code };
    longjmp_asm.u8v(vm.OP_ADDR_CONST);
    longjmp_asm.u32v(0);
    longjmp_asm.u8v(vm.OP_LOAD_CONST_I64);
    longjmp_asm.i64v(1);
    longjmp_asm.u8v(vm.OP_LONGJMP);
    longjmp_asm.u8v(vm.OP_RET_VOID);

    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);

    const setjmp_funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 2, .code = setjmp_asm.code() },
    };
    try machine.loadModuleBytes(buildModule(&module_buf, &setjmp_funcs));
    try std.testing.expectEqual(@as(i64, 0), try machine.runEntry("main"));
    // The first run recorded a live target for &mem[0].
    try std.testing.expect(machine.jumps[0].valid);
    try std.testing.expectEqual(@as(u16, 1), machine.jumps[0].slot);

    // The second module's frame still has slot 1, so the recorded entry would
    // be structurally usable; only the per-run reset can make this fail.
    const longjmp_funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 2, .code = longjmp_asm.code() },
    };
    try machine.loadModuleBytes(buildModule(&module_buf, &longjmp_funcs));
    try std.testing.expectError(error.BadLongjmp, machine.runEntry("main"));
    try std.testing.expect(!machine.jumps[0].valid);
}

test "a failed run keeps the last successful result" {
    var ok_code: [16]u8 = undefined;
    var ok = Asm{ .buf = &ok_code };
    ok.u8v(vm.OP_LOAD_CONST_I64);
    ok.i64v(42);
    ok.u8v(vm.OP_RET);

    var bad_code: [8]u8 = undefined;
    var bad = Asm{ .buf = &bad_code };
    bad.u8v(vm.OP_POP); // empty value stack
    bad.u8v(vm.OP_RET_VOID);

    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = ok.code() },
        .{ .name = "bad", .params = 0, .locals = 0, .code = bad.code() },
    };
    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));

    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));

    // A run that fails after the fresh-image reset must not clear the result.
    try std.testing.expectEqual(vm.CI_E_ENTRY, vm.ci_vm_run(machine, "bad"));
    try std.testing.expectEqual(vm.CI_E_ENTRY, vm.ci_vm_last_error_code(machine));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));

    // An unknown entry fails before the reset and must not clear it either.
    try std.testing.expectEqual(vm.CI_E_ENTRY, vm.ci_vm_run(machine, "missing"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));

    // And the VM is still usable afterwards.
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
}

test "a run re-entered by the owning thread is rejected" {
    var ok_code: [16]u8 = undefined;
    var ok = Asm{ .buf = &ok_code };
    ok.u8v(vm.OP_LOAD_CONST_I64);
    ok.i64v(42);
    ok.u8v(vm.OP_RET);

    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = ok.code() },
    };
    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));

    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));

    // Stand in for a callback that re-enters ci_vm_run: the execution right is
    // held by this thread, exactly as it is during a real run.
    try machine.run_state.?.enter();
    try std.testing.expectEqual(@as(c_int, 1), vm.ci_vm_busy(machine));
    try std.testing.expectEqual(vm.CI_E_RUNTIME, vm.ci_vm_run(machine, "main"));
    try std.testing.expectEqual(vm.CI_E_RUNTIME, vm.ci_vm_last_error_code(machine));
    // The rejected call did not disturb the previous result.
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
    _ = machine.run_state.?.leave();

    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_busy(machine));
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
}

test "loaders report CI_E_BUSY while the VM executes" {
    var ok_code: [16]u8 = undefined;
    var ok = Asm{ .buf = &ok_code };
    ok.u8v(vm.OP_LOAD_CONST_I64);
    ok.i64v(42);
    ok.u8v(vm.OP_RET);

    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = ok.code() },
    };
    var module_buf: [128]u8 = undefined;
    const module = buildModule(&module_buf, &funcs);
    var plans_buf: [32]u8 = undefined;
    const plans = buildEmptyPlans(&plans_buf);
    var package_buf: [256]u8 = undefined;
    const package = buildPackage(&package_buf, module, plans);

    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(module);

    try machine.run_state.?.enter();
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_load_module(machine, module.ptr, module.len));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_load_plans(machine, plans.ptr, plans.len));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_load_package(machine, package.ptr, package.len));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_load_library(machine, "libcinterp-does-not-exist.so"));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_last_error_code(machine));
    _ = machine.run_state.?.leave();

    // Idle again: standalone plan loading is unsupported for v4; packages go
    // through the CIPC-aware loader.
    try std.testing.expectEqual(vm.CI_E_PLANS, vm.ci_vm_load_plans(machine, plans.ptr, plans.len));
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_load_package(machine, package.ptr, package.len));
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
}

const BusyProbe = struct {
    machine: *vm.VM,
    started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    status: c_int = vm.CI_ERROR,

    fn run(self: *BusyProbe) void {
        self.started.store(true, .seq_cst);
        self.status = vm.ci_vm_run(self.machine, "main");
    }
};

/// Hold a VM's execution right from a second thread until the test releases
/// it. This makes the cross-thread `CI_E_BUSY` paths deterministic: no timing
/// window, the owner cannot finish before the assertions run.
const ForeignOwner = struct {
    state: *vm.RunState,
    held: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    release: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    entered: bool = false,

    fn hold(self: *ForeignOwner) void {
        self.state.enter() catch return;
        self.entered = true;
        self.held.store(true, .seq_cst);
        while (!self.release.load(.seq_cst)) std.time.sleep(100 * std.time.ns_per_us);
        _ = self.state.leave();
    }
};

fn waitForFlag(flag: *std.atomic.Value(bool)) !void {
    const deadline = std.time.nanoTimestamp() + 10 * std.time.ns_per_s;
    while (!flag.load(.seq_cst)) {
        if (std.time.nanoTimestamp() > deadline) return error.TimedOutWaitingForTest;
        std.time.sleep(50 * std.time.ns_per_us);
    }
}

test "two threads on one VM: the second reports CI_E_BUSY" {
    var code_buf: [64]u8 = undefined;
    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 1, .code = loopMain(&code_buf, 1_000_000, 42) },
    };
    var module_buf: [128]u8 = undefined;
    const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    defer vm.ci_vm_destroy(machine);
    try machine.loadModuleBytes(buildModule(&module_buf, &funcs));

    var probe = BusyProbe{ .machine = machine };
    const thread = try std.Thread.spawn(.{}, BusyProbe.run, .{&probe});
    var joined = false;
    defer {
        if (!joined) thread.join();
    }

    // Wait for the worker to take the VM, then race it from this thread.
    const deadline = std.time.nanoTimestamp() + 10 * std.time.ns_per_s;
    while (!probe.started.load(.seq_cst)) {
        if (std.time.nanoTimestamp() > deadline) return error.TimedOutWaitingForRun;
    }
    while (vm.ci_vm_busy(machine) == 0) {
        if (std.time.nanoTimestamp() > deadline) return error.TimedOutWaitingForRun;
    }
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_run(machine, "main"));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_last_error_code(machine));

    thread.join();
    joined = true;
    try std.testing.expectEqual(vm.CI_OK, probe.status);
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_busy(machine));
}

const VmRunThread = struct {
    machine: *vm.VM,
    runs: usize,
    status: c_int = vm.CI_ERROR,
    result: i64 = 0,

    fn run(self: *VmRunThread) void {
        var i: usize = 0;
        while (i < self.runs) : (i += 1) {
            self.status = vm.ci_vm_run(self.machine, "main");
            if (self.status != vm.CI_OK) return;
            self.result = vm.ci_vm_result(self.machine);
        }
    }
};

test "two VMs run independently on two threads" {
    var code_a: [64]u8 = undefined;
    var code_b: [64]u8 = undefined;
    const funcs_a = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 1, .code = loopMain(&code_a, 200_000, 42) },
    };
    const funcs_b = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 1, .code = loopMain(&code_b, 200_000, 7) },
    };
    var module_a: [128]u8 = undefined;
    var module_b: [128]u8 = undefined;

    const a = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    const b = vm.ci_vm_create(0) orelse {
        vm.ci_vm_destroy(a);
        return error.OutOfMemory;
    };
    try a.loadModuleBytes(buildModule(&module_a, &funcs_a));
    try b.loadModuleBytes(buildModule(&module_b, &funcs_b));

    var worker_a = VmRunThread{ .machine = a, .runs = 3 };
    var worker_b = VmRunThread{ .machine = b, .runs = 3 };
    const thread_a = try std.Thread.spawn(.{}, VmRunThread.run, .{&worker_a});
    const thread_b = try std.Thread.spawn(.{}, VmRunThread.run, .{&worker_b});
    thread_a.join();
    thread_b.join();

    try std.testing.expectEqual(vm.CI_OK, worker_a.status);
    try std.testing.expectEqual(@as(i64, 42), worker_a.result);
    try std.testing.expectEqual(vm.CI_OK, worker_b.status);
    try std.testing.expectEqual(@as(i64, 7), worker_b.result);

    // Destroying one VM leaves the other one usable.
    vm.ci_vm_destroy(a);
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(b, "main"));
    try std.testing.expectEqual(@as(i64, 7), vm.ci_vm_result(b));
    vm.ci_vm_destroy(b);
}

test "ci_vm_destroy_ex TRY reports a busy VM and defers a same-thread destroy" {
    var ok_code: [16]u8 = undefined;
    var ok = Asm{ .buf = &ok_code };
    ok.u8v(vm.OP_LOAD_CONST_I64);
    ok.i64v(42);
    ok.u8v(vm.OP_RET);
    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = ok.code() },
    };
    var module_buf: [128]u8 = undefined;
    const module = buildModule(&module_buf, &funcs);

    // An idle VM is destroyed by the try path.
    const idle = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    try idle.loadModuleBytes(module);
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_destroy_ex(idle, vm.CI_DESTROY_TRY));

    // Unknown flags are rejected instead of silently ignored.
    const other = vm.ci_vm_create(0) orelse return error.OutOfMemory;
    try other.loadModuleBytes(module);
    try std.testing.expectEqual(vm.CI_E_INVALID_ARGUMENT, vm.ci_vm_destroy_ex(other, 2));
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_busy(other));

    // A second thread holds the execution right: the try path reports busy.
    var owner = ForeignOwner{ .state = other.run_state.? };
    const owner_thread = try std.Thread.spawn(.{}, ForeignOwner.hold, .{&owner});
    var owner_joined = false;
    defer {
        if (!owner_joined) {
            owner.release.store(true, .seq_cst);
            owner_thread.join();
        }
    }
    try waitForFlag(&owner.held);
    try std.testing.expect(owner.entered);
    try std.testing.expectEqual(@as(c_int, 1), vm.ci_vm_busy(other));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_destroy_ex(other, vm.CI_DESTROY_TRY));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_vm_last_error_code(other));
    owner.release.store(true, .seq_cst);
    owner_thread.join();
    owner_joined = true;
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_busy(other));

    // A destroy from the thread that is running the VM cannot wait for itself:
    // it returns immediately (and a repeat request is idempotent) while the
    // outermost run frees the VM.
    try other.run_state.?.enter();
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_destroy_ex(other, 0));
    try std.testing.expectEqual(@as(c_int, 1), vm.ci_vm_busy(other));
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_destroy_ex(other, vm.CI_DESTROY_TRY));
    try std.testing.expect(other.run_state.?.leave());
    // This test stands in for the run frame, which frees the VM here.
    vm.finishDeferredDestroy(other);
}

fn loadTestPackage(process: *vm.Process, package: []const u8, out: *?*vm.VM) c_int {
    return vm.ci_process_load_package(process, package.ptr, package.len, out);
}

test "a process loads, runs, unloads and destroys independent VMs" {
    var code_buf: [16]u8 = undefined;
    var code = Asm{ .buf = &code_buf };
    code.u8v(vm.OP_LOAD_CONST_I64);
    code.i64v(42);
    code.u8v(vm.OP_RET);
    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = code.code() },
    };
    var module_buf: [128]u8 = undefined;
    var plans_buf: [32]u8 = undefined;
    var package_buf: [256]u8 = undefined;
    const package = buildPackage(&package_buf, buildModule(&module_buf, &funcs), buildEmptyPlans(&plans_buf));

    const process = vm.ci_process_create(null) orelse return error.OutOfMemory;
    var first: ?*vm.VM = null;
    var second: ?*vm.VM = null;
    try std.testing.expectEqual(vm.CI_OK, loadTestPackage(process, package, &first));
    try std.testing.expectEqual(vm.CI_OK, loadTestPackage(process, package, &second));
    try std.testing.expect(first != null and second != null);
    try std.testing.expect(first.? != second.?);
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(first.?, "main"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(first.?));
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(second.?, "main"));
    try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(second.?));

    // A rejected package leaves the registry alone and records the category.
    var broken_buf: [256]u8 = undefined;
    @memcpy(broken_buf[0..package.len], package);
    broken_buf[0] = 'X';
    var unused: ?*vm.VM = null;
    try std.testing.expectEqual(vm.CI_E_BAD_PACKAGE, loadTestPackage(process, broken_buf[0..package.len], &unused));
    try std.testing.expect(unused == null);
    try std.testing.expectEqual(vm.CI_E_BAD_PACKAGE, vm.ci_process_last_error_code(process));
    if (@import("builtin").mode == .Debug)
        try std.testing.expect(vm.ci_process_last_error(process)[0] != 0);
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(second.?, "main"));

    // Unloading is one-shot; the borrowed handle is dead afterwards. (Only its
    // value is used below, it is never dereferenced.)
    const first_vm = first.?;
    try std.testing.expectEqual(vm.CI_OK, vm.ci_process_unload_package(process, first_vm));
    try std.testing.expectEqual(vm.CI_E_INVALID_ARGUMENT, vm.ci_process_unload_package(process, first_vm));
    try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(second.?, "main"));

    vm.ci_process_destroy(process);
}

test "a process reports busy VMs instead of freeing them" {
    var code_buf: [16]u8 = undefined;
    var code = Asm{ .buf = &code_buf };
    code.u8v(vm.OP_LOAD_CONST_I64);
    code.i64v(42);
    code.u8v(vm.OP_RET);
    const funcs = [_]FunctionSpec{
        .{ .name = "main", .params = 0, .locals = 0, .code = code.code() },
    };
    var module_buf: [128]u8 = undefined;
    var plans_buf: [32]u8 = undefined;
    var package_buf: [256]u8 = undefined;
    const package = buildPackage(&package_buf, buildModule(&module_buf, &funcs), buildEmptyPlans(&plans_buf));

    const process = vm.ci_process_create(null) orelse return error.OutOfMemory;
    var handle: ?*vm.VM = null;
    try std.testing.expectEqual(vm.CI_OK, loadTestPackage(process, package, &handle));
    const machine = handle orelse return error.OutOfMemory;

    // A second thread holds the VM's execution right, as a run thread would.
    var owner = ForeignOwner{ .state = machine.run_state.? };
    const owner_thread = try std.Thread.spawn(.{}, ForeignOwner.hold, .{&owner});
    var owner_joined = false;
    defer {
        if (!owner_joined) {
            owner.release.store(true, .seq_cst);
            owner_thread.join();
        }
    }
    try waitForFlag(&owner.held);

    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_process_unload_package(process, machine));
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_process_last_error_code(process));

    // Destroy keeps the busy VM and the process alive so the error stays
    // observable and a later unload/destroy can still free it.
    vm.ci_process_destroy(process);
    try std.testing.expectEqual(vm.CI_E_BUSY, vm.ci_process_last_error_code(process));
    try std.testing.expectEqual(@as(c_int, 1), vm.ci_vm_busy(machine));

    owner.release.store(true, .seq_cst);
    owner_thread.join();
    owner_joined = true;
    try std.testing.expectEqual(@as(c_int, 0), vm.ci_vm_busy(machine));
    // Idle again, so the retry frees the VM and the process.
    vm.ci_process_destroy(process);
}

test "CIPC v2 encrypted data is decrypted on every run" {
    const key = [_]u8{
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x01,
    };
    const keys = [_]?[cipc.key_len]u8{ key, null };

    for (keys) |key_opt| {
        var code_buf: [8]u8 = undefined;
        var code = Asm{ .buf = &code_buf };
        code.u8v(vm.OP_LOAD_CONST_POOL);
        code.u32v(@as(u32, 3) << 28);
        code.u8v(vm.OP_RET);
        const funcs = [_]FunctionSpec{
            .{ .name = "main", .params = 0, .locals = 0, .code = code.code() },
        };
        var module_buf: [128]u8 = undefined;
        const module = buildModule(&module_buf, &funcs);
        var plans_buf: [32]u8 = undefined;
        const plans = buildEmptyPlans(&plans_buf);

        var data: [8]u8 = undefined;
        std.mem.writeInt(u64, &data, 42, .little);
        var cipc_buf: [64]u8 = undefined;
        const cipc_bytes = buildCipcWithData(&cipc_buf, &data, key_opt);
        var package_buf: [256]u8 = undefined;
        const package = buildPackageWithCipc(&package_buf, module, plans, cipc_bytes);

        const machine = vm.ci_vm_create(0) orelse return error.OutOfMemory;
        defer vm.ci_vm_destroy(machine);
        try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_load_package(machine, package.ptr, package.len));
        try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
        try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
        try std.testing.expectEqual(vm.CI_OK, vm.ci_vm_run(machine, "main"));
        try std.testing.expectEqual(@as(i64, 42), vm.ci_vm_result(machine));
    }
}

test "LOAD_CONST_POOL fuses fallthrough integer ALU" {
    var code_buf: [32]u8 = undefined;
    var data: [8]u8 = undefined;
    const ref_u64: u32 = @as(u32, 3) << 28;

    std.mem.writeInt(u64, &data, 7, .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, 5, ref_u64, vm.OP_ADD, null), &data, 12);

    std.mem.writeInt(u64, &data, 3, .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, 10, ref_u64, vm.OP_SUB, null), &data, 7);

    std.mem.writeInt(u64, &data, 7, .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, 6, ref_u64, vm.OP_MUL, null), &data, 42);

    std.mem.writeInt(u64, &data, 5, .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, 1, ref_u64, vm.OP_SHL, null), &data, 32);

    std.mem.writeInt(u64, &data, 3, .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, -7, ref_u64, vm.OP_DIV_S, null), &data, -2);
    try expectFusedResult(buildPoolAluProgram(&code_buf, -7, ref_u64, vm.OP_REM_S, null), &data, -1);

    var data32: [4]u8 = undefined;
    std.mem.writeInt(u32, &data32, @bitCast(@as(i32, -2)), .little);
    const ref_s32: u32 = (@as(u32, 2) << 28) | (1 << 30);
    try expectFusedResult(buildPoolAluProgram(&code_buf, -7, ref_s32, vm.OP_DIV_S, null), &data32, 3);
}

test "LOAD_CONST_POOL fuses narrow ALU and normalizes" {
    var code_buf: [32]u8 = undefined;
    var data: [1]u8 = .{1};
    try expectFusedResult(
        buildPoolAluProgram(&code_buf, 127, @as(u32, 1) << 30, vm.OP_ADD_N, 0x80),
        &data,
        -128,
    );

    data[0] = 100;
    try expectFusedResult(buildPoolAluProgram(&code_buf, 200, 0, vm.OP_ADD_N, 0x00), &data, 44);
}

test "LOAD_CONST_POOL fuses integer comparisons" {
    var code_buf: [32]u8 = undefined;
    var data: [8]u8 = undefined;
    const ref: u32 = @as(u32, 3) << 28;

    std.mem.writeInt(u64, &data, 5, .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, 5, ref, vm.OP_CMP_EQ, null), &data, 1);
    try expectFusedResult(buildPoolAluProgram(&code_buf, 4, ref, vm.OP_CMP_EQ, null), &data, 0);

    std.mem.writeInt(u64, &data, 0, .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, -1, ref, vm.OP_CMP_LT, null), &data, 1);
    try expectFusedResult(buildPoolAluProgram(&code_buf, -1, ref, vm.OP_CMP_LT_U, null), &data, 0);

    std.mem.writeInt(u64, &data, std.math.maxInt(u64), .little);
    try expectFusedResult(buildPoolAluProgram(&code_buf, 0, ref, vm.OP_CMP_LT_U, null), &data, 1);
}

test "LOAD_CONST_POOL fusion keeps division-by-zero errors" {
    var code_buf: [32]u8 = undefined;
    const data = [_]u8{0} ** 8;
    const ref: u32 = @as(u32, 3) << 28;
    try expectPoolRuntimeError(buildPoolAluProgram(&code_buf, 10, ref, vm.OP_DIV_S, null), &data);
    try expectPoolRuntimeError(buildPoolAluProgram(&code_buf, 10, ref, vm.OP_REM_U, null), &data);
}

test "a jump into the ALU bypasses the const-load fusion" {
    var code_buf: [48]u8 = undefined;
    var data: [8]u8 = undefined;
    std.mem.writeInt(u64, &data, 7, .little);

    var code = Asm{ .buf = &code_buf };
    code.u8v(vm.OP_LOAD_CONST_I64);
    code.i64v(5);
    code.u8v(vm.OP_LOAD_CONST_I64);
    code.i64v(10);
    code.u8v(vm.OP_JMP);
    // Skip the 4-byte operand plus LOAD_CONST_POOL and its 4-byte ref.
    code.u32v(@intCast(code.pos + 4 + 1 + 4));
    code.u8v(vm.OP_LOAD_CONST_POOL);
    code.u32v(@as(u32, 3) << 28);
    code.u8v(vm.OP_ADD);
    code.u8v(vm.OP_RET);

    const run = try runPoolProgram(code.code(), &data);
    try std.testing.expectEqual(vm.CI_OK, run.status);
    try std.testing.expectEqual(@as(i64, 15), run.result);
    if (comptime traceEnabled()) try std.testing.expectEqual(@as(u64, 0), run.fused);
}

fn buildNarrowProgram(buf: []u8, lhs: i64, rhs: i64, opcode: u8, param: u8) []const u8 {
    var a = Asm{ .buf = buf };
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(lhs);
    a.u8v(vm.OP_LOAD_CONST_I64);
    a.i64v(rhs);
    a.u8v(opcode);
    a.u8v(param);
    a.u8v(vm.OP_RET);
    return a.code();
}

test "narrow shift/div/rem opcodes" {
    var code_buf: [64]u8 = undefined;
    const p8: u8 = 0x80;
    const p32: u8 = 0x82;

    try expectPoolResult(buildNarrowProgram(&code_buf, 1, 1, vm.OP_SHL_N, p8), "", 2);
    try expectPoolResult(buildNarrowProgram(&code_buf, 1, 9, vm.OP_SHL_N, p8), "", 0);
    try expectPoolResult(buildNarrowProgram(&code_buf, 1, 64, vm.OP_SHL_N, p8), "", 1);
    try expectPoolResult(buildNarrowProgram(&code_buf, -1, 1, vm.OP_SHL_N, p8), "", -2);
    try expectPoolResult(buildNarrowProgram(&code_buf, 1, 31, vm.OP_SHL_N, p32), "", -2147483648);

    try expectPoolResult(buildNarrowProgram(&code_buf, -1, 1, vm.OP_SHR_U_N, p8), "", 127);
    try expectPoolResult(buildNarrowProgram(&code_buf, -1, 8, vm.OP_SHR_U_N, p8), "", 0);
    try expectPoolResult(buildNarrowProgram(&code_buf, -1, 1, vm.OP_SHR_S_N, p8), "", -1);
    try expectPoolResult(buildNarrowProgram(&code_buf, -128, 9, vm.OP_SHR_S_N, p8), "", -1);
    try expectPoolResult(buildNarrowProgram(&code_buf, -8, 1, vm.OP_SHR_S_N, p32), "", -4);

    try expectPoolResult(buildNarrowProgram(&code_buf, -7, 2, vm.OP_DIV_S_N, p8), "", -3);
    try expectPoolResult(buildNarrowProgram(&code_buf, -1, 2, vm.OP_DIV_U_N, p8), "", 127);
    try expectPoolResult(buildNarrowProgram(&code_buf, -7, 2, vm.OP_REM_S_N, p8), "", -1);
    try expectPoolResult(buildNarrowProgram(&code_buf, -1, 2, vm.OP_REM_U_N, p8), "", 1);
    try expectPoolResult(buildNarrowProgram(&code_buf, -1, 2, vm.OP_DIV_U_N, p32), "", 0x7FFFFFFF);
}

test "narrow div/rem reject zero divisors" {
    var code_buf: [64]u8 = undefined;
    const p8: u8 = 0x80;
    try expectPoolRuntimeError(buildNarrowProgram(&code_buf, 7, 0, vm.OP_DIV_S_N, p8), "");
    try expectPoolRuntimeError(buildNarrowProgram(&code_buf, 7, 0, vm.OP_DIV_U_N, p8), "");
    try expectPoolRuntimeError(buildNarrowProgram(&code_buf, 7, 0, vm.OP_REM_S_N, p8), "");
    try expectPoolRuntimeError(buildNarrowProgram(&code_buf, 7, 0, vm.OP_REM_U_N, p8), "");
    try expectPoolRuntimeError(buildNarrowProgram(&code_buf, 7, 1, vm.OP_SHL_N, 0x03), "");
}
