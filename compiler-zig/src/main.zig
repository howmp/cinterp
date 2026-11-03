const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const lower_ast = @import("lower_ast.zig");
const ir = @import("ir/parser.zig");
const verify = @import("ir/verify.zig");
const imports = @import("imports.zig");
const libc_defs = @import("libc_defs.zig");
const link_wrappers = @import("link_wrappers.zig");
const win_defs = @import("win_defs.zig");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;

const Target = struct {
    name: []const u8,
    triple: []const u8,
    zig_triple: []const u8,
    arch: u8,
    os: u8,
    abi: u8,
    ptr_bits: u8,
    features: u64,
    link_db: []const u8 = "",
};

const targets = [_]Target{
    .{ .name = "x86_64-linux", .triple = "x86_64-pc-linux-gnu", .zig_triple = "x86_64-linux-gnu", .arch = 1, .os = 1, .abi = 1, .ptr_bits = 64, .features = 61 },
    .{ .name = "x86_64-windows", .triple = "x86_64-pc-windows-gnu", .zig_triple = "x86_64-windows-gnu", .arch = 1, .os = 2, .abi = 2, .ptr_bits = 64, .features = 61 },
    .{ .name = "i686-windows", .triple = "i686-pc-windows-gnu", .zig_triple = "x86-windows-gnu", .arch = 2, .os = 2, .abi = 3, .ptr_bits = 32, .features = 61 },
    .{ .name = "aarch64-linux", .triple = "aarch64-linux-gnu", .zig_triple = "aarch64-linux-gnu", .arch = 3, .os = 1, .abi = 4, .ptr_bits = 64, .features = 62 },
};

fn findTarget(name: []const u8) ?Target {
    for (targets) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}

const Options = struct {
    source: []const u8,
    output: []const u8,
    target: Target,
    cc_path: []const u8 = "zig",
    keep_ir: bool = false,
    dump: bool = false,
    dump_ast: bool = false,
    dump_imports: bool = false,
    cib_version: u8 = 2,
    auto_link: bool = true,
};

fn writeU16(list: *std.ArrayList(u8), v: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, v, .little);
    try list.appendSlice(&buf);
}

fn writeU32(list: *std.ArrayList(u8), v: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, v, .little);
    try list.appendSlice(&buf);
}

fn writeU64(list: *std.ArrayList(u8), v: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, v, .little);
    try list.appendSlice(&buf);
}

fn archMask(arch: u8) u8 {
    return switch (arch) {
        1 => 1,
        2 => 2,
        3 => 4,
        else => 0,
    };
}

fn targetSerialize(allocator: Allocator, target: Target) ![]u8 {
    const producer = try std.fmt.allocPrint(allocator, "cinterp {s}", .{build_options.version});
    const link_db = target.link_db;
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPM");
    try out.append(1);
    try writeU16(&out, 29);
    try out.append(target.arch);
    try out.append(target.os);
    try out.append(target.abi);
    try out.append(target.ptr_bits);
    try out.append(1);
    try out.append(0);
    try writeU64(&out, target.features);
    try writeU16(&out, 1);
    try writeU16(&out, @intCast(target.triple.len));
    try writeU16(&out, @intCast(link_db.len));
    try writeU16(&out, @intCast(producer.len));
    try out.appendSlice(target.triple);
    try out.appendSlice(link_db);
    try out.appendSlice(producer);
    return out.toOwnedSlice();
}

fn serializePlans(allocator: Allocator, plans: []const abi.Plan, abi_id: u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPL");
    try out.append(3);
    try out.append(abi_id);
    try writeU16(&out, @intCast(plans.len));
    try writeU16(&out, 0);
    for (plans) |plan| {
        try out.append(@intCast(plan.name.len));
        try out.appendSlice(plan.name);
        try writeU16(&out, @intCast(plan.args.len));
        try writeU16(&out, @intCast(plan.ret_locs.len));
        try writeU16(&out, plan.stack_size);
        try out.append(if (plan.sret) 1 else 0);
        try out.append(plan.sse_count);
        try out.append(plan.conv);
        try writeU16(&out, plan.ret_size);
        for (plan.args) |arg| {
            try out.append(@intCast(arg.locs.len));
            try writeU16(&out, arg.size);
            try writeU16(&out, arg.alignment);
            try out.append(if (arg.is_struct) 1 else 0);
            try out.append(0);
            for (arg.locs) |loc| {
                try out.append(loc.kind);
                try writeU16(&out, loc.index);
                try writeU16(&out, loc.size);
                try writeU16(&out, loc.offset);
            }
        }
        for (plan.ret_locs) |loc| {
            try out.append(loc.kind);
            try writeU16(&out, loc.index);
            try writeU16(&out, loc.size);
            try writeU16(&out, loc.offset);
        }
    }
    return out.toOwnedSlice();
}

