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

    const usage = "usage: cinterp-run [--lib path]... [--load-only] [--safe] [--dump-target] [--dump-imports] <package.cib> [entry] [-- arg...]\n";
    var load_only = false;
    var safe_mode = false;
    var dump_target = false;
    var dump_imports = false;
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--version")) {
            std.debug.print("cinterp-run 0.1.0\n", .{});
            return;
        }
        if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            std.debug.print("{s}", .{usage});
            return;
        }
        if (std.mem.eql(u8, args[i], "--load-only")) {
            load_only = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--safe")) {
            safe_mode = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--dump-target")) {
            dump_target = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--dump-imports")) {
            dump_imports = true;
            i += 1;
            continue;
        }
        if (!std.mem.eql(u8, args[i], "--lib")) break;
        i += 1;
        if (i >= args.len) {
            std.debug.print("{s}", .{usage});
            std.process.exit(2);
        }
        if (vm.ci_vm_load_library(machine, args[i].ptr) != 0) {
            std.debug.print("cinterp-run: load library failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
            std.process.exit(1);
        }
        i += 1;
    }
    if (i >= args.len) {
        std.debug.print("{s}", .{usage});
        std.process.exit(2);
    }

    const package_path = args[i];
    i += 1;
    var entry: [*:0]const u8 = "main";
    var cargs = std.ArrayList([]const u8).init(allocator);
    defer cargs.deinit();
    cargs.append(package_path) catch {
        std.debug.print("cinterp-run: out of memory\n", .{});
        std.process.exit(2);
    };
    if (i < args.len and std.mem.eql(u8, args[i], "--")) {
        i += 1;
        while (i < args.len) : (i += 1) cargs.append(args[i]) catch {
            std.debug.print("cinterp-run: out of memory\n", .{});
            std.process.exit(2);
        };
    } else if (i < args.len) {
        entry = args[i];
    }

    const package = std.fs.cwd().readFileAlloc(allocator, package_path, 16 * 1024 * 1024) catch |err| {
        std.debug.print("cinterp-run: cannot read {s}: {s}\n", .{ package_path, @errorName(err) });
        std.process.exit(2);
    };
    defer allocator.free(package);

    if (vm.ci_vm_load_package(machine, package.ptr, package.len) != 0) {
        std.debug.print("cinterp-run: load failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        std.process.exit(1);
    }

    if (dump_target) {
        if (machine.target) |t| {
            std.debug.print("target: {s} arch={d} os={d} abi={d} ptr={d} endian={d} features=0x{x} link_db={s}\n", .{
                t.triple[0..t.triple_len], t.arch, t.os, t.abi, t.ptr_bits, t.endian, t.features, t.link_db[0..t.link_db_len],
            });
        } else {
            std.debug.print("target: legacy-v1 (inferred)\n", .{});
        }
    }
    if (dump_imports) {
        var ii: usize = 0;
        while (ii < machine.imports.count) : (ii += 1) {
            const e = &machine.imports.entries[ii];
            std.debug.print("import[plan {d}] {s}:", .{ e.plan_index, e.name[0..e.name_len] });
            var pi: usize = 0;
            while (pi < e.provider_count) : (pi += 1) {
                const pr = &e.providers[pi];
                std.debug.print(" {s}:{s}", .{ pr.name[0..pr.name_len], pr.symbol[0..pr.symbol_len] });
            }
            std.debug.print("\n", .{});
        }
    }
    if (safe_mode) _ = vm.ci_vm_set_safe(machine, 1);
    if (load_only) return;

    const result = machine.runEntryArgs(std.mem.span(entry), cargs.items) catch |err| {
        machine.setError(@errorName(err));
        std.debug.print("cinterp-run: run failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
        std.process.exit(1);
    };
    machine.result = result;
    std.debug.print("result: {d}\n", .{@as(i32, @truncate(result))});
}
