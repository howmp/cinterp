//! No-copy lexer for the LLVM IR text subset consumed by the cinterp Zig
//! frontend (clang 18 / `zig cc -S -emit-llvm` output).
//!
//! Design notes
//!
//! * Tokens are `{ kind, span }` pairs that point into the caller's source
//!   buffer. The lexer never allocates and never copies token text; every
//!   `Span` is a byte range plus a 1-based line/column for diagnostics.
//! * `Token.line_start` is true when the token is the first token on its
//!   source line. LLVM IR is line oriented at record level (globals, metadata,
//!   attribute groups, declarations) and newline terminated inside function
//!   bodies (an instruction ends at the end of the line), so the parser uses
//!   this flag instead of re-scanning for `'\n'`.
//! * Comments (`; ...`) and blank lines are trivia. Both are recorded as line
//!   terminators: whatever follows a comment starts a new line.
//! * `%local`, `@"global"`, `%"quoted"`, `!N`, `!DIFile(...)`, `#0`, `#dbg_*`
//!   and `$comdat` are single tokens so the parser never re-scans sigils.
//! * Invalid input returns `error.LexError` and fills `Lexer.diagnostic`
//!   (`line`, `column`, byte span, message). The lexer never panics.
//!
//! Number literals follow LLVM's lexer:
//!   * `-` immediately followed by a digit is part of the literal (IR has no
//!     binary minus operator).
//!   * `0x...` is *always* a floating point literal (possibly with an APFloat
//!     specifier letter `H`, `K`, `L`, `M` or `R`); integer literals are
//!     decimal only.
//!   * Decimal literals containing `.` or an `e`/`E` exponent are floats.

const std = @import("std");

pub const Kind = enum(u8) {
    eof = 0,
    /// Bare word: keyword, type name, mnemonic, `x`, `true`, ...
    identifier,
    /// `%name`, `%"quoted"`, `%0`
    local_id,
    /// `@name`, `@"quoted"`, `@0`
    global_id,
    /// `!0`, `!DILocation`, `!"quoted"` (a metadata reference or keyword)
    metadata_id,
    /// `#0`
    attr_group_id,
    /// `#dbg_value` style record marker (LLVM 19+); opaque to the parser.
    hash_ident,
    /// `$name` comdat identifier
    comdat_id,
    /// Decimal integer literal, possibly negative.
    integer,
    /// Decimal or hexadecimal floating point literal.
    float_lit,
    /// `"..."`
    string,
    /// `c"..."`
    cstring,

    l_paren,
    r_paren,
    l_brace,
    r_brace,
    l_bracket,
    r_bracket,
    l_angle,
    r_angle,
    comma,
    equals,
    star,
    colon,
    ellipsis,
    /// A lone `!` (introduces `!{ ... }` metadata nodes).
    bang,
    /// `|` (used by metadata flag expressions such as `DISPFlagX | DISPFlagY`).
    pipe,
    /// Any other printable ASCII byte. Opaque metadata records may contain
    /// characters the IR grammar never uses, so the lexer reports them as a
    /// single symbol token instead of failing; truly invalid bytes (control
    /// characters, non-ASCII) are still lexer errors.
    symbol,
};

pub fn kindName(kind: Kind) []const u8 {
    return switch (kind) {
        .eof => "end of file",
        .identifier => "identifier",
        .local_id => "local identifier",
        .global_id => "global identifier",
        .metadata_id => "metadata identifier",
        .attr_group_id => "attribute group id",
        .hash_ident => "dbg record",
        .comdat_id => "comdat identifier",
        .integer => "integer literal",
        .float_lit => "floating point literal",
        .string => "string literal",
        .cstring => "c-string literal",
        .l_paren => "'('",
        .r_paren => "')'",
        .l_brace => "'{'",
        .r_brace => "'}'",
        .l_bracket => "'['",
        .r_bracket => "']'",
        .l_angle => "'<'",
        .r_angle => "'>'",
        .comma => "','",
        .equals => "'='",
        .star => "'*'",
        .colon => "':'",
        .ellipsis => "'...'",
        .bang => "'!'",
        .pipe => "'|'",
        .symbol => "symbol",
    };
}