fn convertProviders(allocator: Allocator, providers: anytype) ![]imports.Provider {
    const out = try allocator.alloc(imports.Provider, providers.len);
    for (providers, 0..) |provider, index| {
        out[index] = .{ .lib = provider.lib, .symbol = provider.symbol };
    }
    return out;
}

fn fallbackWindowsProviders(allocator: Allocator, name: []const u8) ![]imports.Provider {
    const out = try allocator.alloc(imports.Provider, 2);
    out[0] = .{ .lib = "ucrtbase.dll", .symbol = name };
    out[1] = .{ .lib = "msvcrt.dll", .symbol = name };
    return out;
}

/// Build the CIPI table for a package.
///
/// Function plans are resolved through the build-time Zig indexes:
///   * Windows: MinGW `.def` data (`win_defs`) → DLL + Win32 call convention.
///   * Linux: glibc `abilists` (`libc_defs`) → libc/libm/pthread/... provider.
/// Plans with no index entry are left out of CIPI on purpose: the runtime's
/// process/`--lib`/default-CRT fallback resolves them, which is what keeps
/// UCRT `printf` and unknown custom libraries working.
fn buildImportTable(
    allocator: Allocator,
    plans: []const abi.Plan,
    external_data: []const []const u8,
    target: Target,
    auto_link: bool,
) !imports.Table {
    var table = imports.Table.init(allocator);
    errdefer table.deinit();

    var plan_names = std.StringHashMap(void).init(allocator);
    defer plan_names.deinit();
    var function_plan_count: usize = 0;
    for (plans) |plan| {
        if (std.mem.startsWith(u8, plan.name, "callback:")) continue;
        function_plan_count += 1;
        try plan_names.put(plan.name, {});
    }
    if (function_plan_count > std.math.maxInt(u16)) return error.TooManyImports;
    const max_data_entries = std.math.maxInt(u16) - function_plan_count;

    for (external_data) |raw_name| {
        // CIPI counts are u16. Compile-only stress inputs can declare more
        // symbols than the format can address; keep the lower indices (the
        // ones bytecode can reference) and drop the tail.
        if (table.entries.items.len >= max_data_entries) break;
        const name = if (raw_name.len > 0 and raw_name[0] == '@') raw_name[1..] else raw_name;
        // External-data indices are referenced directly by OP_ADDR_EXTERN.
        // Keep the table complete so those indices never shift. Windows
        // historically omits entries that are also function plans.
        if (target.os == 2 and plan_names.contains(name)) continue;
        var providers: []imports.Provider = undefined;
        if (target.os == 1) {
            const out = try allocator.alloc(imports.Provider, 2);
            out[0] = .{ .lib = "libc.so.6", .symbol = name };
            out[1] = .{ .lib = "libm.so.6", .symbol = name };
            providers = out;
        } else {
            providers = try fallbackWindowsProviders(allocator, name);
        }
        try table.add(.{
            .plan_index = 0xffff,
            .name = name,
            .kind = 1,
            .flags = 12,
            .arch_mask = archMask(target.arch),
            .providers = providers,
        });
    }

    if (auto_link) {
        for (plans, 0..) |plan, plan_index| {
            if (std.mem.startsWith(u8, plan.name, "callback:")) continue;
            var providers: ?[]imports.Provider = null;
            var call_conv = plan.conv;
            if (target.os == 2) {
                if (win_defs.lookup(target.arch, plan.name)) |resolved| {
                    providers = try convertProviders(allocator, resolved.slice());
                    call_conv = resolved.conv;
                }
            } else {
                if (libc_defs.lookup(target.arch, plan.name)) |resolved| {
                    providers = try convertProviders(allocator, resolved.slice());
                }
            }
            if (providers) |list| {
                if (list.len == 0) continue;
                try table.add(.{
                    .plan_index = @intCast(plan_index),
                    .name = plan.name,
                    .kind = 0,
                    // Windows providers may be missing on the host (e.g. a
                    // MinGW-only export); allow the runtime fallback.
                    .flags = if (target.os == 2) 11 | 4 else 11,
                    .call_conv = call_conv,
                    .arch_mask = archMask(target.arch),
                    .min_os = 0,
                    .providers = list,
                });
            }
        }
    }
    return table;
}

