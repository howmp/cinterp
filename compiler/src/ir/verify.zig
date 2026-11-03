const std = @import("std");
const ast = @import("ast.zig");

pub const Error = error{
    MissingTargetTriple,
    MissingDatalayout,
    TargetArchMismatch,
    TargetOsMismatch,
    TargetPointerWidthMismatch,
    UnsupportedEndian,
    UnsupportedArchitecture,
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

/// Validate the parsed module against the CLI target before lowering. clang's
/// triple spelling is more verbose than the cinterp target name, so compare the
/// architecture/OS components and derive pointer width from the architecture.
pub fn verify(module: *const ast.Module, expected_arch: u8, expected_os: u8, expected_ptr_bits: u8) Error!void {
    const triple = module.target_triple orelse return Error.MissingTargetTriple;
    const datalayout = module.target_datalayout orelse return Error.MissingDatalayout;

    const arch: u8 = if (contains(triple, "aarch64") or contains(triple, "arm64"))
        3
    else if (contains(triple, "x86_64") or contains(triple, "amd64"))
        1
    else if (contains(triple, "i686") or contains(triple, "i386") or contains(triple, "x86-"))
        2
    else
        return Error.UnsupportedArchitecture;
    if (arch != expected_arch) return Error.TargetArchMismatch;

    const os: u8 = if (contains(triple, "windows") or contains(triple, "win32"))
        2
    else if (contains(triple, "linux"))
        1
    else
        return Error.TargetOsMismatch;
    if (os != expected_os) return Error.TargetOsMismatch;

    const ptr_bits: u8 = if (arch == 2) 32 else 64;
    if (ptr_bits != expected_ptr_bits) return Error.TargetPointerWidthMismatch;

    // cinterp only supports little-endian targets.
    if (datalayout.len == 0 or datalayout[0] != 'e') return Error.UnsupportedEndian;
}

test "target verification accepts matching triples" {
    var m = ast.Module{
        .target_triple = "x86_64-unknown-linux-gnu",
        .target_datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64",
    };
    try verify(&m, 1, 1, 64);
    m.target_triple = "aarch64-linux-gnu";
    try verify(&m, 3, 1, 64);
    m.target_triple = "i686-pc-windows-gnu";
    try verify(&m, 2, 2, 32);
}

test "target verification rejects mismatches" {
    var m = ast.Module{
        .target_triple = "x86_64-unknown-linux-gnu",
        .target_datalayout = "e-m:e",
    };
    try std.testing.expectError(Error.TargetArchMismatch, verify(&m, 2, 1, 32));
    try std.testing.expectError(Error.TargetOsMismatch, verify(&m, 1, 2, 64));
    m.target_triple = "i686-pc-windows-gnu";
    try std.testing.expectError(Error.TargetPointerWidthMismatch, verify(&m, 2, 2, 64));
    m.target_datalayout = "E-m:e";
    try std.testing.expectError(Error.UnsupportedEndian, verify(&m, 2, 2, 32));
}
