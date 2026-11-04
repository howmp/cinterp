//! AST-based lowering: consumes the typed IR AST produced by `ir/parser.zig`
//! (`ir/ast.zig`) and emits an `abi.CompileResult` (CIVM bytecode + CIPL plans
//! + external symbol table). This is the only IR frontend; `main.zig` parses
//! once and calls `compile` here.
//!
//! Design notes:
//!
//! * Type layout (`Layout`) is a pure `ast.Type` -> size/align/offsets function
//!   implementing the string lowerer's rules: packed structs ignore alignment,
//!   arrays are sized with the *aligned* element size, integers are rounded up
//!   to their alignment, `x86_fp80` is 16 bytes on 64-bit targets.
//! * ABI plans live in `abi.zig`: types are rendered back to their canonical
//!   IR spelling and `abi.buildPlanForAbi` is called, so Loc kinds and plan
//!   ordering have a single implementation.
//! * Everything else is emitted instruction by instruction in the order the
//!   retired text lowerer used, including its incidental decisions (slot
//!   allocation order, `__select_else_N` labels, `__f80save_<code len>` slots,
//!   varargs tag encoding, callback plan interleaving) so existing CIBs stay
//!   byte-identical.
//! * Compatibility quirks are preserved on purpose (see `compat:` comments) to
//!   keep emitted CIBs stable: single-index global GEP addends in the default
//!   `GepConstMode.legacy`, integer initialisers capped at 8 bytes,
//!   `fp128`/vector initialisers left zeroed, unresolved `@symbol` operands
//!   lowering to 0.

const std = @import("std");
const op = @import("opcodes.zig");
const abi = @import("abi.zig");
const ast = @import("ir/ast.zig");

const Allocator = std.mem.Allocator;

/// How the relocation addend of a global `getelementptr` constant expression is
/// computed.
pub const GepConstMode = enum {
    /// Compatibility behaviour: only the first index is folded (`addend = idx0 *
    /// sizeof(src)`), the remaining indices are ignored. This is what the
    /// retired text lowerer did; it is the default so emitted CIBs stay stable.
    legacy,
    /// Walk every index (arrays/vectors by element stride, structs by field
    /// offset), i.e. the LLVM-correct addend.
    correct,
};

pub const Options = struct {
    gep_const: GepConstMode = .legacy,
};

// --------------------------------------------------------------------- helpers

fn alignUp(n: u32, a: u32) u32 {
    if (a <= 1) return n;
    return (n + a - 1) / a * a;
}

fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn isTag(value: ast.Value, comptime tag: std.meta.Tag(ast.Value)) bool {
    return std.meta.activeTag(value) == tag;
}

/// Internal symbols declared by the header `cinterp-cc` force-includes
/// (`src/data/cinterp_callbacks.h`). `ci_callback_acquire`/`_release` are
/// macros over these names; the lowerer turns calls into dedicated CIVM
/// opcodes, so they must never reach CIPI (the runtime does not export them).
pub const callback_acquire_symbol = "__ci_callback_acquire";
pub const callback_release_symbol = "__ci_callback_release";

pub fn isCallbackBuiltin(name: []const u8) bool {
    return eql(name, callback_acquire_symbol) or eql(name, callback_release_symbol);
}

fn renderType(allocator: Allocator, ty: *const ast.Type) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try ast.renderType(list.writer(), ty);
    return list.toOwnedSlice();
}

/// Render a type for ABI plan construction.
///
/// `abi.zig` classifies a plan from the rendered spelling alone (it has no
/// access to the module's type table), so named aggregates are expanded to
/// their literal body here: `%struct.D16` becomes `{ double, double }` and
/// `[2 x %struct.D16]` becomes `[2 x { double, double }]`. The canonical IR
/// spelling (`renderType`) is still what the function metadata records, so
/// emitted CIBs keep their previous type strings.
fn renderPlanType(allocator: Allocator, layout: *const Layout, ty: *const ast.Type) ![]const u8 {
    return renderPlanTypeDepth(allocator, layout, ty, 0);
}

fn renderPlanTypeDepth(allocator: Allocator, layout: *const Layout, ty: *const ast.Type, depth: u32) ![]const u8 {
    if (depth > 32) return error.BadType;
    switch (ty.*) {
        .named => |n| {
            // An unknown or opaque name keeps its `%name` spelling; `abi.zig`
            // then reports UnsupportedFfi instead of misclassifying it.
            const target = layout.named.get(n.name) orelse return renderType(allocator, ty);
            return renderPlanTypeDepth(allocator, layout, target, depth + 1);
        },
        .struct_ => |s| {
            if (s.is_opaque) return renderType(allocator, ty);
            var list = std.ArrayList(u8).init(allocator);
            errdefer list.deinit();
            try list.appendSlice(if (s.is_packed) "<{" else "{");
            for (s.fields, 0..) |field, i| {
                try list.appendSlice(if (i == 0) " " else ", ");
                try list.appendSlice(try renderPlanTypeDepth(allocator, layout, field, depth + 1));
            }
            try list.appendSlice(if (s.is_packed) " }>" else " }");
            return list.toOwnedSlice();
        },
        .array => |a| {
            var list = std.ArrayList(u8).init(allocator);
            errdefer list.deinit();
            try list.writer().print("[{d} x ", .{a.count});
            try list.appendSlice(try renderPlanTypeDepth(allocator, layout, a.elem, depth + 1));
            try list.append(']');
            return list.toOwnedSlice();
        },
        else => return renderType(allocator, ty),
    }
}

/// Value of an integer literal as an `i64` when representable. Mirrors the
/// legacy `parseI64` domain (decimal and `0x` spellings up to i64 range) and
/// additionally accepts u64-range literals via a bit cast.
fn intToI64(lit: ast.IntLiteral) ?i64 {
    if (lit.toI64()) |v| return v;
    if (lit.overflow) return null;
    if (!lit.negative and lit.magnitude <= std.math.maxInt(u64)) {
        return @bitCast(@as(u64, @intCast(lit.magnitude)));
    }
    return null;
}

fn intBitsOf(ty: *const ast.Type) ?u32 {
    return switch (ty.*) {
        .int => |t| t.bits,
        else => null,
    };
}

fn floatKindOf(ty: *const ast.Type) ?ast.FloatKind {
    return switch (ty.*) {
        .float => |t| t.kind,
        else => null,
    };
}

fn isF80OrF128(ty: *const ast.Type) bool {
    const kind = floatKindOf(ty) orelse return false;
    return kind == .x86_fp80 or kind == .fp128;
}

fn isPlainFloat(ty: *const ast.Type) bool {
    const kind = floatKindOf(ty) orelse return false;
    return kind == .float or kind == .double;
}

/// True for the type shapes the legacy store path copies with `OP_MEMCPY`
/// instead of a scalar store (`%named`, `[array]`, `{struct}`, `<vector>`).
fn isAggregateLike(ty: *const ast.Type) bool {
    return switch (ty.*) {
        .struct_, .array, .vector, .named => true,
        else => false,
    };
}

fn maskFor(bits: u32) i64 {
    return @intCast((@as(u64, 1) << @intCast(bits)) - 1);
}

// ---------------------------------------------------------------------- layout

const SizeAlign = struct { size: u32, alignment: u32 };

const StructLayout = struct { offsets: []const u32, size: u32, alignment: u32 };

/// `ast.Type` -> size/alignment/field offsets. Encodes the layout rules the
/// compiler has always used (see the module doc comment).
const Layout = struct {
    allocator: Allocator,
    ptr_size: u32,
    /// Named type bodies (`%struct.X` -> parsed type), keyed without the `%`.
    named: std.StringHashMap(*const ast.Type),

    fn init(allocator: Allocator, module: *const ast.Module, ptr_size: u32) !Layout {
        var named = std.StringHashMap(*const ast.Type).init(allocator);
        for (module.type_defs) |def| {
            // `put` matches the legacy `structs.put` (last definition wins).
            try named.put(def.name, def.ty);
        }
        return .{ .allocator = allocator, .ptr_size = ptr_size, .named = named };
    }

    /// Resolve `%name` chains and aliases down to a struct body.
    fn asStruct(self: *const Layout, ty: *const ast.Type) ?ast.StructType {
        var current = ty;
        var depth: u32 = 0;
        while (depth < 32) : (depth += 1) {
            switch (current.*) {
                .struct_ => |s| {
                    if (s.is_opaque) return null;
                    return s;
                },
                .named => |n| current = self.named.get(n.name) orelse return null,
                else => return null,
            }
        }
        return null;
    }

    fn sizeAlign(self: *const Layout, ty: *const ast.Type) anyerror!SizeAlign {
        return self.sizeAlignDepth(ty, 0);
    }

    fn sizeAlignDepth(self: *const Layout, ty: *const ast.Type, depth: u32) anyerror!SizeAlign {
        if (depth > 32) return error.BadType;
        switch (ty.*) {
            .void => return .{ .size = 0, .alignment = 1 },
            .int => |t| {
                const store: u32 = @max(1, (t.bits + 7) / 8);
                const alignment: u32 = if (t.bits <= 8) 1 else if (t.bits <= 16) 2 else if (t.bits <= 32) 4 else if (t.bits <= 64) 8 else 16;
                return .{ .size = alignUp(store, alignment), .alignment = alignment };
            },
            .float => |t| switch (t.kind) {
                .half, .bfloat => return .{ .size = 2, .alignment = 2 },
                .float => return .{ .size = 4, .alignment = 4 },
                .double => return .{ .size = 8, .alignment = 8 },
                .x86_fp80 => return .{
                    .size = if (self.ptr_size == 4) 12 else 16,
                    .alignment = if (self.ptr_size == 4) 4 else 16,
                },
                .fp128, .ppc_fp128 => return .{ .size = 16, .alignment = 16 },
            },
            .ptr => return .{ .size = self.ptr_size, .alignment = self.ptr_size },
            .array => |a| {
                const elem = try self.sizeAlignDepth(a.elem, depth + 1);
                const stride = alignUp(elem.size, elem.alignment);
                const total = std.math.mul(u64, a.count, stride) catch return error.BadType;
                if (total > std.math.maxInt(u32)) return error.BadType;
                return .{ .size = @intCast(total), .alignment = elem.alignment };
            },
            .vector => |v| {
                const elem = try self.sizeAlignDepth(v.elem, depth + 1);
                const total = std.math.mul(u64, v.count, elem.size) catch return error.BadType;
                if (total > std.math.maxInt(u32)) return error.BadType;
                const size: u32 = @intCast(total);
                return .{ .size = size, .alignment = if (size <= 8) 8 else 16 };
            },
            .struct_ => |s| {
                if (s.is_opaque) return error.BadType;
                var off: u32 = 0;
                var max_align: u32 = 1;
                for (s.fields) |field| {
                    const fa = try self.sizeAlignDepth(field, depth + 1);
                    if (!s.is_packed) off = alignUp(off, fa.alignment);
                    off = std.math.add(u32, off, fa.size) catch return error.BadType;
                    if (!s.is_packed and fa.alignment > max_align) max_align = fa.alignment;
                }
                return .{ .size = if (s.is_packed) off else alignUp(off, max_align), .alignment = max_align };
            },
            .named => |n| {
                const target = self.named.get(n.name) orelse return error.BadType;
                return self.sizeAlignDepth(target, depth + 1);
            },
            else => return error.BadType,
        }
    }

    /// Store size: integers use their byte width (i24 -> 3), everything else
    /// uses the aligned size.
    fn storeSize(self: *const Layout, ty: *const ast.Type) anyerror!u32 {
        switch (ty.*) {
            .int => |t| return @max(1, (t.bits + 7) / 8),
            else => return (try self.sizeAlign(ty)).size,
        }
    }

    fn structLayout(self: *const Layout, ty: *const ast.Type) anyerror!StructLayout {
        const s = self.asStruct(ty) orelse return error.BadType;
        var offsets = std.ArrayList(u32).init(self.allocator);
        var off: u32 = 0;
        var max_align: u32 = 1;
        for (s.fields) |field| {
            const fa = try self.sizeAlign(field);
            if (!s.is_packed) off = alignUp(off, fa.alignment);
            try offsets.append(off);
            off = std.math.add(u32, off, fa.size) catch return error.BadType;
            if (!s.is_packed and fa.alignment > max_align) max_align = fa.alignment;
        }
        const size = if (s.is_packed) off else alignUp(off, max_align);
        return .{ .offsets = try offsets.toOwnedSlice(), .size = size, .alignment = max_align };
    }
};

// --------------------------------------------------------------------- globals

const Reloc = struct { offset: u32, target: []const u8, addend: i64 };

const Globals = struct {
    /// `@name` (without the sigil) -> offset into `data`.
    map: std.StringHashMap(u32),
    /// `@name` -> index into `external_names`.
    external: std.StringHashMap(u16),
    external_names: [][]const u8,
    data: []u8,
    relocs: []const Reloc,
};

/// Decode an LLVM C string body (`hi\00`) into `out`, stopping at the first
/// unescaped quote.
fn decodeCString(raw: []const u8, out: []u8) void {
    var i: usize = 0;
    var o: usize = 0;
    while (i < raw.len and o < out.len) {
        const ch = raw[i];
        if (ch == '"') break;
        if (ch == '\\' and i + 1 < raw.len) {
            if (i + 2 < raw.len and std.ascii.isHex(raw[i + 1]) and std.ascii.isHex(raw[i + 2])) {
                const hi = std.fmt.charToDigit(raw[i + 1], 16) catch 0;
                const lo = std.fmt.charToDigit(raw[i + 2], 16) catch 0;
                out[o] = @intCast(hi * 16 + lo);
                i += 3;
                o += 1;
                continue;
            }
            i += 1;
            out[o] = switch (raw[i]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                '"' => '"',
                '0' => 0,
                else => raw[i],
            };
            i += 1;
            o += 1;
            continue;
        }
        out[o] = ch;
        i += 1;
        o += 1;
    }
}

fn writeIntLE(out: []u8, value: u64, size: u32) void {
    var i: u32 = 0;
    while (i < size and i < out.len) : (i += 1) {
        const shift = i * 8;
        if (shift >= @bitSizeOf(u64)) break;
        out[i] = @truncate(value >> @intCast(shift));
    }
}

/// Walk a constant expression and return the *last* global it mentions, which
/// is what the legacy `lastAt` text scan resolves for non-GEP pointer
/// constants (`bitcast (ptr @x to ptr)`, `select (i1 ..., ptr @a, ptr @b)`).
fn lastGlobalRef(expr: *const ast.ConstExpr) ?[]const u8 {
    switch (expr.*) {
        .gep => |g| return valueGlobalRef(g.ptr.val),
        .cast => |c| return valueGlobalRef(c.value),
        // Text order: the right-hand operand is printed last.
        .binary => |b| return valueGlobalRef(b.rhs) orelse valueGlobalRef(b.lhs),
        .icmp => |c| return valueGlobalRef(c.rhs) orelse valueGlobalRef(c.lhs),
        .fcmp => |c| return valueGlobalRef(c.rhs) orelse valueGlobalRef(c.lhs),
        .select => |s| return valueGlobalRef(s.if_false.val) orelse
            valueGlobalRef(s.if_true.val) orelse valueGlobalRef(s.cond.val),
        .extractvalue => |e| return valueGlobalRef(e.aggregate.val),
        .fneg => |u| return valueGlobalRef(u.value),
    }
}

fn valueGlobalRef(value: ast.Value) ?[]const u8 {
    return switch (value) {
        .global => |n| n.name,
        .const_expr => |expr| lastGlobalRef(expr),
        else => null,
    };
}

