const std = @import("std");
const op = @import("opcodes.zig");

const Allocator = std.mem.Allocator;

pub const Loc = struct {
    kind: u8,
    index: u16 = 0,
    size: u16 = 0,
    offset: u16 = 0,
};

const RetInfo = struct { locs: []Loc, size: u16 };
const TypeInfo = struct { kind: u8, size: u16 };

pub const ArgPlan = struct {
    locs: []Loc,
    size: u16,
    alignment: u16 = 8,
    is_struct: bool = false,
};

pub const Plan = struct {
    name: []const u8,
    args: []ArgPlan,
    ret_locs: []Loc,
    stack_size: u16 = 0,
    sret: bool = false,
    sse_count: u8 = 0,
    ret_size: u16 = 0,
    conv: u8 = 0,
};

pub const Function = struct {
    name: []const u8,
    ret: []const u8,
    param_count: u16,
    param_names: [][]const u8,
    param_types: [][]const u8,
    param_attrs: [][]const u8,
    is_varargs: bool = false,
    local_count: u16,
    code: std.ArrayList(u8),
};

const CallbackEntry = struct {
    slot: u16,
    func_index: u16,
    plan_index: u16,
};

const CallbackTable = struct {
    by_func: std.StringHashMap(CallbackEntry),
    next_slot: u16 = 0,
};

pub const Decl = struct {
    ret: []const u8,
    params: [][]const u8,
    is_varargs: bool,
};

pub const CompileResult = struct {
    functions: []Function,
    plans: []Plan,
    external_data: [][]const u8,
};

const Reloc = struct {
    offset: u32,
    target: []const u8,
    addend: i64,
};

const Patch = struct {
    pos: u32,
    label: []const u8,
};

const PhiAssign = struct {
    pred: []const u8,
    result: []const u8,
    value: []const u8,
};

const Globals = struct {
    map: std.StringHashMap(u32),
    external: std.StringHashMap(u16),
    external_names: [][]const u8,
    data: []u8,
    relocs: []Reloc,
};

const Structs = std.StringHashMap([]const []const u8);

fn alignUp(n: u32, a: u32) u32 {
    if (a <= 1) return n;
    return (n + a - 1) / a * a;
}

pub fn splitTop(allocator: Allocator, s: []const u8, sep: u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(allocator);
    var start: usize = 0;
    var depth: i32 = 0;
    var i: usize = 0;
    while (i <= s.len) : (i += 1) {
        const ch: u8 = if (i < s.len) s[i] else sep;
        switch (ch) {
            '(', '[', '{', '<' => depth += 1,
            ')', ']', '}', '>' => depth -= 1,
            else => {},
        }
        if (ch == sep and depth == 0) {
            const part = std.mem.trim(u8, s[start..i], " \t\r\n");
            if (part.len > 0) try out.append(part);
            start = i + 1;
        }
    }
    return out.toOwnedSlice();
}

pub fn stripMeta(line_in: []const u8) []const u8 {
    var line = std.mem.trim(u8, line_in, " \t\r");
    if (std.mem.indexOf(u8, line, ", !")) |idx| line = line[0..idx];
    if (std.mem.indexOf(u8, line, " !dbg")) |idx| line = line[0..idx];
    return std.mem.trim(u8, line, " \t\r");
}

fn stripAlign(text_in: []const u8) []const u8 {
    var text = std.mem.trim(u8, text_in, " \t\r");
    if (std.mem.indexOf(u8, text, ", align")) |idx| {
        text = std.mem.trim(u8, text[0..idx], " \t\r");
    }
    return text;
}

fn startsWithAny(s: []const u8, prefixes: []const []const u8) bool {
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, s, p)) return true;
    }
    return false;
}

fn parseF80Bytes(text_in: []const u8) [10]u8 {
    var out = [_]u8{0} ** 10;
    var text = std.mem.trim(u8, text_in, " \t\r");
    if (std.mem.lastIndexOfScalar(u8, text, ' ')) |sp| text = std.mem.trim(u8, text[sp + 1 ..], " ");
    if (std.mem.startsWith(u8, text, "0xK")) {
        const v = std.fmt.parseInt(u80, text[3..], 16) catch 0;
        var i: u8 = 0;
        while (i < 10) : (i += 1) out[i] = @truncate(v >> @intCast(i * 8));
        return out;
    }
    const value = std.fmt.parseFloat(f64, std.mem.trimRight(u8, text, "LlFf")) catch 0;
    const bits: u64 = @bitCast(value);
    var i: u8 = 0;
    while (i < 8) : (i += 1) out[i] = @truncate(bits >> @intCast(i * 8));
    return out;
}

fn emitF80Const(self: *Lowerer, text: []const u8) !void {
    try self.emitU8(op.OP_F80_CONST);
    const bytes = parseF80Bytes(text);
    try self.func.code.appendSlice(&bytes);
}

fn parseF128Bytes(text_in: []const u8) [16]u8 {
    var out = [_]u8{0} ** 16;
    var text = std.mem.trim(u8, text_in, " \t\r");
    if (std.mem.lastIndexOfScalar(u8, text, ' ')) |sp| text = std.mem.trim(u8, text[sp + 1 ..], " ");
    if (std.mem.startsWith(u8, text, "0xL")) {
        const hex_text = text[3..];
        var value: u128 = 0;
        if (hex_text.len == 32) {
            const high = std.fmt.parseInt(u64, hex_text[0..16], 16) catch 0;
            const low = std.fmt.parseInt(u64, hex_text[16..32], 16) catch 0;
            value = (@as(u128, low) << 64) | @as(u128, high);
        } else {
            value = std.fmt.parseInt(u128, hex_text, 16) catch 0;
        }
        var i: u8 = 0;
        while (i < 16) : (i += 1) out[i] = @truncate(value >> @intCast(i * 8));
        return out;
    }
    const value = std.fmt.parseFloat(f64, std.mem.trimRight(u8, text, "LlFf")) catch 0;
    const bits: u64 = @bitCast(value);
    var i: u8 = 0;
    while (i < 8) : (i += 1) out[i] = @truncate(bits >> @intCast(i * 8));
    return out;
}

fn emitF128Const(self: *Lowerer, text: []const u8) !void {
    try self.emitU8(op.OP_F128_CONST);
    const bytes = parseF128Bytes(text);
    try self.func.code.appendSlice(&bytes);
}

fn typeToken(text_in: []const u8) []const u8 {
    const text = std.mem.trim(u8, text_in, " \t\r");
    if (text.len == 0) return text;
    if (text[0] == '[' or text[0] == '{' or text[0] == '<') {
        var depth: i32 = 0;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            switch (text[i]) {
                '[', '{', '<' => depth += 1,
                ']', '}', '>' => {
                    depth -= 1;
                    if (depth == 0) return text[0 .. i + 1];
                },
                else => {},
            }
        }
        return text;
    }
    var end: usize = 0;
    while (end < text.len and text[end] != ' ' and text[end] != ',' and text[end] != ')') end += 1;
    return text[0..end];
}

fn findCallOpen(rhs: []const u8) ?usize {
    var pos: usize = 0;
    while (std.mem.indexOfScalarPos(u8, rhs, pos, '(')) |p| {
        var e = p;
        while (e > 0 and (rhs[e - 1] == ' ' or rhs[e - 1] == '\t')) e -= 1;
        var s = e;
        while (s > 0) {
            const c = rhs[s - 1];
            if (c == ' ' or c == '\t' or c == '(' or c == ')' or c == ',') break;
            s -= 1;
        }
        if (e > s) {
            const tok = rhs[s..e];
            if (tok.len > 1 and (tok[0] == '@' or tok[0] == '%')) return p;
        }
        pos = p + 1;
    }
    return null;
}

fn stripDefinePrefix(text_in: []const u8) []const u8 {
    var text = std.mem.trim(u8, text_in, " \t\r");
    const words = [_][]const u8{
        "internal ", "external ", "private ", "dso_local ", "available_externally ",
        "linkonce_odr ", "linkonce ", "weak ", "hidden ", "protected ", "appending ",
        "common ", "fastcall ", "stdcall ", "thiscall ",
    };
    var changed = true;
    while (changed) {
        changed = false;
        for (words) |w| {
            if (std.mem.startsWith(u8, text, w)) {
                text = std.mem.trim(u8, text[w.len..], " \t\r");
                changed = true;
                break;
            }
        }
    }
    return text;
}

fn normalizeName(raw: []const u8) []const u8 {
    var name = raw;
    if (name.len >= 2 and name[0] == '"' and name[name.len - 1] == '"') {
        name = name[1 .. name.len - 1];
    }
    if (name.len > 0 and name[0] == 1) name = name[1..];
    return name;
}

fn lastPercent(text: []const u8) ?[]const u8 {
    var i = text.len;
    while (i > 0) {
        i -= 1;
        if (text[i] == '%') {
            var end = i + 1;
            while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_' or text[end] == '.' or text[end] == '$' or text[end] == '-')) end += 1;
            if (end > i + 1) return text[i + 1 .. end];
        }
    }
    return null;
}

fn lastAt(text: []const u8) ?[]const u8 {
    var i = text.len;
    while (i > 0) {
        i -= 1;
        if (text[i] == '@') {
            var end = i + 1;
            if (end < text.len and text[end] == '"') {
                end += 1;
                while (end < text.len and text[end] != '"') end += 1;
                if (end < text.len) end += 1;
            } else {
                while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_' or text[end] == '.' or text[end] == '$' or text[end] == '-')) end += 1;
            }
            if (end > i + 1) return text[i + 1 .. end];
        }
    }
    return null;
}

fn parseI64(text: []const u8) ?i64 {
    const s = std.mem.trim(u8, text, " \t\r");
    if (s.len == 0) return null;
    if (std.mem.eql(u8, s, "true")) return 1;
    if (std.mem.eql(u8, s, "false") or std.mem.eql(u8, s, "null") or std.mem.eql(u8, s, "zeroinitializer") or std.mem.eql(u8, s, "undef")) return 0;
    return std.fmt.parseInt(i64, s, 0) catch null;
}

fn parseBits(text: []const u8) ?u64 {
    var s = std.mem.trim(u8, text, " \t\r");
    if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X")) s = s[2..];
    return std.fmt.parseInt(u64, s, 16) catch null;
}

fn parseFloatBits(text: []const u8, ty: []const u8) ?u64 {
    var s = std.mem.trim(u8, text, " \t\r");
    if (std.mem.indexOf(u8, s, "0x")) |idx| {
        s = s[idx + 2 ..];
        var end: usize = 0;
        while (end < s.len and std.ascii.isHex(s[end])) end += 1;
        const raw = std.fmt.parseInt(u64, s[0..end], 16) catch return null;
        if (std.mem.eql(u8, ty, "float")) {
            if (end > 8) {
                const d: f64 = @bitCast(raw);
                const f: f32 = @floatCast(d);
                return @as(u32, @bitCast(f));
            }
            return raw & 0xFFFFFFFF;
        }
        return raw;
    }
    // Strip a leading type keyword.
    if (std.mem.indexOfScalar(u8, s, ' ')) |sp| s = std.mem.trim(u8, s[sp + 1 ..], " ");
    const value = std.fmt.parseFloat(f64, s) catch return null;
    if (std.mem.eql(u8, ty, "float")) {
        const f: f32 = @floatCast(value);
        return @as(u32, @bitCast(f));
    }
    return @bitCast(value);
}

