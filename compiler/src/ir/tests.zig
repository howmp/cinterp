//! Tests for the LLVM IR frontend (`lexer.zig`, `ast.zig`, `parser.zig`).
//!
//! Run with `zig build test` (this file is a dedicated test root) or
//! `zig test src/ir/tests.zig`.

const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const parser = @import("parser.zig");
const verify = @import("verify.zig");

comptime {
    _ = verify;
}

/// clang 18.1.6 (`zig cc -S -emit-llvm -O0 -g`) output for a small C file
/// exercising structs, packed structs, arrays, string literals, x86_fp80 and
/// fp128 constants, GEP relocations, switch, byval/sret and a variadic call.
const clang18_fixture = @embedFile("testdata/clang18_x86_64.ll");

const Ctx = struct {
    arena: std.heap.ArenaAllocator,

    fn init() Ctx {
        return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    }

    fn deinit(self: *Ctx) void {
        self.arena.deinit();
    }

    fn allocator(self: *Ctx) std.mem.Allocator {
        return self.arena.allocator();
    }
};

fn tag(comptime T: type, value: T) std.meta.Tag(T) {
    return std.meta.activeTag(value);
}

fn parseOk(ctx: *Ctx, text: []const u8) !ast.Module {
    var p = parser.Parser.init(ctx.allocator(), text);
    return p.parse();
}

fn parseExpectingError(text: []const u8, line: u32, column: u32) !void {
    var ctx = Ctx.init();
    defer ctx.deinit();
    var p = parser.Parser.init(ctx.allocator(), text);
    const result = p.parse();
    try std.testing.expectError(error.ParseError, result);
    try std.testing.expectEqual(line, p.diagnostic.line);
    try std.testing.expectEqual(column, p.diagnostic.column);
    try std.testing.expect(p.diagnostic.message.len > 0);
}

fn expectAttr(attrs: []const ast.Attr, comptime which: std.meta.Tag(ast.Attr.Kind)) ?ast.Attr {
    for (attrs) |attr| {
        if (tag(ast.Attr.Kind, attr.kind) == which) return attr;
    }
    return null;
}

fn findOpaqueCall(attrs: []const ast.Attr, name: []const u8) ?ast.Attr {
    for (attrs) |attr| {
        switch (attr.kind) {
            .opaque_call => |c| if (std.mem.eql(u8, c.name, name)) return attr,
            else => {},
        }
    }
    return null;
}

// --------------------------------------------------------------------- module

test "module header, type definitions and globals" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\; ModuleID = 'sample.c'
        \\source_filename = "sample.c"
        \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
        \\target triple = "x86_64-unknown-linux-gnu"
        \\
        \\%struct.Point = type { i32, i32 }
        \\%struct.Pk = type <{ i8, i32 }>
        \\%struct.Opaque = type opaque
        \\%struct.Nested = type { %struct.Point, [3 x i32], ptr }
        \\%vec = type <4 x i32>
        \\
        \\@g_point = global %struct.Point { i32 1, i32 2 }, align 4, !dbg !0
        \\@.str = private unnamed_addr constant [3 x i8] c"hi\00", align 1, !dbg !8
        \\@g_ext = external global i32, align 4
        \\@g_zero = global %struct.Nested zeroinitializer, align 8
        \\@g_packed = global %struct.Pk <{ i8 1, i32 2 }>, align 1
        \\@g_const = internal constant i32 -7, align 4
    );

    try std.testing.expectEqualStrings("sample.c", module.source_filename.?);
    try std.testing.expectEqualStrings("e-m:e-i64:64-f80:128-n8:16:32:64-S128", module.target_datalayout.?);
    try std.testing.expectEqualStrings("x86_64-unknown-linux-gnu", module.target_triple.?);
    try std.testing.expectEqual(@as(usize, 5), module.type_defs.len);

    const point = module.findTypeDef("struct.Point").?;
    try std.testing.expectEqual(ast.Type.struct_, tag(ast.Type, point.ty.*));
    try std.testing.expectEqual(@as(usize, 2), point.ty.struct_.fields.len);
    try std.testing.expect(!point.ty.struct_.is_packed);

    const packed_def = module.findTypeDef("struct.Pk").?;
    try std.testing.expect(packed_def.ty.struct_.is_packed);

    const opaque_def = module.findTypeDef("struct.Opaque").?;
    try std.testing.expect(opaque_def.ty.struct_.is_opaque);

    const vec_def = module.findTypeDef("vec").?;
    try std.testing.expectEqual(ast.Type.vector, tag(ast.Type, vec_def.ty.*));
    try std.testing.expectEqual(@as(u64, 4), vec_def.ty.vector.count);

    try std.testing.expectEqual(@as(usize, 6), module.globals.len);

    const point_g = module.findGlobal("g_point").?;
    try std.testing.expectEqual(ast.Value.aggregate, tag(ast.Value, point_g.init.?));
    try std.testing.expectEqual(@as(usize, 2), point_g.init.?.aggregate.elems.len);
    try std.testing.expectEqual(@as(u32, 4), point_g.alignment.?);
    try std.testing.expectEqual(@as(usize, 1), point_g.metadata.len);
    try std.testing.expectEqualStrings("dbg", point_g.metadata[0].name);

    const str_g = module.findGlobal(".str").?;
    try std.testing.expectEqual(ast.Linkage.private, str_g.modifiers.linkage);
    try std.testing.expect(str_g.modifiers.unnamed_addr);
    try std.testing.expect(str_g.is_const);
    const str_init = str_g.init.?;
    try std.testing.expectEqual(ast.Value.string, tag(ast.Value, str_init));
    try std.testing.expectEqualStrings("hi\\00", str_init.string.raw);
    try std.testing.expect(str_init.string.is_c);
    const decoded = try str_init.string.decode(ctx.allocator());
    try std.testing.expectEqualSlices(u8, &.{ 'h', 'i', 0 }, decoded);

    const ext = module.findGlobal("g_ext").?;
    try std.testing.expectEqual(ast.Linkage.external, ext.modifiers.linkage);
    try std.testing.expect(ext.init == null);

    const zero = module.findGlobal("g_zero").?;
    try std.testing.expectEqual(ast.Value.zeroinitializer, tag(ast.Value, zero.init.?));

    const packed_g = module.findGlobal("g_packed").?;
    try std.testing.expect(packed_g.init.?.aggregate.packed_braces);

    const const_g = module.findGlobal("g_const").?;
    try std.testing.expect(const_g.is_const);
    try std.testing.expectEqual(ast.Linkage.internal, const_g.modifiers.linkage);
    try std.testing.expect(const_g.init.?.int.negative);
    try std.testing.expectEqual(@as(i64, -7), const_g.init.?.int.toI64().?);
}