const GlobalWriter = struct {
    allocator: Allocator,
    layout: *const Layout,
    ptr_size: u32,
    mode: GepConstMode,

    /// Write the constant image of `value` (of type `ty`) into `out`.
    /// `out` is the object's whole storage; nested aggregates recurse with the
    /// corresponding sub-slice. Unrepresentable pieces are left zeroed, exactly
    /// like the legacy `parseConstant`.
    fn writeConstant(self: *GlobalWriter, ty: *const ast.Type, value: ast.Value, out: []u8) anyerror!void {
        if (out.len == 0) return;
        switch (value) {
            .zeroinitializer, .undef, .poison, .null_ => return,
            .aggregate => |agg| {
                if (self.layout.asStruct(ty)) |st| {
                    const layout = try self.layout.structLayout(ty);
                    for (agg.elems, 0..) |elem, idx| {
                        if (idx >= st.fields.len or idx >= layout.offsets.len) break;
                        const base = layout.offsets[idx];
                        if (base >= out.len) break;
                        try self.writeConstant(elem.ty, elem.val, out[base..]);
                    }
                    return;
                }
                switch (ty.*) {
                    .array => |a| {
                        const elem_sa = try self.layout.sizeAlign(a.elem);
                        for (agg.elems, 0..) |elem, idx| {
                            const base = std.math.mul(u64, idx, elem_sa.size) catch return;
                            if (base >= out.len) break;
                            try self.writeConstant(elem.ty, elem.val, out[@intCast(base)..]);
                        }
                        return;
                    },
                    // compat: the legacy constant writer has no vector case and
                    // leaves vector initialisers zeroed. Preserved so the CIB
                    // stays comparable; recorded as a gap in the phase report.
                    .vector => return,
                    else => return,
                }
            },
            .string => |s| {
                // Only arrays of i8 carry C strings in this subset.
                switch (ty.*) {
                    .array => decodeCString(s.raw, out),
                    else => {},
                }
                return;
            },
            .int => |lit| {
                const bits = intBitsOf(ty) orelse return;
                const size: u32 = @max(1, (bits + 7) / 8);
                // compat: legacy writeIntLE caps the value at 8 bytes, so i128
                // initialisers only fill their low 8 bytes.
                var v: u64 = 0;
                if (intToI64(lit)) |n| {
                    v = @bitCast(n);
                } else if (!lit.overflow and lit.magnitude <= std.math.maxInt(u64)) {
                    v = @intCast(lit.magnitude);
                }
                writeIntLE(out, v, size);
                return;
            },
            .float => |lit| {
                const kind = floatKindOf(ty) orelse return;
                switch (kind) {
                    .float, .double, .x86_fp80 => _ = lit.writeLeBytes(out),
                    // compat: fp128 initialisers are left zeroed by the legacy
                    // writer (it has no fp128 case). Preserved.
                    .fp128, .ppc_fp128, .half, .bfloat => {},
                }
                return;
            },
            .const_expr => |expr| {
                switch (expr.*) {
                    .cast => |c| {
                        // `ptr inttoptr (i64 N to ptr)` is the only pointer
                        // constant expression the legacy writer materialises.
                        if (c.op == .inttoptr and intBitsOf(c.src) != null) {
                            const lit = switch (c.value) {
                                .int => |l| l,
                                else => return,
                            };
                            const n = intToI64(lit) orelse return;
                            writeIntLE(out, @bitCast(n), self.ptr_size);
                        }
                        return;
                    },
                    else => return,
                }
            },
            // `local`/`global`/`metadata`/`asm`/`blockaddress` never appear as
            // global initialiser leaves (globals produce relocations instead).
            else => return,
        }
    }

    /// Record pointer relocations for `value`. Mirrors the legacy
    /// `collectRelocs`.
    fn collectRelocs(self: *GlobalWriter, ty: *const ast.Type, value: ast.Value, base: u32, out: *std.ArrayList(Reloc)) anyerror!void {
        switch (ty.*) {
            .ptr => {
                switch (value) {
                    .const_expr => |expr| switch (expr.*) {
                        .gep => |g| {
                            if (gepBaseName(g)) |name| {
                                const addend = self.gepAddend(g) orelse 0;
                                try out.append(.{
                                    .offset = base,
                                    .target = try std.fmt.allocPrint(self.allocator, "@{s}", .{name}),
                                    .addend = addend,
                                });
                            }
                            return;
                        },
                        // compat: any other pointer constant expression that
                        // mentions a global becomes a zero-addend relocation to
                        // the last mentioned symbol (legacy `lastAt`).
                        else => if (lastGlobalRef(expr)) |name| {
                            try out.append(.{
                                .offset = base,
                                .target = try std.fmt.allocPrint(self.allocator, "@{s}", .{name}),
                                .addend = 0,
                            });
                        },
                    },
                    .global => |n| try out.append(.{
                        .offset = base,
                        .target = try std.fmt.allocPrint(self.allocator, "@{s}", .{n.name}),
                        .addend = 0,
                    }),
                    else => {},
                }
                return;
            },
            else => {},
        }

        if (self.layout.asStruct(ty)) |st| {
            switch (value) {
                .aggregate => |agg| {
                    const layout = try self.layout.structLayout(ty);
                    for (agg.elems, 0..) |elem, idx| {
                        if (idx >= st.fields.len or idx >= layout.offsets.len) break;
                        try self.collectRelocs(elem.ty, elem.val, base + layout.offsets[idx], out);
                    }
                },
                else => {},
            }
            return;
        }
        switch (ty.*) {
            .array => |a| {
                switch (value) {
                    .aggregate => |agg| {
                        const elem_sa = try self.layout.sizeAlign(a.elem);
                        for (agg.elems, 0..) |elem, idx| {
                            const off = std.math.mul(u64, idx, elem_sa.size) catch break;
                            if (off > std.math.maxInt(u32)) break;
                            try self.collectRelocs(elem.ty, elem.val, base + @as(u32, @intCast(off)), out);
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    /// Fold a constant `getelementptr` into an addend relative to its base
    /// symbol. In `GepConstMode.legacy` only the first index is used (the
    /// historical behaviour); `correct` walks every index.
    fn gepAddend(self: *GlobalWriter, g: ast.Gep) ?i64 {
        var current = g.src;
        var offset: i64 = 0;
        const first = self.layout.sizeAlign(current) catch return null;
        var pos: usize = 0;
        for (g.indices) |index| {
            const lit = switch (index.val) {
                .int => |l| l,
                // A non-constant index cannot appear in a constant expression.
                else => break,
            };
            const idx = intToI64(lit) orelse break;
            if (pos == 0) {
                offset +%= idx *% @as(i64, first.size);
                pos += 1;
                if (self.mode == .legacy) break;
                continue;
            }
            switch (current.*) {
                .array => |a| {
                    const elem = self.layout.sizeAlign(a.elem) catch break;
                    offset +%= idx *% @as(i64, elem.size);
                    current = a.elem;
                },
                .vector => |v| {
                    const elem = self.layout.sizeAlign(v.elem) catch break;
                    offset +%= idx *% @as(i64, elem.size);
                    current = v.elem;
                },
                .struct_, .named => {
                    const layout = self.layout.structLayout(current) catch break;
                    if (idx < 0 or idx >= layout.offsets.len) break;
                    offset +%= @as(i64, layout.offsets[@intCast(idx)]);
                    const st = self.layout.asStruct(current) orelse break;
                    current = st.fields[@intCast(idx)];
                },
                else => break,
            }
            pos += 1;
        }
        return offset;
    }
};

/// Base symbol of a constant GEP chain (the innermost `@global`).
fn gepBaseName(g: ast.Gep) ?[]const u8 {
    return valueGlobalRef(g.ptr.val);
}

fn buildGlobals(allocator: Allocator, module: *const ast.Module, layout: *const Layout, ptr_size: u32, mode: GepConstMode) !Globals {
    const Spec = struct {
        global: *const ast.Global,
        offset: u32,
        sa: SizeAlign,
    };

    var map = std.StringHashMap(u32).init(allocator);
    var external = std.StringHashMap(u16).init(allocator);
    var external_names = std.ArrayList([]const u8).init(allocator);
    var data = std.ArrayList(u8).init(allocator);

    var specs = std.ArrayList(Spec).init(allocator);
    for (module.globals) |*g| {
        // LLVM linker metadata (`@llvm.compiler.used`, `@llvm.used`,
        // `@llvm.global_ctors`, ...) has no VM storage. The legacy parser
        // ignores these via its text heuristics; keep the data image free of
        // them in the AST path too.
        if (std.mem.startsWith(u8, g.name, "llvm.") or std.mem.startsWith(u8, g.name, ".llvm.")) continue;
        if (g.init == null) {
            // `@x = external global i32`: an unresolved external symbol, no
            // storage. (Legacy also treats `external thread_local` this way.)
            if (external_names.items.len <= std.math.maxInt(u16)) {
                const key = try std.fmt.allocPrint(allocator, "@{s}", .{g.name});
                const idx: u16 = @intCast(external_names.items.len);
                try external.put(key, idx);
                try external_names.append(key);
            }
            continue;
        }
        const sa = layout.sizeAlign(g.ty) catch continue;
        const explicit: u32 = g.alignment orelse 0;
        const want_align = @max(@max(sa.alignment, explicit), 1);
        const off = alignUp(@intCast(data.items.len), want_align);
        while (data.items.len < off) try data.append(0);
        try map.put(g.name, off);
        var i: u32 = 0;
        while (i < sa.size) : (i += 1) try data.append(0);
        try specs.append(.{ .global = g, .offset = off, .sa = sa });
    }

    var writer = GlobalWriter{ .allocator = allocator, .layout = layout, .ptr_size = ptr_size, .mode = mode };
    for (specs.items) |spec| {
        const init = spec.global.init.?;
        const start = spec.offset;
        const end = start + spec.sa.size;
        try writer.writeConstant(spec.global.ty, init, data.items[start..end]);
    }

    var relocs = std.ArrayList(Reloc).init(allocator);
    for (specs.items) |spec| {
        try writer.collectRelocs(spec.global.ty, spec.global.init.?, spec.offset, &relocs);
    }

    while (data.items.len % 8 != 0) try data.append(0);

    return .{
        .map = map,
        .external = external,
        .external_names = try external_names.toOwnedSlice(),
        .data = try data.toOwnedSlice(),
        .relocs = try relocs.toOwnedSlice(),
    };
}

// --------------------------------------------------------------------- context

const ParamInfo = struct {
    name: []const u8,
    ty: *const ast.Type,
    attrs: []const ast.Attr,
};

const CallbackEntry = struct { slot: u16, func_index: u16, plan_index: u16 };

const CallbackTable = struct {
    by_func: std.StringHashMap(CallbackEntry),
    next_slot: u16 = 0,
};

/// Structural equality of two CIPL plans: every field `main.zig` serializes is
/// compared, including the symbol `name` (plans for different imports must
/// never be merged) and the calling convention.
fn plansEqual(a: abi.Plan, b: abi.Plan) bool {
    if (!eql(a.name, b.name)) return false;
    if (a.args.len != b.args.len or a.ret_locs.len != b.ret_locs.len) return false;
    if (a.stack_size != b.stack_size or a.sret != b.sret) return false;
    if (a.sse_count != b.sse_count or a.ret_size != b.ret_size or a.conv != b.conv) return false;
    for (a.args, b.args) |x, y| {
        if (x.size != y.size or x.alignment != y.alignment or x.is_struct != y.is_struct) return false;
        if (x.locs.len != y.locs.len) return false;
        for (x.locs, y.locs) |l, m| {
            if (l.kind != m.kind or l.index != m.index or l.size != m.size or l.offset != m.offset) return false;
        }
    }
    for (a.ret_locs, b.ret_locs) |l, m| {
        if (l.kind != m.kind or l.index != m.index or l.size != m.size or l.offset != m.offset) return false;
    }
    return true;
}

const Patch = struct { pos: u32, label: []const u8 };

const PhiAssign = struct {
    pred: []const u8,
    result: []const u8,
    ty: *const ast.Type,
    value: ast.Value,
};

const Context = struct {
    allocator: Allocator,
    module: *const ast.Module,
    layout: Layout,
    globals: Globals,
    /// Declarations keyed by name (no `@`). Insertion order matches the legacy
    /// `parseDecls` map so external-symbol numbering is identical.
    decls: std.StringHashMap(*const ast.Decl),
    func_indices: std.StringHashMap(u16),
    /// Named parameters only (legacy drops unnamed parameters), per function.
    func_params: []const []const ParamInfo,
    functions: []const abi.Function,
    plans: std.ArrayList(abi.Plan),
    callbacks: CallbackTable,
    abi: u8,
    ptr_size: u32,
    opts: Options,

    fn init(allocator: Allocator, module: *const ast.Module, abi_id: u8, ptr_size: u32, opts: Options) !Context {
        // CIVM holds function indices/plan indices/parameter counts in u16.
        // Reject modules that cannot be addressed before any narrowing cast;
        // `main.zig` additionally enforces the runtime caps (512 functions,
        // 64 args/plan, ...).
        if (module.functions.len > std.math.maxInt(u16)) return error.TooManyFunctions;
        const layout = try Layout.init(allocator, module, ptr_size);
        var globals = try buildGlobals(allocator, module, &layout, ptr_size, opts.gep_const);

        var decls = std.StringHashMap(*const ast.Decl).init(allocator);
        for (module.declares) |*d| try decls.put(d.name, d);

        var func_indices = std.StringHashMap(u16).init(allocator);
        for (module.functions, 0..) |f, idx| try func_indices.put(f.name, @intCast(idx));

        var func_params = try allocator.alloc([]const ParamInfo, module.functions.len);
        for (module.functions, 0..) |f, idx| {
            if (f.sig.params.len > std.math.maxInt(u16)) return error.TooManyArgs;
            var params = std.ArrayList(ParamInfo).init(allocator);
            for (f.sig.params) |param| {
                const name = param.name orelse continue;
                try params.append(.{ .name = name.name, .ty = param.ty, .attrs = param.attrs });
            }
            func_params[idx] = try params.toOwnedSlice();
        }

        // External symbols, in the legacy order: external globals, then
        // relocation targets, then declarations (StringHashMap iteration order).
        var external_names = std.ArrayList([]const u8).init(allocator);
        try external_names.appendSlice(globals.external_names);
        for (globals.relocs) |reloc| {
            const target = reloc.target;
            if (target.len < 2) continue;
            const name = target[1..];
            if (globals.map.contains(name)) continue;
            if (func_indices.contains(name)) continue;
            if (isCallbackBuiltin(name)) continue;
            if (globals.external.contains(target)) continue;
            if (external_names.items.len > std.math.maxInt(u16)) continue;
            const idx: u16 = @intCast(external_names.items.len);
            try globals.external.put(target, idx);
            try external_names.append(target);
        }
        var decl_it = decls.keyIterator();
        while (decl_it.next()) |decl_name_ptr| {
            const decl_name = decl_name_ptr.*;
            if (startsWith(decl_name, "llvm.")) continue;
            if (func_indices.contains(decl_name)) continue;
            // The forced-include callback header declares these builtins in
            // every translation unit that references them; they lower to
            // opcodes, not CIPI imports.
            if (isCallbackBuiltin(decl_name)) continue;
            const key = try std.fmt.allocPrint(allocator, "@{s}", .{decl_name});
            if (globals.external.contains(key)) continue;
            if (external_names.items.len > std.math.maxInt(u16)) continue;
            const idx: u16 = @intCast(external_names.items.len);
            try globals.external.put(key, idx);
            try external_names.append(key);
        }
        globals.external_names = try external_names.toOwnedSlice();

        return .{
            .allocator = allocator,
            .module = module,
            .layout = layout,
            .globals = globals,
            .decls = decls,
            .func_indices = func_indices,
            .func_params = func_params,
            .functions = &.{},
            .plans = std.ArrayList(abi.Plan).init(allocator),
            .callbacks = .{ .by_func = std.StringHashMap(CallbackEntry).init(allocator) },
            .abi = abi_id,
            .ptr_size = ptr_size,
            .opts = opts,
        };
    }

    /// Return the index of an already-appended plan that is byte-identical to
    /// `plan`, or append it and return the new index. Dedup is by full content
    /// (`plansEqual`), so distinct symbol names or ABI layouts never merge.
    fn internPlan(self: *Context, plan: abi.Plan) !u16 {
        for (self.plans.items, 0..) |existing, index| {
            if (plansEqual(existing, plan)) return @intCast(index);
        }
        if (self.plans.items.len > std.math.maxInt(u16)) return error.TooManyPlans;
        const index: u16 = @intCast(self.plans.items.len);
        try self.plans.append(plan);
        return index;
    }
};

// --------------------------------------------------------------------- compile

/// Lower a parsed module into CIVM functions, CIPL plans and the external
/// symbol list.
pub fn compile(allocator: Allocator, module: *const ast.Module, abi_id: u8, ptr_size: u32) anyerror!abi.CompileResult {
    return compileWithOptions(allocator, module, abi_id, ptr_size, .{});
}

pub fn compileWithOptions(allocator: Allocator, module: *const ast.Module, abi_id: u8, ptr_size: u32, opts: Options) anyerror!abi.CompileResult {
    var ctx = try Context.init(allocator, module, abi_id, ptr_size, opts);
    var functions = try allocator.alloc(abi.Function, module.functions.len);
    for (module.functions, 0..) |_, idx| {
        functions[idx] = try lowerFunction(&ctx, idx);
    }
    ctx.functions = functions;
    return .{
        .functions = functions,
        .plans = try ctx.plans.toOwnedSlice(),
        .external_data = ctx.globals.external_names,
    };
}

fn lowerFunction(ctx: *Context, func_index: usize) !abi.Function {
    const f = &ctx.module.functions[func_index];
    const params = ctx.func_params[func_index];

    var param_names = try ctx.allocator.alloc([]const u8, params.len);
    var param_types = try ctx.allocator.alloc([]const u8, params.len);
    var param_attrs = try ctx.allocator.alloc([]const u8, params.len);
    for (params, 0..) |p, i| {
        param_names[i] = p.name;
        param_types[i] = try renderType(ctx.allocator, p.ty);
        param_attrs[i] = param_types[i];
    }

    var out = abi.Function{
        .name = f.name,
        .ret = try renderType(ctx.allocator, f.sig.ret),
        .param_count = @intCast(params.len),
        .param_names = param_names,
        .param_types = param_types,
        .param_attrs = param_attrs,
        .is_varargs = f.sig.is_varargs,
        .local_count = @intCast(params.len),
        .code = std.ArrayList(u8).init(ctx.allocator),
    };

    var lw = Lowerer{
        .ctx = ctx,
        .allocator = ctx.allocator,
        .func = &out,
        .params = params,
        .slots = std.StringHashMap(u16).init(ctx.allocator),
        .next_slot = @intCast(params.len),
        .labels = std.StringHashMap(u32).init(ctx.allocator),
        .patches = std.ArrayList(Patch).init(ctx.allocator),
        .phi_assigns = std.ArrayList(PhiAssign).init(ctx.allocator),
    };
    for (params, 0..) |p, slot| try lw.slots.put(p.name, @intCast(slot));
    try lw.run(f);
    return out;
}

// --------------------------------------------------------------------- lowerer

const Lowerer = struct {
    ctx: *Context,
    allocator: Allocator,
    func: *abi.Function,
    params: []const ParamInfo,
    slots: std.StringHashMap(u16),
    next_slot: u16,
    labels: std.StringHashMap(u32),
    patches: std.ArrayList(Patch),
    phi_assigns: std.ArrayList(PhiAssign),
    current_block: []const u8 = "entry",
    select_id: u32 = 0,

    // --------------------------------------------------------------- emitters

    fn emitU8(self: *Lowerer, v: u8) !void {
        try self.func.code.append(v);
    }
    fn emitU16(self: *Lowerer, v: u16) !void {
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, v, .little);
        try self.func.code.appendSlice(&buf);
    }
    fn emitU32(self: *Lowerer, v: u32) !void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, v, .little);
        try self.func.code.appendSlice(&buf);
    }
    fn emitI64(self: *Lowerer, v: i64) !void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, @bitCast(v), .little);
        try self.func.code.appendSlice(&buf);
    }
    fn emitConst(self: *Lowerer, v: i64) !void {
        try self.emitU8(op.OP_LOAD_CONST_I64);
        try self.emitI64(v);
    }
    fn emitLoadSlot(self: *Lowerer, slot: u16) !void {
        try self.emitU8(op.OP_LOAD_LOCAL);
        try self.emitU16(slot);
    }
    fn emitStoreSlot(self: *Lowerer, slot: u16) !void {
        try self.emitU8(op.OP_STORE_LOCAL);
        try self.emitU16(slot);
    }
    fn emitF80Const(self: *Lowerer, lit: ast.FloatLiteral) !void {
        var buf = [_]u8{0} ** 10;
        _ = lit.writeLeBytes(&buf);
        try self.emitU8(op.OP_F80_CONST);
        try self.func.code.appendSlice(&buf);
    }
    fn emitF128Const(self: *Lowerer, lit: ast.FloatLiteral) !void {
        var buf = [_]u8{0} ** 16;
        _ = lit.writeLeBytes(&buf);
        try self.emitU8(op.OP_F128_CONST);
        try self.func.code.appendSlice(&buf);
    }

    fn slotFor(self: *Lowerer, name: []const u8) !u16 {
        if (self.slots.get(name)) |s| return s;
        const s = self.next_slot;
        self.next_slot += 1;
        try self.slots.put(name, s);
        if (self.next_slot > self.func.local_count) self.func.local_count = self.next_slot;
        return s;
    }

    fn normalizeInt(self: *Lowerer, bits: u32, signed: bool) !void {
        if (bits == 0 or bits >= 64) return;
        try self.emitConst(maskFor(bits));
        try self.emitU8(op.OP_AND);
        if (signed) {
            const shift: i64 = @intCast(64 - bits);
            try self.emitConst(shift);
            try self.emitU8(op.OP_SHL);
            try self.emitConst(shift);
            try self.emitU8(op.OP_SHR_S);
        }
    }

    // ----------------------------------------------------------- value emitters

    fn emitGlobalRef(self: *Lowerer, name: []const u8) !void {
        if (self.ctx.globals.map.get(name)) |off| {
            try self.emitU8(op.OP_ADDR_CONST);
            try self.emitU32(off);
            return;
        }
        if (self.ctx.func_indices.get(name)) |idx| {
            try self.emitU8(op.OP_FUNC_ADDR);
            try self.emitU16(idx);
            return;
        }
        const key = try std.fmt.allocPrint(self.allocator, "@{s}", .{name});
        if (self.ctx.globals.external.get(key)) |idx| {
            try self.emitU8(op.OP_ADDR_EXTERN);
            try self.emitU16(idx);
            return;
        }
        // compat: the legacy lowerer folds unresolved `@symbol` operands to 0.
        try self.emitConst(0);
    }

    fn emitValue(self: *Lowerer, tv: ast.TypedValue) !void {
        return self.emitValueOf(tv.ty, tv.val);
    }

    /// Emit an operand. `ty` is only needed to pick a representation for
    /// literal constants (float width); pass null when the instruction type
    /// already fixed it.
    fn emitValueOf(self: *Lowerer, ty: ?*const ast.Type, value: ast.Value) anyerror!void {
        switch (value) {
            .local => |n| try self.emitLoadSlot(try self.slotFor(n.name)),
            .global => |n| try self.emitGlobalRef(n.name),
            .int => |lit| {
                const v = intToI64(lit) orelse return error.UnsupportedOperand;
                try self.emitConst(v);
            },
            .float => |lit| {
                const t = ty orelse return error.UnsupportedOperand;
                try self.emitFloatConstant(t, lit);
            },
            .null_, .undef, .poison, .zeroinitializer => try self.emitConst(0),
            .const_expr => |expr| try self.emitConstExpr(expr),
            else => return error.UnsupportedOperand,
        }
    }

    /// Emit a floating point constant. Mirrors the legacy `emitFloatOperand`:
    /// `x86_fp80`/`fp128` constants become `OP_F80_CONST`/`OP_F128_CONST`
    /// blobs, float/double constants become raw bit patterns in a local.
    fn emitFloatConstant(self: *Lowerer, ty: *const ast.Type, lit: ast.FloatLiteral) anyerror!void {
        const kind = floatKindOf(ty) orelse return error.UnsupportedOperand;
        switch (kind) {
            .x86_fp80 => try self.emitF80Const(lit),
            .fp128 => try self.emitF128Const(lit),
            .float => {
                // clang prints float constants as 8 hex digits, but accept a
                // 64-bit spelling the way the legacy path does.
                if (lit.width == 64) {
                    const d: f64 = @bitCast(@as(u64, @truncate(lit.bits)));
                    const f: f32 = @floatCast(d);
                    const f32_bits: u32 = @bitCast(f);
                    const wide: u64 = f32_bits;
                    try self.emitConst(@bitCast(wide));
                } else {
                    const f32_bits: u32 = @truncate(lit.bits);
                    const wide: u64 = f32_bits;
                    try self.emitConst(@bitCast(wide));
                }
            },
            .double => {
                const bits: u64 = @truncate(lit.bits);
                try self.emitConst(@bitCast(bits));
            },
            else => return error.UnsupportedOperand,
        }
    }

    fn emitFloatValue(self: *Lowerer, ty: *const ast.Type, value: ast.Value) anyerror!void {
        const kind = floatKindOf(ty) orelse return self.emitValueOf(ty, value);
        switch (kind) {
            .x86_fp80, .fp128 => try self.emitValueOf(ty, value),
            .float, .double => switch (value) {
                .float => |lit| try self.emitFloatConstant(ty, lit),
                // compat: legacy falls back to a plain operand for anything
                // that is not a literal (locals, globals, constant exprs).
                else => try self.emitValueOf(ty, value),
            },
            else => try self.emitValueOf(ty, value),
        }
    }

    fn emitConstExpr(self: *Lowerer, expr: *const ast.ConstExpr) anyerror!void {
        switch (expr.*) {
            .gep => |g| try self.emitGep(g),
            .cast => |c| try self.emitConstCast(c),
            .binary => |b| try self.emitConstBinary(b),
            .icmp => |c| try self.emitIcmp(c.pred, c.ty, c.lhs, c.rhs),
            .fcmp => |c| try self.emitFcmp(c.pred, c.ty, c.lhs, c.rhs),
            // Never produced by clang for C in this subset; the legacy string
            // path cannot lower these either.
            .select, .extractvalue, .fneg => return error.UnsupportedOperand,
        }
    }

    fn emitConstCast(self: *Lowerer, c: ast.CastExpr) anyerror!void {
        switch (c.op) {
            .ptrtoint, .inttoptr, .bitcast, .addrspacecast => try self.emitValueOf(c.src, c.value),
            .trunc => {
                try self.emitValueOf(c.src, c.value);
                try self.normalizeInt(intBitsOf(c.dst) orelse 64, true);
            },
            .zext => {
                try self.emitValueOf(c.src, c.value);
                if (intBitsOf(c.src)) |bits| {
                    if (bits < 64) {
                        try self.emitConst(maskFor(bits));
                        try self.emitU8(op.OP_AND);
                    }
                }
                try self.normalizeInt(intBitsOf(c.dst) orelse 64, true);
            },
            .sext => {
                try self.emitValueOf(c.src, c.value);
                if (intBitsOf(c.src)) |bits| {
                    if (bits < 64) {
                        const shift: i64 = @intCast(64 - bits);
                        try self.emitConst(shift);
                        try self.emitU8(op.OP_SHL);
                        try self.emitConst(shift);
                        try self.emitU8(op.OP_SHR_S);
                    }
                }
                try self.normalizeInt(intBitsOf(c.dst) orelse 64, true);
            },
            else => return error.UnsupportedOperand,
        }
    }

    fn emitConstBinary(self: *Lowerer, b: ast.BinaryExpr) anyerror!void {
        const opcode: u8 = switch (b.op) {
            .add => op.OP_ADD,
            .sub => op.OP_SUB,
            .mul => op.OP_MUL,
            .shl => op.OP_SHL,
            .lshr => op.OP_SHR_U,
            .ashr => op.OP_SHR_S,
            .and_ => op.OP_AND,
            .or_ => op.OP_OR,
            .xor => op.OP_XOR,
            else => return error.UnsupportedOperand,
        };
        try self.emitValueOf(b.ty, b.lhs);
        try self.emitValueOf(b.ty, b.rhs);
        try self.emitU8(opcode);
    }

    // ------------------------------------------------------------ integer cmp

    fn emitIcmp(self: *Lowerer, pred: ast.IcmpPred, ty: *const ast.Type, lhs: ast.Value, rhs: ast.Value) anyerror!void {
        const bits: u32 = intBitsOf(ty) orelse (self.ctx.ptr_size * 8);
        const signed = switch (pred) {
            .slt, .sle, .sgt, .sge => true,
            else => false,
        };
        var invert = false;
        switch (pred) {
            .eq, .ne => {
                try self.emitIntOperand(lhs, bits, false);
                try self.emitIntOperand(rhs, bits, false);
                try self.emitU8(op.OP_CMP_EQ);
                invert = pred == .ne;
            },
            .slt, .ult => {
                try self.emitIntOperand(lhs, bits, signed);
                try self.emitIntOperand(rhs, bits, signed);
                try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
            },
            .sgt, .ugt => {
                try self.emitIntOperand(rhs, bits, signed);
                try self.emitIntOperand(lhs, bits, signed);
                try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
            },
            .sle, .ule => {
                try self.emitIntOperand(rhs, bits, signed);
                try self.emitIntOperand(lhs, bits, signed);
                try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
                invert = true;
            },
            .sge, .uge => {
                try self.emitIntOperand(lhs, bits, signed);
                try self.emitIntOperand(rhs, bits, signed);
                try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
                invert = true;
            },
        }
        if (invert) {
            try self.emitConst(1);
            try self.emitU8(op.OP_XOR);
        }
    }

    /// Same as the legacy `emitIntOperand`: operand followed by truncation to
    /// the instruction's integer width (and sign extension when signed).
    fn emitIntOperand(self: *Lowerer, value: ast.Value, bits: u32, signed: bool) anyerror!void {
        try self.emitValueOf(null, value);
        try self.normalizeInt(bits, signed);
    }

    // --------------------------------------------------------------- float cmp

    fn emitFcmp(self: *Lowerer, pred: ast.FcmpPred, ty: *const ast.Type, lhs: ast.Value, rhs: ast.Value) anyerror!void {
        const code: u8 = switch (pred) {
            .oeq => 0,
            .one => 1,
            .olt => 2,
            .ole => 3,
            .ogt => 4,
            .oge => 5,
            .ord => 6,
            .uno => 7,
            .ueq => 8,
            .ugt => 9,
            .uge => 10,
            .ult => 11,
            .ule => 12,
            .une => 13,
            // The runtime has no encoder for the always-false/true predicates
            // and the legacy path rejects them too.
            .false_, .true_ => return error.BadFcmp,
        };
        try self.emitFloatValue(ty, lhs);
        try self.emitFloatValue(ty, rhs);
        const kind = floatKindOf(ty) orelse return error.BadFcmp;
        try self.emitU8(switch (kind) {
            .x86_fp80 => op.OP_F80_CMP,
            .fp128 => op.OP_F128_CMP,
            .float => op.OP_FCMP32,
            else => op.OP_FCMP,
        });
        try self.emitU8(code);
    }

    // ------------------------------------------------------------------- GEP

    fn emitGep(self: *Lowerer, g: ast.Gep) anyerror!void {
        try self.emitValue(g.ptr);
        var current = g.src;
        for (g.indices, 0..) |index, pos| {
            if (pos == 0) {
                try self.emitIndexAdd(index, try self.typeSize(current));
                continue;
            }
            switch (current.*) {
                .array => |a| {
                    try self.emitIndexAdd(index, try self.typeSize(a.elem));
                    current = a.elem;
                },
                .vector => |v| {
                    // Only index 0 is meaningful for vectors; the legacy path
                    // rejects every vector GEP.
                    const zero = switch (index.val) {
                        .int => |lit| (intToI64(lit) orelse 1) == 0,
                        else => false,
                    };
                    if (!zero) return error.BadGep;
                    current = v.elem;
                },
                .struct_, .named => {
                    const s = self.ctx.layout.asStruct(current) orelse return error.BadGep;
                    const layout = self.ctx.layout.structLayout(current) catch return error.BadGep;
                    const idx = switch (index.val) {
                        .int => |lit| intToI64(lit) orelse return error.BadGep,
                        else => return error.BadGep,
                    };
                    if (idx < 0 or idx >= layout.offsets.len) return error.BadGep;
                    const off = layout.offsets[@intCast(idx)];
                    if (off != 0) {
                        try self.emitConst(off);
                        try self.emitU8(op.OP_ADD);
                    }
                    current = s.fields[@intCast(idx)];
                },
                else => return error.BadGep,
            }
        }
    }

    fn emitIndexAdd(self: *Lowerer, index: ast.TypedValue, step: u32) anyerror!void {
        if (step == 0) return;
        if (isTag(index.val, .int)) {
            const lit = index.val.int;
            const v = intToI64(lit) orelse return error.BadGep;
            const off = v *% @as(i64, step);
            if (off != 0) {
                try self.emitConst(off);
                try self.emitU8(op.OP_ADD);
            }
            return;
        }
        try self.emitValue(index);
        try self.emitConst(step);
        try self.emitU8(op.OP_MUL);
        try self.emitU8(op.OP_ADD);
    }

    fn typeSize(self: *Lowerer, ty: *const ast.Type) !u32 {
        return (try self.ctx.layout.sizeAlign(ty)).size;
    }
    fn typeStoreSize(self: *Lowerer, ty: *const ast.Type) !u32 {
        return self.ctx.layout.storeSize(ty);
    }
    /// Plan spelling: named aggregates are expanded so the ABI classifier can
    /// see their members (see `renderPlanType`).
    fn planType(self: *Lowerer, ty: *const ast.Type) ![]const u8 {
        return renderPlanType(self.allocator, &self.ctx.layout, ty);
    }

    // ------------------------------------------------------------ control flow

    fn jump(self: *Lowerer, opcode: u8, label: []const u8) !void {
        try self.emitU8(opcode);
        const pos: u32 = @intCast(self.func.code.items.len);
        try self.emitU32(0);
        try self.patches.append(.{ .pos = pos, .label = label });
    }

    fn emitPhiAssignments(self: *Lowerer, block: []const u8) !void {
        for (self.phi_assigns.items) |assign| {
            if (!eql(assign.pred, block)) continue;
            try self.emitValueOf(assign.ty, assign.value);
            try self.emitStoreSlot(try self.slotFor(assign.result));
        }
    }

    fn collectPhiAssignments(self: *Lowerer, f: *const ast.Function) !void {
        for (f.blocks) |block| {
            for (block.instructions) |instr| {
                switch (instr.op) {
                    .phi => |p| {
                        const res = instr.result orelse continue;
                        for (p.incoming) |incoming| {
                            try self.phi_assigns.append(.{
                                .pred = incoming.block.name,
                                .result = res.name,
                                .ty = p.ty,
                                .value = incoming.value,
                            });
                        }
                    },
                    else => {},
                }
            }
        }
    }

    // -------------------------------------------------------------------- body

    fn run(self: *Lowerer, f: *const ast.Function) anyerror!void {
        try self.emitGlobalsInstall();
        try self.emitWideFloatParamCopies();
        self.current_block = "entry";
        try self.collectPhiAssignments(f);

        for (f.blocks, 0..) |block, block_index| {
            if (block.label) |label| {
                self.current_block = label.name;
                try self.labels.put(label.name, @intCast(self.func.code.items.len));
            } else if (block_index == 0) {
                self.current_block = "entry";
            }
            for (block.instructions) |instr| {
                switch (instr.op) {
                    .br, .switch_, .ret, .unreachable_ => try self.emitPhiAssignments(self.current_block),
                    else => {},
                }
                try self.lowerInstr(instr);
            }
        }

        for (self.patches.items) |patch| {
            const target = self.labels.get(patch.label) orelse return error.UnknownLabel;
            var buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &buf, target, .little);
            @memcpy(self.func.code.items[patch.pos..][0..4], &buf);
        }
        self.func.local_count = self.next_slot;
    }

    /// `main` starts by installing the module's static data image.
    fn emitGlobalsInstall(self: *Lowerer) anyerror!void {
        if (!eql(self.func.name, "main") or self.ctx.globals.data.len == 0) return;
        const data = self.ctx.globals.data;
        try self.emitU8(op.OP_SET_MEM_TOP);
        try self.emitU32(@intCast(data.len));
        var off: usize = 0;
        while (off < data.len) : (off += 8) {
            var chunk: u64 = 0;
            var i: usize = 0;
            while (i < 8 and off + i < data.len) : (i += 1) {
                chunk |= @as(u64, data[off + i]) << @intCast(i * 8);
            }
            try self.emitConst(@bitCast(chunk));
            try self.emitU8(op.OP_ADDR_CONST);
            try self.emitU32(@intCast(off));
            try self.emitU8(op.OP_STORE_MEM);
            try self.emitU8(@intCast(@min(8, data.len - off)));
        }
        for (self.ctx.globals.relocs) |reloc| {
            const target = reloc.target;
            var handled = false;
            if (target.len > 1) {
                if (self.ctx.globals.map.get(target[1..])) |gofs| {
                    try self.emitU8(op.OP_ADDR_CONST);
                    try self.emitU32(gofs);
                    handled = true;
                } else if (self.ctx.func_indices.get(target[1..])) |fidx| {
                    try self.emitU8(op.OP_FUNC_ADDR);
                    try self.emitU16(fidx);
                    handled = true;
                }
            }
            if (!handled) {
                if (self.ctx.globals.external.get(target)) |eidx| {
                    try self.emitU8(op.OP_ADDR_EXTERN);
                    try self.emitU16(eidx);
                    handled = true;
                }
            }
            if (!handled) continue;
            if (reloc.addend != 0) {
                try self.emitConst(reloc.addend);
                try self.emitU8(op.OP_ADD);
            }
            try self.emitU8(op.OP_ADDR_CONST);
            try self.emitU32(reloc.offset);
            try self.emitU8(op.OP_STORE_MEM);
            try self.emitU8(@intCast(self.ctx.ptr_size));
        }
    }

    /// `x86_fp80`/`fp128` parameters are pointers to their 16-byte storage; make
    /// a private copy so the callee may store through the slot.
    fn emitWideFloatParamCopies(self: *Lowerer) anyerror!void {
        for (self.params) |param| {
            if (!isF80OrF128(param.ty)) continue;
            const slot = try self.slotFor(param.name);
            try self.emitU8(op.OP_ALLOCA);
            try self.emitU16(16);
            try self.emitU8(op.OP_DUP);
            try self.emitLoadSlot(slot);
            try self.emitConst(16);
            try self.emitU8(op.OP_MEMCPY);
            try self.emitStoreSlot(slot);
        }
    }

    // ------------------------------------------------------------- instructions

    fn lowerInstr(self: *Lowerer, instr: ast.Instruction) anyerror!void {
        switch (instr.op) {
            .alloca => |a| try self.lowerAlloca(instr, a),
            .load => |l| try self.lowerLoad(instr, l),
            .store => |s| try self.lowerStore(s),
            .gep => |g| {
                const res = instr.result orelse return error.NoResult;
                try self.emitGep(g);
                try self.emitStoreSlot(try self.slotFor(res.name));
            },
            .phi => {
                const res = instr.result orelse return error.NoResult;
                _ = try self.slotFor(res.name);
            },
            .br => |br| try self.lowerBr(br),
            .switch_ => |sw| try self.lowerSwitch(sw),
            .ret => |ret| try self.lowerRet(ret),
            .unreachable_ => try self.emitU8(op.OP_RET_VOID),
            .select => |sel| try self.lowerSelect(instr, sel),
            .extractvalue => |ev| try self.lowerExtractValue(instr, ev),
            .call => |call| try self.lowerCall(call, instr.result),
            .icmp => |c| {
                const res = instr.result orelse return error.NoResult;
                try self.emitIcmp(c.pred, c.ty, c.lhs, c.rhs);
                try self.emitStoreSlot(try self.slotFor(res.name));
            },
            .fcmp => |c| {
                const res = instr.result orelse return error.NoResult;
                try self.emitFcmp(c.pred, c.ty, c.lhs, c.rhs);
                try self.emitStoreSlot(try self.slotFor(res.name));
            },
            .fneg => |u| try self.lowerFneg(instr, u),
            .freeze => |u| {
                const res = instr.result orelse return error.NoResult;
                try self.emitValueOf(u.ty, u.value);
                try self.emitStoreSlot(try self.slotFor(res.name));
            },
            .binary => |b| try self.lowerBinary(instr, b),
            .cast => |c| try self.lowerCast(instr, c),
        }
    }

    fn lowerAlloca(self: *Lowerer, instr: ast.Instruction, a: ast.Alloca) anyerror!void {
        const res = instr.result orelse return error.NoResult;
        const alloc_align: u32 = a.alignment orelse 8;
        if (a.count) |count| {
            try self.emitValue(count);
            const size = try self.typeSize(a.ty);
            if (size != 1) {
                try self.emitConst(size);
                try self.emitU8(op.OP_MUL);
            }
            if (alloc_align > 8) {
                try self.emitU8(op.OP_ALLOCA_DYN_ALIGN);
                try self.emitU8(@intCast(alloc_align));
            } else {
                try self.emitU8(op.OP_ALLOCA_DYN);
            }
        } else {
            const size = try self.typeSize(a.ty);
            if (size > 0xFFFF) {
                try self.emitConst(size);
                if (alloc_align > 8) {
                    try self.emitU8(op.OP_ALLOCA_DYN_ALIGN);
                    try self.emitU8(@intCast(alloc_align));
                } else {
                    try self.emitU8(op.OP_ALLOCA_DYN);
                }
            } else if (alloc_align > 8) {
                try self.emitU8(op.OP_ALLOCA_ALIGNED);
                try self.emitU16(@intCast(size));
                try self.emitU8(@intCast(alloc_align));
            } else {
                try self.emitU8(op.OP_ALLOCA);
                try self.emitU16(@intCast(size));
            }
        }
        try self.emitStoreSlot(try self.slotFor(res.name));
    }

    fn lowerLoad(self: *Lowerer, instr: ast.Instruction, l: ast.Load) anyerror!void {
        const res = instr.result orelse return error.NoResult;
        const size = try self.typeStoreSize(l.ty);
        if (size == 0) return error.BadLoad;
        try self.emitValue(l.ptr);
        if (!(isF80OrF128(l.ty) or size > 8)) {
            try self.emitU8(op.OP_LOAD_MEM);
            try self.emitU8(@intCast(size));
        }
        try self.emitStoreSlot(try self.slotFor(res.name));
    }

    fn lowerStore(self: *Lowerer, s: ast.Store) anyerror!void {
        const size = try self.typeStoreSize(s.ty);
        if (size == 0) return error.BadStore;
        if (isF80OrF128(s.ty) or (size > 8 and isAggregateLike(s.ty))) {
            try self.emitValue(s.ptr);
            try self.emitValue(s.value);
            try self.emitConst(size);
            try self.emitU8(op.OP_MEMCPY);
            return;
        }
        if (size > 8) return error.BadStore;
        if (isPlainFloat(s.ty)) {
            try self.emitFloatValue(s.ty, s.value.val);
        } else {
            try self.emitValue(s.value);
        }
        try self.emitValue(s.ptr);
        try self.emitU8(op.OP_STORE_MEM);
        try self.emitU8(@intCast(size));
    }

    fn lowerBr(self: *Lowerer, br: ast.Br) anyerror!void {
        switch (br) {
            .unconditional => |u| try self.jump(op.OP_JMP, u.target.name),
            .conditional => |c| {
                switch (c.cond.val) {
                    .int => |lit| {
                        const v = intToI64(lit) orelse 0;
                        try self.jump(op.OP_JMP, if (v != 0) c.if_true.name else c.if_false.name);
                        return;
                    },
                    else => {},
                }
                try self.emitValue(c.cond);
                try self.jump(op.OP_JNZ, c.if_true.name);
                try self.jump(op.OP_JMP, c.if_false.name);
            },
        }
    }

    fn lowerSwitch(self: *Lowerer, sw: ast.Switch) anyerror!void {
        for (sw.cases) |case| {
            const val = switch (case.value.val) {
                .int => |lit| intToI64(lit) orelse 0,
                else => 0,
            };
            try self.emitValue(sw.cond);
            try self.emitConst(val);
            try self.emitU8(op.OP_CMP_EQ);
            try self.jump(op.OP_JNZ, case.target.name);
        }
        try self.jump(op.OP_JMP, sw.default.name);
    }

    fn lowerRet(self: *Lowerer, ret: ast.Ret) anyerror!void {
        switch (ret) {
            .void => try self.emitU8(op.OP_RET_VOID),
            .value => |v| {
                if (isPlainFloat(v.ty)) {
                    try self.emitFloatValue(v.ty, v.val);
                } else if (intBitsOf(v.ty)) |bits| {
                    try self.emitValue(v);
                    try self.normalizeInt(bits, true);
                } else {
                    try self.emitValue(v);
                }
                try self.emitU8(op.OP_RET);
            },
        }
    }

    fn lowerSelect(self: *Lowerer, instr: ast.Instruction, sel: ast.Select) anyerror!void {
        const res = instr.result orelse return error.NoResult;
        const n = self.select_id;
        self.select_id += 1;
        const else_label = try std.fmt.allocPrint(self.allocator, "__select_else_{d}", .{n});
        const end_label = try std.fmt.allocPrint(self.allocator, "__select_end_{d}", .{n});
        try self.emitValue(sel.cond);
        try self.jump(op.OP_JZ, else_label);
        try self.emitValue(sel.if_true);
        try self.jump(op.OP_JMP, end_label);
        try self.labels.put(else_label, @intCast(self.func.code.items.len));
        try self.emitValue(sel.if_false);
        try self.labels.put(end_label, @intCast(self.func.code.items.len));
        try self.emitStoreSlot(try self.slotFor(res.name));
    }

    fn lowerExtractValue(self: *Lowerer, instr: ast.Instruction, ev: ast.ExtractValue) anyerror!void {
        const res = instr.result orelse return error.NoResult;
        var current = ev.aggregate.ty;
        var offset: u32 = 0;
        for (ev.indices) |idx| {
            switch (current.*) {
                .struct_, .named => {
                    const s = self.ctx.layout.asStruct(current) orelse return error.BadExtract;
                    const layout = self.ctx.layout.structLayout(current) catch return error.BadExtract;
                    if (idx >= layout.offsets.len or idx >= s.fields.len) return error.BadExtract;
                    offset += layout.offsets[idx];
                    current = s.fields[idx];
                },
                .array => |a| {
                    const elem = try self.typeSize(a.elem);
                    offset += @as(u32, @intCast(idx)) * elem;
                    current = a.elem;
                },
                else => return error.BadExtract,
            }
        }
        try self.emitValue(ev.aggregate);
        if (offset != 0) {
            try self.emitConst(offset);
            try self.emitU8(op.OP_ADD);
        }
        try self.emitU8(op.OP_LOAD_MEM);
        try self.emitU8(@intCast(try self.typeStoreSize(current)));
        try self.emitStoreSlot(try self.slotFor(res.name));
    }

    fn lowerFneg(self: *Lowerer, instr: ast.Instruction, u: ast.Unary) anyerror!void {
        const res = instr.result orelse return error.NoResult;
        const kind = floatKindOf(u.ty) orelse return error.BadFloat;
        switch (kind) {
            .x86_fp80 => {
                try self.emitValueOf(u.ty, u.value);
                try self.emitU8(op.OP_F80_NEG);
            },
            .fp128 => {
                try self.emitValueOf(u.ty, u.value);
                try self.emitU8(op.OP_F128_NEG);
            },
            else => {
                try self.emitFloatValue(u.ty, u.value);
                const sign: i64 = if (kind == .float) 0x80000000 else @bitCast(@as(u64, 0x8000000000000000));
                try self.emitConst(sign);
                try self.emitU8(op.OP_XOR);
            },
        }
        try self.emitStoreSlot(try self.slotFor(res.name));
    }

    fn lowerBinary(self: *Lowerer, instr: ast.Instruction, b: ast.Binary) anyerror!void {
        const res = instr.result orelse return error.NoResult;
        switch (b.op) {
            .fadd, .fsub, .fmul, .fdiv => {
                const kind = floatKindOf(b.ty) orelse return error.BadFloat;
                try self.emitFloatValue(b.ty, b.lhs);
                try self.emitFloatValue(b.ty, b.rhs);
                const opcode: u8 = switch (kind) {
                    .x86_fp80 => switch (b.op) {
                        .fadd => op.OP_F80_ADD,
                        .fsub => op.OP_F80_SUB,
                        .fmul => op.OP_F80_MUL,
                        else => op.OP_F80_DIV,
                    },
                    .fp128 => switch (b.op) {
                        .fadd => op.OP_F128_ADD,
                        .fsub => op.OP_F128_SUB,
                        .fmul => op.OP_F128_MUL,
                        else => op.OP_F128_DIV,
                    },
                    .float => switch (b.op) {
                        .fadd => op.OP_FADD32,
                        .fsub => op.OP_FSUB32,
                        .fmul => op.OP_FMUL32,
                        else => op.OP_FDIV32,
                    },
                    else => switch (b.op) {
                        .fadd => op.OP_FADD,
                        .fsub => op.OP_FSUB,
                        .fmul => op.OP_FMUL,
                        else => op.OP_FDIV,
                    },
                };
                try self.emitU8(opcode);
                try self.emitStoreSlot(try self.slotFor(res.name));
                return;
            },
            // frem has no CIVM encoding; the legacy path rejects it as well.
            .frem => return error.UnsupportedInstruction,
            else => {},
        }

        const bits: u32 = intBitsOf(b.ty) orelse 64;
        switch (b.op) {
            .udiv, .urem => {
                if (bits < 64) {
                    const mask = maskFor(bits);
                    try self.emitValueOf(b.ty, b.lhs);
                    try self.emitConst(mask);
                    try self.emitU8(op.OP_AND);
                    try self.emitValueOf(b.ty, b.rhs);
                    try self.emitConst(mask);
                    try self.emitU8(op.OP_AND);
                    try self.emitU8(if (b.op == .udiv) op.OP_DIV_U else op.OP_REM_U);
                    try self.normalizeInt(bits, true);
                } else {
                    try self.emitValueOf(b.ty, b.lhs);
                    try self.emitValueOf(b.ty, b.rhs);
                    try self.emitU8(if (b.op == .udiv) op.OP_DIV_U else op.OP_REM_U);
                    try self.normalizeInt(bits, true);
                }
            },
            .lshr, .ashr => {
                const shift_signed = b.op == .ashr;
                if (bits < 64) {
                    if (shift_signed) {
                        const shift: i64 = @intCast(64 - bits);
                        try self.emitValueOf(b.ty, b.lhs);
                        try self.emitConst(shift);
                        try self.emitU8(op.OP_SHL);
                        try self.emitConst(shift);
                        try self.emitU8(op.OP_SHR_S);
                    } else {
                        try self.emitValueOf(b.ty, b.lhs);
                        try self.emitConst(maskFor(bits));
                        try self.emitU8(op.OP_AND);
                    }
                    try self.emitValueOf(b.ty, b.rhs);
                    try self.emitU8(if (shift_signed) op.OP_SHR_S else op.OP_SHR_U);
                    try self.normalizeInt(bits, true);
                } else {
                    try self.emitValueOf(b.ty, b.lhs);
                    try self.emitValueOf(b.ty, b.rhs);
                    try self.emitU8(if (shift_signed) op.OP_SHR_S else op.OP_SHR_U);
                    try self.normalizeInt(bits, true);
                }
            },
            else => {
                const opcode: u8 = switch (b.op) {
                    .add => op.OP_ADD,
                    .sub => op.OP_SUB,
                    .mul => op.OP_MUL,
                    .sdiv => op.OP_DIV_S,
                    .srem => op.OP_REM_S,
                    .and_ => op.OP_AND,
                    .or_ => op.OP_OR,
                    .xor => op.OP_XOR,
                    .shl => op.OP_SHL,
                    else => return error.UnsupportedInstruction,
                };
                try self.emitValueOf(b.ty, b.lhs);
                try self.emitValueOf(b.ty, b.rhs);
                try self.emitU8(opcode);
                try self.normalizeInt(bits, true);
            },
        }
        try self.emitStoreSlot(try self.slotFor(res.name));
    }

    fn lowerCast(self: *Lowerer, instr: ast.Instruction, c: ast.Cast) anyerror!void {
        const res = instr.result orelse return error.NoResult;
        const src_is_wide = isF80OrF128(c.src);
        const float_cast = switch (c.op) {
            .fptosi, .fptoui, .fptrunc, .fpext => true,
            else => false,
        };
        if (src_is_wide) {
            try self.emitValueOf(c.src, c.value);
        } else if (float_cast) {
            try self.emitFloatValue(c.src, c.value);
        } else {
            try self.emitValueOf(c.src, c.value);
        }

        const src_bits: ?u32 = intBitsOf(c.src);
        const dst_bits: ?u32 = intBitsOf(c.dst);
        const src_kind = floatKindOf(c.src);
        const dst_kind = floatKindOf(c.dst);
        switch (c.op) {
            .inttoptr, .bitcast, .addrspacecast => {},
            .ptrtoint => {
                if (dst_bits) |bits| {
                    if (bits < 64) {
                        try self.emitConst(maskFor(bits));
                        try self.emitU8(op.OP_AND);
                    }
                }
            },
            .fptosi => {
                if (src_kind) |kind| {
                    try self.emitU8(switch (kind) {
                        .x86_fp80 => op.OP_F80_TO_I64,
                        .fp128 => op.OP_F128_TO_I64,
                        .float => op.OP_FPTOSI32,
                        else => op.OP_FPTOSI,
                    });
                } else return error.BadCast;
                if (dst_bits) |bits| {
                    if (bits < 64) try self.normalizeInt(bits, true);
                }
            },
            .fptoui => {
                if (src_kind) |kind| {
                    try self.emitU8(switch (kind) {
                        .x86_fp80 => op.OP_F80_TO_U64,
                        .fp128 => op.OP_F128_TO_U64,
                        .float => op.OP_FPTOUI32,
                        else => op.OP_FPTOUI,
                    });
                } else return error.BadCast;
                if (dst_bits) |bits| {
                    if (bits < 64) try self.normalizeInt(bits, true);
                }
            },
            .sitofp => {
                if (dst_kind) |kind| {
                    try self.emitU8(switch (kind) {
                        .x86_fp80 => op.OP_F80_FROM_I64,
                        .fp128 => op.OP_F128_FROM_I64,
                        .float => op.OP_SITOFP32,
                        else => op.OP_SITOFP,
                    });
                } else return error.BadCast;
            },
            .uitofp => {
                if (src_bits) |bits| {
                    if (bits < 64) {
                        try self.emitConst(maskFor(bits));
                        try self.emitU8(op.OP_AND);
                    }
                }
                if (dst_kind) |kind| {
                    try self.emitU8(switch (kind) {
                        .x86_fp80 => op.OP_F80_FROM_U64,
                        .fp128 => op.OP_F128_FROM_U64,
                        .float => op.OP_UITOFP32,
                        else => op.OP_UITOFP,
                    });
                } else return error.BadCast;
            },
            .fpext => {
                const sk = src_kind orelse return error.BadCast;
                const dk = dst_kind orelse return error.BadCast;
                if (sk == .float and dk == .double) {
                    try self.emitU8(op.OP_FPEXT);
                } else if (sk == .float and dk == .x86_fp80) {
                    try self.emitU8(op.OP_F80_FROM_F32);
                } else if (sk == .double and dk == .x86_fp80) {
                    try self.emitU8(op.OP_F80_FROM_F64);
                } else if (sk == .float and dk == .fp128) {
                    try self.emitU8(op.OP_F128_FROM_F32);
                } else if (sk == .double and dk == .fp128) {
                    try self.emitU8(op.OP_F128_FROM_F64);
                } else return error.BadCast;
            },
            .fptrunc => {
                const sk = src_kind orelse return error.BadCast;
                const dk = dst_kind orelse return error.BadCast;
                if (sk == .double and dk == .float) {
                    try self.emitU8(op.OP_FPTRUNC);
                } else if (sk == .x86_fp80 and dk == .float) {
                    try self.emitU8(op.OP_F80_TO_F32);
                } else if (sk == .x86_fp80 and dk == .double) {
                    try self.emitU8(op.OP_F80_TO_F64);
                } else if (sk == .fp128 and dk == .float) {
                    try self.emitU8(op.OP_F128_TO_F32);
                } else if (sk == .fp128 and dk == .double) {
                    try self.emitU8(op.OP_F128_TO_F64);
                } else return error.BadCast;
            },
            .trunc => try self.normalizeInt(dst_bits orelse 64, true),
            .zext => {
                if (src_bits) |bits| {
                    if (bits < 64) {
                        try self.emitConst(maskFor(bits));
                        try self.emitU8(op.OP_AND);
                    }
                }
                try self.normalizeInt(dst_bits orelse 64, true);
            },
            .sext => {
                if (src_bits) |bits| {
                    if (bits < 64) {
                        const shift: i64 = @intCast(64 - bits);
                        try self.emitConst(shift);
                        try self.emitU8(op.OP_SHL);
                        try self.emitConst(shift);
                        try self.emitU8(op.OP_SHR_S);
                    }
                }
                try self.normalizeInt(dst_bits orelse 64, true);
            },
        }
        try self.emitStoreSlot(try self.slotFor(res.name));
    }

    // ------------------------------------------------------------------- calls

    fn lowerCall(self: *Lowerer, call: ast.Call, result: ?ast.NamedRef) anyerror!void {
        var direct_name: ?[]const u8 = null;
        switch (call.callee) {
            .direct => |n| direct_name = n.name,
            .indirect => |tv| {
                if (isTag(tv.val, .null_)) return;
            },
            .asm_ => return error.UnsupportedInstruction,
        }

        if (direct_name) |raw_name| {
            // `llvm.dbg.*` / `llvm.lifetime.*` are no-ops (debug info dropped).
            if (call.ret.isVoid() and (startsWith(raw_name, "llvm.dbg") or startsWith(raw_name, "llvm.lifetime"))) return;
            // `llvm.memcpy` / `llvm.memset` become dedicated opcodes.
            const is_memcpy = startsWith(raw_name, "llvm.memcpy.");
            const is_memset = startsWith(raw_name, "llvm.memset.");
            if (is_memcpy or is_memset) {
                if (call.args.len < 3) return error.BadCall;
                try self.emitValue(call.args[0]);
                try self.emitValue(call.args[1]);
                try self.emitValue(call.args[2]);
                try self.emitU8(if (is_memcpy) op.OP_MEMCPY else op.OP_MEMSET);
                return;
            }
            if (isCallbackBuiltin(raw_name)) {
                try self.lowerCallbackBuiltin(call, result, raw_name);
                return;
            }
            try self.lowerDirectCall(call, result, renameIntrinsic(raw_name));
            return;
        }
        try self.lowerIndirectCall(call, result);
    }

    fn lowerDirectCall(self: *Lowerer, call: ast.Call, result: ?ast.NamedRef, name: []const u8) anyerror!void {
        // Intrinsics with a dedicated encoding, in legacy order.
        if (startsWith(name, "llvm.frameaddress.")) {
            try self.emitConst(0);
            if (result) |r| try self.emitStoreSlot(try self.slotFor(r.name));
            return;
        }
        if (eql(name, "__intrinsic_setjmpex") or eql(name, "__intrinsic_setjmp") or
            eql(name, "setjmp") or eql(name, "_setjmp") or eql(name, "_setjmp3") or
            eql(name, "__builtin_setjmp"))
        {
            if (call.args.len < 1 or result == null) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitU8(op.OP_SETJMP);
            try self.emitU16(try self.slotFor(result.?.name));
            return;
        }
        if (eql(name, "longjmp") or eql(name, "_longjmp") or eql(name, "__builtin_longjmp")) {
            if (call.args.len < 2) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitValue(call.args[1]);
            try self.emitU8(op.OP_LONGJMP);
            return;
        }
        if (startsWith(name, "llvm.is.fpclass.")) {
            const kind: u8 = if (std.mem.endsWith(u8, name, ".f32")) 0 else if (std.mem.endsWith(u8, name, ".f64")) 1 else if (std.mem.endsWith(u8, name, ".f80")) 2 else if (std.mem.endsWith(u8, name, ".f128")) 3 else return error.UnsupportedFfi;
            if (call.args.len < 2 or result == null) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitValue(call.args[1]);
            try self.emitU8(op.OP_FPCLASS);
            try self.emitU8(kind);
            try self.emitStoreSlot(try self.slotFor(result.?.name));
            return;
        }
        if (startsWith(name, "llvm.ptrmask.")) {
            if (call.args.len < 2) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitValue(call.args[1]);
            try self.emitU8(op.OP_AND);
            if (result) |r| try self.emitStoreSlot(try self.slotFor(r.name));
            return;
        }
        if (eql(name, "llvm.va_start.p0") or eql(name, "llvm.va_start")) {
            if (call.args.len < 1) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitU8(op.OP_VA_START);
            return;
        }
        if (eql(name, "llvm.va_copy.p0") or eql(name, "llvm.va_copy") or eql(name, "__va_copy")) {
            if (call.args.len < 2) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitValue(call.args[1]);
            try self.emitU8(op.OP_VA_COPY);
            return;
        }
        if (eql(name, "llvm.va_end.p0") or eql(name, "llvm.va_end")) return;
        if (eql(name, "llvm.stacksave.p0") or eql(name, "llvm.stacksave")) {
            try self.emitU8(op.OP_STACKSAVE);
            if (result) |r| try self.emitStoreSlot(try self.slotFor(r.name));
            return;
        }
        if (eql(name, "llvm.stackrestore.p0") or eql(name, "llvm.stackrestore")) {
            if (call.args.len < 1) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitU8(op.OP_STACKRESTORE);
            return;
        }

        if (self.ctx.func_indices.get(name)) |idx| {
            try self.lowerVmCall(call, result, idx);
            return;
        }
        try self.lowerNativeCall(call, result, name);
    }

    /// Direct call to another function in the same module (CIVM `OP_CALL` /
    /// `OP_CALL_VARIADIC_TYPED`).
    fn lowerVmCall(self: *Lowerer, call: ast.Call, result: ?ast.NamedRef, idx: u16) anyerror!void {
        // OP_CALL_VARIADIC_TYPED stores the argument count as u16.
        if (call.args.len > std.math.maxInt(u16)) return error.TooManyArgs;
        var need_copy = false;
        for (call.args) |arg| {
            if (isF80OrF128(arg.ty) and isTag(arg.val, .local)) {
                need_copy = true;
                break;
            }
        }
        var save_slot: ?u16 = null;
        if (need_copy) {
            try self.emitU8(op.OP_STACKSAVE);
            const save_name = try std.fmt.allocPrint(self.allocator, "__f80save_{d}", .{self.func.code.items.len});
            save_slot = try self.slotFor(save_name);
            try self.emitStoreSlot(save_slot.?);
        }
        for (call.args) |arg| {
            if (isF80OrF128(arg.ty) and isTag(arg.val, .local)) {
                try self.emitU8(op.OP_ALLOCA);
                try self.emitU16(16);
                try self.emitU8(op.OP_DUP);
                try self.emitValue(arg);
                try self.emitConst(16);
                try self.emitU8(op.OP_MEMCPY);
            } else if (isPlainFloat(arg.ty)) {
                try self.emitFloatValue(arg.ty, arg.val);
            } else {
                try self.emitValue(arg);
            }
        }

        const callee = &self.ctx.module.functions[idx];
        const callee_params = self.ctx.func_params[idx];
        if (callee.sig.is_varargs) {
            try self.emitU8(op.OP_CALL_VARIADIC_TYPED);
            try self.emitU16(idx);
            try self.emitU16(@intCast(call.args.len));
            var vi: usize = callee_params.len;
            while (vi < call.args.len) : (vi += 1) {
                const arg = call.args[vi];
                if (byvalType(arg.attrs)) |bt| {
                    try self.emitU8(3);
                    try self.emitU16(@intCast(try self.typeSize(bt)));
                } else if (isF80OrF128(arg.ty)) {
                    const kind = floatKindOf(arg.ty).?;
                    try self.emitU8(if (kind == .x86_fp80) 1 else 2);
                } else if (isAggregateLike(arg.ty)) {
                    try self.emitU8(3);
                    try self.emitU16(@intCast(try self.typeSize(arg.ty)));
                } else {
                    try self.emitU8(0);
                }
            }
        } else {
            try self.emitU8(op.OP_CALL);
            try self.emitU16(idx);
        }
        if (!call.ret.isVoid()) {
            const res = result orelse return error.NoResult;
            try self.emitStoreSlot(try self.slotFor(res.name));
        }
        if (save_slot) |ss| {
            try self.emitLoadSlot(ss);
            try self.emitU8(op.OP_STACKRESTORE);
        }
    }

    /// Indirect call through a function pointer (`OP_CALL_INDIRECT_NATIVE`).
    fn lowerIndirectCall(self: *Lowerer, call: ast.Call, result: ?ast.NamedRef) anyerror!void {
        var plan_types = std.ArrayList([]const u8).init(self.allocator);
        var byval_sizes = try self.allocator.alloc(u16, call.args.len);
        @memset(byval_sizes, 0);
        var sret_idx: ?usize = null;
        var sret_size: u16 = 0;
        for (call.args, 0..) |arg, arg_index| {
            try plan_types.append(try self.planType(arg.ty));
            if (byvalType(arg.attrs)) |bt| {
                byval_sizes[arg_index] = @intCast(try self.typeSize(bt));
            }
            if (sretType(arg.attrs)) |st| {
                sret_idx = arg_index;
                sret_size = @intCast(try self.typeSize(st));
            }
        }
        for (call.args) |arg| {
            if (isPlainFloat(arg.ty)) {
                try self.emitFloatValue(arg.ty, arg.val);
            } else {
                try self.emitValue(arg);
            }
        }
        try self.emitValue(call.callee.indirect);

        const plan_ret = if (sret_idx != null) "void" else try self.planType(call.ret);
        var plan = try abi.buildPlanForAbi(
            self.allocator,
            self.ctx.abi,
            "indirect",
            plan_ret,
            plan_types.items,
            call.is_varargs,
            sret_idx,
            sret_size,
            byval_sizes,
            self.ctx.ptr_size,
        );
        // LLVM prints the convention on the call instruction, not in the
        // function *type*: clang emits `call x86_stdcallcc i32 %fp(i32, i32)`
        // for a `__stdcall` function pointer (verified against clang 18
        // i686-windows), so `call.cc` is the authoritative source here. A
        // function-pointer type never carries a cconv in textual IR, which is
        // why `ast.FunctionType` has no `cc` field to consult.
        plan.conv = abi.convFromName(call.cc);
        const plan_index = try self.ctx.internPlan(plan);
        try self.emitU8(op.OP_CALL_INDIRECT_NATIVE);
        try self.emitU16(plan_index);
        if (!call.ret.isVoid()) {
            const res = result orelse return error.NoResult;
            const slot = try self.slotFor(res.name);
            try self.emitStoreSlot(slot);
            if (intBitsOf(call.ret)) |bits| {
                if (bits < 64) try self.normalizeLoadedInt(slot, bits);
            }
        }
    }

    /// `__ci_callback_acquire` / `__ci_callback_release`, i.e. the expanded
    /// `ci_callback_acquire` / `ci_callback_release` macros from the header
    /// `cinterp-cc` force-includes (`src/data/cinterp_callbacks.h`).
    ///
    /// Acquire takes exactly one *direct function reference* (casts and
    /// constant expressions are stripped, so `ci_callback_acquire(&my_fn)`
    /// reaches the lowerer as `ptr noundef @my_fn`) and emits
    /// `OP_CALLBACK_ACQUIRE plan_index func_index`. Unlike `emitCallback` it
    /// reserves no compile-time callback slot: the runtime allocates one
    /// global trampoline per execution and the C code decides when to release
    /// it.
    ///
    /// Release evaluates its argument to the trampoline pointer and emits
    /// `OP_CALLBACK_RELEASE`, which yields the status.
    ///
    /// Neither symbol ever becomes a CIPI import (see `isCallbackBuiltin`).
    fn lowerCallbackBuiltin(self: *Lowerer, call: ast.Call, result: ?ast.NamedRef, name: []const u8) anyerror!void {
        if (eql(name, callback_acquire_symbol)) {
            if (call.args.len != 1) return error.CallbackAcquireRequiresFunctionRef;
            const target = valueGlobalRef(call.args[0].val) orelse
                return error.CallbackAcquireRequiresFunctionRef;
            const func_index = self.ctx.func_indices.get(target) orelse
                return error.CallbackAcquireRequiresFunctionRef;
            const plan_index = try self.planCallback(target, func_index);
            try self.emitU8(op.OP_CALLBACK_ACQUIRE);
            try self.emitU16(plan_index);
            try self.emitU16(func_index);
        } else {
            if (call.args.len != 1) return error.BadCall;
            try self.emitValue(call.args[0]);
            try self.emitU8(op.OP_CALLBACK_RELEASE);
        }
        if (!call.ret.isVoid()) {
            const res = result orelse return error.NoResult;
            const slot = try self.slotFor(res.name);
            try self.emitStoreSlot(slot);
            if (intBitsOf(call.ret)) |bits| {
                if (bits < 64) try self.normalizeLoadedInt(slot, bits);
            }
        }
    }

    /// Call to an external symbol: build the ABI plan, then the call itself.
    fn lowerNativeCall(self: *Lowerer, call: ast.Call, result: ?ast.NamedRef, name: []const u8) anyerror!void {
        var plan_types = std.ArrayList([]const u8).init(self.allocator);
        var byval_sizes = try self.allocator.alloc(u16, call.args.len);
        @memset(byval_sizes, 0);
        var sret_idx: ?usize = null;
        var sret_size: u16 = 0;
        for (call.args, 0..) |arg, arg_index| {
            try plan_types.append(try self.planType(arg.ty));
            if (byvalType(arg.attrs)) |bt| {
                byval_sizes[arg_index] = @intCast(try self.typeSize(bt));
            }
            if (sretType(arg.attrs)) |st| {
                sret_idx = arg_index;
                sret_size = @intCast(try self.typeSize(st));
            }
        }

        const decl = self.ctx.decls.get(name);
        const is_varargs = call.is_varargs or (if (decl) |d| d.sig.is_varargs else false);
        const plan_ret = if (sret_idx != null) "void" else try self.planType(call.ret);

        var call_name = name;
        const atexit_shim = eql(name, "atexit");
        if (atexit_shim) {
            // atexit -> __cxa_atexit(fn, null, null)
            call_name = "__cxa_atexit";
            try plan_types.append("ptr");
            try plan_types.append("ptr");
        }
        var plan = try abi.buildPlanForAbi(
            self.allocator,
            self.ctx.abi,
            call_name,
            plan_ret,
            plan_types.items,
            is_varargs,
            sret_idx,
            sret_size,
            byval_sizes,
            self.ctx.ptr_size,
        );
        // The call-site convention wins over the declaration's; a missing
        // keyword on both means the target default. `main.zig` may still
        // override known WinAPI exports from the MinGW import table.
        plan.conv = abi.convFromName(call.cc orelse (if (decl) |d| d.sig.cc else null));
        const plan_index = try self.ctx.internPlan(plan);

        for (call.args) |arg| {
            switch (arg.val) {
                .global => |g| {
                    if (self.ctx.func_indices.get(g.name)) |cb_idx| {
                        try self.emitCallback(g.name, cb_idx);
                        continue;
                    }
                },
                else => {},
            }
            if (isPlainFloat(arg.ty)) {
                try self.emitFloatValue(arg.ty, arg.val);
            } else {
                try self.emitValue(arg);
            }
        }
        if (atexit_shim) {
            try self.emitConst(0);
            try self.emitConst(0);
        }

        try self.emitU8(if (is_varargs) op.OP_CALL_VARARG else op.OP_CALL_NATIVE);
        try self.emitU16(plan_index);
        if (!call.ret.isVoid()) {
            const res = result orelse return error.NoResult;
            const slot = try self.slotFor(res.name);
            try self.emitStoreSlot(slot);
            if (intBitsOf(call.ret)) |bits| {
                if (bits < 64) try self.normalizeLoadedInt(slot, bits);
            }
        }
    }

    /// Sign-extend a narrow integer held in `slot` (legacy emits this inline
    /// after native/indirect calls).
    fn normalizeLoadedInt(self: *Lowerer, slot: u16, bits: u32) !void {
        try self.emitLoadSlot(slot);
        try self.emitConst(@intCast(64 - bits));
        try self.emitU8(op.OP_SHL);
        try self.emitConst(@intCast(64 - bits));
        try self.emitU8(op.OP_SHR_S);
        try self.emitStoreSlot(slot);
    }

    /// Create (or reuse) the ABI plan + callback slot for a function used as a
    /// value, and emit `OP_CREATE_CALLBACK`.
    fn emitCallback(self: *Lowerer, key: []const u8, func_index: u16) anyerror!void {
        if (self.ctx.callbacks.by_func.get(key)) |entry| {
            try self.emitU8(op.OP_CREATE_CALLBACK);
            try self.emitU16(entry.slot);
            try self.emitU16(entry.func_index);
            try self.emitU16(entry.plan_index);
            return;
        }
        const plan_index = try self.planCallback(key, func_index);
        if (self.ctx.callbacks.next_slot == std.math.maxInt(u16)) return error.TooManyCallbacks;
        const slot = self.ctx.callbacks.next_slot;
        self.ctx.callbacks.next_slot += 1;
        try self.ctx.callbacks.by_func.put(key, .{ .slot = slot, .func_index = func_index, .plan_index = plan_index });
        try self.emitU8(op.OP_CREATE_CALLBACK);
        try self.emitU16(slot);
        try self.emitU16(func_index);
        try self.emitU16(plan_index);
    }

    /// Build (or dedup into an existing) CIPL plan describing how native code
    /// calls `func_index`, named `callback:<key>`.
    ///
    /// Shared by `OP_CREATE_CALLBACK` (compile-time slot, automatic) and
    /// `OP_CALLBACK_ACQUIRE` (runtime slot, explicit); only the former reserves
    /// a slot, so the caller owns slot allocation.
    fn planCallback(self: *Lowerer, key: []const u8, func_index: u16) anyerror!u16 {
        const params = self.ctx.func_params[func_index];
        var byval_sizes = try self.allocator.alloc(u16, params.len);
        @memset(byval_sizes, 0);
        var sret_idx: ?usize = null;
        var sret_size: u16 = 0;
        var plan_types = std.ArrayList([]const u8).init(self.allocator);
        for (params, 0..) |param, param_index| {
            try plan_types.append(try self.planType(param.ty));
            if (byvalType(param.attrs)) |bt| {
                byval_sizes[param_index] = @intCast(try self.typeSize(bt));
            }
            if (sretType(param.attrs)) |st| {
                sret_idx = param_index;
                sret_size = @intCast(try self.typeSize(st));
            }
        }
        const callee = &self.ctx.module.functions[func_index];
        const plan_ret = if (sret_idx != null) "void" else try self.planType(callee.sig.ret);
        const plan_name = try std.fmt.allocPrint(self.allocator, "callback:{s}", .{key});
        var plan = try abi.buildPlanForAbi(
            self.allocator,
            self.ctx.abi,
            plan_name,
            plan_ret,
            plan_types.items,
            false,
            sret_idx,
            sret_size,
            byval_sizes,
            self.ctx.ptr_size,
        );
        // The callback runs the callee's own definition, so the definition's
        // calling convention is authoritative (Win32 `__stdcall` callback ->
        // conv=1; the runtime dispatches it accordingly).
        plan.conv = abi.convFromName(callee.sig.cc);
        return try self.ctx.internPlan(plan);
    }
};

