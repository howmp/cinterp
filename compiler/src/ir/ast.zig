//! Typed AST for the LLVM IR subset consumed by the cinterp Zig frontend.
//!
//! Ownership: every slice and pointer in this file is owned by the allocator
//! that `ir/parser.zig` was given. The parser never frees anything and the AST
//! exposes no `deinit`; callers are expected to parse into an
//! `std.heap.ArenaAllocator`. All `[]const u8` name/text slices point into the
//! source buffer that was parsed (no copies are made).
//!
//! Spans carry the 1-based `line`/`column` of the construct start so that
//! diagnostics and verifier errors can point at source locations after the
//! parser has finished.

const std = @import("std");
const lexer = @import("lexer.zig");

pub const Span = lexer.Span;

// ---------------------------------------------------------------- named values

/// A `%local`, `@global` or block label reference.
pub const NamedRef = struct {
    /// Name without the sigil. Quoted names keep their escapes verbatim.
    name: []const u8,
    /// True when the source form was `%"..."` / `@"..."`.
    quoted: bool = false,
    /// Set when the name is a bare number (`%0`, `%42`, label `3:`).
    number: ?u32 = null,
    span: Span = .{},

    pub fn isNumber(self: NamedRef) bool {
        return self.number != null;
    }
};

// ------------------------------------------------------------------- types

pub const FloatKind = enum(u8) {
    half,
    bfloat,
    float,
    double,
    x86_fp80,
    fp128,
    ppc_fp128,

    pub fn keyword(self: FloatKind) []const u8 {
        return switch (self) {
            .half => "half",
            .bfloat => "bfloat",
            .float => "float",
            .double => "double",
            .x86_fp80 => "x86_fp80",
            .fp128 => "fp128",
            .ppc_fp128 => "ppc_fp128",
        };
    }

    pub fn bits(self: FloatKind) u16 {
        return switch (self) {
            .half => 16,
            .bfloat => 16,
            .float => 32,
            .double => 64,
            .x86_fp80 => 80,
            .fp128 => 128,
            .ppc_fp128 => 128,
        };
    }
};

pub const IntType = struct { bits: u32, span: Span = .{} };
pub const FloatType = struct { kind: FloatKind, span: Span = .{} };
pub const PtrType = struct { addr_space: u32 = 0, span: Span = .{} };
pub const ArrayType = struct { count: u64, elem: *const Type, span: Span = .{} };
pub const VectorType = struct {
    count: u64,
    elem: *const Type,
    scalable: bool = false,
    span: Span = .{},
};
pub const StructType = struct {
    fields: []const *const Type = &.{},
    is_packed: bool = false,
    /// `= type opaque`: no known body.
    is_opaque: bool = false,
    span: Span = .{},
};
/// Reference to a named type (`%struct.Pk`); resolution is a lowering concern.
pub const NamedType = struct { name: []const u8, span: Span = .{} };
pub const FunctionType = struct {
    ret: *const Type,
    params: []const *const Type,
    varargs: bool = false,
    span: Span = .{},
};

pub const Type = union(enum) {
    void,
    /// `metadata` (only valid as a call/parameter type).
    metadata,
    /// `token`
    token,
    /// `label`
    label,
    int: IntType,
    float: FloatType,
    ptr: PtrType,
    array: ArrayType,
    vector: VectorType,
    struct_: StructType,
    named: NamedType,
    function: FunctionType,

    pub fn isVoid(self: Type) bool {
        return self == .void;
    }

    pub fn isInteger(self: Type) bool {
        return self == .int;
    }

    pub fn intBits(self: Type) ?u32 {
        return switch (self) {
            .int => |t| t.bits,
            else => null,
        };
    }

    pub fn isFloat(self: Type) bool {
        return self == .float;
    }

    pub fn floatKind(self: Type) ?FloatKind {
        return switch (self) {
            .float => |t| t.kind,
            else => null,
        };
    }

    pub fn isPointer(self: Type) bool {
        return self == .ptr;
    }

    pub fn isAggregate(self: Type) bool {
        return switch (self) {
            .array, .vector, .struct_ => true,
            else => false,
        };
    }

    /// Structural equality. Named types compare by name; spans are ignored.
    pub fn eql(a: Type, b: Type) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .void, .metadata, .token, .label => true,
            .int => |x| x.bits == b.int.bits,
            .float => |x| x.kind == b.float.kind,
            .ptr => |x| x.addr_space == b.ptr.addr_space,
            .array => |x| x.count == b.array.count and x.elem.eql(b.array.elem.*),
            .vector => |x| x.count == b.vector.count and x.scalable == b.vector.scalable and
                x.elem.eql(b.vector.elem.*),
            .struct_ => |x| blk: {
                if (x.is_packed != b.struct_.is_packed or x.is_opaque != b.struct_.is_opaque) break :blk false;
                if (x.fields.len != b.struct_.fields.len) break :blk false;
                for (x.fields, b.struct_.fields) |fa, fb| {
                    if (!fa.eql(fb.*)) break :blk false;
                }
                break :blk true;
            },
            .named => |x| std.mem.eql(u8, x.name, b.named.name),
            .function => |x| blk: {
                if (x.varargs != b.function.varargs) break :blk false;
                if (x.params.len != b.function.params.len) break :blk false;
                if (!x.ret.eql(b.function.ret.*)) break :blk false;
                for (x.params, b.function.params) |pa, pb| {
                    if (!pa.eql(pb.*)) break :blk false;
                }
                break :blk true;
            },
        };
    }

    pub fn format(
        self: Type,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        _ = fmt;
        _ = options;
        try renderType(writer, &self);
    }

    pub fn toString(self: Type, allocator: std.mem.Allocator) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();
        try renderType(list.writer(), &self);
        return list.toOwnedSlice();
    }
};

