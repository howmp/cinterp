const std = @import("std");
const vm = @import("vm.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const machine = vm.ci_vm_create(0) orelse {
        std.debug.print("cinterp-run: out of memory\n", .{});
        std.process.exit(2);
    };
    defer vm.ci_vm_destroy(machine);

    var i: usize = 1;
    while (i < args.len and std.mem.eql(u8, args[i], "--lib")) {
        i += 1;
        if (i >= args.len) {
            std.debug.print("usage: cinterp-run [--lib path]... <package.cib> [entry]\n", .{});
            std.process.exit(2);
        }
        if (vm.ci_vm_load_library(machine, args[i].ptr) != 0) {
            std.debug.print("cinterp-run: load library failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
            std.process.exit(1);
        }
        i += 1;
    }
    if (i >= args.len) {
        std.debug.print("usage: cinterp-run [--lib path]... <package.cib> [entry]\n", .{});
        std.process.exit(2);
    }

    const package_path = args[i];
    i += 1;
    const entry: [*:0]const u8 = if (i < args.len) args[i].ptr else "main";

    const package = std.fs.cwd().readFileAlloc(allocator, package_path, 16 * 1024 * 1024) catch |err| {
        std.debug.print("cinterp-run: cannot read {s}: {s}\n", .{ package_path, @errorName(err) });
        std.process.exit(2);
    };
    defer allocator.free(package);

    if (vm.ci_vm_load_package(machine, package.ptr, package.len) != 0) {
        std.debug.print("cinterp-run: load failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        std.process.exit(1);
    }

    const result = vm.ci_vm_run(machine, entry);
    if (result == -1) {
        std.debug.print("cinterp-run: run failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        std.process.exit(1);
    }
    std.debug.print("result: {d}\n", .{result});
}
