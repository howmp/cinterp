//! Recursive-descent parser for the LLVM IR text subset consumed by the
//! cinterp Zig frontend.
//!
//! Scope: everything `lower.zig` reads today (module header, type definitions,
//! globals, declarations, definitions, blocks, the ~45 instruction forms and
//! the `llvm.*` intrinsics, which are simply calls). Anything else that is
//! *legal* at module level (comdats, module flags, metadata records,
//! `uselistorder`, `attributes #N`, `#dbg_*`) is captured as an opaque record
//! instead of being rejected; anything unsupported *inside* a function body is
//! reported as a `line:column` diagnostic rather than panicking or being
//! silently skipped.
//!
//! Memory: all AST nodes/slices are allocated from the allocator passed to the
//! parser and are never freed here. Parse into an `ArenaAllocator`.
//!
//! Diagnostics: the parser keeps the first error in `Parser.diagnostic`
//! (`line`, `column`, byte span, message, offending token text) and returns
//! `error.ParseError`. Use the `Parser` type directly when the diagnostic is
//! needed; `parseModule` is the convenience wrapper.

const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");

const Allocator = std.mem.Allocator;
const Kind = lexer.Kind;
const Token = lexer.Token;
const Span = lexer.Span;

pub const Diagnostic = struct {
    line: u32 = 0,
    column: u32 = 0,
    span: Span = .{},
    message: []const u8 = "",
    /// Source text of the token the parser stopped at (empty at EOF).
    found: []const u8 = "",
};

pub const Error = error{ ParseError, OutOfMemory };

/// Maximum nesting depth for types/values/aggregates; guards against stack
/// exhaustion on malformed input.
const max_depth: u32 = 96;

