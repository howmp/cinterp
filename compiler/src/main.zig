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

/// Upper bounds the runtime loaders enforce. The compiler cannot import
/// `runtime/`, so these mirror the constants there:
///   * `runtime/src/vm.zig`             MAX_FUNCS=512, MAX_NAME=128, MAX_MODULE=2 MiB
///   * `runtime/src/ffi/plan_loader.zig` MAX_PLANS=1024, MAX_ARGS=64, MAX_LOCS=8, MAX_NAME=128
///   * `runtime/src/ffi/link_loader.zig` MAX_IMPORTS=512, MAX_PROVIDERS=8,
///                                        MAX_IMPORT_NAME/MAX_PROVIDER_NAME/MAX_SYMBOL=64,
///                                        MAX_VERSION=32
/// A package that exceeds one of them is rejected (or silently truncated) by
/// the loader, so `validateLimits` fails it at compile time with a
/// `compiler limit: ...` message instead.
pub const Limits = struct {
    pub const functions: usize = 512;
    pub const plans: usize = 1024;
    pub const args_per_plan: usize = 64;
    pub const locs_per_plan: usize = 8;
    pub const name: usize = 128;
    pub const imports: usize = 512;
    pub const providers_per_import: usize = 8;
    pub const import_name: usize = 64;
    pub const provider_name: usize = 64;
    pub const provider_symbol: usize = 64;
    pub const provider_version: usize = 32;
    pub const module_bytes: usize = 2 * 1024 * 1024;
};

pub const LimitError = error{
    TooManyFunctions,
    TooManyPlans,
    TooManyArgs,
    TooManyLocs,
    FunctionNameTooLong,
    PlanNameTooLong,
    FunctionCodeTooLarge,
    ModuleTooLarge,
    TooManyImports,
    ImportNameTooLong,
    TooManyProviders,
    ProviderNameTooLong,
    ProviderSymbolTooLong,
    ProviderVersionTooLong,
};

fn limitMessage(err: LimitError) []const u8 {
    return switch (err) {
        error.TooManyFunctions => "more than 512 functions in the CIVM module",
        error.TooManyPlans => "more than 1024 call plans in the CIPL table",
        error.TooManyArgs => "more than 64 arguments in one call plan",
        error.TooManyLocs => "more than 8 locations for one argument or return",
        error.FunctionNameTooLong => "function name longer than 128 bytes",
        error.PlanNameTooLong => "call plan name longer than 128 bytes",
        error.FunctionCodeTooLarge => "function bytecode larger than 4 GiB",
        error.ModuleTooLarge => "CIVM module larger than 2 MiB",
        error.TooManyImports => "more than 512 entries in the CIPI import table",
        error.ImportNameTooLong => "import name longer than 64 bytes",
        error.TooManyProviders => "more than 8 providers for one import",
        error.ProviderNameTooLong => "provider library name longer than 64 bytes",
        error.ProviderSymbolTooLong => "provider symbol longer than 64 bytes",
        error.ProviderVersionTooLong => "provider version string longer than 32 bytes",
    };
}

/// Exact CIVM length `moduleSerialize` will produce, without building it.
/// Header: magic(4) + version(1) + flags(1) + count(2) + reserved(2) = 10.
fn moduleByteLen(functions: []const abi.Function) usize {
    var total: usize = 10;
    for (functions) |func| {
        total += 1 + func.name.len + 2 + 2 + 4 + func.code.items.len;
    }
    return total;
}