pub fn renderType(writer: anytype, ty: *const Type) anyerror!void {
    switch (ty.*) {
        .void => try writer.writeAll("void"),
        .metadata => try writer.writeAll("metadata"),
        .token => try writer.writeAll("token"),
        .label => try writer.writeAll("label"),
        .int => |t| try writer.print("i{d}", .{t.bits}),
        .float => |t| try writer.writeAll(t.kind.keyword()),
        .ptr => |t| {
            if (t.addr_space == 0) {
                try writer.writeAll("ptr");
            } else {
                try writer.print("ptr addrspace({d})", .{t.addr_space});
            }
        },
        .array => |t| {
            try writer.print("[{d} x ", .{t.count});
            try renderType(writer, t.elem);
            try writer.writeAll("]");
        },
        .vector => |t| {
            try writer.writeAll("<");
            if (t.scalable) try writer.writeAll("vscale x ");
            try writer.print("{d} x ", .{t.count});
            try renderType(writer, t.elem);
            try writer.writeAll(">");
        },
        .struct_ => |t| {
            if (t.is_opaque) {
                try writer.writeAll("opaque");
            } else if (t.is_packed) {
                try writer.writeAll("<{");
                for (t.fields, 0..) |field, i| {
                    try writer.writeAll(if (i == 0) " " else ", ");
                    try renderType(writer, field);
                }
                try writer.writeAll(" }>");
            } else {
                try writer.writeByte('{');
                for (t.fields, 0..) |field, i| {
                    try writer.writeAll(if (i == 0) " " else ", ");
                    try renderType(writer, field);
                }
                try writer.writeAll(" }");
            }
        },
        .named => |t| {
            try writer.writeAll("%");
            try writer.writeAll(t.name);
        },
        .function => |t| {
            try renderType(writer, t.ret);
            try writer.writeAll(" (");
            for (t.params, 0..) |param, i| {
                if (i != 0) try writer.writeAll(", ");
                try renderType(writer, param);
            }
            if (t.varargs) {
                if (t.params.len != 0) try writer.writeAll(", ");
                try writer.writeAll("...");
            }
            try writer.writeAll(")");
        },
    }
}

// ------------------------------------------------------------------- values

pub const IntLiteral = struct {
    span: Span = .{},
    /// Digits exactly as written, without a leading sign.
    digits: []const u8,
    negative: bool = false,
    /// Magnitude; saturates and sets `overflow` for literals wider than u128.
    magnitude: u128 = 0,
    overflow: bool = false,
    /// True for `u0x...` / `s0x...` hexadecimal integer literals; `digits` then
    /// holds the hex digits (no prefix).
    hex: bool = false,

    /// Value as an `i64` when it is representable, null otherwise. Never
    /// panics on out-of-range literals (including `i64` minimum).
    pub fn toI64(self: IntLiteral) ?i64 {
        if (self.overflow) return null;
        if (self.magnitude > @as(u128, std.math.maxInt(u64))) return null;
        if (!self.negative) {
            if (self.magnitude > @as(u128, std.math.maxInt(i64))) return null;
            return @intCast(self.magnitude);
        }
        const min_magnitude: u128 = @as(u128, std.math.maxInt(i64)) + 1;
        if (self.magnitude > min_magnitude) return null;
        if (self.magnitude == min_magnitude) return std.math.minInt(i64);
        return -@as(i64, @intCast(self.magnitude));
    }
};

pub const FloatLiteral = struct {
    pub const Form = enum { decimal, hex };

    span: Span = .{},
    form: Form = .decimal,
    /// Exact source text of the literal (e.g. `0xK3FFFC000000000000000`).
    raw: []const u8,
    /// APFloat specifier letter written after `0x` (`H`/`K`/`L`/`M`/`R`) or 0.
    hex_spec: u8 = 0,
    /// Number of hex digits written (hex form only).
    hex_digits: u8 = 0,
    /// Bit pattern, most significant bit first, in the IEEE/x87 layout of the
    /// written width. clang 18 prints `fp128` as two 64-bit words with the low
    /// word first; that quirk is undone here so `bits` is always the canonical
    /// big-endian pattern (sign bit at bit `width - 1`).
    bits: u128 = 0,
    /// Width in bits implied by the literal (0 when unknown).
    width: u16 = 0,
    /// Parsed value for decimal forms (f64 precision). Null for hex forms.
    value: ?f64 = null,
    /// False when a decimal literal could not be represented exactly for the
    /// destination type (x86_fp80 / fp128 decimal forms).
    exact: bool = true,

    /// Storage size in bytes implied by `width`.
    pub fn byteLen(self: FloatLiteral) u16 {
        return switch (self.width) {
            0 => 0,
            80 => 10,
            else => (self.width + 7) / 8,
        };
    }

    /// Write the little-endian in-memory representation of the constant.
    /// Returns the number of bytes written (clamped to `out.len`).
    pub fn writeLeBytes(self: FloatLiteral, out: []u8) usize {
        const n = @min(@as(usize, self.byteLen()), out.len);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            out[i] = @truncate(self.bits >> @intCast(i * 8));
        }
        return n;
    }
};