fn parseCString(text_in: []const u8, out: []u8) void {
    var text = text_in;
    if (std.mem.indexOf(u8, text, "c\"")) |idx| text = text[idx + 2 ..];
    if (text.len > 0 and text[0] == '"') text = text[1..];
    var i: usize = 0;
    var o: usize = 0;
    while (i < text.len and o < out.len) {
        const ch = text[i];
        if (ch == '"') break;
        if (ch == '\\' and i + 1 < text.len) {
            if (i + 2 < text.len and std.ascii.isHex(text[i + 1]) and std.ascii.isHex(text[i + 2])) {
                const hi = std.fmt.charToDigit(text[i + 1], 16) catch 0;
                const lo = std.fmt.charToDigit(text[i + 2], 16) catch 0;
                out[o] = @intCast(hi * 16 + lo);
                i += 3;
                o += 1;
                continue;
            }
            i += 1;
            out[o] = switch (text[i]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                '"' => '"',
                '0' => 0,
                else => text[i],
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

fn parseStructs(allocator: Allocator, text: []const u8) !Structs {
    var structs = Structs.init(allocator);
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "%")) continue;
        const eq = std.mem.indexOf(u8, line, "= type") orelse continue;
        const name_end = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const name = line[0..name_end];
        var body = std.mem.trim(u8, line[eq + 6 ..], " \t\r");
        if (body.len == 0) continue;
        var is_packed = false;
        if (std.mem.startsWith(u8, body, "<{")) {
            is_packed = true;
            body = body[2 .. body.len - 2];
        } else if (body[0] == '{') {
            body = body[1 .. body.len - 1];
        } else continue;
        var fields = std.ArrayList([]const u8).init(allocator);
        if (is_packed) try fields.append("__is_packed__");
        const parts = try splitTop(allocator, body, ',');
        for (parts) |p| try fields.append(std.mem.trim(u8, p, " \t\r"));
        try structs.put(name, try fields.toOwnedSlice());
    }
    return structs;
}

fn structFields(allocator: Allocator, ty_in: []const u8, structs: *const Structs) !?[]const []const u8 {
    const ty = std.mem.trim(u8, ty_in, " \t\r");
    if (ty.len == 0) return null;
    if (ty[0] == '%') {
        return structs.get(ty);
    }
    if (std.mem.startsWith(u8, ty, "<{")) {
        const inner = ty[2 .. ty.len - 2];
        const parts = try splitTop(allocator, inner, ',');
        var fields = std.ArrayList([]const u8).init(allocator);
        try fields.append("__is_packed__");
        for (parts) |p| try fields.append(p);
        return try fields.toOwnedSlice();
    }
    if (ty[0] == '{') {
        return try splitTop(allocator, ty[1 .. ty.len - 1], ',');
    }
    return null;
}

const SizeAlign = struct { size: u32, alignment: u32 };

fn typeSizeAlign(allocator: Allocator, ty_in: []const u8, structs: *const Structs, ptr_size: u32) !SizeAlign {
    const ty = std.mem.trim(u8, ty_in, " \t\r");
    if (ty.len == 0) return .{ .size = 0, .alignment = 1 };
    const fields_opt = try structFields(allocator, ty, structs);
    if (fields_opt) |raw_fields| {
        var fields = raw_fields;
        var is_packed = false;
        if (fields.len > 0 and std.mem.eql(u8, fields[0], "__is_packed__")) {
            is_packed = true;
            fields = fields[1..];
        }
        var off: u32 = 0;
        var max_align: u32 = 1;
        for (fields) |field| {
            const fa = try typeSizeAlign(allocator, field, structs, ptr_size);
            if (!is_packed) off = alignUp(off, fa.alignment);
            off += fa.size;
            if (!is_packed and fa.alignment > max_align) max_align = fa.alignment;
        }
        return .{ .size = if (is_packed) off else alignUp(off, max_align), .alignment = max_align };
    }
    if (ty[0] == '<' and ty[ty.len - 1] == '>') {
        const inner = std.mem.trim(u8, ty[1 .. ty.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadType;
        const count = std.fmt.parseInt(u32, std.mem.trim(u8, inner[0..x], " "), 10) catch return error.BadType;
        const elem = try typeSizeAlign(allocator, inner[x + 3 ..], structs, ptr_size);
        const size = count * elem.size;
        return .{ .size = size, .alignment = if (size <= 8) 8 else 16 };
    }
    if (ty[0] == '[') {
        const inner = std.mem.trim(u8, ty[1 .. ty.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadType;
        const count = std.fmt.parseInt(u32, std.mem.trim(u8, inner[0..x], " "), 10) catch return error.BadType;
        const elem = try typeSizeAlign(allocator, inner[x + 3 ..], structs, ptr_size);
        return .{ .size = count * alignUp(elem.size, elem.alignment), .alignment = elem.alignment };
    }
    if (std.mem.eql(u8, ty, "ptr")) return .{ .size = ptr_size, .alignment = ptr_size };
    if (std.mem.eql(u8, ty, "x86_fp80")) return .{ .size = if (ptr_size == 4) 12 else 16, .alignment = if (ptr_size == 4) 4 else 16 };
    if (std.mem.eql(u8, ty, "fp128")) return .{ .size = 16, .alignment = 16 };
    if (std.mem.eql(u8, ty, "void")) return .{ .size = 0, .alignment = 1 };
    if (std.mem.eql(u8, ty, "float")) return .{ .size = 4, .alignment = 4 };
    if (std.mem.eql(u8, ty, "double")) return .{ .size = 8, .alignment = 8 };
    if (ty[0] == 'i') {
        const bits = std.fmt.parseInt(u32, ty[1..], 10) catch return error.BadType;
        const store = @max(1, (bits + 7) / 8);
        const alignment: u32 = if (bits <= 8) 1 else if (bits <= 16) 2 else if (bits <= 32) 4 else if (bits <= 64) 8 else 16;
        return .{ .size = alignUp(store, alignment), .alignment = alignment };
    }
    return error.BadType;
}

fn storeSize(allocator: Allocator, ty: []const u8, structs: *const Structs, ptr_size: u32) !u32 {
    const t = std.mem.trim(u8, ty, " \t\r");
    if (t.len > 1 and t[0] == 'i') {
        const bits = std.fmt.parseInt(u32, t[1..], 10) catch return (try typeSizeAlign(allocator, t, structs, ptr_size)).size;
        return @max(1, (bits + 7) / 8);
    }
    return (try typeSizeAlign(allocator, t, structs, ptr_size)).size;
}

fn structLayout(allocator: Allocator, ty: []const u8, structs: *const Structs, ptr_size: u32) !struct { offsets: []u32, size: u32, alignment: u32 } {
    const raw = (try structFields(allocator, ty, structs)) orelse return error.BadType;
    var fields = raw;
    var is_packed = false;
    if (fields.len > 0 and std.mem.eql(u8, fields[0], "__is_packed__")) {
        is_packed = true;
        fields = fields[1..];
    }
    var offsets = std.ArrayList(u32).init(allocator);
    var off: u32 = 0;
    var max_align: u32 = 1;
    for (fields) |field| {
        const fa = try typeSizeAlign(allocator, field, structs, ptr_size);
        if (!is_packed) off = alignUp(off, fa.alignment);
        try offsets.append(off);
        off += fa.size;
        if (!is_packed and fa.alignment > max_align) max_align = fa.alignment;
    }
    return .{ .offsets = try offsets.toOwnedSlice(), .size = if (is_packed) off else alignUp(off, max_align), .alignment = max_align };
}

fn splitTypeInit(text_in: []const u8) ?struct { ty: []const u8, init: []const u8 } {
    const text = std.mem.trim(u8, text_in, " \t\r");
    if (text.len == 0) return null;
    if (text[0] == '[' or text[0] == '{' or text[0] == '<') {
        var depth: i32 = 0;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            switch (text[i]) {
                '[', '{', '<' => depth += 1,
                ']', '}', '>' => {
                    depth -= 1;
                    if (depth == 0) {
                        const ty = text[0 .. i + 1];
                        const rest = std.mem.trim(u8, text[i + 1 ..], " \t\r");
                        if (rest.len == 0) return null;
                        return .{ .ty = ty, .init = rest };
                    }
                },
                else => {},
            }
        }
        return null;
    }
    var end: usize = 0;
    while (end < text.len and text[end] != ' ') end += 1;
    if (end >= text.len) return null;
    return .{ .ty = text[0..end], .init = std.mem.trim(u8, text[end + 1 ..], " \t\r") };
}

fn writeIntLE(out: []u8, value: u64, size: u32) void {
    var i: u32 = 0;
    while (i < size and i < out.len) : (i += 1) {
        const shift = i * 8;
        if (shift >= @bitSizeOf(u64)) break;
        out[i] = @truncate(value >> @intCast(shift));
    }
}

fn parseConstant(allocator: Allocator, ty: []const u8, init: []const u8, out: []u8, structs: *const Structs, ptr_size: u32) anyerror!void {
    const t = std.mem.trim(u8, ty, " \t\r");
    const v = std.mem.trim(u8, init, " \t\r");
    if (v.len == 0 or std.mem.eql(u8, v, "zeroinitializer") or std.mem.eql(u8, v, "undef")) return;
    if (t.len > 0 and t[0] == '[') {
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return;
        const elem_ty = inner[x + 3 ..];
        const elem = try typeSizeAlign(allocator, elem_ty, structs, ptr_size);
        if (std.mem.startsWith(u8, v, "c\"")) {
            parseCString(v, out);
            return;
        }
        if (v[0] == '[') {
            const parts = try splitTop(allocator, v[1 .. v.len - 1], ',');
            for (parts, 0..) |part, idx| {
                const base = idx * elem.size;
                if (base >= out.len) break;
                const st = splitTypeInit(part) orelse continue;
                try parseConstant(allocator, st.ty, st.init, out[base..], structs, ptr_size);
            }
        }
        return;
    }
    const fields_opt = try structFields(allocator, t, structs);
    if (fields_opt != null and (t[0] == '%' or t[0] == '{' or std.mem.startsWith(u8, t, "<{"))) {
        var fields = fields_opt.?;
        if (fields.len > 0 and std.mem.eql(u8, fields[0], "__packed__")) fields = fields[1..];
        const layout = try structLayout(allocator, t, structs, ptr_size);
        var init_body = v;
        if (std.mem.startsWith(u8, init_body, "<{")) {
            init_body = init_body[2 .. init_body.len - 2];
        } else if (init_body.len > 0 and init_body[0] == '{') {
            init_body = init_body[1 .. init_body.len - 1];
        }
        const vals = try splitTop(allocator, init_body, ',');
        for (vals, 0..) |part, idx| {
            if (idx >= fields.len or idx >= layout.offsets.len) break;
            const base = layout.offsets[idx];
            if (base >= out.len) break;
            const st = splitTypeInit(part) orelse continue;
            if (std.mem.eql(u8, st.init, "undef")) continue;
            try parseConstant(allocator, st.ty, st.init, out[base..], structs, ptr_size);
        }
        return;
    }
    if (std.mem.eql(u8, t, "x86_fp80")) {
        const bytes = parseF80Bytes(v);
        @memcpy(out[0..@min(out.len, 10)], bytes[0..@min(out.len, 10)]);
        return;
    }
    if (std.mem.eql(u8, t, "ptr")) {
        if (std.mem.startsWith(u8, v, "inttoptr")) {
            if (std.mem.indexOf(u8, v, "i64")) |idx| {
                const tail = v[idx + 3 ..];
                const sp = std.mem.indexOfScalar(u8, tail, ' ') orelse return;
                const n = parseI64(tail[0..sp]) orelse return;
                writeIntLE(out, @bitCast(n), @intCast(ptr_size));
            }
            return;
        }
        if (std.mem.eql(u8, v, "null")) return;
        return;
    }
    if (std.mem.eql(u8, t, "float") or std.mem.eql(u8, t, "double")) {
        const bits = parseFloatBits(v, t) orelse return;
        writeIntLE(out, bits, if (std.mem.eql(u8, t, "float")) 4 else 8);
        return;
    }
    if (t.len > 0 and t[0] == 'i') {
        const bits = std.fmt.parseInt(u32, t[1..], 10) catch return;
        const size = @max(1, (bits + 7) / 8);
        var num: i64 = 0;
        if (std.mem.startsWith(u8, v, "i")) {
            const sp = std.mem.indexOfScalar(u8, v, ' ') orelse return;
            num = parseI64(v[sp + 1 ..]) orelse 0;
        } else {
            num = parseI64(v) orelse 0;
        }
        writeIntLE(out, @bitCast(num), size);
        return;
    }
}

fn collectRelocs(allocator: Allocator, ty: []const u8, init: []const u8, base: u32, structs: *const Structs, ptr_size: u32, out: *std.ArrayList(Reloc)) !void {
    const t = std.mem.trim(u8, ty, " \t\r");
    const v = std.mem.trim(u8, init, " \t\r");
    if (std.mem.eql(u8, t, "ptr")) {
        if (std.mem.startsWith(u8, v, "getelementptr") or std.mem.startsWith(u8, v, "ptr getelementptr")) {
            var g = v;
            if (std.mem.startsWith(u8, g, "ptr ")) g = std.mem.trim(u8, g[4..], " ");
            const open = std.mem.indexOfScalar(u8, g, '(') orelse return;
            const close = std.mem.lastIndexOfScalar(u8, g, ')') orelse return;
            const parts = try splitTop(allocator, g[open + 1 .. close], ',');
            if (parts.len < 3) return;
            const target = lastAt(parts[1]) orelse return;
            const step = (try typeSizeAlign(allocator, std.mem.trim(u8, parts[0], " "), structs, ptr_size)).size;
            const idx_text = std.mem.trim(u8, parts[2], " ");
            const sp = std.mem.indexOfScalar(u8, idx_text, ' ');
            const idx = parseI64(if (sp) |s| idx_text[s + 1 ..] else idx_text) orelse 0;
            try out.append(.{ .offset = base, .target = try std.fmt.allocPrint(allocator, "@{s}", .{target}), .addend = @as(i64, step) *% idx });
            return;
        }
        if (lastAt(v)) |name| try out.append(.{ .offset = base, .target = try std.fmt.allocPrint(allocator, "@{s}", .{name}), .addend = 0 });
        return;
    }
    const fields_opt = try structFields(allocator, t, structs);
    if (fields_opt != null and (t[0] == '%' or t[0] == '{' or std.mem.startsWith(u8, t, "<{"))) {
        var fields = fields_opt.?;
        if (fields.len > 0 and std.mem.eql(u8, fields[0], "__packed__")) fields = fields[1..];
        const layout = try structLayout(allocator, t, structs, ptr_size);
        var body = v;
        if (std.mem.startsWith(u8, body, "<{")) body = body[2 .. body.len - 2] else if (body.len > 0 and body[0] == '{') body = body[1 .. body.len - 1];
        const vals = try splitTop(allocator, body, ',');
        for (vals, 0..) |part, idx| {
            if (idx >= fields.len or idx >= layout.offsets.len) break;
            const st = splitTypeInit(part) orelse continue;
            try collectRelocs(allocator, st.ty, st.init, base + layout.offsets[idx], structs, ptr_size, out);
        }
        return;
    }
    if (t.len > 0 and t[0] == '[') {
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return;
        const elem = inner[x + 3 ..];
        const es = try typeSizeAlign(allocator, elem, structs, ptr_size);
        if (v.len > 0 and v[0] == '[') {
            const vals = try splitTop(allocator, v[1 .. v.len - 1], ',');
            for (vals, 0..) |part, idx| {
                const st = splitTypeInit(part) orelse continue;
                try collectRelocs(allocator, st.ty, st.init, base + @as(u32, @intCast(idx)) * es.size, structs, ptr_size, out);
            }
        }
    }
}

fn findWordOutsideQuotes(text: []const u8, word: []const u8) ?usize {
    var in_quote = false;
    var i: usize = 0;
    while (i + word.len <= text.len) : (i += 1) {
        if (text[i] == '"' and (i == 0 or text[i - 1] != '\\')) {
            in_quote = !in_quote;
            continue;
        }
        if (in_quote) continue;
        if (!std.mem.startsWith(u8, text[i..], word)) continue;
        const before_ok = i == 0 or !std.ascii.isAlphanumeric(text[i - 1]);
        const after = i + word.len;
        const after_ok = after >= text.len or !std.ascii.isAlphanumeric(text[after]);
        if (before_ok and after_ok) return i;
    }
    return null;
}

/// LLVM linker metadata globals (`@llvm.compiler.used`, `@llvm.global_ctors`,
/// ...) describe linker-side metadata; they are not program objects and must
/// not reserve VM storage. `lower_ast.buildGlobals` skips them; skip them here
/// too so both frontends produce the same data image.
fn isLlvmMetadataGlobal(name: []const u8) bool {
    const bare = if (name.len > 0 and name[0] == '@') name[1..] else name;
    return std.mem.startsWith(u8, bare, "llvm.") or std.mem.startsWith(u8, bare, ".llvm.");
}

fn parseGlobals(allocator: Allocator, text: []const u8, structs: *const Structs, ptr_size: u32) !Globals {
    const Spec = struct { name: []const u8, ty: []const u8, init: []const u8, align_: u32 };
    var specs = std.ArrayList(Spec).init(allocator);
    var external = std.StringHashMap(u16).init(allocator);
    var external_names = std.ArrayList([]const u8).init(allocator);
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = stripMeta(raw);
        if (!std.mem.startsWith(u8, line, "@")) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const name = std.mem.trim(u8, line[0..eq], " \t\r");
        if (isLlvmMetadataGlobal(name)) continue;
        const rest = std.mem.trim(u8, line[eq + 1 ..], " \t\r");
        if (std.mem.startsWith(u8, rest, "external ") or std.mem.indexOf(u8, rest, " external ") != null) {
            if (std.mem.indexOf(u8, rest, "global") != null or std.mem.indexOf(u8, rest, "thread_local") != null) {
                if (external_names.items.len <= std.math.maxInt(u16)) {
                    const idx: u16 = @intCast(external_names.items.len);
                    try external.put(name, idx);
                    try external_names.append(name);
                }
            }
            continue;
        }
        var gpos = findWordOutsideQuotes(rest, "global");
        var kw_len: usize = 6;
        if (gpos == null) {
            gpos = findWordOutsideQuotes(rest, "constant");
            kw_len = 8;
        }
        const gstart = gpos orelse continue;
        const tail_raw = std.mem.trim(u8, rest[gstart + kw_len ..], " \t\r");
        var explicit_align: u32 = 0;
        var tail = tail_raw;
        if (std.mem.indexOf(u8, tail_raw, ", align")) |idx| {
            explicit_align = std.fmt.parseInt(u32, std.mem.trim(u8, tail_raw[idx + 7 ..], " "), 10) catch 0;
            tail = std.mem.trim(u8, tail_raw[0..idx], " \t\r");
        }
        const tm = splitTypeInit(tail) orelse continue;
        try specs.append(.{ .name = name, .ty = tm.ty, .init = tm.init, .align_ = explicit_align });
    }
    var map = std.StringHashMap(u32).init(allocator);
    var data = std.ArrayList(u8).init(allocator);
    for (specs.items) |spec| {
        const sa = typeSizeAlign(allocator, spec.ty, structs, ptr_size) catch continue;
        const off = alignUp(@intCast(data.items.len), @max(@max(sa.alignment, spec.align_), 1));
        while (data.items.len < off) try data.append(0);
        try map.put(spec.name, off);
        var i: u32 = 0;
        while (i < sa.size) : (i += 1) try data.append(0);
    }
    for (specs.items) |spec| {
        const off = map.get(spec.name) orelse continue;
        const sa = typeSizeAlign(allocator, spec.ty, structs, ptr_size) catch continue;
        try parseConstant(allocator, spec.ty, spec.init, data.items[off .. off + sa.size], structs, ptr_size);
    }
    var relocs = std.ArrayList(Reloc).init(allocator);
    for (specs.items) |spec| {
        const off = map.get(spec.name) orelse continue;
        try collectRelocs(allocator, spec.ty, spec.init, off, structs, ptr_size, &relocs);
    }
    while (data.items.len % 8 != 0) try data.append(0);
    return .{ .map = map, .external = external, .external_names = try external_names.toOwnedSlice(), .data = try data.toOwnedSlice(), .relocs = try relocs.toOwnedSlice() };
}

fn parseDecls(allocator: Allocator, text: []const u8) !std.StringHashMap(Decl) {
    var decls = std.StringHashMap(Decl).init(allocator);
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "declare ")) continue;
        const at = std.mem.indexOfScalar(u8, line, '@') orelse continue;
        var name_end = at + 1;
        if (name_end < line.len and line[name_end] == '"') {
            name_end += 1;
            while (name_end < line.len and line[name_end] != '"') name_end += 1;
            name_end += 1;
        } else {
            while (name_end < line.len and (std.ascii.isAlphanumeric(line[name_end]) or line[name_end] == '_' or line[name_end] == '.' or line[name_end] == '$' or line[name_end] == '-')) name_end += 1;
        }
        const name = normalizeName(line[at + 1 .. name_end]);
        var open = std.mem.indexOfScalarPos(u8, line, name_end, '(') orelse continue;
        var depth: i32 = 0;
        var close: ?usize = null;
        var i = open;
        while (i < line.len) : (i += 1) {
            if (line[i] == '(') depth += 1;
            if (line[i] == ')') {
                depth -= 1;
                if (depth == 0) {
                    close = i;
                    break;
                }
            }
        }
        const end = close orelse continue;
        const params_text = line[open + 1 .. end];
        const pre = std.mem.trim(u8, line[7..open], " \t\r");
        var ret = typeToken(pre);
        if (std.mem.indexOf(u8, pre, "(")) |lp| ret = typeToken(pre[0..lp]);
        var params = std.ArrayList([]const u8).init(allocator);
        var varargs = false;
        if (std.mem.trim(u8, params_text, " ").len > 0) {
            const parts = try splitTop(allocator, params_text, ',');
            for (parts) |p| {
                if (std.mem.eql(u8, p, "...")) {
                    varargs = true;
                    continue;
                }
                try params.append(typeToken(p));
            }
        }
        try decls.put(name, .{ .ret = ret, .params = try params.toOwnedSlice(), .is_varargs = varargs });
        _ = &open;
    }
    return decls;
}

const Param = struct { ty: []const u8, name: []const u8, raw: []const u8 };

fn parseFunctionHeader(line: []const u8) ?struct { name: []const u8, ret: []const u8, params: []const Param } {
    _ = line;
    return null;
}