/// Byte range plus 1-based line/column of a token in the lexed buffer.
pub const Span = struct {
    start: u32 = 0,
    end: u32 = 0,
    line: u32 = 0,
    column: u32 = 0,

    pub fn len(self: Span) u32 {
        return self.end - self.start;
    }

    pub fn join(a: Span, b: Span) Span {
        var out = a;
        out.end = b.end;
        return out;
    }
};

pub const Token = struct {
    kind: Kind = .eof,
    /// True when this is the first token on its source line.
    line_start: bool = false,
    span: Span = .{},

    pub fn isEof(self: Token) bool {
        return self.kind == .eof;
    }
};

pub const Diagnostic = struct {
    line: u32 = 0,
    column: u32 = 0,
    span: Span = .{},
    message: []const u8 = "",
};

pub const Error = error{LexError};

pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,
    line: u32 = 1,
    column: u32 = 1,
    at_line_start: bool = true,
    diagnostic: Diagnostic = .{},
    msg_buf: [192]u8 = undefined,

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    /// Source text covered by `span` (clamped to the buffer end).
    pub fn slice(self: *const Lexer, span: Span) []const u8 {
        const start = @min(@as(usize, span.start), self.source.len);
        const end = @min(@as(usize, span.end), self.source.len);
        if (end <= start) return self.source[start..start];
        return self.source[start..end];
    }

    /// Lex the next token. On invalid input returns `error.LexError` and sets
    /// `self.diagnostic`; the position is left just past the offending byte.
    pub fn next(self: *Lexer) Error!Token {
        try self.skipTrivia();
        var tok = Token{
            .line_start = self.at_line_start,
            .span = .{ .start = self.pos, .end = self.pos, .line = self.line, .column = self.column },
        };
        self.at_line_start = false;

        if (self.pos >= self.source.len) {
            tok.kind = .eof;
            return tok;
        }

        const c = self.source[self.pos];
        switch (c) {
            '%' => {
                self.bump();
                try self.scanNameTail(tok.span);
                tok.kind = .local_id;
            },
            '@' => {
                self.bump();
                try self.scanNameTail(tok.span);
                tok.kind = .global_id;
            },
            '!' => {
                const next_c = self.peekAt(1);
                if (next_c == '"') {
                    self.bump();
                    try self.scanQuoted(tok.span);
                    tok.kind = .metadata_id;
                } else if (isIdentStart(next_c)) {
                    self.bump();
                    self.scanIdentBody();
                    tok.kind = .metadata_id;
                } else if (std.ascii.isDigit(next_c)) {
                    self.bump();
                    self.scanDigits();
                    tok.kind = .metadata_id;
                } else {
                    self.bump();
                    tok.kind = .bang;
                }
            },
            '#' => {
                const next_c = self.peekAt(1);
                if (std.ascii.isDigit(next_c)) {
                    self.bump();
                    self.scanDigits();
                    tok.kind = .attr_group_id;
                } else if (isIdentStart(next_c)) {
                    self.bump();
                    self.scanIdentBody();
                    tok.kind = .hash_ident;
                } else {
                    return self.fail(tok.span, "unexpected character '#'", .{});
                }
            },
            '$' => {
                self.bump();
                try self.scanNameTail(tok.span);
                tok.kind = .comdat_id;
            },
            '"' => {
                try self.scanQuoted(tok.span);
                tok.kind = .string;
            },
            'c' => {
                if (self.peekAt(1) == '"') {
                    self.bump();
                    try self.scanQuoted(tok.span);
                    tok.kind = .cstring;
                } else {
                    self.scanIdentBody();
                    tok.kind = .identifier;
                }
            },
            '(' => {
                self.bump();
                tok.kind = .l_paren;
            },
            ')' => {
                self.bump();
                tok.kind = .r_paren;
            },
            '{' => {
                self.bump();
                tok.kind = .l_brace;
            },
            '}' => {
                self.bump();
                tok.kind = .r_brace;
            },
            '[' => {
                self.bump();
                tok.kind = .l_bracket;
            },
            ']' => {
                self.bump();
                tok.kind = .r_bracket;
            },
            '<' => {
                self.bump();
                tok.kind = .l_angle;
            },
            '>' => {
                self.bump();
                tok.kind = .r_angle;
            },
            ',' => {
                self.bump();
                tok.kind = .comma;
            },
            '=' => {
                self.bump();
                tok.kind = .equals;
            },
            '*' => {
                self.bump();
                tok.kind = .star;
            },
            ':' => {
                self.bump();
                tok.kind = .colon;
            },
            '|' => {
                self.bump();
                tok.kind = .pipe;
            },
            '.' => {
                if (self.peekAt(1) == '.' and self.peekAt(2) == '.') {
                    self.bump();
                    self.bump();
                    self.bump();
                    tok.kind = .ellipsis;
                } else {
                    self.scanIdentBody();
                    tok.kind = .identifier;
                }
            },
            '-' => {
                if (std.ascii.isDigit(self.peekAt(1))) {
                    tok.kind = try self.scanNumber(tok.span);
                } else {
                    return self.fail(tok.span, "unexpected character '-' (IR has no binary minus)", .{});
                }
            },
            else => {
                if (std.ascii.isDigit(c)) {
                    tok.kind = try self.scanNumber(tok.span);
                } else if (isIdentStart(c)) {
                    self.scanIdentBody();
                    tok.kind = .identifier;
                } else if (c >= 0x20 and c < 0x7f) {
                    // Printable but not part of the grammar the parser knows:
                    // keep it as a symbol so opaque records stay skippable.
                    self.bump();
                    tok.kind = .symbol;
                } else {
                    return self.fail(tok.span, "unexpected character 0x{x}", .{c});
                }
            },
        }

        tok.span.end = self.pos;
        return tok;
    }

    // ----------------------------------------------------------------- internals

    inline fn peekAt(self: *const Lexer, offset: u32) u8 {
        const at = self.pos + offset;
        if (at >= self.source.len) return 0;
        return self.source[at];
    }

    inline fn bump(self: *Lexer) void {
        const c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
    }

    fn skipTrivia(self: *Lexer) Error!void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            switch (c) {
                ' ', '\t', '\r' => self.bump(),
                '\n' => {
                    self.at_line_start = true;
                    self.bump();
                },
                ';' => {
                    while (self.pos < self.source.len and self.source[self.pos] != '\n') self.bump();
                    // A comment terminates the logical line.
                    self.at_line_start = true;
                },
                else => return,
            }
        }
    }

    fn startSpan(self: *const Lexer) Span {
        return .{ .start = self.pos, .end = self.pos, .line = self.line, .column = self.column };
    }

    /// Scan the body of a `%name`, `@name` or `$name` token (the sigil is
    /// already consumed). Accepts bare names and quoted names.
    fn scanNameTail(self: *Lexer, start: Span) Error!void {
        if (self.pos >= self.source.len) return self.fail(start, "expected a name after sigil", .{});
        const c = self.source[self.pos];
        if (c == '"') return self.scanQuoted(start);
        if (std.ascii.isDigit(c)) {
            // Unnamed values: `%0`, `@1`, `%42`.
            self.scanDigits();
            return;
        }
        if (!isIdentStart(c)) {
            return self.fail(start, "invalid character in name", .{});
        }
        self.scanIdentBody();
    }

    fn scanIdentBody(self: *Lexer) void {
        // An identifier starts at the current position; the caller guarantees
        // the first byte is an identifier start (or a digit for metadata ids).
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (!isIdentChar(c)) break;
            self.bump();
        }
    }

    fn scanDigits(self: *Lexer) void {
        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) self.bump();
    }

    /// Scan a quoted string, escape sequences included. `start` points at the
    /// token start (the opening quote is at `self.pos` on entry).
    fn scanQuoted(self: *Lexer, start: Span) Error!void {
        if (self.pos >= self.source.len or self.source[self.pos] != '"') {
            return self.fail(start, "expected '\"'", .{});
        }
        self.bump(); // opening quote
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '"') {
                self.bump();
                return;
            }
            if (c == '\\') {
                const esc_span = self.startSpan();
                self.bump();
                if (self.pos >= self.source.len) break; // unterminated
                if (std.ascii.isHex(self.source[self.pos])) {
                    if (self.pos + 1 < self.source.len and std.ascii.isHex(self.source[self.pos + 1])) {
                        self.bump();
                        self.bump();
                        continue;
                    }
                    return self.fail(esc_span, "hex escape needs exactly two hex digits", .{});
                }
                switch (self.source[self.pos]) {
                    '\\', '"' => {
                        self.bump();
                        continue;
                    },
                    else => return self.fail(esc_span, "invalid string escape", .{}),
                }
            }
            self.bump();
        }
        return self.fail(start, "unterminated string literal", .{});
    }

    fn scanNumber(self: *Lexer, start: Span) Error!Kind {
        if (self.source[self.pos] == '-') self.bump();

        // Hexadecimal floating point literal (LLVM: integers are decimal only).
        if (self.peekAt(0) == '0' and (self.peekAt(1) == 'x' or self.peekAt(1) == 'X')) {
            self.bump();
            self.bump();
            // Optional APFloat specifier letter (H/K/L/M/R) followed by digits.
            const spec = self.peekAt(0);
            if (isHexSpecifier(spec) and std.ascii.isHex(self.peekAt(1))) self.bump();
            var digits: u32 = 0;
            while (std.ascii.isHex(self.peekAt(0))) : (digits += 1) self.bump();
            if (digits == 0) return self.fail(start, "hexadecimal literal needs at least one digit", .{});
            // Tolerate `0x1.8p3` style hex fractions/exponents.
            if (self.peekAt(0) == '.') {
                self.bump();
                while (std.ascii.isHex(self.peekAt(0))) self.bump();
            }
            if (self.peekAt(0) == 'p' or self.peekAt(0) == 'P') {
                self.bump();
                if (self.peekAt(0) == '+' or self.peekAt(0) == '-') self.bump();
                const exp_start = self.pos;
                self.scanDigits();
                if (self.pos == exp_start) return self.fail(start, "hex float exponent needs digits", .{});
            }
            return .float_lit;
        }

        var is_float = false;
        self.scanDigits();
        if (self.peekAt(0) == '.') {
            is_float = true;
            self.bump();
            self.scanDigits();
        }
        if (self.peekAt(0) == 'e' or self.peekAt(0) == 'E') {
            is_float = true;
            self.bump();
            if (self.peekAt(0) == '+' or self.peekAt(0) == '-') self.bump();
            const exp_start = self.pos;
            self.scanDigits();
            if (self.pos == exp_start) return self.fail(start, "float exponent needs digits", .{});
        }
        return if (is_float) .float_lit else .integer;
    }

    fn fail(self: *Lexer, span: Span, comptime fmt: []const u8, args: anytype) Error {
        const msg = std.fmt.bufPrint(&self.msg_buf, fmt, args) catch "invalid token";
        self.diagnostic = .{
            .line = span.line,
            .column = span.column,
            .span = span,
            .message = msg,
        };
        return error.LexError;
    }
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == '.' or c == '$';
}