pub const StringLiteral = struct {
    span: Span = .{},
    /// Contents between the quotes with escapes still present.
    raw: []const u8,
    is_c: bool = false,

    /// Decode `\XX` hex escapes (and `\\`, `\"`) into bytes.
    /// The returned slice is allocated from `allocator`.
    pub fn decode(self: StringLiteral, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        var i: usize = 0;
        while (i < self.raw.len) {
            const c = self.raw[i];
            if (c == '\\' and i + 1 < self.raw.len) {
                if (i + 2 < self.raw.len and std.ascii.isHex(self.raw[i + 1]) and std.ascii.isHex(self.raw[i + 2])) {
                    const hi = std.fmt.charToDigit(self.raw[i + 1], 16) catch 0;
                    const lo = std.fmt.charToDigit(self.raw[i + 2], 16) catch 0;
                    try out.append(hi * 16 + lo);
                    i += 3;
                    continue;
                }
                switch (self.raw[i + 1]) {
                    '\\' => {
                        try out.append('\\');
                        i += 2;
                        continue;
                    },
                    '"' => {
                        try out.append('"');
                        i += 2;
                        continue;
                    },
                    else => {},
                }
            }
            try out.append(c);
            i += 1;
        }
        return out.toOwnedSlice();
    }
};

pub const Aggregate = struct {
    pub const Kind = enum { braces, brackets, angles };

    kind: Kind = .braces,
    /// `<{ ... }>` packed struct literal (kind stays `.angles`).
    packed_braces: bool = false,
    elems: []const TypedValue = &.{},
    span: Span = .{},

    pub fn braces(self: Aggregate) bool {
        return self.kind == .braces;
    }
};

pub const MetadataRef = union(enum) {
    pub const Named = struct {
        /// Keyword without the leading `!` (e.g. `DIExpression`).
        name: []const u8,
        /// True when a `(...)` payload followed.
        has_args: bool = false,
        /// Source text including the `(...)` payload, when present.
        raw: []const u8 = "",
        span: Span = .{},
    };

    pub const Node = struct {
        /// Source text of the `{ ... }` payload, braces included.
        raw: []const u8,
        span: Span = .{},
    };

    id: u32,
    named: Named,
    node: Node,
};

pub const MetadataAttachment = struct {
    /// Attachment name without `!` (`dbg`, `nosanitize`, `llvm.loop`, ...).
    name: []const u8,
    ref: MetadataRef,
    span: Span = .{},
};

pub const AsmValue = struct {
    span: Span = .{},
    /// Full source text of the `asm ...` construct.
    raw: []const u8 = "",
    /// Template string contents (between quotes, escapes preserved).
    template: []const u8 = "",
    constraints: ?[]const u8 = null,
    has_side_effects: bool = false,
    align_stack: bool = false,
    intel_dialect: bool = false,
    unwind: bool = false,
};

pub const BlockAddress = struct {
    span: Span = .{},
    function: NamedRef,
    block: NamedRef,
};

pub const Value = union(enum) {
    local: NamedRef,
    global: NamedRef,
    int: IntLiteral,
    float: FloatLiteral,
    /// `null`, `none`
    null_: Span,
    undef: Span,
    poison: Span,
    zeroinitializer: Span,
    aggregate: Aggregate,
    string: StringLiteral,
    const_expr: *const ConstExpr,
    metadata: MetadataRef,
    /// `metadata <ty> <value>`: a value wrapped as metadata (used by
    /// `llvm.dbg.*` intrinsic arguments).
    metadata_value: *const TypedValue,
    asm_: AsmValue,
    blockaddress: BlockAddress,

    pub fn tagName(self: Value) []const u8 {
        return @tagName(self);
    }

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        _ = fmt;
        _ = options;
        try renderValue(writer, &self);
    }
};

pub const TypedValue = struct {
    ty: *const Type,
    attrs: []const Attr = &.{},
    val: Value,
    span: Span = .{},

    pub fn format(
        self: TypedValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        _ = fmt;
        _ = options;
        try renderType(writer, self.ty);
        try writer.writeAll(" ");
        try renderValue(writer, &self.val);
    }
};

