//! Windows API import resolution from Zig's bundled MinGW `.def` files.
//!
//! The table is generated at build time by `tools/gen_link_index.zig` and
//! embedded through the `win_defs_generated` anonymous import. It contains
//! both Windows API DLLs and the UCRT/MSVCRT/NTDLL exports that MinGW
//! describes, so the compiler can emit concrete CIPI providers instead of
//! relying on a checked-in winmd snapshot.
//!
//! Lookup accepts the spellings that reach the compiler:
//!   * `GetTickCount64` (x64)
//!   * `\01_MessageBoxA@16` (Win32 stdcall as printed by the IR frontend)
//!   * `_snprintf` (after `link_wrappers` aliasing)
//!
//! The returned provider symbol is always the undecorated PE export name;
//! stdcall decoration only affects `conv`.

const std = @import("std");
const link_index = @import("link_index.zig");
const generated = @import("win_defs_generated");

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
    /// Win32 call convention for this symbol: 1 = stdcall, 0 = cdecl.
    /// Ignored by the Win64 backend.
    conv: u8 = 0,

    pub fn slice(self: *const Result) []const Provider {
        return self.providers[0..self.len];
    }
};

const header = link_index.parse(generated.blob) catch @compileError("win_defs: invalid generated index");
comptime {
    if (header.kind != .windows) @compileError("win_defs: generated index is not a Windows index");
}

/// Normalize an external symbol to the index key spelling: drop the textual
/// `\01` stdcall escape the IR parser keeps, any raw control prefix, and an
/// attached `@N` decoration. Leading underscores are preserved so that
/// `exit` and `_exit` stay distinct; `lookup` retries without the underscore.
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

/// Resolve `name` for `arch` (1 = x86_64, 2 = x86, 3 = aarch64). Returns null
/// when the MinGW defs do not describe the symbol; the runtime then falls back
/// to the process/CRT search path.
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
        const conv = entry.conv(arch);
        if (result.len == 0 or conv > result.conv) result.conv = conv;
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

test "normalizes Win32 stdcall decoration and escapes" {
    // Leading underscores are preserved so `exit` and `_exit` stay distinct;
    // `lookup` retries the name without the underscore.
    try std.testing.expectEqualStrings("_MessageBoxA", normalize("\\01_MessageBoxA@16"));
    try std.testing.expectEqualStrings("_MessageBoxA", normalize("_MessageBoxA@16"));
    try std.testing.expectEqualStrings("_snprintf", normalize("_snprintf"));
    try std.testing.expectEqualStrings("_GetTickCount64", normalize("\\01_GetTickCount64@0"));
    try std.testing.expectEqualStrings("MessageBoxA", normalize("MessageBoxA"));
}

test "resolves Win64 WinAPI providers" {
    const tick = lookup(1, "GetTickCount64") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("kernel32.dll", tick.slice()[0].lib);
    try std.testing.expectEqualStrings("GetTickCount64", tick.slice()[0].symbol);
    try std.testing.expectEqual(@as(u8, 1), tick.conv);

    const metrics = lookup(1, "GetSystemMetrics") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("user32.dll", metrics.slice()[0].lib);

    const module = lookup(1, "GetModuleHandleA") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("kernel32.dll", module.slice()[0].lib);

    const api_set = lookup(1, "VirtualAlloc2") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, api_set.slice()[0].lib, "api-ms-win-core-memory-"));
}

test "resolves Win32 decorated and cdecl WinAPI providers" {
    const message_box = lookup(2, "\\01_MessageBoxA@16") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("user32.dll", message_box.slice()[0].lib);
    try std.testing.expectEqualStrings("MessageBoxA", message_box.slice()[0].symbol);
    try std.testing.expectEqual(@as(u8, 1), message_box.conv);

    const wsprintf = lookup(2, "wsprintfA") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("user32.dll", wsprintf.slice()[0].lib);
    try std.testing.expectEqual(@as(u8, 0), wsprintf.conv);

    const metrics = lookup(2, "\\01_GetSystemMetrics@4") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("user32.dll", metrics.slice()[0].lib);
    try std.testing.expectEqual(@as(u8, 1), metrics.conv);
}

test "MinGW aliases resolve to the real export" {
    const close = lookup(1, "close") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ucrtbase.dll", close.slice()[0].lib);
    try std.testing.expectEqualStrings("_close", close.slice()[0].symbol);

    const underscore_close = lookup(1, "_close") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("_close", underscore_close.slice()[0].symbol);
}

test "CRT symbols and unknown names" {
    const malloc = lookup(1, "malloc") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ucrtbase.dll", malloc.slice()[0].lib);
    try std.testing.expectEqual(@as(u8, 0), malloc.conv);

    const snprintf = lookup(2, "_snprintf") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ntdll.dll", snprintf.slice()[0].lib);

    try std.testing.expect(lookup(1, "printf") == null);
    try std.testing.expect(lookup(1, "definitely_not_a_win32_symbol") == null);
}
