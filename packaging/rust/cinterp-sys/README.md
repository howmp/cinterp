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

## Example

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