test "globals with nested aggregates and a multi-index GEP relocation" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\%struct.Inner = type { i32, [2 x i16] }
        \\%struct.Outer = type { %struct.Inner, ptr }
        \\
        \\@arr = global [4 x i32] [i32 1, i32 2, i32 3, i32 4], align 16
        \\@nested = global [2 x %struct.Outer] [
        \\  %struct.Outer { %struct.Inner { i32 1, [2 x i16] [i16 2, i16 3] }, ptr @arr },
        \\  %struct.Outer zeroinitializer
        \\], align 8
        \\@p = global ptr getelementptr inbounds ([4 x i32], ptr @arr, i64 0, i64 2), align 8
        \\@q = global ptr getelementptr (%struct.Outer, ptr @nested, i32 1, i32 1), align 8
        \\@r = global i64 ptrtoint (ptr @arr to i64), align 8
    );

    const nested = module.findGlobal("nested").?;
    const agg = nested.init.?.aggregate;
    try std.testing.expectEqual(ast.Aggregate.Kind.brackets, agg.kind);
    try std.testing.expectEqual(@as(usize, 2), agg.elems.len);
    try std.testing.expectEqual(ast.Aggregate.Kind.braces, agg.elems[0].val.aggregate.kind);
    try std.testing.expectEqual(@as(usize, 2), agg.elems[0].val.aggregate.elems.len);
    // Inner struct nested two levels deep keeps its typed elements.
    const inner = agg.elems[0].val.aggregate.elems[0];
    try std.testing.expectEqual(@as(usize, 2), inner.val.aggregate.elems.len);
    try std.testing.expectEqual(@as(u128, 3), inner.val.aggregate.elems[1].val.aggregate.elems[1].val.int.magnitude);

    const p = module.findGlobal("p").?;
    const gep = p.init.?.const_expr.gep;
    try std.testing.expect(gep.inbounds);
    try std.testing.expectEqual(@as(usize, 2), gep.indices.len);
    try std.testing.expectEqual(@as(u64, 4), gep.src.array.count);
    try std.testing.expectEqualStrings("arr", gep.ptr.val.global.name);
    try std.testing.expectEqual(@as(u128, 0), gep.indices[0].val.int.magnitude);
    try std.testing.expectEqual(@as(u128, 2), gep.indices[1].val.int.magnitude);

    const q = module.findGlobal("q").?;
    const qgep = q.init.?.const_expr.gep;
    try std.testing.expectEqual(@as(usize, 2), qgep.indices.len);
    try std.testing.expectEqual(@as(u128, 1), qgep.indices[0].val.int.magnitude);
    try std.testing.expectEqual(@as(u128, 1), qgep.indices[1].val.int.magnitude);
    try std.testing.expectEqualStrings("%struct.Outer", qgep.src.toString(ctx.allocator()) catch unreachable);

    const r = module.findGlobal("r").?;
    const cast_expr = r.init.?.const_expr.cast;
    try std.testing.expectEqual(ast.CastOp.ptrtoint, cast_expr.op);
    try std.testing.expectEqual(ast.Type.ptr, tag(ast.Type, cast_expr.src.*));
    try std.testing.expectEqual(@as(u32, 64), cast_expr.dst.intBits().?);
    try std.testing.expectEqualStrings("arr", cast_expr.value.global.name);
}

// ---------------------------------------------------------------------- types

test "types: arrays, vectors, structs, pointers and function types" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    const a = ctx.allocator();

    const cases = [_]struct { text: []const u8, rendered: []const u8 }{
        .{ .text = "[4 x i32]", .rendered = "[4 x i32]" },
        .{ .text = "[2 x [3 x i8]]", .rendered = "[2 x [3 x i8]]" },
        .{ .text = "<4 x i32>", .rendered = "<4 x i32>" },
        .{ .text = "<2 x float>", .rendered = "<2 x float>" },
        .{ .text = "<vscale x 4 x i32>", .rendered = "<vscale x 4 x i32>" },
        .{ .text = "{ i32, i64 }", .rendered = "{ i32, i64 }" },
        .{ .text = "<{ i8, i32 }>", .rendered = "<{ i8, i32 }>" },
        .{ .text = "%struct.Pk", .rendered = "%struct.Pk" },
        .{ .text = "ptr", .rendered = "ptr" },
        .{ .text = "ptr addrspace(1)", .rendered = "ptr addrspace(1)" },
        .{ .text = "i32 (i32, i64, ...)", .rendered = "i32 (i32, i64, ...)" },
        .{ .text = "void ()", .rendered = "void ()" },
        .{ .text = "void (...)", .rendered = "void (...)" },
        .{ .text = "x86_fp80", .rendered = "x86_fp80" },
        .{ .text = "fp128", .rendered = "fp128" },
        .{ .text = "i1", .rendered = "i1" },
        .{ .text = "i128", .rendered = "i128" },
    };
    for (cases) |case| {
        const ty = try parser.parseTypeString(a, case.text);
        const rendered = try ty.toString(a);
        try std.testing.expectEqualStrings(case.rendered, rendered);
    }

    const packed_ty = try parser.parseTypeString(a, "<{ i8, i32 }>");
    try std.testing.expectEqual(ast.Type.struct_, tag(ast.Type, packed_ty.*));
    try std.testing.expect(packed_ty.struct_.is_packed);
    try std.testing.expectEqual(@as(usize, 2), packed_ty.struct_.fields.len);
    try std.testing.expectEqual(@as(u32, 8), packed_ty.struct_.fields[0].intBits().?);

    const named = try parser.parseTypeString(a, "%struct.Nested");
    try std.testing.expectEqual(ast.Type.named, tag(ast.Type, named.*));
    try std.testing.expectEqualStrings("struct.Nested", named.named.name);

    const ptr_ty = try parser.parseTypeString(a, "ptr");
    try std.testing.expectEqual(ast.Type.ptr, tag(ast.Type, ptr_ty.*));
    try std.testing.expectEqual(@as(u32, 0), ptr_ty.ptr.addr_space);

    const fn_ty = try parser.parseTypeString(a, "ptr (i32, ...)");
    try std.testing.expectEqual(ast.Type.function, tag(ast.Type, fn_ty.*));
    try std.testing.expect(fn_ty.function.varargs);
    try std.testing.expectEqual(@as(usize, 1), fn_ty.function.params.len);

    const vec = try parser.parseTypeString(a, "<8 x i16>");
    try std.testing.expectEqual(@as(u64, 8), vec.vector.count);
    try std.testing.expectEqual(@as(u32, 16), vec.vector.elem.intBits().?);

    const scalable = try parser.parseTypeString(a, "<vscale x 16 x i8>");
    try std.testing.expect(scalable.vector.scalable);

    // Errors carry a position.
    var p = parser.Parser.init(a, "i32 (i32");
    try std.testing.expectError(error.ParseError, p.parseTypeOnly());
    try std.testing.expectEqual(@as(u32, 1), p.diagnostic.line);
    try std.testing.expectEqual(@as(u32, 9), p.diagnostic.column);
}