// --------------------------------------------------------------- small helpers

fn byvalType(attrs: []const ast.Attr) ?*const ast.Type {
    for (attrs) |attr| {
        switch (attr.kind) {
            .byval => |ty| return ty,
            else => {},
        }
    }
    return null;
}

fn sretType(attrs: []const ast.Attr) ?*const ast.Type {
    for (attrs) |attr| {
        switch (attr.kind) {
            .sret => |ty| return ty,
            else => {},
        }
    }
    return null;
}

/// Map `llvm.*` intrinsic names onto the libc entries the runtime implements.
fn renameIntrinsic(name: []const u8) []const u8 {
    if (!startsWith(name, "llvm.")) return name;
    const Rename = struct { prefix: []const u8, f32: []const u8, f64: []const u8, wide: []const u8 };
    const table = [_]Rename{
        .{ .prefix = "llvm.fmuladd.", .f32 = "fmaf", .f64 = "fma", .wide = "fmal" },
        .{ .prefix = "llvm.fabs.", .f32 = "fabsf", .f64 = "fabs", .wide = "fabsl" },
        .{ .prefix = "llvm.sqrt.", .f32 = "sqrtf", .f64 = "sqrt", .wide = "sqrtl" },
        .{ .prefix = "llvm.round.", .f32 = "roundf", .f64 = "round", .wide = "round" },
        .{ .prefix = "llvm.ceil.", .f32 = "ceilf", .f64 = "ceil", .wide = "ceil" },
        .{ .prefix = "llvm.floor.", .f32 = "floorf", .f64 = "floor", .wide = "floor" },
        .{ .prefix = "llvm.trunc.", .f32 = "truncf", .f64 = "trunc", .wide = "trunc" },
        .{ .prefix = "llvm.nearbyint.", .f32 = "nearbyintf", .f64 = "nearbyint", .wide = "nearbyint" },
        .{ .prefix = "llvm.rint.", .f32 = "rintf", .f64 = "rint", .wide = "rint" },
        .{ .prefix = "llvm.sin.", .f32 = "sinf", .f64 = "sin", .wide = "sin" },
        .{ .prefix = "llvm.cos.", .f32 = "cosf", .f64 = "cos", .wide = "cos" },
        .{ .prefix = "llvm.exp2.", .f32 = "exp2f", .f64 = "exp2", .wide = "exp2" },
        .{ .prefix = "llvm.log2.", .f32 = "log2f", .f64 = "log2", .wide = "log2" },
        .{ .prefix = "llvm.pow.", .f32 = "powf", .f64 = "pow", .wide = "pow" },
        .{ .prefix = "llvm.fmin.", .f32 = "fminf", .f64 = "fmin", .wide = "fmin" },
        .{ .prefix = "llvm.fmax.", .f32 = "fmaxf", .f64 = "fmax", .wide = "fmax" },
    };
    for (table) |entry| {
        if (!startsWith(name, entry.prefix)) continue;
        if (std.mem.endsWith(u8, name, ".f32")) return entry.f32;
        if (std.mem.endsWith(u8, name, ".f64")) return entry.f64;
        return entry.wide;
    }
    if (startsWith(name, "llvm.copysign.")) {
        if (std.mem.endsWith(u8, name, ".f32")) return "copysignf";
        if (std.mem.endsWith(u8, name, ".f80") or std.mem.endsWith(u8, name, ".f128")) return "copysignl";
        return "copysign";
    }
    return name;
}