fn parseFunctionsFrom(allocator: Allocator, text: []const u8) ![]Function {
    var funcs = std.ArrayList(Function).init(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var body = std.ArrayList([]const u8).init(allocator);
    var pending: ?struct { name: []const u8, ret: []const u8, params: []Param, is_varargs: bool } = null;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (pending == null) {
            if (!std.mem.startsWith(u8, line, "define ")) continue;
            const at = std.mem.indexOfScalar(u8, line, '@') orelse continue;
            var name_end = at + 1;
            if (name_end < line.len and line[name_end] == '"') {
                name_end += 1;
                while (name_end < line.len and line[name_end] != '"') name_end += 1;
                name_end += 1;
            } else {
                while (name_end < line.len and (std.ascii.isAlphanumeric(line[name_end]) or line[name_end] == '_' or line[name_end] == '.' or line[name_end] == '$' or line[name_end] == '-')) name_end += 1;
            }
            const open = std.mem.indexOfScalarPos(u8, line, name_end, '(') orelse continue;
            var depth: i32 = 0;
            var close: ?usize = null;
            var i = open;
            while (i < line.len) : (i += 1) {
                if (line[i] == '(') depth += 1;
                if (line[i] == ')') {
                    depth -= 1;
                    if (depth == 0) {
                        close = i;
                        break;
                    }
                }
            }
            const end = close orelse continue;
            const pre = stripDefinePrefix(line[6..open]);
            var ret = typeToken(pre);
            if (std.mem.indexOf(u8, pre, "(")) |lp| ret = typeToken(pre[0..lp]);
            const params_text = line[open + 1 .. end];
            var params = std.ArrayList(Param).init(allocator);
            if (std.mem.trim(u8, params_text, " ").len > 0 and !std.mem.eql(u8, std.mem.trim(u8, params_text, " "), "void")) {
                const parts = try splitTop(allocator, params_text, ',');
                for (parts) |p| {
                    if (std.mem.eql(u8, p, "...")) continue;
                    const ty = typeToken(p);
                    const nm = lastPercent(p);
                    if (nm == null) continue;
                    try params.append(.{ .ty = ty, .name = nm.?, .raw = p });
                }
            }
            pending = .{ .name = normalizeName(line[at + 1 .. name_end]), .ret = ret, .params = try params.toOwnedSlice(), .is_varargs = std.mem.indexOf(u8, params_text, "...") != null };
            body.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, line, "}")) {
            const p = pending.?;
            var param_names = std.ArrayList([]const u8).init(allocator);
            var param_types = std.ArrayList([]const u8).init(allocator);
            var param_attrs = std.ArrayList([]const u8).init(allocator);
            var param_count: u16 = 0;
            var is_varargs = false;
            for (p.params) |param| {
                try param_names.append(param.name);
                try param_types.append(param.ty);
                try param_attrs.append(param.raw);
                if (std.mem.eql(u8, std.mem.trim(u8, param.raw, " "), "...")) is_varargs = true else param_count += 1;
            }
            try funcs.append(.{
                .name = p.name,
                .ret = p.ret,
                .param_count = param_count,
                .param_names = try param_names.toOwnedSlice(),
                .param_types = try param_types.toOwnedSlice(),
                .param_attrs = try param_attrs.toOwnedSlice(),
                .is_varargs = p.is_varargs,
                .local_count = param_count,
                .code = std.ArrayList(u8).init(allocator),
            });
            // Body is lowered later; attach via a parallel list keyed by index.
            pending = null;
            continue;
        }
        try body.append(raw);
    }
    return funcs.toOwnedSlice();
}

// The parser above intentionally keeps the body attached to each function in a
// second pass; this table is filled by parseModule.
const BodyTable = struct {
    bodies: [][]const []const u8,
};

fn parseModule(allocator: Allocator, text: []const u8) !struct { funcs: []Function, bodies: [][]const []const u8 } {
    var funcs = std.ArrayList(Function).init(allocator);
    var bodies = std.ArrayList([]const []const u8).init(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var body = std.ArrayList([]const u8).init(allocator);
    var pending: ?struct { name: []const u8, ret: []const u8, params: []Param, is_varargs: bool } = null;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (pending == null) {
            if (!std.mem.startsWith(u8, line, "define ")) continue;
            const at = std.mem.indexOfScalar(u8, line, '@') orelse continue;
            var name_end = at + 1;
            if (name_end < line.len and line[name_end] == '"') {
                name_end += 1;
                while (name_end < line.len and line[name_end] != '"') name_end += 1;
                name_end += 1;
            } else {
                while (name_end < line.len and (std.ascii.isAlphanumeric(line[name_end]) or line[name_end] == '_' or line[name_end] == '.' or line[name_end] == '$' or line[name_end] == '-')) name_end += 1;
            }
            const open = std.mem.indexOfScalarPos(u8, line, name_end, '(') orelse continue;
            var depth: i32 = 0;
            var close: ?usize = null;
            var i = open;
            while (i < line.len) : (i += 1) {
                if (line[i] == '(') depth += 1;
                if (line[i] == ')') {
                    depth -= 1;
                    if (depth == 0) {
                        close = i;
                        break;
                    }
                }
            }
            const end = close orelse continue;
            const pre = stripDefinePrefix(line[6..open]);
            var ret = typeToken(pre);
            if (std.mem.indexOf(u8, pre, "(")) |lp| ret = typeToken(pre[0..lp]);
            const params_text = line[open + 1 .. end];
            var params = std.ArrayList(Param).init(allocator);
            if (std.mem.trim(u8, params_text, " ").len > 0 and !std.mem.eql(u8, std.mem.trim(u8, params_text, " "), "void")) {
                const parts = try splitTop(allocator, params_text, ',');
                for (parts) |p| {
                    if (std.mem.eql(u8, p, "...")) continue;
                    const nm = lastPercent(p);
                    if (nm == null) continue;
                    try params.append(.{ .ty = typeToken(p), .name = nm.?, .raw = p });
                }
            }
            pending = .{ .name = normalizeName(line[at + 1 .. name_end]), .ret = ret, .params = try params.toOwnedSlice(), .is_varargs = std.mem.indexOf(u8, params_text, "...") != null };
            body.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, line, "}")) {
            const p = pending.?;
            var names = std.ArrayList([]const u8).init(allocator);
            var ptypes = std.ArrayList([]const u8).init(allocator);
            var pattrs = std.ArrayList([]const u8).init(allocator);
            var is_varargs = false;
            for (p.params) |param| {
                try names.append(param.name);
                try ptypes.append(param.ty);
                try pattrs.append(param.raw);
                if (std.mem.eql(u8, std.mem.trim(u8, param.raw, " "), "...")) is_varargs = true;
            }
            try funcs.append(.{
                .name = p.name,
                .ret = p.ret,
                .param_count = @intCast(p.params.len),
                .param_names = try names.toOwnedSlice(),
                .param_types = try ptypes.toOwnedSlice(),
                .param_attrs = try pattrs.toOwnedSlice(),
                .is_varargs = p.is_varargs,
                .local_count = @intCast(p.params.len),
                .code = std.ArrayList(u8).init(allocator),
            });
            try bodies.append(try body.toOwnedSlice());
            pending = null;
            continue;
        }
        try body.append(raw);
    }
    return .{ .funcs = try funcs.toOwnedSlice(), .bodies = try bodies.toOwnedSlice() };
}