fn isIdentChar(c: u8) bool {
    // LLVM's `isalnum` + `_`, `.`, `$`, `-` for bare identifiers.
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '$' or c == '-';
}

fn isHexSpecifier(c: u8) bool {
    return switch (c) {
        'H', 'K', 'L', 'M', 'R' => true,
        else => false,
    };
}

// ---------------------------------------------------------------------- tests

test "lex basic tokens and spans" {
    const src =
        \\@g = global i32 -7, align 4, !dbg !12
        \\%x = add nsw i32 %a, 1
    ;
    var lx = Lexer.init(src);
    const t0 = try lx.next();
    try std.testing.expectEqual(Kind.global_id, t0.kind);
    try std.testing.expectEqualStrings("@g", lx.slice(t0.span));
    try std.testing.expect(t0.line_start);
    try std.testing.expectEqual(@as(u32, 1), t0.span.line);
    try std.testing.expectEqual(@as(u32, 1), t0.span.column);

    const t1 = try lx.next();
    try std.testing.expectEqual(Kind.equals, t1.kind);
    try std.testing.expect(!t1.line_start);

    // Walk to the end of the first line, then check the line-start flag.
    var tok = t1;
    while (tok.kind != .eof and !(tok.kind == .local_id and tok.line_start)) {
        tok = try lx.next();
    }
    try std.testing.expectEqual(Kind.local_id, tok.kind);
    try std.testing.expectEqual(@as(u32, 2), tok.span.line);
    try std.testing.expectEqual(@as(u32, 1), tok.span.column);
}