// ----------------------------------------------------------------------- debug

/// Compact structural dump used by `cinterp-cc ... --dump-ast`.
pub fn dumpModule(writer: anytype, module: *const ast.Module) !void {
    try writer.print("AST: {d} type defs, {d} globals, {d} declares, {d} functions\n", .{
        module.type_defs.len, module.globals.len, module.declares.len, module.functions.len,
    });
    for (module.functions) |f| {
        var instr_count: usize = 0;
        for (f.blocks) |block| instr_count += block.instructions.len;
        try writer.print("  define {} @{s}: {d} blocks, {d} instructions\n", .{
            f.sig.ret.*, f.name, f.blocks.len, instr_count,
        });
    }
}

// ------------------------------------------------------------------ test hooks

/// Narrow seam used by the unit tests; not part of the lowering contract.
pub const TestHook = struct {
    pub const RelocInfo = struct { offset: u32, target: []const u8, addend: i64 };

    /// Static data image bytes produced for `module`.
    pub fn globalData(allocator: Allocator, module: *const ast.Module, ptr_size: u32) ![]u8 {
        const layout = try Layout.init(allocator, module, ptr_size);
        const globals = try buildGlobals(allocator, module, &layout, ptr_size, .legacy);
        return globals.data;
    }

    /// Relocation entries produced for `module` under `mode`.
    pub fn globalRelocs(allocator: Allocator, module: *const ast.Module, ptr_size: u32, mode: GepConstMode) ![]RelocInfo {
        const layout = try Layout.init(allocator, module, ptr_size);
        const globals = try buildGlobals(allocator, module, &layout, ptr_size, mode);
        var out = try allocator.alloc(RelocInfo, globals.relocs.len);
        for (globals.relocs, 0..) |reloc, i| {
            out[i] = .{ .offset = reloc.offset, .target = reloc.target, .addend = reloc.addend };
        }
        return out;
    }
};