test "function parameters: byval, sret, align, noundef, signext, zeroext, varargs" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\%struct.Big = type { i64, i64, i64 }
        \\
        \\define void @make(ptr dead_on_unwind noalias writable sret(%struct.Big) align 8 %out,
        \\                 ptr noundef byval(%struct.Big) align 8 %in,
        \\                 i32 signext %x, i64 zeroext noundef %y, ...) #0 {
        \\entry:
        \\  ret void
        \\}
        \\declare i32 @printf(ptr noundef, ...) #1
    );

    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    const func = module.functions[0];
    try std.testing.expectEqualStrings("make", func.name);
    try std.testing.expect(func.sig.is_varargs);
    try std.testing.expectEqual(@as(usize, 4), func.sig.params.len);
    try std.testing.expect(func.sig.ret.isVoid());

    const sret_attr = expectAttr(func.sig.params[0].attrs, .sret).?;
    try std.testing.expectEqual(ast.Type.named, tag(ast.Type, sret_attr.kind.sret.*));
    try std.testing.expectEqualStrings("struct.Big", sret_attr.kind.sret.named.name);
    try std.testing.expect(expectAttr(func.sig.params[0].attrs, .align_) != null);
    try std.testing.expectEqual(@as(u32, 8), expectAttr(func.sig.params[0].attrs, .align_).?.kind.align_);
    try std.testing.expect(expectAttr(func.sig.params[0].attrs, .noalias_) != null);
    try std.testing.expect(expectAttr(func.sig.params[0].attrs, .writable) != null);
    try std.testing.expect(expectAttr(func.sig.params[0].attrs, .dead_on_unwind) != null);

    const byval_attr = expectAttr(func.sig.params[1].attrs, .byval).?;
    try std.testing.expectEqualStrings("struct.Big", byval_attr.kind.byval.named.name);
    try std.testing.expect(expectAttr(func.sig.params[1].attrs, .noundef) != null);

    try std.testing.expect(expectAttr(func.sig.params[2].attrs, .signext) != null);
    try std.testing.expect(expectAttr(func.sig.params[3].attrs, .zeroext) != null);
    try std.testing.expect(expectAttr(func.sig.params[3].attrs, .noundef) != null);

    try std.testing.expectEqualStrings("out", func.sig.params[0].name.?.name);
    try std.testing.expectEqualStrings("y", func.sig.params[3].name.?.name);
    try std.testing.expectEqual(@as(usize, 1), func.attr_groups.len);
    try std.testing.expectEqual(@as(u32, 0), func.attr_groups[0]);

    try std.testing.expectEqual(@as(usize, 1), module.declares.len);
    const decl = module.declares[0];
    try std.testing.expectEqualStrings("printf", decl.name);
    try std.testing.expect(decl.sig.is_varargs);
    try std.testing.expectEqual(@as(usize, 1), decl.sig.params.len);
    // `ptr noundef` parameter with no name.
    try std.testing.expect(decl.sig.params[0].name == null);
    try std.testing.expect(expectAttr(decl.sig.params[0].attrs, .noundef) != null);
}

test "parameter attributes: parenthesised payload (AArch64 alignstack)" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    // Shape of the AArch64 IR that used to fail with
    // `38:60: error: expected '(', found integer literal (found '8')`: the
    // attribute parser consumed the `(` of `alignstack(8)` and then expected a
    // second one. `deref` is valueless, `nofpclass(...)` carries a list and
    // unknown `name(...)` attributes must keep their payload without eating the
    // parameter name that follows.
    const module = try parseOk(&ctx,
        \\define double @user(ptr %d) {
        \\entry:
        \\  %6 = load [2 x double], ptr %d, align 8
        \\  %call4 = call double @c_take_d16([2 x double] alignstack(8) %6)
        \\  ret double %call4
        \\}
        \\declare double @c_take_d16([2 x double] alignstack(8))
        \\declare void @sink(ptr deref alignstack(8) %p, ptr nofpclass(nan inf) %q, ptr futureattr(1, 2) %r)
    );

    const call = module.functions[0].blocks[0].instructions[1].op.call;
    try std.testing.expectEqual(@as(usize, 1), call.args.len);
    try std.testing.expectEqualStrings("(8)", findOpaqueCall(call.args[0].attrs, "alignstack").?.kind.opaque_call.raw);
    // The argument value survived the attribute payload.
    try std.testing.expectEqual(ast.Value.local, tag(ast.Value, call.args[0].val));

    const decl = module.findDecl("c_take_d16").?;
    try std.testing.expectEqualStrings("(8)", findOpaqueCall(decl.sig.params[0].attrs, "alignstack").?.kind.opaque_call.raw);

    const sink = module.findDecl("sink").?;
    try std.testing.expectEqual(@as(usize, 3), sink.sig.params.len);
    // Valueless attribute consumes only its word.
    try std.testing.expectEqualStrings("deref", expectAttr(sink.sig.params[0].attrs, .opaque_).?.kind.opaque_);
    try std.testing.expectEqualStrings("(8)", findOpaqueCall(sink.sig.params[0].attrs, "alignstack").?.kind.opaque_call.raw);
    try std.testing.expectEqualStrings("(nan inf)", findOpaqueCall(sink.sig.params[1].attrs, "nofpclass").?.kind.opaque_call.raw);
    // Unknown `word(...)` attribute is skipped verbatim.
    try std.testing.expectEqualStrings("(1, 2)", findOpaqueCall(sink.sig.params[2].attrs, "futureattr").?.kind.opaque_call.raw);
    try std.testing.expectEqualStrings("p", sink.sig.params[0].name.?.name);
    try std.testing.expectEqualStrings("q", sink.sig.params[1].name.?.name);
    try std.testing.expectEqualStrings("r", sink.sig.params[2].name.?.name);
}

// --------------------------------------------------------------- instructions