const Lowerer = struct {
    allocator: Allocator,
    func: *Function,
    slots: std.StringHashMap(u16),
    next_slot: u16,
    labels: std.StringHashMap(u32),
    patches: std.ArrayList(Patch),
    phi_assignments: std.ArrayList(PhiAssign),
    globals: *const Globals,
    structs: *const Structs,
    func_indices: *const std.StringHashMap(u16),
    decls: *const std.StringHashMap(Decl),
    plans: *std.ArrayList(Plan),
    functions: []Function,
    callbacks: *CallbackTable,
    abi: u8,
    ptr_size: u32,
    select_id: u32 = 0,
    current_block: []const u8 = "",
    func_body: ?[]const []const u8 = null,

    fn emitU8(self: *Lowerer, v: u8) anyerror!void {
        try self.func.code.append(v);
    }
    fn emitU16(self: *Lowerer, v: u16) anyerror!void {
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, v, .little);
        try self.func.code.appendSlice(&buf);
    }
    fn emitU32(self: *Lowerer, v: u32) anyerror!void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, v, .little);
        try self.func.code.appendSlice(&buf);
    }
    fn emitI64(self: *Lowerer, v: i64) anyerror!void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, @bitCast(v), .little);
        try self.func.code.appendSlice(&buf);
    }
    fn emitConst(self: *Lowerer, v: i64) anyerror!void {
        try self.emitU8(op.OP_LOAD_CONST_I64);
        try self.emitI64(v);
    }
    fn emitLoadSlot(self: *Lowerer, slot: u16) anyerror!void {
        try self.emitU8(op.OP_LOAD_LOCAL);
        try self.emitU16(slot);
    }
    fn emitStoreSlot(self: *Lowerer, slot: u16) anyerror!void {
        try self.emitU8(op.OP_STORE_LOCAL);
        try self.emitU16(slot);
    }
    fn slotFor(self: *Lowerer, name: []const u8) !u16 {
        if (self.slots.get(name)) |s| return s;
        const s = self.next_slot;
        self.next_slot += 1;
        try self.slots.put(name, s);
        if (self.next_slot > self.func.local_count) self.func.local_count = self.next_slot;
        return s;
    }
    fn normalizeInt(self: *Lowerer, bits: u32, signed: bool) anyerror!void {
        if (bits == 0 or bits >= 64) return;
        const mask: i64 = @intCast((@as(u64, 1) << @intCast(bits)) - 1);
        try self.emitConst(mask);
        try self.emitU8(op.OP_AND);
        if (signed) {
            const shift: i64 = @intCast(64 - bits);
            try self.emitConst(shift);
            try self.emitU8(op.OP_SHL);
            try self.emitConst(shift);
            try self.emitU8(op.OP_SHR_S);
        }
    }
    fn emitIntOperand(self: *Lowerer, text: []const u8, bits: u32, signed: bool) anyerror!void {
        try self.emitOperand(text);
        try self.normalizeInt(bits, signed);
    }
    fn emitFloatOperand(self: *Lowerer, text: []const u8, ty: []const u8) anyerror!void {
        const stripped = std.mem.trim(u8, text, " \t\r");
        if (std.mem.eql(u8, ty, "x86_fp80") or std.mem.eql(u8, ty, "fp128")) {
            try self.emitOperand(stripped);
            return;
        }
        if (std.mem.indexOfAny(u8, stripped, "%@") == null) {
            const bits = parseFloatBits(stripped, ty) orelse return error.UnsupportedOperand;
            try self.emitConst(@bitCast(bits));
            return;
        }
        try self.emitOperand(stripped);
    }
    fn typeSize(self: *Lowerer, ty: []const u8) !u32 {
        return (try typeSizeAlign(self.allocator, ty, self.structs, self.ptr_size)).size;
    }
    fn typeStoreSize(self: *Lowerer, ty: []const u8) !u32 {
        return storeSize(self.allocator, ty, self.structs, self.ptr_size);
    }
    fn emitOperand(self: *Lowerer, text_in: []const u8) anyerror!void {
        var text = std.mem.trim(u8, text_in, " \t\r");
        if (std.mem.startsWith(u8, text, "ptr ") and (std.mem.startsWith(u8, text[4..], "inttoptr") or std.mem.startsWith(u8, text[4..], "ptrtoint"))) {
            text = std.mem.trim(u8, text[4..], " ");
        }
        if (text.len == 0) return error.UnsupportedOperand;
        if (std.mem.startsWith(u8, text, "%")) {
            try self.emitLoadSlot(try self.slotFor(text[1..]));
            return;
        }
        if (std.mem.startsWith(u8, text, "@")) {
            if (self.globals.map.get(text)) |off| {
                try self.emitU8(op.OP_ADDR_CONST);
                try self.emitU32(off);
                return;
            }
            const key = text[1..];
            if (self.func_indices.get(key)) |idx| {
                try self.emitU8(op.OP_FUNC_ADDR);
                try self.emitU16(idx);
                return;
            }
            if (self.globals.external.get(text)) |idx| {
                try self.emitU8(op.OP_ADDR_EXTERN);
                try self.emitU16(idx);
                return;
            }
            try self.emitConst(0);
            return;
        }
        if (std.mem.startsWith(u8, text, "icmp ")) {
            var it = std.mem.tokenizeScalar(u8, text, ' ');
            _ = it.next();
            const pred = it.next() orelse return error.UnsupportedOperand;
            var after_pred = std.mem.trim(u8, text["icmp ".len + pred.len ..], " ");
            if (after_pred.len >= 2 and after_pred[0] == '(' and after_pred[after_pred.len - 1] == ')') {
                after_pred = std.mem.trim(u8, after_pred[1 .. after_pred.len - 1], " ");
            }
            const ty = typeToken(after_pred);
            const rest = std.mem.trim(u8, after_pred[ty.len..], " ");
            try self.emitIcmpExpr(pred, ty, rest);
            return;
        }
        if (std.mem.startsWith(u8, text, "getelementptr ")) {
            try self.emitGep(text);
            return;
        }
        if (std.mem.startsWith(u8, text, "inttoptr") or std.mem.startsWith(u8, text, "ptrtoint")) {
            const open = std.mem.indexOfScalar(u8, text, '(') orelse return error.UnsupportedOperand;
            const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return error.UnsupportedOperand;
            var inner = std.mem.trim(u8, text[open + 1 .. close], " ");
            if (std.mem.startsWith(u8, inner, "i64 ")) inner = std.mem.trim(u8, inner[4..], " ");
            if (std.mem.startsWith(u8, inner, "ptr ")) inner = std.mem.trim(u8, inner[4..], " ");
            if (std.mem.indexOf(u8, inner, " to ")) |idx| inner = std.mem.trim(u8, inner[0..idx], " ");
            try self.emitOperand(inner);
            return;
        }
        if (std.mem.eql(u8, text, "null") or std.mem.eql(u8, text, "false") or std.mem.eql(u8, text, "undef") or std.mem.eql(u8, text, "zeroinitializer")) {
            try self.emitConst(0);
            return;
        }
        if (std.mem.eql(u8, text, "true")) {
            try self.emitConst(1);
            return;
        }
        if (std.mem.startsWith(u8, text, "double") or std.mem.startsWith(u8, text, "float")) {
            const ty = typeToken(text);
            try self.emitFloatOperand(text, ty);
            return;
        }
        if (std.mem.startsWith(u8, text, "x86_fp80") or std.mem.indexOf(u8, text, "0xK") != null) {
            const ty = typeToken(text);
            var value = if (ty.len < text.len) std.mem.trim(u8, text[ty.len..], " ") else text;
            value = stripLeadingAttrs(value);
            if (value.len > 0 and (value[0] == '%' or value[0] == '@')) {
                try self.emitOperand(value);
            } else {
                try emitF80Const(self, value);
            }
            return;
        }
        if (std.mem.startsWith(u8, text, "fp128") or std.mem.indexOf(u8, text, "0xL") != null) {
            const ty = typeToken(text);
            var value = if (ty.len < text.len) std.mem.trim(u8, text[ty.len..], " ") else text;
            value = stripLeadingAttrs(value);
            if (value.len > 0 and (value[0] == '%' or value[0] == '@')) {
                try self.emitOperand(value);
            } else {
                try emitF128Const(self, value);
            }
            return;
        }
        if (try self.emitConstExpr(text)) return;
        // Strip a leading type token when present.
        var value = text;
        const ty = typeToken(text);
        if (ty.len < text.len and text[ty.len] == ' ') value = std.mem.trim(u8, text[ty.len + 1 ..], " ");
        // Attributes such as noundef/signext/align precede the actual value.
        value = stripLeadingAttrs(value);
        if (value.len > 0 and (value[0] == '@' or value[0] == '%')) {
            try self.emitOperand(value);
            return;
        }
        if (std.mem.startsWith(u8, value, "ptr getelementptr ")) {
            try self.emitGep(value[4..]);
            return;
        }
        if (std.mem.indexOfAny(u8, value, ".eE") != null) {
            if (std.fmt.parseFloat(f64, value)) |fv| {
                try self.emitConst(@bitCast(@as(u64, @bitCast(fv))));
                return;
            } else |_| {}
        }
        if (std.mem.startsWith(u8, value, "getelementptr ")) {
            try self.emitGep(value);
            return;
        }
        if (parseI64(value)) |v| {
            try self.emitConst(v);
            return;
        }
        if (try self.emitConstExpr(value)) return;
        std.debug.print("unsupported operand: {s} (value={s})\n", .{ text, value });
        return error.UnsupportedOperand;
    }
    fn emitConstExpr(self: *Lowerer, text_in: []const u8) anyerror!bool {
        var t = std.mem.trim(u8, text_in, " \t\r");
        if (t.len >= 2 and t[0] == '(' and t[t.len - 1] == ')') t = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const ty = typeToken(t);
        if (ty.len < t.len) {
            const rest = std.mem.trim(u8, t[ty.len..], " ");
            if (rest.len > 0 and (std.mem.startsWith(u8, rest, "getelementptr ") or std.mem.startsWith(u8, rest, "ptrtoint") or std.mem.startsWith(u8, rest, "inttoptr") or std.mem.startsWith(u8, rest, "add ") or std.mem.startsWith(u8, rest, "sub ") or std.mem.startsWith(u8, rest, "mul ") or std.mem.startsWith(u8, rest, "shl ") or std.mem.startsWith(u8, rest, "lshr ") or std.mem.startsWith(u8, rest, "ashr ") or std.mem.startsWith(u8, rest, "and ") or std.mem.startsWith(u8, rest, "or ") or std.mem.startsWith(u8, rest, "xor ") or std.mem.startsWith(u8, rest, "trunc ") or std.mem.startsWith(u8, rest, "zext ") or std.mem.startsWith(u8, rest, "sext "))) {
                return self.emitConstExpr(rest);
            }
        }
        const sp = std.mem.indexOfScalar(u8, t, ' ');
        const opname = if (sp) |s| t[0..s] else t;
        if (std.mem.eql(u8, opname, "getelementptr")) {
            try self.emitGep(t);
            return true;
        }
        if (std.mem.eql(u8, opname, "ptrtoint") or std.mem.eql(u8, opname, "inttoptr")) {
            const open = std.mem.indexOfScalar(u8, t, '(') orelse return false;
            const close = std.mem.lastIndexOfScalar(u8, t, ')') orelse return false;
            var inner = std.mem.trim(u8, t[open + 1 .. close], " ");
            if (std.mem.indexOf(u8, inner, " to ")) |idx| inner = std.mem.trim(u8, inner[0..idx], " ");
            if (std.mem.startsWith(u8, inner, "ptr ")) inner = std.mem.trim(u8, inner[4..], " ");
            try self.emitOperand(inner);
            return true;
        }
        const binary = std.mem.eql(u8, opname, "add") or std.mem.eql(u8, opname, "sub") or std.mem.eql(u8, opname, "mul") or std.mem.eql(u8, opname, "shl") or std.mem.eql(u8, opname, "lshr") or std.mem.eql(u8, opname, "ashr") or std.mem.eql(u8, opname, "and") or std.mem.eql(u8, opname, "or") or std.mem.eql(u8, opname, "xor");
        if (binary) {
            var after = std.mem.trim(u8, t[opname.len..], " ");
            for ([_][]const u8{ "nsw ", "nuw ", "exact " }) |flag| {
                if (std.mem.startsWith(u8, after, flag)) {
                    after = std.mem.trim(u8, after[flag.len..], " ");
                    break;
                }
            }
            const open = std.mem.indexOfScalar(u8, after, '(') orelse return false;
            const close = std.mem.lastIndexOfScalar(u8, after, ')') orelse return false;
            const parts = try splitTop(self.allocator, after[open + 1 .. close], ',');
            if (parts.len != 2) return false;
            try self.emitOperand(parts[0]);
            try self.emitOperand(parts[1]);
            const opcode: u8 = if (std.mem.eql(u8, opname, "add")) op.OP_ADD else if (std.mem.eql(u8, opname, "sub")) op.OP_SUB else if (std.mem.eql(u8, opname, "mul")) op.OP_MUL else if (std.mem.eql(u8, opname, "shl")) op.OP_SHL else if (std.mem.eql(u8, opname, "lshr")) op.OP_SHR_U else if (std.mem.eql(u8, opname, "ashr")) op.OP_SHR_S else if (std.mem.eql(u8, opname, "and")) op.OP_AND else if (std.mem.eql(u8, opname, "or")) op.OP_OR else op.OP_XOR;
            try self.emitU8(opcode);
            return true;
        }
        if (std.mem.eql(u8, opname, "trunc") or std.mem.eql(u8, opname, "zext") or std.mem.eql(u8, opname, "sext")) {
            const open = std.mem.indexOfScalar(u8, t, '(') orelse return false;
            const close = std.mem.lastIndexOfScalar(u8, t, ')') orelse return false;
            const inner = std.mem.trim(u8, t[open + 1 .. close], " ");
            const to_idx = std.mem.lastIndexOf(u8, inner, " to ") orelse return false;
            const value = std.mem.trim(u8, inner[0..to_idx], " ");
            const dst_ty = typeToken(inner[to_idx + 4 ..]);
            try self.emitOperand(value);
            const bits = if (dst_ty.len > 1 and dst_ty[0] == 'i') std.fmt.parseInt(u32, dst_ty[1..], 10) catch 64 else 64;
            if (std.mem.eql(u8, opname, "zext")) {
                const src_bits = if (ty.len > 1 and ty[0] == 'i') std.fmt.parseInt(u32, ty[1..], 10) catch 64 else 64;
                if (src_bits < 64) {
                    try self.emitConst(@intCast((@as(u64, 1) << @intCast(src_bits)) - 1));
                    try self.emitU8(op.OP_AND);
                }
            }
            try self.normalizeInt(bits, true);
            return true;
        }
        return false;
    }

    fn emitIcmpExpr(self: *Lowerer, pred: []const u8, ty: []const u8, args_text: []const u8) anyerror!void {
        const bits: u32 = if (ty.len > 0 and ty[0] == 'i') std.fmt.parseInt(u32, ty[1..], 10) catch 64 else self.ptr_size * 8;
        const signed = std.mem.eql(u8, pred, "slt") or std.mem.eql(u8, pred, "sle") or std.mem.eql(u8, pred, "sgt") or std.mem.eql(u8, pred, "sge");
        const args = try splitTop(self.allocator, args_text, ',');
        if (args.len != 2) {
            std.debug.print("bad icmp args ({d}): pred={s} ty={s} args={s}\n", .{ args.len, pred, ty, args_text });
            return error.BadIcmp;
        }
        const a = args[0];
        const b = args[1];
        var invert = false;
        if (std.mem.eql(u8, pred, "eq") or std.mem.eql(u8, pred, "ne")) {
            try self.emitIntOperand(a, bits, false);
            try self.emitIntOperand(b, bits, false);
            try self.emitU8(op.OP_CMP_EQ);
            if (std.mem.eql(u8, pred, "ne")) invert = true;
        } else if (std.mem.eql(u8, pred, "slt") or std.mem.eql(u8, pred, "ult")) {
            try self.emitIntOperand(a, bits, signed);
            try self.emitIntOperand(b, bits, signed);
            try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
        } else if (std.mem.eql(u8, pred, "sgt") or std.mem.eql(u8, pred, "ugt")) {
            try self.emitIntOperand(b, bits, signed);
            try self.emitIntOperand(a, bits, signed);
            try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
        } else if (std.mem.eql(u8, pred, "sle") or std.mem.eql(u8, pred, "ule")) {
            try self.emitIntOperand(b, bits, signed);
            try self.emitIntOperand(a, bits, signed);
            try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
            invert = true;
        } else if (std.mem.eql(u8, pred, "sge") or std.mem.eql(u8, pred, "uge")) {
            try self.emitIntOperand(a, bits, signed);
            try self.emitIntOperand(b, bits, signed);
            try self.emitU8(if (signed) op.OP_CMP_LT else op.OP_CMP_LT_U);
            invert = true;
        } else return error.BadIcmp;
        if (invert) {
            try self.emitConst(1);
            try self.emitU8(op.OP_XOR);
        }
    }
    fn emitPointer(self: *Lowerer, text_in: []const u8) anyerror!void {
        var text = stripAlign(text_in);
        if (std.mem.startsWith(u8, text, "ptr ")) text = std.mem.trim(u8, text[4..], " ");
        text = stripLeadingAttrs(text);
        if (std.mem.startsWith(u8, text, "getelementptr ")) {
            try self.emitGep(text);
            return;
        }
        if (text.len > 0 and (text[0] == '%' or text[0] == '@')) {
            try self.emitOperand(text);
            return;
        }
        if (std.mem.eql(u8, text, "null")) {
            try self.emitConst(0);
            return;
        }
        try self.emitOperand(text);
    }
    fn emitIndexAdd(self: *Lowerer, index_in: []const u8, step: u32) anyerror!void {
        const index = std.mem.trim(u8, index_in, " ");
        if (step == 0) return;
        if (std.mem.indexOfScalar(u8, index, '%') == null) {
            var n: ?i64 = null;
            var it = std.mem.tokenizeAny(u8, index, " ,");
            while (it.next()) |tok| {
                if (parseI64(tok)) |v| n = v;
            }
            if (n) |v| {
                const off = v *% @as(i64, step);
                if (off != 0) {
                    try self.emitConst(off);
                    try self.emitU8(op.OP_ADD);
                }
                return;
            }
        }
        try self.emitOperand(index);
        try self.emitConst(step);
        try self.emitU8(op.OP_MUL);
        try self.emitU8(op.OP_ADD);
    }
    fn emitGep(self: *Lowerer, rhs: []const u8) anyerror!void {
        var rest = std.mem.trim(u8, rhs[13..], " ");
        if (std.mem.startsWith(u8, rest, "inbounds ")) rest = rest[9..];
        if (std.mem.startsWith(u8, rest, "nuw ")) rest = rest[4..];
        if (rest.len > 0 and rest[0] == '(' and rest[rest.len - 1] == ')') rest = rest[1 .. rest.len - 1];
        const parts = try splitTop(self.allocator, rest, ',');
        if (parts.len < 2) return error.BadGep;
        var current = parts[0];
        try self.emitPointer(parts[1]);
        var pos: usize = 0;
        while (pos + 2 < parts.len) : (pos += 1) {
            const index = parts[pos + 2];
            if (pos == 0) {
                try self.emitIndexAdd(index, try self.typeSize(current));
                continue;
            }
            if (current.len > 0 and current[0] == '[') {
                const inner = std.mem.trim(u8, current[1 .. current.len - 1], " ");
                const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadGep;
                const elem = inner[x + 3 ..];
                try self.emitIndexAdd(index, try self.typeSize(elem));
                current = elem;
                continue;
            }
            if (try structFields(self.allocator, current, self.structs)) |fields| {
                var field_idx: ?i64 = null;
                var it = std.mem.tokenizeAny(u8, index, " ,");
                while (it.next()) |tok| {
                    if (parseI64(tok)) |v| field_idx = v;
                }
                const fi = field_idx orelse return error.BadGep;
                if (fi < 0 or fi >= fields.len) return error.BadGep;
                const layout = try structLayout(self.allocator, current, self.structs, self.ptr_size);
                const off = layout.offsets[@intCast(fi)];
                if (off != 0) {
                    try self.emitConst(off);
                    try self.emitU8(op.OP_ADD);
                }
                current = fields[@intCast(fi)];
                continue;
            }
            return error.BadGep;
        }
    }
    fn jump(self: *Lowerer, opcode: u8, label: []const u8) anyerror!void {
        try self.emitU8(opcode);
        const pos: u32 = @intCast(self.func.code.items.len);
        try self.emitU32(0);
        try self.patches.append(.{ .pos = pos, .label = label });
    }
    fn emitPhiAssignments(self: *Lowerer, block: []const u8) anyerror!void {
        for (self.phi_assignments.items) |assign| {
            if (!std.mem.eql(u8, assign.pred, block)) continue;
            try self.emitOperand(assign.value);
            try self.emitStoreSlot(try self.slotFor(assign.result));
        }
    }
    fn collectPhiAssignments(self: *Lowerer, body: []const []const u8) !void {
        for (body) |raw| {
            const line = stripMeta(raw);
            const phi_pos = std.mem.indexOf(u8, line, "= phi ") orelse continue;
            const lhs = std.mem.trim(u8, line[0..phi_pos], " ");
            if (lhs.len < 2 or lhs[0] != '%') continue;
            const result = lhs[1..];
            var rest = line[phi_pos + 6 ..];
            while (true) {
                const open = std.mem.indexOfScalar(u8, rest, '[') orelse break;
                const close_rel = std.mem.indexOfScalarPos(u8, rest, open, ']') orelse break;
                const inner = rest[open + 1 .. close_rel];
                const parts = try splitTop(self.allocator, inner, ',');
                if (parts.len >= 2) {
                    var label = std.mem.trim(u8, parts[1], " ");
                    if (label.len > 0 and label[0] == '%') label = label[1..];
                    try self.phi_assignments.append(.{ .pred = label, .result = result, .value = parts[0] });
                }
                rest = rest[close_rel + 1 ..];
            }
        }
    }
    fn lower(self: *Lowerer) anyerror!void {
        if (std.mem.eql(u8, self.func.name, "main") and self.globals.data.len > 0) {
            try self.emitU8(op.OP_SET_MEM_TOP);
            try self.emitU32(@intCast(self.globals.data.len));
            var off: usize = 0;
            while (off < self.globals.data.len) : (off += 8) {
                var chunk: u64 = 0;
                var i: usize = 0;
                while (i < 8 and off + i < self.globals.data.len) : (i += 1) {
                    chunk |= @as(u64, self.globals.data[off + i]) << @intCast(i * 8);
                }
                try self.emitConst(@bitCast(chunk));
                try self.emitU8(op.OP_ADDR_CONST);
                try self.emitU32(@intCast(off));
                try self.emitU8(op.OP_STORE_MEM);
                try self.emitU8(@intCast(@min(8, self.globals.data.len - off)));
            }
            for (self.globals.relocs) |reloc| {
                const target = reloc.target;
                var handled = false;
                if (self.globals.map.get(target)) |gofs| {
                    try self.emitU8(op.OP_ADDR_CONST);
                    try self.emitU32(gofs);
                    handled = true;
                } else if (target.len > 1) {
                    if (self.func_indices.get(target[1..])) |fidx| {
                        try self.emitU8(op.OP_FUNC_ADDR);
                        try self.emitU16(fidx);
                        handled = true;
                    }
                }
                if (!handled) {
                    if (self.globals.external.get(target)) |eidx| {
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
                try self.emitU8(@intCast(self.ptr_size));
            }
        }
        const body = self.func_body orelse return error.NoBody;
        for (self.func.param_types, 0..) |pty, pi| {
            if (!std.mem.eql(u8, pty, "x86_fp80") and !std.mem.eql(u8, pty, "fp128")) continue;
            if (pi >= self.func.param_names.len) break;
            const ps = try self.slotFor(self.func.param_names[pi]);
            try self.emitU8(op.OP_ALLOCA);
            try self.emitU16(16);
            try self.emitU8(op.OP_DUP);
            try self.emitLoadSlot(ps);
            try self.emitConst(16);
            try self.emitU8(op.OP_MEMCPY);
            try self.emitStoreSlot(ps);
        }
        self.current_block = "entry";
        try self.collectPhiAssignments(body);
        var i: usize = 0;
        while (i < body.len) : (i += 1) {
            var line = stripMeta(body[i]);
            if (std.mem.indexOfScalar(u8, line, ';')) |comment| line = std.mem.trim(u8, line[0..comment], " \t\r");
            if (line.len == 0 or std.mem.startsWith(u8, line, "#dbg")) continue;
            if (line[line.len - 1] == ':') {
                const label = line[0 .. line.len - 1];
                self.current_block = label;
                try self.labels.put(label, @intCast(self.func.code.items.len));
                continue;
            }
            if (std.mem.startsWith(u8, line, "br ") or std.mem.startsWith(u8, line, "switch ") or std.mem.startsWith(u8, line, "ret ") or std.mem.eql(u8, line, "unreachable")) {
                try self.emitPhiAssignments(self.current_block);
            }
            if (std.mem.startsWith(u8, line, "switch ")) {
                var cases = std.ArrayList([]const u8).init(self.allocator);
                i += 1;
                while (i < body.len) : (i += 1) {
                    var part = stripMeta(body[i]);
                    const closed = std.mem.indexOfScalar(u8, part, ']') != null;
                    part = std.mem.trim(u8, std.mem.replaceOwned(u8, self.allocator, part, "]", "") catch part, " ");
                    if (part.len > 0) try cases.append(part);
                    if (closed) break;
                }
                try self.lowerSwitch(line, cases.items);
                continue;
            }
            try self.lowerInstr(line);
        }
        for (self.patches.items) |patch| {
            const target = self.labels.get(patch.label) orelse return error.UnknownLabel;
            var buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &buf, target, .little);
            @memcpy(self.func.code.items[patch.pos .. patch.pos + 4], &buf);
        }
        self.func.local_count = self.next_slot;
    }
    fn lowerSwitch(self: *Lowerer, header: []const u8, cases: []const []const u8) anyerror!void {
        const comma = std.mem.indexOfScalar(u8, header, ',') orelse return error.BadSwitch;
        const cond = std.mem.trim(u8, header[6..comma], " ");
        const default_label = blk: {
            const li = std.mem.indexOf(u8, header, "label %") orelse return error.BadSwitch;
            break :blk std.mem.trim(u8, header[li + 7 ..], " [");
        };
        for (cases) |case| {
            const li = std.mem.indexOf(u8, case, "label %") orelse continue;
            const label = std.mem.trim(u8, case[li + 7 ..], " ");
            const comma2 = std.mem.indexOfScalar(u8, case, ',') orelse continue;
            const value_text = std.mem.trim(u8, case[0..comma2], " ");
            var val: i64 = 0;
            var vit = std.mem.tokenizeAny(u8, value_text, " ,");
            while (vit.next()) |tok| {
                if (parseI64(tok)) |v| val = v;
            }
            try self.emitOperand(cond);
            try self.emitConst(val);
            try self.emitU8(op.OP_CMP_EQ);
            try self.jump(op.OP_JNZ, label);
        }
        try self.jump(op.OP_JMP, default_label);
    }
    fn lowerInstr(self: *Lowerer, line: []const u8) anyerror!void {
        var result: ?[]const u8 = null;
        var rhs = line;
        if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
            const lhs = std.mem.trim(u8, line[0..eq], " ");
            rhs = std.mem.trim(u8, line[eq + 1 ..], " ");
            if (lhs.len > 1 and lhs[0] == '%') result = lhs[1..];
        }
        if (std.mem.startsWith(u8, rhs, "alloca ")) {
            const res = result orelse return error.NoResult;
            var raw = std.mem.trim(u8, rhs[7..], " ");
            var alloc_align: u32 = 8;
            if (std.mem.indexOf(u8, raw, ", align")) |idx| {
                alloc_align = std.fmt.parseInt(u32, std.mem.trim(u8, raw[idx + 7 ..], " "), 10) catch 8;
                raw = std.mem.trim(u8, raw[0..idx], " ");
            }
            const parts = try splitTop(self.allocator, raw, ',');
            const ty = parts[0];
            if (parts.len > 1) {
                try self.emitOperand(parts[1]);
                const size = try self.typeSize(ty);
                if (size != 1) {
                    try self.emitConst(size);
                    try self.emitU8(op.OP_MUL);
                }
                if (alloc_align > 8) {
                    try self.emitU8(op.OP_ALLOCA_DYN_ALIGN);
                    try self.emitU8(@intCast(alloc_align));
                } else try self.emitU8(op.OP_ALLOCA_DYN);
            } else {
                const size = try self.typeSize(ty);
                if (size > 0xFFFF) {
                    try self.emitConst(size);
                    if (alloc_align > 8) {
                        try self.emitU8(op.OP_ALLOCA_DYN_ALIGN);
                        try self.emitU8(@intCast(alloc_align));
                    } else try self.emitU8(op.OP_ALLOCA_DYN);
                } else if (alloc_align > 8) {
                    try self.emitU8(op.OP_ALLOCA_ALIGNED);
                    try self.emitU16(@intCast(size));
                    try self.emitU8(@intCast(alloc_align));
                } else {
                    try self.emitU8(op.OP_ALLOCA);
                    try self.emitU16(@intCast(size));
                }
            }
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "phi ")) {
            _ = try self.slotFor(result orelse return error.NoResult);
            return;
        }
        if (std.mem.startsWith(u8, rhs, "store ")) {
            var store_rhs = rhs[6..];
            if (std.mem.startsWith(u8, store_rhs, "volatile ")) store_rhs = store_rhs[9..];
            if (std.mem.startsWith(u8, store_rhs, "atomic ")) store_rhs = store_rhs[7..];
            const st = splitTypeInit(store_rhs) orelse return error.BadStore;
            const ty = st.ty;
            var depth: i32 = 0;
            var value: []const u8 = "";
            var ptr: []const u8 = "";
            var pos: usize = 0;
            while (pos < st.init.len) : (pos += 1) {
                switch (st.init[pos]) {
                    '(', '[', '{', '<' => depth += 1,
                    ')', ']', '}', '>' => depth -= 1,
                    ',' => {
                        if (depth == 0) {
                            var rest = std.mem.trim(u8, st.init[pos + 1 ..], " ");
                            if (std.mem.startsWith(u8, rest, "ptr ")) {
                                value = std.mem.trim(u8, st.init[0..pos], " ");
                                rest = std.mem.trim(u8, rest[4..], " ");
                                ptr = stripAlign(rest);
                                break;
                            }
                        }
                    },
                    else => {},
                }
            }
            if (value.len == 0 or ptr.len == 0) return error.BadStore;
            const size = try self.typeStoreSize(ty);
            if (size == 0) return error.BadStore;
            if (std.mem.eql(u8, ty, "x86_fp80") or std.mem.eql(u8, ty, "fp128") or (size > 8 and startsWithAny(ty, &.{ "%", "[", "{", "<" }))) {
                try self.emitPointer(ptr);
                try self.emitPointer(value);
                try self.emitConst(size);
                try self.emitU8(op.OP_MEMCPY);
                return;
            }
            if (size > 8) return error.BadStore;
            if (std.mem.eql(u8, ty, "float") or std.mem.eql(u8, ty, "double")) {
                try self.emitFloatOperand(value, ty);
            } else try self.emitOperand(value);
            try self.emitPointer(ptr);
            try self.emitU8(op.OP_STORE_MEM);
            try self.emitU8(@intCast(size));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "load ")) {
            const res = result orelse return error.NoResult;
            var load_rhs = rhs[5..];
            if (std.mem.startsWith(u8, load_rhs, "volatile ")) load_rhs = load_rhs[9..];
            if (std.mem.startsWith(u8, load_rhs, "atomic ")) load_rhs = load_rhs[7..];
            var depth: i32 = 0;
            var comma: ?usize = null;
            var ci: usize = 0;
            while (ci < load_rhs.len) : (ci += 1) {
                switch (load_rhs[ci]) {
                    '(', '[', '{', '<' => depth += 1,
                    ')', ']', '}', '>' => depth -= 1,
                    ',' => {
                        if (depth == 0) {
                            comma = ci;
                            break;
                        }
                    },
                    else => {},
                }
            }
            const comma_idx = comma orelse return error.BadLoad;
            const ty = std.mem.trim(u8, load_rhs[0..comma_idx], " ");
            var after = std.mem.trim(u8, load_rhs[comma_idx + 1 ..], " ");
            if (std.mem.startsWith(u8, after, "ptr ")) after = std.mem.trim(u8, after[4..], " ");
            const ptr = stripAlign(after);
            const size = try self.typeStoreSize(ty);
            if (size == 0) return error.BadLoad;
            if (std.mem.eql(u8, ty, "x86_fp80") or std.mem.eql(u8, ty, "fp128") or size > 8) {
                try self.emitPointer(ptr);
            } else {
                try self.emitPointer(ptr);
                try self.emitU8(op.OP_LOAD_MEM);
                try self.emitU8(@intCast(size));
            }
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "fadd ") or std.mem.startsWith(u8, rhs, "fsub ") or std.mem.startsWith(u8, rhs, "fmul ") or std.mem.startsWith(u8, rhs, "fdiv ")) {
            const res = result orelse return error.NoResult;
            const sp = std.mem.indexOfScalar(u8, rhs, ' ') orelse return error.BadFloat;
            const opname = rhs[0..sp];
            var rest = std.mem.trim(u8, rhs[sp + 1 ..], " ");
            if (std.mem.startsWith(u8, rest, "fast ")) rest = rest[5..];
            const ty = typeToken(rest);
            rest = std.mem.trim(u8, rest[ty.len..], " ");
            const args = try splitTop(self.allocator, rest, ',');
            if (args.len != 2) return error.BadFloat;
            try self.emitFloatOperand(args[0], ty);
            try self.emitFloatOperand(args[1], ty);
            if (std.mem.eql(u8, ty, "x86_fp80")) {
                try self.emitU8(if (std.mem.eql(u8, opname, "fadd")) op.OP_F80_ADD else if (std.mem.eql(u8, opname, "fsub")) op.OP_F80_SUB else if (std.mem.eql(u8, opname, "fmul")) op.OP_F80_MUL else op.OP_F80_DIV);
            } else if (std.mem.eql(u8, ty, "fp128")) {
                try self.emitU8(if (std.mem.eql(u8, opname, "fadd")) op.OP_F128_ADD else if (std.mem.eql(u8, opname, "fsub")) op.OP_F128_SUB else if (std.mem.eql(u8, opname, "fmul")) op.OP_F128_MUL else op.OP_F128_DIV);
            } else if (std.mem.eql(u8, ty, "float")) {
                try self.emitU8(if (std.mem.eql(u8, opname, "fadd")) op.OP_FADD32 else if (std.mem.eql(u8, opname, "fsub")) op.OP_FSUB32 else if (std.mem.eql(u8, opname, "fmul")) op.OP_FMUL32 else op.OP_FDIV32);
            } else {
                try self.emitU8(if (std.mem.eql(u8, opname, "fadd")) op.OP_FADD else if (std.mem.eql(u8, opname, "fsub")) op.OP_FSUB else if (std.mem.eql(u8, opname, "fmul")) op.OP_FMUL else op.OP_FDIV);
            }
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "fneg ")) {
            const res = result orelse return error.NoResult;
            const ty = typeToken(rhs[5..]);
            const val = std.mem.trim(u8, rhs[5 + ty.len ..], " ");
            if (std.mem.eql(u8, ty, "x86_fp80")) {
                try self.emitOperand(val);
                try self.emitU8(op.OP_F80_NEG);
            } else if (std.mem.eql(u8, ty, "fp128")) {
                try self.emitOperand(val);
                try self.emitU8(op.OP_F128_NEG);
            } else {
                try self.emitFloatOperand(val, ty);
                const sign: i64 = if (std.mem.eql(u8, ty, "float")) 0x80000000 else @bitCast(@as(u64, 0x8000000000000000));
                try self.emitConst(sign);
                try self.emitU8(op.OP_XOR);
            }
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "fcmp ")) {
            const res = result orelse return error.NoResult;
            const sp = std.mem.indexOfScalar(u8, rhs, ' ') orelse return error.BadFcmp;
            var rest = std.mem.trim(u8, rhs[sp + 1 ..], " ");
            const pred = typeToken(rest);
            rest = std.mem.trim(u8, rest[pred.len..], " ");
            const ty = typeToken(rest);
            rest = std.mem.trim(u8, rest[ty.len..], " ");
            const args = try splitTop(self.allocator, rest, ',');
            if (args.len != 2) return error.BadFcmp;
            const pred_code: u8 = if (std.mem.eql(u8, pred, "oeq")) 0 else if (std.mem.eql(u8, pred, "one")) 1 else if (std.mem.eql(u8, pred, "olt")) 2 else if (std.mem.eql(u8, pred, "ole")) 3 else if (std.mem.eql(u8, pred, "ogt")) 4 else if (std.mem.eql(u8, pred, "oge")) 5 else if (std.mem.eql(u8, pred, "ord")) 6 else if (std.mem.eql(u8, pred, "uno")) 7 else if (std.mem.eql(u8, pred, "ueq")) 8 else if (std.mem.eql(u8, pred, "ugt")) 9 else if (std.mem.eql(u8, pred, "uge")) 10 else if (std.mem.eql(u8, pred, "ult")) 11 else if (std.mem.eql(u8, pred, "ule")) 12 else if (std.mem.eql(u8, pred, "une")) 13 else return error.BadFcmp;
            try self.emitFloatOperand(args[0], ty);
            try self.emitFloatOperand(args[1], ty);
            if (std.mem.eql(u8, ty, "x86_fp80")) {
                try self.emitU8(op.OP_F80_CMP);
            } else if (std.mem.eql(u8, ty, "fp128")) {
                try self.emitU8(op.OP_F128_CMP);
            } else {
                try self.emitU8(if (std.mem.eql(u8, ty, "float")) op.OP_FCMP32 else op.OP_FCMP);
            }
            try self.emitU8(pred_code);
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "icmp ")) {
            const res = result orelse return error.NoResult;
            const sp = std.mem.indexOfScalar(u8, rhs, ' ') orelse return error.BadIcmp;
            const rest = std.mem.trim(u8, rhs[sp + 1 ..], " ");
            const pred = typeToken(rest);
            var rest2 = std.mem.trim(u8, rest[pred.len..], " ");
            const ty = typeToken(rest2);
            rest2 = std.mem.trim(u8, rest2[ty.len..], " ");
            try self.emitIcmpExpr(pred, ty, rest2);
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (startsWithAny(rhs, &.{ "trunc ", "zext ", "sext ", "fptosi ", "fptoui ", "sitofp ", "uitofp ", "fpext ", "fptrunc ", "inttoptr ", "ptrtoint ", "bitcast " })) {
            const res = result orelse return error.NoResult;
            const sp = std.mem.indexOfScalar(u8, rhs, ' ') orelse return error.BadCast;
            const opname = rhs[0..sp];
            var rest = std.mem.trim(u8, rhs[sp + 1 ..], " ");
            const src_ty = typeToken(rest);
            rest = std.mem.trim(u8, rest[src_ty.len..], " ");
            const to_idx = std.mem.lastIndexOf(u8, rest, " to ") orelse return error.BadCast;
            const value = std.mem.trim(u8, rest[0..to_idx], " ");
            const dst_ty = typeToken(rest[to_idx + 4 ..]);
            const float_cast = std.mem.eql(u8, opname, "fptosi") or std.mem.eql(u8, opname, "fptoui") or std.mem.eql(u8, opname, "fptrunc") or std.mem.eql(u8, opname, "fpext");
            if (std.mem.eql(u8, src_ty, "x86_fp80") or std.mem.eql(u8, src_ty, "fp128")) {
                try self.emitOperand(value);
            } else if (float_cast) {
                try self.emitFloatOperand(value, src_ty);
            } else {
                try self.emitOperand(value);
            }
            if (std.mem.eql(u8, opname, "inttoptr")) {
                // pointer bits are already in the operand
            } else if (std.mem.eql(u8, opname, "ptrtoint")) {
                if (dst_ty.len > 1 and dst_ty[0] == 'i') {
                    const bits = std.fmt.parseInt(u32, dst_ty[1..], 10) catch 64;
                    if (bits < 64) {
                        try self.emitConst(@intCast((@as(u64, 1) << @intCast(bits)) - 1));
                        try self.emitU8(op.OP_AND);
                    }
                }
            } else if (std.mem.eql(u8, opname, "bitcast")) {
                // no-op
            } else if (std.mem.eql(u8, opname, "fptosi")) {
                if (std.mem.eql(u8, src_ty, "x86_fp80")) try self.emitU8(op.OP_F80_TO_I64) else if (std.mem.eql(u8, src_ty, "fp128")) try self.emitU8(op.OP_F128_TO_I64) else try self.emitU8(if (std.mem.eql(u8, src_ty, "float")) op.OP_FPTOSI32 else op.OP_FPTOSI);
                const bits = if (dst_ty.len > 1 and dst_ty[0] == 'i') std.fmt.parseInt(u32, dst_ty[1..], 10) catch 64 else 64;
                if (bits < 64) try self.normalizeInt(bits, true);
            } else if (std.mem.eql(u8, opname, "fptoui")) {
                if (std.mem.eql(u8, src_ty, "x86_fp80")) try self.emitU8(op.OP_F80_TO_U64) else if (std.mem.eql(u8, src_ty, "fp128")) try self.emitU8(op.OP_F128_TO_U64) else try self.emitU8(if (std.mem.eql(u8, src_ty, "float")) op.OP_FPTOUI32 else op.OP_FPTOUI);
                if (dst_ty.len > 1 and dst_ty[0] == 'i') {
                    const bits = std.fmt.parseInt(u32, dst_ty[1..], 10) catch 64;
                    if (bits < 64) try self.normalizeInt(bits, true);
                }
            } else if (std.mem.eql(u8, opname, "sitofp")) {
                if (std.mem.eql(u8, dst_ty, "x86_fp80")) try self.emitU8(op.OP_F80_FROM_I64) else if (std.mem.eql(u8, dst_ty, "fp128")) try self.emitU8(op.OP_F128_FROM_I64) else try self.emitU8(if (std.mem.eql(u8, dst_ty, "float")) op.OP_SITOFP32 else op.OP_SITOFP);
            } else if (std.mem.eql(u8, opname, "uitofp")) {
                if (src_ty.len > 1 and src_ty[0] == 'i') {
                    const bits = std.fmt.parseInt(u32, src_ty[1..], 10) catch 64;
                    if (bits < 64) {
                        try self.emitConst(@intCast((@as(u64, 1) << @intCast(bits)) - 1));
                        try self.emitU8(op.OP_AND);
                    }
                }
                if (std.mem.eql(u8, dst_ty, "x86_fp80")) try self.emitU8(op.OP_F80_FROM_U64) else if (std.mem.eql(u8, dst_ty, "fp128")) try self.emitU8(op.OP_F128_FROM_U64) else try self.emitU8(if (std.mem.eql(u8, dst_ty, "float")) op.OP_UITOFP32 else op.OP_UITOFP);
            } else if (std.mem.eql(u8, opname, "fpext")) {
                if (std.mem.eql(u8, src_ty, "float") and std.mem.eql(u8, dst_ty, "double")) try self.emitU8(op.OP_FPEXT) else if (std.mem.eql(u8, src_ty, "float") and std.mem.eql(u8, dst_ty, "x86_fp80")) try self.emitU8(op.OP_F80_FROM_F32) else if (std.mem.eql(u8, src_ty, "double") and std.mem.eql(u8, dst_ty, "x86_fp80")) try self.emitU8(op.OP_F80_FROM_F64) else if (std.mem.eql(u8, src_ty, "float") and std.mem.eql(u8, dst_ty, "fp128")) try self.emitU8(op.OP_F128_FROM_F32) else if (std.mem.eql(u8, src_ty, "double") and std.mem.eql(u8, dst_ty, "fp128")) try self.emitU8(op.OP_F128_FROM_F64) else return error.BadCast;
            } else if (std.mem.eql(u8, opname, "fptrunc")) {
                if (std.mem.eql(u8, src_ty, "double") and std.mem.eql(u8, dst_ty, "float")) try self.emitU8(op.OP_FPTRUNC) else if (std.mem.eql(u8, src_ty, "x86_fp80") and std.mem.eql(u8, dst_ty, "float")) try self.emitU8(op.OP_F80_TO_F32) else if (std.mem.eql(u8, src_ty, "x86_fp80") and std.mem.eql(u8, dst_ty, "double")) try self.emitU8(op.OP_F80_TO_F64) else if (std.mem.eql(u8, src_ty, "fp128") and std.mem.eql(u8, dst_ty, "float")) try self.emitU8(op.OP_F128_TO_F32) else if (std.mem.eql(u8, src_ty, "fp128") and std.mem.eql(u8, dst_ty, "double")) try self.emitU8(op.OP_F128_TO_F64) else return error.BadCast;
            } else if (std.mem.eql(u8, opname, "trunc")) {
                const bits = if (dst_ty.len > 1 and dst_ty[0] == 'i') std.fmt.parseInt(u32, dst_ty[1..], 10) catch 64 else 64;
                try self.normalizeInt(bits, true);
            } else if (std.mem.eql(u8, opname, "zext")) {
                const src_bits = if (src_ty.len > 1 and src_ty[0] == 'i') std.fmt.parseInt(u32, src_ty[1..], 10) catch 64 else 64;
                if (src_bits < 64) {
                    try self.emitConst(@intCast((@as(u64, 1) << @intCast(src_bits)) - 1));
                    try self.emitU8(op.OP_AND);
                }
                const dst_bits = if (dst_ty.len > 1 and dst_ty[0] == 'i') std.fmt.parseInt(u32, dst_ty[1..], 10) catch 64 else 64;
                try self.normalizeInt(dst_bits, true);
            } else if (std.mem.eql(u8, opname, "sext")) {
                const src_bits = if (src_ty.len > 1 and src_ty[0] == 'i') std.fmt.parseInt(u32, src_ty[1..], 10) catch 64 else 64;
                if (src_bits < 64) {
                    try self.emitConst(@intCast(64 - src_bits));
                    try self.emitU8(op.OP_SHL);
                    try self.emitConst(@intCast(64 - src_bits));
                    try self.emitU8(op.OP_SHR_S);
                }
                const dst_bits = if (dst_ty.len > 1 and dst_ty[0] == 'i') std.fmt.parseInt(u32, dst_ty[1..], 10) catch 64 else 64;
                try self.normalizeInt(dst_bits, true);
            } else return error.BadCast;
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "add ") or std.mem.startsWith(u8, rhs, "sub ") or std.mem.startsWith(u8, rhs, "mul ") or std.mem.startsWith(u8, rhs, "sdiv ") or std.mem.startsWith(u8, rhs, "udiv ") or std.mem.startsWith(u8, rhs, "srem ") or std.mem.startsWith(u8, rhs, "urem ") or std.mem.startsWith(u8, rhs, "and ") or std.mem.startsWith(u8, rhs, "or ") or std.mem.startsWith(u8, rhs, "xor ") or std.mem.startsWith(u8, rhs, "shl ") or std.mem.startsWith(u8, rhs, "lshr ") or std.mem.startsWith(u8, rhs, "ashr ")) {
            const res = result orelse return error.NoResult;
            const sp = std.mem.indexOfScalar(u8, rhs, ' ') orelse return error.BadArith;
            const opname = rhs[0..sp];
            var rest = std.mem.trim(u8, rhs[sp + 1 ..], " ");
            if (std.mem.startsWith(u8, rest, "nsw ")) rest = rest[4..];
            if (std.mem.startsWith(u8, rest, "nuw ")) rest = rest[4..];
            if (std.mem.startsWith(u8, rest, "exact ")) rest = rest[6..];
            const ty = typeToken(rest);
            const bits: u32 = if (ty.len > 0 and ty[0] == 'i') std.fmt.parseInt(u32, ty[1..], 10) catch 64 else 64;
            rest = std.mem.trim(u8, rest[ty.len..], " ");
            const args = try splitTop(self.allocator, rest, ',');
            if (args.len != 2) return error.BadArith;
            const a = args[0];
            const b = args[1];
            if ((std.mem.eql(u8, opname, "udiv") or std.mem.eql(u8, opname, "urem")) and bits < 64) {
                const mask: i64 = @intCast((@as(u64, 1) << @intCast(bits)) - 1);
                try self.emitOperand(a);
                try self.emitConst(mask);
                try self.emitU8(op.OP_AND);
                try self.emitOperand(b);
                try self.emitConst(mask);
                try self.emitU8(op.OP_AND);
                try self.emitU8(if (std.mem.eql(u8, opname, "udiv")) op.OP_DIV_U else op.OP_REM_U);
                try self.normalizeInt(bits, true);
            } else if (std.mem.eql(u8, opname, "lshr") and bits < 64) {
                const mask: i64 = @intCast((@as(u64, 1) << @intCast(bits)) - 1);
                try self.emitOperand(a);
                try self.emitConst(mask);
                try self.emitU8(op.OP_AND);
                try self.emitOperand(b);
                try self.emitU8(op.OP_SHR_U);
                try self.normalizeInt(bits, true);
            } else if (std.mem.eql(u8, opname, "ashr") and bits < 64) {
                try self.emitOperand(a);
                try self.emitConst(64 - bits);
                try self.emitU8(op.OP_SHL);
                try self.emitConst(64 - bits);
                try self.emitU8(op.OP_SHR_S);
                try self.emitOperand(b);
                try self.emitU8(op.OP_SHR_S);
                try self.normalizeInt(bits, true);
            } else {
                try self.emitOperand(a);
                try self.emitOperand(b);
                const opcode: u8 = if (std.mem.eql(u8, opname, "add")) op.OP_ADD else if (std.mem.eql(u8, opname, "sub")) op.OP_SUB else if (std.mem.eql(u8, opname, "mul")) op.OP_MUL else if (std.mem.eql(u8, opname, "sdiv")) op.OP_DIV_S else if (std.mem.eql(u8, opname, "udiv")) op.OP_DIV_U else if (std.mem.eql(u8, opname, "srem")) op.OP_REM_S else if (std.mem.eql(u8, opname, "urem")) op.OP_REM_U else if (std.mem.eql(u8, opname, "and")) op.OP_AND else if (std.mem.eql(u8, opname, "or")) op.OP_OR else if (std.mem.eql(u8, opname, "xor")) op.OP_XOR else if (std.mem.eql(u8, opname, "shl")) op.OP_SHL else if (std.mem.eql(u8, opname, "lshr")) op.OP_SHR_U else op.OP_SHR_S;
                try self.emitU8(opcode);
                try self.normalizeInt(bits, true);
            }
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "getelementptr ")) {
            const res = result orelse return error.NoResult;
            try self.emitGep(rhs);
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "br ")) {
            const rest = std.mem.trim(u8, rhs[3..], " ");
            if (std.mem.startsWith(u8, rest, "label %")) {
                try self.jump(op.OP_JMP, std.mem.trim(u8, rest[7..], " "));
                return;
            }
            if (std.mem.startsWith(u8, rest, "i1 ")) {
                var cond = std.mem.trim(u8, rest[3..], " ");
                const comma = std.mem.indexOfScalar(u8, cond, ',') orelse return error.BadBr;
                const cond_val = std.mem.trim(u8, cond[0..comma], " ");
                var labels = std.mem.trim(u8, cond[comma + 1 ..], " ");
                if (std.mem.startsWith(u8, labels, "label %")) labels = labels[7..];
                const comma2 = std.mem.indexOfScalar(u8, labels, ',') orelse return error.BadBr;
                const true_label = std.mem.trim(u8, labels[0..comma2], " ");
                var false_label = std.mem.trim(u8, labels[comma2 + 1 ..], " ");
                if (std.mem.startsWith(u8, false_label, "label %")) false_label = false_label[7..];
                if (std.mem.eql(u8, cond_val, "true")) {
                    try self.jump(op.OP_JMP, true_label);
                } else if (std.mem.eql(u8, cond_val, "false")) {
                    try self.jump(op.OP_JMP, false_label);
                } else {
                    try self.emitOperand(cond_val);
                    try self.jump(op.OP_JNZ, true_label);
                    try self.jump(op.OP_JMP, false_label);
                }
                return;
            }
            return error.BadBr;
        }
        if (std.mem.eql(u8, rhs, "ret void")) {
            try self.emitU8(op.OP_RET_VOID);
            return;
        }
        if (std.mem.startsWith(u8, rhs, "ret ")) {
            const rest = std.mem.trim(u8, rhs[4..], " ");
            const ty = typeToken(rest);
            const val = std.mem.trim(u8, rest[ty.len..], " ");
            if (std.mem.eql(u8, ty, "float") or std.mem.eql(u8, ty, "double")) {
                try self.emitFloatOperand(val, ty);
            } else if (ty.len > 1 and ty[0] == 'i') {
                const bits = std.fmt.parseInt(u32, ty[1..], 10) catch 64;
                try self.emitIntOperand(val, bits, true);
            } else try self.emitOperand(val);
            try self.emitU8(op.OP_RET);
            return;
        }
        if (std.mem.startsWith(u8, rhs, "select ")) {
            const res = result orelse return error.NoResult;
            const parts = try splitTop(self.allocator, rhs[7..], ',');
            if (parts.len != 3) return error.BadSelect;
            const n = self.select_id;
            self.select_id += 1;
            const else_label = try std.fmt.allocPrint(self.allocator, "__select_else_{d}", .{n});
            const end_label = try std.fmt.allocPrint(self.allocator, "__select_end_{d}", .{n});
            try self.emitOperand(parts[0]);
            try self.jump(op.OP_JZ, else_label);
            try self.emitOperand(parts[1]);
            try self.jump(op.OP_JMP, end_label);
            try self.labels.put(else_label, @intCast(self.func.code.items.len));
            try self.emitOperand(parts[2]);
            try self.labels.put(end_label, @intCast(self.func.code.items.len));
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "extractvalue ")) {
            const res = result orelse return error.NoResult;
            const rest = std.mem.trim(u8, rhs[13..], " ");
            const comma = std.mem.lastIndexOfScalar(u8, rest, ',') orelse return error.BadExtract;
            const agg_part = std.mem.trim(u8, rest[0..comma], " ");
            const idx_text = std.mem.trim(u8, rest[comma + 1 ..], " ");
            const ty = typeToken(agg_part);
            const val = std.mem.trim(u8, agg_part[ty.len..], " ");
            const fields = (try structFields(self.allocator, ty, self.structs)) orelse return error.BadExtract;
            const idx = std.fmt.parseInt(usize, idx_text, 10) catch return error.BadExtract;
            if (idx >= fields.len) return error.BadExtract;
            const layout = try structLayout(self.allocator, ty, self.structs, self.ptr_size);
            try self.emitPointer(val);
            if (layout.offsets[idx] != 0) {
                try self.emitConst(layout.offsets[idx]);
                try self.emitU8(op.OP_ADD);
            }
            try self.emitU8(op.OP_LOAD_MEM);
            try self.emitU8(@intCast(try self.typeStoreSize(fields[idx])));
            try self.emitStoreSlot(try self.slotFor(res));
            return;
        }
        if (std.mem.startsWith(u8, rhs, "call ") or std.mem.startsWith(u8, rhs, "tail call ")) {
            try self.lowerCall(rhs, result);
            return;
        }
        if (std.mem.eql(u8, rhs, "unreachable")) {
            try self.emitU8(op.OP_RET_VOID);
            return;
        }
        std.debug.print("unsupported instruction: {s}\n", .{line});
        return error.UnsupportedInstruction;
    }
    fn emitCallback(self: *Lowerer, key: []const u8, func_index: u16) anyerror!void {
        if (self.callbacks.by_func.get(key)) |entry| {
            try self.emitU8(op.OP_CREATE_CALLBACK);
            try self.emitU16(entry.slot);
            try self.emitU16(entry.func_index);
            try self.emitU16(entry.plan_index);
            return;
        }
        const callback_fn = self.functions[func_index];
        var byval_sizes = try self.allocator.alloc(u16, callback_fn.param_attrs.len);
        @memset(byval_sizes, 0);
        var sret_idx: ?usize = null;
        var sret_size: u16 = 0;
        for (callback_fn.param_attrs, 0..) |raw, param_index| {
            if (std.mem.indexOf(u8, raw, "byval(")) |bi| {
                const bopen = std.mem.indexOfScalarPos(u8, raw, bi, '(') orelse continue;
                const bclose = std.mem.indexOfScalarPos(u8, raw, bopen, ')') orelse continue;
                const agg_ty = std.mem.trim(u8, raw[bopen + 1 .. bclose], " ");
                byval_sizes[param_index] = @intCast(try self.typeSize(agg_ty));
            }
            if (std.mem.indexOf(u8, raw, "sret(")) |si| {
                const sopen = std.mem.indexOfScalarPos(u8, raw, si, '(') orelse continue;
                const sclose = std.mem.indexOfScalarPos(u8, raw, sopen, ')') orelse continue;
                const agg_ty = std.mem.trim(u8, raw[sopen + 1 .. sclose], " ");
                sret_idx = param_index;
                sret_size = @intCast(try self.typeSize(agg_ty));
            }
        }
        const plan_ret = if (sret_idx != null) "void" else callback_fn.ret;
        const plan_name = try std.fmt.allocPrint(self.allocator, "callback:{s}", .{key});
        const plan = try buildPlanForAbi(self.allocator, self.abi, plan_name, plan_ret, callback_fn.param_types, false, sret_idx, sret_size, byval_sizes, self.ptr_size);
        const plan_index: u16 = @intCast(self.plans.items.len);
        try self.plans.append(plan);
        const slot = self.callbacks.next_slot;
        self.callbacks.next_slot += 1;
        try self.callbacks.by_func.put(key, .{ .slot = slot, .func_index = func_index, .plan_index = plan_index });
        try self.emitU8(op.OP_CREATE_CALLBACK);
        try self.emitU16(slot);
        try self.emitU16(func_index);
        try self.emitU16(plan_index);
    }
    fn lowerCall(self: *Lowerer, rhs_in: []const u8, result: ?[]const u8) anyerror!void {
        var rhs = rhs_in;
        if (std.mem.startsWith(u8, rhs, "tail ")) rhs = rhs[5..];
        if (!std.mem.startsWith(u8, rhs, "call ")) return error.BadCall;
        rhs = std.mem.trim(u8, rhs[5..], " ");
        if (std.mem.startsWith(u8, rhs, "void @llvm.lifetime") or std.mem.startsWith(u8, rhs, "void @llvm.dbg")) return;
        if (std.mem.indexOf(u8, rhs, " null()") != null or std.mem.endsWith(u8, rhs, "null()")) return;
        const call_open = findCallOpen(rhs) orelse return error.BadCall;
        const call_close = std.mem.lastIndexOfScalar(u8, rhs, ')') orelse return error.BadCall;
        const call_head = std.mem.trim(u8, rhs[0..call_open], " ");
        const head_sp = std.mem.lastIndexOfScalar(u8, call_head, ' ') orelse return error.BadCall;
        const callee_token = std.mem.trim(u8, call_head[head_sp + 1 ..], " ");
        if (std.mem.eql(u8, callee_token, "null")) return;
        if (std.mem.indexOf(u8, rhs, "@llvm.memcpy.") != null or std.mem.indexOf(u8, rhs, "@llvm.memset.") != null) {
            const kind = if (std.mem.indexOf(u8, rhs, "@llvm.memcpy.") != null) "memcpy" else "memset";
            const open = std.mem.indexOfScalar(u8, rhs, '(') orelse return error.BadCall;
            const close = std.mem.lastIndexOfScalar(u8, rhs, ')') orelse return error.BadCall;
            const args = try splitTop(self.allocator, rhs[open + 1 .. close], ',');
            if (args.len < 3) return error.BadCall;
            try self.emitPointer(args[0]);
            if (std.mem.eql(u8, kind, "memcpy")) {
                try self.emitPointer(args[1]);
                try self.emitOperand(typeValue(args[2]));
                try self.emitU8(op.OP_MEMCPY);
            } else {
                try self.emitOperand(typeValue(args[1]));
                try self.emitOperand(typeValue(args[2]));
                try self.emitU8(op.OP_MEMSET);
            }
            return;
        }
        // Indirect call: `call <ret> %fn(args)`. TCC/clang emits this for
        // function pointers; the runtime dispatches VM labels or native code.
        if (callee_token.len > 0 and callee_token[0] == '%') {
            const open = call_open;
            const close = call_close;
            const ret_part = stripLeadingAttrs(std.mem.trim(u8, call_head[0..head_sp], " "));
            const fn_token = callee_token;
            if (fn_token.len < 2 or fn_token[0] != '%') return error.BadCall;
            const fn_name = fn_token[1..];
            var ret_ty = typeToken(ret_part);
            if (std.mem.indexOf(u8, ret_part, "...") != null) {
                if (std.mem.indexOfScalar(u8, ret_part, '(')) |lp| ret_ty = typeToken(std.mem.trim(u8, ret_part[0..lp], " "));
            }
            const args_text = rhs[open + 1 .. close];
            const raw_args = if (std.mem.trim(u8, args_text, " ").len > 0) try splitTop(self.allocator, args_text, ',') else &[_][]const u8{};
            var types = std.ArrayList([]const u8).init(self.allocator);
            var values = std.ArrayList([]const u8).init(self.allocator);
            var byval_sizes = try self.allocator.alloc(u16, raw_args.len);
            @memset(byval_sizes, 0);
            var sret_idx: ?usize = null;
            var sret_size: u16 = 0;
            for (raw_args, 0..) |arg, arg_index| {
                try types.append(typeToken(arg));
                try values.append(typeValue(arg));
                if (std.mem.indexOf(u8, arg, "byval(")) |bi| {
                    const bo = std.mem.indexOfScalarPos(u8, arg, bi, '(') orelse continue;
                    const bc = std.mem.indexOfScalarPos(u8, arg, bo, ')') orelse continue;
                    byval_sizes[arg_index] = @intCast(try self.typeSize(std.mem.trim(u8, arg[bo + 1 .. bc], " ")));
                }
                if (std.mem.indexOf(u8, arg, "sret(")) |si| {
                    const so = std.mem.indexOfScalarPos(u8, arg, si, '(') orelse continue;
                    const sc = std.mem.indexOfScalarPos(u8, arg, so, ')') orelse continue;
                    sret_idx = arg_index;
                    sret_size = @intCast(try self.typeSize(std.mem.trim(u8, arg[so + 1 .. sc], " ")));
                }
            }
            for (types.items, values.items) |ty, value| {
                if (std.mem.eql(u8, ty, "float") or std.mem.eql(u8, ty, "double")) {
                    try self.emitFloatOperand(value, ty);
                } else try self.emitOperand(value);
            }
            try self.emitOperand(try std.fmt.allocPrint(self.allocator, "%{s}", .{fn_name}));
            const plan_ret = if (sret_idx != null) "void" else ret_ty;
            const plan = try buildPlanForAbi(self.allocator, self.abi, "indirect", plan_ret, types.items, std.mem.indexOf(u8, ret_part, "...") != null, sret_idx, sret_size, byval_sizes, self.ptr_size);
            const plan_index: u16 = @intCast(self.plans.items.len);
            try self.plans.append(plan);
            try self.emitU8(op.OP_CALL_INDIRECT_NATIVE);
            try self.emitU16(plan_index);
            if (!std.mem.eql(u8, ret_ty, "void")) {
                const res = result orelse return error.NoResult;
                const slot = try self.slotFor(res);
                try self.emitStoreSlot(slot);
                if (ret_ty.len > 1 and ret_ty[0] == 'i' and !std.mem.eql(u8, ret_ty, "i64")) {
                    const bits = std.fmt.parseInt(u32, ret_ty[1..], 10) catch 64;
                    if (bits < 64) {
                        try self.emitLoadSlot(slot);
                        try self.emitConst(64 - bits);
                        try self.emitU8(op.OP_SHL);
                        try self.emitConst(64 - bits);
                        try self.emitU8(op.OP_SHR_S);
                        try self.emitStoreSlot(slot);
                    }
                }
            }
            return;
        }
        // Find the callee @name.
        const at = std.mem.indexOfScalar(u8, rhs, '@') orelse return error.BadCall;
        var name_end = at + 1;
        if (name_end < rhs.len and rhs[name_end] == '"') {
            name_end += 1;
            while (name_end < rhs.len and rhs[name_end] != '"') name_end += 1;
            name_end += 1;
        } else {
            while (name_end < rhs.len and (std.ascii.isAlphanumeric(rhs[name_end]) or rhs[name_end] == '_' or rhs[name_end] == '.' or rhs[name_end] == '$' or rhs[name_end] == '-')) name_end += 1;
        }
        const name_raw = normalizeName(rhs[at + 1 .. name_end]);
        var name = name_raw;
        if (std.mem.startsWith(u8, name, "llvm.fmuladd.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "fmaf" else if (std.mem.endsWith(u8, name, ".f64")) "fma" else "fmal";
        } else if (std.mem.startsWith(u8, name, "llvm.fabs.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "fabsf" else if (std.mem.endsWith(u8, name, ".f64")) "fabs" else "fabsl";
        } else if (std.mem.startsWith(u8, name, "llvm.sqrt.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "sqrtf" else if (std.mem.endsWith(u8, name, ".f64")) "sqrt" else "sqrtl";
        } else if (std.mem.startsWith(u8, name, "llvm.round.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "roundf" else "round";
        } else if (std.mem.startsWith(u8, name, "llvm.ceil.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "ceilf" else "ceil";
        } else if (std.mem.startsWith(u8, name, "llvm.floor.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "floorf" else "floor";
        } else if (std.mem.startsWith(u8, name, "llvm.trunc.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "truncf" else "trunc";
        } else if (std.mem.startsWith(u8, name, "llvm.nearbyint.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "nearbyintf" else "nearbyint";
        } else if (std.mem.startsWith(u8, name, "llvm.rint.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "rintf" else "rint";
        } else if (std.mem.startsWith(u8, name, "llvm.sin.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "sinf" else "sin";
        } else if (std.mem.startsWith(u8, name, "llvm.cos.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "cosf" else "cos";
        } else if (std.mem.startsWith(u8, name, "llvm.exp2.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "exp2f" else "exp2";
        } else if (std.mem.startsWith(u8, name, "llvm.log2.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "log2f" else "log2";
        } else if (std.mem.startsWith(u8, name, "llvm.pow.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "powf" else "pow";
        } else if (std.mem.startsWith(u8, name, "llvm.fmin.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "fminf" else "fmin";
        } else if (std.mem.startsWith(u8, name, "llvm.fmax.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "fmaxf" else "fmax";
        } else if (std.mem.startsWith(u8, name, "llvm.copysign.")) {
            name = if (std.mem.endsWith(u8, name, ".f32")) "copysignf" else if (std.mem.endsWith(u8, name, ".f80") or std.mem.endsWith(u8, name, ".f128")) "copysignl" else "copysign";
        }
        const open = std.mem.indexOfScalarPos(u8, rhs, name_end, '(') orelse {
            std.debug.print("bad direct call: {s}\n", .{rhs});
            return error.BadCall;
        };
        const close = std.mem.lastIndexOfScalar(u8, rhs, ')') orelse return error.BadCall;
        const args_text = rhs[open + 1 .. close];
        const ret_part_raw = std.mem.trim(u8, rhs[0..at], " ");
        const ret_part = stripLeadingAttrs(ret_part_raw);
        var ret_ty = typeToken(ret_part);
        if (std.mem.indexOf(u8, ret_part, "(")) |lp| ret_ty = typeToken(ret_part[0..lp]);
        const is_varargs = std.mem.indexOf(u8, ret_part, "...") != null or (self.decls.get(name) orelse Decl{ .ret = "void", .params = &.{}, .is_varargs = false }).is_varargs;
        const raw_args = if (std.mem.trim(u8, args_text, " ").len > 0) try splitTop(self.allocator, args_text, ',') else &[_][]const u8{};
        if (std.mem.startsWith(u8, name, "llvm.frameaddress.")) {
            try self.emitConst(0);
            if (result) |r| try self.emitStoreSlot(try self.slotFor(r));
            return;
        }
        if (std.mem.eql(u8, name, "__intrinsic_setjmpex") or std.mem.eql(u8, name, "__intrinsic_setjmp")) {
            if (raw_args.len < 1 or result == null) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitU8(op.OP_SETJMP);
            try self.emitU16(try self.slotFor(result.?));
            return;
        }
        if (std.mem.eql(u8, name, "setjmp") or std.mem.eql(u8, name, "_setjmp") or std.mem.eql(u8, name, "_setjmp3") or std.mem.eql(u8, name, "__builtin_setjmp")) {
            if (raw_args.len < 1 or result == null) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitU8(op.OP_SETJMP);
            try self.emitU16(try self.slotFor(result.?));
            return;
        }
        if (std.mem.eql(u8, name, "longjmp") or std.mem.eql(u8, name, "_longjmp") or std.mem.eql(u8, name, "__builtin_longjmp")) {
            if (raw_args.len < 2) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitOperand(typeValue(raw_args[1]));
            try self.emitU8(op.OP_LONGJMP);
            return;
        }
        if (std.mem.startsWith(u8, name, "llvm.is.fpclass.")) {
            const kind: u8 = if (std.mem.endsWith(u8, name, ".f32")) 0 else if (std.mem.endsWith(u8, name, ".f64")) 1 else if (std.mem.endsWith(u8, name, ".f80")) 2 else if (std.mem.endsWith(u8, name, ".f128")) 3 else return error.UnsupportedFfi;
            if (raw_args.len < 2 or result == null) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitOperand(typeValue(raw_args[1]));
            try self.emitU8(op.OP_FPCLASS);
            try self.emitU8(kind);
            try self.emitStoreSlot(try self.slotFor(result.?));
            return;
        }
        if (std.mem.startsWith(u8, name, "llvm.ptrmask.")) {
            if (raw_args.len < 2) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitOperand(typeValue(raw_args[1]));
            try self.emitU8(op.OP_AND);
            if (result) |r| try self.emitStoreSlot(try self.slotFor(r));
            return;
        }
        if (std.mem.eql(u8, name, "llvm.va_start.p0") or std.mem.eql(u8, name, "llvm.va_start")) {
            if (raw_args.len < 1) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitU8(op.OP_VA_START);
            return;
        }
        if (std.mem.eql(u8, name, "llvm.va_copy.p0") or std.mem.eql(u8, name, "llvm.va_copy") or std.mem.eql(u8, name, "__va_copy")) {
            if (raw_args.len < 2) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitOperand(typeValue(raw_args[1]));
            try self.emitU8(op.OP_VA_COPY);
            return;
        }
        if (std.mem.eql(u8, name, "llvm.va_end.p0") or std.mem.eql(u8, name, "llvm.va_end")) return;
        if (std.mem.eql(u8, name, "llvm.stacksave.p0") or std.mem.eql(u8, name, "llvm.stacksave")) {
            try self.emitU8(op.OP_STACKSAVE);
            if (result) |r| try self.emitStoreSlot(try self.slotFor(r));
            return;
        }
        if (std.mem.eql(u8, name, "llvm.stackrestore.p0") or std.mem.eql(u8, name, "llvm.stackrestore")) {
            if (raw_args.len < 1) return error.BadCall;
            try self.emitOperand(typeValue(raw_args[0]));
            try self.emitU8(op.OP_STACKRESTORE);
            return;
        }
        if (self.func_indices.get(name)) |idx| {
            var need_copy = false;
            for (raw_args) |arg| {
                const ty = typeToken(arg);
                const value = typeValue(arg);
                if ((std.mem.eql(u8, ty, "x86_fp80") or std.mem.eql(u8, ty, "fp128")) and value.len > 0 and value[0] == '%') {
                    need_copy = true;
                    break;
                }
            }
            var save_slot: ?u16 = null;
            if (need_copy) {
                try self.emitU8(op.OP_STACKSAVE);
                save_slot = try self.slotFor(try std.fmt.allocPrint(self.allocator, "__f80save_{d}", .{self.func.code.items.len}));
                try self.emitStoreSlot(save_slot.?);
            }
            for (raw_args) |arg| {
                const ty = typeToken(arg);
                const value = typeValue(arg);
                if ((std.mem.eql(u8, ty, "x86_fp80") or std.mem.eql(u8, ty, "fp128")) and value.len > 0 and value[0] == '%') {
                    try self.emitU8(op.OP_ALLOCA);
                    try self.emitU16(16);
                    try self.emitU8(op.OP_DUP);
                    try self.emitOperand(value);
                    try self.emitConst(16);
                    try self.emitU8(op.OP_MEMCPY);
                } else if (std.mem.eql(u8, ty, "float") or std.mem.eql(u8, ty, "double")) {
                    try self.emitFloatOperand(value, ty);
                } else try self.emitOperand(value);
            }
            const callee = self.functions[idx];
            if (callee.is_varargs) {
                try self.emitU8(op.OP_CALL_VARIADIC_TYPED);
                try self.emitU16(idx);
                try self.emitU16(@intCast(raw_args.len));
                var vi: usize = callee.param_count;
                while (vi < raw_args.len) : (vi += 1) {
                    const ty = typeToken(raw_args[vi]);
                    if (std.mem.indexOf(u8, raw_args[vi], "byval(")) |bi| {
                        const bo = std.mem.indexOfScalarPos(u8, raw_args[vi], bi, '(') orelse continue;
                        const bc = std.mem.indexOfScalarPos(u8, raw_args[vi], bo, ')') orelse continue;
                        try self.emitU8(3);
                        try self.emitU16(@intCast(try self.typeSize(std.mem.trim(u8, raw_args[vi][bo + 1 .. bc], " "))));
                    } else if (std.mem.eql(u8, ty, "x86_fp80")) {
                        try self.emitU8(1);
                    } else if (std.mem.eql(u8, ty, "fp128")) {
                        try self.emitU8(2);
                    } else if (ty.len > 0 and (ty[0] == '%' or ty[0] == '[' or ty[0] == '{' or ty[0] == '<')) {
                        try self.emitU8(3);
                        try self.emitU16(@intCast(try self.typeSize(ty)));
                    } else {
                        try self.emitU8(0);
                    }
                }
            } else {
                try self.emitU8(op.OP_CALL);
                try self.emitU16(idx);
            }
            if (!std.mem.eql(u8, ret_ty, "void")) {
                const res = result orelse return error.NoResult;
                try self.emitStoreSlot(try self.slotFor(res));
            }
            if (save_slot) |ss| {
                try self.emitLoadSlot(ss);
                try self.emitU8(op.OP_STACKRESTORE);
            }
            return;
        }
        var types = std.ArrayList([]const u8).init(self.allocator);
        var values = std.ArrayList([]const u8).init(self.allocator);
        var byval_sizes = try self.allocator.alloc(u16, raw_args.len);
        @memset(byval_sizes, 0);
        var sret_idx: ?usize = null;
        var sret_size: u16 = 0;
        for (raw_args, 0..) |arg, arg_index| {
            try types.append(typeToken(arg));
            try values.append(typeValue(arg));
            if (std.mem.indexOf(u8, arg, "byval(")) |bi| {
                const byval_open = std.mem.indexOfScalarPos(u8, arg, bi, '(') orelse continue;
                const byval_close = std.mem.indexOfScalarPos(u8, arg, byval_open, ')') orelse continue;
                const agg_ty = std.mem.trim(u8, arg[byval_open + 1 .. byval_close], " ");
                byval_sizes[arg_index] = @intCast(try self.typeSize(agg_ty));
            }
            if (std.mem.indexOf(u8, arg, "sret(")) |si| {
                const sret_open = std.mem.indexOfScalarPos(u8, arg, si, '(') orelse continue;
                const sret_close = std.mem.indexOfScalarPos(u8, arg, sret_open, ')') orelse continue;
                const agg_ty = std.mem.trim(u8, arg[sret_open + 1 .. sret_close], " ");
                sret_idx = arg_index;
                sret_size = @intCast(try self.typeSize(agg_ty));
            }
        }
        const plan_ret = if (sret_idx != null) "void" else ret_ty;
        var call_name = name;
        if (std.mem.eql(u8, call_name, "atexit")) {
            call_name = "__cxa_atexit";
            try types.append("ptr");
            try values.append("null");
            try types.append("ptr");
            try values.append("null");
        }
        const plan = try buildPlanForAbi(self.allocator, self.abi, call_name, plan_ret, types.items, is_varargs, sret_idx, sret_size, byval_sizes, self.ptr_size);
        const plan_index = self.plans.items.len;
        try self.plans.append(plan);
        for (types.items, values.items) |ty, value| {
            if (value.len > 1 and value[0] == '@') {
                if (self.func_indices.get(value[1..])) |idx| {
                    try self.emitCallback(value[1..], idx);
                    continue;
                }
            }
            if (std.mem.eql(u8, ty, "float") or std.mem.eql(u8, ty, "double")) {
                try self.emitFloatOperand(value, ty);
            } else try self.emitOperand(value);
        }
        try self.emitU8(if (is_varargs) op.OP_CALL_VARARG else op.OP_CALL_NATIVE);
        try self.emitU16(@intCast(plan_index));
        if (!std.mem.eql(u8, ret_ty, "void")) {
            const res = result orelse return error.NoResult;
            const slot = try self.slotFor(res);
            try self.emitStoreSlot(slot);
            if (ret_ty.len > 1 and ret_ty[0] == 'i' and !std.mem.eql(u8, ret_ty, "i64") and !std.mem.eql(u8, ret_ty, "i128")) {
                const bits = std.fmt.parseInt(u32, ret_ty[1..], 10) catch 64;
                if (bits < 64) {
                    try self.emitLoadSlot(slot);
                    try self.emitConst(64 - bits);
                    try self.emitU8(op.OP_SHL);
                    try self.emitConst(64 - bits);
                    try self.emitU8(op.OP_SHR_S);
                    try self.emitStoreSlot(slot);
                }
            }
        }
    }
};

fn stripLeadingAttrs(text_in: []const u8) []const u8 {
    var text = std.mem.trim(u8, text_in, " \t\r");
    while (true) {
        if (std.mem.startsWith(u8, text, "noundef ")) {
            text = std.mem.trim(u8, text[8..], " ");
        } else if (std.mem.startsWith(u8, text, "noalias ")) {
            text = std.mem.trim(u8, text[8..], " ");
        } else if (std.mem.startsWith(u8, text, "nonnull ")) {
            text = std.mem.trim(u8, text[8..], " ");
        } else if (std.mem.startsWith(u8, text, "signext ")) {
            text = std.mem.trim(u8, text[8..], " ");
        } else if (std.mem.startsWith(u8, text, "zeroext ")) {
            text = std.mem.trim(u8, text[8..], " ");
        } else if (std.mem.startsWith(u8, text, "writable ")) {
            text = std.mem.trim(u8, text[9..], " ");
        } else if (std.mem.startsWith(u8, text, "dead_on_unwind ")) {
            text = std.mem.trim(u8, text[15..], " ");
        } else if (std.mem.startsWith(u8, text, "byval(") or std.mem.startsWith(u8, text, "sret(")) {
            const close = std.mem.indexOfScalar(u8, text, ')') orelse break;
            text = std.mem.trim(u8, text[close + 1 ..], " ");
        } else if (std.mem.startsWith(u8, text, "align ")) {
            const sp = std.mem.indexOfScalar(u8, text, ' ') orelse break;
            const sp2 = std.mem.indexOfScalarPos(u8, text, sp + 1, ' ') orelse break;
            text = std.mem.trim(u8, text[sp2 + 1 ..], " ");
        } else break;
    }
    return text;
}

fn typeValue(arg: []const u8) []const u8 {
    const text = std.mem.trim(u8, arg, " \t\r");
    const ty = typeToken(text);
    var value = if (ty.len < text.len) std.mem.trim(u8, text[ty.len..], " ") else text;
    value = stripLeadingAttrs(value);
    // Preserve expressions (GEP, casts, inline compares); only collapse a
    // simple token. Collapsing a GEP to its base symbol loses the offset.
    if (value.len > 0 and (value[0] == '%' or value[0] == '@')) return value;
    return value;
}

fn typeInfo(ty: []const u8) !TypeInfo {
    const t = std.mem.trim(u8, ty, " ");
    if (std.mem.eql(u8, t, "void")) return .{ .kind = 0, .size = 0 };
    if (std.mem.eql(u8, t, "fp128")) return .{ .kind = 1, .size = 16 };
    if (std.mem.eql(u8, t, "float")) return .{ .kind = 1, .size = 4 };
    if (std.mem.eql(u8, t, "double")) return .{ .kind = 1, .size = 8 };
    if (std.mem.eql(u8, t, "ptr")) return .{ .kind = 0, .size = 8 };
    if (t.len >= 2 and t[0] == '<' and t[t.len - 1] == '>') {
        const inner = std.mem.trim(u8, t[1 .. t.len - 1], " ");
        const x = std.mem.indexOf(u8, inner, " x ") orelse return error.BadType;
        const count = std.fmt.parseInt(u16, std.mem.trim(u8, inner[0..x], " "), 10) catch return error.BadType;
        const elem = std.mem.trim(u8, inner[x + 3 ..], " ");
        const es: u16 = if (std.mem.eql(u8, elem, "float")) 4 else if (std.mem.eql(u8, elem, "double")) 8 else if (elem.len > 1 and elem[0] == 'i') @intCast(@max(1, ((std.fmt.parseInt(u16, elem[1..], 10) catch 8) + 7) / 8)) else return error.BadType;
        return .{ .kind = 1, .size = count * es };
    }
    if (t.len > 1 and t[0] == 'i') {
        const bits = std.fmt.parseInt(u32, t[1..], 10) catch return error.BadType;
        return .{ .kind = 0, .size = @intCast(@max(1, (bits + 7) / 8)) };
    }
    return error.BadType;
}

fn planReturnScalar(allocator: Allocator, abi: u8, ret_ty: []const u8) !RetInfo {
    if (std.mem.eql(u8, ret_ty, "void")) return .{ .locs = &.{}, .size = 0 };
    if (std.mem.eql(u8, ret_ty, "x86_fp80")) {
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 8, .index = 0, .size = 16, .offset = 0 }}), .size = 16 };
    }
    const info = typeInfo(ret_ty) catch return error.UnsupportedFfi;
    if (info.kind == 1) {
        // Win32 returns floating point values in st0; the other targets use xmm0/v0.
        if (abi == 3) return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 8, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 6, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
    }
    return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 4, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
}

fn buildWin64Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    _ = ptr_size;
    var gpr: u16 = if (sret_idx != null) 1 else 0;
    var xmm: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var sse_count: u8 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = 0, .size = 8, .offset = arg_offset }}), .size = 8, .alignment = 8 });
            arg_offset += 8;
            continue;
        }
        if (i < byval_sizes.len and byval_sizes[i] > 0) {
            const sz = byval_sizes[i];
            stack_size = std.mem.alignForward(u16, stack_size, 8);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = sz, .offset = arg_offset }}), .size = sz, .alignment = 8, .is_struct = true });
            stack_size += std.mem.alignForward(u16, sz, 8);
            arg_offset += sz;
            continue;
        }
        const info = typeInfo(ty) catch return error.UnsupportedFfi;
        if (info.kind == 0) {
            if (gpr < 4) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 0, .index = gpr, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                gpr += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
            }
        } else {
            if (xmm < 4) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 1, .index = xmm, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                xmm += 1;
                sse_count += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
                sse_count += 1;
            }
        }
        arg_offset += 8;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnScalar(allocator, 2, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 8), .sret = sret_idx != null, .sse_count = sse_count, .ret_size = r.size };
}

