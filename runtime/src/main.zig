const std = @import("std");
const vm = @import("vm.zig");
const build_options = @import("build_options");

/// Largest C argv a run can carry: `ci_vm_run_args` accepts at most 256
/// entries and argv[0] (the package path) is one of them.
const max_args = 256;

const usage =
    \\usage: cinterp-run [--lib path]... [--load-only] [--dump-target] [--dump-imports]
    \\                   [--repeat n] [--entry name] [--jobs n] <package.cib> [entry] [-- arg...]
    \\       cinterp-run [--lib path]... [--load-only] [--dump-target] [--dump-imports]
    \\                   [--repeat n] [--entry name] [--jobs n] --run-all <package.cib>... [-- arg...]
    \\
    \\  --lib path      add a native library search handle to every loaded VM
    \\  --load-only     load and validate every package, run nothing
    \\  --dump-target   print the target of every loaded package
    \\  --dump-imports  print the import plans of every loaded package
    \\  --repeat n      run every package n times (n >= 1) from one VM, fresh image
    \\  --entry name    entry point for every package and every run (default: main)
    \\  --jobs n        run packages on n worker threads (n >= 1, default 1)
    \\  --run-all       every positional before -- is a package (no implicit mode)
    \\  -- arg...       arguments passed to every run; argv[0] stays the package path
    \\
    \\A single package run once keeps the legacy output: exactly one `result: <i32>`
    \\line. Multi-package or repeated runs print `package: <path> run: <i>/<n>` before
    \\each run and then the same `result:` line. Every run starts from a fresh image,
    \\and the C `main` return value is reported through `result:` - it is not the
    \\process exit status (0 success, 1 load/run failure, 2 usage/I/O).
    \\
    \\With --jobs n > 1 each package (and its VM) belongs to exactly one worker
    \\thread, so a VM is never run by two threads; the order of the `package:`/`result:`
    \\lines is not deterministic and the packages' own stdout/stderr may interleave.
    \\atexit/signal handlers stay process-global, and all VMs stay alive until exit.
    \\
;

const Job = struct {
    path: [:0]const u8,
    machine: *vm.VM,
};

const Runner = struct {
    targets: []const Job,
    entry: [*:0]const u8,
    /// Arguments after `--`; the package path is prepended as argv[0] per run.
    tail: []const [*:0]const u8,
    repeat: usize,
    multi: bool,
    /// Shared work queue over `targets`; a VM is only ever run by the thread that
    /// claimed it, which is what keeps one VM off two threads.
    next: std.atomic.Value(usize),
    failed: std.atomic.Value(bool),

    fn runPackage(self: *Runner, index: usize) bool {
        const job = self.targets[index];
        const argc = self.tail.len + 1;
        var argv_buf: [max_args]?[*:0]const u8 = undefined;
        argv_buf[0] = job.path.ptr;
        for (self.tail, 0..) |arg, k| argv_buf[k + 1] = arg;

        var done: usize = 0;
        while (done < self.repeat) : (done += 1) {
            if (self.multi) {
                std.debug.print("package: {s} run: {d}/{d}\n", .{ job.path, done + 1, self.repeat });
            }
            if (vm.ci_vm_run_args(job.machine, self.entry, @intCast(argc), argv_buf[0..argc].ptr) != 0) {
                std.debug.print("cinterp-run: run failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(job.machine))});
                return false;
            }
            std.debug.print("result: {d}\n", .{@as(i32, @truncate(vm.ci_vm_result(job.machine)))});
        }
        return true;
    }

    /// Pull packages off the shared queue until it is empty. Safe to call from
    /// worker threads and from the main thread: failures are only recorded, so
    /// a worker never terminates the process out from under the other workers.
    fn work(self: *Runner) void {
        while (true) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.targets.len) return;
            if (!self.runPackage(index)) self.failed.store(true, .monotonic);
        }
    }
};

fn usageFail(comptime fmt: []const u8, fmt_args: anytype) noreturn {
    std.debug.print("cinterp-run: " ++ fmt ++ "\n", fmt_args);
    std.debug.print("{s}", .{usage});
    std.process.exit(2);
}

