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

Every release tarball (sysv-x86_64, win64-x86_64, win32-x86, arm64) ships
`cinterp.pc`, the CMake package config and the `cinterp-sys` Rust crate. Only
the Linux x86-64 tarball also ships `bin/cinterp-cc` (its compiler can emit
packages for all four targets); the other three are runtime-only, so compile
with the Linux tarball or build the compiler from source.

### pkg-config

```bash
export PKG_CONFIG_PATH=/path/to/cinterp/pkgconfig
cc host.c $(pkg-config --cflags --libs cinterp)
# static link against libcinterp.a / cinterp_static.lib:
cc host.c $(pkg-config --static --cflags --libs cinterp)
```

`Libs.private` carries the extra system libraries needed for a static link
(`-ldl -lpthread -lm` on Unix, empty on Windows), so `--static` needs no extra
flags.

### CMake

```cmake
find_package(cinterp 0.1 REQUIRED)
target_link_libraries(host PRIVATE cinterp::cinterp)
```

The tarball installs `cinterpConfig.cmake` **and**
`cinterpConfigVersion.cmake` (both at `cmake/` and at
`lib/cmake/cinterp/`). The version file implements same-major matching: a
request up to the tarball's `VERSION` in the same major series matches, so
`find_package(cinterp 0.1 REQUIRED)` succeeds against 0.1.x while
`find_package(cinterp 1.0)` fails.

### Rust

```toml
[dependencies]
cinterp-sys = { path = "vendor/cinterp-sys" }
```

The crate exposes the raw `ci_vm_*` symbols plus a small safe `Vm` wrapper; see
`rust/cinterp-sys/README.md` in the release tarball. `Error` carries three
fields:

- `Error.code` is the category reported by `ci_vm_last_error_code()` (a
  `CI_E_*` value, or the raw status when the VM recorded no category);
- `Error.status` is the negative value the failing call returned
  (`CI_ERROR` or `CI_E_*`);
- `Error.message` is the text from `ci_vm_last_error()`.

Match on `code` for control flow and use `status` for logging. For VM-reported
failures the two currently hold the same negative value; `code` is the stable
category, while `status` records exactly what the call returned.

## Compile a package

```bash
./build/cinterp-cc compile app.c -o app.cib --target x86_64-linux
```

Use the target that matches the runtime you will load the package into.
`--dump-imports` lists the native symbols the package expects; the compiler
auto-links C standard library symbols and (on Windows) Windows APIs using the
symbol indexes it generates at build time from the Zig toolchain. Symbols the
indexes do not cover are resolved by the runtime fallback; custom libraries can
be added with `--lib` at run time.

## C API

```c
#include <stdio.h>
#include <cinterp.h>

int main(void) {
    /* package_bytes/package_size: contents of app.cib */
    ci_vm *vm = ci_vm_create(0);      /* 0 = default 8192-slot value stack */
    if (!vm) return 1;

    if (ci_vm_load_package(vm, package_bytes, package_size) != CI_OK) {
        fprintf(stderr, "load: %s (%d)\n",
                ci_vm_last_error(vm), ci_vm_last_error_code(vm));
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
    printf("result: %lld\n", (long long)value);
    ci_vm_destroy(vm);
    return 0;
}
```

`ci_vm_run`/`ci_vm_run_args` return a status; the interpreted `main` return
value is read with `ci_vm_result`. `ci_vm_run_args` takes at most 256 argv
entries.

`ci_vm_create_ex` accepts a `ci_vm_config` for forward-compatible options:
`struct_size` must cover at least `stack_size` (set it to
`sizeof(ci_vm_config)` to pass `memory_size`), and `flags` must be zero.

- `stack_size` is an upper bound in VM value slots. `0` selects the default
  **8192 slots**, which is also the maximum; values above 8192 make creation
  fail (NULL). It can only lower the stack, never raise it.
- `memory_size` is the linear memory size in bytes. `0` selects the default
  **1 MiB**, and the maximum is **16 MiB**; larger values make creation fail.

A config whose `struct_size` stops after `stack_size` is accepted and uses the
default 1 MiB memory.

