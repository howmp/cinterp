# cinterp-sys

Raw FFI bindings and a small safe wrapper for the cinterp C embedding ABI.

The crate is shipped inside cinterp release tarballs under `rust/cinterp-sys`.
It expects the native library at `../../lib` and the header at `../../include`
relative to the crate directory. Override these with:

```bash
export CINTERP_LIB_DIR=/opt/cinterp/lib
export CINTERP_INCLUDE_DIR=/opt/cinterp/include
```

or add the crate as a path dependency:

```toml
[dependencies]
cinterp-sys = { path = "vendor/cinterp-sys" }
```

## Run the example

`examples/run_hello.rs` loads a package, runs an entry point and prints the
result. `--expect N` turns it into a smoke test that exits non-zero when the
result differs.

```bash
cd rust/cinterp-sys
cargo run --offline --example run_hello -- /path/to/app.cib --expect 42
# result = 42
```

The example needs the shared library at run time as well; when the library is
not installed system-wide, export the loader path first:

```bash
export LD_LIBRARY_PATH="$PWD/../../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

## Tests

```bash
cargo test --offline
```

The crate's unit tests cover the `CI_*` status names, `Error` formatting and
the ABI version reported by the native library. They link `libcinterp`, so run
them where `CINTERP_LIB_DIR` (or `../../lib`) resolves.

## API notes

- `Vm::last_error_code()` returns the stable `CI_E_*` category of the last
  failed call; `Vm::last_error()` returns its message and
  `Vm::clear_error()` resets both.
- `Error::code` is that category (`ci_vm_last_error_code`), `Error::status` is
  the negative value the failing call returned, and `Error::message` is the
  text from `ci_vm_last_error()`. `status_name(code)` maps either value to its
  `CI_*` name for logging.
- `CI_ERROR` means the runtime could not categorize the failure; every other
  failure is a specific `CI_E_*` value.

## Example code

```rust
use cinterp_sys::Vm;

let bytes = std::fs::read("app.cib").unwrap();
let mut vm = Vm::new(0).expect("create VM");
vm.load_package(&bytes).expect("load package");
let args = ["app", "--flag"];
vm.run_args("main", &args).expect("run");
println!("result = {}", vm.result());
```

One `Vm` is single-threaded. Use separate `Vm` instances for independent
execution; callback trampolines are process-wide and retired when their VM is
destroyed. See `docs/embedding.md` and `docs/compatibility.md` in the release
tarball.