/// Check every record against the runtime caps before anything is serialized.
/// `module_bytes` is `moduleByteLen(result.functions)`; keeping it a parameter
/// lets the oversized-module path be unit-tested without allocating 2 MiB.
pub fn validateLimits(result: abi.CompileResult, module_bytes: usize, table: *const imports.Table) LimitError!void {
    if (result.functions.len > Limits.functions) return error.TooManyFunctions;
    if (result.plans.len > Limits.plans) return error.TooManyPlans;

    for (result.functions) |func| {
        if (func.name.len > Limits.name) return error.FunctionNameTooLong;
        // moduleSerialize stores the CIVM code length as u32.
        if (func.code.items.len > std.math.maxInt(u32)) return error.FunctionCodeTooLarge;
    }

    for (result.plans) |plan| {
        if (plan.name.len > Limits.name) return error.PlanNameTooLong;
        if (plan.args.len > Limits.args_per_plan) return error.TooManyArgs;
        if (plan.ret_locs.len > Limits.locs_per_plan) return error.TooManyLocs;
        for (plan.args) |arg| {
            if (arg.locs.len > Limits.locs_per_plan) return error.TooManyLocs;
        }
    }

    if (module_bytes > Limits.module_bytes) return error.ModuleTooLarge;

    if (table.entries.items.len > Limits.imports) return error.TooManyImports;
    for (table.entries.items) |entry| {
        if (entry.name.len > Limits.import_name) return error.ImportNameTooLong;
        if (entry.providers.len > Limits.providers_per_import) return error.TooManyProviders;
        for (entry.providers) |provider| {
            if (provider.lib.len > Limits.provider_name) return error.ProviderNameTooLong;
            if (provider.symbol.len > Limits.provider_symbol) return error.ProviderSymbolTooLong;
            if (provider.version.len > Limits.provider_version) return error.ProviderVersionTooLong;
        }
    }
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
    // CIPM stores the lengths as u16 and the runtime copies into fixed
    // 96/128/64-byte fields, so reject before narrowing.
    if (target.triple.len > 96 or link_db.len > 128 or producer.len > 64) return error.NameTooLong;
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
    // CIPL counts are u16 and each length is u8; `validateLimits` already
    // enforces the runtime caps, these checks keep the serializer safe on its
    // own (e.g. when called directly from a test).
    if (plans.len > std.math.maxInt(u16)) return error.TooManyPlans;
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPL");
    try out.append(3);
    try out.append(abi_id);
    try writeU16(&out, @intCast(plans.len));
    try writeU16(&out, 0);
    for (plans) |plan| {
        if (plan.name.len > std.math.maxInt(u8)) return error.NameTooLong;
        if (plan.args.len > std.math.maxInt(u16) or plan.ret_locs.len > std.math.maxInt(u16)) return error.TooManyLocs;
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
            if (arg.locs.len > std.math.maxInt(u8)) return error.TooManyLocs;
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
    if (functions.len > std.math.maxInt(u16)) return error.TooManyFunctions;
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIVM");
    try out.append(1);
    try out.append(1);
    try writeU16(&out, @intCast(functions.len));
    try writeU16(&out, 0);
    for (functions) |func| {
        if (func.name.len > std.math.maxInt(u8)) return error.NameTooLong;
        if (func.code.items.len > std.math.maxInt(u32)) return error.FunctionCodeTooLarge;
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
    // CIPKG lengths are u32; every section is bounded by validateLimits, but
    // guard the narrowing casts locally as well.
    if (module.len > std.math.maxInt(u32) or plans.len > std.math.maxInt(u32) or
        meta.len > std.math.maxInt(u32) or import_bytes.len > std.math.maxInt(u32)) return error.PackageTooLarge;
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
                std.debug.print("compiler currently supports --cc zig only\n", .{});
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

    // Fail before writing a package the runtime loaders would reject or
    // truncate. `moduleByteLen` is the exact CIVM size; `serializePlans` and
    // friends re-check their own narrowing casts.
    const module_bytes = moduleByteLen(result.functions);
    validateLimits(result, module_bytes, &import_table) catch |err| {
        std.debug.print("compiler limit: {s}\n", .{limitMessage(err)});
        return err;
    };

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
            try stdout.print("  plan[{d}] {s}: args={d} ret={d} stack={d} conv={d}\n", .{
                index, plan.name, plan.args.len, plan.ret_locs.len, plan.stack_size, plan.conv,
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

// ---------------------------------------------------------------- limits tests

fn sampleFunction(name: []const u8) abi.Function {
    return .{
        .name = name,
        .ret = "i32",
        .param_count = 0,
        .param_names = &.{},
        .param_types = &.{},
        .param_attrs = &.{},
        .local_count = 0,
        .code = std.ArrayList(u8).init(std.testing.allocator),
    };
}

fn emptyResult() abi.CompileResult {
    return .{ .functions = &.{}, .plans = &.{}, .external_data = &.{} };
}

test "moduleByteLen matches moduleSerialize and a small package validates" {
    var table = imports.Table.init(std.testing.allocator);
    defer table.deinit();

    var funcs = [_]abi.Function{sampleFunction("main")};
    defer funcs[0].code.deinit();
    const result = abi.CompileResult{ .functions = &funcs, .plans = &.{}, .external_data = &.{} };

    // 10-byte CIVM header + u8 len + "main" + 2+2 counts + u32 code len.
    const expected = moduleByteLen(result.functions);
    try std.testing.expectEqual(@as(usize, 23), expected);
    const bytes = try moduleSerialize(std.testing.allocator, result.functions);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(expected, bytes.len);

    try validateLimits(result, expected, &table);
}

test "validateLimits rejects over-long function and plan names" {
    var table = imports.Table.init(std.testing.allocator);
    defer table.deinit();

    var funcs = [_]abi.Function{sampleFunction("f" ** (Limits.name + 1))};
    defer funcs[0].code.deinit();
    var result = abi.CompileResult{ .functions = &funcs, .plans = &.{}, .external_data = &.{} };
    try std.testing.expectError(error.FunctionNameTooLong, validateLimits(result, 10, &table));

    // 128 bytes is still accepted (runtime MAX_NAME == 128).
    funcs[0].name = "f" ** Limits.name;
    result.functions = &funcs;
    try validateLimits(result, 10, &table);

    const long_plan = "p" ** (Limits.name + 1);
    var plans = [_]abi.Plan{.{ .name = long_plan, .args = &.{}, .ret_locs = &.{} }};
    result = .{ .functions = &.{}, .plans = &plans, .external_data = &.{} };
    try std.testing.expectError(error.PlanNameTooLong, validateLimits(result, 10, &table));
}

test "validateLimits rejects more than 64 plan arguments" {
    var table = imports.Table.init(std.testing.allocator);
    defer table.deinit();

    var locs = [_]abi.Loc{.{ .kind = 0, .index = 0, .size = 8, .offset = 0 }};
    var args: [Limits.args_per_plan + 1]abi.ArgPlan = undefined;
    for (&args) |*arg| arg.* = .{ .locs = &locs, .size = 8 };

    var plans = [_]abi.Plan{.{ .name = "printf", .args = &args, .ret_locs = &.{} }};
    const result = abi.CompileResult{ .functions = &.{}, .plans = &plans, .external_data = &.{} };
    try std.testing.expectError(error.TooManyArgs, validateLimits(result, 10, &table));

    // 64 arguments are still accepted.
    plans[0].args = args[0..Limits.args_per_plan];
    try validateLimits(result, 10, &table);
}

test "validateLimits rejects more than 8 argument/return locations" {
    var table = imports.Table.init(std.testing.allocator);
    defer table.deinit();

    var nine_locs = [_]abi.Loc{.{ .kind = 0, .index = 0, .size = 1, .offset = 0 }} ** (Limits.locs_per_plan + 1);
    var one_arg = [_]abi.ArgPlan{.{ .locs = &nine_locs, .size = 9 }};
    var plans = [_]abi.Plan{.{ .name = "wide", .args = &one_arg, .ret_locs = &.{} }};
    var result = abi.CompileResult{ .functions = &.{}, .plans = &plans, .external_data = &.{} };
    try std.testing.expectError(error.TooManyLocs, validateLimits(result, 10, &table));

    var ret_plan = [_]abi.Plan{.{ .name = "wide_ret", .args = &.{}, .ret_locs = &nine_locs }};
    result = .{ .functions = &.{}, .plans = &ret_plan, .external_data = &.{} };
    try std.testing.expectError(error.TooManyLocs, validateLimits(result, 10, &table));
}

test "validateLimits rejects function/plan counts and oversized modules" {
    var table = imports.Table.init(std.testing.allocator);
    defer table.deinit();

    var many_funcs: [Limits.functions + 1]abi.Function = undefined;
    for (&many_funcs) |*func| func.* = sampleFunction("f");
    defer for (&many_funcs) |*func| func.code.deinit();
    var result = abi.CompileResult{ .functions = &many_funcs, .plans = &.{}, .external_data = &.{} };
    try std.testing.expectError(error.TooManyFunctions, validateLimits(result, 10, &table));

    var many_plans: [Limits.plans + 1]abi.Plan = undefined;
    for (&many_plans) |*plan| plan.* = .{ .name = "f", .args = &.{}, .ret_locs = &.{} };
    result = .{ .functions = &.{}, .plans = &many_plans, .external_data = &.{} };
    try std.testing.expectError(error.TooManyPlans, validateLimits(result, 10, &table));

    try std.testing.expectError(error.ModuleTooLarge, validateLimits(emptyResult(), Limits.module_bytes + 1, &table));
    try validateLimits(emptyResult(), Limits.module_bytes, &table);
}

test "validateLimits enforces CIPI import caps" {
    const no_providers: [0]imports.Provider = .{};
    const empty = emptyResult();

    var table = imports.Table.init(std.testing.allocator);
    defer table.deinit();
    var i: usize = 0;
    while (i <= Limits.imports) : (i += 1) {
        try table.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&no_providers) });
    }
    try std.testing.expectError(error.TooManyImports, validateLimits(empty, 10, &table));

    var long_name = imports.Table.init(std.testing.allocator);
    defer long_name.deinit();
    try long_name.add(.{ .plan_index = 0, .name = "i" ** (Limits.import_name + 1), .providers = @constCast(&no_providers) });
    try std.testing.expectError(error.ImportNameTooLong, validateLimits(empty, 10, &long_name));

    var many_providers = imports.Table.init(std.testing.allocator);
    defer many_providers.deinit();
    const nine = [_]imports.Provider{.{ .lib = "libc.so.6", .symbol = "puts" }} ** (Limits.providers_per_import + 1);
    try many_providers.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&nine) });
    try std.testing.expectError(error.TooManyProviders, validateLimits(empty, 10, &many_providers));

    var long_lib = imports.Table.init(std.testing.allocator);
    defer long_lib.deinit();
    const bad_lib = [_]imports.Provider{.{ .lib = "l" ** (Limits.provider_name + 1), .symbol = "puts" }};
    try long_lib.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&bad_lib) });
    try std.testing.expectError(error.ProviderNameTooLong, validateLimits(empty, 10, &long_lib));

    var long_symbol = imports.Table.init(std.testing.allocator);
    defer long_symbol.deinit();
    const bad_symbol = [_]imports.Provider{.{ .lib = "libc.so.6", .symbol = "s" ** (Limits.provider_symbol + 1) }};
    try long_symbol.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&bad_symbol) });
    try std.testing.expectError(error.ProviderSymbolTooLong, validateLimits(empty, 10, &long_symbol));

    var long_version = imports.Table.init(std.testing.allocator);
    defer long_version.deinit();
    const bad_version = [_]imports.Provider{.{ .lib = "libc.so.6", .symbol = "puts", .version = "v" ** (Limits.provider_version + 1) }};
    try long_version.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&bad_version) });
    try std.testing.expectError(error.ProviderVersionTooLong, validateLimits(empty, 10, &long_version));
}
