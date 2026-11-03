const std = @import("std");

fn readVersion(b: *std.Build) []const u8 {
    const path = b.pathFromRoot("../VERSION");
    const text = std.fs.cwd().readFileAlloc(b.allocator, path, 1024) catch
        @panic("missing VERSION next to compiler/ (or pass -Dversion)");
    return std.mem.trim(u8, text, " \t\r\n");
}

/// Build the host-side link-index generator and run it for both metadata
/// sources. The outputs are a compact `.bin` plus a wrapper module that
/// `@embedFile`s it; `addLinkIndexes` injects those wrappers as anonymous
/// imports so `src/win_defs.zig` / `src/libc_defs.zig` can read them.
const LinkIndexes = struct {
    win_zig: std.Build.LazyPath,
    libc_zig: std.Build.LazyPath,
};

fn generateLinkIndexes(b: *std.Build) LinkIndexes {
    const generator = b.addExecutable(.{
        .name = "gen-link-index",
        .root_source_file = b.path("tools/gen_link_index.zig"),
        .target = b.host,
        .optimize = .ReleaseSafe,
    });
    const format_module = b.createModule(.{ .root_source_file = b.path("src/link_index.zig") });
    generator.root_module.addImport("link_index", format_module);

    const win_run = b.addRunArtifact(generator);
    win_run.addArg("win");
    win_run.addArg(b.graph.zig_exe);
    _ = win_run.addOutputFileArg("win_defs.bin");
    const win_zig = win_run.addOutputFileArg("win_defs_generated.zig");

    const libc_run = b.addRunArtifact(generator);
    libc_run.addArg("libc");
    libc_run.addArg(b.graph.zig_exe);
    _ = libc_run.addOutputFileArg("libc_defs.bin");
    const libc_zig = libc_run.addOutputFileArg("libc_defs_generated.zig");

    // `zig build gen-link-index` regenerates and validates both tables without
    // building the compiler; the generator prints entry/library/blob sizes.
    const gen_step = b.step("gen-link-index", "Generate the MinGW/glibc external-symbol link indexes");
    gen_step.dependOn(&win_run.step);
    gen_step.dependOn(&libc_run.step);

    return .{ .win_zig = win_zig, .libc_zig = libc_zig };
}

fn addLinkIndexes(indexes: LinkIndexes, module: *std.Build.Module) void {
    module.addAnonymousImport("win_defs_generated", .{ .root_source_file = indexes.win_zig });
    module.addAnonymousImport("libc_defs_generated", .{ .root_source_file = indexes.libc_zig });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "override the package version from VERSION") orelse
        readVersion(b);
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const indexes = generateLinkIndexes(b);

    const exe = b.addExecutable(.{
        .name = "cinterp-cc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_options", options);
    addLinkIndexes(indexes, &exe.root_module);
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
    addLinkIndexes(indexes, &tests.root_module);
    const run_tests = b.addRunArtifact(tests);

    const imports_tests = b.addTest(.{
        .root_source_file = b.path("src/imports.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_imports_tests = b.addRunArtifact(imports_tests);

    const link_index_tests = b.addTest(.{
        .root_source_file = b.path("src/link_index.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_link_index_tests = b.addRunArtifact(link_index_tests);

    const link_wrappers_tests = b.addTest(.{
        .root_source_file = b.path("src/link_wrappers.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_link_wrappers_tests = b.addRunArtifact(link_wrappers_tests);

    const win_defs_tests = b.addTest(.{
        .root_source_file = b.path("src/win_defs.zig"),
        .target = target,
        .optimize = optimize,
    });
    win_defs_tests.root_module.addAnonymousImport("win_defs_generated", .{ .root_source_file = indexes.win_zig });
    const run_win_defs_tests = b.addRunArtifact(win_defs_tests);

    const libc_defs_tests = b.addTest(.{
        .root_source_file = b.path("src/libc_defs.zig"),
        .target = target,
        .optimize = optimize,
    });
    libc_defs_tests.root_module.addAnonymousImport("libc_defs_generated", .{ .root_source_file = indexes.libc_zig });
    const run_libc_defs_tests = b.addRunArtifact(libc_defs_tests);

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

    const test_step = b.step("test", "Run compiler unit tests (main, abi, ir, lower_ast, imports, link_index, link_wrappers, win_defs, libc_defs)");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_imports_tests.step);
    test_step.dependOn(&run_link_index_tests.step);
    test_step.dependOn(&run_link_wrappers_tests.step);
    test_step.dependOn(&run_win_defs_tests.step);
    test_step.dependOn(&run_libc_defs_tests.step);
    test_step.dependOn(&run_ir_tests.step);
    test_step.dependOn(&run_abi_tests.step);
    test_step.dependOn(&run_lower_ast_tests.step);

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