pub fn renderValue(writer: anytype, value: *const Value) anyerror!void {
    switch (value.*) {
        .local => |n| try writer.print("%{s}", .{n.name}),
        .global => |n| try writer.print("@{s}", .{n.name}),
        .int => |v| {
            if (v.negative) try writer.writeAll("-");
            if (v.hex) try writer.writeAll("0x");
            try writer.writeAll(v.digits);
        },
        .float => |v| try writer.writeAll(v.raw),
        .null_ => try writer.writeAll("null"),
        .undef => try writer.writeAll("undef"),
        .poison => try writer.writeAll("poison"),
        .zeroinitializer => try writer.writeAll("zeroinitializer"),
        .aggregate => |agg| {
            const open: u8, const close: u8 = switch (agg.kind) {
                .braces => .{ '{', '}' },
                .brackets => .{ '[', ']' },
                .angles => .{ '<', '>' },
            };
            try writer.writeByte(open);
            if (agg.packed_braces) try writer.writeByte('{');
            for (agg.elems, 0..) |elem, i| {
                if (i != 0) try writer.writeAll(", ");
                try elem.format("", .{}, writer);
            }
            if (agg.packed_braces) try writer.writeByte('}');
            try writer.writeByte(close);
        },
        .string => |s| {
            if (s.is_c) try writer.writeAll("c");
            try writer.writeByte('"');
            try writer.writeAll(s.raw);
            try writer.writeByte('"');
        },
        .const_expr => |expr| try renderConstExpr(writer, expr),
        .metadata_value => |tv| try tv.format("", .{}, writer),
        .metadata => |m| switch (m) {
            .id => |id| try writer.print("!{d}", .{id}),
            .named => |n| {
                try writer.print("!{s}", .{n.name});
                if (n.has_args) try writer.writeAll(n.raw);
            },
            .node => |n| {
                try writer.writeByte('!');
                try writer.writeAll(n.raw);
            },
        },
        .asm_ => |a| try writer.writeAll(a.raw),
        .blockaddress => |b| try writer.print("blockaddress(@{s}, %{s})", .{ b.function.name, b.block.name }),
    }
}

// --------------------------------------------------------------- attributes

pub const Attr = struct {
    span: Span = .{},
    kind: Kind,

    pub const Kind = union(enum) {
        noundef,
        signext,
        zeroext,
        noalias_,
        nonnull,
        inreg,
        returned,
        immarg,
        readonly,
        readnone,
        writeonly,
        writable,
        dead_on_unwind,
        nofree,
        nocyclone,
        nosync,
        nounwind,
        willreturn,
        mustprogress,
        byval: *const Type,
        sret: *const Type,
        byref: *const Type,
        elementtype: *const Type,
        inalloca: *const Type,
        preallocated: *const Type,
        initializes: *const Type,
        align_: u32,
        dereferenceable: u64,
        dereferenceable_or_null: u64,
        addr_space: u32,
        /// A recognised attribute word that is not modelled above.
        opaque_: []const u8,
        /// `name(arg, ...)` attribute whose payload is kept verbatim.
        opaque_call: struct { name: []const u8, raw: []const u8 },
    };

    pub fn format(
        self: Attr,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        _ = fmt;
        _ = options;
        try renderAttr(writer, self);
    }
};

pub fn renderAttr(writer: anytype, attr: Attr) anyerror!void {
    switch (attr.kind) {
        .noundef => try writer.writeAll("noundef"),
        .signext => try writer.writeAll("signext"),
        .zeroext => try writer.writeAll("zeroext"),
        .noalias_ => try writer.writeAll("noalias"),
        .nonnull => try writer.writeAll("nonnull"),
        .inreg => try writer.writeAll("inreg"),
        .returned => try writer.writeAll("returned"),
        .immarg => try writer.writeAll("immarg"),
        .readonly => try writer.writeAll("readonly"),
        .readnone => try writer.writeAll("readnone"),
        .writeonly => try writer.writeAll("writeonly"),
        .writable => try writer.writeAll("writable"),
        .dead_on_unwind => try writer.writeAll("dead_on_unwind"),
        .nofree => try writer.writeAll("nofree"),
        .nocyclone => try writer.writeAll("nocyclone"),
        .nosync => try writer.writeAll("nosync"),
        .nounwind => try writer.writeAll("nounwind"),
        .willreturn => try writer.writeAll("willreturn"),
        .mustprogress => try writer.writeAll("mustprogress"),
        .byval => |t| {
            try writer.writeAll("byval(");
            try renderType(writer, t);
            try writer.writeAll(")");
        },
        .sret => |t| {
            try writer.writeAll("sret(");
            try renderType(writer, t);
            try writer.writeAll(")");
        },
        .byref => |t| {
            try writer.writeAll("byref(");
            try renderType(writer, t);
            try writer.writeAll(")");
        },
        .elementtype => |t| {
            try writer.writeAll("elementtype(");
            try renderType(writer, t);
            try writer.writeAll(")");
        },
        .inalloca => |t| {
            try writer.writeAll("inalloca(");
            try renderType(writer, t);
            try writer.writeAll(")");
        },
        .preallocated => |t| {
            try writer.writeAll("preallocated(");
            try renderType(writer, t);
            try writer.writeAll(")");
        },
        .initializes => |t| {
            try writer.writeAll("initializes(");
            try renderType(writer, t);
            try writer.writeAll(")");
        },
        .align_ => |n| try writer.print("align {d}", .{n}),
        .dereferenceable => |n| try writer.print("dereferenceable({d})", .{n}),
        .dereferenceable_or_null => |n| try writer.print("dereferenceable_or_null({d})", .{n}),
        .addr_space => |n| try writer.print("addrspace({d})", .{n}),
        .opaque_ => |word| try writer.writeAll(word),
        .opaque_call => |c| try writer.print("{s}{s}", .{ c.name, c.raw }),
    }
}

