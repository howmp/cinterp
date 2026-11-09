const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const lower_ast = @import("lower_ast.zig");
const ir = @import("ir/parser.zig");
const verify = @import("ir/verify.zig");
const imports = @import("imports.zig");
const cipc = @import("cipc.zig");
const libc_defs = @import("libc_defs.zig");
const link_wrappers = @import("link_wrappers.zig");
const win_defs = @import("win_defs.zig");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;

/// Callback API header force-included into every CIB compilation. It is
/// embedded in the compiler binary, written next to the temporary IR file and
/// passed to `zig cc -include`, so CIB sources can call
/// `ci_callback_acquire`/`ci_callback_release` without an `#include` and
/// without an include path (and the tarball needs no extra installed header).
const callbacks_header = @embedFile("data/cinterp_callbacks.h");

const Target = struct {
    name: []const u8,
    zig_triple: []const u8,
    arch: u8,
    os: u8,
    abi: u8,
    ptr_bits: u8,
};

const targets = [_]Target{
    .{ .name = "x86_64-linux", .zig_triple = "x86_64-linux-gnu", .arch = 1, .os = 1, .abi = 1, .ptr_bits = 64 },
    .{ .name = "x86_64-windows", .zig_triple = "x86_64-windows-gnu", .arch = 1, .os = 2, .abi = 2, .ptr_bits = 64 },
    .{ .name = "i686-windows", .zig_triple = "x86-windows-gnu", .arch = 2, .os = 2, .abi = 3, .ptr_bits = 32 },
    .{ .name = "aarch64-linux", .zig_triple = "aarch64-linux-gnu", .arch = 3, .os = 1, .abi = 4, .ptr_bits = 64 },
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
    pub const vm_stack_slots: usize = 8192;
    pub const vm_memory: usize = 16 * 1024 * 1024;
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
    StackTooDeep,
    VmMemoryTooLarge,
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
        error.StackTooDeep => "function local_count exceeds the VM stack limit (8192 slots)",
        error.VmMemoryTooLarge => "static data exceeds the VM maximum linear memory (16 MiB)",
    };
}

