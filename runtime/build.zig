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
    const t = target.result;
    if (t.os.tag == .windows and t.cpu.arch == .x86_64) {
        exe.addAssemblyFile(b.path("src/ffi/asm/call_x86_64_win64.S"));
        exe.addAssemblyFile(b.path("src/ffi/asm/callbacks_x86_64_win64.S"));
    } else if (t.os.tag == .windows and t.cpu.arch == .x86) {
        exe.addAssemblyFile(b.path("src/ffi/asm/call_x86_win32.S"));
        exe.addAssemblyFile(b.path("src/ffi/asm/callbacks_x86_win32.S"));
    } else if (t.cpu.arch == .aarch64) {
        exe.addAssemblyFile(b.path("src/ffi/asm/call_arm64_aapcs.S"));
        exe.addAssemblyFile(b.path("src/ffi/asm/callbacks_arm64_aapcs.S"));
    } else {
        exe.addAssemblyFile(b.path("src/ffi/asm/call_x86_64_sysv.S"));
        exe.addAssemblyFile(b.path("src/ffi/asm/callbacks_x86_64_sysv.S"));
    }
    const release = optimize == .ReleaseSmall or optimize == .ReleaseFast;
    exe.root_module.unwind_tables = !release;
    exe.root_module.error_tracing = !release;
    exe.root_module.omit_frame_pointer = release;
    exe.root_module.strip = release;
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
    if (t.os.tag == .windows and t.cpu.arch == .x86_64) {
        tests.addAssemblyFile(b.path("src/ffi/asm/call_x86_64_win64.S"));
        tests.addAssemblyFile(b.path("src/ffi/asm/callbacks_x86_64_win64.S"));
    } else if (t.os.tag == .windows and t.cpu.arch == .x86) {
        tests.addAssemblyFile(b.path("src/ffi/asm/call_x86_win32.S"));
        tests.addAssemblyFile(b.path("src/ffi/asm/callbacks_x86_win32.S"));
    } else if (t.cpu.arch == .aarch64) {
        tests.addAssemblyFile(b.path("src/ffi/asm/call_arm64_aapcs.S"));
        tests.addAssemblyFile(b.path("src/ffi/asm/callbacks_arm64_aapcs.S"));
    } else {
        tests.addAssemblyFile(b.path("src/ffi/asm/call_x86_64_sysv.S"));
        tests.addAssemblyFile(b.path("src/ffi/asm/callbacks_x86_64_sysv.S"));
    }
    tests.linkLibC();
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run runtime unit tests");
    test_step.dependOn(&run_tests.step);
}