pub const Parser = struct {
    allocator: Allocator,
    source: []const u8,
    lex: lexer.Lexer = undefined,
    cur: Token = .{},
    next_tok: Token = .{},
    prev_span: Span = .{},
    primed: bool = false,
    depth: u32 = 0,
    diagnostic: Diagnostic = .{},
    msg_buf: [256]u8 = undefined,

    // Module header values.
    source_filename: ?[]const u8 = null,
    target_datalayout: ?[]const u8 = null,
    target_triple: ?[]const u8 = null,

    // Module records.
    type_defs: std.ArrayList(ast.TypeDef) = undefined,
    globals: std.ArrayList(ast.Global) = undefined,
    declares: std.ArrayList(ast.Decl) = undefined,
    functions: std.ArrayList(ast.Function) = undefined,
    attr_groups: std.ArrayList(ast.AttributeGroup) = undefined,
    metadata: std.ArrayList(ast.MetadataRecord) = undefined,
    opaque_records: std.ArrayList(ast.OpaqueRecord) = undefined,

    pub fn init(allocator: Allocator, source: []const u8) Parser {
        return .{
            .allocator = allocator,
            .source = source,
            .lex = lexer.Lexer.init(source),
        };
    }

    /// Parse the whole module. `Parser.diagnostic` describes the failure.
    pub fn parse(self: *Parser) Error!ast.Module {
        self.lex = lexer.Lexer.init(self.source);
        self.type_defs = std.ArrayList(ast.TypeDef).init(self.allocator);
        self.globals = std.ArrayList(ast.Global).init(self.allocator);
        self.declares = std.ArrayList(ast.Decl).init(self.allocator);
        self.functions = std.ArrayList(ast.Function).init(self.allocator);
        self.attr_groups = std.ArrayList(ast.AttributeGroup).init(self.allocator);
        self.metadata = std.ArrayList(ast.MetadataRecord).init(self.allocator);
        self.opaque_records = std.ArrayList(ast.OpaqueRecord).init(self.allocator);

        try self.advance(); // prime cur/next_tok
        while (self.cur.kind != .eof) {
            try self.parseTopLevelRecord();
        }

        return ast.Module{
            .source_filename = self.source_filename,
            .target_datalayout = self.target_datalayout,
            .target_triple = self.target_triple,
            .type_defs = try self.type_defs.toOwnedSlice(),
            .globals = try self.globals.toOwnedSlice(),
            .declares = try self.declares.toOwnedSlice(),
            .functions = try self.functions.toOwnedSlice(),
            .attribute_groups = try self.attr_groups.toOwnedSlice(),
            .metadata = try self.metadata.toOwnedSlice(),
            .opaque_records = try self.opaque_records.toOwnedSlice(),
            .line_count = self.lex.line,
        };
    }

    // ------------------------------------------------------- standalone entry

    /// Parse one type from the whole buffer (priming the token stream first).
    /// Trailing tokens are an error.
    pub fn parseTypeOnly(self: *Parser) Error!*const ast.Type {
        try self.advance();
        const ty = try self.parseType();
        if (self.cur.kind != .eof) {
            return self.fail(self.cur, "trailing {s} '{s}' after type", .{
                lexer.kindName(self.cur.kind), self.curText(),
            });
        }
        return ty;
    }

    /// Parse one value of type `ty` from the whole buffer.
    pub fn parseValueOnly(self: *Parser, ty: *const ast.Type) Error!ast.Value {
        try self.advance();
        const value = try self.parseValue(ty);
        if (self.cur.kind != .eof) {
            return self.fail(self.cur, "trailing {s} '{s}' after value", .{
                lexer.kindName(self.cur.kind), self.curText(),
            });
        }
        return value;
    }

    // ------------------------------------------------------------- token layer

    fn lexNext(self: *Parser) Error!Token {
        return self.lex.next() catch |err| switch (err) {
            error.LexError => {
                const d = self.lex.diagnostic;
                self.diagnostic = .{
                    .line = d.line,
                    .column = d.column,
                    .span = d.span,
                    .message = d.message,
                    .found = self.sliceSpan(d.span),
                };
                return error.ParseError;
            },
        };
    }

    fn advance(self: *Parser) Error!void {
        if (!self.primed) {
            self.cur = try self.lexNext();
            self.next_tok = try self.lexNext();
            self.primed = true;
            self.prev_span = self.cur.span;
            return;
        }
        self.prev_span = self.cur.span;
        self.cur = self.next_tok;
        self.next_tok = try self.lexNext();
    }

    fn text(self: *const Parser, tok: Token) []const u8 {
        return self.lex.slice(tok.span);
    }

    fn curText(self: *const Parser) []const u8 {
        return self.text(self.cur);
    }

    fn sliceSpan(self: *const Parser, span: Span) []const u8 {
        return self.lex.slice(span);
    }

    fn sliceRange(self: *const Parser, start: u32, end: u32) []const u8 {
        return self.lex.slice(.{ .start = start, .end = end });
    }

    fn check(self: *const Parser, kind: Kind) bool {
        return self.cur.kind == kind;
    }

    fn checkNext(self: *const Parser, kind: Kind) bool {
        return self.next_tok.kind == kind;
    }

    fn isWord(self: *const Parser, word: []const u8) bool {
        return self.cur.kind == .identifier and std.mem.eql(u8, self.curText(), word);
    }

    fn isNextWord(self: *const Parser, word: []const u8) bool {
        return self.next_tok.kind == .identifier and std.mem.eql(u8, self.text(self.next_tok), word);
    }

    fn eat(self: *Parser, kind: Kind) Error!bool {
        if (self.cur.kind != kind) return false;
        try self.advance();
        return true;
    }

    fn eatWord(self: *Parser, word: []const u8) Error!bool {
        if (!self.isWord(word)) return false;
        try self.advance();
        return true;
    }

    fn expect(self: *Parser, kind: Kind, comptime what: []const u8) Error!Token {
        if (self.cur.kind != kind) {
            return self.fail(self.cur, "expected {s} ({s}), found {s} '{s}'", .{
                lexer.kindName(kind), what, lexer.kindName(self.cur.kind), self.curText(),
            });
        }
        const tok = self.cur;
        try self.advance();
        return tok;
    }

    fn expectWord(self: *Parser, word: []const u8) Error!Token {
        if (!self.isWord(word)) {
            return self.fail(self.cur, "expected '{s}', found {s} '{s}'", .{
                word, lexer.kindName(self.cur.kind), self.curText(),
            });
        }
        const tok = self.cur;
        try self.advance();
        return tok;
    }

    /// Fail at `tok` with a formatted message. Messages are formatted into the
    /// parser's fixed buffer, so no allocation can fail here.
    fn fail(self: *Parser, tok: Token, comptime fmt: []const u8, args: anytype) Error {
        if (self.diagnostic.line == 0) {
            const msg = std.fmt.bufPrint(&self.msg_buf, fmt, args) catch "parse error";
            self.diagnostic = .{
                .line = tok.span.line,
                .column = tok.span.column,
                .span = tok.span,
                .message = msg,
                .found = self.text(tok),
            };
        }
        return error.ParseError;
    }

    fn failMsg(self: *Parser, comptime fmt: []const u8, args: anytype) Error {
        return self.fail(self.cur, fmt, args);
    }

    fn enter(self: *Parser) Error!void {
        self.depth += 1;
        if (self.depth > max_depth) {
            return self.failMsg("nesting too deep (limit {d})", .{max_depth});
        }
    }

    fn leave(self: *Parser) void {
        self.depth -= 1;
    }

    fn newType(self: *Parser, ty: ast.Type) Error!*const ast.Type {
        const p = try self.allocator.create(ast.Type);
        p.* = ty;
        return p;
    }

    fn newConstExpr(self: *Parser, expr: ast.ConstExpr) Error!*const ast.ConstExpr {
        const p = try self.allocator.create(ast.ConstExpr);
        p.* = expr;
        return p;
    }

    /// Consume tokens until the matching close delimiter and return the raw
    /// source text of the balanced region (delimiters included).
    fn skipBalancedRaw(self: *Parser, open: Kind, close: Kind) Error![]const u8 {
        if (self.cur.kind != open) {
            return self.failMsg("expected {s}, found {s}", .{ lexer.kindName(open), lexer.kindName(self.cur.kind) });
        }
        const start = self.cur.span.start;
        var depth: u32 = 0;
        while (true) {
            switch (self.cur.kind) {
                .eof => return self.failMsg("unterminated {s} group", .{lexer.kindName(open)}),
                else => {},
            }
            if (self.cur.kind == open) {
                depth += 1;
            } else if (self.cur.kind == close) {
                depth -= 1;
                if (depth == 0) {
                    const end = self.cur.span.end;
                    try self.advance();
                    return self.sliceRange(start, end);
                }
            }
            try self.advance();
        }
    }

    fn parseU32(self: *Parser) Error!u32 {
        const tok = try self.expect(.integer, "unsigned integer");
        return std.fmt.parseInt(u32, self.text(tok), 10) catch
            self.fail(tok, "integer '{s}' does not fit in 32 bits", .{self.text(tok)});
    }

    fn parseU64(self: *Parser) Error!u64 {
        const tok = try self.expect(.integer, "unsigned integer");
        return std.fmt.parseInt(u64, self.text(tok), 10) catch
            self.fail(tok, "integer '{s}' does not fit in 64 bits", .{self.text(tok)});
    }

    /// Parse a `%name`, `@name`, `$name` or metadata name token.
    fn parseNamed(self: *Parser, kind: Kind) Error!ast.NamedRef {
        if (self.cur.kind != kind) {
            return self.failMsg("expected {s}, found {s} '{s}'", .{
                lexer.kindName(kind), lexer.kindName(self.cur.kind), self.curText(),
            });
        }
        const tok = self.cur;
        const raw = self.text(tok);
        var name: []const u8 = undefined;
        var quoted = false;
        var number: ?u32 = null;
        if (raw.len >= 2 and raw[1] == '"') {
            quoted = true;
            name = raw[2 .. raw.len - 1];
        } else {
            name = raw[1..];
            if (name.len != 0 and allDigits(name)) {
                number = std.fmt.parseInt(u32, name, 10) catch null;
            }
        }
        if (name.len == 0) return self.fail(tok, "empty name", .{});
        try self.advance();
        return .{ .name = name, .quoted = quoted, .number = number, .span = tok.span };
    }

    /// Branch targets are always `%name`.
    fn parseLabelRef(self: *Parser) Error!ast.NamedRef {
        return self.parseNamed(.local_id);
    }

    // ---------------------------------------------------------------- records

    fn expectEndOfRecord(self: *Parser) Error!void {
        if (self.cur.kind == .eof) return;
        if (self.cur.line_start) return;
        return self.fail(self.cur, "unexpected {s} '{s}' at end of record", .{
            lexer.kindName(self.cur.kind), self.curText(),
        });
    }

    fn parseTopLevelRecord(self: *Parser) Error!void {
        switch (self.cur.kind) {
            .identifier => {
                const word = self.curText();
                if (std.mem.eql(u8, word, "source_filename")) return self.parseSourceFilename();
                if (std.mem.eql(u8, word, "target")) return self.parseTargetDirective();
                if (std.mem.eql(u8, word, "declare")) return self.parseDecl();
                if (std.mem.eql(u8, word, "define")) return self.parseDefine();
                if (std.mem.eql(u8, word, "attributes")) return self.parseAttributeGroupRecord();
                return self.skipOpaqueRecord(word);
            },
            .global_id => return self.parseGlobal(),
            .local_id => return self.parseTypeDef(),
            .metadata_id, .bang => return self.parseMetadataRecord(),
            .comdat_id => return self.skipOpaqueRecord("comdat"),
            else => return self.skipOpaqueRecord(""),
        }
    }

    fn skipOpaqueRecord(self: *Parser, keyword: []const u8) Error!void {
        const start = self.cur.span;
        var end: u32 = self.cur.span.end;
        try self.advance(); // always consume at least one token
        while (self.cur.kind != .eof and !self.cur.line_start) {
            end = self.cur.span.end;
            try self.advance();
        }
        try self.opaque_records.append(.{
            .keyword = keyword,
            .raw = self.sliceRange(start.start, end),
            .span = start,
        });
    }

    fn parseSourceFilename(self: *Parser) Error!void {
        try self.advance(); // source_filename
        _ = try self.expect(.equals, "'='");
        const tok = try self.expect(.string, "string literal");
        self.source_filename = stripQuotes(self.text(tok));
        try self.expectEndOfRecord();
    }

    fn parseTargetDirective(self: *Parser) Error!void {
        try self.advance(); // target
        const which = try self.expect(.identifier, "'datalayout' or 'triple'");
        const word = self.text(which);
        _ = try self.expect(.equals, "'='");
        const tok = try self.expect(.string, "string literal");
        const value = stripQuotes(self.text(tok));
        if (std.mem.eql(u8, word, "datalayout")) {
            self.target_datalayout = value;
        } else if (std.mem.eql(u8, word, "triple")) {
            self.target_triple = value;
        } else {
            return self.fail(which, "unsupported target directive '{s}'", .{word});
        }
        try self.expectEndOfRecord();
    }

    fn parseTypeDef(self: *Parser) Error!void {
        const start = self.cur.span;
        const ref = try self.parseNamed(.local_id);
        _ = try self.expect(.equals, "'='");
        _ = try self.expectWord("type");
        const ty = try self.parseType();
        try self.expectEndOfRecord();
        try self.type_defs.append(.{
            .name = ref.name,
            .ref = ref,
            .ty = ty,
            .span = Span.join(start, self.prev_span),
        });
    }

    fn parseAttributeGroupRecord(self: *Parser) Error!void {
        const start = self.cur.span;
        try self.advance(); // attributes
        const id_tok = try self.expect(.attr_group_id, "'#N' attribute group id");
        const id_text = self.text(id_tok);
        const id = std.fmt.parseInt(u32, id_text[1..], 10) catch
            return self.fail(id_tok, "bad attribute group id '{s}'", .{id_text});
        _ = try self.expect(.equals, "'='");
        var raw: []const u8 = "";
        if (self.check(.l_brace)) {
            raw = try self.skipBalancedRaw(.l_brace, .r_brace);
        } else {
            raw = try self.captureRestOfLine();
        }
        try self.attr_groups.append(.{ .id = id, .raw = raw, .span = Span.join(start, self.prev_span) });
    }

    /// Capture the remaining tokens on the current line as raw source text.
    fn captureRestOfLine(self: *Parser) Error![]const u8 {
        if (self.cur.kind == .eof or self.cur.line_start) return "";
        const start = self.cur.span.start;
        var end = self.cur.span.end;
        while (self.cur.kind != .eof and !self.cur.line_start) {
            end = self.cur.span.end;
            try self.advance();
        }
        return sliceRange(self, start, end);
    }

    fn parseMetadataRecord(self: *Parser) Error!void {
        const start = self.cur.span;
        const name_tok = self.cur;
        var name: []const u8 = undefined;
        var id: ?u32 = null;
        if (name_tok.kind == .metadata_id) {
            const raw = self.text(name_tok);
            name = raw[1..];
            if (name.len >= 2 and name[0] == '"') {
                name = name[1 .. name.len - 1];
            } else if (allDigits(name)) {
                id = std.fmt.parseInt(u32, name, 10) catch null;
            }
        } else {
            name = "!";
        }
        try self.advance();
        if (!self.check(.equals)) {
            // Not a metadata definition (`!llvm.module.flags` without a value
            // would be malformed); keep it opaque instead of failing.
            const raw0 = self.sliceRange(start.start, name_tok.span.end);
            try self.opaque_records.append(.{ .keyword = "metadata", .raw = raw0, .span = start });
            return;
        }
        try self.advance(); // '='
        const raw = try self.captureRestOfLine();
        try self.metadata.append(.{
            .name = name,
            .id = id,
            .raw = raw,
            .span = Span.join(start, self.prev_span),
        });
    }

    // ----------------------------------------------------------- module header

    fn parseGlobalModifiers(self: *Parser, mods: *ast.GlobalModifiers, comptime allow_thread_local: bool) Error!void {
        while (self.cur.kind == .identifier) {
            const word = self.curText();
            if (linkageFromWord(word)) |linkage| {
                mods.linkage = linkage;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "dso_local")) {
                mods.dso_local = true;
                mods.preemptable = false;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "dso_preemptable")) {
                mods.preemptable = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "hidden")) {
                mods.visibility = .hidden;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "protected")) {
                mods.visibility = .protected;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "default")) {
                mods.visibility = .default;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "dllimport")) {
                mods.dll_storage = .dllimport;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "dllexport")) {
                mods.dll_storage = .dllexport;
                try self.advance();
                continue;
            }
            if (allow_thread_local and std.mem.eql(u8, word, "thread_local")) {
                mods.thread_local = true;
                try self.advance();
                if (self.check(.l_paren)) _ = try self.skipBalancedRaw(.l_paren, .r_paren);
                continue;
            }
            if (std.mem.eql(u8, word, "unnamed_addr")) {
                mods.unnamed_addr = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "local_unnamed_addr")) {
                mods.local_unnamed_addr = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "externally_initialized")) {
                mods.externally_initialized = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "addrspace")) {
                try self.advance();
                _ = try self.expect(.l_paren, "'(' after addrspace");
                _ = try self.parseU32();
                _ = try self.expect(.r_paren, "')' after addrspace");
                continue;
            }
            break;
        }
    }

    // ---------------------------------------------------------------- globals

    fn parseGlobal(self: *Parser) Error!void {
        const start = self.cur.span;
        const ref = try self.parseNamed(.global_id);
        _ = try self.expect(.equals, "'=' after global name");

        var mods = ast.GlobalModifiers{};
        try self.parseGlobalModifiers(&mods, true);

        const kw = self.cur;
        var is_const = false;
        if (self.isWord("alias") or self.isWord("ifunc")) {
            const line = kw.span.line;
            while (self.cur.kind != .eof and self.cur.span.line == line) try self.advance();
            return;
        }
        if (self.isWord("global")) {
            is_const = false;
        } else if (self.isWord("constant")) {
            is_const = true;
        } else {
            return self.fail(kw, "expected 'global' or 'constant', found '{s}'", .{self.curText()});
        }
        try self.advance();

        const ty = try self.parseType();

        var initializer: ?ast.Value = null;
        if (!self.check(.comma) and !self.check(.eof) and !self.cur.line_start) {
            initializer = try self.parseValue(ty);
        }

        var alignment: ?u32 = null;
        var section: ?[]const u8 = null;
        var comdat: ?ast.NamedRef = null;
        var metadata = std.ArrayList(ast.MetadataAttachment).init(self.allocator);

        while (self.check(.comma)) {
            if (self.next_tok.kind == .metadata_id) {
                try self.advance(); // ','
                try metadata.append(try self.parseMetadataAttachment());
                continue;
            }
            if (self.next_tok.kind == .identifier) {
                const word = self.text(self.next_tok);
                if (std.mem.eql(u8, word, "align")) {
                    try self.advance();
                    try self.advance();
                    alignment = try self.parseU32();
                    continue;
                }
                if (std.mem.eql(u8, word, "section")) {
                    try self.advance();
                    try self.advance();
                    const tok = try self.expect(.string, "section name");
                    section = stripQuotes(self.text(tok));
                    continue;
                }
                if (std.mem.eql(u8, word, "comdat")) {
                    try self.advance();
                    try self.advance();
                    if (self.check(.l_paren)) {
                        try self.advance();
                        comdat = try self.parseNamed(.comdat_id);
                        _ = try self.expect(.r_paren, "')' after comdat");
                    } else if (self.check(.comdat_id)) {
                        comdat = try self.parseNamed(.comdat_id);
                    } else {
                        // Bare `comdat` selects the comdat named after the global.
                        comdat = ref;
                    }
                    continue;
                }
                if (std.mem.eql(u8, word, "syncscope")) {
                    try self.advance();
                    try self.advance();
                    if (self.check(.l_paren)) _ = try self.skipBalancedRaw(.l_paren, .r_paren);
                    continue;
                }
            }
            break;
        }

        try self.expectEndOfRecord();
        try self.globals.append(.{
            .name = ref.name,
            .name_ref = ref,
            .modifiers = mods,
            .is_const = is_const,
            .ty = ty,
            .init = initializer,
            .alignment = alignment,
            .section = section,
            .comdat = comdat,
            .metadata = if (metadata.items.len == 0) &.{} else try metadata.toOwnedSlice(),
            .span = Span.join(start, self.prev_span),
        });
    }

    // ------------------------------------------------------------ declarations

    const Header = struct {
        mods: ast.GlobalModifiers = .{},
        ret_attrs: []const ast.Attr = &.{},
        ret: *const ast.Type,
        cc: ?[]const u8 = null,
        name_ref: ast.NamedRef,
        sig: ast.Signature = undefined,
    };

    fn parseDecl(self: *Parser) Error!void {
        const start = self.cur.span;
        try self.advance(); // declare
        const header = try self.parseFunctionHeader();
        const trailer = try self.parseFunctionTrailer(false);
        try self.expectEndOfRecord();

        try self.declares.append(.{
            .name = header.name_ref.name,
            .name_ref = header.name_ref,
            .modifiers = header.mods,
            .sig = header.sig,
            .attrs = trailer.attrs,
            .attr_groups = trailer.attr_groups,
            .metadata = trailer.metadata,
            .span = Span.join(start, self.prev_span),
        });
    }

    fn parseDefine(self: *Parser) Error!void {
        const start = self.cur.span;
        try self.advance(); // define
        const header = try self.parseFunctionHeader();
        const trailer = try self.parseFunctionTrailer(true);
        if (!self.check(.l_brace)) {
            return self.failMsg("expected '{{' to start function body, found {s} '{s}'", .{
                lexer.kindName(self.cur.kind), self.curText(),
            });
        }
        try self.advance(); // '{'
        const blocks = try self.parseFunctionBody();
        const end = self.prev_span;

        var func = ast.Function{
            .name = header.name_ref.name,
            .name_ref = header.name_ref,
            .modifiers = header.mods,
            .sig = header.sig,
            .blocks = blocks,
            .attrs = trailer.attrs,
            .attr_groups = trailer.attr_groups,
            .metadata = trailer.metadata,
            .span = Span.join(start, end),
        };
        func.sig.span = Span.join(start, end);
        try self.functions.append(func);
    }

    /// Parse `[modifiers] [cconv] [ret attrs] <ret ty> @name(<params>)`.
    fn parseFunctionHeader(self: *Parser) Error!Header {
        var mods = ast.GlobalModifiers{};
        try self.parseGlobalModifiers(&mods, false);

        var attrs = std.ArrayList(ast.Attr).init(self.allocator);
        var cc: ?[]const u8 = null;
        while (self.cur.kind == .identifier) {
            const word = self.curText();
            if (cc == null and isCallConv(word)) {
                cc = word;
                try self.advance();
                continue;
            }
            if (try self.tryParseAttr(&attrs)) continue;
            break;
        }
        const ret = try self.parseType();
        const name_ref = try self.parseNamed(.global_id);
        const sig = try self.parseParams(ret, attrs.items, cc);
        return .{
            .mods = mods,
            .ret_attrs = sig.ret_attrs,
            .ret = ret,
            .cc = cc,
            .name_ref = name_ref,
            .sig = sig,
        };
    }

    fn parseParams(self: *Parser, ret: *const ast.Type, ret_attrs: []const ast.Attr, cc: ?[]const u8) Error!ast.Signature {
        const start = self.prev_span;
        _ = try self.expect(.l_paren, "'(' after function name");
        var params = std.ArrayList(ast.Param).init(self.allocator);
        var varargs = false;

        if (!self.check(.r_paren)) {
            while (true) {
                if (self.check(.ellipsis)) {
                    varargs = true;
                    try self.advance();
                    break;
                }
                const param_start = self.cur.span;
                const ty = try self.parseType();
                // Legacy `(void)` spelling of an empty parameter list.
                if (ty.* == .void and params.items.len == 0 and self.check(.r_paren)) break;
                const attrs = try self.parseValueAttrs();
                var name: ?ast.NamedRef = null;
                if (self.check(.local_id)) name = try self.parseNamed(.local_id);
                try params.append(.{
                    .ty = ty,
                    .attrs = attrs,
                    .name = name,
                    .span = Span.join(param_start, self.prev_span),
                });
                if (self.check(.comma)) {
                    try self.advance();
                    continue;
                }
                break;
            }
        }
        _ = try self.expect(.r_paren, "')' after parameter list");

        return .{
            .ret = ret,
            .ret_attrs = ret_attrs,
            .params = try params.toOwnedSlice(),
            .is_varargs = varargs,
            .cc = cc,
            .span = Span.join(start, self.prev_span),
        };
    }

    const Trailer = struct {
        attrs: []const ast.Attr = &.{},
        attr_groups: []const u32 = &.{},
        metadata: []const ast.MetadataAttachment = &.{},
        alignment: ?u32 = null,
        section: ?[]const u8 = null,
        comdat: ?ast.NamedRef = null,
        gc: ?[]const u8 = null,
    };

    fn parseFunctionTrailer(self: *Parser, comptime until_brace: bool) Error!Trailer {
        var attrs = std.ArrayList(ast.Attr).init(self.allocator);
        var groups = std.ArrayList(u32).init(self.allocator);
        var metadata = std.ArrayList(ast.MetadataAttachment).init(self.allocator);
        var out = Trailer{};

        while (true) {
            if (until_brace and self.check(.l_brace)) break;
            if (self.cur.kind == .eof) {
                if (until_brace) return self.failMsg("unexpected end of file in function header", .{});
                break;
            }
            if (!until_brace and self.cur.line_start) break;

            switch (self.cur.kind) {
                .attr_group_id => {
                    const tok = self.cur;
                    const raw = self.text(tok);
                    const id = std.fmt.parseInt(u32, raw[1..], 10) catch
                        return self.fail(tok, "bad attribute group id '{s}'", .{raw});
                    try groups.append(id);
                    try self.advance();
                },
                .metadata_id => try metadata.append(try self.parseMetadataAttachment()),
                .string => {
                    // String attributes: `"frame-pointer"="all"`.
                    try self.advance();
                    if (self.check(.equals)) {
                        try self.advance();
                        if (self.check(.string) or self.check(.integer)) try self.advance();
                    }
                },
                .identifier => {
                    const word = self.curText();
                    if (std.mem.eql(u8, word, "align")) {
                        try self.advance();
                        out.alignment = try self.parseU32();
                        continue;
                    }
                    if (std.mem.eql(u8, word, "section")) {
                        try self.advance();
                        const tok = try self.expect(.string, "section name");
                        out.section = stripQuotes(self.text(tok));
                        continue;
                    }
                    if (std.mem.eql(u8, word, "comdat")) {
                        try self.advance();
                        if (self.check(.l_paren)) {
                            try self.advance();
                            out.comdat = try self.parseNamed(.comdat_id);
                            _ = try self.expect(.r_paren, "')' after comdat");
                        } else if (self.check(.comdat_id)) {
                            out.comdat = try self.parseNamed(.comdat_id);
                        }
                        continue;
                    }
                    if (std.mem.eql(u8, word, "gc")) {
                        try self.advance();
                        const tok = try self.expect(.string, "gc name");
                        out.gc = stripQuotes(self.text(tok));
                        continue;
                    }
                    if (std.mem.eql(u8, word, "prefix") or
                        std.mem.eql(u8, word, "prologue") or
                        std.mem.eql(u8, word, "personality"))
                    {
                        try self.advance();
                        _ = try self.parseTypedValue();
                        continue;
                    }
                    if (std.mem.eql(u8, word, "unnamed_addr") or std.mem.eql(u8, word, "local_unnamed_addr")) {
                        try self.advance();
                        continue;
                    }
                    if (isCallConv(word)) {
                        try self.advance();
                        continue;
                    }
                    if (try self.tryParseAttr(&attrs)) continue;
                    // Unknown word: keep it as an opaque attribute so that new
                    // function attributes do not break parsing.
                    try attrs.append(.{ .span = self.cur.span, .kind = .{ .opaque_ = word } });
                    try self.advance();
                    if (self.check(.l_paren)) _ = try self.skipBalancedRaw(.l_paren, .r_paren);
                },
                else => {
                    return self.fail(self.cur, "unexpected {s} '{s}' in function header", .{
                        lexer.kindName(self.cur.kind), self.curText(),
                    });
                },
            }
        }

        out.attrs = if (attrs.items.len == 0) &.{} else try attrs.toOwnedSlice();
        out.attr_groups = if (groups.items.len == 0) &.{} else try groups.toOwnedSlice();
        out.metadata = if (metadata.items.len == 0) &.{} else try metadata.toOwnedSlice();
        return out;
    }

    // ------------------------------------------------------------ function body

    fn parseFunctionBody(self: *Parser) Error![]const ast.BasicBlock {
        var blocks = std.ArrayList(ast.BasicBlock).init(self.allocator);
        var instrs = std.ArrayList(ast.Instruction).init(self.allocator);
        var label: ?ast.NamedRef = null;
        var block_start = self.cur.span;

        while (true) {
            if (self.cur.kind == .eof) {
                return self.failMsg("unterminated function body (missing '}}')", .{});
            }
            if (self.check(.r_brace)) {
                try blocks.append(.{
                    .label = label,
                    .instructions = try instrs.toOwnedSlice(),
                    .span = Span.join(block_start, self.prev_span),
                });
                try self.advance(); // '}'
                break;
            }
            if (self.check(.hash_ident)) {
                // `#dbg_value(...)` style debug records: trivia for lowering.
                const record_start = self.cur.span.start;
                try self.advance();
                while (self.cur.kind == .l_paren) {
                    _ = try self.skipBalancedRaw(.l_paren, .r_paren);
                }
                try self.opaque_records.append(.{
                    .keyword = "dbg_record",
                    .raw = self.sliceRange(record_start, self.prev_span.end),
                    .span = .{ .start = record_start, .end = self.prev_span.end, .line = self.cur.span.line, .column = self.cur.span.column },
                });
                continue;
            }
            if (try self.tryParseLabel()) |lbl| {
                if (label != null or instrs.items.len != 0) {
                    try blocks.append(.{
                        .label = label,
                        .instructions = try instrs.toOwnedSlice(),
                        .span = Span.join(block_start, self.prev_span),
                    });
                    instrs = std.ArrayList(ast.Instruction).init(self.allocator);
                }
                label = lbl;
                block_start = lbl.span;
                continue;
            }

            try instrs.append(try self.parseInstruction());
        }
        return try blocks.toOwnedSlice();
    }

    /// If the current position is a block label (`name:` or `42:`), consume it
    /// and return it; otherwise return null.
    fn tryParseLabel(self: *Parser) Error!?ast.NamedRef {
        if (!self.checkNext(.colon)) return null;
        if (self.cur.kind == .identifier) {
            const tok = self.cur;
            const name = self.text(tok);
            try self.advance(); // name
            try self.advance(); // ':'
            return ast.NamedRef{ .name = name, .span = tok.span };
        }
        if (self.cur.kind == .integer) {
            const tok = self.cur;
            const name = self.text(tok);
            const number = std.fmt.parseInt(u32, name, 10) catch null;
            try self.advance();
            try self.advance();
            return ast.NamedRef{ .name = name, .number = number, .span = tok.span };
        }
        if (self.cur.kind == .string) {
            // Quoted block label: `"entry block":`.
            const tok = self.cur;
            const raw = self.text(tok);
            const name = raw[1 .. raw.len - 1];
            try self.advance();
            try self.advance();
            return ast.NamedRef{ .name = name, .quoted = true, .span = tok.span };
        }
        return null;
    }

    // ------------------------------------------------------------ instructions

    fn parseInstruction(self: *Parser) Error!ast.Instruction {
        const start = self.cur.span;
        var result: ?ast.NamedRef = null;
        if (self.cur.kind == .local_id and self.next_tok.kind == .equals) {
            result = try self.parseNamed(.local_id);
            _ = try self.expect(.equals, "'='");
        }

        const tok = self.cur;
        if (tok.kind != .identifier) {
            return self.fail(tok, "expected an instruction mnemonic, found {s} '{s}'", .{
                lexer.kindName(tok.kind), self.curText(),
            });
        }
        const word = self.text(tok);
        try self.advance();

        var op: ast.Op = undefined;
        if (std.mem.eql(u8, word, "alloca")) {
            op = .{ .alloca = try self.parseAlloca(tok.span) };
        } else if (std.mem.eql(u8, word, "load")) {
            op = .{ .load = try self.parseLoad(tok.span) };
        } else if (std.mem.eql(u8, word, "store")) {
            op = .{ .store = try self.parseStore(tok.span) };
        } else if (std.mem.eql(u8, word, "getelementptr")) {
            op = .{ .gep = try self.parseGep(tok.span) };
        } else if (std.mem.eql(u8, word, "phi")) {
            op = .{ .phi = try self.parsePhi(tok.span) };
        } else if (std.mem.eql(u8, word, "br")) {
            op = .{ .br = try self.parseBr(tok.span) };
        } else if (std.mem.eql(u8, word, "switch")) {
            op = .{ .switch_ = try self.parseSwitch(tok.span) };
        } else if (std.mem.eql(u8, word, "ret")) {
            op = .{ .ret = try self.parseRet(tok.span) };
        } else if (std.mem.eql(u8, word, "unreachable")) {
            op = .{ .unreachable_ = tok.span };
        } else if (std.mem.eql(u8, word, "select")) {
            op = .{ .select = try self.parseSelect(tok.span) };
        } else if (std.mem.eql(u8, word, "extractvalue")) {
            op = .{ .extractvalue = try self.parseExtractValue(tok.span) };
        } else if (std.mem.eql(u8, word, "icmp")) {
            op = .{ .icmp = try self.parseIcmp(tok.span) };
        } else if (std.mem.eql(u8, word, "fcmp")) {
            op = .{ .fcmp = try self.parseFcmp(tok.span) };
        } else if (std.mem.eql(u8, word, "fneg")) {
            op = .{ .fneg = try self.parseUnary(tok.span) };
        } else if (std.mem.eql(u8, word, "freeze")) {
            op = .{ .freeze = try self.parseUnary(tok.span) };
        } else if (binaryOpFromWord(word)) |bop| {
            op = .{ .binary = try self.parseBinary(bop, tok.span) };
        } else if (castOpFromWord(word)) |cop| {
            op = .{ .cast = try self.parseCast(cop, tok.span) };
        } else if (std.mem.eql(u8, word, "call") or
            std.mem.eql(u8, word, "callbr") or
            std.mem.eql(u8, word, "tail") or
            std.mem.eql(u8, word, "musttail") or
            std.mem.eql(u8, word, "notail"))
        {
            op = .{ .call = try self.parseCall(word, tok.span) };
        } else {
            return self.fail(tok, "unsupported instruction '{s}'", .{word});
        }

        var instr = ast.Instruction{
            .result = result,
            .span = Span.join(start, self.prev_span),
            .op = op,
        };
        try self.parseInstructionMetadata(&instr);
        try self.validateResult(&instr, tok);
        try self.expectEndOfRecord();
        return instr;
    }

    fn validateResult(self: *Parser, instr: *const ast.Instruction, mnemonic_tok: Token) Error!void {
        const needs_result = switch (instr.op) {
            .alloca, .load, .gep, .phi, .select, .extractvalue, .icmp, .fcmp, .fneg, .freeze, .binary, .cast => true,
            .call => |c| !c.ret.isVoid(),
            else => false,
        };
        if (needs_result and instr.result == null) {
            return self.fail(mnemonic_tok, "'{s}' requires a result value", .{instr.mnemonic()});
        }
    }

    fn parseInstructionMetadata(self: *Parser, instr: *ast.Instruction) Error!void {
        var list = std.ArrayList(ast.MetadataAttachment).init(self.allocator);
        while (self.check(.comma) and self.next_tok.kind == .metadata_id) {
            try self.advance(); // ','
            try list.append(try self.parseMetadataAttachment());
        }
        if (list.items.len != 0) instr.metadata = try list.toOwnedSlice();
    }

    fn parseAlloca(self: *Parser, start: Span) Error!ast.Alloca {
        var out = ast.Alloca{ .ty = undefined, .span = start };
        while (self.cur.kind == .identifier) {
            if (std.mem.eql(u8, self.curText(), "inalloca")) {
                out.inalloca = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, self.curText(), "swifterror")) {
                out.swifterror = true;
                try self.advance();
                continue;
            }
            break;
        }
        out.ty = try self.parseType();
        while (self.check(.comma)) {
            if (self.next_tok.kind == .metadata_id) break;
            if (isNextWord(self, "align")) {
                try self.advance();
                try self.advance();
                out.alignment = try self.parseU32();
                continue;
            }
            if (isNextWord(self, "addrspace")) {
                try self.advance();
                try self.advance();
                _ = try self.expect(.l_paren, "'(' after addrspace");
                out.addr_space = try self.parseU32();
                _ = try self.expect(.r_paren, "')' after addrspace");
                continue;
            }
            if (out.count != null) break;
            try self.advance(); // ','
            out.count = try self.parseTypedValue();
        }
        out.span = Span.join(start, self.prev_span);
        return out;
    }

    fn parseLoad(self: *Parser, start: Span) Error!ast.Load {
        var out = ast.Load{ .ty = undefined, .ptr = undefined, .span = start };
        while (self.cur.kind == .identifier) {
            if (std.mem.eql(u8, self.curText(), "volatile")) {
                out.is_volatile = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, self.curText(), "atomic")) {
                out.is_atomic = true;
                try self.advance();
                continue;
            }
            break;
        }
        out.ty = try self.parseType();
        _ = try self.expect(.comma, "',' after load type");
        out.ptr = try self.parseTypedValue();
        if (self.cur.kind == .identifier and isAtomicOrdering(self.curText())) {
            out.ordering = self.curText();
            try self.advance();
        }
        try self.parseAlignClause(&out.alignment);
        out.span = Span.join(start, self.prev_span);
        return out;
    }

    fn parseStore(self: *Parser, start: Span) Error!ast.Store {
        var out = ast.Store{ .ty = undefined, .value = undefined, .ptr = undefined, .span = start };
        while (self.cur.kind == .identifier) {
            if (std.mem.eql(u8, self.curText(), "volatile")) {
                out.is_volatile = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, self.curText(), "atomic")) {
                out.is_atomic = true;
                try self.advance();
                continue;
            }
            break;
        }
        out.ty = try self.parseType();
        out.value = try self.parseTypedValueWithType(out.ty);
        _ = try self.expect(.comma, "',' between store value and pointer");
        out.ptr = try self.parseTypedValue();
        if (self.cur.kind == .identifier and isAtomicOrdering(self.curText())) {
            out.ordering = self.curText();
            try self.advance();
        }
        try self.parseAlignClause(&out.alignment);
        out.span = Span.join(start, self.prev_span);
        return out;
    }

    fn parseAlignClause(self: *Parser, out: *?u32) Error!void {
        if (self.check(.comma) and isNextWord(self, "align")) {
            try self.advance();
            try self.advance();
            out.* = try self.parseU32();
        }
    }

    fn parseGep(self: *Parser, start: Span) Error!ast.Gep {
        var out = ast.Gep{ .src = undefined, .ptr = undefined, .span = start };
        while (self.cur.kind == .identifier) {
            const word = self.curText();
            if (std.mem.eql(u8, word, "inbounds")) {
                out.inbounds = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "nuw")) {
                out.nuw = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "nusw") or std.mem.eql(u8, word, "inrange")) {
                try self.advance();
                continue;
            }
            break;
        }

        var indices = std.ArrayList(ast.TypedValue).init(self.allocator);
        if (self.check(.l_paren)) {
            try self.advance(); // '('
            out.src = try self.parseType();
            _ = try self.expect(.comma, "',' after getelementptr element type");
            out.ptr = try self.parseTypedValue();
            while (self.check(.comma) and self.next_tok.kind != .metadata_id) {
                try self.advance();
                try indices.append(try self.parseTypedValue());
            }
            _ = try self.expect(.r_paren, "')' to close getelementptr constant expression");
        } else {
            out.src = try self.parseType();
            _ = try self.expect(.comma, "',' after getelementptr element type");
            out.ptr = try self.parseTypedValue();
            while (self.check(.comma) and self.next_tok.kind != .metadata_id) {
                try self.advance();
                try indices.append(try self.parseTypedValue());
            }
        }
        out.indices = try indices.toOwnedSlice();
        out.span = Span.join(start, self.prev_span);
        return out;
    }

    fn parsePhi(self: *Parser, start: Span) Error!ast.Phi {
        try self.skipFastMathFlags();
        const ty = try self.parseType();
        var incoming = std.ArrayList(ast.PhiIncoming).init(self.allocator);
        while (true) {
            const inc_start = self.cur.span;
            _ = try self.expect(.l_bracket, "'[' in phi incoming block");
            const value = try self.parseValue(ty);
            _ = try self.expect(.comma, "',' in phi incoming block");
            const block = try self.parseLabelRef();
            _ = try self.expect(.r_bracket, "']' in phi incoming block");
            try incoming.append(.{
                .value = value,
                .block = block,
                .span = Span.join(inc_start, self.prev_span),
            });
            if (self.check(.comma) and self.next_tok.kind != .metadata_id) {
                try self.advance();
                continue;
            }
            break;
        }
        return .{ .ty = ty, .incoming = try incoming.toOwnedSlice(), .span = Span.join(start, self.prev_span) };
    }

    fn parseBr(self: *Parser, start: Span) Error!ast.Br {
        if (self.isWord("label")) {
            try self.advance();
            const target = try self.parseLabelRef();
            return .{ .unconditional = .{ .target = target, .span = Span.join(start, self.prev_span) } };
        }
        const cond = try self.parseTypedValue();
        _ = try self.expect(.comma, "',' after branch condition");
        _ = try self.expectWord("label");
        const if_true = try self.parseLabelRef();
        _ = try self.expect(.comma, "',' between branch targets");
        _ = try self.expectWord("label");
        const if_false = try self.parseLabelRef();
        return .{ .conditional = .{
            .cond = cond,
            .if_true = if_true,
            .if_false = if_false,
            .span = Span.join(start, self.prev_span),
        } };
    }

    fn parseSwitch(self: *Parser, start: Span) Error!ast.Switch {
        const cond = try self.parseTypedValue();
        _ = try self.expect(.comma, "',' after switch condition");
        _ = try self.expectWord("label");
        const default = try self.parseLabelRef();
        _ = try self.expect(.l_bracket, "'[' starting switch cases");
        var cases = std.ArrayList(ast.SwitchCase).init(self.allocator);
        while (!self.check(.r_bracket)) {
            if (self.cur.kind == .eof) return self.failMsg("unterminated switch case list", .{});
            const case_start = self.cur.span;
            const value = try self.parseTypedValue();
            _ = try self.expect(.comma, "',' between switch case value and label");
            _ = try self.expectWord("label");
            const target = try self.parseLabelRef();
            try cases.append(.{
                .value = value,
                .target = target,
                .span = Span.join(case_start, self.prev_span),
            });
            if (self.check(.comma)) {
                if (self.next_tok.kind == .metadata_id) break;
                try self.advance();
            }
        }
        _ = try self.expect(.r_bracket, "']' closing switch cases");
        return .{ .cond = cond, .default = default, .cases = try cases.toOwnedSlice(), .span = Span.join(start, self.prev_span) };
    }

    fn parseRet(self: *Parser, start: Span) Error!ast.Ret {
        if (self.isWord("void")) {
            try self.advance();
            return .{ .void = Span.join(start, self.prev_span) };
        }
        const value = try self.parseTypedValue();
        return .{ .value = value };
    }

    fn parseSelect(self: *Parser, start: Span) Error!ast.Select {
        try self.skipFastMathFlags();
        const cond = try self.parseTypedValue();
        _ = try self.expect(.comma, "',' after select condition");
        const if_true = try self.parseTypedValue();
        _ = try self.expect(.comma, "',' between select operands");
        const if_false = try self.parseTypedValue();
        return .{
            .cond = cond,
            .if_true = if_true,
            .if_false = if_false,
            .span = Span.join(start, self.prev_span),
        };
    }

    fn parseExtractValue(self: *Parser, start: Span) Error!ast.ExtractValue {
        const aggregate = try self.parseTypedValue();
        var indices = std.ArrayList(u32).init(self.allocator);
        while (self.check(.comma)) {
            if (self.next_tok.kind == .metadata_id) break;
            try self.advance();
            try indices.append(try self.parseU32());
        }
        return .{ .aggregate = aggregate, .indices = try indices.toOwnedSlice(), .span = Span.join(start, self.prev_span) };
    }

    fn parseIcmp(self: *Parser, start: Span) Error!ast.Icmp {
        const pred = icmpPredFromWord(self.curText()) orelse
            return self.failMsg("unknown icmp predicate '{s}'", .{self.curText()});
        try self.advance();
        // LLVM 19 adds the `samesign` flag on icmp.
        if (self.isWord("samesign")) try self.advance();
        const ty = try self.parseType();
        const lhs = try self.parseValue(ty);
        _ = try self.expect(.comma, "',' between icmp operands");
        const rhs = try self.parseValue(ty);
        return .{ .pred = pred, .ty = ty, .lhs = lhs, .rhs = rhs, .span = Span.join(start, self.prev_span) };
    }

    fn parseFcmp(self: *Parser, start: Span) Error!ast.Fcmp {
        var fast = false;
        if (self.isFastMathFlag(self.curText())) {
            fast = true;
            try self.skipFastMathFlags();
        }
        const pred = fcmpPredFromWord(self.curText()) orelse
            return self.failMsg("unknown fcmp predicate '{s}'", .{self.curText()});
        try self.advance();
        const ty = try self.parseType();
        const lhs = try self.parseValue(ty);
        _ = try self.expect(.comma, "',' between fcmp operands");
        const rhs = try self.parseValue(ty);
        return .{
            .pred = pred,
            .ty = ty,
            .lhs = lhs,
            .rhs = rhs,
            .fast = fast,
            .span = Span.join(start, self.prev_span),
        };
    }

    fn parseUnary(self: *Parser, start: Span) Error!ast.Unary {
        try self.skipFastMathFlags();
        const ty = try self.parseType();
        const value = try self.parseValue(ty);
        return .{ .ty = ty, .value = value, .span = Span.join(start, self.prev_span) };
    }

    fn parseBinary(self: *Parser, op: ast.BinaryOp, start: Span) Error!ast.Binary {
        var out = ast.Binary{
            .op = op,
            .ty = undefined,
            .lhs = undefined,
            .rhs = undefined,
            .span = start,
        };
        while (self.cur.kind == .identifier) {
            const word = self.curText();
            if (std.mem.eql(u8, word, "nuw")) {
                out.nuw = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "nsw")) {
                out.nsw = true;
                try self.advance();
                continue;
            }
            if (std.mem.eql(u8, word, "exact")) {
                out.exact = true;
                try self.advance();
                continue;
            }
            if (self.isFastMathFlag(word)) {
                out.fast = true;
                try self.advance();
                continue;
            }
            break;
        }
        out.ty = try self.parseType();
        out.lhs = try self.parseValue(out.ty);
        _ = try self.expect(.comma, "',' between operands");
        out.rhs = try self.parseValue(out.ty);
        out.span = Span.join(start, self.prev_span);
        return out;
    }

    fn parseCast(self: *Parser, op: ast.CastOp, start: Span) Error!ast.Cast {
        var nonneg = false;
        if (self.isWord("nneg")) {
            nonneg = true;
            try self.advance();
        }
        const src = try self.parseType();
        const value = try self.parseValue(src);
        _ = try self.expectWord("to");
        const dst = try self.parseType();
        return .{
            .op = op,
            .src = src,
            .value = value,
            .dst = dst,
            .nonneg = nonneg,
            .span = Span.join(start, self.prev_span),
        };
    }

    fn parseCall(self: *Parser, mnemonic: []const u8, start: Span) Error!ast.Call {
        var out = ast.Call{ .callee = undefined, .ret = undefined, .span = start };
        var ret_attrs = std.ArrayList(ast.Attr).init(self.allocator);
        var fn_attrs = std.ArrayList(ast.Attr).init(self.allocator);
        var groups = std.ArrayList(u32).init(self.allocator);
        var bundles = std.ArrayList([]const u8).init(self.allocator);

        if (std.mem.eql(u8, mnemonic, "tail")) {
            out.is_tail = true;
        } else if (std.mem.eql(u8, mnemonic, "musttail")) {
            out.is_musttail = true;
        } else if (std.mem.eql(u8, mnemonic, "notail")) {
            out.is_notail = true;
        } else if (std.mem.eql(u8, mnemonic, "callbr")) {
            out.is_callbr = true;
        }

        if (!std.mem.eql(u8, mnemonic, "call") and !std.mem.eql(u8, mnemonic, "callbr")) {
            // `tail call`, `musttail call`, ...
            const callee_kw = try self.expect(.identifier, "'call'");
            const kw = self.text(callee_kw);
            if (std.mem.eql(u8, kw, "callbr")) {
                out.is_callbr = true;
            } else if (!std.mem.eql(u8, kw, "call")) {
                return self.fail(callee_kw, "expected 'call' after '{s}', found '{s}'", .{ mnemonic, kw });
            }
        }

        // Return attributes, calling convention and fast-math flags.
        while (self.cur.kind == .identifier) {
            const word = self.curText();
            if (out.cc == null and isCallConv(word)) {
                out.cc = word;
                try self.advance();
                continue;
            }
            if (self.isFastMathFlag(word)) {
                try self.advance();
                continue;
            }
            if (try self.tryParseAttr(&ret_attrs)) continue;
            break;
        }
        out.ret_attrs = if (ret_attrs.items.len == 0) &.{} else try ret_attrs.toOwnedSlice();

        const ty = try self.parseType();
        if (ty.* == .function) {
            out.fn_ty = ty;
            out.ret = ty.function.ret;
            out.is_varargs = ty.function.varargs;
        } else {
            out.ret = ty;
        }

        // Callee.
        if (self.check(.global_id)) {
            out.callee = .{ .direct = try self.parseNamed(.global_id) };
        } else if (self.check(.local_id)) {
            const ref = try self.parseNamed(.local_id);
            const ptr_ty = out.fn_ty orelse try self.newType(.{ .ptr = .{} });
            out.callee = .{ .indirect = .{ .ty = ptr_ty, .val = .{ .local = ref }, .span = ref.span } };
        } else if (self.isWord("asm")) {
            out.callee = .{ .asm_ = try self.parseAsm() };
        } else if (self.isWord("null")) {
            const span = self.cur.span;
            try self.advance();
            const ptr_ty = try self.newType(.{ .ptr = .{} });
            out.callee = .{ .indirect = .{ .ty = ptr_ty, .val = .{ .null_ = span }, .span = span } };
        } else {
            return self.failMsg("expected a callee after call type, found {s} '{s}'", .{
                lexer.kindName(self.cur.kind), self.curText(),
            });
        }

        // Arguments.
        _ = try self.expect(.l_paren, "'(' starting call arguments");
        var args = std.ArrayList(ast.TypedValue).init(self.allocator);
        while (!self.check(.r_paren)) {
            if (self.cur.kind == .eof) return self.failMsg("unterminated call argument list", .{});
            try args.append(try self.parseTypedValue());
            if (self.check(.comma)) {
                try self.advance();
                continue;
            }
            break;
        }
        _ = try self.expect(.r_paren, "')' closing call arguments");
        out.args = try args.toOwnedSlice();

        // Function attributes, attribute groups and operand bundles. `callbr`
        // prints its call-site attributes before the `to label` clause, so the
        // label list is parsed after this loop.
        while (true) {
            switch (self.cur.kind) {
                .attr_group_id => {
                    const tok = self.cur;
                    const raw = self.text(tok);
                    const id = std.fmt.parseInt(u32, raw[1..], 10) catch
                        return self.fail(tok, "bad attribute group id '{s}'", .{raw});
                    try groups.append(id);
                    try self.advance();
                },
                .l_bracket => {
                    if (out.is_callbr) break;
                    try bundles.append(try self.skipBalancedRaw(.l_bracket, .r_bracket));
                },
                .identifier => {
                    const word = self.curText();
                    if (isCallConv(word)) {
                        try self.advance();
                        continue;
                    }
                    if (self.isFastMathFlag(word)) {
                        try self.advance();
                        continue;
                    }
                    if (try self.tryParseAttr(&fn_attrs)) continue;
                    break;
                },
                else => break,
            }
        }
        if (out.is_callbr) {
            _ = try self.expectWord("to");
            _ = try self.expectWord("label");
            var targets = std.ArrayList(ast.NamedRef).init(self.allocator);
            try targets.append(try self.parseLabelRef());
            _ = try self.expect(.l_bracket, "'[' listing callbr labels");
            while (!self.check(.r_bracket)) {
                if (self.cur.kind == .eof) return self.failMsg("unterminated callbr label list", .{});
                _ = try self.expectWord("label");
                try targets.append(try self.parseLabelRef());
                if (self.check(.comma)) try self.advance();
            }
            _ = try self.expect(.r_bracket, "']' closing callbr labels");
            out.callbr_targets = try targets.toOwnedSlice();
        }

        out.fn_attrs = if (fn_attrs.items.len == 0) &.{} else try fn_attrs.toOwnedSlice();
        out.attr_groups = if (groups.items.len == 0) &.{} else try groups.toOwnedSlice();
        out.operand_bundles = if (bundles.items.len == 0) &.{} else try bundles.toOwnedSlice();
        out.span = Span.join(start, self.prev_span);
        return out;
    }

    fn parseAsm(self: *Parser) Error!ast.AsmValue {
        const start = self.cur.span;
        _ = try self.expectWord("asm");
        var out = ast.AsmValue{ .span = start };
        while (self.cur.kind == .identifier) {
            const word = self.curText();
            if (std.mem.eql(u8, word, "sideeffect")) {
                out.has_side_effects = true;
            } else if (std.mem.eql(u8, word, "alignstack")) {
                out.align_stack = true;
            } else if (std.mem.eql(u8, word, "inteldialect")) {
                out.intel_dialect = true;
            } else if (std.mem.eql(u8, word, "unwind")) {
                out.unwind = true;
            } else {
                break;
            }
            try self.advance();
        }
        const tmpl = try self.expect(.string, "inline asm template");
        out.template = stripQuotes(self.text(tmpl));
        if (self.check(.comma)) {
            try self.advance();
            const cons = try self.expect(.string, "inline asm constraints");
            out.constraints = stripQuotes(self.text(cons));
        }
        out.raw = self.sliceRange(start.start, self.prev_span.end);
        out.span = Span.join(start, self.prev_span);
        return out;
    }


    // ------------------------------------------------------------------- types

    /// Parse a type, including a trailing function-type parameter list.
    pub fn parseType(self: *Parser) Error!*const ast.Type {
        const start = self.cur.span;
        const ty = try self.parsePrimaryType();
        if (self.check(.l_paren)) return self.parseFunctionTypeSuffix(ty, start);
        return ty;
    }

    fn parseFunctionTypeSuffix(self: *Parser, ret: *const ast.Type, start: Span) Error!*const ast.Type {
        _ = try self.expect(.l_paren, "'(' starting function type");
        var params = std.ArrayList(*const ast.Type).init(self.allocator);
        var varargs = false;
        if (!self.check(.r_paren)) {
            while (true) {
                if (self.check(.ellipsis)) {
                    varargs = true;
                    try self.advance();
                    break;
                }
                try params.append(try self.parseType());
                if (self.check(.comma)) {
                    try self.advance();
                    continue;
                }
                break;
            }
        }
        _ = try self.expect(.r_paren, "')' closing function type");
        return self.newType(.{ .function = .{
            .ret = ret,
            .params = try params.toOwnedSlice(),
            .varargs = varargs,
            .span = Span.join(start, self.prev_span),
        } });
    }

    fn parsePrimaryType(self: *Parser) Error!*const ast.Type {
        try self.enter();
        defer self.leave();

        const tok = self.cur;
        switch (tok.kind) {
            .l_bracket => {
                try self.advance();
                const count_tok = try self.expect(.integer, "array element count");
                const count = std.fmt.parseInt(u64, self.text(count_tok), 10) catch
                    return self.fail(count_tok, "bad array element count '{s}'", .{self.text(count_tok)});
                _ = try self.expectWord("x");
                const elem = try self.parseType();
                _ = try self.expect(.r_bracket, "']' closing array type");
                return self.newType(.{ .array = .{
                    .count = count,
                    .elem = elem,
                    .span = Span.join(tok.span, self.prev_span),
                } });
            },
            .l_brace => {
                try self.advance(); // '{'
                const fields = try self.parseStructFields(.r_brace);
                _ = try self.expect(.r_brace, "'}' closing struct type");
                return self.newType(.{ .struct_ = .{
                    .fields = fields,
                    .is_packed = false,
                    .span = Span.join(tok.span, self.prev_span),
                } });
            },
            .l_angle => {
                try self.advance();
                if (self.check(.l_brace)) {
                    try self.advance();
                    const fields = try self.parseStructFields(.r_brace);
                    _ = try self.expect(.r_brace, "'}' closing packed struct type");
                    _ = try self.expect(.r_angle, "'>' closing packed struct type");
                    return self.newType(.{ .struct_ = .{
                        .fields = fields,
                        .is_packed = true,
                        .span = Span.join(tok.span, self.prev_span),
                    } });
                }
                var scalable = false;
                if (self.isWord("vscale")) {
                    scalable = true;
                    try self.advance();
                    _ = try self.expectWord("x");
                }
                const count_tok = try self.expect(.integer, "vector element count");
                const count = std.fmt.parseInt(u64, self.text(count_tok), 10) catch
                    return self.fail(count_tok, "bad vector element count '{s}'", .{self.text(count_tok)});
                _ = try self.expectWord("x");
                const elem = try self.parseType();
                _ = try self.expect(.r_angle, "'>' closing vector type");
                return self.newType(.{ .vector = .{
                    .count = count,
                    .elem = elem,
                    .scalable = scalable,
                    .span = Span.join(tok.span, self.prev_span),
                } });
            },
            .local_id => {
                const ref = try self.parseNamed(.local_id);
                return self.newType(.{ .named = .{ .name = ref.name, .span = ref.span } });
            },
            .identifier => {
                const word = self.text(tok);
                if (std.mem.eql(u8, word, "void")) {
                    try self.advance();
                    return self.newType(.void);
                }
                if (std.mem.eql(u8, word, "metadata")) {
                    try self.advance();
                    return self.newType(.metadata);
                }
                if (std.mem.eql(u8, word, "token")) {
                    try self.advance();
                    return self.newType(.token);
                }
                if (std.mem.eql(u8, word, "label")) {
                    try self.advance();
                    return self.newType(.label);
                }
                if (std.mem.eql(u8, word, "opaque")) {
                    try self.advance();
                    return self.newType(.{ .struct_ = .{
                        .is_opaque = true,
                        .span = tok.span,
                    } });
                }
                if (std.mem.eql(u8, word, "ptr")) {
                    try self.advance();
                    var addr_space: u32 = 0;
                    if (self.isWord("addrspace")) {
                        try self.advance();
                        _ = try self.expect(.l_paren, "'(' after addrspace");
                        addr_space = try self.parseU32();
                        _ = try self.expect(.r_paren, "')' after addrspace");
                    }
                    return self.newType(.{ .ptr = .{ .addr_space = addr_space, .span = Span.join(tok.span, self.prev_span) } });
                }
                if (floatKindFromWord(word)) |kind| {
                    try self.advance();
                    return self.newType(.{ .float = .{ .kind = kind, .span = tok.span } });
                }
                if (word.len > 1 and word[0] == 'i' and allDigits(word[1..])) {
                    const bits = std.fmt.parseInt(u32, word[1..], 10) catch
                        return self.fail(tok, "bad integer type '{s}'", .{word});
                    if (bits == 0) return self.fail(tok, "integer type must have at least one bit", .{});
                    try self.advance();
                    return self.newType(.{ .int = .{ .bits = bits, .span = tok.span } });
                }
                return self.fail(tok, "unknown type '{s}'", .{word});
            },
            else => return self.fail(tok, "expected a type, found {s} '{s}'", .{
                lexer.kindName(tok.kind), self.curText(),
            }),
        }
    }

    fn parseStructFields(self: *Parser, close: Kind) Error![]const *const ast.Type {
        var fields = std.ArrayList(*const ast.Type).init(self.allocator);
        while (!self.check(close)) {
            if (self.cur.kind == .eof) return self.failMsg("unterminated struct type", .{});
            try fields.append(try self.parseType());
            if (self.check(.comma)) {
                try self.advance();
                continue;
            }
            break;
        }
        if (fields.items.len == 0) return &.{};
        return try fields.toOwnedSlice();
    }

    // ----------------------------------------------------------------- values

    fn parseTypedValue(self: *Parser) Error!ast.TypedValue {
        const start = self.cur.span;
        const ty = try self.parseType();
        return self.parseTypedValueWithTypeAndStart(ty, start);
    }

    fn parseTypedValueWithType(self: *Parser, ty: *const ast.Type) Error!ast.TypedValue {
        const start = self.prev_span;
        return self.parseTypedValueWithTypeAndStart(ty, start);
    }

    fn parseTypedValueWithTypeAndStart(self: *Parser, ty: *const ast.Type, start: Span) Error!ast.TypedValue {
        const attrs = try self.parseValueAttrs();
        const val = try self.parseValue(ty);
        return .{
            .ty = ty,
            .attrs = attrs,
            .val = val,
            .span = Span.join(start, self.prev_span),
        };
    }

    pub fn parseValue(self: *Parser, expected: ?*const ast.Type) Error!ast.Value {
        try self.enter();
        defer self.leave();

        const tok = self.cur;
        // `metadata ptr %x`: a value wrapped as metadata (llvm.dbg.* arguments).
        if (expected) |ty| {
            if (ty.* == .metadata and tok.kind != .metadata_id and tok.kind != .bang) {
                const inner = try self.allocator.create(ast.TypedValue);
                inner.* = try self.parseTypedValue();
                return .{ .metadata_value = inner };
            }
        }
        switch (tok.kind) {
            .local_id => return .{ .local = try self.parseNamed(.local_id) },
            .global_id => return .{ .global = try self.parseNamed(.global_id) },
            .integer => return .{ .int = try self.parseIntLiteral() },
            .float_lit => return .{ .float = try self.parseFloatLiteral(expected) },
            .string, .cstring => return .{ .string = try self.parseStringLiteral() },
            .l_brace, .l_bracket, .l_angle => return .{ .aggregate = try self.parseAggregate() },
            .metadata_id, .bang => {
                if (expected) |ty| {
                    if (ty.* == .metadata) return .{ .metadata = try self.parseMetadataRef() };
                }
                return self.fail(tok, "unexpected metadata reference '{s}' in value position", .{self.curText()});
            },
            else => return self.fail(tok, "expected a value, found {s} '{s}'", .{
                lexer.kindName(tok.kind), self.curText(),
            }),
            .identifier => {
                const word = self.curText();
                if (std.mem.eql(u8, word, "null") or std.mem.eql(u8, word, "none")) {
                    try self.advance();
                    return .{ .null_ = tok.span };
                }
                if (std.mem.eql(u8, word, "undef")) {
                    try self.advance();
                    return .{ .undef = tok.span };
                }
                if (std.mem.eql(u8, word, "poison")) {
                    try self.advance();
                    return .{ .poison = tok.span };
                }
                if (std.mem.eql(u8, word, "zeroinitializer")) {
                    try self.advance();
                    return .{ .zeroinitializer = tok.span };
                }
                if (std.mem.eql(u8, word, "true") or std.mem.eql(u8, word, "false")) {
                    const one = std.mem.eql(u8, word, "true");
                    try self.advance();
                    return .{ .int = .{
                        .span = tok.span,
                        .digits = if (one) "1" else "0",
                        .magnitude = if (one) 1 else 0,
                    } };
                }
                if (hexIntWord(word)) |hex| {
                    try self.advance();
                    var magnitude: u128 = 0;
                    var overflow = false;
                    for (hex) |c| {
                        const d = std.fmt.charToDigit(c, 16) catch 0;
                        if (magnitude > (std.math.maxInt(u128) >> 4)) {
                            overflow = true;
                            break;
                        }
                        magnitude = (magnitude << 4) | d;
                    }
                    return .{ .int = .{
                        .span = tok.span,
                        .digits = hex,
                        .hex = true,
                        .magnitude = magnitude,
                        .overflow = overflow,
                    } };
                }
                if (std.mem.eql(u8, word, "asm")) return .{ .asm_ = try self.parseAsm() };
                if (std.mem.eql(u8, word, "blockaddress")) {
                    try self.advance();
                    _ = try self.expect(.l_paren, "'(' after blockaddress");
                    const function = try self.parseNamed(.global_id);
                    _ = try self.expect(.comma, "',' in blockaddress");
                    const block = try self.parseNamed(.local_id);
                    _ = try self.expect(.r_paren, "')' after blockaddress");
                    return .{ .blockaddress = .{
                        .span = Span.join(tok.span, self.prev_span),
                        .function = function,
                        .block = block,
                    } };
                }
                if (isConstExprWord(word)) return .{ .const_expr = try self.parseConstExpr() };
                return self.fail(tok, "unsupported value '{s}'", .{word});
            },
        }
    }

    fn parseIntLiteral(self: *Parser) Error!ast.IntLiteral {
        const tok = self.cur;
        const raw = self.text(tok);
        const negative = raw.len != 0 and raw[0] == '-';
        const digits = if (negative) raw[1..] else raw;
        var magnitude: u128 = 0;
        var overflow = false;
        for (digits) |c| {
            const d = std.fmt.charToDigit(c, 10) catch
                return self.fail(tok, "invalid digit '{c}' in integer literal", .{c});
            const mul = @mulWithOverflow(magnitude, @as(u128, 10));
            const add = @addWithOverflow(mul[0], @as(u128, d));
            if (mul[1] != 0 or add[1] != 0) {
                overflow = true;
                magnitude = std.math.maxInt(u128);
                break;
            }
            magnitude = add[0];
        }
        try self.advance();
        return .{ .span = tok.span, .digits = digits, .negative = negative, .magnitude = magnitude, .overflow = overflow };
    }

    fn parseFloatLiteral(self: *Parser, expected: ?*const ast.Type) Error!ast.FloatLiteral {
        const tok = self.cur;
        const raw = self.text(tok);
        var out = ast.FloatLiteral{ .span = tok.span, .raw = raw };

        const hex_at = std.mem.indexOf(u8, raw, "0x") orelse std.mem.indexOf(u8, raw, "0X");
        if (hex_at) |at| {
            out.form = .hex;
            var digits_start = at + 2;
            if (digits_start < raw.len and isHexSpecifier(raw[digits_start]) and
                digits_start + 1 < raw.len and std.ascii.isHex(raw[digits_start + 1]))
            {
                out.hex_spec = raw[digits_start];
                digits_start += 1;
            }
            var digits_end = digits_start;
            while (digits_end < raw.len and std.ascii.isHex(raw[digits_end])) digits_end += 1;
            const digits = raw[digits_start..digits_end];
            out.hex_digits = @intCast(@min(digits.len, 255));

            // Canonical width: the APFloat specifier wins, then the destination
            // type, then the digit count (LLVM prints 8 digits for float and
            // 16 for double).
            var width: u16 = 0;
            switch (out.hex_spec) {
                'H', 'R' => width = 16,
                'K' => width = 80,
                'L', 'M' => width = 128,
                else => {},
            }
            if (width == 0 and expected != null) {
                if (expected.?.floatKind()) |kind| width = kind.bits();
            }
            if (width == 0) width = @intCast(digits.len * 4);
            out.width = width;

            var bits: u128 = 0;
            var overflow = false;
            for (digits) |c| {
                const d = std.fmt.charToDigit(c, 16) catch 0;
                if (bits > (std.math.maxInt(u128) >> 4)) {
                    overflow = true;
                    break;
                }
                bits = (bits << 4) | d;
            }
            if (overflow) return self.fail(tok, "hexadecimal float constant is too wide", .{});
            // clang prints fp128 as two 64-bit words with the low word first;
            // normalize to the canonical big-endian bit pattern.
            if ((out.hex_spec == 'L' or out.hex_spec == 'M') and digits.len == 32) {
                const lo = bits & 0xFFFF_FFFF_FFFF_FFFF;
                const hi = bits >> 64;
                bits = (hi << 64) | lo;
                bits = (lo << 64) | hi;
            }
            // LLVM prints `float` hexadecimal constants using the 64-bit
            // double-precision spelling (16 hex digits) so the value survives
            // a print/parse round trip, e.g. `float 0x405147AE20000000` is
            // 69.12f, not the double 0x405147AE20000000. An 8-digit spelling
            // is the raw f32 bit pattern. Mirror the legacy `parseFloatBits`.
            if (width == 32 and digits.len > 8) {
                const d: f64 = @bitCast(@as(u64, @truncate(bits)));
                const f: f32 = @floatCast(d);
                bits = @as(u32, @bitCast(f));
            }
            if (raw.len != 0 and raw[0] == '-') bits |= @as(u128, 1) << @intCast(width - 1);
            out.bits = bits;
            out.exact = true;
            try self.advance();
            return out;
        }

        out.form = .decimal;
        const parsed = std.fmt.parseFloat(f64, raw) catch
            return self.fail(tok, "invalid floating point literal '{s}'", .{raw});
        out.value = parsed;
        if (expected) |ty| {
            if (ty.floatKind()) |kind| {
                out.width = kind.bits();
                switch (kind) {
                    .half => {
                        const half: f16 = @floatCast(parsed);
                        out.bits = @as(u16, @bitCast(half));
                        out.exact = true;
                    },
                    .bfloat => {
                        const single: f32 = @floatCast(parsed);
                        const bits32: u32 = @bitCast(single);
                        out.bits = bits32 >> 16;
                        out.exact = false;
                    },
                    .float => {
                        const single: f32 = @floatCast(parsed);
                        out.bits = @as(u32, @bitCast(single));
                        out.exact = true;
                    },
                    .double => {
                        out.bits = @as(u64, @bitCast(parsed));
                        out.exact = true;
                    },
                    .x86_fp80, .fp128, .ppc_fp128 => {
                        // Decimal spellings of these types are printed by LLVM
                        // in hexadecimal; keep the f64 approximation but flag
                        // it as inexact.
                        out.bits = @as(u64, @bitCast(parsed));
                        out.exact = false;
                    },
                }
            } else {
                out.width = 64;
                out.bits = @as(u64, @bitCast(parsed));
            }
        } else {
            out.width = 64;
            out.bits = @as(u64, @bitCast(parsed));
        }
        try self.advance();
        return out;
    }

    fn parseStringLiteral(self: *Parser) Error!ast.StringLiteral {
        const tok = self.cur;
        const raw = self.text(tok);
        const is_c = tok.kind == .cstring;
        const inner = if (is_c) raw[2 .. raw.len - 1] else raw[1 .. raw.len - 1];
        try self.advance();
        return .{ .span = tok.span, .raw = inner, .is_c = is_c };
    }

    fn parseAggregate(self: *Parser) Error!ast.Aggregate {
        try self.enter();
        defer self.leave();

        const tok = self.cur;
        var out = ast.Aggregate{ .span = tok.span };
        var close: Kind = .r_brace;
        switch (tok.kind) {
            .l_brace => {
                out.kind = .braces;
                close = .r_brace;
                try self.advance();
            },
            .l_bracket => {
                out.kind = .brackets;
                close = .r_bracket;
                try self.advance();
            },
            .l_angle => {
                out.kind = .angles;
                close = .r_angle;
                try self.advance();
                if (self.check(.l_brace)) {
                    out.packed_braces = true;
                    close = .r_brace;
                    try self.advance();
                }
            },
            else => return self.fail(tok, "expected an aggregate literal", .{}),
        }

        var elems = std.ArrayList(ast.TypedValue).init(self.allocator);
        while (!self.check(close)) {
            if (self.cur.kind == .eof) return self.failMsg("unterminated aggregate literal", .{});
            try elems.append(try self.parseTypedValue());
            if (self.check(.comma)) {
                try self.advance();
                continue;
            }
            break;
        }
        _ = try self.expect(close, "closing delimiter of aggregate literal");
        if (out.packed_braces) _ = try self.expect(.r_angle, "'>' after packed struct literal");
        out.elems = try elems.toOwnedSlice();
        out.span = Span.join(tok.span, self.prev_span);
        return out;
    }

    // -------------------------------------------------------- constant exprs

    fn parseConstExpr(self: *Parser) Error!*const ast.ConstExpr {
        try self.enter();
        defer self.leave();

        const tok = self.cur;
        const word = self.text(tok);

        if (std.mem.eql(u8, word, "getelementptr")) {
            try self.advance();
            return self.newConstExpr(.{ .gep = try self.parseGep(tok.span) });
        }
        if (castOpFromWord(word)) |op| {
            try self.advance();
            return self.newConstExpr(.{ .cast = try self.parseCastExpr(op, tok.span) });
        }
        if (binaryOpFromWord(word)) |op| {
            try self.advance();
            return self.newConstExpr(.{ .binary = try self.parseBinaryExpr(op, tok.span) });
        }
        if (std.mem.eql(u8, word, "icmp")) {
            try self.advance();
            const pred = icmpPredFromWord(self.curText()) orelse
                return self.failMsg("unknown icmp predicate '{s}'", .{self.curText()});
            try self.advance();
            const ops = try self.parseParenTypedValues(2);
            return self.newConstExpr(.{ .icmp = .{
                .pred = pred,
                .ty = ops[0].ty,
                .lhs = ops[0].val,
                .rhs = ops[1].val,
                .span = Span.join(tok.span, self.prev_span),
            } });
        }
        if (std.mem.eql(u8, word, "fcmp")) {
            try self.advance();
            const pred = fcmpPredFromWord(self.curText()) orelse
                return self.failMsg("unknown fcmp predicate '{s}'", .{self.curText()});
            try self.advance();
            const ops = try self.parseParenTypedValues(2);
            return self.newConstExpr(.{ .fcmp = .{
                .pred = pred,
                .ty = ops[0].ty,
                .lhs = ops[0].val,
                .rhs = ops[1].val,
                .span = Span.join(tok.span, self.prev_span),
            } });
        }
        if (std.mem.eql(u8, word, "select")) {
            try self.advance();
            const ops = try self.parseParenTypedValues(3);
            return self.newConstExpr(.{ .select = .{
                .cond = ops[0],
                .if_true = ops[1],
                .if_false = ops[2],
                .span = Span.join(tok.span, self.prev_span),
            } });
        }
        if (std.mem.eql(u8, word, "extractvalue")) {
            try self.advance();
            _ = try self.expect(.l_paren, "'(' after extractvalue");
            const aggregate = try self.parseTypedValue();
            var indices = std.ArrayList(u32).init(self.allocator);
            while (self.check(.comma)) {
                try self.advance();
                try indices.append(try self.parseU32());
            }
            _ = try self.expect(.r_paren, "')' closing extractvalue");
            return self.newConstExpr(.{ .extractvalue = .{
                .aggregate = aggregate,
                .indices = try indices.toOwnedSlice(),
                .span = Span.join(tok.span, self.prev_span),
            } });
        }
        if (std.mem.eql(u8, word, "fneg")) {
            try self.advance();
            const ops = try self.parseParenTypedValues(1);
            return self.newConstExpr(.{ .fneg = .{
                .ty = ops[0].ty,
                .value = ops[0].val,
                .span = Span.join(tok.span, self.prev_span),
            } });
        }
        return self.fail(tok, "unsupported constant expression '{s}'", .{word});
    }

    fn parseParenTypedValues(self: *Parser, comptime count: usize) Error![count]ast.TypedValue {
        _ = try self.expect(.l_paren, "'(' starting constant expression");
        var out: [count]ast.TypedValue = undefined;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            out[i] = try self.parseTypedValue();
            if (i + 1 < count) _ = try self.expect(.comma, "',' between constant expression operands");
        }
        _ = try self.expect(.r_paren, "')' closing constant expression");
        return out;
    }

    fn parseCastExpr(self: *Parser, op: ast.CastOp, start: Span) Error!ast.CastExpr {
        _ = try self.expect(.l_paren, "'(' after cast");
        const src = try self.parseType();
        const value = try self.parseValue(src);
        _ = try self.expectWord("to");
        const dst = try self.parseType();
        _ = try self.expect(.r_paren, "')' closing cast");
        return .{ .op = op, .src = src, .value = value, .dst = dst, .span = Span.join(start, self.prev_span) };
    }

    fn parseBinaryExpr(self: *Parser, op: ast.BinaryOp, start: Span) Error!ast.BinaryExpr {
        var out = ast.BinaryExpr{ .op = op, .ty = undefined, .lhs = undefined, .rhs = undefined, .span = start };
        while (self.cur.kind == .identifier) {
            const word = self.curText();
            if (std.mem.eql(u8, word, "nuw")) {
                out.nuw = true;
            } else if (std.mem.eql(u8, word, "nsw")) {
                out.nsw = true;
            } else if (std.mem.eql(u8, word, "exact")) {
                out.exact = true;
            } else if (self.isFastMathFlag(word)) {
                out.fast = true;
            } else break;
            try self.advance();
        }
        const ops = try self.parseParenTypedValues(2);
        out.ty = ops[0].ty;
        out.lhs = ops[0].val;
        out.rhs = ops[1].val;
        out.span = Span.join(start, self.prev_span);
        return out;
    }

    // ------------------------------------------------------------- attributes

    fn parseValueAttrs(self: *Parser) Error![]const ast.Attr {
        var list = std.ArrayList(ast.Attr).init(self.allocator);
        while (try self.tryParseAttr(&list)) {}
        if (list.items.len == 0) return &.{};
        return try list.toOwnedSlice();
    }

    /// Parse a single parameter/return attribute if one is present.
    fn tryParseAttr(self: *Parser, out: *std.ArrayList(ast.Attr)) Error!bool {
        if (self.cur.kind != .identifier) return false;
        const tok = self.cur;
        const word = self.text(tok);

        if (std.mem.eql(u8, word, "align")) {
            try self.advance();
            const value = try self.parseU32();
            try out.append(.{ .span = tok.span, .kind = .{ .align_ = value } });
            return true;
        }
        if (std.mem.eql(u8, word, "addrspace")) {
            try self.advance();
            _ = try self.expect(.l_paren, "'(' after addrspace");
            const value = try self.parseU32();
            _ = try self.expect(.r_paren, "')' after addrspace");
            try out.append(.{ .span = tok.span, .kind = .{ .addr_space = value } });
            return true;
        }
        if (std.mem.eql(u8, word, "byval") or
            std.mem.eql(u8, word, "sret") or
            std.mem.eql(u8, word, "byref") or
            std.mem.eql(u8, word, "elementtype") or
            std.mem.eql(u8, word, "inalloca") or
            std.mem.eql(u8, word, "initializes") or
            std.mem.eql(u8, word, "preallocated"))
        {
            try self.advance();
            _ = try self.expect(.l_paren, "'(' after typed attribute");
            const ty = try self.parseType();
            _ = try self.expect(.r_paren, "')' after typed attribute");
            const kind: ast.Attr.Kind = if (std.mem.eql(u8, word, "byval"))
                .{ .byval = ty }
            else if (std.mem.eql(u8, word, "sret"))
                .{ .sret = ty }
            else if (std.mem.eql(u8, word, "byref"))
                .{ .byref = ty }
            else if (std.mem.eql(u8, word, "elementtype"))
                .{ .elementtype = ty }
            else if (std.mem.eql(u8, word, "inalloca"))
                .{ .inalloca = ty }
            else if (std.mem.eql(u8, word, "initializes"))
                .{ .initializes = ty }
            else
                .{ .preallocated = ty };
            try out.append(.{ .span = tok.span, .kind = kind });
            return true;
        }
        if (std.mem.eql(u8, word, "dereferenceable") or std.mem.eql(u8, word, "dereferenceable_or_null")) {
            try self.advance();
            _ = try self.expect(.l_paren, "'(' after dereferenceable");
            const value = try self.parseU64();
            _ = try self.expect(.r_paren, "')' after dereferenceable");
            const kind: ast.Attr.Kind = if (std.mem.eql(u8, word, "dereferenceable"))
                .{ .dereferenceable = value }
            else
                .{ .dereferenceable_or_null = value };
            try out.append(.{ .span = tok.span, .kind = kind });
            return true;
        }
        if (simpleAttrFromWord(word)) |kind| {
            try self.advance();
            try out.append(.{ .span = tok.span, .kind = kind });
            return true;
        }
        if (argAttrFromWord(word)) {
            try self.advance();
            _ = try self.expect(.l_paren, "'(' after attribute");
            const raw = try self.skipBalancedRaw(.l_paren, .r_paren);
            try out.append(.{ .span = tok.span, .kind = .{ .opaque_call = .{ .name = word, .raw = raw } } });
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------- metadata

    fn parseMetadataAttachment(self: *Parser) Error!ast.MetadataAttachment {
        if (self.cur.kind != .metadata_id) {
            return self.failMsg("expected a metadata attachment name, found {s}", .{lexer.kindName(self.cur.kind)});
        }
        const tok = self.cur;
        const raw = self.text(tok);
        var name = raw[1..];
        if (name.len >= 2 and name[0] == '"') name = name[1 .. name.len - 1];
        try self.advance();
        const ref = try self.parseMetadataRef();
        return .{ .name = name, .ref = ref, .span = Span.join(tok.span, self.prev_span) };
    }

    fn parseMetadataRef(self: *Parser) Error!ast.MetadataRef {
        switch (self.cur.kind) {
            .metadata_id => {
                const tok = self.cur;
                const raw = self.text(tok);
                const inner = raw[1..];
                if (inner.len != 0 and allDigits(inner)) {
                    const id = std.fmt.parseInt(u32, inner, 10) catch
                        return self.fail(tok, "metadata id '{s}' is out of range", .{raw});
                    try self.advance();
                    return .{ .id = id };
                }
                const name = if (inner.len >= 2 and inner[0] == '"') inner[1 .. inner.len - 1] else inner;
                try self.advance();
                var has_args = false;
                var payload: []const u8 = "";
                if (self.check(.l_paren)) {
                    payload = try self.skipBalancedRaw(.l_paren, .r_paren);
                    has_args = true;
                }
                return .{ .named = .{
                    .name = name,
                    .has_args = has_args,
                    .raw = payload,
                    .span = Span.join(tok.span, self.prev_span),
                } };
            },
            .bang => {
                const tok = self.cur;
                try self.advance(); // '!'
                if (!self.check(.l_brace)) {
                    return self.failMsg("expected '{{' after '!' in metadata node", .{});
                }
                const raw = try self.skipBalancedRaw(.l_brace, .r_brace);
                return .{ .node = .{ .raw = raw, .span = Span.join(tok.span, self.prev_span) } };
            },
            else => return self.failMsg("expected a metadata reference, found {s} '{s}'", .{
                lexer.kindName(self.cur.kind), self.curText(),
            }),
        }
    }

    fn skipFastMathFlags(self: *Parser) Error!void {
        while (self.cur.kind == .identifier and self.isFastMathFlag(self.curText())) try self.advance();
    }

    fn isFastMathFlag(self: *const Parser, word: []const u8) bool {
        _ = self;
        return fastMathFlagFromWord(word);
    }
};

// ------------------------------------------------------------------ type table

fn stripQuotes(raw: []const u8) []const u8 {
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
    return raw;
}

fn allDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// `u0x...` / `s0x...` hexadecimal integer literals (LLVM's spelling).
fn hexIntWord(word: []const u8) ?[]const u8 {
    if (word.len <= 3) return null;
    const is_hex_int = std.mem.startsWith(u8, word, "u0x") or std.mem.startsWith(u8, word, "s0x");
    if (!is_hex_int) return null;
    const digits = word[3..];
    for (digits) |c| {
        if (!std.ascii.isHex(c)) return null;
    }
    return digits;
}

fn floatKindFromWord(word: []const u8) ?ast.FloatKind {
    const table = .{
        .{ "half", ast.FloatKind.half },
        .{ "bfloat", ast.FloatKind.bfloat },
        .{ "float", ast.FloatKind.float },
        .{ "double", ast.FloatKind.double },
        .{ "x86_fp80", ast.FloatKind.x86_fp80 },
        .{ "fp128", ast.FloatKind.fp128 },
        .{ "ppc_fp128", ast.FloatKind.ppc_fp128 },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, word, entry[0])) return entry[1];
    }
    return null;
}