// ----------------------------------------------------------------------- tests

const parser = @import("ir/parser.zig");
const testing = std.testing;

const fixture_clang18 = @embedFile("ir/testdata/clang18_x86_64.ll");
const fixture_hello = @embedFile("testdata/lower_ast/hello.ll");
const fixture_structs = @embedFile("testdata/lower_ast/structs.ll");
const fixture_ffi_qsort = @embedFile("testdata/lower_ast/ffi_qsort.ll");
const fixture_ffi_callback = @embedFile("testdata/lower_ast/ffi_callback.ll");
/// Clang 18 IR for `examples/ffi_callback_scope.c` (compiled with the exact
/// `cinterp-cc` flags plus the forced-include callback header): the explicit
/// `ci_callback_acquire`/`ci_callback_release` macros lower to
/// `OP_CALLBACK_ACQUIRE`/`OP_CALLBACK_RELEASE` and one `callback:cmp` plan.
const fixture_ffi_callback_scope = @embedFile("testdata/lower_ast/ffi_callback_scope.ll");
/// Clang IR for a synthetic C file covering the paths the example corpus does
/// not hit: VLA (dynamic alloca), stacksave/restore, memcpy/memset intrinsics,
/// indirect calls, pointer `select`, all integer arithmetic/shift opcodes, the
/// integer/float cast matrix and every `fcmp`/`icmp` predicate shape used by C.
const fixture_misc = @embedFile("testdata/lower_ast/misc.ll");

