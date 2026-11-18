const std = @import("std");

fn readVersion(b: *std.Build) []const u8 {
    if (b.option([]const u8, "version", "override the package version from VERSION")) |value| {
        return value;
    }
    const path = b.pathFromRoot("../../VERSION");
    const data = std.fs.cwd().readFileAlloc(b.allocator, path, 64) catch
        @panic("missing VERSION at the repository root (or pass -Dversion)");
    return std.mem.trim(u8, data, " \t\r\n");
}

fn addBackend(b: *std.Build, compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const t = target.result;
    if (t.os.tag == .windows and t.cpu.arch == .x86_64) {
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/call_x86_64_win64.S"));
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/callbacks_x86_64_win64.S"));
    } else if (t.os.tag == .windows and t.cpu.arch == .x86) {
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/call_x86_win32.S"));
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/callbacks_x86_win32.S"));
    } else if (t.cpu.arch == .aarch64) {
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/call_arm64_aapcs.S"));
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/callbacks_arm64_aapcs.S"));
    } else {
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/call_x86_64_sysv.S"));
        compile.addAssemblyFile(b.path("../../runtime/src/ffi/asm/callbacks_x86_64_sysv.S"));
    }
}

fn trimModule(module: *std.Build.Module, optimize: std.builtin.OptimizeMode) void {
    const release = optimize == .ReleaseSmall or optimize == .ReleaseFast;
    module.unwind_tables = !release;
    module.error_tracing = !release;
    module.omit_frame_pointer = release;
    module.strip = release;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const cib_path = b.option([]const u8, "cib", "path to the CIB package to embed") orelse
        @panic("pass -Dcib=<package.cib>");

    const version = readVersion(b);
    const options = b.addOptions();
    const version_z = b.allocator.dupeZ(u8, version) catch @panic("out of memory");
    options.addOption([:0]const u8, "version", version_z);

    const vm_module = b.createModule(.{
        .root_source_file = b.path("../../runtime/src/vm.zig"),
        .target = target,
        .optimize = optimize,
    });
    vm_module.addOptions("build_options", options);
    vm_module.stack_check = false;
    trimModule(vm_module, optimize);

    const write_files = b.addWriteFiles();
    _ = write_files.addCopyFile(b.path(cib_path), "keygenme.cib");
    const embedded_cib = write_files.add("embed.zig", "pub const bytes = @embedFile(\"keygenme.cib\");\n");

    const exe = b.addExecutable(.{
        .name = "keygenme",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vm", vm_module);
    exe.root_module.addAnonymousImport("cib", .{ .root_source_file = embedded_cib });
    addBackend(b, exe, target);
    trimModule(&exe.root_module, optimize);
    if (target.result.os.tag != .windows) exe.linkLibC();
    b.installArtifact(exe);
}