fn isHexSpecifier(c: u8) bool {
    return switch (c) {
        'H', 'K', 'L', 'M', 'R' => true,
        else => false,
    };
}

fn linkageFromWord(word: []const u8) ?ast.Linkage {
    const table = .{
        .{ "private", ast.Linkage.private },
        .{ "internal", ast.Linkage.internal },
        .{ "available_externally", ast.Linkage.available_externally },
        .{ "linkonce", ast.Linkage.linkonce },
        .{ "weak", ast.Linkage.weak },
        .{ "common", ast.Linkage.common },
        .{ "appending", ast.Linkage.appending },
        .{ "extern_weak", ast.Linkage.extern_weak },
        .{ "linkonce_odr", ast.Linkage.linkonce_odr },
        .{ "weak_odr", ast.Linkage.weak_odr },
        .{ "external", ast.Linkage.external },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, word, entry[0])) return entry[1];
    }
    return null;
}

fn isCallConv(word: []const u8) bool {
    const table = [_][]const u8{
        "ccc",           "fastcc",     "coldcc",         "anyregcc",
        "preserve_mostcc", "preserve_allcc", "cxx_fast_tlscc", "swiftcc",
        "tailcc",        "ghccc",      "webkit_jscc",    "x86_stdcallcc",
        "x86_fastcallcc", "x86_thiscallcc", "x86_vectorcallcc", "x86_regcallcc",
        "x86_64_sysvcc", "win64cc",    "x86_intrcc",     "arm_apcscc",
        "arm_aapcscc",   "arm_aapcs_vfpcc", "aarch64_vector_pcs", "msp430_intrcc",
        "avr_intrcc",    "avr_signalcc", "ptx_kernel",   "ptx_device",
        "spir_func",     "spir_kernel", "intel_ocl_bicc", "amdgpu_ps",
        "amdgpu_cs",     "amdgpu_kernel", "amdgpu_gfx",  "amdgpu_vs",
        "amdgpu_gs",     "amdgpu_hs",  "amdgpu_es",      "amdgpu_ls",
        "amdgpu_ngg",    "amdgpu_cs_chain", "amdgpu_cs_chain_preserve",
        "dupal",         "dxil_vertex", "dxil_pixel",    "dxil_geometry",
        "dxil_hull",     "dxil_domain", "dxil_library",  "dxil_root_signature",
        "dxil_compute",
    };
    for (table) |entry| {
        if (std.mem.eql(u8, word, entry)) return true;
    }
    return false;
}