fn buildWin32Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16) !Plan {
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = stack_size, .size = 4, .offset = arg_offset }}), .size = 4, .alignment = 4 });
            stack_size += 4;
            arg_offset += 4;
            continue;
        }
        if (i < byval_sizes.len and byval_sizes[i] > 0) {
            const sz = byval_sizes[i];
            stack_size = std.mem.alignForward(u16, stack_size, 4);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = sz, .offset = arg_offset }}), .size = sz, .alignment = 4, .is_struct = true });
            stack_size += std.mem.alignForward(u16, sz, 4);
            arg_offset += sz;
            continue;
        }
        const info: TypeInfo = if (std.mem.eql(u8, ty, "ptr")) .{ .kind = 0, .size = 4 } else try typeInfo(ty);
        if (info.kind == 1 and info.size == 8) stack_size = std.mem.alignForward(u16, stack_size, 8);
        try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
        stack_size += std.mem.alignForward(u16, info.size, 4);
        arg_offset += info.size;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnScalar(allocator, 3, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 4), .sret = sret_idx != null, .ret_size = r.size };
}

fn buildAapcs64Plan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16) !Plan {
    var gpr: u16 = if (sret_idx != null) 1 else 0;
    var xmm: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var sse_count: u8 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, i| {
        if (sret_idx != null and sret_idx.? == i) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = 0, .size = 8, .offset = arg_offset }}), .size = 8, .alignment = 8 });
            arg_offset += 8;
            continue;
        }
        if (i < byval_sizes.len and byval_sizes[i] > 0) {
            const sz = byval_sizes[i];
            stack_size = std.mem.alignForward(u16, stack_size, 8);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = sz, .offset = arg_offset }}), .size = sz, .alignment = 8, .is_struct = true });
            stack_size += std.mem.alignForward(u16, sz, 8);
            arg_offset += sz;
            continue;
        }
        const info = typeInfo(ty) catch return error.UnsupportedFfi;
        if (info.kind == 0) {
            if (gpr < 8) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 0, .index = gpr, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                gpr += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
            }
        } else {
            if (xmm < 8) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 1, .index = xmm, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size) });
                xmm += 1;
                sse_count += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8 });
                stack_size += 8;
                sse_count += 1;
            }
        }
        arg_offset += 8;
    }
    var r: RetInfo = undefined;
    if (sret_idx != null) r = .{ .locs = &.{}, .size = sret_size } else r = try planReturnScalar(allocator, 4, ret_ty);
    return .{ .name = name, .args = try args.toOwnedSlice(), .ret_locs = r.locs, .stack_size = std.mem.alignForward(u16, stack_size, 8), .sret = sret_idx != null, .sse_count = sse_count, .ret_size = r.size };
}

