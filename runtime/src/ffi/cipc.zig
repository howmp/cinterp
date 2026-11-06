//! Runtime CIPC name/data pool.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Pool = struct {
    bytes: []u8,
    names: [][]const u8,
    data: []const u8,
    data_base: u32,

    pub fn parse(allocator: Allocator, input: []const u8) !Pool {
        if (input.len < 20 or !std.mem.eql(u8, input[0..4], "CIPC")) return error.BadPool;
        if (input[4] != 1) return error.BadPoolVersion;
        const name_count = readU16(input, 6);
        const name_blob_len = readU32(input, 8);
        const data_len = readU32(input, 12);
        const data_base = readU32(input, 16);
        const offsets_end = 20 + @as(usize, name_count) * 2;
        if (offsets_end > input.len) return error.TruncatedPool;
        const name_blob_start = offsets_end;
        if (name_blob_start + name_blob_len > input.len) return error.TruncatedPool;
        var data_start = name_blob_start + name_blob_len;
        data_start = (data_start + 15) & ~@as(usize, 15);
        if (data_start + data_len > input.len) return error.TruncatedPool;
        if (data_start + data_len != input.len) return error.TrailingPool;

        const bytes = try allocator.dupe(u8, input);
        errdefer allocator.free(bytes);
        const names = try allocator.alloc([]const u8, name_count);
        errdefer allocator.free(names);
        var i: usize = 0;
        while (i < name_count) : (i += 1) {
            const off = readU16(input, 20 + i * 2);
            const start = name_blob_start + off;
            if (start >= name_blob_start + name_blob_len) return error.BadPoolName;
            const end = std.mem.indexOfScalarPos(u8, bytes, start, 0) orelse return error.BadPoolName;
            if (end >= name_blob_start + name_blob_len) return error.BadPoolName;
            names[i] = bytes[start..end];
        }
        return .{
            .bytes = bytes,
            .names = names,
            .data = bytes[data_start .. data_start + data_len],
            .data_base = data_base,
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
