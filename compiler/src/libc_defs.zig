//! Linux external-symbol resolution from Zig's bundled glibc `abilists`.
//!
//! The table is generated at build time by `tools/gen_link_index.zig` from
//! `<zig lib>/libc/glibc/abilists` and embedded through the
//! `libc_defs_generated` anonymous import. It maps a symbol to the glibc
//! shared object that exports it for x86_64-linux-gnu and aarch64-linux-gnu.
//!
//! `ld` (the dynamic loader) is deliberately not indexed. Symbols that are not
//! in the list are left to the runtime's default-library fallback (`libc.so.6`,
//! `libm.so.6`, `libdl.so.2`, ...), and `--lib` still wins over CIPI providers.

const std = @import("std");
const link_index = @import("link_index.zig");
const generated = @import("libc_defs_generated");

pub const source_id = generated.source_id;
pub const entry_count = generated.entry_count;
pub const max_providers = 8;

pub const Provider = struct {
    lib: []const u8,
    symbol: []const u8,
};

pub const Result = struct {
    providers: [max_providers]Provider = undefined,
    len: u8 = 0,

    pub fn slice(self: *const Result) []const Provider {
        return self.providers[0..self.len];
    }
};

const header = link_index.parse(generated.blob) catch @compileError("libc_defs: invalid generated index");
comptime {
    if (header.kind != .glibc) @compileError("libc_defs: generated index is not a glibc index");
}

/// Normalize an external symbol to the index key spelling. glibc abilists
/// store plain names; stripping a leading underscore is handled by `lookup`.
pub fn normalize(name: []const u8) []const u8 {
    var value = name;
    if (value.len >= 3 and value[0] == '\\' and std.ascii.isHex(value[1]) and std.ascii.isHex(value[2])) {
        value = value[3..];
    }
    while (value.len > 0 and (value[0] == 1 or value[0] == 0x1f)) value = value[1..];
    if (std.mem.lastIndexOfScalar(u8, value, '@')) |position| {
        if (position > 0 and isAllDigits(value[position + 1 ..])) value = value[0..position];
    }
    return value;
}

/// Resolve `name` for `arch` (1 = x86_64, 3 = aarch64).
pub fn lookup(arch: u8, name: []const u8) ?Result {
    const key = normalize(name);
    if (key.len == 0) return null;
    if (lookupKey(arch, key)) |result| return result;
    if (key.len > 1 and key[0] == '_') return lookupKey(arch, key[1..]);
    return null;
}

fn lookupKey(arch: u8, key: []const u8) ?Result {
    const first = link_index.firstKey(generated.blob, header, key) catch return null;
    const mask = link_index.archMask(arch);
    if (mask == 0) return null;
    var result = Result{};
    var index: u32 = first;
    while (index < header.entry_count) : (index += 1) {
        const entry = link_index.entryAt(generated.blob, header, index) catch return null;
        if (!std.mem.eql(u8, entry.key, key)) break;
        if (entry.arch_mask != 0 and (entry.arch_mask & mask) == 0) continue;
        const lib = link_index.libAt(generated.blob, header, entry.lib_id) catch continue;
        var duplicate = false;
        for (result.providers[0..result.len]) |provider| {
            if (std.mem.eql(u8, provider.lib, lib)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        if (result.len >= max_providers) break;
        result.providers[result.len] = .{ .lib = lib, .symbol = entry.symbol };
        result.len += 1;
    }
    return if (result.len == 0) null else result;
}

fn isAllDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |char| {
        if (!std.ascii.isDigit(char)) return false;
    }
    return true;
}

test "resolves libc symbols on x86_64" {
    const printf = lookup(1, "printf") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("libc.so.6", printf.slice()[0].lib);
    try std.testing.expectEqualStrings("printf", printf.slice()[0].symbol);

    const qsort = lookup(1, "qsort") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("libc.so.6", qsort.slice()[0].lib);
}

test "resolves libm symbols" {
    const sin = lookup(1, "sin") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("libm.so.6", sin.slice()[0].lib);

    const cos = lookup(3, "cos") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("libm.so.6", cos.slice()[0].lib);
}

test "keeps every exporting library as a provider" {
    const pthread = lookup(1, "pthread_create") orelse return error.TestUnexpectedResult;
    var saw_libc = false;
    var saw_pthread = false;
    for (pthread.slice()) |provider| {
        if (std.mem.eql(u8, provider.lib, "libc.so.6")) saw_libc = true;
        if (std.mem.eql(u8, provider.lib, "libpthread.so.0")) saw_pthread = true;
    }
    try std.testing.expect(saw_libc and saw_pthread);

    const dlopen = lookup(1, "dlopen") orelse return error.TestUnexpectedResult;
    try std.testing.expect(dlopen.slice().len >= 2);
    try std.testing.expectEqualStrings("libc.so.6", dlopen.slice()[0].lib);

    const clock = lookup(1, "clock_gettime") orelse return error.TestUnexpectedResult;
    var saw_rt = false;
    for (clock.slice()) |provider| {
        if (std.mem.eql(u8, provider.lib, "librt.so.1")) saw_rt = true;
    }
    try std.testing.expect(saw_rt);
}

test "aarch64 and unknown symbols" {
    const sin = lookup(3, "sin") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("libm.so.6", sin.slice()[0].lib);

    // The dynamic loader is never a provider.
    try std.testing.expect(lookup(1, "_dl_signal_error") == null or
        !std.mem.eql(u8, lookup(1, "_dl_signal_error").?.slice()[0].lib, "ld-linux-x86-64.so.2"));
    try std.testing.expect(lookup(1, "definitely_not_a_glibc_symbol") == null);
}

test "atexit rewrite has a libc provider" {
    const cxa = lookup(1, "__cxa_atexit") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("libc.so.6", cxa.slice()[0].lib);
}
