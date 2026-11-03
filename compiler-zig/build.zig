const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cinterp-cc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
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
    const run_tests = b.addRunArtifact(tests);

    const ir_tests = b.addTest(.{
        .root_source_file = b.path("src/ir/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_ir_tests = b.addRunArtifact(ir_tests);

    // Lowering tests: AST lowering must reproduce the legacy text path
    // byte-for-byte (src/lower_ast.zig embeds the `.ll` fixtures under
    // src/testdata/lower_ast and src/ir/testdata).
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

    const test_step = b.step("test", "Run compiler-zig unit tests (including src/ir and src/lower_ast)");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_ir_tests.step);
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
