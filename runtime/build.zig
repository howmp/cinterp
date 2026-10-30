const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cinterp-run",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addAssemblyFile(b.path("src/ffi/asm/call_x86_64_sysv.S"));
    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run cinterp-run <package.cib>");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/vm_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.addAssemblyFile(b.path("src/ffi/asm/call_x86_64_sysv.S"));
    tests.linkLibC();
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run runtime unit tests");
    test_step.dependOn(&run_tests.step);
}