const control_flow_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\@counter = global i32 0, align 4
    \\
    \\define i32 @loops(i32 %n) {
    \\entry:
    \\  br label %loop
    \\loop:
    \\  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
    \\  %acc = phi i32 [ 0, %entry ], [ %sum, %loop ]
    \\  %sum = add nsw i32 %acc, %i
    \\  %next = add nsw i32 %i, 1
    \\  %done = icmp sge i32 %next, %n
    \\  br i1 %done, label %exit, label %loop
    \\exit:
    \\  %sel = select i1 %done, i32 %sum, i32 0
    \\  ret i32 %sel
    \\}
    \\
    \\define i32 @branchy(i32 %x) {
    \\entry:
    \\  switch i32 %x, label %default [
    \\    i32 0, label %zero
    \\    i32 -3, label %minus
    \\  ]
    \\zero:
    \\  ret i32 1
    \\minus:
    \\  ret i32 2
    \\default:
    \\  unreachable
    \\}
    \\
    \\define i32 @main() {
    \\entry:
    \\  %a = call i32 @loops(i32 5)
    \\  %b = call i32 @branchy(i32 -3)
    \\  %sum = add i32 %a, %b
    \\  store i32 %sum, ptr @counter, align 4
    \\  %ld = load volatile i32, ptr @counter, align 4
    \\  ret i32 %ld
    \\}
;

const globals_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\%struct.Inner = type { i32, [2 x i16] }
    \\%struct.Outer = type { i8, %struct.Inner, [2 x ptr] }
    \\
    \\@.str = private unnamed_addr constant [4 x i8] c"abc\00", align 1
    \\@inner = global %struct.Inner { i32 7, [2 x i16] [i16 1, i16 2] }, align 4
    \\@outer = global %struct.Outer { i8 1, %struct.Inner { i32 9, [2 x i16] [i16 3, i16 4] }, [2 x ptr] [ptr @.str, ptr null] }, align 8
    \\@arr = global [4 x i32] [i32 10, i32 20, i32 30, i32 40], align 16
    \\@elem = global ptr getelementptr inbounds ([4 x i32], ptr @arr, i64 0, i64 2), align 8
    \\@field = global ptr getelementptr inbounds (%struct.Outer, ptr @outer, i32 0, i32 2), align 8
    \\@ext = external global i32, align 4
    \\
    \\define i32 @main() {
    \\entry:
    \\  %0 = load i32, ptr @ext, align 4
    \\  ret i32 %0
    \\}
;

const intrinsics_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\declare i32 @setjmp(ptr)
    \\declare void @longjmp(ptr, i32)
    \\declare void @llvm.va_start.p0(ptr)
    \\declare void @llvm.va_copy.p0(ptr, ptr)
    \\declare void @llvm.va_end.p0(ptr)
    \\declare ptr @llvm.stacksave.p0()
    \\declare void @llvm.stackrestore.p0(ptr)
    \\declare ptr @llvm.frameaddress.p0(i32)
    \\declare ptr @llvm.ptrmask.p0.i64(ptr, i64)
    \\declare i1 @llvm.is.fpclass.f64(double, i32)
    \\declare double @llvm.fmuladd.f64(double, double, double)
    \\
    \\define i32 @intrinsics(ptr %env, ptr %ap, ptr %ap2) {
    \\entry:
    \\  %r = call i32 @setjmp(ptr %env)
    \\  %s = call ptr @llvm.stacksave.p0()
    \\  %fa = call ptr @llvm.frameaddress.p0(i32 0)
    \\  %m = call ptr @llvm.ptrmask.p0.i64(ptr %fa, i64 4095)
    \\  %k = call i1 @llvm.is.fpclass.f64(double 1.500000e+00, i32 3)
    \\  %fma = call double @llvm.fmuladd.f64(double 1.500000e+00, double 2.000000e+00, double 3.000000e+00)
    \\  call void @llvm.va_start.p0(ptr %ap)
    \\  call void @llvm.va_copy.p0(ptr %ap2, ptr %ap)
    \\  call void @llvm.va_end.p0(ptr %ap)
    \\  call void @llvm.stackrestore.p0(ptr %s)
    \\  call void @longjmp(ptr %env, i32 %r)
    \\  ret i32 0
    \\}
;

const null_callee_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\define void @null_calls(ptr %p) {
    \\entry:
    \\  call void null()
    \\  ret void
    \\}
;

/// The argument form is accepted by the parser for robustness. Clang emits the
/// bare `null()` spelling for an indirect null call.
const null_callee_args_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\define void @null_call_args(ptr %p) {
    \\entry:
    \\  call void null(ptr %p)
    \\  ret void
    \\}
;

const f32_literals_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\@fdec = global float 6.912000e+01, align 4
    \\@fhex = global float 0x405147AE20000000, align 4
    \\@ddec = global double 6.912000e+01, align 8
    \\
    \\declare void @take_float(float)
    \\declare void @take_double(double)
    \\
    \\define void @literal_args(ptr %p) {
    \\entry:
    \\  store float 6.912000e+01, ptr %p, align 4
    \\  store float 0x405147AE20000000, ptr %p, align 4
    \\  call void @take_float(float 6.912000e+01)
    \\  call void @take_float(float 0x405147AE20000000)
    \\  call void @take_double(double 6.912000e+01)
    \\  ret void
    \\}
;

// ---------------------------------------------------------------------------
// Former AST/legacy difference cases (docs/ir-parser-differences.md).
//
// These are correctness properties, not layout accidents: the AST emits a valid
// address or instruction where the retired text parser silently emitted 0 or
// dropped the line. They are covered by `CompileResult` goldens below.
// ---------------------------------------------------------------------------

const inttoptr_global_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\@vram = global ptr inttoptr (i64 40960 to ptr), align 8
    \\@flag = global i32 7, align 4
    \\
    \\define i32 @main() {
    \\entry:
    \\  ret i32 0
    \\}
;

const external_constant_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\@a = external constant [0 x i8], align 1
    \\
    \\define i32 @f(ptr %p) {
    \\entry:
    \\  %cmp = icmp ugt ptr %p, @a
    \\  %z = zext i1 %cmp to i32
    \\  ret i32 %z
    \\}
;

const metadata_global_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\@i = internal global i32 0, align 4
    \\@j = internal global i32 0, align 4
    \\@k = global i32 0, align 4
    \\@llvm.compiler.used = appending global [1 x ptr] [ptr @k], section "llvm.metadata"
    \\
    \\define i32 @main() {
    \\entry:
    \\  ret i32 0
    \\}
;

const global_name_in_initializer_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\%struct.test = type { ptr }
    \\
    \\@test.const_test = internal constant %struct.test { ptr @global_int }, align 8
    \\@global_int = global i32 0, align 4
    \\@flag = global i32 0, align 4
    \\@global_test = global %struct.test zeroinitializer, align 8
    \\
    \\define i32 @test() {
    \\entry:
    \\  %v = load i32, ptr @flag, align 4
    \\  ret i32 %v
    \\}
;

const null_suffix_callee_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\@gi = global i32 0, align 4
    \\
    \\define internal ptr @getnull() {
    \\entry:
    \\  ret ptr null
    \\}
    \\
    \\define void @foo(ptr %a, ptr %b) {
    \\entry:
    \\  ret void
    \\}
    \\
    \\define i32 @main() {
    \\entry:
    \\  %call = call ptr @getnull()
    \\  call void @foo(ptr @gi, ptr %call)
    \\  ret i32 0
    \\}
;

fn parseFixture(allocator: Allocator, text: []const u8) !ast.Module {
    var p = parser.Parser.init(allocator, text);
    return p.parse();
}

/// Hand-written shape of the forced-include callback macros: one explicit
/// acquire, a native call that receives the trampoline and one release. Kept
/// minimal so opcode encoding and plan selection can be asserted on exact
/// bytes; `fixture_ffi_callback_scope` covers the real clang output.
const callback_scope_ir =
    \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
    \\target triple = "x86_64-unknown-linux-gnu"
    \\
    \\declare ptr @__ci_callback_acquire(ptr)
    \\declare i32 @__ci_callback_release(ptr)
    \\declare void @take(ptr)
    \\
    \\define i32 @cb(i32 %a, i32 %b) {
    \\entry:
    \\  %r = add i32 %a, %b
    \\  ret i32 %r
    \\}
    \\
    \\define i32 @main() {
    \\entry:
    \\  %tramp = call ptr @__ci_callback_acquire(ptr @cb)
    \\  call void @take(ptr %tramp)
    \\  %status = call i32 @__ci_callback_release(ptr %tramp)
    \\  ret i32 %status
    \\}
;

// --------------------------------------------------------------------- goldens
//
// A golden file is the canonical text image of everything `main.zig`
// serializes into CIPKG/CIVM/CIPL/CIPI for one source: function names,
// parameter metadata, bytecode bytes, every plan/ArgPlan/Loc field and the
// external-symbol list, concatenated for each ABI the case covers. Comparing
// it protects code bytes, plan ordering and sizes without a second frontend.
//
// Regenerate after an intentional codegen change (review the diff!):
//   cd compiler && CINTERP_WRITE_GOLDEN=1 \
//     zig test src/lower_ast.zig --test-filter "write golden files"

const GoldenCase = struct {
    name: []const u8,
    text: []const u8,
    abis: []const u8,
    golden: []const u8,
};

const golden_clang18 = @embedFile("testdata/lower_ast/golden/clang18.golden");
const golden_hello = @embedFile("testdata/lower_ast/golden/hello.golden");
const golden_structs = @embedFile("testdata/lower_ast/golden/structs.golden");
const golden_ffi_qsort = @embedFile("testdata/lower_ast/golden/ffi_qsort.golden");
const golden_ffi_callback = @embedFile("testdata/lower_ast/golden/ffi_callback.golden");
const golden_ffi_callback_scope = @embedFile("testdata/lower_ast/golden/ffi_callback_scope.golden");
const golden_misc = @embedFile("testdata/lower_ast/golden/misc.golden");
const golden_control_flow = @embedFile("testdata/lower_ast/golden/control_flow.golden");
const golden_globals = @embedFile("testdata/lower_ast/golden/globals.golden");
const golden_intrinsics = @embedFile("testdata/lower_ast/golden/intrinsics.golden");
const golden_null_callee = @embedFile("testdata/lower_ast/golden/null_callee.golden");
const golden_null_callee_args = @embedFile("testdata/lower_ast/golden/null_callee_args.golden");
const golden_f32_literals = @embedFile("testdata/lower_ast/golden/f32_literals.golden");
const golden_inttoptr_global = @embedFile("testdata/lower_ast/golden/inttoptr_global.golden");
const golden_external_constant = @embedFile("testdata/lower_ast/golden/external_constant.golden");
const golden_metadata_global = @embedFile("testdata/lower_ast/golden/metadata_global.golden");
const golden_global_name_in_initializer = @embedFile("testdata/lower_ast/golden/global_name_in_initializer.golden");
const golden_null_suffix_callee = @embedFile("testdata/lower_ast/golden/null_suffix_callee.golden");

/// ABI ids: 1 = SysV x86-64, 2 = Win64, 3 = Win32, 4 = AArch64 AAPCS64.
const golden_cases = [_]GoldenCase{
    .{ .name = "clang18", .text = fixture_clang18, .abis = &.{ 1, 2, 4 }, .golden = golden_clang18 },
    .{ .name = "hello", .text = fixture_hello, .abis = &.{ 1, 2, 3, 4 }, .golden = golden_hello },
    .{ .name = "structs", .text = fixture_structs, .abis = &.{ 1, 2, 3, 4 }, .golden = golden_structs },
    .{ .name = "ffi_qsort", .text = fixture_ffi_qsort, .abis = &.{ 1, 2, 3, 4 }, .golden = golden_ffi_qsort },
    .{ .name = "ffi_callback", .text = fixture_ffi_callback, .abis = &.{ 1, 2, 3, 4 }, .golden = golden_ffi_callback },
    .{ .name = "ffi_callback_scope", .text = fixture_ffi_callback_scope, .abis = &.{ 1, 2, 3, 4 }, .golden = golden_ffi_callback_scope },
    .{ .name = "misc", .text = fixture_misc, .abis = &.{ 1, 2, 3, 4 }, .golden = golden_misc },
    .{ .name = "control_flow", .text = control_flow_ir, .abis = &.{ 1, 2 }, .golden = golden_control_flow },
    .{ .name = "globals", .text = globals_ir, .abis = &.{1}, .golden = golden_globals },
    .{ .name = "intrinsics", .text = intrinsics_ir, .abis = &.{ 1, 2 }, .golden = golden_intrinsics },
    .{ .name = "null_callee", .text = null_callee_ir, .abis = &.{ 1, 2 }, .golden = golden_null_callee },
    .{ .name = "null_callee_args", .text = null_callee_args_ir, .abis = &.{1}, .golden = golden_null_callee_args },
    .{ .name = "f32_literals", .text = f32_literals_ir, .abis = &.{ 1, 2, 3, 4 }, .golden = golden_f32_literals },
    .{ .name = "inttoptr_global", .text = inttoptr_global_ir, .abis = &.{1}, .golden = golden_inttoptr_global },
    .{ .name = "external_constant", .text = external_constant_ir, .abis = &.{1}, .golden = golden_external_constant },
    .{ .name = "metadata_global", .text = metadata_global_ir, .abis = &.{ 1, 2 }, .golden = golden_metadata_global },
    .{ .name = "global_name_in_initializer", .text = global_name_in_initializer_ir, .abis = &.{1}, .golden = golden_global_name_in_initializer },
    .{ .name = "null_suffix_callee", .text = null_suffix_callee_ir, .abis = &.{1}, .golden = golden_null_suffix_callee },
};

