const std = @import("std");
const vm = @import("vm.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("usage: cinterp-run <package.cib> [entry]\n", .{});
        std.process.exit(2);
    }

    const package = std.fs.cwd().readFileAlloc(allocator, args[1], 16 * 1024 * 1024) catch |err| {
        std.debug.print("cinterp-run: cannot read {s}: {s}\n", .{ args[1], @errorName(err) });
        std.process.exit(2);
    };
    defer allocator.free(package);

    const machine = vm.ci_vm_create(0) orelse {
        std.debug.print("cinterp-run: out of memory\n", .{});
        std.process.exit(2);
    };
    defer vm.ci_vm_destroy(machine);

    if (vm.ci_vm_load_package(machine, package.ptr, package.len) != 0) {
        std.debug.print("cinterp-run: load failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        std.process.exit(1);
    }

    const entry: [*:0]const u8 = if (args.len > 2) args[2] else "main";
    const result = vm.ci_vm_run(machine, entry);
    if (result == -1) {
        std.debug.print("cinterp-run: run failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        std.process.exit(1);
    }
    std.debug.print("result: {d}\n", .{result});
}