// ----------------------------------------------------------- constant exprs

pub const IcmpPred = enum { eq, ne, ugt, uge, ult, ule, sgt, sge, slt, sle };
pub const FcmpPred = enum { false_, oeq, ogt, oge, olt, ole, one, ord, ueq, ugt, uge, ult, ule, une, uno, true_ };

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    sdiv,
    udiv,
    srem,
    urem,
    and_,
    or_,
    xor,
    shl,
    lshr,
    ashr,
    fadd,
    fsub,
    fmul,
    fdiv,
    frem,

    pub fn keyword(self: BinaryOp) []const u8 {
        return switch (self) {
            .and_ => "and",
            .or_ => "or",
            .xor => "xor",
            else => @tagName(self),
        };
    }
};

pub const CastOp = enum {
    trunc,
    zext,
    sext,
    fptrunc,
    fpext,
    fptoui,
    fptosi,
    uitofp,
    sitofp,
    ptrtoint,
    inttoptr,
    bitcast,
    addrspacecast,
};

pub const Gep = struct {
    inbounds: bool = false,
    nuw: bool = false,
    /// Source element type (first operand of the textual form).
    src: *const Type,
    ptr: TypedValue,
    indices: []const TypedValue = &.{},
    span: Span = .{},
};

pub const CastExpr = struct {
    op: CastOp,
    src: *const Type,
    value: Value,
    dst: *const Type,
    /// `nonneg` flag on `uitofp`/`sitofp`.
    nonneg: bool = false,
    span: Span = .{},
};

pub const BinaryExpr = struct {
    op: BinaryOp,
    ty: *const Type,
    lhs: Value,
    rhs: Value,
    nuw: bool = false,
    nsw: bool = false,
    exact: bool = false,
    /// `fast` (or any fast-math flag) was present.
    fast: bool = false,
    span: Span = .{},
};

pub const IcmpExpr = struct {
    pred: IcmpPred,
    ty: *const Type,
    lhs: Value,
    rhs: Value,
    span: Span = .{},
};

pub const FcmpExpr = struct {
    pred: FcmpPred,
    ty: *const Type,
    lhs: Value,
    rhs: Value,
    fast: bool = false,
    span: Span = .{},
};

pub const SelectExpr = struct {
    cond: TypedValue,
    if_true: TypedValue,
    if_false: TypedValue,
    span: Span = .{},
};

pub const ExtractValueExpr = struct {
    aggregate: TypedValue,
    indices: []const u32 = &.{},
    span: Span = .{},
};

pub const UnaryExpr = struct {
    ty: *const Type,
    value: Value,
    span: Span = .{},
};

pub const ConstExpr = union(enum) {
    gep: Gep,
    cast: CastExpr,
    binary: BinaryExpr,
    icmp: IcmpExpr,
    fcmp: FcmpExpr,
    select: SelectExpr,
    extractvalue: ExtractValueExpr,
    fneg: UnaryExpr,
};

pub fn renderConstExpr(writer: anytype, expr: *const ConstExpr) anyerror!void {
    switch (expr.*) {
        .gep => |g| {
            try writer.writeAll("getelementptr ");
            if (g.inbounds) try writer.writeAll("inbounds ");
            if (g.nuw) try writer.writeAll("nuw ");
            try writer.writeAll("(");
            try renderType(writer, g.src);
            try writer.writeAll(", ");
            try g.ptr.format("", .{}, writer);
            for (g.indices) |idx| {
                try writer.writeAll(", ");
                try idx.format("", .{}, writer);
            }
            try writer.writeAll(")");
        },
        .cast => |c| {
            try writer.print("{s} (", .{@tagName(c.op)});
            try renderType(writer, c.src);
            try writer.writeAll(" ");
            try renderValue(writer, &c.value);
            try writer.writeAll(" to ");
            try renderType(writer, c.dst);
            try writer.writeAll(")");
        },
        .binary => |b| {
            try writer.print("{s} (", .{b.op.keyword()});
            try renderType(writer, b.ty);
            try writer.writeAll(" ");
            try renderValue(writer, &b.lhs);
            try writer.writeAll(", ");
            try renderType(writer, b.ty);
            try writer.writeAll(" ");
            try renderValue(writer, &b.rhs);
            try writer.writeAll(")");
        },
        .icmp => |c| {
            try writer.print("icmp {s} (", .{@tagName(c.pred)});
            try renderType(writer, c.ty);
            try writer.writeAll(" ");
            try renderValue(writer, &c.lhs);
            try writer.writeAll(", ");
            try renderType(writer, c.ty);
            try writer.writeAll(" ");
            try renderValue(writer, &c.rhs);
            try writer.writeAll(")");
        },
        .fcmp => |c| {
            try writer.print("fcmp {s} (", .{fcmpPredName(c.pred)});
            try renderType(writer, c.ty);
            try writer.writeAll(" ");
            try renderValue(writer, &c.lhs);
            try writer.writeAll(", ");
            try renderType(writer, c.ty);
            try writer.writeAll(" ");
            try renderValue(writer, &c.rhs);
            try writer.writeAll(")");
        },
        .select => |s| {
            try writer.writeAll("select (");
            try s.cond.format("", .{}, writer);
            try writer.writeAll(", ");
            try s.if_true.format("", .{}, writer);
            try writer.writeAll(", ");
            try s.if_false.format("", .{}, writer);
            try writer.writeAll(")");
        },
        .extractvalue => |e| {
            try writer.writeAll("extractvalue (");
            try e.aggregate.format("", .{}, writer);
            for (e.indices) |idx| try writer.print(", {d}", .{idx});
            try writer.writeAll(")");
        },
        .fneg => |u| {
            try writer.writeAll("fneg (");
            try renderType(writer, u.ty);
            try writer.writeAll(" ");
            try renderValue(writer, &u.value);
            try writer.writeAll(")");
        },
    }
}

