const std = @import("std");

fn readVersion(b: *std.Build) []const u8 {
    const path = b.pathFromRoot("../VERSION");
    const text = std.fs.cwd().readFileAlloc(b.allocator, path, 1024) catch
        @panic("missing VERSION next to compiler-zig/ (or pass -Dversion)");
    return std.mem.trim(u8, text, " \t\r\n");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "override the package version from VERSION") orelse
        readVersion(b);
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "cinterp-cc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_options", options);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run cinterp-cc");
    run_step.dependOn(&run_cmd.step);

    // Compiler tests (main.zig) and the LLVM IR frontend tests (src/ir).
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addOptions("build_options", options);
    const run_tests = b.addRunArtifact(tests);

    const imports_tests = b.addTest(.{
        .root_source_file = b.path("src/imports.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_imports_tests = b.addRunArtifact(imports_tests);

    const cstdapi_tests = b.addTest(.{
        .root_source_file = b.path("src/cstdapi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_cstdapi_tests = b.addRunArtifact(cstdapi_tests);

    const ir_tests = b.addTest(.{
        .root_source_file = b.path("src/ir/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_ir_tests = b.addRunArtifact(ir_tests);

    // ABI plan unit tests (src/abi.zig) plus the AST lowering tests. The
    // lowering tests compare emitted CIVM/CIPL against embedded golden files
    // under src/testdata/lower_ast/golden; the `.ll` fixtures live under
    // src/testdata/lower_ast and src/ir/testdata.
    const abi_tests = b.addTest(.{
        .root_source_file = b.path("src/abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_abi_tests = b.addRunArtifact(abi_tests);

    const lower_ast_tests = b.addTest(.{
        .root_source_file = b.path("src/lower_ast.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lower_ast_tests = b.addRunArtifact(lower_ast_tests);

    const winmd_tests = b.addTest(.{
        .root_source_file = b.path("src/winmd.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_winmd_tests = b.addRunArtifact(winmd_tests);

    const test_step = b.step("test", "Run compiler-zig unit tests (including src/abi, src/ir, src/lower_ast, src/cstdapi and src/imports)");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_imports_tests.step);
    test_step.dependOn(&run_cstdapi_tests.step);
    test_step.dependOn(&run_ir_tests.step);
    test_step.dependOn(&run_abi_tests.step);
    test_step.dependOn(&run_lower_ast_tests.step);
    test_step.dependOn(&run_winmd_tests.step);

    // `zig build ir-dump -- <file.ll>`: structural dump of the typed IR AST.
    // Debug aid for the lowering port; not installed.
    const ir_dump = b.addExecutable(.{
        .name = "ir-dump",
        .root_source_file = b.path("src/ir/dump.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ir_dump_run = b.addRunArtifact(ir_dump);
    if (b.args) |args| ir_dump_run.addArgs(args);
    const ir_dump_step = b.step("ir-dump", "Parse a .ll file and dump the typed AST");
    ir_dump_step.dependOn(&ir_dump_run.step);
}
