//! CIPI import table construction and serialization.
//!
//! Entries are kept structured so `cinterp-cc --dump-imports` can print the
//! same provider bindings that are written into the package.

const std = @import("std");
const cipc = @import("cipc.zig");

const Allocator = std.mem.Allocator;

/// Caps read by `runtime/src/ffi/link_loader.zig`. The compiler cannot import
/// `runtime/`, so keep these in sync; `main.zig`'s `validateLimits` reports a
/// `compiler limit: ...` diagnostic before serialization, and `serialize`
/// re-checks them so no package the runtime would reject can be written.
pub const MAX_IMPORTS: usize = 512;
pub const MAX_PROVIDERS: usize = 8;
pub const MAX_IMPORT_NAME: usize = 64;
pub const MAX_PROVIDER_NAME: usize = 64;
pub const MAX_SYMBOL: usize = 64;
pub const MAX_VERSION: usize = 32;

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

    /// Add every string that the CIPI writer will reference to the CIPC name
    /// pool. Must be called before `cipc.serialize`.
    pub fn internNames(self: *const Table, names: *cipc.NamePool) !void {
        for (self.entries.items) |entry| {
            if (entry.kind != 0) _ = try names.ref(entry.name);
            for (entry.providers) |provider| {
                if (provider.lib.len > 0) _ = try names.ref(provider.lib);
                if (provider.symbol.len > 0 and !std.mem.eql(u8, provider.symbol, entry.name)) {
                    _ = try names.ref(provider.symbol);
                }
            }
        }
    }

    pub fn serialize(self: *const Table, allocator: Allocator, names: *const cipc.NamePool) ![]u8 {
        if (self.entries.items.len > MAX_IMPORTS) return error.TooManyImports;
        if (self.entries.items.len == 0) return allocator.alloc(u8, 0);
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        try writeU16(&out, @intCast(self.entries.items.len));
        for (self.entries.items) |entry| {
            if (entry.name.len > MAX_IMPORT_NAME) return error.NameTooLong;
            if (entry.providers.len > MAX_PROVIDERS) return error.TooManyProviders;
            try writeU16(&out, entry.plan_index);
            try out.append(entry.kind);
            try out.append(entry.flags);
            // Function entries derive the name from CIPL; data entries need a
            // real name reference.
            if (entry.kind == 0) {
                try writeU16(&out, 0xFFFF);
            } else {
                try writeU16(&out, names.get(entry.name) orelse return error.NameNotInterned);
            }
            try out.append(@intCast(entry.providers.len));
            for (entry.providers) |provider| {
                if (provider.lib.len > MAX_PROVIDER_NAME or provider.symbol.len > MAX_SYMBOL)
                    return error.NameTooLong;
                const lib_ref = names.get(provider.lib) orelse return error.NameNotInterned;
                const symbol_ref: u16 = if (provider.symbol.len == 0 or
                    std.mem.eql(u8, provider.symbol, entry.name))
                    0xFFFF
                else
                    names.get(provider.symbol) orelse return error.NameNotInterned;
                try writeU16(&out, lib_ref);
                try writeU16(&out, symbol_ref);
                try writeU16(&out, provider.ordinal);
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

test "empty table serializes no CIPI bytes" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    var names = cipc.NamePool.init(std.testing.allocator);
    defer names.deinit();
    const bytes = try table.serialize(std.testing.allocator, &names);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
}

test "entry serialization preserves providers and flags" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    var names = cipc.NamePool.init(std.testing.allocator);
    defer names.deinit();
    const providers = [_]Provider{
        .{ .lib = "libc.so.6", .symbol = "puts" },
        .{ .lib = "libm.so.6", .symbol = "puts" },
    };
    try table.add(.{
        .plan_index = 3,
        .name = "puts",
        .providers = @constCast(&providers),
    });
    try table.internNames(&names);
    const bytes = try table.serialize(std.testing.allocator, &names);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes[0..2], .little));
    try std.testing.expectEqual(@as(u16, 0xFFFF), std.mem.readInt(u16, bytes[6..8], .little));
    try std.testing.expectEqual(@as(u8, 2), bytes[8]);
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, bytes[9..11], .little));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes[15..17], .little));
}

test "serialization rejects records beyond the runtime caps" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();

    var names = cipc.NamePool.init(std.testing.allocator);
    defer names.deinit();
    const no_providers: [0]Provider = .{};
    // > 64-byte import name.
    try table.add(.{ .plan_index = 0, .name = "i" ** 65, .providers = @constCast(&no_providers) });
    try table.internNames(&names);
    try std.testing.expectError(error.NameTooLong, table.serialize(std.testing.allocator, &names));

    var long_lib = Table.init(std.testing.allocator);
    defer long_lib.deinit();
    const bad_provider = [_]Provider{.{ .lib = "l" ** 65, .symbol = "puts" }};
    try long_lib.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&bad_provider) });
    try long_lib.internNames(&names);
    try std.testing.expectError(error.NameTooLong, long_lib.serialize(std.testing.allocator, &names));

    var long_symbol = Table.init(std.testing.allocator);
    defer long_symbol.deinit();
    const bad_symbol = [_]Provider{.{ .lib = "libc.so.6", .symbol = "s" ** 65 }};
    try long_symbol.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&bad_symbol) });
    try long_symbol.internNames(&names);
    try std.testing.expectError(error.NameTooLong, long_symbol.serialize(std.testing.allocator, &names));

    var many_providers = Table.init(std.testing.allocator);
    defer many_providers.deinit();
    const nine = [_]Provider{.{ .lib = "libc.so.6", .symbol = "puts" }} ** 9;
    try many_providers.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&nine) });
    try many_providers.internNames(&names);
    try std.testing.expectError(error.TooManyProviders, many_providers.serialize(std.testing.allocator, &names));

    var many_imports = Table.init(std.testing.allocator);
    defer many_imports.deinit();
    var i: usize = 0;
    while (i <= MAX_IMPORTS) : (i += 1) {
        try many_imports.add(.{ .plan_index = 0, .name = "puts", .providers = @constCast(&no_providers) });
    }
    try many_imports.internNames(&names);
    try std.testing.expectError(error.TooManyImports, many_imports.serialize(std.testing.allocator, &names));
}
