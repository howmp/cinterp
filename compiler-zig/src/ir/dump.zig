//! `ir-dump`: parse a `.ll` file with the phase-one IR frontend and print a
//! structural dump of the typed AST. Intended as a debugging aid while porting
//! lowering (`zig build ir-dump -- file.ll`); it is not installed.
//!
//! Exit status: 0 on a successful parse, 1 on a diagnostic (printed as
//! `file:line:column: error: message (found 'token')`), 2 on usage errors.

const std = @import("std");
const ast = @import("ast.zig");
const parser = @import("parser.zig");

fn usage() void {
    std.debug.print("usage: ir-dump [--counts] <file.ll>\n", .{});
}

fn dumpValue(writer: anytype, value: ast.Value) !void {
    switch (value) {
        .aggregate => |agg| {
            try writer.writeAll("<aggregate>");
            _ = agg;
        },
        .const_expr => |expr| {
            try writer.writeAll("constant-expression:");
            switch (expr.*) {
                .gep => |g| try writer.print("getelementptr(indices={d}, inbounds={})", .{ g.indices.len, g.inbounds }),
                .cast => |c| try writer.print("{s}", .{@tagName(c.op)}),
                .binary => |b| try writer.print("{s}", .{b.op.keyword()}),
                .icmp => |c| try writer.print("icmp {s}", .{@tagName(c.pred)}),
                .fcmp => |c| try writer.print("fcmp {s}", .{ast.fcmpPredName(c.pred)}),
                .select => try writer.writeAll("select"),
                .extractvalue => try writer.writeAll("extractvalue"),
                .fneg => try writer.writeAll("fneg"),
            }
        },
        else => try writer.print("{}", .{value}),
    }
}

fn dumpInstruction(writer: anytype, instr: ast.Instruction) !void {
    if (instr.result) |res| try writer.print("  %{s} = ", .{res.name}) else try writer.writeAll("  ");
    try writer.writeAll(instr.mnemonic());
    switch (instr.op) {
        .alloca => |a| {
            try writer.writeAll(" ");
            try writer.print("{}", .{a.ty.*});
        },
        .load => |l| {
            try writer.writeAll(" ");
            try writer.print("{}", .{l.ty.*});
        },
        .store => |s| {
            try writer.writeAll(" ");
            try writer.print("{}", .{s.ty.*});
        },
        .gep => |g| try writer.print(" (indices={d}, inbounds={})", .{ g.indices.len, g.inbounds }),
        .phi => |p| try writer.print(" (incoming={d})", .{p.incoming.len}),
        .switch_ => |s| try writer.print(" (cases={d}, default=%{s})", .{ s.cases.len, s.default.name }),
        .call => |c| {
            switch (c.callee) {
                .direct => |n| try writer.print(" @{s}", .{n.name}),
                .indirect => |tv| try writer.print(" %{s}", .{tv.val.local.name}),
                .asm_ => try writer.writeAll(" asm"),
            }
            try writer.print(" (args={d}, varargs={}, tail={})", .{ c.args.len, c.is_varargs, c.is_tail });
        },
        .ret => |r| switch (r) {
            .void => try writer.writeAll(" void"),
            .value => |v| {
                try writer.writeAll(" ");
                try writer.print("{}", .{v.ty.*});
            },
        },
        .binary => |b| {
            try writer.writeAll(" ");
            try writer.print("{}", .{b.ty.*});
        },
        .cast => |c| {
            try writer.writeAll(" ");
            try writer.print("{} -> {}", .{ c.src.*, c.dst.* });
        },
        .icmp => |c| try writer.print(" {s}", .{@tagName(c.pred)}),
        .fcmp => |c| try writer.print(" {s}", .{ast.fcmpPredName(c.pred)}),
        else => {},
    }
    if (instr.metadata.len != 0) {
        try writer.writeAll(" [");
        for (instr.metadata, 0..) |attachment, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("!{s}", .{attachment.name});
        }
        try writer.writeAll("]");
    }
    try writer.writeAll("\n");
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
    var counts_only = false;
    var path: ?[]const u8 = null;
    for (argv[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--counts")) {
            counts_only = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            continue; // `zig build ir-dump -- --flag file` passes the separator through
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            usage();
            return;
        } else if (arg.len != 0 and arg[0] == '-') {
            usage();
            std.process.exit(2);
        } else {
            path = arg;
        }
    }
    const file = path orelse {
        usage();
        std.process.exit(2);
    };

    const text = std.fs.cwd().readFileAlloc(allocator, file, 256 * 1024 * 1024) catch |err| {
        std.debug.print("ir-dump: cannot read '{s}': {s}\n", .{ file, @errorName(err) });
        std.process.exit(2);
    };

    var p = parser.Parser.init(allocator, text);
    const module = p.parse() catch {
        std.debug.print("{s}:{d}:{d}: error: {s} (found '{s}')\n", .{
            file, p.diagnostic.line, p.diagnostic.column, p.diagnostic.message, p.diagnostic.found,
        });
        std.process.exit(1);
    };

    var out = std.io.getStdOut().writer();
    try out.print("{s}: {d} type defs, {d} globals, {d} declares, {d} functions, {d} metadata, {d} opaque records\n", .{
        file,
        module.type_defs.len,
        module.globals.len,
        module.declares.len,
        module.functions.len,
        module.metadata.len,
        module.opaque_records.len,
    });
    if (module.source_filename) |v| try out.print("  source_filename = \"{s}\"\n", .{v});
    if (module.target_triple) |v| try out.print("  target triple = \"{s}\"\n", .{v});
    if (module.target_datalayout) |v| try out.print("  target datalayout = \"{s}\"\n", .{v});
    if (counts_only) return;

    for (module.type_defs) |def| {
        try out.print("  %{s} = type {}\n", .{ def.name, def.ty.* });
    }
    for (module.globals) |g| {
        try out.print("  @{s} = {s} {}", .{ g.name, if (g.is_const) "constant" else "global", g.ty.* });
        if (g.init) |init| {
            try out.writeAll(" = ");
            try dumpValue(out, init);
        }
        if (g.alignment) |a| try out.print(", align {d}", .{a});
        try out.writeAll("\n");
    }
    for (module.declares) |d| {
        try out.print("  declare {} @{s}(", .{ d.sig.ret.*, d.name });
        for (d.sig.params, 0..) |param, i| {
            if (i != 0) try out.writeAll(", ");
            try out.print("{}", .{param.ty.*});
        }
        if (d.sig.is_varargs) try out.writeAll(", ...");
        try out.writeAll(")\n");
    }
    for (module.functions) |f| {
        try out.print("  define {} @{s}(", .{ f.sig.ret.*, f.name });
        for (f.sig.params, 0..) |param, i| {
            if (i != 0) try out.writeAll(", ");
            try out.print("{}", .{param.ty.*});
            for (param.attrs) |attr| try out.print(" {}", .{attr});
            if (param.name) |name| try out.print(" %{s}", .{name.name});
        }
        if (f.sig.is_varargs) try out.writeAll(", ...");
        try out.print(") [{d} blocks]\n", .{f.blocks.len});
        for (f.blocks) |block| {
            try out.print("  {s}:\n", .{if (block.name().len != 0) block.name() else "<entry>"});
            for (block.instructions) |instr| try dumpInstruction(out, instr);
        }
    }
}
