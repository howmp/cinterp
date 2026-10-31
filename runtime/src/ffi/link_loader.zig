const std = @import("std");

pub const MAX_IMPORTS: usize = 256;
pub const MAX_PROVIDERS: usize = 8;
pub const MAX_IMPORT_NAME: usize = 64;
pub const MAX_PROVIDER_NAME: usize = 64;
pub const MAX_SYMBOL: usize = 64;
pub const MAX_VERSION: usize = 32;
pub const MAX_TRIPLE: usize = 96;
pub const MAX_LINK_DB: usize = 128;
pub const MAX_PRODUCER: usize = 64;

pub const TargetInfo = struct {
    arch: u8 = 0,
    os: u8 = 0,
    abi: u8 = 0,
    ptr_bits: u8 = 0,
    endian: u8 = 0,
    flags: u8 = 0,
    features: u64 = 0,
    min_runtime: u16 = 0,
    triple: [MAX_TRIPLE]u8 = undefined,
    triple_len: u16 = 0,
    link_db: [MAX_LINK_DB]u8 = undefined,
    link_db_len: u16 = 0,
    producer: [MAX_PRODUCER]u8 = undefined,
    producer_len: u16 = 0,
};

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

    fn readU64(self: *Reader) !u64 {
        const b = try self.take(8);
        var v: u64 = 0;
        var i: usize = 0;
        while (i < 8) : (i += 1) v |= @as(u64, b[i]) << @intCast(8 * i);
        return v;
    }
};

fn copyStringU16(dst: []u8, src: []const u8, len: *u16) !void {
    if (src.len > dst.len) return error.NameTooLong;
    @memcpy(dst[0..src.len], src);
    len.* = @intCast(src.len);
}

pub fn decodeTarget(bytes: []const u8) !TargetInfo {
    var r = Reader{ .data = bytes };
    const magic = try r.take(4);
    if (!std.mem.eql(u8, magic, "CIPM")) return error.BadTargetMagic;
    const version = try r.readU8();
    if (version != 1) return error.BadTargetVersion;
    const header_size = try r.readU16();
    if (header_size != 29) return error.BadTargetHeader;
    var target = TargetInfo{};
    target.arch = try r.readU8();
    target.os = try r.readU8();
    target.abi = try r.readU8();
    target.ptr_bits = try r.readU8();
    target.endian = try r.readU8();
    target.flags = try r.readU8();
    target.features = try r.readU64();
    target.min_runtime = try r.readU16();
    const triple_len = try r.readU16();
    const link_db_len = try r.readU16();
    const producer_len = try r.readU16();
    const triple = try r.take(triple_len);
    const link_db = try r.take(link_db_len);
    const producer = try r.take(producer_len);
    try copyStringU16(&target.triple, triple, &target.triple_len);
    try copyStringU16(&target.link_db, link_db, &target.link_db_len);
    try copyStringU16(&target.producer, producer, &target.producer_len);
    if (r.pos != bytes.len) return error.TrailingBytes;
    return target;
}

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