test "lex quoted names and strings with escapes" {
    const src = "  %\"weird name\" = call void @\"quo\\22ted\"(c\"a\\00b\")\n";
    var lx = Lexer.init(src);
    const a = try lx.next();
    try std.testing.expectEqual(Kind.local_id, a.kind);
    try std.testing.expectEqualStrings("%\"weird name\"", lx.slice(a.span));

    var b = a;
    while (b.kind != .global_id) b = try lx.next();
    try std.testing.expectEqualStrings("@\"quo\\22ted\"", lx.slice(b.span));

    var c = b;
    while (c.kind != .cstring) c = try lx.next();
    try std.testing.expectEqualStrings("c\"a\\00b\"", lx.slice(c.span));
}

test "lex numeric literal kinds" {
    const cases = [_]struct { text: []const u8, kind: Kind }{
        .{ .text = "1", .kind = .integer },
        .{ .text = "-3", .kind = .integer },
        .{ .text = "0", .kind = .integer },
        .{ .text = "170141183460469231731687303715884105727", .kind = .integer },
        .{ .text = "1.5", .kind = .float_lit },
        .{ .text = "-0.000000e+00", .kind = .float_lit },
        .{ .text = "3.250000e+00", .kind = .float_lit },
        .{ .text = "0xK3FFFC000000000000000", .kind = .float_lit },
        .{ .text = "0xL00000000000000004000400000000000", .kind = .float_lit },
        .{ .text = "0x7FEFFFFFFFFFFFFF", .kind = .float_lit },
        .{ .text = "0xH7C00", .kind = .float_lit },
    };
    for (cases) |case| {
        var lx = Lexer.init(case.text);
        const tok = try lx.next();
        try std.testing.expectEqual(case.kind, tok.kind);
        try std.testing.expectEqualStrings(case.text, lx.slice(tok.span));
        try std.testing.expectEqual(Kind.eof, (try lx.next()).kind);
    }
}