test "basic instructions: alloca, load, store, gep, arithmetic, casts, ret, br" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\@g = global [4 x i32] zeroinitializer, align 16
        \\
        \\define i32 @f(i32 %n) {
        \\entry:
        \\  %slot = alloca i32, align 4
        \\  %arr = alloca [4 x i32], i32 2, align 16
        \\  store i32 %n, ptr %slot, align 4
        \\  %v = load i32, ptr %slot, align 4
        \\  %gep = getelementptr inbounds [4 x i32], ptr @g, i64 0, i64 1
        \\  %gep2 = getelementptr i8, ptr %gep, i32 4
        \\  %sum = add nsw i32 %v, 1
        \\  %diff = sub nuw i32 %sum, 2
        \\  %q = sdiv i32 %diff, 3
        \\  %sh = lshr i32 %q, 1
        \\  %cmp = icmp slt i32 %sh, 10
        \\  %sel = select i1 %cmp, i32 1, i32 2
        \\  %ext = zext i32 %sel to i64
        \\  %tr = trunc i64 %ext to i8
        \\  %bc = bitcast ptr %slot to ptr
        \\  %pi = ptrtoint ptr %bc to i64
        \\  %ip = inttoptr i64 %pi to ptr
        \\  %f = sitofp i32 %sel to double
        \\  %i = fptosi double %f to i32
        \\  %ex = extractvalue { i32, i32 } { i32 1, i32 2 }, 1
        \\  br label %next
        \\next:
        \\  ret i32 %ex
        \\}
    );

    const func = module.functions[0];
    const instrs = func.blocks[0].instructions;
    try std.testing.expectEqualStrings("entry", func.blocks[0].name());
    try std.testing.expectEqualStrings("next", func.blocks[1].name());

    try std.testing.expectEqual(ast.Op.alloca, tag(ast.Op, instrs[0].op));
    try std.testing.expectEqualStrings("slot", instrs[0].result.?.name);
    try std.testing.expectEqual(@as(u32, 4), instrs[0].op.alloca.alignment.?);
    try std.testing.expectEqual(@as(u32, 32), instrs[0].op.alloca.ty.intBits().?);

    try std.testing.expectEqual(@as(u128, 2), instrs[1].op.alloca.count.?.val.int.magnitude);

    try std.testing.expectEqual(ast.Op.store, tag(ast.Op, instrs[2].op));
    try std.testing.expectEqual(ast.Value.local, tag(ast.Value, instrs[2].op.store.value.val));
    try std.testing.expectEqualStrings("slot", instrs[2].op.store.ptr.val.local.name);
    try std.testing.expectEqual(@as(u32, 4), instrs[2].op.store.alignment.?);

    try std.testing.expectEqual(ast.Op.load, tag(ast.Op, instrs[3].op));
    try std.testing.expectEqual(@as(u32, 32), instrs[3].op.load.ty.intBits().?);

    const gep = instrs[4].op.gep;
    try std.testing.expect(gep.inbounds);
    try std.testing.expectEqual(@as(usize, 2), gep.indices.len);
    try std.testing.expectEqualStrings("g", gep.ptr.val.global.name);
    try std.testing.expectEqual(@as(usize, 1), instrs[5].op.gep.indices.len);

    try std.testing.expectEqual(ast.BinaryOp.add, instrs[6].op.binary.op);
    try std.testing.expect(instrs[6].op.binary.nsw);
    try std.testing.expect(instrs[7].op.binary.nuw);
    try std.testing.expectEqual(ast.BinaryOp.sdiv, instrs[8].op.binary.op);
    try std.testing.expectEqual(ast.BinaryOp.lshr, instrs[9].op.binary.op);

    try std.testing.expectEqual(ast.IcmpPred.slt, instrs[10].op.icmp.pred);
    try std.testing.expectEqual(@as(u128, 10), instrs[10].op.icmp.rhs.int.magnitude);

    try std.testing.expectEqual(ast.Op.select, tag(ast.Op, instrs[11].op));
    try std.testing.expectEqual(ast.Op.cast, tag(ast.Op, instrs[12].op));
    try std.testing.expectEqual(ast.CastOp.zext, instrs[12].op.cast.op);
    try std.testing.expectEqual(ast.CastOp.trunc, instrs[13].op.cast.op);
    try std.testing.expectEqual(ast.CastOp.bitcast, instrs[14].op.cast.op);
    try std.testing.expectEqual(ast.CastOp.ptrtoint, instrs[15].op.cast.op);
    try std.testing.expectEqual(ast.CastOp.inttoptr, instrs[16].op.cast.op);
    try std.testing.expectEqual(ast.CastOp.sitofp, instrs[17].op.cast.op);
    try std.testing.expectEqual(ast.CastOp.fptosi, instrs[18].op.cast.op);

    const ev = instrs[19].op.extractvalue;
    try std.testing.expectEqual(@as(usize, 1), ev.indices.len);
    try std.testing.expectEqual(@as(u32, 1), ev.indices[0]);

    try std.testing.expectEqual(ast.Op.br, tag(ast.Op, instrs[20].op));
    try std.testing.expectEqualStrings("next", instrs[20].op.br.unconditional.target.name);

    try std.testing.expectEqual(ast.Op.ret, tag(ast.Op, func.blocks[1].instructions[0].op));
}

test "switch with multi-line cases, negative values and metadata" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\define i32 @sw(i32 noundef %x) {
        \\entry:
        \\  switch i32 %x, label %default [
        \\    i32 0, label %a
        \\    i32 -3, label %b
        \\    i32 2147483647, label %c
        \\  ], !dbg !7
        \\
        \\a:
        \\  ret i32 1
        \\b:
        \\  ret i32 2
        \\c:
        \\  ret i32 3
        \\default:
        \\  ret i32 4
        \\}
    );

    const func = module.functions[0];
    const sw = func.blocks[0].instructions[0].op.switch_;
    try std.testing.expectEqualStrings("x", sw.cond.val.local.name);
    try std.testing.expectEqualStrings("default", sw.default.name);
    try std.testing.expectEqual(@as(usize, 3), sw.cases.len);
    try std.testing.expectEqual(@as(u128, 0), sw.cases[0].value.val.int.magnitude);
    try std.testing.expect(sw.cases[1].value.val.int.negative);
    try std.testing.expectEqual(@as(i64, -3), sw.cases[1].value.val.int.toI64().?);
    try std.testing.expectEqualStrings("b", sw.cases[1].target.name);
    try std.testing.expectEqual(@as(u128, 2147483647), sw.cases[2].value.val.int.magnitude);
    try std.testing.expectEqualStrings("dbg", func.blocks[0].instructions[0].metadata[0].name);
    try std.testing.expectEqual(@as(u32, 7), func.blocks[0].instructions[0].metadata[0].ref.id);
    try std.testing.expectEqual(@as(usize, 5), func.blocks.len);
}

