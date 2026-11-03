//! CIPI import table construction and serialization.
//!
//! Entries are kept structured so `cinterp-cc --dump-imports` can print the
//! same provider bindings that are written into the package.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Provider = struct {
    kind: u8 = 1,
    lib: []const u8,
    symbol: []const u8,
    ordinal: u16 = 0,
    version: []const u8 = "",
};

pub const Entry = struct {
    plan_index: u16,
    name: []const u8,
    kind: u8 = 0,
    flags: u8 = 11,
    call_conv: u8 = 0,
    arch_mask: u8 = 0,
    min_os: u16 = 0,
    providers: []Provider,
};

pub const Table = struct {
    allocator: Allocator,
    entries: std.ArrayList(Entry),

    pub fn init(allocator: Allocator) Table {
        return .{ .allocator = allocator, .entries = std.ArrayList(Entry).init(allocator) };
    }

    pub fn deinit(self: *Table) void {
        self.entries.deinit();
    }

    pub fn add(self: *Table, entry: Entry) !void {
        try self.entries.append(entry);
    }

    pub fn count(self: *const Table) usize {
        return self.entries.items.len;
    }

    pub fn serialize(self: *const Table, allocator: Allocator) ![]u8 {
        if (self.entries.items.len > std.math.maxInt(u16)) return error.TooManyImports;
        var out = std.ArrayList(u8).init(allocator);
        try out.appendSlice("CIPI");
        try out.append(1);
        try out.append(0);
        try writeU16(&out, @intCast(self.entries.items.len));
        try writeU16(&out, 0);
        for (self.entries.items) |entry| {
            if (entry.name.len > 255 or entry.providers.len > 255) return error.NameTooLong;
            try writeU16(&out, entry.plan_index);
            try out.append(entry.kind);
            try out.append(entry.flags);
            try out.append(entry.call_conv);
            try out.append(entry.arch_mask);
            try writeU16(&out, entry.min_os);
            try out.append(@intCast(entry.name.len));
            try out.appendSlice(entry.name);
            try out.append(@intCast(entry.providers.len));
            for (entry.providers) |provider| {
                if (provider.lib.len > 255 or provider.symbol.len > 255 or
                    provider.version.len > 255) return error.NameTooLong;
                try out.append(provider.kind);
                try out.append(@intCast(provider.lib.len));
                try out.appendSlice(provider.lib);
                try out.append(@intCast(provider.symbol.len));
                try out.appendSlice(provider.symbol);
                try writeU16(&out, provider.ordinal);
                try out.append(@intCast(provider.version.len));
                try out.appendSlice(provider.version);
            }
        }
        return out.toOwnedSlice();
    }
};

fn writeU16(out: *std.ArrayList(u8), value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try out.appendSlice(&buf);
}

test "empty table serializes a CIPI header" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const bytes = try table.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, "CIPI", bytes[0..4]);
    try std.testing.expectEqual(@as(u8, 1), bytes[4]);
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, bytes[6..8], .little));
    try std.testing.expectEqual(@as(usize, 10), bytes.len);
}

test "entry serialization preserves providers and flags" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const providers = [_]Provider{
        .{ .lib = "libc.so.6", .symbol = "puts" },
        .{ .lib = "libm.so.6", .symbol = "puts" },
    };
    try table.add(.{
        .plan_index = 3,
        .name = "puts",
        .providers = @constCast(&providers),
    });
    const bytes = try table.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, "CIPI", bytes[0..4]);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes[6..8], .little));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "libc.so.6") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "libm.so.6") != null);
}