fn fastMathFlagFromWord(word: []const u8) bool {
    const table = [_][]const u8{
        "fast", "nnan", "ninf", "nsz", "arcp", "contract", "afn", "reassoc", "nofpclass",
    };
    for (table) |entry| {
        if (std.mem.eql(u8, word, entry)) return true;
    }
    return false;
}

fn isAtomicOrdering(word: []const u8) bool {
    const table = [_][]const u8{
        "unordered", "monotonic", "acquire", "release", "acq_rel", "seq_cst",
    };
    for (table) |entry| {
        if (std.mem.eql(u8, word, entry)) return true;
    }
    return false;
}

fn simpleAttrFromWord(word: []const u8) ?ast.Attr.Kind {
    const table = .{
        .{ "noundef", ast.Attr.Kind{ .noundef = {} } },
        .{ "signext", ast.Attr.Kind{ .signext = {} } },
        .{ "zeroext", ast.Attr.Kind{ .zeroext = {} } },
        .{ "noalias", ast.Attr.Kind{ .noalias_ = {} } },
        .{ "nonnull", ast.Attr.Kind{ .nonnull = {} } },
        .{ "inreg", ast.Attr.Kind{ .inreg = {} } },
        .{ "returned", ast.Attr.Kind{ .returned = {} } },
        .{ "nocapture", ast.Attr.Kind{ .opaque_ = "nocapture" } },
        .{ "nest", ast.Attr.Kind{ .opaque_ = "nest" } },
        .{ "noext", ast.Attr.Kind{ .opaque_ = "noext" } },
        .{ "swiftasync", ast.Attr.Kind{ .opaque_ = "swiftasync" } },
        .{ "swiftself", ast.Attr.Kind{ .opaque_ = "swiftself" } },
        .{ "swifterror", ast.Attr.Kind{ .opaque_ = "swifterror" } },
        .{ "allocalign", ast.Attr.Kind{ .opaque_ = "allocalign" } },
        .{ "allocptr", ast.Attr.Kind{ .opaque_ = "allocptr" } },
        .{ "nofpclass", ast.Attr.Kind{ .opaque_ = "nofpclass" } },
        .{ "immarg", ast.Attr.Kind{ .immarg = {} } },
        .{ "readonly", ast.Attr.Kind{ .readonly = {} } },
        .{ "readnone", ast.Attr.Kind{ .readnone = {} } },
        .{ "writeonly", ast.Attr.Kind{ .writeonly = {} } },
        .{ "writable", ast.Attr.Kind{ .writable = {} } },
        .{ "dead_on_unwind", ast.Attr.Kind{ .dead_on_unwind = {} } },
        .{ "nofree", ast.Attr.Kind{ .nofree = {} } },
        .{ "nocyclone", ast.Attr.Kind{ .nocyclone = {} } },
        .{ "nosync", ast.Attr.Kind{ .nosync = {} } },
        .{ "nounwind", ast.Attr.Kind{ .nounwind = {} } },
        .{ "willreturn", ast.Attr.Kind{ .willreturn = {} } },
        .{ "mustprogress", ast.Attr.Kind{ .mustprogress = {} } },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, word, entry[0])) return entry[1];
    }
    return null;
}