fn goldenCase(name: []const u8) *const GoldenCase {
    for (&golden_cases) |*case| {
        if (eql(case.name, name)) return case;
    }
    unreachable;
}

fn abiName(abi_id: u8) []const u8 {
    return switch (abi_id) {
        1 => "sysv",
        2 => "win64",
        3 => "win32",
        4 => "aapcs64",
        else => "unknown",
    };
}

fn ptrSizeFor(abi_id: u8) u32 {
    return if (abi_id == 3) 4 else 8;
}

fn writeLoc(out: anytype, loc: abi.Loc) !void {
    try out.print("{d}:{d}:{d}:{d}", .{ loc.kind, loc.index, loc.size, loc.offset });
}

/// Canonical text image of one `CompileResult`. Every field that reaches
/// CIVM/CIPL is covered; the trailing `externals` list is CIPI's data set.
fn writeResult(out: anytype, abi_id: u8, ptr_size: u32, result: abi.CompileResult) !void {
    try out.print("abi={s} ptr={d}\n", .{ abiName(abi_id), ptr_size });
    for (result.functions) |func| {
        try out.print("fn {s} ret={s} params={d} locals={d} varargs={d}\n", .{
            func.name, func.ret, func.param_count, func.local_count, @intFromBool(func.is_varargs),
        });
        try out.print("  pnames=", .{});
        for (func.param_names, 0..) |name, i| {
            if (i != 0) try out.print(",", .{});
            try out.print("{s}", .{name});
        }
        try out.print(" ptypes=", .{});
        for (func.param_types, 0..) |ty, i| {
            if (i != 0) try out.print(",", .{});
            try out.print("{s}", .{ty});
        }
        try out.print(" pattrs=", .{});
        for (func.param_attrs, 0..) |attr, i| {
            if (i != 0) try out.print(",", .{});
            try out.print("{s}", .{attr});
        }
        try out.print("\n  code=", .{});
        for (func.code.items) |byte| try out.print("{x:0>2}", .{byte});
        try out.print("\n", .{});
    }
    for (result.plans) |plan| {
        try out.print("plan {s} args={d} retlocs={d} stack={d} sret={d} sse={d} retsize={d} conv={d}\n", .{
            plan.name, plan.args.len, plan.ret_locs.len, plan.stack_size,
            @intFromBool(plan.sret), plan.sse_count, plan.ret_size, plan.conv,
        });
        for (plan.args, 0..) |arg, i| {
            try out.print("  arg{d} size={d} align={d} struct={d} locs=", .{
                i, arg.size, arg.alignment, @intFromBool(arg.is_struct),
            });
            for (arg.locs, 0..) |loc, j| {
                if (j != 0) try out.print(",", .{});
                try writeLoc(out, loc);
            }
            try out.print("\n", .{});
        }
        try out.print("  retloc=", .{});
        for (plan.ret_locs, 0..) |loc, j| {
            if (j != 0) try out.print(",", .{});
            try writeLoc(out, loc);
        }
        try out.print("\n", .{});
    }
    try out.print("externals={d}\n", .{result.external_data.len});
    for (result.external_data) |name| try out.print("  ext {s}\n", .{name});
}

fn writeCase(allocator: Allocator, case: *const GoldenCase, out: anytype) !void {
    for (case.abis) |abi_id| {
        const ptr_size = ptrSizeFor(abi_id);
        var module = try parseFixture(allocator, case.text);
        const result = try compile(allocator, &module, abi_id, ptr_size);
        try writeResult(out, abi_id, ptr_size, result);
    }
}

fn expectGolden(allocator: Allocator, case: *const GoldenCase) !void {
    var buf = std.ArrayList(u8).init(allocator);
    try writeCase(allocator, case, buf.writer());
    try testing.expectEqualStrings(case.golden, buf.items);
}

test "clang18 parser fixture lowers to the golden CIVM/CIPL (SysV/Win64/AAPCS64)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("clang18"));
}

test "hello fixture lowers to the golden CIVM/CIPL (all ABIs)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("hello"));
}

test "structs fixture lowers to the golden CIVM/CIPL (all ABIs)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("structs"));
}

test "ffi_qsort fixture lowers to the golden CIVM/CIPL (all ABIs)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("ffi_qsort"));
}

test "ffi_callback fixture lowers to the golden CIVM/CIPL (all ABIs)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("ffi_callback"));
}

test "ffi_callback_scope fixture lowers to the golden CIVM/CIPL (all ABIs)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("ffi_callback_scope"));
}

// ------------------------------------------------- explicit callback builtins

fn functionIndexByName(result: abi.CompileResult, name: []const u8) ?u16 {
    for (result.functions, 0..) |func, index| {
        if (eql(func.name, name)) return @intCast(index);
    }
    return null;
}

fn planIndexByName(result: abi.CompileResult, name: []const u8) ?u16 {
    for (result.plans, 0..) |plan, index| {
        if (eql(plan.name, name)) return @intCast(index);
    }
    return null;
}

fn codeOf(result: abi.CompileResult, name: []const u8) []const u8 {
    for (result.functions) |func| {
        if (eql(func.name, name)) return func.code.items;
    }
    return &.{};
}

fn callbackPlanCount(result: abi.CompileResult) usize {
    var count: usize = 0;
    for (result.plans) |plan| {
        if (startsWith(plan.name, "callback:")) count += 1;
    }
    return count;
}

test "ci_callback_acquire/release lower to dedicated opcodes with one callback plan" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, callback_scope_ir);
    const result = try compile(allocator, &module, 1, 8);

    // Both builtins stay out of CIPI: no plan for them and no external-data
    // entry (`take` is the only declared symbol that reaches the table).
    try testing.expectEqual(@as(?u16, null), planIndexByName(result, callback_acquire_symbol));
    try testing.expectEqual(@as(?u16, null), planIndexByName(result, callback_release_symbol));
    for (result.external_data) |name| {
        try testing.expect(!eql(name, "@" ++ callback_acquire_symbol));
        try testing.expect(!eql(name, "@" ++ callback_release_symbol));
    }

    // One callback plan for the callee definition (`cb(i32, i32)` -> two
    // integer args on SysV), plus the `take` native plan.
    try testing.expectEqual(@as(usize, 1), callbackPlanCount(result));
    const cb_func = functionIndexByName(result, "cb").?;
    const cb_plan = planIndexByName(result, "callback:cb").?;
    try testing.expectEqual(@as(usize, 2), result.plans[cb_plan].args.len);
    try testing.expectEqual(@as(u8, 0), result.plans[cb_plan].conv);

    // OP_CALLBACK_ACQUIRE plan_index func_index, little-endian u16 operands.
    const code = codeOf(result, "main");
    var acquire_bytes: [5]u8 = undefined;
    acquire_bytes[0] = op.OP_CALLBACK_ACQUIRE;
    std.mem.writeInt(u16, acquire_bytes[1..3], cb_plan, .little);
    std.mem.writeInt(u16, acquire_bytes[3..5], cb_func, .little);
    const acquire_at = std.mem.indexOf(u8, code, &acquire_bytes);
    try testing.expect(acquire_at != null);

    // The release comes after it and takes no operands.
    const release_at = std.mem.indexOfScalar(u8, code, op.OP_CALLBACK_RELEASE);
    try testing.expect(release_at != null);
    try testing.expect(acquire_at.? < release_at.?);

    // The automatic path is untouched: acquire/release never allocate a
    // compile-time callback slot (`OP_CREATE_CALLBACK` is not emitted).
    try testing.expect(std.mem.indexOfScalar(u8, code, op.OP_CREATE_CALLBACK) == null);
}

test "ci_callback_acquire strips casts around the direct function reference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator,
        \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
        \\target triple = "x86_64-unknown-linux-gnu"
        \\
        \\declare ptr @__ci_callback_acquire(ptr)
        \\declare i32 @__ci_callback_release(ptr)
        \\
        \\define i32 @cb(i32 %a, i32 %b) {
        \\entry:
        \\  %r = add i32 %a, %b
        \\  ret i32 %r
        \\}
        \\
        \\define i32 @main() {
        \\entry:
        \\  %tramp = call ptr @__ci_callback_acquire(ptr bitcast (ptr @cb to ptr))
        \\  %status = call i32 @__ci_callback_release(ptr %tramp)
        \\  ret i32 %status
        \\}
        \\
    );
    const result = try compile(allocator, &module, 1, 8);

    const cb_func = functionIndexByName(result, "cb").?;
    const cb_plan = planIndexByName(result, "callback:cb") orelse return error.TestExpectedCallbackPlan;
    var acquire_bytes: [5]u8 = undefined;
    acquire_bytes[0] = op.OP_CALLBACK_ACQUIRE;
    std.mem.writeInt(u16, acquire_bytes[1..3], cb_plan, .little);
    std.mem.writeInt(u16, acquire_bytes[3..5], cb_func, .little);
    try testing.expect(std.mem.indexOf(u8, codeOf(result, "main"), &acquire_bytes) != null);
}

test "ci_callback_acquire requires a direct function reference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // A function pointer value (not a direct reference).
    var through_value = try parseFixture(allocator,
        \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
        \\target triple = "x86_64-unknown-linux-gnu"
        \\
        \\declare ptr @__ci_callback_acquire(ptr)
        \\
        \\define i32 @main(ptr %fn) {
        \\entry:
        \\  %tramp = call ptr @__ci_callback_acquire(ptr %fn)
        \\  ret i32 0
        \\}
        \\
    );
    try testing.expectError(error.CallbackAcquireRequiresFunctionRef, compile(allocator, &through_value, 1, 8));

    // A global that is not a function of this module.
    var through_global = try parseFixture(allocator,
        \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
        \\target triple = "x86_64-unknown-linux-gnu"
        \\
        \\@table = global i32 0, align 4
        \\
        \\declare ptr @__ci_callback_acquire(ptr)
        \\
        \\define i32 @main() {
        \\entry:
        \\  %tramp = call ptr @__ci_callback_acquire(ptr @table)
        \\  ret i32 0
        \\}
        \\
    );
    try testing.expectError(error.CallbackAcquireRequiresFunctionRef, compile(allocator, &through_global, 1, 8));
}

test "explicit acquire and the automatic callback path share one plan" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator,
        \\target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"
        \\target triple = "x86_64-unknown-linux-gnu"
        \\
        \\declare ptr @__ci_callback_acquire(ptr)
        \\declare i32 @__ci_callback_release(ptr)
        \\declare void @take(ptr)
        \\
        \\define i32 @cb(i32 %a, i32 %b) {
        \\entry:
        \\  %r = add i32 %a, %b
        \\  ret i32 %r
        \\}
        \\
        \\define i32 @main() {
        \\entry:
        \\  call void @take(ptr @cb)
        \\  %tramp = call ptr @__ci_callback_acquire(ptr @cb)
        \\  %status = call i32 @__ci_callback_release(ptr %tramp)
        \\  ret i32 %status
        \\}
        \\
    );
    const result = try compile(allocator, &module, 1, 8);

    // `emitCallback` (automatic) and `planCallback` (explicit) intern the same
    // `callback:cb` plan instead of emitting a second CIPL record.
    try testing.expectEqual(@as(usize, 1), callbackPlanCount(result));
    const cb_plan = planIndexByName(result, "callback:cb").?;
    const cb_func = functionIndexByName(result, "cb").?;

    const code = codeOf(result, "main");
    // Automatic: OP_CREATE_CALLBACK slot func plan, slot 0 for the first use.
    var create_bytes: [7]u8 = undefined;
    create_bytes[0] = op.OP_CREATE_CALLBACK;
    std.mem.writeInt(u16, create_bytes[1..3], 0, .little);
    std.mem.writeInt(u16, create_bytes[3..5], cb_func, .little);
    std.mem.writeInt(u16, create_bytes[5..7], cb_plan, .little);
    try testing.expect(std.mem.indexOf(u8, code, &create_bytes) != null);

    // Explicit: the same plan, no compile-time slot in the encoding.
    var acquire_bytes: [5]u8 = undefined;
    acquire_bytes[0] = op.OP_CALLBACK_ACQUIRE;
    std.mem.writeInt(u16, acquire_bytes[1..3], cb_plan, .little);
    std.mem.writeInt(u16, acquire_bytes[3..5], cb_func, .little);
    try testing.expect(std.mem.indexOf(u8, code, &acquire_bytes) != null);
}

test "misc fixture lowers to the golden CIVM/CIPL (all ABIs)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("misc"));
}

test "phi/switch/select/volatile lower to the golden CIVM/CIPL" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("control_flow"));
}

test "setjmp/longjmp and runtime intrinsics lower to the golden CIVM/CIPL" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try expectGolden(arena.allocator(), goldenCase("intrinsics"));
}

test "null callee calls lower to no instructions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, null_callee_ir);
    const result = try compile(allocator, &module, 1, 8);
    try testing.expectEqual(@as(usize, 1), result.functions.len);
    // The call is dropped; only the return instruction remains.
    try testing.expectEqualSlices(u8, &.{op.OP_RET_VOID}, result.functions[0].code.items);

    var args_module = try parseFixture(allocator, null_callee_args_ir);
    const args_result = try compile(allocator, &args_module, 1, 8);
    try testing.expectEqualSlices(u8, &.{op.OP_RET_VOID}, args_result.functions[0].code.items);

    try expectGolden(allocator, goldenCase("null_callee"));
    try expectGolden(allocator, goldenCase("null_callee_args"));
}

/// Count `OP_LOAD_CONST_I64 value` sequences in emitted CIVM code.
fn countConstI64(code: []const u8, value: i64) usize {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, @bitCast(value), .little);
    var count: usize = 0;
    var i: usize = 0;
    while (i + 9 <= code.len) : (i += 1) {
        if (code[i] != op.OP_LOAD_CONST_I64) continue;
        if (std.mem.eql(u8, code[i + 1 .. i + 9], &buf)) count += 1;
    }
    return count;
}

test "decimal and hex f32 literals in stores, globals and call args" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, f32_literals_ir);

    // 69.12f has the f32 bit pattern 0x428A3D71. The double spelling LLVM
    // prints for `float` (0x405147AE20000000) must round-trip to the same f32.
    const fdec = module.findGlobal("fdec").?.init.?.float;
    try testing.expectEqual(@as(u16, 32), fdec.width);
    try testing.expectEqual(@as(u128, 0x428A3D71), fdec.bits);
    const fhex = module.findGlobal("fhex").?.init.?.float;
    try testing.expectEqual(@as(u16, 32), fhex.width);
    try testing.expectEqual(@as(u128, 0x428A3D71), fhex.bits);

    // Global data image: both float globals carry the f32 pattern; the double
    // carries the f64 pattern.
    const data = try TestHook.globalData(allocator, &module, 8);
    try testing.expectEqual(@as(usize, 16), data.len);
    try testing.expectEqualSlices(u8, &.{ 0x71, 0x3D, 0x8A, 0x42 }, data[0..4]);
    try testing.expectEqualSlices(u8, &.{ 0x71, 0x3D, 0x8A, 0x42 }, data[4..8]);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0xE1, 0x7A, 0x14, 0xAE, 0x47, 0x51, 0x40 }, data[8..16]);

    const result = try compile(allocator, &module, 1, 8);
    const func = result.functions[0];
    try testing.expectEqualStrings("literal_args", func.name);
    // store fdec + store fhex + take_float(fdec) + take_float(fhex).
    try testing.expectEqual(@as(usize, 4), countConstI64(func.code.items, @bitCast(@as(u64, 0x428A3D71))));
    // take_double arg.
    try testing.expectEqual(@as(usize, 1), countConstI64(func.code.items, @bitCast(@as(u64, 0x405147AE147AE148))));

    try expectGolden(allocator, goldenCase("f32_literals"));
}

test "ast lowering consumes the parsed AST, not the source text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, fixture_ffi_qsort);
    const before = try compile(allocator, &module, 1, 8);

    // Mutating a parsed global initialiser must change the emitted data-image
    // install in `main`; if the AST were ignored this would be a no-op.
    try testing.expect(module.globals.len > 0);
    const mutable_globals = try allocator.dupe(ast.Global, module.globals);
    module.globals = mutable_globals;
    mutable_globals[0].init = .{ .zeroinitializer = .{} };
    const after = try compile(allocator, &module, 1, 8);

    try testing.expectEqual(before.functions.len, after.functions.len);
    var differ = false;
    for (before.functions, after.functions) |b, a| {
        if (!std.mem.eql(u8, b.code.items, a.code.items)) differ = true;
    }
    try testing.expect(differ);
}

fn findReloc(relocs: []const TestHook.RelocInfo, target: []const u8) ?TestHook.RelocInfo {
    for (relocs) |reloc| {
        if (eql(reloc.target, target)) return reloc;
    }
    return null;
}