test "lex metadata, attr groups and comdat ids" {
    const src = "!0 = !DIExpression(DW_OP_constu, 1) #3 $cn";
    var lx = Lexer.init(src);
    const a = try lx.next();
    try std.testing.expectEqual(Kind.metadata_id, a.kind);
    try std.testing.expectEqualStrings("!0", lx.slice(a.span));
    var kinds = std.ArrayList(Kind).init(std.testing.allocator);
    defer kinds.deinit();
    var tok = a;
    while (tok.kind != .eof) : (tok = try lx.next()) try kinds.append(tok.kind);
    try std.testing.expect(std.mem.indexOfScalar(Kind, kinds.items, .attr_group_id) != null);
    try std.testing.expect(std.mem.indexOfScalar(Kind, kinds.items, .comdat_id) != null);
}

test "lex invalid input returns diagnostics" {
    var lx = Lexer.init("i32 \x01 1");
    _ = try lx.next();
    try std.testing.expectError(error.LexError, lx.next());
    try std.testing.expectEqual(@as(u32, 1), lx.diagnostic.line);

    var lx2 = Lexer.init("\"unterminated");
    try std.testing.expectError(error.LexError, lx2.next());
    try std.testing.expect(lx2.diagnostic.message.len > 0);

    var lx3 = Lexer.init("c\"bad\\q\"");
    try std.testing.expectError(error.LexError, lx3.next());
    try std.testing.expectEqual(@as(u32, 1), lx3.diagnostic.line);
    try std.testing.expectEqual(@as(u32, 6), lx3.diagnostic.column);
}

test "unknown printable bytes become symbol tokens" {
    var lx = Lexer.init("+ | ?");
    var kinds: [3]Kind = undefined;
    for (&kinds) |*slot| slot.* = (try lx.next()).kind;
    try std.testing.expectEqual(Kind.symbol, kinds[0]);
    try std.testing.expectEqual(Kind.pipe, kinds[1]);
    try std.testing.expectEqual(Kind.symbol, kinds[2]);
}

test "lex tracks line and column across comments and blank lines" {
    const src = "; leading comment\n\n  %a = alloca i32 ; trailing\n";
    var lx = Lexer.init(src);
    const t = try lx.next();
    try std.testing.expectEqual(Kind.local_id, t.kind);
    try std.testing.expectEqual(@as(u32, 3), t.span.line);
    try std.testing.expectEqual(@as(u32, 3), t.span.column);
    try std.testing.expect(t.line_start);
}