/// Build an ABI call plan from raw type spellings.
///
/// Shared with the AST lowering path (`lower_ast.zig`), which renders typed IR
/// types back to their canonical spelling and reuses this code so that the
/// `Loc` kinds, plan ordering and every size/offset stay bit-identical between
/// the legacy text path and the AST path. Keep the behaviour unchanged.
pub fn buildPlanForAbi(allocator: Allocator, abi: u8, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    return switch (abi) {
        1 => buildSysvPlan(allocator, name, ret_ty, arg_types, is_varargs, sret_idx, sret_size, byval_sizes, ptr_size),
        2 => buildWin64Plan(allocator, name, ret_ty, arg_types, sret_idx, sret_size, byval_sizes, ptr_size),
        3 => buildWin32Plan(allocator, name, ret_ty, arg_types, sret_idx, sret_size, byval_sizes),
        4 => buildAapcs64Plan(allocator, name, ret_ty, arg_types, sret_idx, sret_size, byval_sizes),
        else => error.UnsupportedFfi,
    };
}

fn returnLocs(allocator: Allocator, ret_ty: []const u8, ptr_size: u32) !struct { locs: []Loc, size: u16 } {
    _ = ptr_size;
    const ty = std.mem.trim(u8, ret_ty, " ");
    if (std.mem.eql(u8, ty, "x86_fp80")) {
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 8, .index = 0, .size = 16, .offset = 0 }}), .size = 16 };
    }
    if (ty.len >= 2 and ty[0] == '{' and ty[ty.len - 1] == '}') {
        const fields = try splitTop(allocator, ty[1 .. ty.len - 1], ',');
        var classes = [_]?u8{ null, null };
        var offset: u32 = 0;
        var max_align: u32 = 1;
        for (fields) |field| {
            const info = typeInfo(field) catch return error.UnsupportedFfi;
            if (info.kind == 0 and info.size == 0) return error.UnsupportedFfi;
            const idx = offset / 8;
            if (idx > 1) return error.UnsupportedFfi;
            if (classes[idx] != null and classes[idx].? != info.kind) {
                classes[idx] = 0;
            } else {
                classes[idx] = info.kind;
            }
            offset += info.size;
            max_align = @max(max_align, @min(info.size, 8));
        }
        const total: u16 = @intCast(alignUp(offset, max_align));
        var gpr: u16 = 0;
        var xmm: u16 = 0;
        var locs = std.ArrayList(Loc).init(allocator);
        for (classes, 0..) |cls_opt, idx| {
            const cls = cls_opt orelse continue;
            const remaining: u16 = if (total > idx * 8) total - @as(u16, @intCast(idx * 8)) else 0;
            const size: u16 = @min(8, remaining);
            if (cls == 0) {
                try locs.append(.{ .kind = if (gpr == 0) 4 else 5, .index = 0, .size = size, .offset = @intCast(idx * 8) });
                gpr += 1;
            } else {
                try locs.append(.{ .kind = if (xmm == 0) 6 else 7, .index = 0, .size = size, .offset = @intCast(idx * 8) });
                xmm += 1;
            }
        }
        return .{ .locs = try locs.toOwnedSlice(), .size = total };
    }
    const info = typeInfo(ty) catch return error.UnsupportedFfi;
    if (info.kind == 0 and info.size == 0) return .{ .locs = &.{}, .size = 0 };
    if (info.kind == 0) {
        return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 4, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
    }
    return .{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 6, .index = 0, .size = info.size, .offset = 0 }}), .size = info.size };
}

