const std = @import("std");

/// Minimal stderr output helpers. The CLI only needs strings, decimal and hex
/// integers, so this avoids instantiating `std.fmt` (and its float/alignment
/// machinery) in the runtime executable.
pub fn str(s: []const u8) void {
    write(s);
}

var output_mutex: std.Thread.Mutex = .{};

pub fn lock() void {
    output_mutex.lock();
}

pub fn unlock() void {
    output_mutex.unlock();
}

pub fn write(s: []const u8) void {
    std.io.getStdErr().writeAll(s) catch {};
}

pub fn u64dec(v: u64) void {
    var buf: [20]u8 = undefined;
    var i: usize = buf.len;
    var x = v;
    while (true) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(x % 10));
        x /= 10;
        if (x == 0) break;
    }
    write(buf[i..]);
}

pub fn usizeDec(v: usize) void {
    u64dec(v);
}

pub fn i64dec(v: i64) void {
    if (v < 0) {
        write("-");
        // Negate without overflowing on i64 min.
        u64dec(@as(u64, @intCast(-(v + 1))) + 1);
    } else {
        u64dec(@intCast(v));
    }
}

pub fn hex(v: u64) void {
    var buf: [16]u8 = undefined;
    var i: usize = buf.len;
    var x = v;
    while (true) {
        i -= 1;
        const d: u8 = @intCast(x & 0xf);
        buf[i] = if (d < 10) '0' + d else 'a' + (d - 10);
        x >>= 4;
        if (x == 0) break;
    }
    write(buf[i..]);
}

/// Decimal parse for `--repeat`/`--jobs`; mirrors the accepted grammar of
/// `std.fmt.parseUnsigned` (digits only, no sign/separators) for those flags.
pub fn parseUsize(text: []const u8) ?usize {
    if (text.len == 0) return null;
    var v: usize = 0;
    for (text) |c| {
        if (c < '0' or c > '9') return null;
        v = std.math.mul(usize, v, 10) catch return null;
        v = std.math.add(usize, v, c - '0') catch return null;
    }
    return v;
}
