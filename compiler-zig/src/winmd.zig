const std = @import("std");

const Allocator = std.mem.Allocator;

const db_gz = @embedFile("data/winmd.generated.json.gz");

pub const Provider = struct {
    dll: []const u8,
    symbol: []const u8,
};

pub const Result = struct {
    providers: []Provider,
    conv: u8,
    min_os: u16,
};

fn archMask(arch: u8) u8 {
    return switch (arch) {
        1 => 1, // x86_64
        2 => 2, // x86
        3 => 4, // aarch64
        else => 0,
    };
}

/// Embedded Windows API metadata from winmd. One instance is created per
/// compile; JSON strings/providers live in the arena.
pub const Database = struct {
    arena: std.heap.ArenaAllocator,
    root: std.json.Value,

    pub fn init(allocator: Allocator) !Database {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        var compressed = std.io.fixedBufferStream(db_gz);
        var json = std.ArrayList(u8).init(arena.allocator());
        try std.compress.gzip.decompress(compressed.reader(), json.writer());
        const root = try std.json.parseFromSliceLeaky(
            std.json.Value,
            arena.allocator(),
            json.items,
            .{},
        );
        return .{ .arena = arena, .root = root };
    }

    pub fn deinit(self: *Database) void {
        self.arena.deinit();
    }

    pub fn lookup(self: *Database, name: []const u8, arch: u8) ?Result {
        if (self.root != .object) return null;
        const apis = self.root.object.get("apis") orelse return null;
        if (apis != .object) return null;
        var base = name;
        // Win32 stdcall IR spells symbols as @"\01_Name@4"; the parser keeps
        // the textual \XX escape, so strip it (and the leading underscore)
        // before looking up the undecorated winmd API name.
        if (base.len >= 3 and base[0] == '\\' and std.ascii.isHex(base[1]) and std.ascii.isHex(base[2]))
            base = base[3..];
        while (base.len > 0 and base[0] == 1) base = base[1..];
        if (std.mem.indexOfScalar(u8, base, '@')) |at| base = base[0..at];
        var candidate = base;
        var entries = apis.object.get(candidate);
        if (entries == null and base.len > 0 and base[0] == '_') {
            candidate = base[1..];
            entries = apis.object.get(candidate);
        }
        const list = entries orelse return null;
        if (list != .array) return null;
        const mask = archMask(arch);
        var providers = std.ArrayList(Provider).init(self.arena.allocator());
        var conv: u8 = 1; // winapi/stdcall default
        var min_os: u16 = 0;
        for (list.array.items) |entry| {
            if (entry != .object) continue;
            const mask_val: std.json.Value = entry.object.get("arch_mask") orelse std.json.Value{ .integer = 7 };
            if (mask_val != .integer) continue;
            const emask: u8 = @intCast(mask_val.integer);
            if (mask != 0 and (emask & mask) == 0) continue;
            const dll = entry.object.get("dll") orelse continue;
            if (dll != .string) continue;
            const conv_val: std.json.Value = entry.object.get("callconv") orelse std.json.Value{ .string = "winapi" };
            if (conv_val == .string and std.mem.eql(u8, conv_val.string, "cdecl")) conv = 0;
            const mo: std.json.Value = entry.object.get("min_os") orelse std.json.Value{ .integer = 0 };
            if (mo == .integer and mo.integer > min_os) min_os = @intCast(mo.integer);
            var duplicate = false;
            for (providers.items) |p| {
                if (std.mem.eql(u8, p.dll, dll.string)) duplicate = true;
            }
            if (!duplicate and providers.items.len < 8) {
                providers.append(.{ .dll = dll.string, .symbol = candidate }) catch return null;
            }
        }
        if (providers.items.len == 0) return null;
        return .{ .providers = providers.items, .conv = conv, .min_os = min_os };
    }
};

test "winmd resolves Win64 and decorated Win32 imports" {
    var db = try Database.init(std.testing.allocator);
    defer db.deinit();

    const tick = db.lookup("GetTickCount64", 1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("kernel32.dll", tick.providers[0].dll);
    try std.testing.expectEqualStrings("GetTickCount64", tick.providers[0].symbol);
    try std.testing.expectEqual(@as(u8, 1), tick.conv);

    const decorated = db.lookup("\\01_GetTickCount64@0", 2) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("kernel32.dll", decorated.providers[0].dll);
    try std.testing.expectEqualStrings("GetTickCount64", decorated.providers[0].symbol);
    try std.testing.expectEqual(@as(u8, 1), decorated.conv);

    const sprintf = db.lookup("wsprintfA", 2) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("user32.dll", sprintf.providers[0].dll);
    try std.testing.expectEqual(@as(u8, 0), sprintf.conv);
}