pub fn fcmpPredName(pred: FcmpPred) []const u8 {
    return switch (pred) {
        .false_ => "false",
        .true_ => "true",
        else => @tagName(pred),
    };
}

// ------------------------------------------------------------- instructions

pub const Alloca = struct {
    ty: *const Type,
    count: ?TypedValue = null,
    alignment: ?u32 = null,
    addr_space: ?u32 = null,
    inalloca: bool = false,
    swifterror: bool = false,
    span: Span = .{},
};

pub const Load = struct {
    ty: *const Type,
    ptr: TypedValue,
    alignment: ?u32 = null,
    is_volatile: bool = false,
    is_atomic: bool = false,
    ordering: ?[]const u8 = null,
    span: Span = .{},
};

pub const Store = struct {
    ty: *const Type,
    value: TypedValue,
    ptr: TypedValue,
    alignment: ?u32 = null,
    is_volatile: bool = false,
    is_atomic: bool = false,
    ordering: ?[]const u8 = null,
    span: Span = .{},
};

pub const PhiIncoming = struct {
    value: Value,
    block: NamedRef,
    span: Span = .{},
};

pub const Phi = struct {
    ty: *const Type,
    incoming: []const PhiIncoming = &.{},
    span: Span = .{},
};

pub const Br = union(enum) {
    unconditional: Unconditional,
    conditional: Conditional,

    pub const Unconditional = struct { target: NamedRef, span: Span = .{} };
    pub const Conditional = struct {
        cond: TypedValue,
        if_true: NamedRef,
        if_false: NamedRef,
        span: Span = .{},
    };
};

pub const SwitchCase = struct {
    value: TypedValue,
    target: NamedRef,
    span: Span = .{},
};

pub const Switch = struct {
    cond: TypedValue,
    default: NamedRef,
    cases: []const SwitchCase = &.{},
    span: Span = .{},
};

pub const Ret = union(enum) {
    void: Span,
    value: TypedValue,
};

pub const Select = struct {
    cond: TypedValue,
    if_true: TypedValue,
    if_false: TypedValue,
    span: Span = .{},
};

pub const ExtractValue = struct {
    aggregate: TypedValue,
    indices: []const u32 = &.{},
    span: Span = .{},
};

pub const Call = struct {
    pub const Callee = union(enum) {
        direct: NamedRef,
        indirect: TypedValue,
        asm_: AsmValue,
    };

    callee: Callee,
    /// Return type as written (function type is folded into `ret`/`fn_ty`).
    ret: *const Type,
    ret_attrs: []const Attr = &.{},
    args: []const TypedValue = &.{},
    /// Explicit function type when the call spelled one out.
    fn_ty: ?*const Type = null,
    is_varargs: bool = false,
    is_tail: bool = false,
    is_musttail: bool = false,
    is_notail: bool = false,
    is_callbr: bool = false,
    /// Calling convention keyword (`fastcc`, ...) when present.
    cc: ?[]const u8 = null,
    fn_attrs: []const Attr = &.{},
    attr_groups: []const u32 = &.{},
    /// Operand bundles, kept as raw source text.
    operand_bundles: []const []const u8 = &.{},
    callbr_targets: []const NamedRef = &.{},
    span: Span = .{},

    pub fn calleeName(self: Call) ?NamedRef {
        return switch (self.callee) {
            .direct => |n| n,
            else => null,
        };
    }
};

pub const Icmp = struct {
    pred: IcmpPred,
    ty: *const Type,
    lhs: Value,
    rhs: Value,
    span: Span = .{},
};

pub const Fcmp = struct {
    pred: FcmpPred,
    ty: *const Type,
    lhs: Value,
    rhs: Value,
    fast: bool = false,
    span: Span = .{},
};

pub const Binary = struct {
    op: BinaryOp,
    ty: *const Type,
    lhs: Value,
    rhs: Value,
    nuw: bool = false,
    nsw: bool = false,
    exact: bool = false,
    fast: bool = false,
    span: Span = .{},
};

pub const Cast = struct {
    op: CastOp,
    src: *const Type,
    value: Value,
    dst: *const Type,
    nonneg: bool = false,
    span: Span = .{},
};

