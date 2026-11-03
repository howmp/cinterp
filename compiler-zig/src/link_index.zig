//! Shared binary format for the build-time-generated external-symbol indexes.
//!
//! `tools/gen_link_index.zig` writes this format from the installed Zig
//! toolchain (MinGW `.def` files for Windows, glibc `abilists` for Linux).
//! `src/win_defs.zig` and `src/libc_defs.zig` read it. The generated blob is
//! embedded with `@embedFile`, so lookups are pure memory reads: no JSON or
//! gzip parsing at compiler startup.
//!
//! All integers are little-endian.
//!
//! ```text
//! header (40 bytes)
//!   0  magic[4] = "CILI"
//!   4  version u8 = 1
//!   5  kind u8 (1 = Windows MinGW defs, 2 = glibc abilists)
//!   6  entry_size u8 = 20
//!   7  flags u8 = 0
//!   8  entry_count u32
//!  12  entry_off u32
//!  16  lib_off u32
//!  20  lib_count u16
//!  22  reserved u16
//!  24  string_off u32
//!  28  string_len u32
//!  32  source_off u32
//!  36  source_len u16
//!  38  reserved u16
//! lib table: lib_count entries of { off u32, len u16 }
//! entries: entry_count entries of 20 bytes
//!   0  key_off u32
//!   4  key_len u16
//!   6  sym_off u32
//!  10  sym_len u16
//!  12  lib_id u16
//!  14  arch_mask u8   (1 = x86_64, 2 = x86, 4 = aarch64; 0 = any)
//!  15  conv_bits u8   (bit0 = x86/stdcall, bit1 = x64/winapi; per-arch)
//!  16  priority u8    (lower sorts first)
//!  17  flags u8       (bit0 = DATA export)
//!  18  reserved u16
//! string pool: keys, symbols, library names
//! ```
//!
//! Entries are sorted by key bytes, then priority, then library name so a
//! lower-bound binary search yields every provider for a key in priority
//! order.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const magic = "CILI";
pub const format_version: u8 = 1;
pub const header_size: usize = 40;
pub const entry_size: usize = 20;
pub const lib_entry_size: usize = 6;

pub const Kind = enum(u8) {
    windows = 1,
    glibc = 2,
};

pub const arch_x86_64: u8 = 1;
pub const arch_x86: u8 = 2;
pub const arch_aarch64: u8 = 3;

pub fn archMask(arch: u8) u8 {
    return switch (arch) {
        arch_x86_64 => 1,
        arch_x86 => 2,
        arch_aarch64 => 4,
        else => 0,
    };
}

pub fn convForArch(conv_bits: u8, arch: u8) u8 {
    return switch (arch) {
        arch_x86 => conv_bits & 1,
        arch_x86_64 => (conv_bits >> 1) & 1,
        else => 0,
    };
}

pub const Header = struct {
    kind: Kind,
    entry_count: u32,
    entry_off: u32,
    lib_off: u32,
    lib_count: u16,
    string_off: u32,
    string_len: u32,
    source_off: u32,
    source_len: u16,

    pub fn source(self: Header, blob: []const u8) []const u8 {
        const start = @as(usize, self.string_off) + @as(usize, self.source_off);
        return blob[start .. start + self.source_len];
    }
};

pub const Entry = struct {
    key: []const u8,
    symbol: []const u8,
    lib_id: u16,
    arch_mask: u8,
    conv_bits: u8,
    priority: u8,
    flags: u8,

    pub fn conv(self: Entry, arch: u8) u8 {
        return convForArch(self.conv_bits, arch);
    }
};

