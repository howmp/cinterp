const std = @import("std");
const builtin = @import("builtin");
const vm = @import("vm.zig");

const debug_errors = builtin.mode == .Debug;

/// `ci_vm_run_args` accepts at most 256 entries; argv[0] is the package path.
const max_args = 256;

const usage =
    \\usage: cinterp-run [--trace] <package.cib> [-- arg1 arg2 ...]
    \\
    \\The package is loaded and its main entry is run once. Arguments after
    \\`--` are passed as argv[1..], with the package path as argv[0]. The
    \\result is reported as `result: <i32>`; it is not the process exit
    \\status (0 success, 1 load/run failure, 2 usage/I/O).
    \\
    \\`--trace` (or CINTERP_TRACE=1) prints opcode, function and native-call
    \\histograms after the run. Counters are only compiled into Debug and
    \\ReleaseSafe runtimes.
    \\
;

fn usageFail(comptime fmt: []const u8, fmt_args: anytype) noreturn {
    std.debug.print("cinterp-run: " ++ fmt ++ "\n", fmt_args);
    std.debug.print("{s}", .{usage});
    std.process.exit(2);
}

fn outOfMemory() noreturn {
    std.debug.print("cinterp-run: out of memory\n", .{});
    std.process.exit(2);
}

/// Programs that call libc `exit()` never return from `ci_vm_run_args`, so the
/// final dump in `main` would be skipped. Keep the VM and timer reachable from
/// an `atexit` handler instead. Windows exes do not link the CRT, so they only
/// get the normal post-run dump.
var trace_machine: ?*vm.VM = null;
var trace_timer: ?std.time.Timer = null;

fn traceAtExit() callconv(.C) void {
    if (trace_machine) |machine| {
        const elapsed_ns: ?u64 = if (trace_timer) |*timer| timer.read() else null;
        machine.dumpTrace(std.io.getStdErr().writer(), elapsed_ns) catch {};
        trace_machine = null;
    }
}

extern "c" fn atexit(handler: *const fn () callconv(.C) void) c_int;

fn installTraceAtExit() void {
    if (comptime builtin.os.tag != .windows) _ = atexit(&traceAtExit);
}

fn initFpu() void {
    if (comptime @import("builtin").cpu.arch == .x86 or
        @import("builtin").cpu.arch == .x86_64)
    {
        // MinGW CRT normally resets the x87 control word during startup. A
        // no-CRT Windows executable must do it explicitly so `long double`
        // keeps extended precision.
        asm volatile ("fninit" ::: "memory");
    }
}

pub fn main() u8 {
    initFpu();
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch return 2;
    defer std.process.argsFree(allocator, args);

    const trace_env = std.process.getEnvVarOwned(allocator, "CINTERP_TRACE") catch null;
    defer if (trace_env) |value| allocator.free(value);
    var trace = if (trace_env) |value| value.len != 0 and !std.mem.eql(u8, value, "0") else false;

    var arg_start: usize = 1;
    if (args.len > 1 and std.mem.eql(u8, args[1], "--trace")) {
        trace = true;
        arg_start = 2;
    }
    if (args.len <= arg_start) usageFail("missing package", .{});
    const package = args[arg_start];
    if (args.len > arg_start + 1 and !std.mem.eql(u8, args[arg_start + 1], "--")) {
        usageFail("unexpected argument '{s}'; use -- before program arguments", .{args[arg_start + 1]});
    }
    const first_tail: usize = if (args.len > arg_start + 1) arg_start + 2 else args.len;
    if (args.len - first_tail + 1 > max_args) usageFail("too many arguments after --", .{});

    var argv_buf: [max_args]?[*:0]const u8 = undefined;
    argv_buf[0] = package.ptr;
    var argc: usize = 1;
    var i = first_tail;
    while (i < args.len) : (i += 1) {
        argv_buf[argc] = args[i].ptr;
        argc += 1;
    }

    const bytes = std.fs.cwd().readFileAlloc(allocator, package, 16 * 1024 * 1024) catch |err| {
        if (comptime debug_errors) {
            std.debug.print("cinterp-run: cannot read {s}: {s}\n", .{ package, @errorName(err) });
        } else {
            std.debug.print("cinterp-run: cannot read {s}\n", .{package});
        }
        return 2;
    };
    defer allocator.free(bytes);

    const machine = vm.ci_vm_create(0) orelse outOfMemory();
    machine.setTrace(trace);
    const load_status = vm.ci_vm_load_package(machine, bytes.ptr, bytes.len);
    if (load_status != 0) {
        if (comptime debug_errors) {
            std.debug.print("cinterp-run: load failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        } else {
            std.debug.print("cinterp-run: load failed: error {d}\n", .{vm.ci_vm_last_error_code(machine)});
        }
        return 1;
    }

    var timer: ?std.time.Timer = std.time.Timer.start() catch null;
    if (trace) {
        trace_machine = machine;
        trace_timer = timer;
        installTraceAtExit();
    }
    const run_status = vm.ci_vm_run_args(machine, "main", @intCast(argc), argv_buf[0..argc].ptr);
    const elapsed_ns: ?u64 = if (timer) |*t| t.read() else null;
    if (run_status != 0) {
        if (comptime debug_errors) {
            std.debug.print("cinterp-run: run failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        } else {
            std.debug.print("cinterp-run: run failed: error {d}\n", .{vm.ci_vm_last_error_code(machine)});
        }
    }
    if (trace) {
        trace_machine = null;
        machine.dumpTrace(std.io.getStdErr().writer(), elapsed_ns) catch {};
    }
    if (run_status != 0) return 1;

    std.debug.print("result: {d}\n", .{@as(i32, @truncate(vm.ci_vm_result(machine)))});
    // Keep the VM alive: a CIB may have registered a libc atexit handler that
    // still has to run against this VM at process exit.
    return 0;
}