test "phi incoming values, including constant expressions" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\@g = global [4 x i32] zeroinitializer
        \\
        \\define ptr @f(i32 %n) {
        \\entry:
        \\  br label %loop
        \\loop:
        \\  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
        \\  %p = phi ptr [ @g, %entry ], [ getelementptr inbounds (i8, ptr @g, i64 4), %loop ]
        \\  %next = add i32 %i, 1
        \\  %done = icmp sge i32 %next, %n
        \\  br i1 %done, label %exit, label %loop
        \\exit:
        \\  ret ptr %p
        \\}
    );

    const func = module.functions[0];
    const loop = func.blocks[1];
    try std.testing.expectEqualStrings("loop", loop.name());
    const phi0 = loop.instructions[0].op.phi;
    try std.testing.expectEqual(@as(usize, 2), phi0.incoming.len);
    try std.testing.expectEqual(@as(u128, 0), phi0.incoming[0].value.int.magnitude);
    try std.testing.expectEqualStrings("entry", phi0.incoming[0].block.name);
    try std.testing.expectEqualStrings("next", phi0.incoming[1].value.local.name);
    try std.testing.expectEqualStrings("loop", phi0.incoming[1].block.name);

    const phi1 = loop.instructions[1].op.phi;
    try std.testing.expectEqual(ast.Type.ptr, tag(ast.Type, phi1.ty.*));
    try std.testing.expectEqual(ast.Value.global, tag(ast.Value, phi1.incoming[0].value));
    try std.testing.expectEqual(ast.Value.const_expr, tag(ast.Value, phi1.incoming[1].value));
    const gep = phi1.incoming[1].value.const_expr.gep;
    try std.testing.expectEqual(@as(usize, 1), gep.indices.len);
    try std.testing.expectEqual(@as(u128, 4), gep.indices[0].val.int.magnitude);
}

test "calls: direct, variadic, indirect, intrinsic and metadata attachments" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\@.fmt = private unnamed_addr constant [4 x i8] c"%d\0A\00", align 1
        \\@g = global [4 x i32] zeroinitializer
        \\
        \\define void @f(ptr %p, ptr %fn) {
        \\entry:
        \\  call void @llvm.dbg.declare(metadata ptr %p, metadata !12, metadata !DIExpression()), !dbg !13
        \\  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %p, ptr align 1 @g, i64 4, i1 false)
        \\  %r = call i32 (ptr, ...) @printf(ptr noundef @.fmt, i32 noundef 1)
        \\  call void %fn(i32 noundef 3)
        \\  %q = tail call i32 @g2(i32 %r) #2
        \\  ret void
        \\}
        \\declare void @llvm.dbg.declare(metadata, metadata, metadata) #1
        \\declare void @llvm.memcpy.p0.p0.i64(ptr noalias, ptr noalias, i64, i1 immarg) #3
        \\declare i32 @printf(ptr noundef, ...) #4
        \\declare i32 @g2(i32)
    );

    const instrs = module.functions[0].blocks[0].instructions;
    try std.testing.expectEqual(ast.Op.call, tag(ast.Op, instrs[0].op));
    const dbg_call = instrs[0].op.call;
    try std.testing.expectEqualStrings("llvm.dbg.declare", dbg_call.callee.direct.name);
    try std.testing.expectEqual(@as(usize, 3), dbg_call.args.len);
    try std.testing.expectEqual(ast.Value.metadata_value, tag(ast.Value, dbg_call.args[0].val));
    try std.testing.expectEqual(ast.Value.metadata, tag(ast.Value, dbg_call.args[1].val));
    try std.testing.expectEqual(@as(u32, 12), dbg_call.args[1].val.metadata.id);
    try std.testing.expectEqual(ast.Value.metadata, tag(ast.Value, dbg_call.args[2].val));
    try std.testing.expectEqualStrings("DIExpression", dbg_call.args[2].val.metadata.named.name);
    try std.testing.expectEqualStrings("dbg", instrs[0].metadata[0].name);
    try std.testing.expectEqual(@as(u32, 13), instrs[0].metadata[0].ref.id);

    const memcpy_call = instrs[1].op.call;
    try std.testing.expectEqualStrings("llvm.memcpy.p0.p0.i64", memcpy_call.callee.direct.name);
    try std.testing.expectEqual(@as(usize, 4), memcpy_call.args.len);
    const align_attr = expectAttr(memcpy_call.args[0].attrs, .align_).?;
    try std.testing.expectEqual(@as(u32, 1), align_attr.kind.align_);
    try std.testing.expectEqual(ast.Value.int, tag(ast.Value, memcpy_call.args[2].val));

    const printf_call = instrs[2].op.call;
    try std.testing.expectEqualStrings("printf", printf_call.callee.direct.name);
    try std.testing.expect(printf_call.fn_ty != null);
    try std.testing.expect(printf_call.is_varargs);
    try std.testing.expectEqual(@as(usize, 2), printf_call.args.len);
    try std.testing.expectEqual(ast.Type.function, tag(ast.Type, printf_call.fn_ty.?.*));
    try std.testing.expectEqual(@as(u32, 32), printf_call.ret.intBits().?);
    try std.testing.expectEqual(ast.Value.global, tag(ast.Value, printf_call.args[0].val));

    const indirect = instrs[3].op.call;
    try std.testing.expectEqual(ast.Call.Callee.indirect, tag(ast.Call.Callee, indirect.callee));
    try std.testing.expectEqualStrings("fn", indirect.callee.indirect.val.local.name);
    try std.testing.expectEqual(@as(usize, 1), indirect.args.len);

    const tail_call = instrs[4].op.call;
    try std.testing.expect(tail_call.is_tail);
    try std.testing.expectEqual(@as(u32, 32), tail_call.ret.intBits().?);
    try std.testing.expectEqual(@as(usize, 1), tail_call.attr_groups.len);

    // Declarations are available and report varargs for printf.
    const decl = module.findDecl("printf").?;
    try std.testing.expect(decl.sig.is_varargs);
    try std.testing.expectEqual(@as(usize, 4), module.declares.len);
}

