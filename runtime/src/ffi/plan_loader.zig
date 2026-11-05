const std = @import("std");
const abi = @import("abi.zig");

pub const MAX_PLANS: usize = 1024;
pub const MAX_ARGS: usize = 64;
pub const MAX_LOCS: usize = 8;
pub const MAX_NAME: usize = 128;

pub const StoredArg = struct {
    locs: [MAX_LOCS]abi.Loc = undefined,
    loc_count: u16 = 0,
    size: u16 = 0,
    alignment: u16 = 0,
    is_struct: bool = false,
};

pub const StoredPlan = struct {
    name: [MAX_NAME]u8 = undefined,
    name_len: u8 = 0,
    args: [MAX_ARGS]StoredArg = undefined,
    arg_plans: [MAX_ARGS]abi.ArgPlan = undefined,
    arg_count: u16 = 0,
    ret_locs: [MAX_LOCS]abi.Loc = undefined,
    ret_count: u16 = 0,
    stack_size: u16 = 0,
    sret: bool = false,
    sse_count: u8 = 0,
    ret_size: u16 = 0,
    conv: u8 = 0,
};

pub const Store = struct {
    plans: []StoredPlan = &.{},
    count: u16 = 0,
    abi_id: u8 = 0,

    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        allocator.free(self.plans);
        allocator.destroy(self);
    }

    pub fn find(self: *const Store, name: []const u8) ?*const StoredPlan {
        const count: usize = self.count;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const p = &self.plans[i];
            const n: usize = p.name_len;
            if (std.mem.eql(u8, p.name[0..n], name)) return p;
        }
        return null;
    }

    pub fn indexOf(self: *const Store, name: []const u8) ?u16 {
        const count: usize = self.count;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const p = &self.plans[i];
            const n: usize = p.name_len;
            if (std.mem.eql(u8, p.name[0..n], name)) return @intCast(i);
        }
        return null;
    }

    pub fn planAt(self: *const Store, index: usize) ?*const StoredPlan {
        const count: usize = self.count;
        if (index >= count) return null;
        return &self.plans[index];
    }

    pub fn callPlan(self: *const Store, p: *const StoredPlan) abi.CallPlan {
        _ = self;
        const ac: usize = p.arg_count;
        const rc: usize = p.ret_count;
        return .{
            .args = p.arg_plans[0..ac],
            .ret_locs = p.ret_locs[0..rc],
            .stack_size = p.stack_size,
            .sret = p.sret,
            .sse_count = p.sse_count,
            .ret_size = p.ret_size,
            .conv = p.conv,
        };
    }

    pub fn get(self: *const Store, name: []const u8) ?abi.CallPlan {
        const p = self.find(name) orelse return null;
        return self.callPlan(p);
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

fn readLoc(r: *Reader) !abi.Loc {
    const kind_byte = try r.readU8();
    const kind: abi.LocKind = switch (kind_byte) {
        0 => .gpr,
        1 => .xmm,
        2 => .stack,
        3 => .sret,
        4 => .rax,
        5 => .rdx,
        6 => .xmm0,
        7 => .xmm1,
        8 => .st0,
        9 => .xmm2,
        10 => .xmm3,
        else => return error.BadLocKind,
    };
    const index = try r.readU16();
    const size = try r.readU16();
    const offset = try r.readU16();
    return .{ .kind = kind, .index = index, .size = size, .offset = offset };
}

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, names: []const []const u8) !*Store {
    var r = Reader{ .data = bytes };
    const abi_id = try r.readU8();
    if (abi_id < 1 or abi_id > 4) return error.BadAbi;
    const count = try r.readU16();
    if (count > MAX_PLANS) return error.TooManyPlans;

    const store = try allocator.create(Store);
    errdefer allocator.destroy(store);
    store.plans = try allocator.alloc(StoredPlan, @as(usize, count));
    errdefer allocator.free(store.plans);
    store.count = count;
    store.abi_id = abi_id;

    const total: usize = count;
    var pi: usize = 0;
    while (pi < total) : (pi += 1) {
        const plan = &store.plans[pi];
        const name_ref = try r.readU16();
        if (name_ref >= names.len) return error.BadConstIndex;
        const name = names[name_ref];
        if (name.len > MAX_NAME) return error.NameTooLong;
        @memcpy(plan.name[0..name.len], name);
        plan.name_len = @intCast(name.len);

        const args_count = try r.readU8();
        const ret_count = try r.readU8();
        const stack_size = try r.readU16();
        const flags = try r.readU8();
        const ret_size = try r.readU16();

        const ac: usize = args_count;
        const rc: usize = ret_count;
        if (ac > MAX_ARGS) return error.TooManyArgs;
        if (rc > MAX_LOCS) return error.TooManyLocs;
        plan.arg_count = args_count;
        plan.ret_count = ret_count;
        plan.stack_size = stack_size;
        plan.sret = (flags & 1) != 0;
        plan.sse_count = (flags >> 1) & 0xf;
        plan.conv = (flags >> 5) & 3;
        plan.ret_size = ret_size;

        var ai: usize = 0;
        while (ai < ac) : (ai += 1) {
            const arg = &plan.args[ai];
            const arg_flags = try r.readU8();
            const loc_count = arg_flags & 0x0f;
            const lc: usize = loc_count;
            const size = try r.readU16();
            const is_struct = (arg_flags & 0x80) != 0;
            if (lc > MAX_LOCS) return error.TooManyLocs;
            arg.loc_count = loc_count;
            arg.size = size;
            arg.alignment = size;
            arg.is_struct = is_struct;

            var li: usize = 0;
            while (li < lc) : (li += 1) {
                arg.locs[li] = try readLoc(&r);
            }
            plan.arg_plans[ai] = .{
                .locs = arg.locs[0..lc],
                .size = size,
                .alignment = size,
                .is_struct = is_struct,
            };
        }

        var ri: usize = 0;
        while (ri < rc) : (ri += 1) {
            plan.ret_locs[ri] = try readLoc(&r);
        }
    }

    if (r.pos != bytes.len) return error.TrailingBytes;
    return store;
}