fn buildSysvPlan(allocator: Allocator, name: []const u8, ret_ty: []const u8, arg_types: []const []const u8, is_varargs: bool, sret_idx: ?usize, sret_size: u16, byval_sizes: []const u16, ptr_size: u32) !Plan {
    _ = is_varargs;
    var gpr: u16 = if (sret_idx != null) 1 else 0;
    var xmm: u16 = 0;
    var stack_size: u16 = 0;
    var arg_offset: u16 = 0;
    var sse_count: u8 = 0;
    var args = std.ArrayList(ArgPlan).init(allocator);
    for (arg_types, 0..) |ty, arg_index| {
        if (sret_idx != null and sret_idx.? == arg_index) {
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 3, .index = 0, .size = 8, .offset = arg_offset }}), .size = 8, .alignment = 8, .is_struct = false });
            arg_offset += 8;
            continue;
        }
        if (std.mem.eql(u8, ty, "x86_fp80")) {
            stack_size = std.mem.alignForward(u16, stack_size, 16);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = 16, .offset = arg_offset }}), .size = 16, .alignment = 16, .is_struct = true });
            stack_size += 16;
            arg_offset += 16;
            continue;
        }
        if (arg_index < byval_sizes.len and byval_sizes[arg_index] > 0) {
            const size = byval_sizes[arg_index];
            arg_offset = std.mem.alignForward(u16, arg_offset, 8);
            stack_size = std.mem.alignForward(u16, stack_size, 8);
            try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = size, .offset = arg_offset }}), .size = size, .alignment = 8, .is_struct = true });
            stack_size += std.mem.alignForward(u16, size, 8);
            arg_offset += size;
            continue;
        }
        const info = typeInfo(ty) catch {
            return error.UnsupportedFfi;
        };
        if (info.kind == 0) {
            if (gpr < 6) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 0, .index = gpr, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size), .is_struct = false });
                gpr += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8, .is_struct = false });
                stack_size += 8;
            }
        } else {
            if (xmm < 8) {
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 1, .index = xmm, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = @max(1, info.size), .is_struct = false });
                xmm += 1;
                sse_count += 1;
            } else {
                stack_size = std.mem.alignForward(u16, stack_size, 8);
                try args.append(.{ .locs = try allocator.dupe(Loc, &.{.{ .kind = 2, .index = stack_size, .size = info.size, .offset = arg_offset }}), .size = info.size, .alignment = 8, .is_struct = false });
                stack_size += 8;
                sse_count += 1;
            }
        }
        arg_offset += 8;
    }
    var ret_locs: []Loc = &.{};
    var ret_size: u16 = 0;
    if (sret_idx != null) {
        ret_size = sret_size;
    } else {
        const r = try returnLocs(allocator, ret_ty, ptr_size);
        ret_locs = r.locs;
        ret_size = r.size;
    }
    return .{
        .name = name,
        .args = try args.toOwnedSlice(),
        .ret_locs = ret_locs,
        .stack_size = std.mem.alignForward(u16, stack_size, 8),
        .sret = sret_idx != null,
        .sse_count = sse_count,
        .ret_size = ret_size,
    };
}