test "call through a null callee parses as an indirect null" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    // `void f(void (*p)(void)) { ((void (*)(void))0)(); }` lowers to a call
    // through a null function pointer. The legacy lowerer treats it as a
    // no-op; the parser must still accept the spelling.
    const module = try parseOk(&ctx,
        \\define void @f(ptr %p) {
        \\entry:
        \\  call void null(), !dbg !12
        \\  call void null(ptr %p)
        \\  ret void
        \\}
    );

    const instrs = module.functions[0].blocks[0].instructions;
    try std.testing.expectEqual(@as(usize, 3), instrs.len);

    const bare = instrs[0].op.call;
    try std.testing.expectEqual(ast.Call.Callee.indirect, tag(ast.Call.Callee, bare.callee));
    try std.testing.expectEqual(ast.Value.null_, tag(ast.Value, bare.callee.indirect.val));
    try std.testing.expect(bare.ret.isVoid());
    try std.testing.expectEqual(@as(usize, 0), bare.args.len);
    try std.testing.expectEqual(@as(usize, 1), instrs[0].metadata.len);
    try std.testing.expectEqualStrings("dbg", instrs[0].metadata[0].name);

    const with_arg = instrs[1].op.call;
    try std.testing.expectEqual(ast.Call.Callee.indirect, tag(ast.Call.Callee, with_arg.callee));
    try std.testing.expectEqual(ast.Value.null_, tag(ast.Value, with_arg.callee.indirect.val));
    try std.testing.expectEqual(@as(usize, 1), with_arg.args.len);
    try std.testing.expectEqual(ast.Value.local, tag(ast.Value, with_arg.args[0].val));

    try std.testing.expect(tag(ast.Ret, instrs[2].op.ret) == .void);
}

test "constant float forms: f80, f128, double hex and decimal" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\@ld = global x86_fp80 0xK3FFFC000000000000000, align 16
        \\@q = global fp128 0xL00000000000000004000400000000000, align 16
        \\@d = global double 0x7FEFFFFFFFFFFFFF, align 8
        \\@dd = global double 3.250000e+00, align 8
        \\@fnegzero = global float -0.000000e+00, align 4
        \\@one = global double 1.000000e+00, align 8
    );

    const ld = module.findGlobal("ld").?.init.?.float;
    try std.testing.expectEqual(ast.FloatLiteral.Form.hex, ld.form);
    try std.testing.expectEqual(@as(u8, 'K'), ld.hex_spec);
    try std.testing.expectEqual(@as(u16, 80), ld.width);
    try std.testing.expectEqual(@as(u16, 10), ld.byteLen());
    try std.testing.expectEqual(@as(u128, 0x3FFFC000000000000000), ld.bits);
    var ld_bytes: [10]u8 = undefined;
    _ = ld.writeLeBytes(&ld_bytes);
    try std.testing.expectEqual(@as(u8, 0xC0), ld_bytes[7]);
    try std.testing.expectEqual(@as(u8, 0x3F), ld_bytes[9]);

    const q = module.findGlobal("q").?.init.?.float;
    try std.testing.expectEqual(@as(u8, 'L'), q.hex_spec);
    try std.testing.expectEqual(@as(u16, 128), q.width);
    try std.testing.expectEqual(@as(u128, 0x40004000000000000000000000000000), q.bits);
    var q_bytes: [16]u8 = undefined;
    _ = q.writeLeBytes(&q_bytes);
    try std.testing.expectEqual(@as(u8, 0x40), q_bytes[15]);
    try std.testing.expectEqual(@as(u8, 0x00), q_bytes[14]);
    try std.testing.expectEqual(@as(u8, 0x40), q_bytes[13]);

    const d = module.findGlobal("d").?.init.?.float;
    try std.testing.expectEqual(@as(u16, 64), d.width);
    try std.testing.expectEqual(@as(u128, 0x7FEFFFFFFFFFFFFF), d.bits);

    const dd = module.findGlobal("dd").?.init.?.float;
    try std.testing.expectEqual(ast.FloatLiteral.Form.decimal, dd.form);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(f64, 3.25))), @as(u64, @truncate(dd.bits)));

    const fnegzero = module.findGlobal("fnegzero").?.init.?.float;
    try std.testing.expectEqual(@as(u32, 0x80000000), @as(u32, @truncate(fnegzero.bits)));

    const one = module.findGlobal("one").?.init.?.float;
    try std.testing.expectEqual(@as(u64, @bitCast(@as(f64, 1.0))), @as(u64, @truncate(one.bits)));
}

test "float hex constants use the double-precision spelling" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    // LLVM prints a `float` hexadecimal constant as the 64-bit double bit
    // pattern of the f32 value, not as the 32-bit f32 pattern. An 8-digit
    // spelling is the raw f32 pattern (the legacy lowerer accepts both).
    const module = try parseOk(&ctx,
        \\@wide = global float 0x405147AE20000000, align 4
        \\@raw = global float 0x428A3D71, align 4
        \\@dec = global float 6.912000e+01, align 4
        \\@neg = global float 0xC0463851E0000000, align 4
        \\@dbl = global double 0x405147AE147AE148, align 8
    );

    const wide = module.findGlobal("wide").?.init.?.float;
    try std.testing.expectEqual(ast.FloatLiteral.Form.hex, wide.form);
    try std.testing.expectEqual(@as(u16, 32), wide.width);
    try std.testing.expectEqual(@as(u128, 0x428A3D71), wide.bits);

    // The raw f32 spelling must not be reinterpreted as a double.
    const raw = module.findGlobal("raw").?.init.?.float;
    try std.testing.expectEqual(@as(u16, 32), raw.width);
    try std.testing.expectEqual(@as(u128, 0x428A3D71), raw.bits);

    // Decimal spellings for an f32 destination carry the f32 bit pattern too.
    const dec = module.findGlobal("dec").?.init.?.float;
    try std.testing.expectEqual(ast.FloatLiteral.Form.decimal, dec.form);
    try std.testing.expectEqual(@as(u16, 32), dec.width);
    try std.testing.expectEqual(@as(u128, 0x428A3D71), dec.bits);

    const neg = module.findGlobal("neg").?.init.?.float;
    try std.testing.expectEqual(@as(u128, 0xC231C28F), neg.bits);

    const dbl = module.findGlobal("dbl").?.init.?.float;
    try std.testing.expectEqual(@as(u16, 64), dbl.width);
    try std.testing.expectEqual(@as(u128, 0x405147AE147AE148), dbl.bits);
}

test "negative and hexadecimal integer literals" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\@a = global i32 -2147483648
        \\@b = global i64 u0x7FFFFFFFFFFFFFFF
        \\@c = global i64 s0xFFFFFFFFFFFFFFFF
        \\@d = global i128 170141183460469231731687303715884105727
        \\@e = global i1 true
        \\@f = global i1 false
    );

    const a = module.findGlobal("a").?.init.?.int;
    try std.testing.expect(a.negative);
    try std.testing.expectEqual(@as(u128, 2147483648), a.magnitude);
    try std.testing.expectEqual(@as(i64, -2147483648), a.toI64().?);

    const b = module.findGlobal("b").?.init.?.int;
    try std.testing.expect(b.hex);
    try std.testing.expectEqual(@as(u128, 0x7FFFFFFFFFFFFFFF), b.magnitude);

    const c = module.findGlobal("c").?.init.?.int;
    try std.testing.expect(c.hex);
    try std.testing.expectEqual(@as(u128, 0xFFFFFFFFFFFFFFFF), c.magnitude);

    const d = module.findGlobal("d").?.init.?.int;
    try std.testing.expect(!d.overflow);
    try std.testing.expectEqual(@as(u128, 170141183460469231731687303715884105727), d.magnitude);

    try std.testing.expectEqual(@as(u128, 1), module.findGlobal("e").?.init.?.int.magnitude);
    try std.testing.expectEqual(@as(u128, 0), module.findGlobal("f").?.init.?.int.magnitude);
}

