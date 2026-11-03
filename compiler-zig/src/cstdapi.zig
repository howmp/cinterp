//! C standard-library link metadata.
//!
//! The database is embedded for normal builds and can be replaced with
//! `--link-db <dir>` (or a direct file path). `link_wrappers.json` is always
//! embedded: it describes ABI wrappers/aliases that are not present in the
//! public header or LLVM IR.

const std = @import("std");
const imports = @import("imports.zig");

const Allocator = std.mem.Allocator;

const db_json = @embedFile("data/cstdapi.generated.json");
const wrappers_json = @embedFile("data/link_wrappers.json");

pub const Database = struct {
    arena: std.heap.ArenaAllocator,
    root: std.json.Value,
    wrappers: std.json.Value,
    database_id: []const u8,

    pub fn initDefault(allocator: Allocator) !Database {
        return initFromSlice(allocator, db_json);
    }

    /// Load `path` as a directory containing cstdapi.generated.json or as the
    /// JSON file itself. Missing files fall back to the embedded database,
    /// matching the previous Python `set_database` behavior.
    pub fn initFromPath(allocator: Allocator, path: []const u8) !Database {
        const file = try resolveDbFile(allocator, path, "cstdapi.generated.json");
        defer if (file) |value| allocator.free(value);
        if (file) |value| {
            if (std.fs.cwd().readFileAlloc(allocator, value, 32 * 1024 * 1024)) |data| {
                defer allocator.free(data);
                return initFromSlice(allocator, data);
            } else |_| {}
        }
        return initDefault(allocator);
    }

    fn initFromSlice(allocator: Allocator, data: []const u8) !Database {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const arena_allocator = arena.allocator();
        const root = try std.json.parseFromSliceLeaky(std.json.Value, arena_allocator, data, .{});
        const wrappers = try std.json.parseFromSliceLeaky(std.json.Value, arena_allocator, wrappers_json, .{});
        const commit = stringField(root, "upstream_commit") orelse "unknown";
        const id = try std.fmt.allocPrint(arena_allocator, "cstdapi@{s}", .{commit});
        return .{
            .arena = arena,
            .root = root,
            .wrappers = wrappers,
            .database_id = id,
        };
    }

    pub fn deinit(self: *Database) void {
        self.arena.deinit();
    }

    pub fn databaseId(self: *const Database) []const u8 {
        return self.database_id;
    }

    /// Target-specific same-signature symbol alias (for example MSVC's
    /// `snprintf` -> `_snprintf`).
    pub fn alias(self: *const Database, os_id: u8, name: []const u8) ?[]const u8 {
        const aliases = objectField(self.wrappers, "aliases") orelse return null;
        if (aliases != .object) return null;
        const os_aliases = objectField(aliases, osKey(os_id)) orelse return null;
        if (os_aliases != .object) return null;
        const value = objectField(os_aliases, name) orelse return null;
        if (value != .string) return null;
        return value.string;
    }

    /// Resolve providers for an external function plan. Returns null when the
    /// symbol is not described by this database; returns
    /// `error.UnavailableSymbol` when the target explicitly marks it missing.
    pub fn lookup(
        self: *Database,
        target_name: []const u8,
        os_id: u8,
        name: []const u8,
    ) !?[]imports.Provider {
        if (try self.wrapperLookup(os_id, name)) |providers| return providers;
        if (os_id == 2) {
            for (windows_ucrt_helpers) |helper| {
                if (std.mem.eql(u8, helper, name)) {
                    const out = try self.arena.allocator().alloc(imports.Provider, 1);
                    out[0] = .{ .lib = "ucrtbase.dll", .symbol = name };
                    return out;
                }
            }
        }

        const targets = objectField(self.root, "targets") orelse return null;
        if (targets != .object) return null;
        const target = objectField(targets, target_name) orelse return null;
        if (target != .object) return null;
        const symbols = objectField(target, "symbols") orelse return null;
        if (symbols != .object) return null;
        var symbol = symbolName(name);
        if (symbol.len == 0) return null;
        var entry = objectField(symbols, symbol);
        if (entry == null and symbol.len > 0 and symbol[0] == '_') {
            symbol = symbol[1..];
            entry = objectField(symbols, symbol);
        }
        const value = entry orelse return null;
        if (value != .object) return null;
        if (value.object.get("available")) |available| {
            if (available == .bool and !available.bool) {
                std.debug.print("cinterp-cc: C standard library symbol '{s}' is unavailable on {s}\n", .{ symbol, target_name });
                return error.UnavailableSymbol;
            }
        }
        const providers_value = value.object.get("providers") orelse return null;
        return try self.parseProviders(providers_value);
    }

    fn wrapperLookup(self: *Database, os_id: u8, name: []const u8) !?[]imports.Provider {
        const targets = objectField(self.wrappers, "targets") orelse return null;
        if (targets != .object) return null;
        const os_targets = objectField(targets, osKey(os_id)) orelse return null;
        if (os_targets != .object) return null;
        var it = os_targets.object.iterator();
        while (it.next()) |entry| {
            const value = entry.value_ptr.*;
            if (value != .object) continue;
            const symbol = stringField(value, "symbol") orelse continue;
            if (!std.mem.eql(u8, symbol, name)) continue;
            const providers = value.object.get("providers") orelse return null;
            return try self.parseProviders(providers);
        }
        return null;
    }

    fn parseProviders(self: *Database, value: std.json.Value) ![]imports.Provider {
        if (value != .array) return &.{};
        var out = std.ArrayList(imports.Provider).init(self.arena.allocator());
        for (value.array.items) |item| {
            if (item != .object) continue;
            const lib = stringField(item, "lib") orelse continue;
            const symbol = stringField(item, "symbol") orelse continue;
            var kind: u8 = 1;
            if (item.object.get("kind")) |kind_value| {
                if (kind_value == .integer and kind_value.integer > 0 and kind_value.integer < 256) {
                    kind = @intCast(kind_value.integer);
                }
            }
            try out.append(.{ .kind = kind, .lib = lib, .symbol = symbol });
        }
        return out.toOwnedSlice();
    }
};