fn dumpImports(writer: anytype, table: *const imports.Table) !void {
    for (table.entries.items) |entry| {
        try writer.print("  import[plan {d}] {s}:", .{ entry.plan_index, entry.name });
        if (entry.providers.len == 0) {
            try writer.writeAll(" (unresolved)");
        } else {
            for (entry.providers, 0..) |provider, index| {
                if (index > 0) try writer.writeAll(",");
                try writer.print(" {s}:{s}", .{ provider.lib, provider.symbol });
            }
        }
        try writer.writeByte('\n');
    }
}

fn moduleSerialize(allocator: Allocator, functions: []const abi.Function) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIVM");
    try out.append(1);
    try out.append(1);
    try writeU16(&out, @intCast(functions.len));
    try writeU16(&out, 0);
    for (functions) |func| {
        if (func.name.len > 255) return error.NameTooLong;
        try out.append(@intCast(func.name.len));
        try out.appendSlice(func.name);
        try writeU16(&out, func.param_count);
        try writeU16(&out, func.local_count);
        try writeU32(&out, @intCast(func.code.items.len));
        try out.appendSlice(func.code.items);
    }
    return out.toOwnedSlice();
}

fn packageSerialize(
    allocator: Allocator,
    module: []const u8,
    plans: []const u8,
    meta: []const u8,
    import_bytes: []const u8,
    cib_version: u8,
) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPKG");
    if (cib_version == 1) {
        try out.append(1);
        try out.append(0);
        try writeU32(&out, @intCast(module.len));
        try writeU32(&out, @intCast(plans.len));
        try out.appendSlice(module);
        try out.appendSlice(plans);
        return out.toOwnedSlice();
    }
    var flags: u8 = 0x1;
    if (import_bytes.len > 0) flags |= 0x2;
    try out.append(2);
    try out.append(flags);
    try writeU16(&out, 25);
    try writeU32(&out, @intCast(module.len));
    try writeU32(&out, @intCast(plans.len));
    try writeU32(&out, @intCast(meta.len));
    try writeU32(&out, @intCast(import_bytes.len));
    try out.appendSlice(module);
    try out.appendSlice(plans);
    try out.appendSlice(meta);
    try out.appendSlice(import_bytes);
    return out.toOwnedSlice();
}

fn runZigCc(allocator: Allocator, opts: Options, ll_path: []const u8) !void {
    var argv = std.ArrayList([]const u8).init(allocator);
    try argv.append(opts.cc_path);
    try argv.append("cc");
    const native = opts.target.arch == 1 and opts.target.os == 1 and
        builtin.os.tag == .linux and builtin.cpu.arch == .x86_64;
    if (!native) {
        try argv.append(try std.fmt.allocPrint(allocator, "--target={s}", .{opts.target.zig_triple}));
    }
    try argv.appendSlice(&.{
        "-S",                "-emit-llvm",           "-O0",                              "-g0", "-fno-discard-value-names",
        "-fno-sanitize=all", "-fno-stack-protector", "-ffine-grained-bitfield-accesses",
    });
    if (opts.target.os == 2) {
        try argv.appendSlice(&.{ "-fms-extensions", "-fdeclspec" });
    }
    try argv.append(opts.source);
    try argv.append("-o");
    try argv.append(ll_path);
    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = argv.items });
    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("{s}", .{result.stderr});
                return error.CCompilerFailed;
            }
        },
        else => return error.CCompilerFailed,
    }
}

fn usage() void {
    std.debug.print("usage: cinterp-cc compile <source.c> [-o out.cib] [--target T] [--cc-path zig] [--keep-ir]\n" ++
        "                      [--dump] [--dump-ast] [--dump-imports]\n" ++
        "                      [--cib-version 1|2] [--no-auto-link]\n", .{});
}

/// Parse the IR text into the typed AST, verify target consistency and lower it.
fn lowerModule(allocator: Allocator, ir_text: []const u8, opts: Options) !abi.CompileResult {
    var p = ir.Parser.init(allocator, ir_text);
    const module = p.parse() catch {
        std.debug.print("{d}:{d}: error: {s} (found '{s}')\n", .{
            p.diagnostic.line, p.diagnostic.column, p.diagnostic.message, p.diagnostic.found,
        });
        return error.IrParseError;
    };
    if (opts.dump_ast) {
        lower_ast.dumpModule(std.io.getStdErr().writer(), &module) catch {};
    }
    verify.verify(&module, opts.target.arch, opts.target.os, opts.target.ptr_bits) catch |e| {
        std.debug.print("IR target verification failed: {s}\n", .{@errorName(e)});
        return error.IrTargetMismatch;
    };
    return lower_ast.compile(allocator, &module, opts.target.abi, opts.target.ptr_bits / 8);
}