fn argAttrFromWord(word: []const u8) bool {
    const table = [_][]const u8{
        "captures", "range", "nofpclass", "allocsize", "alignstack",
        "allockind", "initializes", "annotate", "memory", "deref",
    };
    for (table) |entry| {
        if (std.mem.eql(u8, word, entry)) return true;
    }
    return false;
}

fn isConstExprWord(word: []const u8) bool {
    const table = [_][]const u8{
        "getelementptr", "ptrtoint",  "inttoptr",  "bitcast",  "addrspacecast",
        "trunc",         "zext",       "sext",      "fptrunc",  "fpext",
        "fptoui",        "fptosi",     "uitofp",    "sitofp",   "icmp",
        "fcmp",          "select",     "extractvalue", "fneg",  "add",
        "sub",           "mul",        "sdiv",      "udiv",     "srem",
        "urem",          "and",        "or",        "xor",      "shl",
        "lshr",          "ashr",       "fadd",      "fsub",     "fmul",
        "fdiv",          "frem",
    };
    for (table) |entry| {
        if (std.mem.eql(u8, word, entry)) return true;
    }
    return false;
}

fn binaryOpFromWord(word: []const u8) ?ast.BinaryOp {
    const table = .{
        .{ "add", ast.BinaryOp.add },
        .{ "sub", ast.BinaryOp.sub },
        .{ "mul", ast.BinaryOp.mul },
        .{ "sdiv", ast.BinaryOp.sdiv },
        .{ "udiv", ast.BinaryOp.udiv },
        .{ "srem", ast.BinaryOp.srem },
        .{ "urem", ast.BinaryOp.urem },
        .{ "and", ast.BinaryOp.and_ },
        .{ "or", ast.BinaryOp.or_ },
        .{ "xor", ast.BinaryOp.xor },
        .{ "shl", ast.BinaryOp.shl },
        .{ "lshr", ast.BinaryOp.lshr },
        .{ "ashr", ast.BinaryOp.ashr },
        .{ "fadd", ast.BinaryOp.fadd },
        .{ "fsub", ast.BinaryOp.fsub },
        .{ "fmul", ast.BinaryOp.fmul },
        .{ "fdiv", ast.BinaryOp.fdiv },
        .{ "frem", ast.BinaryOp.frem },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, word, entry[0])) return entry[1];
    }
    return null;
}