pub const Unary = struct {
    ty: *const Type,
    value: Value,
    span: Span = .{},
};

pub const Op = union(enum) {
    alloca: Alloca,
    load: Load,
    store: Store,
    gep: Gep,
    phi: Phi,
    br: Br,
    switch_: Switch,
    ret: Ret,
    unreachable_: Span,
    select: Select,
    extractvalue: ExtractValue,
    call: Call,
    icmp: Icmp,
    fcmp: Fcmp,
    fneg: Unary,
    freeze: Unary,
    binary: Binary,
    cast: Cast,

    pub fn mnemonic(self: Op) []const u8 {
        return switch (self) {
            .alloca => "alloca",
            .load => "load",
            .store => "store",
            .gep => "getelementptr",
            .phi => "phi",
            .br => "br",
            .switch_ => "switch",
            .ret => "ret",
            .unreachable_ => "unreachable",
            .select => "select",
            .extractvalue => "extractvalue",
            .call => |c| if (c.is_callbr) "callbr" else "call",
            .icmp => "icmp",
            .fcmp => "fcmp",
            .fneg => "fneg",
            .freeze => "freeze",
            .binary => |b| b.op.keyword(),
            .cast => |c| @tagName(c.op),
        };
    }
};

pub const Instruction = struct {
    /// `%x = ...` result, null for instructions without a result.
    result: ?NamedRef = null,
    span: Span = .{},
    op: Op,
    metadata: []const MetadataAttachment = &.{},

    pub fn mnemonic(self: Instruction) []const u8 {
        return self.op.mnemonic();
    }
};

// ------------------------------------------------------- functions / blocks

pub const BasicBlock = struct {
    /// Null for an unlabelled entry block.
    label: ?NamedRef = null,
    instructions: []const Instruction = &.{},
    span: Span = .{},

    pub fn name(self: BasicBlock) []const u8 {
        return if (self.label) |l| l.name else "";
    }
};

pub const Param = struct {
    ty: *const Type,
    attrs: []const Attr = &.{},
    /// Null for unnamed parameters.
    name: ?NamedRef = null,
    span: Span = .{},
};

pub const Signature = struct {
    ret: *const Type,
    ret_attrs: []const Attr = &.{},
    params: []const Param = &.{},
    is_varargs: bool = false,
    cc: ?[]const u8 = null,
    span: Span = .{},

    /// Index of the `byval`/`sret` parameter carrying `ty`, if any.
    pub fn findAttrParamIndex(self: Signature, want_sret: bool) ?usize {
        for (self.params, 0..) |param, i| {
            for (param.attrs) |attr| {
                const is_sret = @as(std.meta.Tag(Attr.Kind), attr.kind) == .sret;
                if (is_sret == want_sret) return i;
            }
        }
        return null;
    }
};

pub const Linkage = enum(u8) {
    external,
    private,
    internal,
    available_externally,
    linkonce,
    weak,
    common,
    appending,
    extern_weak,
    linkonce_odr,
    weak_odr,
};

pub const Visibility = enum(u8) { default, hidden, protected };
pub const DllStorage = enum(u8) { none, dllimport, dllexport };

pub const GlobalModifiers = struct {
    linkage: Linkage = .external,
    visibility: Visibility = .default,
    dll_storage: DllStorage = .none,
    preemptable: bool = true,
    dso_local: bool = false,
    thread_local: bool = false,
    unnamed_addr: bool = false,
    local_unnamed_addr: bool = false,
    externally_initialized: bool = false,
};

pub const Function = struct {
    name: []const u8,
    name_ref: NamedRef,
    modifiers: GlobalModifiers = .{},
    sig: Signature,
    blocks: []const BasicBlock = &.{},
    /// Function attributes written on the definition line.
    attrs: []const Attr = &.{},
    attr_groups: []const u32 = &.{},
    metadata: []const MetadataAttachment = &.{},
    span: Span = .{},
};

pub const Decl = struct {
    name: []const u8,
    name_ref: NamedRef,
    modifiers: GlobalModifiers = .{},
    sig: Signature,
    attrs: []const Attr = &.{},
    attr_groups: []const u32 = &.{},
    metadata: []const MetadataAttachment = &.{},
    span: Span = .{},
};

pub const Global = struct {
    name: []const u8,
    name_ref: NamedRef,
    modifiers: GlobalModifiers = .{},
    /// `constant` rather than `global`.
    is_const: bool = false,
    addr_space: u32 = 0,
    ty: *const Type,
    /// Null for `external` declarations (no initialiser).
    init: ?Value = null,
    alignment: ?u32 = null,
    section: ?[]const u8 = null,
    comdat: ?NamedRef = null,
    metadata: []const MetadataAttachment = &.{},
    span: Span = .{},
};

// -------------------------------------------------------------- module level

pub const TypeDef = struct {
    name: []const u8,
    ref: NamedRef,
    ty: *const Type,
    span: Span = .{},
};

pub const AttributeGroup = struct {
    id: u32,
    /// Source text of the `{ ... }` body (or the whole record when unbraced).
    raw: []const u8,
    span: Span = .{},
};