/// Exact CIVM length `moduleSerialize` will produce, without building it.
/// Header: magic(4) + version(1) + flags(1) + count(2) + reserved(2) = 10.
fn moduleByteLen(functions: []const abi.Function) usize {
    var total: usize = 10;
    for (functions) |func| {
        total += 2 + 2 + 4 + func.code.items.len;
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
        if (func.local_count > Limits.vm_stack_slots) return error.StackTooDeep;
        // moduleSerialize stores the CIVM code length as u32.
        if (func.code.items.len > std.math.maxInt(u32)) return error.FunctionCodeTooLarge;
    }
    const data_end = @as(u64, result.data_base) + result.const_data.len;
    if (data_end > Limits.vm_memory) return error.VmMemoryTooLarge;

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

fn serializePlans(allocator: Allocator, plans: []const abi.Plan, abi_id: u8, names: *cipc.NamePool) ![]u8 {
    if (plans.len == 0) return allocator.alloc(u8, 0);
    if (plans.len > std.math.maxInt(u16)) return error.TooManyPlans;
    var out = std.ArrayList(u8).init(allocator);
    try out.append(abi_id);
    try writeU16(&out, @intCast(plans.len));
    for (plans) |plan| {
        if (plan.name.len > Limits.name) return error.NameTooLong;
        if (plan.args.len > std.math.maxInt(u8) or plan.ret_locs.len > std.math.maxInt(u8)) return error.TooManyLocs;
        if (plan.sse_count > 15 or plan.conv > 3) return error.TooManyLocs;
        try writeU16(&out, try names.ref(plan.name));
        try out.append(@intCast(plan.args.len));
        try out.append(@intCast(plan.ret_locs.len));
        try writeU16(&out, plan.stack_size);
        try out.append((if (plan.sret) @as(u8, 1) else 0) |
            (@as(u8, plan.sse_count) << 1) |
            (@as(u8, plan.conv) << 5));
        try writeU16(&out, plan.ret_size);
        for (plan.args) |arg| {
            if (arg.locs.len > 7) return error.TooManyLocs;
            try out.append(@as(u8, @intCast(arg.locs.len)) | (if (arg.is_struct) @as(u8, 0x80) else 0));
            try writeU16(&out, arg.size);
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
        // `lower_ast` already lowers the forced-include callback builtins to
        // opcodes; keep them out of CIPI even if a hand-written module or a
        // future frontend leaves them in the plan table.
        if (lower_ast.isCallbackBuiltin(plan.name)) continue;
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
        if (lower_ast.isCallbackBuiltin(name)) continue;
        // External-data indices are referenced directly by OP_ADDR_EXTERN.
        // Keep the table complete so those indices never shift. Windows
        // historically omits entries that are also function plans.
        if (target.os == 2 and plan_names.contains(name)) continue;
        var providers: []imports.Provider = undefined;
        if (target.os == 1) {
            // Linux data symbols are resolved by loadImportedData's fallback
            // through the process, --lib handles, and the default CRT
            // libraries. Do not repeat that library list in every entry.
            providers = &.{};
        } else if (win_defs.lookupData(target.arch, name)) |resolved| {
            providers = try convertProviders(allocator, resolved.slice());
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
            if (lower_ast.isCallbackBuiltin(plan.name)) continue;
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
    var entry_index: u16 = 0xFFFF;
    for (functions, 0..) |func, index| {
        if (std.mem.eql(u8, func.name, "main")) {
            entry_index = @intCast(index);
            break;
        }
    }
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIVM");
    try out.append(2);
    try out.append(1);
    try writeU16(&out, @intCast(functions.len));
    try writeU16(&out, entry_index);
    for (functions) |func| {
        if (func.code.items.len > std.math.maxInt(u32)) return error.FunctionCodeTooLarge;
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
    import_bytes: []const u8,
    const_bytes: []const u8,
) ![]u8 {
    // CIPKG lengths are u32; every section is bounded by validateLimits, but
    // guard the narrowing casts locally as well.
    if (module.len > std.math.maxInt(u32) or plans.len > std.math.maxInt(u32) or
        import_bytes.len > std.math.maxInt(u32) or const_bytes.len > std.math.maxInt(u32))
        return error.PackageTooLarge;
    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice("CIPKG");
    try out.append(4);
    try writeU32(&out, @intCast(module.len));
    try writeU32(&out, @intCast(plans.len));
    try writeU32(&out, @intCast(import_bytes.len));
    try writeU32(&out, @intCast(const_bytes.len));
    try out.appendSlice(module);
    try out.appendSlice(plans);
    try out.appendSlice(import_bytes);
    try out.appendSlice(const_bytes);
    return out.toOwnedSlice();
}

fn runZigCc(allocator: Allocator, opts: Options, ll_path: []const u8, callbacks_header_path: []const u8) !void {
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
    // `-include` comes before the source so the callback builtins are declared
    // ahead of user code, exactly like a top-of-file `#include`. Arguments go
    // through argv (no shell), and `std.process.Child` applies the Windows
    // `CommandLineToArgvW` quoting rules itself, so paths with spaces must not
    // be quoted by hand.
    try argv.appendSlice(&.{ "-include", callbacks_header_path });
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
        "                      [--dump] [--dump-ast] [--dump-imports] [--no-auto-link]\n", .{});
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
    return lower_ast.compileWithOptions(allocator, &module, opts.target.abi, opts.target.ptr_bits / 8, .{
        // The legacy mode exists only to keep lowering goldens comparable;
        // real C input needs every GEP index folded into the relocation addend.
        .gep_const = .correct,
        .legacy_codegen = false,
    });
}

/// Remove the per-compile temporary IR file and force-included header unless
/// `--keep-ir` asked to keep them. Called from a `defer` and again on the
/// early-exit diagnostics path, where `std.process.exit` skips defers.
fn removeTempFiles(ll_path: []const u8, callbacks_header_path: []const u8, keep_ir: bool) void {
    if (keep_ir) return;
    std.fs.cwd().deleteFile(ll_path) catch {};
    std.fs.cwd().deleteFile(callbacks_header_path) catch {};
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
    const nonce = std.crypto.random.int(u64);
    const ll_path = try std.fmt.allocPrint(allocator, "{s}.{x}.ll", .{ out, nonce });
    // The forced-include header shares the temporary IR file's directory and
    // nonce, so it is unique per compile, never collides with a user file and
    // is removed together with the IR unless `--keep-ir` asks to inspect them.
    const callbacks_header_path = try std.fmt.allocPrint(allocator, "{s}.{x}.cinterp_callbacks.h", .{ out, nonce });
    defer removeTempFiles(ll_path, callbacks_header_path, keep_ir);
    try std.fs.cwd().writeFile(.{ .sub_path = callbacks_header_path, .data = callbacks_header });

    try runZigCc(allocator, .{
        .source = src,
        .output = out,
        .target = target,
        .cc_path = cc_path,
        .keep_ir = keep_ir,
    }, ll_path, callbacks_header_path);
    const ir_text = try std.fs.cwd().readFileAlloc(allocator, ll_path, 64 * 1024 * 1024);
    const result = lowerModule(allocator, ir_text, .{
        .source = src,
        .output = out,
        .target = target,
        .cc_path = cc_path,
        .keep_ir = keep_ir,
        .dump = dump,
        .dump_ast = dump_ast,
        .dump_imports = dump_imports,
        .auto_link = auto_link,
    }) catch |err| {
        if (err == error.CallbackAcquireRequiresFunctionRef) {
            std.debug.print("error: ci_callback_acquire requires a direct function reference\n", .{});
            // `std.process.exit` skips defers, so drop the temporaries here.
            removeTempFiles(ll_path, callbacks_header_path, keep_ir);
            std.process.exit(1);
        }
        return err;
    };

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

    // Fail before writing a package the runtime loaders would reject or
    // truncate. `moduleByteLen` is the exact CIVM size; `serializePlans` and
    // friends re-check their own narrowing casts.
    const module_bytes = moduleByteLen(result.functions);
    validateLimits(result, module_bytes, &import_table) catch |err| {
        std.debug.print("compiler limit: {s}\n", .{limitMessage(err)});
        return err;
    };

    const module = try moduleSerialize(allocator, result.functions);
    var names = cipc.NamePool.init(allocator);
    defer names.deinit();
    const plans = try serializePlans(allocator, result.plans, target.abi, &names);
    try import_table.internNames(&names);
    const const_bytes = try cipc.serialize(allocator, &names, result.const_data, result.data_base);
    const import_bytes = try import_table.serialize(allocator, &names);
    const package = try packageSerialize(allocator, module, plans, import_bytes, const_bytes);
    const file = try std.fs.cwd().createFile(out, .{});
    defer file.close();
    try file.writeAll(package);

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "{s}: {d}B module, {d}B plans, {d}B const, {d} functions, {d} external plans, target={s}, cib=v4, imports={d}, cc=zig\n",
        .{ out, module.len, plans.len, const_bytes.len, result.functions.len, result.plans.len, target.name, import_table.count() },
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

test "callback acquire/release builtins never reach the CIPI table" {
    // `buildImportTable` allocates provider lists per entry from `allocator`
    // (arena-allocated in production), so only the table itself is freed here.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var table = try buildImportTable(
        allocator,
        // A hand-written/legacy module may still carry the builtin as a plan;
        // `lower_ast` filters it, this is the belt-and-braces path in `main`.
        &.{
            .{ .name = "__ci_callback_acquire", .args = &.{}, .ret_locs = &.{} },
            .{ .name = "__ci_callback_release", .args = &.{}, .ret_locs = &.{} },
            .{ .name = "puts", .args = &.{}, .ret_locs = &.{} },
        },
        &.{ "@__ci_callback_acquire", "@__ci_callback_release", "@errno" },
        findTarget("x86_64-linux").?,
        true,
    );
    defer table.deinit();

    for (table.entries.items) |entry| {
        try std.testing.expect(!std.mem.eql(u8, entry.name, "__ci_callback_acquire"));
        try std.testing.expect(!std.mem.eql(u8, entry.name, "__ci_callback_release"));
    }
    // The unrelated symbols still get their entries.
    var saw_errno = false;
    var saw_puts_plan = false;
    for (table.entries.items) |entry| {
        if (std.mem.eql(u8, entry.name, "errno")) saw_errno = true;
        if (std.mem.eql(u8, entry.name, "puts") and entry.plan_index != 0xffff) saw_puts_plan = true;
    }
    try std.testing.expect(saw_errno);
    try std.testing.expect(saw_puts_plan);
}

test "embedded callback header declares the builtins and macros" {
    try std.testing.expect(std.mem.indexOf(u8, callbacks_header, "ci_callback_fn __ci_callback_acquire(ci_callback_fn fn);") != null);
    try std.testing.expect(std.mem.indexOf(u8, callbacks_header, "int __ci_callback_release(ci_callback_fn fn);") != null);
    try std.testing.expect(std.mem.indexOf(u8, callbacks_header, "#define ci_callback_acquire(fn)") != null);
    try std.testing.expect(std.mem.indexOf(u8, callbacks_header, "#define ci_callback_release(fn)") != null);
    try std.testing.expect(std.mem.indexOf(u8, callbacks_header, "#ifndef CINTERP_CALLBACKS_H") != null);
}

test "package v4 uses the 22-byte trusted header" {
    const module = "CIVM";
    const plans = "CIPL";
    const package = try packageSerialize(std.testing.allocator, module, plans, "", "");
    defer std.testing.allocator.free(package);
    try std.testing.expectEqualSlices(u8, "CIPKG", package[0..5]);
    try std.testing.expectEqual(@as(u8, 4), package[5]);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, package[6..10], .little));
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, package[10..14], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, package[14..18], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, package[18..22], .little));
    try std.testing.expectEqual(@as(usize, 30), package.len);
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
    try std.testing.expectEqual(@as(u8, op.OP_LOAD_CONST_POOL), code[0]);
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

    // 10-byte CIVM v2 header + 2+2 counts + u32 code len.
    const expected = moduleByteLen(result.functions);
    try std.testing.expectEqual(@as(usize, 18), expected);
    const bytes = try moduleSerialize(std.testing.allocator, result.functions);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(expected, bytes.len);

    try validateLimits(result, expected, &table);
}

test "validateLimits rejects oversized VM stack and static data" {
    var table = imports.Table.init(std.testing.allocator);
    defer table.deinit();

    var funcs = [_]abi.Function{sampleFunction("main")};
    defer funcs[0].code.deinit();
    funcs[0].local_count = Limits.vm_stack_slots + 1;
    const result = abi.CompileResult{ .functions = &funcs, .plans = &.{}, .external_data = &.{} };
    try std.testing.expectError(error.StackTooDeep, validateLimits(result, 10, &table));

    var data_result = emptyResult();
    data_result.data_base = Limits.vm_memory + 1;
    try std.testing.expectError(error.VmMemoryTooLarge, validateLimits(data_result, 10, &table));

    data_result.data_base = 0;
    const huge = "x" ** (Limits.vm_memory + 1);
    data_result.const_data = huge;
    try std.testing.expectError(error.VmMemoryTooLarge, validateLimits(data_result, 10, &table));
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