pub fn parse(blob: []const u8) !Header {
    if (blob.len < header_size) return error.TruncatedIndex;
    if (!std.mem.eql(u8, blob[0..4], magic)) return error.BadIndexMagic;
    if (blob[4] != format_version) return error.BadIndexVersion;
    if (blob[6] != entry_size) return error.BadIndexEntrySize;
    const kind = std.meta.intToEnum(Kind, blob[5]) catch return error.BadIndexKind;
    const header = Header{
        .kind = kind,
        .entry_count = std.mem.readInt(u32, blob[8..12], .little),
        .entry_off = std.mem.readInt(u32, blob[12..16], .little),
        .lib_off = std.mem.readInt(u32, blob[16..20], .little),
        .lib_count = std.mem.readInt(u16, blob[20..22], .little),
        .string_off = std.mem.readInt(u32, blob[24..28], .little),
        .string_len = std.mem.readInt(u32, blob[28..32], .little),
        .source_off = std.mem.readInt(u32, blob[32..36], .little),
        .source_len = std.mem.readInt(u16, blob[36..38], .little),
    };
    const strings_end = @as(usize, header.string_off) + @as(usize, header.string_len);
    if (strings_end > blob.len) return error.TruncatedIndex;
    const entries_end = @as(usize, header.entry_off) +
        @as(usize, header.entry_count) * entry_size;
    if (entries_end > blob.len) return error.TruncatedIndex;
    if (header.entry_off < header_size) return error.BadIndexOffset;
    const libs_end = @as(usize, header.lib_off) +
        @as(usize, header.lib_count) * lib_entry_size;
    if (libs_end > blob.len) return error.TruncatedIndex;
    if (@as(usize, header.source_off) + @as(usize, header.source_len) > header.string_len)
        return error.BadIndexOffset;
    return header;
}

fn stringAt(blob: []const u8, header: Header, off: u32, len: u32) ![]const u8 {
    if (@as(usize, off) + @as(usize, len) > header.string_len) return error.BadIndexOffset;
    const start = @as(usize, header.string_off) + @as(usize, off);
    return blob[start .. start + len];
}

pub fn entryAt(blob: []const u8, header: Header, index: usize) !Entry {
    if (index >= header.entry_count) return error.IndexOutOfRange;
    const base = @as(usize, header.entry_off) + index * entry_size;
    if (base + entry_size > blob.len) return error.TruncatedIndex;
    const record = blob[base .. base + entry_size];
    return .{
        .key = try stringAt(blob, header, std.mem.readInt(u32, record[0..4], .little), std.mem.readInt(u16, record[4..6], .little)),
        .symbol = try stringAt(blob, header, std.mem.readInt(u32, record[6..10], .little), std.mem.readInt(u16, record[10..12], .little)),
        .lib_id = std.mem.readInt(u16, record[12..14], .little),
        .arch_mask = record[14],
        .conv_bits = record[15],
        .priority = record[16],
        .flags = record[17],
    };
}

pub fn libAt(blob: []const u8, header: Header, id: u16) ![]const u8 {
    if (id >= header.lib_count) return error.IndexOutOfRange;
    const base = @as(usize, header.lib_off) + @as(usize, id) * lib_entry_size;
    if (base + lib_entry_size > blob.len) return error.TruncatedIndex;
    const record = blob[base .. base + lib_entry_size];
    return stringAt(blob, header, std.mem.readInt(u32, record[0..4], .little), std.mem.readInt(u16, record[4..6], .little));
}