test "global layout, nested aggregates and multi-index GEP relocations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Layout: .str@0 (4B), %struct.Inner@4 (align 4), %struct.Outer@16,
    // [4 x i32] arr@48 (align 16), @elem@64, @field@72.
    const data = blk: {
        var module = try parseFixture(allocator, globals_ir);
        break :blk try TestHook.globalData(allocator, &module, 8);
    };
    try testing.expectEqual(@as(usize, 80), data.len);
    try testing.expectEqualStrings("abc\x00", data[0..4]);
    // %struct.Inner { i32 7, [2 x i16] [1, 2] }: 07 00 00 00 01 00 02 00
    try testing.expectEqualSlices(u8, &.{ 7, 0, 0, 0, 1, 0, 2, 0 }, data[4..12]);
    // %struct.Outer { 1, {9, [3, 4]}, [@.str, null] }: Inner lands at offset 4
    // (i8 + padding), the pointer array at offset 16.
    try testing.expectEqual(@as(u8, 1), data[16]);
    try testing.expectEqualSlices(u8, &.{ 9, 0, 0, 0, 3, 0, 4, 0 }, data[20..28]);
    try testing.expectEqualSlices(u8, &.{ 10, 0, 0, 0, 20, 0, 0, 0, 30, 0, 0, 0, 40, 0, 0, 0 }, data[48..64]);
    // Pointer slots stay zeroed; the relocations below fill them in at load.
    try testing.expectEqualSlices(u8, &[_]u8{0} ** 8, data[32..40]);
    try testing.expectEqualSlices(u8, &[_]u8{0} ** 8, data[64..72]);

    // Compatibility GEP mode folds only the first index (addend 0 for both GEP
    // initialisers); @elem's and @field's later indices are ignored on purpose.
    {
        var module = try parseFixture(allocator, globals_ir);
        const relocs = try TestHook.globalRelocs(allocator, &module, 8, .legacy);
        try testing.expectEqual(@as(usize, 3), relocs.len);
        // @outer's [2 x ptr] [ptr @.str, ptr null] -> @.str at outer+16.
        const str_reloc = findReloc(relocs, "@.str").?;
        try testing.expectEqual(@as(u32, 32), str_reloc.offset);
        try testing.expectEqual(@as(i64, 0), str_reloc.addend);
        const arr_reloc = findReloc(relocs, "@arr").?;
        try testing.expectEqual(@as(u32, 64), arr_reloc.offset);
        try testing.expectEqual(@as(i64, 0), arr_reloc.addend);
        const field_reloc = findReloc(relocs, "@outer").?;
        try testing.expectEqual(@as(u32, 72), field_reloc.offset);
        try testing.expectEqual(@as(i64, 0), field_reloc.addend);
    }
    // Correct GEP mode walks every index: [4 x i32] index 2 -> 8 bytes;
    // %struct.Outer indices (0, 2) -> field offset 16, [2 x ptr] index 0.
    {
        var module = try parseFixture(allocator, globals_ir);
        const relocs = try TestHook.globalRelocs(allocator, &module, 8, .correct);
        try testing.expectEqual(@as(usize, 3), relocs.len);
        try testing.expectEqual(@as(i64, 8), findReloc(relocs, "@arr").?.addend);
        try testing.expectEqual(@as(i64, 16), findReloc(relocs, "@outer").?.addend);
        try testing.expectEqual(@as(i64, 0), findReloc(relocs, "@.str").?.addend);
    }

    try expectGolden(allocator, goldenCase("globals"));
}

test "global inttoptr initializer is materialized" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, inttoptr_global_ir);
    const data = try TestHook.globalData(allocator, &module, 8);
    try testing.expectEqual(@as(usize, 16), data.len);
    // 40960 == 0xA000, little-endian pointer image.
    try testing.expectEqualSlices(u8, &.{ 0x00, 0xA0, 0, 0, 0, 0, 0, 0 }, data[0..8]);
    try testing.expectEqualSlices(u8, &.{ 7, 0, 0, 0 }, data[8..12]);

    const result = try compile(allocator, &module, 1, 8);
    try testing.expectEqual(@as(usize, 1), countConstI64(result.functions[0].code.items, 40960));
    try testing.expectEqual(@as(usize, 0), result.external_data.len);

    try expectGolden(allocator, goldenCase("inttoptr_global"));
}

test "external constant declarations are imported and addressed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, external_constant_ir);
    const result = try compile(allocator, &module, 1, 8);
    try testing.expectEqual(@as(usize, 1), result.external_data.len);
    try testing.expectEqualStrings("@a", result.external_data[0]);
    // The comparison must use the external symbol address, not constant 0.
    try testing.expect(std.mem.indexOf(u8, result.functions[0].code.items, &.{ op.OP_ADDR_EXTERN, 0, 0 }) != null);

    try expectGolden(allocator, goldenCase("external_constant"));
}

test "llvm metadata globals do not reserve VM storage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, metadata_global_ir);
    const data = try TestHook.globalData(allocator, &module, 8);
    // i, j and k only; @llvm.compiler.used is linker metadata, not a VM object.
    try testing.expectEqual(@as(usize, 16), data.len);

    try expectGolden(allocator, goldenCase("metadata_global"));
}

test "initializer mentioning a global name keeps the global allocated" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, global_name_in_initializer_ir);
    // Layout: @test.const_test (8B) @0, @global_int @8, @flag @12,
    // @global_test @16; total 24 bytes.
    const data = try TestHook.globalData(allocator, &module, 8);
    try testing.expectEqual(@as(usize, 24), data.len);
    const relocs = try TestHook.globalRelocs(allocator, &module, 8, .legacy);
    try testing.expectEqual(@as(usize, 1), relocs.len);
    try testing.expectEqual(@as(u32, 0), relocs[0].offset);
    try testing.expectEqualStrings("@global_int", relocs[0].target);

    const result = try compile(allocator, &module, 1, 8);
    // The load of @flag must use offset 12, after the constant object.
    try testing.expect(std.mem.indexOf(u8, result.functions[0].code.items, &.{ op.OP_ADDR_CONST, 12, 0, 0, 0 }) != null);

    try expectGolden(allocator, goldenCase("global_name_in_initializer"));
}

test "call result is kept when the callee name ends in null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, null_suffix_callee_ir);
    const result = try compile(allocator, &module, 1, 8);
    const main_func = result.functions[2];
    try testing.expectEqualStrings("main", main_func.name);
    // @getnull is function 0, @foo is function 1: both calls must be present.
    try testing.expect(std.mem.indexOf(u8, main_func.code.items, &.{ op.OP_CALL, 0, 0 }) != null);
    try testing.expect(std.mem.indexOf(u8, main_func.code.items, &.{ op.OP_CALL, 1, 0 }) != null);

    try expectGolden(allocator, goldenCase("null_suffix_callee"));
}

/// AArch64 IR for a call that returns a named aggregate and forwards another
/// one as an argument (the shape clang emits for `D16`).
const aapcs64_named_struct_ir =
    \\%struct.D16 = type { double, double }
    \\
    \\define i32 @main() {
    \\entry:
    \\  %call = call %struct.D16 @c_make_d16(double 1.500000e+00, double 2.500000e+00)
    \\  %a = extractvalue %struct.D16 %call, 0
    \\  %b = extractvalue %struct.D16 %call, 1
    \\  %s = fadd double %a, %b
    \\  %t = call double @c_take_d16(%struct.D16 %call)
    \\  %u = fadd double %s, %t
    \\  %r = fptosi double %u to i32
    \\  ret i32 %r
    \\}
    \\
    \\declare %struct.D16 @c_make_d16(double, double)
    \\
    \\declare double @c_take_d16(%struct.D16)
    \\
;

test "AAPCS64 plans expand named structs to their literal body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator, aapcs64_named_struct_ir);
    const result = try compile(allocator, &module, 4, 8);

    // Function metadata keeps the canonical IR spelling.
    try testing.expectEqualStrings("i32", result.functions[0].ret);
    try testing.expectEqualStrings("main", result.functions[0].name);

    try testing.expectEqual(@as(usize, 2), result.plans.len);

    // `%struct.D16` is expanded to `{ double, double }`: an HFA returning in
    // v0/v1 and taking its two scalar doubles in v0/v1.
    const make = result.plans[0];
    try testing.expectEqualStrings("c_make_d16", make.name);
    try testing.expectEqual(@as(usize, 2), make.ret_locs.len);
    try testing.expectEqual(@as(u8, 6), make.ret_locs[0].kind);
    try testing.expectEqual(@as(u8, 7), make.ret_locs[1].kind);
    try testing.expectEqual(@as(u16, 16), make.ret_size);
    try testing.expectEqual(@as(u8, 1), make.args[0].locs[0].kind);
    try testing.expectEqual(@as(u8, 1), make.args[1].locs[0].kind);

    // The `%struct.D16` argument is expanded too: one two-register HFA.
    const take = result.plans[1];
    try testing.expectEqualStrings("c_take_d16", take.name);
    try testing.expect(take.args[0].is_struct);
    try testing.expectEqual(@as(u16, 16), take.args[0].size);
    try testing.expectEqual(@as(usize, 2), take.args[0].locs.len);
    try testing.expectEqual(@as(u8, 1), take.args[0].locs[0].kind);
    try testing.expectEqual(@as(u16, 0), take.args[0].locs[0].index);
    try testing.expectEqual(@as(u16, 1), take.args[0].locs[1].index);

    // A name the module never defines stays unexpanded and is reported as an
    // unsupported ABI shape instead of being misclassified.
    var unknown = try parseFixture(allocator,
        \\%struct.Unknown = type opaque
        \\
        \\declare i32 @c_take_unknown(%struct.Unknown)
        \\
        \\define i32 @main() {
        \\entry:
        \\  %r = call i32 @c_take_unknown(%struct.Unknown zeroinitializer)
        \\  ret i32 %r
        \\}
        \\
    );
    try testing.expectError(error.UnsupportedFfi, compile(allocator, &unknown, 4, 8));
}

test "plansEqual compares every serialized plan field" {
    var locs = [_]abi.Loc{.{ .kind = 0, .index = 1, .size = 8, .offset = 0 }};
    var ret = [_]abi.Loc{.{ .kind = 4, .index = 0, .size = 4, .offset = 0 }};
    var arg_list = [_]abi.ArgPlan{.{ .locs = &locs, .size = 8, .alignment = 8 }};
    const base = abi.Plan{
        .name = "foo",
        .args = &arg_list,
        .ret_locs = &ret,
        .stack_size = 0,
        .sret = false,
        .sse_count = 0,
        .ret_size = 4,
        .conv = 0,
    };
    try testing.expect(plansEqual(base, base));

    // Different symbol names never compare equal, whatever the layout.
    var other = base;
    other.name = "bar";
    try testing.expect(!plansEqual(base, other));

    other = base;
    other.conv = 1;
    try testing.expect(!plansEqual(base, other));

    other = base;
    other.stack_size = 8;
    try testing.expect(!plansEqual(base, other));

    other = base;
    other.sret = true;
    try testing.expect(!plansEqual(base, other));

    other = base;
    other.sse_count = 1;
    try testing.expect(!plansEqual(base, other));

    other = base;
    other.ret_size = 8;
    try testing.expect(!plansEqual(base, other));

    var alt_locs = [_]abi.Loc{locs[0]};
    alt_locs[0].index = 2;
    var alt_arg = [_]abi.ArgPlan{.{ .locs = &alt_locs, .size = 8, .alignment = 8 }};
    other = base;
    other.args = &alt_arg;
    try testing.expect(!plansEqual(base, other));

    var size_arg = [_]abi.ArgPlan{.{ .locs = &locs, .size = 4, .alignment = 8 }};
    other = base;
    other.args = &size_arg;
    try testing.expect(!plansEqual(base, other));

    var align_arg = [_]abi.ArgPlan{.{ .locs = &locs, .size = 8, .alignment = 4 }};
    other = base;
    other.args = &align_arg;
    try testing.expect(!plansEqual(base, other));

    var struct_arg = [_]abi.ArgPlan{.{ .locs = &locs, .size = 8, .alignment = 8, .is_struct = true }};
    other = base;
    other.args = &struct_arg;
    try testing.expect(!plansEqual(base, other));

    var two_locs = [_]abi.Loc{ locs[0], locs[0] };
    var two_loc_arg = [_]abi.ArgPlan{.{ .locs = &two_locs, .size = 8, .alignment = 8 }};
    other = base;
    other.args = &two_loc_arg;
    try testing.expect(!plansEqual(base, other));

    var alt_ret = [_]abi.Loc{.{ .kind = 5, .index = 0, .size = 4, .offset = 0 }};
    other = base;
    other.ret_locs = &alt_ret;
    try testing.expect(!plansEqual(base, other));

    // Every Loc field participates.
    var ret_index = [_]abi.Loc{.{ .kind = 4, .index = 1, .size = 4, .offset = 0 }};
    other = base;
    other.ret_locs = &ret_index;
    try testing.expect(!plansEqual(base, other));

    var ret_offset = [_]abi.Loc{.{ .kind = 4, .index = 0, .size = 4, .offset = 8 }};
    other = base;
    other.ret_locs = &ret_offset;
    try testing.expect(!plansEqual(base, other));

    var ret_size = [_]abi.Loc{.{ .kind = 4, .index = 0, .size = 8, .offset = 0 }};
    other = base;
    other.ret_locs = &ret_size;
    try testing.expect(!plansEqual(base, other));
}

test "identical native call signatures share one plan, different symbols do not" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const dedup_ir =
        \\declare i32 @foo(i32)
        \\declare i32 @bar(i32)
        \\
        \\define i32 @main() {
        \\entry:
        \\  %a = call i32 @foo(i32 1)
        \\  %b = call i32 @foo(i32 2)
        \\  %c = call i32 @bar(i32 3)
        \\  %d = add i32 %a, %b
        \\  %e = add i32 %c, %d
        \\  ret i32 %e
        \\}
        \\
    ;
    var module = try parseFixture(allocator, dedup_ir);
    const result = try compile(allocator, &module, 1, 8);
    // foo(x) is called twice -> one plan; bar(x) has the same layout but a
    // different symbol name -> a second plan.
    try testing.expectEqual(@as(usize, 2), result.plans.len);
    try testing.expectEqualStrings("foo", result.plans[0].name);
    try testing.expectEqualStrings("bar", result.plans[1].name);
}

test "calling conventions flow into plans: call site, declaration, indirect and callback" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Win32 `__stdcall` direct call: the call instruction carries the cconv.
    var stdcall_module = try parseFixture(allocator,
        \\declare x86_stdcallcc i32 @c_std_add3(i32, i32, i32)
        \\
        \\define i32 @main() {
        \\entry:
        \\  %r = call x86_stdcallcc i32 @c_std_add3(i32 10, i32 20, i32 30)
        \\  ret i32 %r
        \\}
        \\
    );
    const stdcall_result = try compile(allocator, &stdcall_module, 3, 4);
    try testing.expectEqual(@as(usize, 1), stdcall_result.plans.len);
    try testing.expectEqual(@as(u8, 1), stdcall_result.plans[0].conv);

    // No cconv at the call site: fall back to the declaration (`__fastcall`).
    var fastcall_module = try parseFixture(allocator,
        \\declare x86_fastcallcc i32 @fast_add(i32, i32, i32)
        \\
        \\define i32 @main() {
        \\entry:
        \\  %r = call i32 @fast_add(i32 1, i32 2, i32 3)
        \\  ret i32 %r
        \\}
        \\
    );
    const fastcall_result = try compile(allocator, &fastcall_module, 3, 4);
    try testing.expectEqual(@as(usize, 1), fastcall_result.plans.len);
    try testing.expectEqual(@as(u8, 2), fastcall_result.plans[0].conv);

    // Indirect call through a `__stdcall` function pointer.
    var indirect_module = try parseFixture(allocator,
        \\define i32 @run(ptr %fp) {
        \\entry:
        \\  %r = call x86_stdcallcc i32 %fp(i32 1, i32 2)
        \\  ret i32 %r
        \\}
        \\
    );
    const indirect_result = try compile(allocator, &indirect_module, 3, 4);
    try testing.expectEqual(@as(usize, 1), indirect_result.plans.len);
    try testing.expectEqualStrings("indirect", indirect_result.plans[0].name);
    try testing.expectEqual(@as(u8, 1), indirect_result.plans[0].conv);

    // Callback plan uses the *callee definition's* convention.
    var callback_module = try parseFixture(allocator,
        \\define x86_stdcallcc i32 @cb(i32 %a, i32 %b) {
        \\entry:
        \\  %r = add i32 %a, %b
        \\  ret i32 %r
        \\}
        \\
        \\declare void @take(ptr)
        \\
        \\define i32 @main() {
        \\entry:
        \\  call void @take(ptr @cb)
        \\  ret i32 0
        \\}
        \\
    );
    const callback_result = try compile(allocator, &callback_module, 3, 4);
    try testing.expectEqual(@as(usize, 2), callback_result.plans.len);
    try testing.expectEqualStrings("take", callback_result.plans[0].name);
    try testing.expectEqual(@as(u8, 0), callback_result.plans[0].conv);
    try testing.expectEqualStrings("callback:cb", callback_result.plans[1].name);
    try testing.expectEqual(@as(u8, 1), callback_result.plans[1].conv);
}

test "Win64 variadic lowering duplicates FP args (printf shape)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try parseFixture(allocator,
        \\declare i32 @printf(ptr, ...)
        \\
        \\define i32 @main() {
        \\entry:
        \\  %r = call i32 (ptr, ...) @printf(ptr null, double 1.500000e+00, i32 7)
        \\  ret i32 %r
        \\}
        \\
    );
    const result = try compile(allocator, &module, 2, 8);
    try testing.expectEqual(@as(usize, 1), result.plans.len);
    const plan = result.plans[0];
    try testing.expectEqualStrings("printf", plan.name);
    // ptr -> RCX, double -> XMM1 + RDX, int -> R8.
    try testing.expectEqual(@as(u8, 0), plan.args[0].locs[0].kind);
    try testing.expectEqual(@as(u16, 0), plan.args[0].locs[0].index);
    try testing.expectEqual(@as(usize, 2), plan.args[1].locs.len);
    try testing.expectEqual(@as(u8, 1), plan.args[1].locs[0].kind);
    try testing.expectEqual(@as(u16, 1), plan.args[1].locs[0].index);
    try testing.expectEqual(@as(u8, 0), plan.args[1].locs[1].kind);
    try testing.expectEqual(@as(u16, 1), plan.args[1].locs[1].index);
    try testing.expectEqual(@as(u8, 0), plan.args[2].locs[0].kind);
    try testing.expectEqual(@as(u16, 2), plan.args[2].locs[0].index);
    try testing.expectEqual(@as(u8, 1), plan.sse_count);
}

test "write golden files" {
    const enabled = std.process.getEnvVarOwned(testing.allocator, "CINTERP_WRITE_GOLDEN") catch return;
    defer testing.allocator.free(enabled);
    if (!eql(enabled, "1")) return;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for (&golden_cases) |*case| {
        var buf = std.ArrayList(u8).init(allocator);
        try writeCase(allocator, case, buf.writer());
        const path = try std.fmt.allocPrint(allocator, "src/testdata/lower_ast/golden/{s}.golden", .{case.name});
        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = buf.items });
        std.debug.print("wrote {s} ({d} bytes)\n", .{ path, buf.items.len });
    }
}