pub fn compile(allocator: Allocator, text: []const u8, abi: u8, ptr_size: u32) anyerror!CompileResult {
    const structs = try parseStructs(allocator, text);
    var globals = try parseGlobals(allocator, text, &structs, ptr_size);
    const decls = try parseDecls(allocator, text);
    const parsed = try parseModule(allocator, text);
    var indices = std.StringHashMap(u16).init(allocator);
    for (parsed.funcs, 0..) |func, idx| try indices.put(func.name, @intCast(idx));
    var external_names = std.ArrayList([]const u8).init(allocator);
    try external_names.appendSlice(globals.external_names);
    for (globals.relocs) |reloc| {
        const target = reloc.target;
        if (globals.map.contains(target)) continue;
        if (target.len > 1 and indices.contains(target[1..])) continue;
        if (globals.external.contains(target)) continue;
        if (external_names.items.len > std.math.maxInt(u16)) continue;
        const idx: u16 = @intCast(external_names.items.len);
        try globals.external.put(target, idx);
        try external_names.append(target);
    }
    var decl_it = decls.keyIterator();
    while (decl_it.next()) |decl_name_ptr| {
        const decl_name = decl_name_ptr.*;
        if (std.mem.startsWith(u8, decl_name, "llvm.")) continue;
        if (indices.contains(decl_name)) continue;
        const key = try std.fmt.allocPrint(allocator, "@{s}", .{decl_name});
        if (globals.external.contains(key)) continue;
        if (external_names.items.len > std.math.maxInt(u16)) continue;
        const idx: u16 = @intCast(external_names.items.len);
        try globals.external.put(key, idx);
        try external_names.append(key);
    }
    globals.external_names = try external_names.toOwnedSlice();
    var plans = std.ArrayList(Plan).init(allocator);
    var callbacks = CallbackTable{ .by_func = std.StringHashMap(CallbackEntry).init(allocator) };
    for (parsed.funcs, 0..) |*func, idx| {
        var lowerer = Lowerer{
            .allocator = allocator,
            .func = func,
            .slots = std.StringHashMap(u16).init(allocator),
            .next_slot = func.param_count,
            .labels = std.StringHashMap(u32).init(allocator),
            .patches = std.ArrayList(Patch).init(allocator),
            .phi_assignments = std.ArrayList(PhiAssign).init(allocator),
            .globals = &globals,
            .structs = &structs,
            .func_indices = &indices,
            .decls = &decls,
            .plans = &plans,
            .functions = parsed.funcs,
            .callbacks = &callbacks,
            .abi = abi,
            .ptr_size = ptr_size,
            .func_body = parsed.bodies[idx],
        };
        for (func.param_names, 0..) |pname, slot| {
            try lowerer.slots.put(pname, @intCast(slot));
        }
        try lowerer.lower();
    }
    return .{ .functions = parsed.funcs, .plans = try plans.toOwnedSlice(), .external_data = globals.external_names };
}

test "splitTop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parts = try splitTop(arena.allocator(), "i32 1, { i32, i32 } { i32 2, i32 3 }, i32 4", ',');
    try std.testing.expectEqual(@as(usize, 3), parts.len);
}
