//! CIPC constant and name pool serialization.
//!
//! The pool stores deduplicated UTF-8 names for CIPL/CIPI references and a
//! raw data blob for scalar constants and the module's static data image.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const key_len: usize = 16;

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

fn appendXor(out: *std.ArrayList(u8), bytes: []const u8, key: [key_len]u8) !void {
    for (bytes, 0..) |byte, i| try out.append(byte ^ key[i % key.len]);
}

/// Serialize a CIPC v2 section. `name_blob` and `data` are XOR-encrypted with
/// `key` when it is non-null; the key itself, lengths, name offsets and
/// `data_base` stay plaintext. `data` offsets are relative to the start of the
/// 16-byte-aligned data blob. `data_base` is the VM memory offset where the
/// blob is installed (the mutable-global image occupies the bytes before it).
pub fn serialize(
    allocator: Allocator,
    names: *const NamePool,
    data: []const u8,
    data_base: u32,
    key: ?[key_len]u8,
) ![]u8 {
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
    try out.append(2);
    try out.append(if (key != null) 1 else 0);
    try writeU16(&out, @intCast(names.count()));
    try writeU32(&out, @intCast(name_blob.items.len));
    try writeU32(&out, @intCast(data.len));
    try writeU32(&out, data_base);
    const header_key = key orelse [_]u8{0} ** key_len;
    try out.appendSlice(&header_key);
    for (offsets.items) |offset| try writeU16(&out, offset);
    if (key) |k| {
        try appendXor(&out, name_blob.items, k);
    } else {
        try out.appendSlice(name_blob.items);
    }
    while (out.items.len % 16 != 0) try out.append(0);
    if (key) |k| {
        try appendXor(&out, data, k);
    } else {
        try out.appendSlice(data);
    }
    return out.toOwnedSlice();
}

fn decodeXor(allocator: Allocator, bytes: []const u8, key: [key_len]u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len);
    for (bytes, 0..) |byte, i| out[i] = byte ^ key[i % key.len];
    return out;
}

test "CIPC v2 plaintext keeps names and data verbatim" {
    var names = NamePool.init(std.testing.allocator);
    defer names.deinit();
    try std.testing.expectEqual(@as(u16, 0), try names.ref("printf"));
    try std.testing.expectEqual(@as(u16, 1), try names.ref("libc.so.6"));
    try std.testing.expectEqual(@as(u16, 0), try names.ref("printf"));
    const bytes = try serialize(std.testing.allocator, &names, "abc", 0, null);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, "CIPC", bytes[0..4]);
    try std.testing.expectEqual(@as(u8, 2), bytes[4]);
    try std.testing.expectEqual(@as(u8, 0), bytes[5]);
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** key_len), bytes[20..36]);
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, bytes[6..8], .little));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "printf\x00") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "libc.so.6\x00") != null);
    try std.testing.expect(std.mem.endsWith(u8, bytes, "abc"));
}

test "CIPC v2 XOR encrypts names and data" {
    var names = NamePool.init(std.testing.allocator);
    defer names.deinit();
    _ = try names.ref("printf");
    _ = try names.ref("libc.so.6");

    const key = [_]u8{
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x01,
    };
    const bytes = try serialize(std.testing.allocator, &names, "abc", 0, key);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, "CIPC", bytes[0..4]);
    try std.testing.expectEqual(@as(u8, 2), bytes[4]);
    try std.testing.expectEqual(@as(u8, 1), bytes[5]);
    try std.testing.expectEqualSlices(u8, &key, bytes[20..36]);

    const name_count = std.mem.readInt(u16, bytes[6..8], .little);
    const name_blob_len = std.mem.readInt(u32, bytes[8..12], .little);
    const data_len = std.mem.readInt(u32, bytes[12..16], .little);
    const name_blob_start = 36 + @as(usize, name_count) * 2;
    const data_start = (name_blob_start + name_blob_len + 15) & ~@as(usize, 15);
    try std.testing.expectEqual(@as(usize, 3), data_len);
    try std.testing.expectEqual(data_start + data_len, bytes.len);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "printf\x00") == null);
    try std.testing.expect(!std.mem.endsWith(u8, bytes, "abc"));

    const name_plain = try decodeXor(std.testing.allocator, bytes[name_blob_start .. name_blob_start + name_blob_len], key);
    defer std.testing.allocator.free(name_plain);
    try std.testing.expect(std.mem.indexOf(u8, name_plain, "printf\x00") != null);
    try std.testing.expect(std.mem.indexOf(u8, name_plain, "libc.so.6\x00") != null);

    const data_plain = try decodeXor(std.testing.allocator, bytes[data_start..], key);
    defer std.testing.allocator.free(data_plain);
    try std.testing.expectEqualSlices(u8, "abc", data_plain);
}