pub const MetadataRecord = struct {
    /// Record name without `!` (`0`, `llvm.module.flags`, `DIFile`, ...).
    name: []const u8,
    /// Numeric id when the name is a plain number.
    id: ?u32 = null,
    /// Source text of the record body (right hand side).
    raw: []const u8,
    span: Span = .{},
};

pub const OpaqueRecord = struct {
    /// Leading keyword (`comdat`, `module`, `uselistorder`, ...); may be empty.
    keyword: []const u8,
    raw: []const u8,
    span: Span = .{},
};

pub const Module = struct {
    /// `source_filename = "..."`
    source_filename: ?[]const u8 = null,
    target_datalayout: ?[]const u8 = null,
    target_triple: ?[]const u8 = null,
    type_defs: []const TypeDef = &.{},
    globals: []const Global = &.{},
    declares: []const Decl = &.{},
    functions: []const Function = &.{},
    attribute_groups: []const AttributeGroup = &.{},
    metadata: []const MetadataRecord = &.{},
    opaque_records: []const OpaqueRecord = &.{},
    /// Number of source lines lexed (for diagnostics/tests).
    line_count: u32 = 0,

    pub fn findGlobal(self: *const Module, name: []const u8) ?*const Global {
        for (self.globals) |*g| {
            if (std.mem.eql(u8, g.name, name)) return g;
        }
        return null;
    }

    pub fn findDecl(self: *const Module, name: []const u8) ?*const Decl {
        for (self.declares) |*d| {
            if (std.mem.eql(u8, d.name, name)) return d;
        }
        return null;
    }

    pub fn findFunction(self: *const Module, name: []const u8) ?*const Function {
        for (self.functions) |*f| {
            if (std.mem.eql(u8, f.name, name)) return f;
        }
        return null;
    }

    pub fn findTypeDef(self: *const Module, name: []const u8) ?*const TypeDef {
        for (self.type_defs) |*t| {
            if (std.mem.eql(u8, t.name, name)) return t;
        }
        return null;
    }
};

// -------------------------------------------------------------------- tests

test "type rendering and equality" {
    const allocator = std.testing.allocator;
    var i32_t = Type{ .int = .{ .bits = 32 } };
    var i64_t = Type{ .int = .{ .bits = 64 } };

    const arr = Type{ .array = .{ .count = 4, .elem = &i32_t } };
    const struct_ty = Type{ .struct_ = .{ .fields = &.{ &i32_t, &i64_t }, .is_packed = true } };
    const vec = Type{ .vector = .{ .count = 4, .elem = &i32_t } };
    const fn_ty = Type{ .function = .{ .ret = &i32_t, .params = &.{ &i32_t, &i64_t }, .varargs = true } };
    const named = Type{ .named = .{ .name = "struct.Pk" } };
    const ptr_ty = Type{ .ptr = .{} };

    const arr_text = try arr.toString(allocator);
    defer allocator.free(arr_text);
    try std.testing.expectEqualStrings("[4 x i32]", arr_text);

    const struct_text = try struct_ty.toString(allocator);
    defer allocator.free(struct_text);
    try std.testing.expectEqualStrings("<{ i32, i64 }>", struct_text);

    const vec_text = try vec.toString(allocator);
    defer allocator.free(vec_text);
    try std.testing.expectEqualStrings("<4 x i32>", vec_text);

    const fn_text = try fn_ty.toString(allocator);
    defer allocator.free(fn_text);
    try std.testing.expectEqualStrings("i32 (i32, i64, ...)", fn_text);

    const named_text = try named.toString(allocator);
    defer allocator.free(named_text);
    try std.testing.expectEqualStrings("%struct.Pk", named_text);

    try std.testing.expect(arr.eql(arr));
    try std.testing.expect(!arr.eql(vec));
    try std.testing.expect(ptr_ty.eql(.{ .ptr = .{} }));
    try std.testing.expect(fn_ty.eql(.{ .function = .{ .ret = &i32_t, .params = &.{ &i32_t, &i64_t }, .varargs = true } }));
}

test "float literal byte layout" {
    // fp128 2.5 as printed by clang 18: low 64-bit word first.
    var lit = FloatLiteral{
        .raw = "0xL00000000000000004000400000000000",
        .form = .hex,
        .hex_spec = 'L',
        .hex_digits = 32,
        .bits = 0x40004000000000000000000000000000,
        .width = 128,
    };
    var buf: [16]u8 = undefined;
    const n = lit.writeLeBytes(&buf);
    try std.testing.expectEqual(@as(usize, 16), n);
    try std.testing.expectEqual(@as(u8, 0x40), buf[15]);
    try std.testing.expectEqual(@as(u8, 0x00), buf[14]);
    try std.testing.expectEqual(@as(u8, 0x40), buf[13]);
    try std.testing.expectEqual(@as(u8, 0x00), buf[0]);

    lit = .{
        .raw = "0xK3FFFC000000000000000",
        .form = .hex,
        .hex_spec = 'K',
        .hex_digits = 20,
        .bits = 0x3FFFC000000000000000,
        .width = 80,
    };
    try std.testing.expectEqual(@as(u16, 10), lit.byteLen());
}