fn outOfMemory() noreturn {
    std.debug.print("cinterp-run: out of memory\n", .{});
    std.process.exit(2);
}

/// `--repeat`/`--jobs` value: a decimal integer >= 1.
fn countValue(args: []const [:0]u8, i: *usize, flag: []const u8) usize {
    if (i.* + 1 >= args.len) usageFail("{s} requires a value", .{flag});
    const text: []const u8 = args[i.* + 1];
    const value = std.fmt.parseUnsigned(usize, text, 10) catch
        usageFail("{s} requires an integer >= 1, got '{s}'", .{ flag, text });
    if (value < 1) usageFail("{s} requires an integer >= 1, got '{s}'", .{ flag, text });
    i.* += 2;
    return value;
}

fn dumpPackage(job: Job, dump_target: bool, dump_imports: bool, header: bool) void {
    if (header) std.debug.print("package: {s}\n", .{job.path});
    if (dump_target) {
        if (job.machine.target) |t| {
            std.debug.print("target: {s} arch={d} os={d} abi={d} ptr={d} endian={d} features=0x{x} link_db={s}\n", .{
                t.triple[0..t.triple_len], t.arch, t.os, t.abi, t.ptr_bits, t.endian, t.features, t.link_db[0..t.link_db_len],
            });
        } else {
            std.debug.print("target: legacy-v1 (inferred)\n", .{});
        }
    }
    if (dump_imports) {
        var ii: usize = 0;
        while (ii < job.machine.imports.count) : (ii += 1) {
            const e = &job.machine.imports.entries[ii];
            std.debug.print("import[plan {d}] {s}:", .{ e.plan_index, e.name[0..e.name_len] });
            var pi: usize = 0;
            while (pi < e.provider_count) : (pi += 1) {
                const pr = &e.providers[pi];
                std.debug.print(" {s}:{s}", .{ pr.name[0..pr.name_len], pr.symbol[0..pr.symbol_len] });
            }
            std.debug.print("\n", .{});
        }
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var load_only = false;
    var dump_target = false;
    var dump_imports = false;
    var run_all = false;
    var repeat: usize = 1;
    var jobs: usize = 1;
    var chosen_entry: ?[*:0]const u8 = null;
    var packages = std.ArrayList([:0]const u8).init(allocator);
    var libs = std.ArrayList([:0]const u8).init(allocator);
    var tail = std.ArrayList([*:0]const u8).init(allocator);

    // Option and `--lib` prefix, exactly where the legacy grammar allowed them.
    // An unknown flag still falls through to the package slot, as before.
    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--version")) {
            std.debug.print("cinterp-run {s}\n", .{build_options.version});
            return;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            std.debug.print("{s}", .{usage});
            return;
        }
        if (std.mem.eql(u8, arg, "--load-only")) {
            load_only = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--dump-target")) {
            dump_target = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--dump-imports")) {
            dump_imports = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--run-all")) {
            run_all = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--repeat")) {
            repeat = countValue(args, &i, "--repeat");
            continue;
        }
        if (std.mem.eql(u8, arg, "--jobs")) {
            jobs = countValue(args, &i, "--jobs");
            continue;
        }
        if (std.mem.eql(u8, arg, "--entry")) {
            if (i + 1 >= args.len) usageFail("--entry requires a name", .{});
            chosen_entry = args[i + 1].ptr;
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--lib")) {
            if (i + 1 >= args.len) usageFail("--lib requires a path", .{});
            libs.append(args[i + 1]) catch outOfMemory();
            i += 2;
            continue;
        }
        break;
    }

    // Positionals up to `--`; everything after `--` is C argv for every run.
    while (i < args.len and !std.mem.eql(u8, args[i], "--")) : (i += 1) {
        packages.append(args[i]) catch outOfMemory();
    }
    if (i < args.len) i += 1;
    while (i < args.len) : (i += 1) tail.append(args[i].ptr) catch outOfMemory();

    if (packages.items.len == 0) usageFail("missing package", .{});
    if (tail.items.len + 1 > max_args) usageFail("too many arguments after --", .{});

    // Legacy grammar: `<package.cib> [entry]`. `--run-all` is the only way to
    // name more than one package, so `cinterp-run a.cib b.cib` still means
    // "package a.cib, entry b".
    var entry: [*:0]const u8 = "main";
    if (!run_all) {
        if (packages.items.len > 2) {
            usageFail("unexpected extra argument; use --run-all to run multiple packages", .{});
        }
        if (packages.items.len == 2) {
            if (chosen_entry != null) usageFail("a positional entry and --entry are mutually exclusive", .{});
            entry = packages.items[1].ptr;
        }
    }
    if (chosen_entry) |name| entry = name;

    // Without --run-all the second positional is the entry point, not a
    // package, so only the first positional is loaded.
    const package_paths = if (run_all) packages.items else packages.items[0..1];

    // Multi/repeat gets a per-run header; a single package run once keeps the
    // legacy bare `result:` output.
    const multi = run_all or repeat > 1;

    const process = vm.ci_process_create(null) orelse outOfMemory();

    // Load every package before running anything: load errors are then
    // deterministic in package order regardless of --jobs, and --load-only
    // validates the whole set instead of stopping at the first bad package.
    var runs = std.ArrayList(Job).init(allocator);
    var load_failed = false;
    for (package_paths) |path| {
        const bytes = std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024) catch |err| {
            std.debug.print("cinterp-run: cannot read {s}: {s}\n", .{ path, @errorName(err) });
            std.process.exit(2);
        };
        var machine_opt: ?*vm.VM = null;
        const status = vm.ci_process_load_package(process, bytes.ptr, bytes.len, &machine_opt);
        allocator.free(bytes);
        if (status != 0) {
            std.debug.print("cinterp-run: load failed: {s}\n", .{std.mem.span(vm.ci_process_last_error(process))});
            if (!multi) std.process.exit(1);
            load_failed = true;
            continue;
        }
        const machine = machine_opt.?;
        var lib_failed = false;
        for (libs.items) |lib| {
            if (vm.ci_vm_load_library(machine, lib.ptr) != 0) {
                std.debug.print("cinterp-run: load library failed: {s}\n", .{std.mem.span(vm.ci_vm_last_error(machine))});
                if (!multi) std.process.exit(1);
                load_failed = true;
                lib_failed = true;
                break;
            }
        }
        if (lib_failed) continue;
        runs.append(.{ .path = path, .machine = machine }) catch outOfMemory();
    }
    if (load_failed) std.process.exit(1);

    if (dump_target or dump_imports) {
        for (runs.items) |job| dumpPackage(job, dump_target, dump_imports, multi);
    }
    // ci_process_destroy is deliberately never called: a CIB may have registered
    // a libc atexit handler that still has to run against its VM, so the process
    // and its VMs stay alive until the final libc exit (they only leak into the
    // kernel at that point).
    if (load_only) std.c.exit(0);

    var runner = Runner{
        .targets = runs.items,
        .entry = entry,
        .tail = tail.items,
        .repeat = repeat,
        .multi = multi,
        .next = std.atomic.Value(usize).init(0),
        .failed = std.atomic.Value(bool).init(false),
    };
    const worker_count = @min(jobs, runs.items.len);
    if (worker_count <= 1) {
        // Default path: one thread, packages in command-line order.
        var index: usize = 0;
        while (index < runs.items.len) : (index += 1) {
            if (!runner.runPackage(index)) runner.failed.store(true, .monotonic);
        }
    } else {
        var threads: [vm.MAX_PROCESS_VMS]std.Thread = undefined;
        var started: usize = 0;
        while (started < worker_count) : (started += 1) {
            threads[started] = std.Thread.spawn(.{}, Runner.work, .{&runner}) catch break;
        }
        // If the host refused a thread, drain the queue here as well; the
        // shared counter keeps each VM on exactly one thread either way.
        if (started < worker_count) runner.work();
        for (threads[0..started]) |thread| thread.join();
    }
    // A failed run must not call std.process.exit off a worker thread, so the
    // main thread owns the final status.
    if (runner.failed.load(.monotonic)) std.process.exit(1);
    // Keep every VM alive while libc runs ordinary atexit handlers.
    std.c.exit(0);
}
