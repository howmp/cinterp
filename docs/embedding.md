# Embedding cinterp in a host application

`libcinterp` executes packages produced ahead of time by the `cinterp`
compiler. The runtime is a small Zig library with a plain C ABI; it does not
need clang, Python or executable memory at run time.

## Build and install

```bash
# release runtime + static/shared libraries + header (Linux x64 example)
cd runtime
zig build -Doptimize=ReleaseSmall
# zig-out/include/cinterp.h
# zig-out/lib/libcinterp.a
# zig-out/lib/libcinterp.so -> libcinterp.so.0 -> libcinterp.so.0.1.0
```

Other targets use Zig's cross compilation:

```bash
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall
zig build -Dtarget=x86-windows-gnu -Doptimize=ReleaseSmall
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSmall
```

The release tarball also ships `cinterp.pc`, a CMake package config and the
`cinterp-sys` Rust crate.

### pkg-config

```bash
cc host.c $(pkg-config --cflags --libs cinterp)
```

### CMake

```cmake
find_package(cinterp CONFIG REQUIRED)
target_link_libraries(host PRIVATE cinterp::cinterp)
```

### Rust

```toml
[dependencies]
cinterp-sys = { path = "vendor/cinterp-sys" }
```

The crate exposes the raw `ci_vm_*` symbols plus a small safe wrapper; see
`rust/cinterp-sys/README.md` in the release tarball.

## Compile a package

```bash
./build/cinterp-cc compile app.c -o app.cib --target x86_64-linux
```

Use the target that matches the runtime you will load the package into.
`--dump-imports` lists the native symbols the package expects; the compiler
auto-links C standard library symbols and (on Windows) documented Windows
APIs. Custom libraries can be added with `--lib` at run time.

## C API

```c
#include <cinterp.h>

ci_vm *vm = ci_vm_create(0);          /* 0 = default value-stack limit */
if (!vm) return 1;

if (ci_vm_load_package(vm, package_bytes, package_size) != CI_OK) {
    fprintf(stderr, "load: %s\n", ci_vm_last_error(vm));
    ci_vm_destroy(vm);
    return 1;
}

const char *argv[] = { "app", "--flag" };
if (ci_vm_run_args(vm, "main", 2, argv) != CI_OK) {
    fprintf(stderr, "run: %s\n", ci_vm_last_error(vm));
    ci_vm_destroy(vm);
    return 1;
}

int64_t value = ci_vm_result(vm);
ci_vm_destroy(vm);
```

`ci_vm_run`/`ci_vm_run_args` return a status; the interpreted `main` return
value is read with `ci_vm_result`. `ci_vm_create_ex` accepts a
`ci_vm_config` for forward-compatible options; `struct_size` must be
`sizeof(ci_vm_config)` and reserved flags must be zero. `stack_size` bounds the
VM value stack (0 = default 8192 slots); `memory_size` sets the linear memory
in bytes (0 = default 1 MiB, maximum 16 MiB). A config whose `struct_size`
stops after `stack_size` is accepted and uses the default memory size.

```c
ci_vm_config cfg = { sizeof(cfg), 0, 0, 256 * 1024 };
ci_vm *vm = ci_vm_create_ex(&cfg);
```

The VM allocates its value stack, linear memory, module buffer and FFI plan
store per instance/package, so an idle VM costs roughly 0.9 MiB instead of the
former ~10 MiB fixed footprint.

## Errors and ownership

- Functions return `CI_OK` or a negative `CI_E_*` status. The last error text
  and category are available through `ci_vm_last_error` and
  `ci_vm_last_error_code`.
- Loaders are transactional: a failed `ci_vm_load_package` leaves a previously
  loaded package intact.
- The VM copies the package bytes; the caller may free its buffer after a
  successful load.
- C strings returned by `ci_vm_last_error`/`ci_version` are owned by the
  library and remain valid until the next failing operation or VM destruction.
- Native pointers produced by FFI (`malloc`, etc.) are host pointers. Packages
  are trusted build products; the runtime is not an in-process sandbox. Run
  untrusted packages in a separate process or container.

## Threads, callbacks and multiple VMs

- One VM is single-threaded. Do not call into the same VM concurrently.
- Separate VMs are independent. Callback trampolines are process-wide; when a
  VM is destroyed its trampolines are retired permanently, so a host function
  pointer retained past VM destruction will not dispatch into recycled state.
- The runtime supports callbacks on SysV x86-64, Win64, Win32 and AArch64
  (up to two return vectors for HFA callbacks).

## Version and compatibility

The ABI version is `CI_ABI_VERSION` (currently 2). Package format versions,
the N−1 read guarantee and the C ABI rules are documented in
[`compatibility.md`](compatibility.md). `ci_version()` returns the release
version from the repository `VERSION` file.