fn parseCibVersion(value: []const u8) u8 {
    const version = std.fmt.parseInt(u8, value, 10) catch {
        std.debug.print("invalid --cib-version: {s}\n", .{value});
        std.process.exit(2);
    };
    if (version != 1 and version != 2) {
        std.debug.print("invalid --cib-version: {s} (expected 1 or 2)\n", .{value});
        std.process.exit(2);
    }
    return version;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    if (argv.len < 2) {
        usage();
        std.process.exit(2);
    }
    if (std.mem.eql(u8, argv[1], "--version")) {
        std.debug.print("cinterp-cc {s}\n", .{build_options.version});
        return;
    }
    if (!std.mem.eql(u8, argv[1], "compile")) {
        usage();
        std.process.exit(2);
    }

    var source: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var target: Target = findTarget("x86_64-linux").?;
    var cc_path: []const u8 = "zig";
    var keep_ir = false;
    var dump = false;
    var dump_ast = false;
    var dump_imports = false;
    var cib_version: u8 = 2;
    var auto_link = true;

    var i: usize = 2;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-o") or std.mem.eql(u8, a, "--output")) {
            i += 1;
            if (i >= argv.len) {
                usage();
                std.process.exit(2);
            }
            output = argv[i];
        } else if (std.mem.eql(u8, a, "--target")) {
            i += 1;
            if (i >= argv.len) {
                usage();
                std.process.exit(2);
            }
            target = findTarget(argv[i]) orelse {
                std.debug.print("unknown target: {s}\n", .{argv[i]});
                std.process.exit(2);
            };
        } else if (std.mem.eql(u8, a, "--cc-path")) {
            i += 1;
            if (i >= argv.len) {
                usage();
                std.process.exit(2);
            }
            cc_path = argv[i];
        } else if (std.mem.eql(u8, a, "--cc")) {
            i += 1;
            if (i >= argv.len) {
                usage();
                std.process.exit(2);
            }
            if (!std.mem.eql(u8, argv[i], "zig")) {
                std.debug.print("compiler-zig currently supports --cc zig only\n", .{});
                std.process.exit(2);
            }
        } else if (std.mem.eql(u8, a, "--keep-ir")) {
            keep_ir = true;
        } else if (std.mem.eql(u8, a, "--dump")) {
            dump = true;
        } else if (std.mem.eql(u8, a, "--dump-ast")) {
            dump_ast = true;
        } else if (std.mem.eql(u8, a, "--dump-imports")) {
            dump_imports = true;
        } else if (std.mem.eql(u8, a, "--cib-version")) {
            i += 1;
            if (i >= argv.len) {
                usage();
                std.process.exit(2);
            }
            cib_version = parseCibVersion(argv[i]);
        } else if (std.mem.startsWith(u8, a, "--cib-version=")) {
            cib_version = parseCibVersion(a["--cib-version=".len..]);
        } else if (std.mem.eql(u8, a, "--no-auto-link")) {
            auto_link = false;
        } else if (a.len > 0 and a[0] == '-') {
            usage();
            std.process.exit(2);
        } else {
            source = a;
        }
    }
    const src = source orelse {
        usage();
        std.process.exit(2);
    };
    const out = output orelse blk: {
        if (std.mem.lastIndexOfScalar(u8, src, '.')) |dot| {
            break :blk try std.fmt.allocPrint(allocator, "{s}.cib", .{src[0..dot]});
        }
        break :blk try std.fmt.allocPrint(allocator, "{s}.cib", .{src});
    };
    const ll_path = try std.fmt.allocPrint(allocator, "{s}.{x}.ll", .{ out, std.crypto.random.int(u64) });
    defer if (!keep_ir) std.fs.cwd().deleteFile(ll_path) catch {};

    try runZigCc(allocator, .{
        .source = src,
        .output = out,
        .target = target,
        .cc_path = cc_path,
        .keep_ir = keep_ir,
    }, ll_path);
    const ir_text = try std.fs.cwd().readFileAlloc(allocator, ll_path, 64 * 1024 * 1024);
    const result = try lowerModule(allocator, ir_text, .{
        .source = src,
        .output = out,
        .target = target,
        .cc_path = cc_path,
        .keep_ir = keep_ir,
        .dump = dump,
        .dump_ast = dump_ast,
        .dump_imports = dump_imports,
        .cib_version = cib_version,
        .auto_link = auto_link,
    });

    // `data/link_wrappers.json` aliases a handful of same-signature symbols
    // that headers/IR spell differently (Windows `snprintf -> _snprintf`).
    // `atexit -> __cxa_atexit` stays in lower_ast.zig because it adds args.
    var wrappers = try link_wrappers.Wrappers.init(allocator);
    defer wrappers.deinit();

    for (result.plans) |*plan| {
        if (wrappers.alias(target.os, plan.name)) |aliased| {
            plan.name = aliased;
        }
        if (target.os == 2) {
            if (win_defs.lookup(target.arch, plan.name)) |resolved| plan.conv = resolved.conv;
        }
    }

    var import_table = try buildImportTable(
        allocator,
        result.plans,
        result.external_data,
        target,
        auto_link,
    );
    defer import_table.deinit();

    if (auto_link and result.plans.len > 0) {
        // Diagnostic provenance of the build-time table; no checked-in link
        // snapshots are involved any more.
        target.link_db = if (target.os == 2) win_defs.source_id else libc_defs.source_id;
    }

    const module = try moduleSerialize(allocator, result.functions);
    const plans = try serializePlans(allocator, result.plans, target.abi);
    const meta = try targetSerialize(allocator, target);
    const import_bytes = try import_table.serialize(allocator);
    const package = try packageSerialize(allocator, module, plans, meta, import_bytes, cib_version);
    const file = try std.fs.cwd().createFile(out, .{});
    defer file.close();
    try file.writeAll(package);

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "{s}: {d}B module, {d}B plans, {d} functions, {d} external plans, target={s}, cib=v{d}, imports={d}, cc=zig\n",
        .{ out, module.len, plans.len, result.functions.len, result.plans.len, target.name, cib_version, import_table.count() },
    );
    if (dump) {
        for (result.functions) |func| {
            try stdout.print("  {s}: params={d} locals={d} code={d}\n", .{
                func.name, func.param_count, func.local_count, func.code.items.len,
            });
        }
        for (result.plans, 0..) |plan, index| {
            try stdout.print("  plan[{d}] {s}: args={d} ret={d} stack={d}\n", .{
                index, plan.name, plan.args.len, plan.ret_locs.len, plan.stack_size,
            });
        }
    }
    if (dump_imports) {
        try dumpImports(stdout, &import_table);
    }
}