```c
ci_vm_config cfg = {
    .struct_size = sizeof(cfg),
    .flags = 0,
    .stack_size = 0,           /* 0 = default 8192 slots */
    .memory_size = 256 * 1024  /* 0 = default 1 MiB */
};
ci_vm *vm = ci_vm_create_ex(&cfg);
```

The VM allocates its value stack, linear memory, module buffer and FFI plan
store per instance/package. A default VM is a VM record of roughly 0.9 MiB plus
an 8192-slot value stack (64 KiB) and 1 MiB of linear memory — about 2 MiB in
total; the former fixed ~10 MiB footprint (including a 6.5 MiB plan table) is
gone. `memory_size` can be lowered for small packages.

## Errors and ownership

- Functions return `CI_OK` or a **category-specific negative `CI_E_*` status**.
  `CI_ERROR` (-1) is only returned when the runtime cannot classify the
  failure. `ci_vm_last_error_code` returns the same category, and
  `ci_vm_last_error` returns the specific error name (for example
  `BadPackageMagic`).
- A successful `ci_vm_load_*`, `ci_vm_run`, `ci_vm_run_args` or
  `ci_vm_load_library` clears both the error text and the category.
  `ci_vm_clear_error(vm)` clears them explicitly and returns `CI_OK`.
- The text returned by `ci_vm_last_error` lives in a 128-byte buffer owned by
  the VM. The pointer stays valid until the next call on that VM that sets or
  clears the error (a failing load/run, a successful one, or
  `ci_vm_clear_error`), or until `ci_vm_destroy`. Do not free it.
  `ci_vm_last_error(NULL)` returns an empty string; `ci_vm_last_error_code(NULL)`
  returns `CI_E_INVALID_ARGUMENT`.
- `ci_version()` returns a pointer to a static string that stays valid for the
  lifetime of the process; do not free it.
- Loaders are transactional: a failed `ci_vm_load_package` leaves a previously
  loaded package intact.
- The VM copies the package bytes; the caller may free its buffer after a
  successful load.
- Native pointers produced by FFI (`malloc`, etc.) are host pointers. Packages
  are trusted build products; the runtime is not an in-process sandbox. Run
  untrusted packages in a separate process or container.

## Threads, callbacks and multiple VMs

- One VM is single-threaded. Do not call into the same VM concurrently.
- Separate VMs are independent. Callback trampolines are process-wide: a fixed
  pool of **256 slots** shared by every VM in the process.
- A slot is **retired permanently** when its owning VM is destroyed or its
  plans are reloaded, and is **never reused** (a host may still hold the
  function pointer, and reusing the slot would redirect it into a different
  VM). The pool is therefore a one-time budget of 256 callback registrations
  per process: after the pool is exhausted, `CREATE_CALLBACK` fails with
  `TooManyCallbacks` (`CI_E_RUNTIME`). Creating and destroying VMs with
  callbacks in a loop eventually exhausts it; it is not a per-VM limit.
- `ci_vm_destroy` waits for an in-flight callback to return before freeing the
  VM.
- Callbacks are supported on SysV x86-64, Win64, Win32 and AArch64. Win32
  `__stdcall` callbacks are supported (the trampoline pops the stdcall
  arguments); Win32 `__fastcall` callbacks are rejected at registration with
  `UnsupportedCallback` (`CI_E_RUNTIME`) because the i686 trampoline never sees
  the ECX/EDX arguments. HFA returns use up to four vector registers: AArch64
  HFAs of 1-4 elements return in `v0`-`v3` (including the four-register case).

## Version and compatibility

- `CI_ABI_VERSION` is currently **2**. `ci_abi_version()` returns it, and
  `ci_version()` returns the release version from the repository `VERSION`
  file. `ci_vm_clear_error()` is part of the same header/ABI.
- Package format versions, the N−1 read guarantee and the C ABI rules are
  documented in [`compatibility.md`](compatibility.md).
- `CI_ABI_VERSION` and the shared-library SONAME major are independent
  numbers; check `ci_abi_version()` rather than inferring compatibility from
  the `.so` file name. See `compatibility.md` for the SONAME policy.