fn castOpFromWord(word: []const u8) ?ast.CastOp {
    const table = .{
        .{ "trunc", ast.CastOp.trunc },
        .{ "zext", ast.CastOp.zext },
        .{ "sext", ast.CastOp.sext },
        .{ "fptrunc", ast.CastOp.fptrunc },
        .{ "fpext", ast.CastOp.fpext },
        .{ "fptoui", ast.CastOp.fptoui },
        .{ "fptosi", ast.CastOp.fptosi },
        .{ "uitofp", ast.CastOp.uitofp },
        .{ "sitofp", ast.CastOp.sitofp },
        .{ "ptrtoint", ast.CastOp.ptrtoint },
        .{ "inttoptr", ast.CastOp.inttoptr },
        .{ "bitcast", ast.CastOp.bitcast },
        .{ "addrspacecast", ast.CastOp.addrspacecast },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, word, entry[0])) return entry[1];
    }
    return null;
}

fn icmpPredFromWord(word: []const u8) ?ast.IcmpPred {
    const table = .{
        .{ "eq", ast.IcmpPred.eq },
        .{ "ne", ast.IcmpPred.ne },
        .{ "ugt", ast.IcmpPred.ugt },
        .{ "uge", ast.IcmpPred.uge },
        .{ "ult", ast.IcmpPred.ult },
        .{ "ule", ast.IcmpPred.ule },
        .{ "sgt", ast.IcmpPred.sgt },
        .{ "sge", ast.IcmpPred.sge },
        .{ "slt", ast.IcmpPred.slt },
        .{ "sle", ast.IcmpPred.sle },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, word, entry[0])) return entry[1];
    }
    return null;
}

