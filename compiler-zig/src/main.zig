const std = @import("std");
const builtin = @import("builtin");
const lower = @import("lower.zig");
const lower_ast = @import("lower_ast.zig");
const ir = @import("ir/parser.zig");
const verify = @import("ir/verify.zig");
const winmd = @import("winmd.zig");

const Allocator = std.mem.Allocator;

/// Which LLVM IR frontend lowers the module.
///
/// * `ast` (default): parse once into the typed AST (`ir/parser.zig`), verify
///   target consistency, then lower from `lower_ast.zig`.
/// * `legacy`: the original text-based lowering in `lower.zig`, retained for
///   byte-level differential/rollback comparisons.
const IrParser = enum { legacy, ast };

const Target = struct {
    name: []const u8,
    triple: []const u8,
    zig_triple: []const u8,
    arch: u8,
    os: u8,
    abi: u8,
    ptr_bits: u8,
    features: u64,
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
    ir_parser: IrParser = .ast,
    dump_ast: bool = false,
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

fn targetSerialize(allocator: Allocator, target: Target) ![]u8 {
    const producer = "cinterp 0.1.0";
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
    try writeU16(&out, 0);
    try writeU16(&out, @intCast(producer.len));
    try out.appendSlice(target.triple);
    try out.appendSlice(producer);
    return out.toOwnedSlice();
}

fn serializePlans(allocator: Allocator, plans: []const lower.Plan, abi: u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPL");
    try out.append(3);
    try out.append(abi);
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

fn writeProvider(out: *std.ArrayList(u8), lib: []const u8, symbol: []const u8) !void {
    try out.append(1); // SONAME
    try out.append(@intCast(lib.len));
    try out.appendSlice(lib);
    try out.append(@intCast(symbol.len));
    try out.appendSlice(symbol);
    try writeU16(out, 0); // ordinal
    try out.append(0); // version
}

fn writeWindowsProviders(out: *std.ArrayList(u8), db: ?*winmd.Database, arch: u8, name: []const u8) !bool {
    const database = db orelse return false;
    const api = database.lookup(name, arch) orelse return false;
    try out.append(@intCast(api.providers.len));
    for (api.providers) |p| try writeProvider(out, p.dll, p.symbol);
    return true;
}

fn serializeImports(allocator: Allocator, plans: []const lower.Plan, external_data: []const []const u8, target: Target) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPI");
    try out.append(1);
    try out.append(0);
    var function_count: u16 = 0;
    for (plans) |plan| {
        if (!std.mem.startsWith(u8, plan.name, "callback:")) function_count += 1;
    }
    var plan_names = std.StringHashMap(void).init(allocator);
    defer plan_names.deinit();
    for (plans) |plan| {
        if (!std.mem.startsWith(u8, plan.name, "callback:")) try plan_names.put(plan.name, {});
    }
    var data_count: u16 = 0;
    for (external_data) |raw_name| {
        const name = if (raw_name.len > 0 and raw_name[0] == '@') raw_name[1..] else raw_name;
        if (target.os == 2 and plan_names.contains(name)) continue;
        if (data_count >= std.math.maxInt(u16) - function_count) break;
        data_count += 1;
    }
    try writeU16(&out, data_count + function_count);
    try writeU16(&out, 0);
    const linux = target.os == 1;
    var win_db: ?winmd.Database = null;
    if (!linux) win_db = try winmd.Database.init(allocator);
    defer if (win_db) |*db| db.deinit();
    var data_written: u16 = 0;
    for (external_data) |raw_name| {
        if (data_written >= data_count) break;
        const name = if (raw_name.len > 0 and raw_name[0] == '@') raw_name[1..] else raw_name;
        if (target.os == 2 and plan_names.contains(name)) continue;
        data_written += 1;
        try writeU16(&out, 0xffff);
        try out.append(1); // data
        try out.append(11); // required | lazy | allow_override
        try out.append(0);
        try out.append(0);
        try writeU16(&out, 0);
        try out.append(@intCast(name.len));
        try out.appendSlice(name);
        if (linux) {
            try out.append(2);
            try writeProvider(&out, "libc.so.6", name);
            try writeProvider(&out, "libm.so.6", name);
        } else if (!try writeWindowsProviders(&out, if (win_db) |*db| db else null, target.arch, name)) {
            try out.append(2);
            try writeProvider(&out, "ucrtbase.dll", name);
            try writeProvider(&out, "msvcrt.dll", name);
        }
    }
    for (plans, 0..) |plan, plan_index| {
        if (std.mem.startsWith(u8, plan.name, "callback:")) continue;
        try writeU16(&out, @intCast(plan_index));
        try out.append(0); // function
        try out.append(11);
        try out.append(plan.conv);
        try out.append(0);
        try writeU16(&out, 0);
        try out.append(@intCast(plan.name.len));
        try out.appendSlice(plan.name);
        if (linux) {
            try out.append(2);
            try writeProvider(&out, "libc.so.6", plan.name);
            try writeProvider(&out, "libm.so.6", plan.name);
        } else if (!try writeWindowsProviders(&out, if (win_db) |*db| db else null, target.arch, plan.name)) {
            try out.append(2);
            try writeProvider(&out, "ucrtbase.dll", plan.name);
            try writeProvider(&out, "msvcrt.dll", plan.name);
        }
    }
    return out.toOwnedSlice();
}

fn moduleSerialize(allocator: Allocator, functions: []const lower.Function) ![]u8 {
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

fn packageSerialize(allocator: Allocator, module: []const u8, plans: []const u8, meta: []const u8, imports: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPKG");
    try out.append(2);
    try out.append(0x3);
    try writeU16(&out, 25);
    try writeU32(&out, @intCast(module.len));
    try writeU32(&out, @intCast(plans.len));
    try writeU32(&out, @intCast(meta.len));
    try writeU32(&out, @intCast(imports.len));
    try out.appendSlice(module);
    try out.appendSlice(plans);
    try out.appendSlice(meta);
    try out.appendSlice(imports);
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
        "-S", "-emit-llvm", "-O0", "-g0", "-fno-discard-value-names",
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
    std.debug.print("usage: cinterp-cc compile <source.c> [-o out.cib] [--target T] [--cc-path zig] [--keep-ir] [--dump]\n" ++
        "                      [--ir-parser=legacy|ast] [--dump-ast]\n", .{});
}

fn parseIrParser(value: []const u8) ?IrParser {
    if (std.mem.eql(u8, value, "legacy")) return .legacy;
    if (std.mem.eql(u8, value, "ast")) return .ast;
    return null;
}

/// Lower the IR text with the selected frontend.
fn lowerModule(allocator: Allocator, ir_text: []const u8, opts: Options) !lower.CompileResult {
    switch (opts.ir_parser) {
        .legacy => return lower.compile(allocator, ir_text, opts.target.abi, opts.target.ptr_bits / 8),
        .ast => {
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
        },
    }
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
        std.debug.print("cinterp-cc 0.1.0\n", .{});
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
    var ir_parser: IrParser = .ast;
    var dump_ast = false;

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
        } else if (std.mem.eql(u8, a, "--ir-parser")) {
            i += 1;
            if (i >= argv.len) {
                usage();
                std.process.exit(2);
            }
            ir_parser = parseIrParser(argv[i]) orelse {
                std.debug.print("unknown IR frontend: {s} (expected legacy|ast)\n", .{argv[i]});
                std.process.exit(2);
            };
        } else if (std.mem.startsWith(u8, a, "--ir-parser=")) {
            ir_parser = parseIrParser(a["--ir-parser=".len..]) orelse {
                std.debug.print("unknown IR frontend: {s} (expected legacy|ast)\n", .{a["--ir-parser=".len..]});
                std.process.exit(2);
            };
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

    try runZigCc(allocator, .{ .source = src, .output = out, .target = target, .cc_path = cc_path, .keep_ir = keep_ir }, ll_path);
    const ir_text = try std.fs.cwd().readFileAlloc(allocator, ll_path, 64 * 1024 * 1024);
    const result = try lowerModule(allocator, ir_text, .{
        .source = src,
        .output = out,
        .target = target,
        .cc_path = cc_path,
        .keep_ir = keep_ir,
        .dump = dump,
        .ir_parser = ir_parser,
        .dump_ast = dump_ast,
    });
    if (target.os == 2) {
        var db = try winmd.Database.init(allocator);
        defer db.deinit();
        for (result.plans) |*plan| {
            if (db.lookup(plan.name, target.arch)) |api| plan.conv = api.conv;
        }
    }

    const module = try moduleSerialize(allocator, result.functions);
    const plans = try serializePlans(allocator, result.plans, target.abi);
    const meta = try targetSerialize(allocator, target);
    const imports = try serializeImports(allocator, result.plans, result.external_data, target);
    const package = try packageSerialize(allocator, module, plans, meta, imports);
    const file = try std.fs.cwd().createFile(out, .{});
    defer file.close();
    try file.writeAll(package);

    if (dump) {
        std.debug.print("{s}: {d}B module, {d}B plans, {d} functions, {d} plans, target={s}\n", .{
            out, module.len, plans.len, result.functions.len, result.plans.len, target.name,
        });
        for (result.functions) |func| {
            std.debug.print("  {s}: params={d} locals={d} code={d}\n", .{
                func.name, func.param_count, func.local_count, func.code.items.len,
            });
        }
    }
}

test "target lookup" {
    try std.testing.expect(findTarget("x86_64-linux") != null);
    try std.testing.expect(findTarget("nope") == null);
}

test "ir parser selection defaults to legacy" {
    const defaults = Options{
        .source = "x.c",
        .output = "x.cib",
        .target = findTarget("x86_64-linux").?,
    };
    try std.testing.expectEqual(IrParser.ast, defaults.ir_parser);
    try std.testing.expect(!defaults.dump_ast);
    try std.testing.expectEqual(IrParser.legacy, parseIrParser("legacy").?);
    try std.testing.expectEqual(IrParser.ast, parseIrParser("ast").?);
    try std.testing.expect(parseIrParser("") == null);
    try std.testing.expect(parseIrParser("AST") == null);
}
