const std = @import("std");

fn addBackend(compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const t = target.result;
    if (t.os.tag == .windows and t.cpu.arch == .x86_64) {
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/call_x86_64_win64.S"));
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/callbacks_x86_64_win64.S"));
    } else if (t.os.tag == .windows and t.cpu.arch == .x86) {
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/call_x86_win32.S"));
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/callbacks_x86_win32.S"));
    } else if (t.cpu.arch == .aarch64) {
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/call_arm64_aapcs.S"));
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/callbacks_arm64_aapcs.S"));
    } else {
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/call_x86_64_sysv.S"));
        compile.addAssemblyFile(compile.step.owner.path("src/ffi/asm/callbacks_x86_64_sysv.S"));
    }
    const release = optimize == .ReleaseSmall or optimize == .ReleaseFast;
    compile.root_module.unwind_tables = !release;
    compile.root_module.error_tracing = !release;
    compile.root_module.omit_frame_pointer = release;
    compile.root_module.strip = release;
    compile.linkLibC();
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cinterp-run",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addBackend(exe, target, optimize);
    b.installArtifact(exe);

    const static_lib = b.addStaticLibrary(.{
        .name = if (target.result.os.tag == .windows) "cinterp_static" else "cinterp",
        .root_source_file = b.path("src/vm.zig"),
        .target = target,
        .optimize = optimize,
    });
    addBackend(static_lib, target, optimize);
    static_lib.root_module.stack_check = false;
    b.installArtifact(static_lib);

    const shared_lib = b.addSharedLibrary(.{
        .name = "cinterp",
        .root_source_file = b.path("src/vm.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    addBackend(shared_lib, target, optimize);
    shared_lib.root_module.stack_check = false;
    b.installArtifact(shared_lib);

    const install_header = b.addInstallHeaderFile(b.path("include/cinterp.h"), "cinterp.h");
    b.getInstallStep().dependOn(&install_header.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run cinterp-run <package.cib>");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/vm_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    addBackend(tests, target, optimize);
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run runtime unit tests");
    test_step.dependOn(&run_tests.step);
}
