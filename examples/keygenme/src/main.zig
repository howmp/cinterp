const std = @import("std");
const builtin = @import("builtin");
const vm = @import("vm");
const cib = @import("cib");

const debug_errors = builtin.mode == .Debug;
const max_args = 256;

fn initFpu() void {
    if (comptime builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64) {
        asm volatile ("fninit" ::: "memory");
    }
}

fn fail(comptime what: []const u8, machine: *vm.VM) u8 {
    if (comptime debug_errors) {
        std.debug.print("keygenme: {s} failed: {s}\n", .{ what, std.mem.span(vm.ci_vm_last_error(machine)) });
    } else {
        std.debug.print("keygenme: {s} failed: error {d}\n", .{ what, vm.ci_vm_last_error_code(machine) });
    }
    return 1;
}

pub fn main() u8 {
    initFpu();

    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch return 2;
    defer std.process.argsFree(allocator, args);

    if (args.len > max_args) {
        std.debug.print("keygenme: too many arguments\n", .{});
        return 2;
    }

    var argv: [max_args]?[*:0]const u8 = undefined;
    for (args, 0..) |arg, i| {
        argv[i] = arg.ptr;
    }

    const machine = vm.ci_vm_create(0) orelse {
        std.debug.print("keygenme: out of memory\n", .{});
        return 2;
    };
    defer vm.ci_vm_destroy(machine);

    if (vm.ci_vm_load_package(machine, cib.bytes.ptr, cib.bytes.len) != 0) {
        return fail("load", machine);
    }
    if (vm.ci_vm_run_args(machine, "main", @intCast(args.len), argv[0..args.len].ptr) != 0) {
        return fail("run", machine);
    }

    return @intCast(vm.ci_vm_result(machine) & 0xff);
}
