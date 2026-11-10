pub const LocKind = enum { gpr, xmm, stack, sret, rax, rdx, xmm0, xmm1, st0, xmm2, xmm3 };

pub const Loc = struct {
    kind: LocKind,
    index: u16 = 0,
    size: u16,
    offset: u16,
};

pub const ArgPlan = struct {
    locs: []const Loc,
    size: u16,
    alignment: u16,
    is_struct: bool = false,
};

pub const CallPlan = struct {
    args: []const ArgPlan,
    ret_locs: []const Loc,
    stack_size: u16 = 0,
    stack_align: u16 = 8,
    sret: bool = false,
    sse_count: u8 = 0,
    ret_size: u16 = 0,
    conv: u8 = 0,
    native: bool = false,
};