test "target lookup" {
    try std.testing.expect(findTarget("x86_64-linux") != null);
    try std.testing.expect(findTarget("nope") == null);
}

test "package v1 uses the 15-byte legacy header" {
    const module = "CIVM";
    const plans = "CIPL";
    const package = try packageSerialize(std.testing.allocator, module, plans, "", "", 1);
    defer std.testing.allocator.free(package);
    try std.testing.expectEqualSlices(u8, "CIPKG", package[0..5]);
    try std.testing.expectEqual(@as(u8, 1), package[5]);
    try std.testing.expectEqual(@as(u8, 0), package[6]);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, package[7..11], .little));
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, package[11..15], .little));
    try std.testing.expectEqual(@as(usize, 23), package.len);
}

test "lowerModule parses and lowers IR through the AST frontend" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const text =
        \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
        \\target triple = "x86_64-unknown-linux-gnu"
        \\
        \\define i32 @main() {
        \\entry:
        \\  ret i32 42
        \\}
    ;
    const opts = Options{
        .source = "x.c",
        .output = "x.cib",
        .target = findTarget("x86_64-linux").?,
    };
    try std.testing.expect(!opts.dump_ast);
    const result = try lowerModule(allocator, text, opts);
    try std.testing.expectEqual(@as(usize, 1), result.functions.len);
    try std.testing.expectEqualStrings("main", result.functions[0].name);
    // The function body starts by materialising the constant and ends with a
    // (32-bit truncated) return.
    const op = @import("opcodes.zig");
    const code = result.functions[0].code.items;
    try std.testing.expectEqual(@as(u8, op.OP_LOAD_CONST_I64), code[0]);
    try std.testing.expectEqual(@as(i64, 42), std.mem.readInt(i64, code[1..9], .little));
    try std.testing.expectEqual(@as(u8, op.OP_RET), code[code.len - 1]);
}
