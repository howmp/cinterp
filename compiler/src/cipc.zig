//! CIPC constant and name pool serialization.
//!
//! The pool stores deduplicated UTF-8 names for CIPL/CIPI references and a
//! raw data blob for scalar constants and the module's static data image.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const NamePool = struct {
    allocator: Allocator,
    names: std.ArrayList([]const u8),
    map: std.StringHashMap(u16),

    pub fn init(allocator: Allocator) NamePool {
        return .{
            .allocator = allocator,
            .names = std.ArrayList([]const u8).init(allocator),
            .map = std.StringHashMap(u16).init(allocator),
        };
    }

    pub fn deinit(self: *NamePool) void {
        self.names.deinit();
        self.map.deinit();
    }

    pub fn ref(self: *NamePool, name: []const u8) !u16 {
        if (name.len == 0) return error.EmptyName;
        if (self.map.get(name)) |index| return index;
        if (self.names.items.len >= 0xFFFF) return error.TooManyNames;
        const index: u16 = @intCast(self.names.items.len);
        try self.names.append(name);
        try self.map.put(name, index);
        return index;
    }

    pub fn get(self: *const NamePool, name: []const u8) ?u16 {
        return self.map.get(name);
    }

    pub fn count(self: *const NamePool) usize {
        return self.names.items.len;
    }
};

fn writeU16(out: *std.ArrayList(u8), value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try out.appendSlice(&buf);
}

fn writeU32(out: *std.ArrayList(u8), value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try out.appendSlice(&buf);
}

/// Serialize a CIPC section. `data` is copied verbatim after the name table
/// and a 16-byte pad; its offsets are relative to the start of that blob.
/// `data_base` is the VM memory offset where the blob is installed (the
/// mutable-global image occupies the bytes before it).
pub fn serialize(allocator: Allocator, names: *const NamePool, data: []const u8, data_base: u32) ![]u8 {
    if (names.count() > 0xFFFF) return error.TooManyNames;
    if (data.len > std.math.maxInt(u32)) return error.PoolTooLarge;

    var name_blob = std.ArrayList(u8).init(allocator);
    defer name_blob.deinit();
    var offsets = std.ArrayList(u16).init(allocator);
    defer offsets.deinit();

    for (names.names.items) |name| {
        if (name_blob.items.len > std.math.maxInt(u16)) return error.NamePoolTooLarge;
        try offsets.append(@intCast(name_blob.items.len));
        try name_blob.appendSlice(name);
        try name_blob.append(0);
    }
    if (name_blob.items.len > std.math.maxInt(u16)) return error.NamePoolTooLarge;

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.appendSlice("CIPC");
    try out.append(1);
    try out.append(0);
    try writeU16(&out, @intCast(names.count()));
    try writeU32(&out, @intCast(name_blob.items.len));
    try writeU32(&out, @intCast(data.len));
    try writeU32(&out, data_base);
    for (offsets.items) |offset| try writeU16(&out, offset);
    try out.appendSlice(name_blob.items);
    while (out.items.len % 16 != 0) try out.append(0);
    try out.appendSlice(data);
    return out.toOwnedSlice();
}

test "CIPC names are deduplicated and offsets are stable" {
    var names = NamePool.init(std.testing.allocator);
    defer names.deinit();
    try std.testing.expectEqual(@as(u16, 0), try names.ref("printf"));
    try std.testing.expectEqual(@as(u16, 1), try names.ref("libc.so.6"));
    try std.testing.expectEqual(@as(u16, 0), try names.ref("printf"));
    const bytes = try serialize(std.testing.allocator, &names, "abc", 0);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, "CIPC", bytes[0..4]);
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, bytes[6..8], .little));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "printf\x00") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "libc.so.6\x00") != null);
    try std.testing.expect(std.mem.endsWith(u8, bytes, "abc"));
}