const windows_ucrt_helpers = [_][]const u8{
    "_errno",
    "__acrt_iob_func",
    "__p__environ",
    "__p__wenviron",
};

fn osKey(os_id: u8) []const u8 {
    return if (os_id == 2) "windows" else "linux";
}

fn symbolName(name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, name, "callback:") or std.mem.startsWith(u8, name, "llvm.")) {
        return "";
    }
    const end = std.mem.indexOfScalar(u8, name, '@') orelse name.len;
    return name[0..end];
}

fn objectField(value: std.json.Value, field: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(field);
}

fn stringField(value: std.json.Value, field: []const u8) ?[]const u8 {
    const field_value = objectField(value, field) orelse return null;
    if (field_value != .string) return null;
    return field_value.string;
}

fn resolveDbFile(allocator: Allocator, path: []const u8, name: []const u8) !?[]const u8 {
    if (std.fs.cwd().openDir(path, .{})) |dir_value| {
        var dir = dir_value;
        dir.close();
        return try std.fs.path.join(allocator, &.{ path, name });
    } else |_| {}
    std.fs.cwd().access(path, .{}) catch return null;
    return try allocator.dupe(u8, path);
}

test "embedded cstdapi resolves Linux providers" {
    var db = try Database.initDefault(std.testing.allocator);
    defer db.deinit();
    const providers = (try db.lookup("x86_64-linux", 1, "printf")) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(providers.len >= 1);
    try std.testing.expectEqualStrings("libc.so.6", providers[0].lib);
    try std.testing.expectEqualStrings("printf", providers[0].symbol);
}

test "Windows aliases and leading-underscore lookup" {
    var db = try Database.initDefault(std.testing.allocator);
    defer db.deinit();
    try std.testing.expectEqualStrings("_snprintf", db.alias(2, "snprintf").?);
    const providers = (try db.lookup("i686-windows", 2, "_snprintf")) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(providers.len >= 1);
    try std.testing.expectEqualStrings("ucrtbase.dll", providers[0].lib);
}

test "wrapper providers resolve __cxa_atexit" {
    var db = try Database.initDefault(std.testing.allocator);
    defer db.deinit();
    const providers = (try db.lookup("x86_64-linux", 1, "__cxa_atexit")) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("libc.so.6", providers[0].lib);
}