/// First entry index whose key is >= `key` (lower bound over the sorted table).
pub fn firstKey(blob: []const u8, header: Header, key: []const u8) !u32 {
    var lo: u32 = 0;
    var hi: u32 = header.entry_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const entry = try entryAt(blob, header, mid);
        if (std.mem.order(u8, entry.key, key) == .lt) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

/// Input row accepted by `Builder.add`. `conv_bits` uses the same per-arch
/// encoding as `Entry.conv_bits`; `rank` decides which symbol spelling and
/// conversion wins when the same (key, library) pair is seen again (lower is
/// more authoritative: 0 = architecture-specific def, 1 = common def).
pub const Input = struct {
    key: []const u8,
    symbol: []const u8,
    lib: []const u8,
    arch_mask: u8,
    conv_bits: u8,
    priority: u8,
    flags: u8 = 0,
    rank: u8 = 0,
};

const Pending = struct {
    key: []const u8,
    symbol: []const u8,
    lib: []const u8,
    arch_mask: u8,
    conv_bits: u8,
    priority: u8,
    flags: u8,
    rank: u8,
};

/// Accumulates deduplicated rows and serializes them into the binary format.
/// All input slices must outlive the builder (the generators use an arena).
pub const Builder = struct {
    allocator: Allocator,
    kind: Kind,
    source: []const u8,
    rows: std.ArrayList(Pending),
    by_key_lib: std.StringHashMap(usize),

    pub fn init(allocator: Allocator, kind: Kind, source: []const u8) Builder {
        return .{
            .allocator = allocator,
            .kind = kind,
            .source = source,
            .rows = std.ArrayList(Pending).init(allocator),
            .by_key_lib = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Builder) void {
        self.rows.deinit();
        self.by_key_lib.deinit();
    }

    pub fn count(self: *const Builder) usize {
        return self.rows.items.len;
    }

    pub fn add(self: *Builder, input: Input) !void {
        const composite = try std.mem.concat(self.allocator, u8, &.{ input.key, "\x00", input.lib });
        if (self.by_key_lib.get(composite)) |index| {
            const existing = &self.rows.items[index];
            existing.arch_mask |= input.arch_mask;
            existing.conv_bits |= input.conv_bits;
            existing.flags |= input.flags;
            if (input.priority < existing.priority) existing.priority = input.priority;
            if (input.rank < existing.rank) {
                existing.symbol = input.symbol;
                existing.rank = input.rank;
            }
            return;
        }
        try self.by_key_lib.put(composite, self.rows.items.len);
        try self.rows.append(.{
            .key = input.key,
            .symbol = input.symbol,
            .lib = input.lib,
            .arch_mask = input.arch_mask,
            .conv_bits = input.conv_bits,
            .priority = input.priority,
            .flags = input.flags,
            .rank = input.rank,
        });
    }

    /// Library names in sorted order; also the id assignment used by the table.
    fn sortedLibs(self: *Builder, list: *std.ArrayList([]const u8)) !void {
        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();
        for (self.rows.items) |row| {
            if (seen.contains(row.lib)) continue;
            try seen.put(row.lib, {});
            try list.append(row.lib);
        }
        std.mem.sort([]const u8, list.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);
    }

    fn entryLessThan(_: void, a: Pending, b: Pending) bool {
        const order = std.mem.order(u8, a.key, b.key);
        if (order != .eq) return order == .lt;
        if (a.priority != b.priority) return a.priority < b.priority;
        const lib_order = std.mem.order(u8, a.lib, b.lib);
        if (lib_order != .eq) return lib_order == .lt;
        return std.mem.order(u8, a.symbol, b.symbol) == .lt;
    }

    pub fn finish(self: *Builder) ![]u8 {
        std.mem.sort(Pending, self.rows.items, {}, entryLessThan);

        var libs = std.ArrayList([]const u8).init(self.allocator);
        defer libs.deinit();
        try self.sortedLibs(&libs);
        if (libs.items.len > std.math.maxInt(u16)) return error.TooManyLibraries;
        var lib_ids = std.StringHashMap(u16).init(self.allocator);
        defer lib_ids.deinit();
        for (libs.items, 0..) |lib, index| {
            try lib_ids.put(lib, @intCast(index));
        }

        var strings = std.ArrayList(u8).init(self.allocator);
        defer strings.deinit();
        var string_offsets = std.StringHashMap(u32).init(self.allocator);
        defer string_offsets.deinit();

        const Interned = struct {
            fn get(pool: *std.ArrayList(u8), map: *std.StringHashMap(u32), value: []const u8) !u32 {
                if (map.get(value)) |offset| return offset;
                const offset: u32 = @intCast(pool.items.len);
                if (value.len > std.math.maxInt(u16)) return error.StringTooLong;
                try pool.appendSlice(value);
                try map.put(value, offset);
                return offset;
            }
        };

        const source_off = try Interned.get(&strings, &string_offsets, self.source);

        const entry_off = header_size + libs.items.len * lib_entry_size;
        const string_off = entry_off + self.rows.items.len * entry_size;
        if (string_off > std.math.maxInt(u32)) return error.IndexTooLarge;

        var out = std.ArrayList(u8).init(self.allocator);
        errdefer out.deinit();
        try out.ensureTotalCapacity(entry_off + self.rows.items.len * entry_size);

        var header = [_]u8{0} ** header_size;
        @memcpy(header[0..4], magic);
        header[4] = format_version;
        header[5] = @intFromEnum(self.kind);
        header[6] = entry_size;
        writeU32(header[8..12], @intCast(self.rows.items.len));
        writeU32(header[12..16], @intCast(entry_off));
        writeU32(header[16..20], @intCast(header_size));
        writeU16(header[20..22], @intCast(libs.items.len));
        writeU32(header[24..28], @intCast(string_off));
        writeU32(header[32..36], source_off);
        writeU16(header[36..38], @intCast(self.source.len));
        try out.appendSlice(&header);

        for (libs.items) |lib| {
            const off = try Interned.get(&strings, &string_offsets, lib);
            var record = [_]u8{0} ** lib_entry_size;
            writeU32(record[0..4], off);
            writeU16(record[4..6], @intCast(lib.len));
            try out.appendSlice(&record);
        }

        for (self.rows.items) |row| {
            const key_off = try Interned.get(&strings, &string_offsets, row.key);
            const symbol_off = try Interned.get(&strings, &string_offsets, row.symbol);
            var record = [_]u8{0} ** entry_size;
            writeU32(record[0..4], key_off);
            writeU16(record[4..6], @intCast(row.key.len));
            writeU32(record[6..10], symbol_off);
            writeU16(record[10..12], @intCast(row.symbol.len));
            writeU16(record[12..14], lib_ids.get(row.lib).?);
            record[14] = row.arch_mask;
            record[15] = row.conv_bits;
            record[16] = row.priority;
            record[17] = row.flags;
            try out.appendSlice(&record);
        }

        try out.appendSlice(strings.items);
        const string_len: u32 = @intCast(strings.items.len);
        writeU32(out.items[28..32], string_len);
        return out.toOwnedSlice();
    }
};

fn writeU16(dst: []u8, value: u16) void {
    std.mem.writeInt(u16, dst[0..2], value, .little);
}

fn writeU32(dst: []u8, value: u32) void {
    std.mem.writeInt(u32, dst[0..4], value, .little);
}

test "builder round-trips entries sorted by key and priority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var builder = Builder.init(allocator, .windows, "test@0");
    try builder.add(.{ .key = "MessageBoxA", .symbol = "MessageBoxA", .lib = "user32.dll", .arch_mask = 2, .conv_bits = 1, .priority = 0, .rank = 0 });
    try builder.add(.{ .key = "MessageBoxA", .symbol = "MessageBoxA", .lib = "api-ms-win-ntuser-dialogbox-l1-1-0", .arch_mask = 3, .conv_bits = 1, .priority = 16, .rank = 1 });
    try builder.add(.{ .key = "GetTickCount64", .symbol = "GetTickCount64", .lib = "kernel32.dll", .arch_mask = 3, .conv_bits = 3, .priority = 5, .rank = 0 });
    const blob = try builder.finish();

    const header = try parse(blob);
    try std.testing.expectEqual(Kind.windows, header.kind);
    try std.testing.expectEqual(@as(u32, 3), header.entry_count);
    try std.testing.expectEqualStrings("test@0", header.source(blob));

    const first = try firstKey(blob, header, "MessageBoxA");
    const entry = try entryAt(blob, header, first);
    try std.testing.expectEqualStrings("user32.dll", try libAt(blob, header, entry.lib_id));
    try std.testing.expectEqual(@as(u8, 1), entry.conv(2));
    try std.testing.expectEqual(@as(u8, 0), entry.conv(1));
    const second = try entryAt(blob, header, first + 1);
    try std.testing.expectEqualStrings("MessageBoxA", second.key);
    try std.testing.expectEqual(@as(u8, 0), second.conv(1));
}

test "builder merges duplicate key and library rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var builder = Builder.init(allocator, .glibc, "glibc@0");
    try builder.add(.{ .key = "printf", .symbol = "printf", .lib = "libc.so.6", .arch_mask = 1, .conv_bits = 0, .priority = 0 });
    try builder.add(.{ .key = "printf", .symbol = "printf", .lib = "libc.so.6", .arch_mask = 4, .conv_bits = 0, .priority = 0 });
    const blob = try builder.finish();
    const header = try parse(blob);
    try std.testing.expectEqual(@as(u32, 1), header.entry_count);
    const entry = try entryAt(blob, header, 0);
    try std.testing.expectEqual(@as(u8, 5), entry.arch_mask);
}