test "quoted names and escaped strings" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\@.str = private unnamed_addr constant [7 x i8] c"a\09b\22c\00", align 1
        \\@"quoted global" = global i32 7
        \\
        \\define void @"fn with space"(i32 %"arg name") {
        \\"entry block":
        \\  %"odd name" = add i32 %"arg name", 1
        \\  ret void
        \\}
    );

    const g = module.findGlobal("quoted global").?;
    try std.testing.expect(g.name_ref.quoted);
    try std.testing.expectEqual(@as(u128, 7), g.init.?.int.magnitude);

    const str = module.findGlobal(".str").?;
    try std.testing.expectEqualStrings("a\\09b\\22c\\00", str.init.?.string.raw);
    const decoded = try str.init.?.string.decode(ctx.allocator());
    try std.testing.expectEqualSlices(u8, &.{ 'a', 9, 'b', '"', 'c', 0 }, decoded);

    const func = module.functions[0];
    try std.testing.expectEqualStrings("fn with space", func.name);
    try std.testing.expect(func.name_ref.quoted);
    try std.testing.expectEqualStrings("arg name", func.sig.params[0].name.?.name);
    try std.testing.expectEqualStrings("entry block", func.blocks[0].name());
    try std.testing.expectEqualStrings("odd name", func.blocks[0].instructions[0].result.?.name);
}

test "constexpr operands inside instructions" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\@g = global [4 x i32] zeroinitializer
        \\
        \\define i32 @f() {
        \\entry:
        \\  %v = load i32, ptr getelementptr inbounds ([4 x i32], ptr @g, i64 0, i64 2), align 4
        \\  %a = add i32 %v, ptrtoint (ptr @g to i32)
        \\  %b = add i64 %a, add (i64 1, i64 2)
        \\  store i32 %a, ptr getelementptr inbounds (i8, ptr @g, i64 4), align 4
        \\  ret i32 %b
        \\}
    );

    const instrs = module.functions[0].blocks[0].instructions;
    const load_ptr = instrs[0].op.load.ptr;
    try std.testing.expectEqual(ast.Value.const_expr, tag(ast.Value, load_ptr.val));
    try std.testing.expectEqual(@as(usize, 2), load_ptr.val.const_expr.gep.indices.len);

    const add_a = instrs[1].op.binary;
    try std.testing.expectEqual(ast.Value.const_expr, tag(ast.Value, add_a.rhs));
    try std.testing.expectEqual(ast.CastOp.ptrtoint, add_a.rhs.const_expr.cast.op);

    const add_b = instrs[2].op.binary;
    try std.testing.expectEqual(ast.Value.const_expr, tag(ast.Value, add_b.rhs));
    try std.testing.expectEqual(ast.BinaryOp.add, add_b.rhs.const_expr.binary.op);
    try std.testing.expectEqual(@as(u128, 1), add_b.rhs.const_expr.binary.lhs.int.magnitude);
    try std.testing.expectEqual(@as(u128, 2), add_b.rhs.const_expr.binary.rhs.int.magnitude);

    const store_ptr = instrs[3].op.store.ptr;
    try std.testing.expectEqual(ast.Value.const_expr, tag(ast.Value, store_ptr.val));
    try std.testing.expectEqual(@as(u128, 4), store_ptr.val.const_expr.gep.indices[0].val.int.magnitude);
}

test "gep with struct indices and vector types" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\%struct.V = type { <4 x i32>, <2 x float> }
        \\@gv = global <4 x i32> <i32 1, i32 2, i32 3, i32 4>, align 16
        \\@gvv = global %struct.V zeroinitializer, align 16
        \\
        \\define <4 x i32> @vecadd(<4 x i32> noundef %a, <4 x i32> noundef %b) {
        \\entry:
        \\  %slot = alloca <4 x i32>, align 16
        \\  store <4 x i32> %a, ptr %slot, align 16
        \\  %gep = getelementptr inbounds %struct.V, ptr @gvv, i32 0, i32 0
        \\  %add = add <4 x i32> %a, %b
        \\  ret <4 x i32> %add
        \\}
    );

    const vec_init = module.findGlobal("gv").?.init.?.aggregate;
    try std.testing.expectEqual(ast.Aggregate.Kind.angles, vec_init.kind);
    try std.testing.expectEqual(@as(usize, 4), vec_init.elems.len);
    try std.testing.expectEqual(@as(u128, 4), vec_init.elems[3].val.int.magnitude);

    const func = module.functions[0];
    try std.testing.expectEqual(@as(u64, 4), func.sig.ret.vector.count);
    try std.testing.expectEqual(@as(usize, 2), func.sig.params.len);
    const instrs = func.blocks[0].instructions;
    const gep = instrs[2].op.gep;
    try std.testing.expectEqual(@as(usize, 2), gep.indices.len);
    try std.testing.expectEqual(@as(u128, 0), gep.indices[1].val.int.magnitude);
    try std.testing.expectEqual(ast.Type.vector, tag(ast.Type, instrs[3].op.binary.ty.*));
}

// ---------------------------------------------------------------- module odds

test "attribute groups, comdats, module flags and metadata records stay opaque" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx,
        \\source_filename = "x.c"
        \\target triple = "x86_64-unknown-linux-gnu"
        \\
        \\$cn = comdat any
        \\@g = global i32 1, comdat, align 4
        \\@h = global i32 2, comdat($cn), align 4
        \\
        \\define void @f() #0 {
        \\entry:
        \\  ret void
        \\}
        \\
        \\attributes #0 = { noinline nounwind "frame-pointer"="all" }
        \\!llvm.module.flags = !{!0, !1}
        \\!llvm.ident = !{!2}
        \\!0 = !{i32 1, !"wchar_size", i32 4}
        \\!1 = !{i32 7, !"PIC Level", i32 2}
        \\!2 = !{!"clang version 18.1.6"}
        \\!3 = distinct !DICompileUnit(language: DW_LANG_C11, file: !4, isOptimized: false)
        \\!4 = !DIFile(filename: "x.c", directory: "/tmp")
        \\uselistorder i32 %x, { 1, 0 }
        \\module asm "nop"
    );

    try std.testing.expectEqual(@as(usize, 1), module.attribute_groups.len);
    try std.testing.expectEqual(@as(u32, 0), module.attribute_groups[0].id);
    try std.testing.expect(std.mem.indexOf(u8, module.attribute_groups[0].raw, "noinline") != null);

    // Every metadata record is preserved as an opaque record with its name.
    try std.testing.expect(module.metadata.len >= 5);
    var saw_module_flags = false;
    for (module.metadata) |record| {
        if (std.mem.eql(u8, record.name, "llvm.module.flags")) saw_module_flags = true;
    }
    try std.testing.expect(saw_module_flags);

    // comdat / uselistorder / module asm records are skipped, not rejected.
    try std.testing.expect(module.opaque_records.len >= 3);
    try std.testing.expect(module.findGlobal("g").?.comdat != null);

    const func = module.functions[0];
    try std.testing.expectEqual(@as(usize, 1), func.attr_groups.len);
}

