//! Target link-ABI aliases that neither LLVM IR nor the public headers carry.
//!
//! `data/link_wrappers.json` is the only checked-in link-metadata file left:
//! the rest of the provider tables are generated at build time from the
//! installed Zig toolchain (MinGW `.def` files, glibc `abilists`).
//!
//! `atexit -> __cxa_atexit` is lowered in `lower_ast.zig` (it needs extra
//! arguments); this module only exposes same-signature aliases such as
//! `snprintf -> _snprintf` on Windows.

const std = @import("std");

const wrappers_json = @embedFile("data/link_wrappers.json");

pub const Wrappers = struct {
    arena: std.heap.ArenaAllocator,
    root: std.json.Value,

    pub fn init(allocator: std.mem.Allocator) !Wrappers {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const root = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), wrappers_json, .{});
        if (root != .object) return error.BadWrappers;
        return .{ .arena = arena, .root = root };
    }

    pub fn deinit(self: *Wrappers) void {
        self.arena.deinit();
    }

    /// Target-specific same-signature alias. `os_id` uses 1 = linux,
    /// 2 = windows.
    pub fn alias(self: *const Wrappers, os_id: u8, name: []const u8) ?[]const u8 {
        const aliases = objectField(self.root, "aliases") orelse return null;
        const os_aliases = objectField(aliases, if (os_id == 2) "windows" else "linux") orelse return null;
        const value = objectField(os_aliases, name) orelse return null;
        return if (value == .string) value.string else null;
    }
};

fn objectField(value: std.json.Value, field: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(field);
}

test "Windows CRT aliases" {
    var wrappers = try Wrappers.init(std.testing.allocator);
    defer wrappers.deinit();
    try std.testing.expectEqualStrings("_snprintf", wrappers.alias(2, "snprintf").?);
    try std.testing.expectEqualStrings("_vsnprintf", wrappers.alias(2, "vsnprintf").?);
    try std.testing.expect(wrappers.alias(2, "printf") == null);
}

test "no Linux same-signature aliases" {
    var wrappers = try Wrappers.init(std.testing.allocator);
    defer wrappers.deinit();
    try std.testing.expect(wrappers.alias(1, "snprintf") == null);
    try std.testing.expect(wrappers.alias(1, "atexit") == null);
}
