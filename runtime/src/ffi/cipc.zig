//! Runtime CIPC name/data pool.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const key_len: usize = 16;

pub const Pool = struct {
    bytes: []u8,
    names: [][]const u8,
    data: []const u8,
    data_base: u32,
    key: [key_len]u8,
    encrypted: bool,

    pub fn parse(allocator: Allocator, input: []const u8) !Pool {
        if (input.len < 36 or !std.mem.eql(u8, input[0..4], "CIPC")) return error.BadPool;
        if (input[4] != 2) return error.BadPoolVersion;
        const flags = input[5];
        if ((flags & ~@as(u8, 1)) != 0) return error.BadPoolFlags;
        const encrypted = (flags & 1) != 0;
        const name_count = readU16(input, 6);
        const name_blob_len = readU32(input, 8);
        const data_len = readU32(input, 12);
        const data_base = readU32(input, 16);
        var key: [key_len]u8 = undefined;
        @memcpy(&key, input[20..36]);
        const offsets_end = 36 + @as(usize, name_count) * 2;
        if (offsets_end > input.len) return error.TruncatedPool;
        const name_blob_start = offsets_end;
        const name_blob_end = std.math.add(usize, name_blob_start, @as(usize, name_blob_len)) catch return error.TruncatedPool;
        if (name_blob_end > input.len) return error.TruncatedPool;
        const pad = (16 - (name_blob_end & 15)) & 15;
        const data_start = std.math.add(usize, name_blob_end, pad) catch return error.TruncatedPool;
        const data_end = std.math.add(usize, data_start, @as(usize, data_len)) catch return error.TruncatedPool;
        if (data_end > input.len) return error.TruncatedPool;
        if (data_end != input.len) return error.TrailingPool;

        const bytes = try allocator.dupe(u8, input);
        errdefer allocator.free(bytes);
        if (encrypted) {
            for (bytes[name_blob_start..name_blob_end], 0..) |*byte, i| {
                byte.* ^= key[i % key.len];
            }
        }
        const names = try allocator.alloc([]const u8, name_count);
        errdefer allocator.free(names);
        var i: usize = 0;
        while (i < name_count) : (i += 1) {
            const off = readU16(input, 36 + i * 2);
            const start = std.math.add(usize, name_blob_start, @as(usize, off)) catch return error.BadPoolName;
            if (start >= name_blob_end) return error.BadPoolName;
            const end = std.mem.indexOfScalarPos(u8, bytes, start, 0) orelse return error.BadPoolName;
            if (end >= name_blob_end) return error.BadPoolName;
            names[i] = bytes[start..end];
        }
        return .{
            .bytes = bytes,
            .names = names,
            .data = bytes[data_start..data_end],
            .data_base = data_base,
            .key = key,
            .encrypted = encrypted,
        };
    }

    pub fn deinit(self: *Pool, allocator: Allocator) void {
        allocator.free(self.names);
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

fn readU16(bytes: []const u8, pos: usize) u16 {
    return @as(u16, bytes[pos]) | (@as(u16, bytes[pos + 1]) << 8);
}

fn readU32(bytes: []const u8, pos: usize) u32 {
    return @as(u32, bytes[pos]) |
        (@as(u32, bytes[pos + 1]) << 8) |
        (@as(u32, bytes[pos + 2]) << 16) |
        (@as(u32, bytes[pos + 3]) << 24);
}

fn appendU16(out: *std.ArrayList(u8), value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try out.appendSlice(&buf);
}

fn appendU32(out: *std.ArrayList(u8), value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try out.appendSlice(&buf);
}

fn appendXor(out: *std.ArrayList(u8), bytes: []const u8, key: [key_len]u8) !void {
    for (bytes, 0..) |byte, i| try out.append(byte ^ key[i % key.len]);
}

fn buildPool(
    allocator: Allocator,
    name_blob: []const u8,
    offsets: []const u16,
    data: []const u8,
    data_base: u32,
    key_opt: ?[key_len]u8,
) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const key = key_opt orelse [_]u8{0} ** key_len;
    try out.appendSlice("CIPC");
    try out.append(2);
    try out.append(if (key_opt != null) 1 else 0);
    try appendU16(&out, @intCast(offsets.len));
    try appendU32(&out, @intCast(name_blob.len));
    try appendU32(&out, @intCast(data.len));
    try appendU32(&out, data_base);
    try out.appendSlice(&key);
    for (offsets) |off| try appendU16(&out, off);
    if (key_opt) |k| {
        try appendXor(&out, name_blob, k);
    } else {
        try out.appendSlice(name_blob);
    }
    while (out.items.len % 16 != 0) try out.append(0);
    if (key_opt) |k| {
        try appendXor(&out, data, k);
    } else {
        try out.appendSlice(data);
    }
    return out.toOwnedSlice();
}

test "CIPC v2 decrypts names at load and leaves data encrypted" {
    const key = [_]u8{
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x01,
    };
    const plain_names = "cb\x00";
    const plain_data = "ab";
    const offsets = [_]u16{0};
    const encoded = try buildPool(std.testing.allocator, plain_names, &offsets, plain_data, 7, key);
    defer std.testing.allocator.free(encoded);

    var pool = try Pool.parse(std.testing.allocator, encoded);
    defer pool.deinit(std.testing.allocator);
    try std.testing.expect(pool.encrypted);
    try std.testing.expectEqualSlices(u8, &key, &pool.key);
    try std.testing.expectEqual(@as(usize, 1), pool.names.len);
    try std.testing.expectEqualStrings("cb", pool.names[0]);
    try std.testing.expectEqual(@as(u32, 7), pool.data_base);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 'a' ^ key[0], 'b' ^ key[1] }, pool.data);
}

test "CIPC v2 plaintext names and data" {
    const plain_names = "cb\x00";
    const plain_data = "ab";
    const offsets = [_]u16{0};
    const encoded = try buildPool(std.testing.allocator, plain_names, &offsets, plain_data, 0, null);
    defer std.testing.allocator.free(encoded);

    var pool = try Pool.parse(std.testing.allocator, encoded);
    defer pool.deinit(std.testing.allocator);
    try std.testing.expect(!pool.encrypted);
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** key_len), &pool.key);
    try std.testing.expectEqualStrings("cb", pool.names[0]);
    try std.testing.expectEqualSlices(u8, plain_data, pool.data);
}

test "CIPC rejects unknown flags" {
    const plain_names = "cb\x00";
    const plain_data = "ab";
    const offsets = [_]u16{0};
    const encoded = try buildPool(std.testing.allocator, plain_names, &offsets, plain_data, 0, null);
    defer std.testing.allocator.free(encoded);
    encoded[5] = 2;
    try std.testing.expectError(error.BadPoolFlags, Pool.parse(std.testing.allocator, encoded));
}