test "clang 18 fixture parses end to end" {
    var ctx = Ctx.init();
    defer ctx.deinit();

    const module = try parseOk(&ctx, clang18_fixture);

    try std.testing.expectEqualStrings("fixture.c", module.source_filename.?);
    try std.testing.expectEqualStrings("x86_64-unknown-linux-gnu", module.target_triple.?);
    try std.testing.expect(module.target_datalayout != null);
    try std.testing.expect(module.type_defs.len >= 3);
    try std.testing.expect(module.globals.len >= 7);
    try std.testing.expect(module.functions.len >= 5);
    try std.testing.expect(module.declares.len >= 1);

    // x86_fp80 and fp128 globals keep their exact bit patterns.
    const ld = module.findGlobal("g_ld").?.init.?.float;
    try std.testing.expectEqual(@as(u128, 0x3FFFC000000000000000), ld.bits);
    const q = module.findGlobal("g_f128").?.init.?.float;
    try std.testing.expectEqual(@as(u128, 0x40004000000000000000000000000000), q.bits);

    // The GEP relocation global is a constant expression with a single index.
    const reloc = module.findGlobal("g_reloc").?.init.?.const_expr.gep;
    try std.testing.expectEqual(@as(usize, 1), reloc.indices.len);
    try std.testing.expectEqualStrings("g_arr", reloc.ptr.val.global.name);

    // All debug intrinsics are plain calls.
    var intrinsic_calls: usize = 0;
    for (module.functions) |func| {
        for (func.blocks) |block| {
            for (block.instructions) |instr| {
                if (tag(ast.Op, instr.op) != .call) continue;
                const callee = instr.op.call.callee;
                if (tag(ast.Call.Callee, callee) != .direct) continue;
                if (std.mem.startsWith(u8, callee.direct.name, "llvm.")) intrinsic_calls += 1;
            }
        }
    }
    try std.testing.expect(intrinsic_calls > 0);

    // Every instruction node has a plausible span.
    for (module.functions) |func| {
        for (func.blocks) |block| {
            for (block.instructions) |instr| {
                try std.testing.expect(instr.span.line >= 1);
                try std.testing.expect(instr.span.column >= 1);
                try std.testing.expect(instr.span.end >= instr.span.start);
            }
        }
    }
}

// ------------------------------------------------------------------- failures

test "malformed input returns a positioned error instead of panicking" {
    // Bad alignment operand: `x` is at line 1, column 26.
    try parseExpectingError("@g = global i32 1, align x\n", 1, 26);

    // Unsupported (legal) instruction form.
    try parseExpectingError(
        \\define void @f() {
        \\entry:
        \\  atomicrmw add ptr @g, i32 1 seq_cst
        \\}
    , 3, 3);

    // Unterminated function body: EOF is reported at line 4, column 1.
    try parseExpectingError("define void @f() {\nentry:\n  ret void\n", 4, 1);

    // Missing operand type.
    try parseExpectingError(
        \\define i32 @f() {
        \\entry:
        \\  ret 0
        \\}
    , 3, 7);

    // Bad type.
    try parseExpectingError("@g = global i33x 0\n", 1, 13);

    // Lexical error (a '+' cannot start a token) is surfaced with position.
    try parseExpectingError("@g = global i32 1\n@h = global i32 +2\n", 2, 17);
}

test "truncated and mutated fixture never panics" {
    const allocator = std.testing.allocator;
    var step: usize = 0;
    const stride: usize = 97;
    var len: usize = 0;
    while (len < clang18_fixture.len) : (len += stride) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var p = parser.Parser.init(arena.allocator(), clang18_fixture[0..len]);
        const result = p.parse();
        if (result) |_| {} else |err| {
            try std.testing.expectEqual(error.ParseError, err);
            try std.testing.expect(p.diagnostic.line >= 1);
            try std.testing.expect(p.diagnostic.column >= 1);
            try std.testing.expect(p.diagnostic.message.len > 0);
        }
        step += 1;
    }
    try std.testing.expect(step > 10);

    // Mutate a handful of bytes and require a clean error or a clean parse.
    const mutations = [_]u8{ '}', '{', '!', '?', 0, '"', '%', '@', '(', ')' };
    var i: usize = 0;
    while (i < mutations.len) : (i += 1) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const copy = try arena.allocator().dupe(u8, clang18_fixture);
        const at = (i * 293) % copy.len;
        copy[at] = mutations[i];
        var p = parser.Parser.init(arena.allocator(), copy);
        const result = p.parse();
        if (result) |_| {} else |err| {
            try std.testing.expectEqual(error.ParseError, err);
            try std.testing.expect(p.diagnostic.line >= 1);
        }
    }
}

test "nested type depth is bounded" {
    var ctx = Ctx.init();
    defer ctx.deinit();
    var text = std.ArrayList(u8).init(ctx.allocator());
    var i: usize = 0;
    while (i < 200) : (i += 1) try text.appendSlice("[1 x ");
    try text.appendSlice("i32");
    i = 0;
    while (i < 200) : (i += 1) try text.append(']');
    var p = parser.Parser.init(ctx.allocator(), text.items);
    try std.testing.expectError(error.ParseError, p.parseTypeOnly());
    try std.testing.expect(p.diagnostic.message.len > 0);
}

test "lexer kinds for clang 18 trivia and tokens" {
    var lx = lexer.Lexer.init(clang18_fixture);
    var count: usize = 0;
    while (true) {
        const tok = try lx.next();
        if (tok.kind == .eof) break;
        count += 1;
        try std.testing.expect(tok.span.line >= 1);
        try std.testing.expect(tok.span.end > tok.span.start);
    }
    try std.testing.expect(count > 1000);
}
