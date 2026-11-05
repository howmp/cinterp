const std = @import("std");

pub const MAX_IMPORTS: usize = 512;
pub const MAX_PROVIDERS: usize = 8;
pub const MAX_IMPORT_NAME: usize = 64;
pub const MAX_PROVIDER_NAME: usize = 64;
pub const MAX_SYMBOL: usize = 64;
pub const MAX_VERSION: usize = 32;

pub const Provider = struct {
    kind: u8 = 0,
    name: [MAX_PROVIDER_NAME]u8 = undefined,
    name_len: u8 = 0,
    symbol: [MAX_SYMBOL]u8 = undefined,
    symbol_len: u8 = 0,
    ordinal: u16 = 0,
    version: [MAX_VERSION]u8 = undefined,
    version_len: u8 = 0,
};

pub const ImportEntry = struct {
    plan_index: u16 = 0,
    kind: u8 = 0,
    flags: u8 = 0,
    call_conv: u8 = 0,
    arch_mask: u8 = 0,
    min_os: u16 = 0,
    name: [MAX_IMPORT_NAME]u8 = undefined,
    name_len: u8 = 0,
    provider_count: u8 = 0,
    providers: [MAX_PROVIDERS]Provider = undefined,
};

pub const Table = struct {
    entries: [MAX_IMPORTS]ImportEntry = undefined,
    count: u16 = 0,

    pub fn at(self: *const Table, index: usize) ?*const ImportEntry {
        if (index >= self.count) return null;
        return &self.entries[index];
    }

    pub fn indexOfPlan(self: *const Table, plan_index: u16) ?usize {
        const total: usize = self.count;
        var i: usize = 0;
        while (i < total) : (i += 1) {
            if (self.entries[i].plan_index == plan_index) return i;
        }
        return null;
    }

    pub fn byPlan(self: *const Table, plan_index: u16) ?*const ImportEntry {
        const total: usize = self.count;
        var i: usize = 0;
        while (i < total) : (i += 1) {
            if (self.entries[i].plan_index == plan_index) return &self.entries[i];
        }
        return null;
    }
};

const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    fn take(self: *Reader, n: usize) ![]const u8 {
        if (self.pos + n > self.data.len) return error.Truncated;
        const out = self.data[self.pos .. self.pos + n];
        self.pos += n;
        return out;
    }

    fn readU8(self: *Reader) !u8 {
        const b = try self.take(1);
        return b[0];
    }

    fn readU16(self: *Reader) !u16 {
        const b = try self.take(2);
        return @as(u16, b[0]) | (@as(u16, b[1]) << 8);
    }
};

fn copyStringU8(dst: []u8, src: []const u8, len: *u8) !void {
    if (src.len > dst.len or src.len > 255) return error.NameTooLong;
    @memcpy(dst[0..src.len], src);
    len.* = @intCast(src.len);
}

fn readProvider(r: *Reader) !Provider {
    var p = Provider{};
    p.kind = try r.readU8();
    const name_len = try r.readU8();
    const name = try r.take(name_len);
    try copyStringU8(&p.name, name, &p.name_len);
    const symbol_len = try r.readU8();
    const symbol = try r.take(symbol_len);
    try copyStringU8(&p.symbol, symbol, &p.symbol_len);
    p.ordinal = try r.readU16();
    const version_len = try r.readU8();
    const version = try r.take(version_len);
    try copyStringU8(&p.version, version, &p.version_len);
    return p;
}

pub fn decodeImports(bytes: []const u8) !Table {
    var table = Table{};
    if (bytes.len == 0) return table;
    var r = Reader{ .data = bytes };
    const magic = try r.take(4);
    if (!std.mem.eql(u8, magic, "CIPI")) return error.BadImportMagic;
    const version = try r.readU8();
    if (version != 1) return error.BadImportVersion;
    _ = try r.readU8();
    const count = try r.readU16();
    _ = try r.readU16();
    if (count > MAX_IMPORTS) return error.TooManyImports;
    table.count = count;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        var entry = ImportEntry{};
        entry.plan_index = try r.readU16();
        entry.kind = try r.readU8();
        entry.flags = try r.readU8();
        entry.call_conv = try r.readU8();
        entry.arch_mask = try r.readU8();
        entry.min_os = try r.readU16();
        const name_len = try r.readU8();
        const name = try r.take(name_len);
        try copyStringU8(&entry.name, name, &entry.name_len);
        const provider_count = try r.readU8();
        if (provider_count > MAX_PROVIDERS) return error.TooManyProviders;
        entry.provider_count = provider_count;
        var pi: usize = 0;
        while (pi < provider_count) : (pi += 1) {
            entry.providers[pi] = try readProvider(&r);
        }
        table.entries[i] = entry;
    }
    if (r.pos != bytes.len) return error.TrailingBytes;
    return table;
}