fn fcmpPredFromWord(word: []const u8) ?ast.FcmpPred {
    const table = .{
        .{ "false", ast.FcmpPred.false_ },
        .{ "oeq", ast.FcmpPred.oeq },
        .{ "ogt", ast.FcmpPred.ogt },
        .{ "oge", ast.FcmpPred.oge },
        .{ "olt", ast.FcmpPred.olt },
        .{ "ole", ast.FcmpPred.ole },
        .{ "one", ast.FcmpPred.one },
        .{ "ord", ast.FcmpPred.ord },
        .{ "ueq", ast.FcmpPred.ueq },
        .{ "ugt", ast.FcmpPred.ugt },
        .{ "uge", ast.FcmpPred.uge },
        .{ "ult", ast.FcmpPred.ult },
        .{ "ule", ast.FcmpPred.ule },
        .{ "une", ast.FcmpPred.une },
        .{ "uno", ast.FcmpPred.uno },
        .{ "true", ast.FcmpPred.true_ },
    };
    inline for (table) |entry| {
        if (std.mem.eql(u8, word, entry[0])) return entry[1];
    }
    return null;
}

pub fn parseModule(allocator: Allocator, text: []const u8) Error!ast.Module {
    var parser = Parser.init(allocator, text);
    return parser.parse();
}

/// Parse exactly one type from `text`. Trailing tokens are an error.
pub fn parseTypeString(allocator: Allocator, text: []const u8) Error!*const ast.Type {
    var p = Parser.init(allocator, text);
    return p.parseTypeOnly();
}

/// Parse exactly one value of type `ty` from `text`.
pub fn parseValueString(allocator: Allocator, ty: *const ast.Type, text: []const u8) Error!ast.Value {
    var p = Parser.init(allocator, text);
    return p.parseValueOnly(ty);
}
